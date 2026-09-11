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

import '../../../../core/audio/latency_calibrator.dart';
import '../../../../core/design_system/public.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../chords/public.dart';
import '../../../live/public.dart';
import '../../../settings/public.dart';
import '../../data/beginner_course.dart';
import '../../domain/course.dart';
import '../../domain/rhythm_assignment.dart';
import '../../domain/rhythm_countin.dart';
import '../../domain/rhythm_grading.dart';
import '../../domain/rhythm_grid.dart';
import '../../domain/rhythm_mode.dart';
import '../curriculum_names.dart';
import '../providers/curriculum_progress_providers.dart';
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

/// The spoken count-in number, so a test can find it without colliding with the
/// lane's own count row.
@visibleForTesting
const Key countInNumberKey = ValueKey('rhythm.countIn.number');

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

  /// One bar of the exercise's OWN metre, counted before bar 1.
  late final RhythmCountIn _countIn;

  /// Non-null while a CALIBRATION run is in progress rather than an attempt.
  ///
  /// Calibration happens here, at the exercise's own tempo, and not in the
  /// global settings tap-test — for two measured reasons. The tap-test's pair is
  /// screen-tap against click or flash, so it carries touch latency and measures
  /// neither of this screen's channels (pendulum out, microphone in). And
  /// anticipation GROWS with slower tempi, so a number taken at one tempo is
  /// only approximate at another; taken here it is taken at the tempo the
  /// learner is about to be scored at.
  LatencyCalibrator? _calibrator;

  /// What the last calibration run concluded, shown until the next run.
  String? _calibrationNote;

  /// True once the attempt has run its full length and stopped itself.
  ///
  /// An attempt that loops forever cannot be graded AS an attempt, and a "bar 2
  /// of 4" readout over an endless loop would be a lie.
  bool _finished = false;

  /// The rung being practised. Held rather than recomputed per build, because it
  /// is what a finished attempt's evidence is attributed to.
  late final CurriculumMission _mission;

  /// Whether the attempt that just finished was recorded as evidence, or null
  /// before any attempt has finished.
  ///
  /// Three-valued on purpose. "Not recorded" is not a failure — it is the app
  /// declining to judge on too little evidence — and it must be distinguishable
  /// from "nothing has happened yet", or the screen would claim a refusal it
  /// never made.
  bool? _attemptCounted;

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
    _mission = mission;
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
    _countIn = RhythmCountIn.forGrid(_assignment.grid);
    // The pendulum follows the EXERCISE timeline, which is negative during the
    // count-in; `frameAt` wraps a negative position into the loop, so the
    // count-in is fed its own ghost-only crossing list instead (see `_crossings`).
    _clock = _PlaybackClock(
      () => _countInNumber != null ? _position : _exercisePosition,
    );
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
    var justFinished = false;
    setState(() {
      _position =
          Duration(microseconds: ((engineNow - start) * 1e6).round()) +
          (elapsed - _engineAnchorTick);
      // The attempt has a length, so it ends. Grading a run that never stops
      // would keep moving the denominator under the learner's own score.
      final exercise = _exercisePosition;
      final attemptMicros =
          _beatDuration.inMicroseconds *
          _assignment.grid.beatsPerBar *
          _attemptBars;
      if (exercise != null &&
          attemptMicros > 0 &&
          exercise.inMicroseconds >= attemptMicros) {
        _playing = false;
        _finished = true;
        justFinished = true;
      }
    });
    // AFTER the state change, never inside `build`: recording is a write, and a
    // write driven by a rebuild would count one attempt again every time the
    // widget happened to rebuild.
    if (justFinished) _recordFinishedAttempt();
  }

  /// Records the finished attempt, exactly once, unless it was a calibration run.
  ///
  /// A calibration run uses the same ticker and the same grid, but the learner
  /// was following a reference rather than being measured — crediting it as an
  /// attempt would put the calibration's own strokes into the learner's score.
  void _recordFinishedAttempt() {
    if (_calibrator != null) return;
    final counted = ref
        .read(curriculumEstimatesProvider.notifier)
        .recordRhythmAttempt(mission: _mission, attempt: _gradeAttempt());
    setState(() => _attemptCounted = counted);
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
      _finished = false;
      _attemptCounted = null;
      _playing = true;
    });
  }

  /// Reference strokes collected before a calibration is allowed to conclude.
  static const int _calibrationTaps = 8;

  void _startCalibration() {
    setState(() {
      _calibrationNote = null;
      _calibrator = LatencyCalibrator(
        // The exercise's OWN beat, because anticipation is tempo-dependent.
        beatPeriodSec: _beatDuration.inMicroseconds / 1e6,
      );
      _startEngineSec = _engineNowSec;
      _position = Duration.zero;
      _strokes.clear();
      _finished = false;
      _attemptCounted = null;
      _playing = _engineNowSec != null;
    });
  }

  /// Saves the measured offset, or refuses to.
  ///
  /// An unstable run is NOT saved. A median over inconsistent taps would be a
  /// number with no evidence behind it, and every timing score afterwards would
  /// inherit it silently — worse than staying uncalibrated, which at least says
  /// so out loud.
  void _finishCalibration() {
    final calibrator = _calibrator;
    if (calibrator == null) return;
    final l10n = AppLocalizations.of(context);
    final offset = calibrator.offsetSec;
    final stable = calibrator.isStable && offset != null;
    if (stable) {
      final ms = (offset * 1000).round();
      ref.read(strumLatencyProvider.notifier).set(ms);
      _calibrationNote = l10n.curriculumCalibrateSaved(ms);
    } else {
      _calibrationNote = l10n.curriculumCalibrateUneven;
    }
    setState(() {
      _calibrator = null;
      _playing = false;
      _position = null;
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
    final calibrator = _calibrator;
    if (calibrator != null) {
      // Calibration measures the offset between the beat the learner SEES and
      // the strum the engine REPORTS, on the exercise's own timeline.
      final atSec =
          (live.latestStrumTime - start) -
          _countIn.durationAt(_beatDuration).inMicroseconds / 1e6;
      if (atSec >= 0) calibrator.registerTap(atSec);
      if (calibrator.sampleCount >= _calibrationTaps) _finishCalibration();
      return;
    }
    // On the EXERCISE timeline, not the button's: bar 1 beat 1 is zero, so the
    // count-in does not shift every expected onset by a bar.
    final atUs =
        ((live.latestStrumTime - start) * 1e6).round() -
        _countIn.durationAt(_beatDuration).inMicroseconds;
    // A stroke played while counting in is not a mistake — but one just BEFORE
    // bar 1 is bar 1 played early, and must still be graded.
    if (!RhythmCountIn.countsTowardAttempt(
      atUs: atUs,
      toleranceUs: rhythmToleranceUs,
    )) {
      return;
    }
    _strokes.add(
      DetectedStroke(
        atUs: atUs,
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
    // While counting in, the hand swings through a bar of pure ghosts. That is
    // our own model applied honestly: the hand never stops, so the learner's arm
    // is already moving when bar 1 arrives instead of starting from rest.
    if (_countInNumber != null) return _countIn.ghostCrossings;
    if (_calibrator != null) return _calibrationCrossings;
    final perBar = _assignment.grid.handCrossings;
    final bars = _chords.isEmpty ? 1 : _chords.length;
    return [for (var bar = 0; bar < bars; bar++) ...perBar];
  }

  Duration get _beatDuration =>
      Duration(microseconds: (60000000 / _assignment.bpm).round());

  /// Where the exercise itself stands: negative for the whole count-in, zero
  /// exactly at bar 1 beat 1.
  Duration? get _exercisePosition => _position == null
      ? null
      : _countIn.exercisePosition(
          position: _position!,
          beatDuration: _beatDuration,
        );

  /// The number being counted, or null once the exercise has begun.
  int? get _countInNumber => _position == null
      ? null
      : _countIn.numberAt(position: _position!, beatDuration: _beatDuration);

  /// While calibrating, the hand strikes on EVERY beat: the learner is asked for
  /// one reference stroke per beat, so every beat yields a sample.
  List<bool> get _calibrationCrossings => [
    for (var beat = 0; beat < _assignment.grid.beatsPerBar * 2; beat++) ...[
      true,
      false,
    ],
  ];

  /// How many bars the whole attempt lasts.
  int get _attemptBars => _assignment.bars;

  /// One-based bar within the attempt, or null before bar 1.
  int? get _barNumber {
    final exercise = _exercisePosition;
    if (exercise == null || exercise.isNegative) return null;
    final barMicros =
        _beatDuration.inMicroseconds * _assignment.grid.beatsPerBar;
    if (barMicros <= 0) return null;
    final bar = exercise.inMicroseconds ~/ barMicros + 1;
    return bar > _attemptBars ? null : bar;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final frame = ref.watch(liveFrameProvider);
    final live = frame.asData?.value;
    _absorb(live);

    final crossings = _crossings;
    final countInNumber = _countInNumber;
    // Same timeline the clock reports, so the painted frame and the scored grid
    // can never disagree about where the hand is.
    final pendulumPosition = countInNumber != null
        ? _position
        : _exercisePosition;
    final pendulum = pendulumPosition == null
        ? null
        : SsStrumPendulum.frameAt(
            position: pendulumPosition,
            beatDuration: _beatDuration,
            struck: crossings,
          );
    final perBar = _assignment.grid.handCrossings.length;
    final barIndex = pendulum == null
        ? 0
        : (pendulum.crossingIndex ~/ perBar) %
              (_chords.isEmpty ? 1 : _chords.length);
    // Nothing is asked during the count-in: it is for listening, so naming a
    // chord there would score a bar that has not started.
    final askedChord = (_chords.isEmpty || countInNumber != null)
        ? null
        : _chords[barIndex];
    final fretting = _frettingFor(live, askedChord);

    return Scaffold(
      appBar: AppBar(
        // The RUNG's name, not a generic "Strumming". Opening step 6 from the
        // ladder and landing on a screen indistinguishable from step 2 leaves the
        // learner unable to tell whether the tap did what it offered.
        title: Text(curriculumMissionName(l10n, _mission.missionId)),
      ),
      // The transport sits OUTSIDE the scroll view on purpose: a practice
      // screen's play control must be reachable without scrolling, and a widget
      // test caught it sitting below the fold at phone height.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SsSpacing.space3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: SsSpacing.space3,
            children: [
              FilledButton.icon(
                onPressed: _toggle,
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                label: Text('${_assignment.bpm.round()} BPM'),
              ),
              TextButton.icon(
                onPressed: _calibrator == null ? _startCalibration : null,
                icon: const Icon(Icons.tune),
                label: Text(l10n.curriculumCalibrateAction),
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
              _loopPosition(context, l10n, colors, countInNumber),
              if (_calibrator != null)
                Text(
                  l10n.curriculumCalibrateInstruction,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colors.brand),
                ),
              if (_calibrationNote != null)
                Text(
                  _calibrationNote!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              const SizedBox(height: SsSpacing.space3),
              SsStrumPendulum(
                clock: _clock,
                beatDuration: _beatDuration,
                struck: crossings,
                height: 180,
                muted: _assignment.grid.slots.every((slot) => slot.muted),
                sounding: _soundingFor(askedChord),
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
                    activeSlotIndex: (bar == barIndex && countInNumber == null)
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

  /// Where the learner is: counting in, in bar N of the attempt, or finished.
  ///
  /// This closed the last gap that made the exercise unusable rather than merely
  /// unpolished. Without it the loop had no landmarks at all: no count-in, so
  /// bar 1 was always a guess; no bar number, so a four-bar attempt was
  /// indistinguishable from an endless loop; and no end, so there was never a
  /// moment the summary was ABOUT something.
  Widget _loopPosition(
    BuildContext context,
    AppLocalizations l10n,
    SsColorScheme colors,
    int? countInNumber,
  ) {
    final text = Theme.of(context).textTheme;
    if (countInNumber != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.curriculumCountInLabel,
            style: text.labelMedium?.copyWith(color: colors.textSecondary),
          ),
          Text(
            // Keyed: the lane below also prints "1" as part of its "1 & 2 &"
            // count row, so a test looking for the spoken number by text alone
            // matches three widgets and proves nothing.
            key: countInNumberKey,
            l10n.curriculumCountInNumber(countInNumber),
            // Big, because it is read at a glance while the hand is already
            // moving — not something to study.
            style: text.displaySmall?.copyWith(
              color: colors.brand,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
    }
    final bar = _barNumber;
    return Text(
      bar == null
          ? (_finished ? l10n.curriculumAttemptDone : '')
          : l10n.curriculumBarOf(bar, _attemptBars),
      style: text.labelLarge?.copyWith(
        color: _finished ? colors.textSecondary : colors.textPrimary,
        fontFeatures: const [FontFeature.tabularFigures()],
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
  /// The attempt as it stands, graded.
  ///
  /// One definition, used by the on-screen summary AND by the evidence record,
  /// so what the learner is shown and what is written down can never disagree.
  RhythmAttempt _gradeAttempt() {
    // `_attemptBars`, not the chord cycle's length. The attempt is as long as
    // the assignment says, and grading only the first cycle would push every
    // stroke after it into `extraConfirmedStrokes` and compute coverage over too
    // few slots — a bug that only became visible once the attempt had an end.
    final calibrationMs = ref.read(strumLatencyProvider);
    return gradeRhythm(
      _assignment.grid,
      bpm: _assignment.bpm,
      bars: _attemptBars,
      strokes: _strokes,
      // 0 means "measured, and it is zero"; absent means never measured, and
      // then no timing is claimed at all.
      timingCalibrationUs: _isCalibrated ? calibrationMs * 1000 : null,
    );
  }

  Widget _attemptSummary(
    BuildContext context,
    AppLocalizations l10n,
    SsColorScheme colors,
  ) {
    final start = _startEngineSec;
    // `_finished` as well as `_playing`: the summary used to vanish at the exact
    // moment it became final, throwing away the one reading the learner came for.
    if (start == null || !(_playing || _finished)) {
      return const SizedBox.shrink();
    }
    // Watched, not read, so a calibration saved mid-screen re-grades the view.
    ref.watch(strumLatencyProvider);
    final attempt = _gradeAttempt();
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
          ..._timingLines(context, l10n, colors, attempt),
          // Only once an attempt has actually finished, and only when it was
          // recorded. Silence otherwise: the "too little heard" line above
          // already says why nothing was written, and repeating it as "not
          // counted" would read as a penalty for a quiet room.
          if (_finished && _attemptCounted == true)
            Text(
              l10n.curriculumAttemptCounted,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: colors.success),
            ),
        ],
      ),
    );
  }

  /// Whether this device has a measured pendulum↔strum offset.
  ///
  /// The preference stores 0 for "uncalibrated", which is indistinguishable from
  /// a genuine zero — so a separate marker would be better. It is not worth a
  /// migration here: a real device measuring exactly 0 ms is vanishingly
  /// unlikely, and the cost of the collision is one extra calibration run, not a
  /// false score.
  bool get _isCalibrated => ref.read(strumLatencyProvider) != 0;

  /// The timing report, or an honest statement that there isn't one.
  List<Widget> _timingLines(
    BuildContext context,
    AppLocalizations l10n,
    SsColorScheme colors,
    RhythmAttempt attempt,
  ) {
    final label = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: colors.textSecondary);
    if (!attempt.hasTimingReport) {
      // Rule: what is not measured says so. An uncalibrated device gets no
      // timing number rather than a plausible-looking one.
      if (_isCalibrated) return const [];
      return [Text(l10n.curriculumTimingUncalibrated, style: label)];
    }
    final offMs = (attempt.meanAbsTimingErrorUs! / 1000).round();
    return [
      Text(l10n.curriculumTimingOff(offMs), style: label),
      Text(switch (attempt.timingShape!) {
        RhythmTimingShape.systematicLate => l10n.curriculumTimingLate,
        RhythmTimingShape.systematicEarly => l10n.curriculumTimingEarly,
        RhythmTimingShape.scattered => l10n.curriculumTimingScattered,
      }, style: label),
    ];
  }

  /// Which strings [chord] actually sounds, from the app's OWN fingering.
  ///
  /// Null when there is no chord to ask about — a damped rung, or the count-in —
  /// and then the band shows all six, because nothing is being excluded.
  ///
  /// `-1` in a shipped fingering is the `×` of standard notation: the string is
  /// not played. Feeding it to the pendulum is what stops an Am being animated as
  /// though the pick sounded the bass E.
  List<bool>? _soundingFor(String? chord) {
    if (chord == null) return null;
    final shape = ChordShapes.forLabel(chord);
    if (shape == null) return null;
    return [for (final fret in shape.frets) fret >= 0];
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
