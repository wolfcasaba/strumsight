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
/// It deliberately does **not** score stroke TIMING yet. Timing credit needs the
/// detected onset and the grid to sit on the same clock, and the offset between
/// the engine's time base and this screen's playback clock has not been
/// measured. Grading against an unverified clock would tell a learner they were
/// late when they were not — exactly the false teaching the whole pillar is
/// built to avoid. The grader (`gradeRhythm`) is written and tested; wiring it
/// up waits for that measurement.
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

  /// The ticker's own elapsed time, the only time base this screen reads.
  ///
  /// Deliberately NOT `SchedulerBinding.currentFrameTimeStamp`: that is valid
  /// only inside a frame, so reading it from a tap handler asserts.
  Duration _tickerElapsed = Duration.zero;
  Duration _startedAt = Duration.zero;
  Duration _elapsedAtPause = Duration.zero;

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
    setState(() => _position = _elapsedAtPause + (elapsed - _startedAt));
  }

  void _toggle() {
    setState(() {
      if (_playing) {
        _elapsedAtPause = _position ?? Duration.zero;
        _playing = false;
        // The position is kept, not cleared: resuming continues the bar rather
        // than restarting it, and a null read would park the pendulum.
        return;
      }
      _startedAt = _tickerElapsed;
      _playing = true;
    });
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
