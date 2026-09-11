/// The rhythm pillar's practice screen: the hand's motion, the notation, and
/// what the microphone can honestly confirm.
///
/// Design: `docs/superpowers/specs/2026-09-11-gamified-curriculum-design.md` §3.
/// Research: `docs/research/visual-rhythm-cues-2026-09.md`.
///
/// ## What this screen claims, and what it does NOT
///
/// It shows the chord state live: the chord lane and the fingering dots go green
/// only while the recogniser CONFIRMS the chord that was asked for (§2 rules 1
/// and 2), amber when it confirms a different one, and neutral otherwise —
/// neutral being "I cannot tell", never "you failed".
///
/// ## The clock, and why timing can be scored
///
/// MEASURED (`test/features/live/strum_timestamp_latency_test.dart`), by driving
/// the real `LivePipeline` with synthetic strums at known times:
///
///   - `latestStrumTime` is the stroke's TRUE onset on the engine's sample
///     clock — placement error 0.0-3.4 ms across four strums.
///   - the frame CARRYING it arrives 84-142 ms later, independently reproducing
///     the 85-165 ms the `LiveFrame` doc comment cites from r145.
///
/// Those two differ by a factor of about 42, which is the whole design
/// constraint: timestamping a stroke when its frame arrives would import the
/// second number as false lateness, and 142 ms against a 50 ms window means
/// every stroke would read as late. So a stroke is placed at `latestStrumTime`,
/// and the exercise grid runs on the SAME engine clock rather than on a clock of
/// its own — an offset that does not exist cannot be miscalibrated.
///
/// The ticker remains, but only to interpolate BETWEEN engine anchors so the
/// pendulum moves at frame rate instead of the engine's ~66 ms cadence. The
/// visual interpolates; the grading never does.
///
/// Still NOT corrected here, and named: the learner hears the count through the
/// speaker and is heard through the microphone, so their perception carries this
/// device's output+input latency. `LatencyCalibrator` already measures that (tap
/// test, median, MAD-gated); applying it is the next step, and until then the
/// score is of what the microphone heard, not of what the learner felt.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/public.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../chords/public.dart';
import '../../../live/public.dart';
import '../../data/beginner_course.dart';
import '../../domain/course.dart';
import '../../domain/rhythm_assignment.dart';
import '../../domain/rhythm_grading.dart';
import '../../domain/rhythm_grid.dart';
import '../../domain/rhythm_mode.dart';
import '../widgets/rhythm_lane.dart';

/// Reads the screen's own playback position for the design system's clock port.
///
/// A pull-style getter, not a stream: `SsBeatClock` is polled once per frame by
/// design, so a stopped clock is simply a null read.
final class _PlaybackClock implements SsBeatClock {
  _PlaybackClock(this._read);
  final Duration? Function() _read;
  @override
  Duration? get position => _read();
}

final class RhythmPracticeScreen extends ConsumerStatefulWidget {
  const RhythmPracticeScreen({super.key, this.mission});

  /// The rung to practise. Defaults to the shipped pattern rung so the route
  /// works on its own.
  final CurriculumMission? mission;

  @override
  ConsumerState<RhythmPracticeScreen> createState() =>
      _RhythmPracticeScreenState();
}

final class _RhythmPracticeScreenState
    extends ConsumerState<RhythmPracticeScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final _PlaybackClock _clock;
  late final RhythmAssignment _assignment;

  /// The chords this exercise cycles, one per bar. Empty for a damped rung.
  late final List<String> _chords;

  Duration? _position;
  bool _playing = false;

  /// The ticker's own elapsed time. Used ONLY to interpolate between engine
  /// anchors so the pendulum runs at frame rate — never as the timeline itself.
  ///
  /// Deliberately NOT `SchedulerBinding.currentFrameTimeStamp`: that is valid
  /// only inside a frame, so reading it from a tap handler asserts.
  Duration _tickerElapsed = Duration.zero;

  /// The engine clock reading at the exercise's start. Null until the engine has
  /// produced a frame — which is also when playback can begin, because without
  /// the engine there is no shared clock and so nothing that could be scored.
  double? _startEngineSec;

  /// The newest engine clock reading, and the ticker time it arrived at.
  double? _engineNowSec;
  Duration _engineAnchorTick = Duration.zero;

  /// Strokes heard this run, placed on the engine clock.
  final List<DetectedStroke> _strokes = [];
  int _lastStrumSeq = 0;

  @override
  void initState() {
    super.initState();
    final course = beginnerCourse();
    // The no-argument route is a direct entry point, not a teaching decision:
    // it opens the richest rung (the one with a chord) so the whole surface is
    // reachable. The real flow always passes the learner's own mission.
    final mission =
        widget.mission ??
        course.missionsInOrder.firstWhere(
          (candidate) => candidate.rhythm?.mode.scoresChord ?? false,
          orElse: () => course.missionsInOrder.firstWhere(
            (candidate) => candidate.rhythm != null,
            orElse: () => course.missionsInOrder.first,
          ),
        );
    _assignment =
        mission.rhythm ??
        RhythmAssignment(
          mode: RhythmMode.mutedStrokes,
          grid: RhythmGrid.pendulum(
            subdivision: RhythmSubdivision.quarter,
            struck: const [true, true, true, true],
            muted: true,
          ),
          bpm: beginnerQuarterBpm,
          bars: beginnerBarsPerAttempt,
        );
    // A damped rung has no chord to name, so the lane says so instead of
    // showing a shape the learner is not meant to fret.
    _chords = _assignment.mode.scoresChord
        ? const ['Em', 'Am']
        : const <String>[];
    _clock = _PlaybackClock(() => _position);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    _tickerElapsed = elapsed;
    if (!_playing) return;
    final start = _startEngineSec;
    final engineNow = _engineNowSec;
    if (start == null || engineNow == null) return;
    // Interpolate forward from the last engine anchor: the anchor is the truth,
    // the ticker only fills the ~66 ms gaps so the motion is smooth. Derived
    // from the anchor every frame, never accumulated (ADR 0274).
    setState(() {
      _position =
          Duration(microseconds: ((engineNow - start) * 1e6).round()) +
          (elapsed - _engineAnchorTick);
    });
  }

  void _toggle() {
    setState(() {
      if (_playing) {
        _playing = false;
        return;
      }
      // Starting anchors the exercise to the engine clock's current reading, so
      // the grid and every detected stroke share one scale from the first bar.
      _startEngineSec = _engineNowSec;
      _position = Duration.zero;
      _strokes.clear();
      _playing = true;
    });
  }

  /// Folds a freshly arrived frame into the clock anchor and the stroke list.
  ///
  /// A stroke is placed at `latestStrumTime` — the MEASURED true onset — never
  /// at the moment this frame arrived, which the same measurement puts 84-142 ms
  /// later.
  void _absorb(LiveFrame? live) {
    if (live == null || live.engineTimeSec < 0) return;
    _engineNowSec = live.engineTimeSec;
    _engineAnchorTick = _tickerElapsed;

    final start = _startEngineSec;
    if (!_playing || start == null) return;
    if (live.strumSeq <= _lastStrumSeq) return;
    _lastStrumSeq = live.strumSeq;
    final strum = live.latestStrum;
    if (strum == null || live.latestStrumTime < 0) return;
    _strokes.add(
      DetectedStroke(
        atUs: ((live.latestStrumTime - start) * 1e6).round(),
        direction: strum.direction,
        // The pipeline publishes a strum only once its DIRECTION is confirmed,
        // so a stroke reaching here is confirmed evidence by construction.
        isConfirmed: true,
      ),
    );
  }

  /// Crossings per loop: two per beat, across however many bars the exercise
  /// repeats, with the chord cycle laid over them.
  List<bool> get _crossings {
    final perBar = _assignment.grid.handCrossings;
    final bars = _chords.isEmpty ? 1 : _chords.length;
    return [for (var bar = 0; bar < bars; bar++) ...perBar];
  }

  Duration get _beatDuration =>
      Duration(microseconds: (60000000 / _assignment.bpm).round());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final frame = ref.watch(liveFrameProvider);
    final live = frame.asData?.value;
    _absorb(live);

    final crossings = _crossings;
    final pendulum = _position == null
        ? null
        : SsStrumPendulum.frameAt(
            position: _position!,
            beatDuration: _beatDuration,
            struck: crossings,
          );
    final perBar = _assignment.grid.handCrossings.length;
    final barIndex = pendulum == null
        ? 0
        : (pendulum.crossingIndex ~/ perBar) %
              (_chords.isEmpty ? 1 : _chords.length);
    final askedChord = _chords.isEmpty ? null : _chords[barIndex];
    final fretting = _frettingFor(live, askedChord);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.curriculumRhythmTitle)),
      // The transport sits OUTSIDE the scroll view on purpose: a practice
      // screen's play control must be reachable without scrolling, and a widget
      // test caught it sitting below the fold at phone height.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SsSpacing.space3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _toggle,
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                label: Text('${_assignment.bpm.round()} BPM'),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(SsSpacing.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.curriculumModeStep(
                  _assignment.mode.step,
                  RhythmMode.values.length,
                ),
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: SsSpacing.space3),
              SsStrumPendulum(
                clock: _clock,
                beatDuration: _beatDuration,
                struck: crossings,
                height: 180,
              ),
              const SizedBox(height: SsSpacing.space4),
              if (askedChord != null)
                _nowPlaying(context, l10n, colors, askedChord, fretting),
              const SizedBox(height: SsSpacing.space4),
              for (
                var bar = 0;
                bar < (_chords.isEmpty ? 1 : _chords.length);
                bar++
              )
                Padding(
                  padding: const EdgeInsets.only(bottom: SsSpacing.space3),
                  child: RhythmLane(
                    grid: _assignment.grid,
                    chord: _chords.isEmpty ? null : _chords[bar],
                    fretting: bar == barIndex
                        ? fretting
                        : FrettingState.unconfirmed,
                    activeSlotIndex: bar == barIndex
                        ? _activeSlot(pendulum)
                        : null,
                    heardChord: live?.current?.label,
                  ),
                ),
              _attemptSummary(context, l10n, colors),
              const SizedBox(height: SsSpacing.space2),
              // Rule 4: the "I cannot hear you" signal is the level METER, not a
              // banner of prose.
              SsSignalQualityIndicator(
                level: live?.inputLevel ?? 0,
                listening: live?.listening ?? false,
                activeColor: colors.success,
                trackColor: colors.surfaceSunken,
                warningColor: colors.warning,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// What this run can honestly claim so far.
  ///
  /// Two numbers, never one: `directionAccuracy` answers "of the strokes I
  /// heard, how many went the right way", and `coverage` answers "how much of
  /// the pattern did I hear at all". Without the second, two clean strokes out of
  /// sixteen would read as a flawless attempt. Below the coverage floor the
  /// screen says it could not hear enough — which costs the learner nothing
  /// (design §2 rule 6).
  Widget _attemptSummary(
    BuildContext context,
    AppLocalizations l10n,
    SsColorScheme colors,
  ) {
    final start = _startEngineSec;
    if (start == null || !_playing) return const SizedBox.shrink();
    final attempt = gradeRhythm(
      _assignment.grid,
      bpm: _assignment.bpm,
      bars: _chords.isEmpty ? 1 : _chords.length,
      strokes: _strokes,
    );
    final accuracy = attempt.directionAccuracy;
    final text = !attempt.isReportable || accuracy == null
        ? l10n.curriculumTooLittleHeard
        : l10n.curriculumDirectionAccuracy((accuracy * 100).round());
    return Padding(
      padding: const EdgeInsets.only(top: SsSpacing.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: attempt.isReportable
                  ? colors.textPrimary
                  : colors.textSecondary,
            ),
          ),
          Text(
            l10n.curriculumHeard(attempt.heard, attempt.notatedStrokes),
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  /// The notated slot currently sounding, or null on a ghost crossing.
  int? _activeSlot(SsStrumPendulumFrame? pendulum) {
    if (pendulum == null || !pendulum.isStruck) return null;
    final perBar = _assignment.grid.handCrossings.length;
    final withinBar = pendulum.crossingIndex % perBar;
    // An eighth grid has one slot per crossing; a quarter grid has one per TWO,
    // because its odd crossings are the hand coming back.
    return _assignment.grid.subdivision == RhythmSubdivision.eighth
        ? withinBar
        : withinBar ~/ 2;
  }

  /// What the recogniser can honestly say about the held chord.
  ///
  /// Green requires BOTH a confirmed decision and the asked-for label. Anything
  /// short of that is neutral, never a negative claim (§2 rules 1 and 2).
  FrettingState _frettingFor(LiveFrame? live, String? askedChord) {
    if (live == null || askedChord == null) return FrettingState.unconfirmed;
    final confirmed = live.chordDecision == RecognitionDecision.confirmed;
    if (!confirmed) return FrettingState.unconfirmed;
    final heard = live.current?.label;
    if (heard == null) return FrettingState.unconfirmed;
    return heard == askedChord
        ? FrettingState.ringing
        : FrettingState.otherChord;
  }

  Widget _nowPlaying(
    BuildContext context,
    AppLocalizations l10n,
    SsColorScheme colors,
    String chord,
    FrettingState fretting,
  ) {
    final shape = ChordShapes.forLabel(chord);
    final dotColor = switch (fretting) {
      FrettingState.ringing => colors.success,
      FrettingState.otherChord => colors.warning,
      FrettingState.unconfirmed => colors.brand,
    };
    final next = _chords.length < 2
        ? null
        : _chords[(_chords.indexOf(chord) + 1) % _chords.length];
    return Container(
      padding: const EdgeInsets.all(SsSpacing.space3),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(SsRadius.md),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          if (shape != null)
            SsChordDiagram(
              frets: shape.frets,
              ink: colors.textSecondary,
              // The shape the learner is HOLDING is what turns green, rather
              // than a badge elsewhere on the screen.
              dotColor: dotColor,
              size: 84,
              label: chord,
            ),
          const SizedBox(width: SsSpacing.space4),
          Expanded(
            child: Text(
              next == null
                  ? l10n.curriculumChordStays
                  : l10n.curriculumNextChord(next),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
