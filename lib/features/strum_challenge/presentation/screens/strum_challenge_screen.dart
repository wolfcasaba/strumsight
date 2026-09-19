/// The 60-second strum challenge: one fixed pattern, one minute, one honest
/// number, and a best to beat today.
///
/// Why (market research, 2026-09-15): no competitor scores strum DIRECTION,
/// and the most-loved measurable micro-goal in the category is a one-minute
/// drill with a per-day best. This screen is the down/up detector turned into
/// that drill — offline, no account, and never a false "wrong".
///
/// ## What this screen shares with the rhythm exercise, deliberately
///
/// The clock, the stroke intake and the grading are the rhythm practice
/// screen's (`rhythm_practice_screen.dart`), not a second implementation:
///
///   - the grid runs on the ENGINE clock (`engineTimeSec`) and a stroke is
///     placed at `latestStrumTime`, the measured true onset — never at the
///     moment its frame arrived, which the same measurement puts 84-142 ms
///     later (`test/features/live/strum_timestamp_latency_test.dart`);
///   - the ticker only interpolates between engine anchors so the pendulum
///     moves at frame rate; the grading never uses it;
///   - a stroke during the count-in is dropped, and one just BEFORE bar 1 is
///     bar 1 played early (`RhythmCountIn.countsTowardAttempt`);
///   - during the scored bars the beat is FELT, not heard: an audible click is
///     counted as a stroke on the very beat it marks (15 false strums from 16
///     clicks, `metronome_click_pollution_test.dart`), so `curriculumPulseFor`
///     decides the channel.
///
/// ## What it claims
///
/// The score is `RhythmAttempt.credited` — strokes heard, in time, travelling
/// the way the pattern asked. A bar whose six struck slots were all credited
/// is a "full pattern". Below the coverage floor the screen says it could not
/// hear enough (design §2 rule 6) instead of showing a low score: silence is
/// absence of evidence, never evidence of a wrong stroke.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/config/app_config.dart';
import '../../../../app/routing/app_route.dart';
import '../../../../core/design_system/public.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../curriculum/public.dart'
    show
        CurriculumPulse,
        CurriculumPulsePhase,
        DetectedStroke,
        FrettingState,
        RhythmAttempt,
        RhythmCountIn,
        RhythmGrid,
        RhythmLane,
        RhythmTimingShape,
        curriculumPulseFor,
        gradeRhythm,
        rhythmToleranceUs;
import '../../../learn/public.dart' show Metronome, metronomeMutedProvider;
import '../../../live/public.dart' show LiveFrame, liveFrameProvider;
import '../../../settings/public.dart' show strumLatencyProvider;
import '../../../streak/public.dart' show streakProvider;
import '../../domain/strum_challenge.dart';
import '../../providers/strum_challenge_providers.dart';

/// Reads the screen's own playback position for the design system's clock
/// port. Pull-style: `SsBeatClock` is polled once per frame by design.
final class _PlaybackClock implements SsBeatClock {
  _PlaybackClock(this._read);
  final Duration? Function() _read;
  @override
  Duration? get position => _read();
}

/// The count-in readout, keyed so a test can find it without colliding with
/// the lane's own count row.
@visibleForTesting
const Key strumChallengeCountInKey = ValueKey('strumChallenge.countIn');

/// The remaining-seconds counter.
@visibleForTesting
const Key strumChallengeSecondsLeftKey = ValueKey('strumChallenge.secondsLeft');

/// The live score counter shown during the scored bars.
@visibleForTesting
const Key strumChallengeScoreKey = ValueKey('strumChallenge.score');

final class StrumChallengeScreen extends ConsumerStatefulWidget {
  const StrumChallengeScreen({super.key});

  @override
  ConsumerState<StrumChallengeScreen> createState() =>
      _StrumChallengeScreenState();
}

final class _StrumChallengeScreenState
    extends ConsumerState<StrumChallengeScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final _PlaybackClock _clock;

  /// One bar of the pattern's own metre, counted before bar 1.
  late final RhythmCountIn _countIn;

  /// How many scored bars make up the minute (20 at 80 BPM in 4/4).
  late final int _bars;

  final RhythmGrid _grid = strumChallengeGrid;

  /// The shipped click, sounded only during the count-in.
  final Metronome _metronome = Metronome();

  Duration? _position;
  bool _playing = false;

  /// True once the run has lasted its full minute and stopped itself.
  bool _finished = false;

  /// The ticker's own elapsed time. Used ONLY to interpolate between engine
  /// anchors — never as the timeline itself.
  Duration _tickerElapsed = Duration.zero;

  /// The engine clock reading at the run's start. Null until the engine has
  /// produced a frame — without it there is no shared clock to score on.
  double? _startEngineSec;

  /// The newest engine clock reading, and the ticker time it arrived at.
  double? _engineNowSec;
  Duration _engineAnchorTick = Duration.zero;

  /// Strokes heard this run, placed on the engine clock.
  final List<DetectedStroke> _strokes = [];
  int _lastStrumSeq = 0;

  /// The last beat index a pulse was emitted for; -1 means nothing yet.
  int _lastPulsedBeat = -1;

  /// The finished run, graded once at the moment it ended.
  RhythmAttempt? _result;

  /// Whether the finished run beat today's best.
  bool _newBest = false;

  @override
  void initState() {
    super.initState();
    _bars = strumChallengeBars(
      bpm: strumChallengeBpm,
      beatsPerBar: _grid.beatsPerBar,
    );
    _countIn = RhythmCountIn.forGrid(_grid);
    // The pendulum follows the EXERCISE timeline, which is negative during the
    // count-in; `frameAt` wraps a negative position into the loop, so the
    // count-in is fed its own clock and ghost-only crossings instead.
    _clock = _PlaybackClock(
      () => _countInNumber != null ? _position : _exercisePosition,
    );
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _metronome.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    _tickerElapsed = elapsed;
    if (!_playing) return;
    final start = _startEngineSec;
    final engineNow = _engineNowSec;
    if (start == null || engineNow == null) return;
    var justFinished = false;
    setState(() {
      // Interpolate forward from the last engine anchor: the anchor is the
      // truth, the ticker only fills the ~66 ms gaps. Derived from the anchor
      // every frame, never accumulated (ADR 0274).
      _position =
          Duration(microseconds: ((engineNow - start) * 1e6).round()) +
          (elapsed - _engineAnchorTick);
      final exercise = _exercisePosition;
      if (exercise != null && exercise.inMicroseconds >= _attemptMicros) {
        _playing = false;
        _finished = true;
        justFinished = true;
      }
    });
    _pulseIfNewBeat();
    // AFTER the state change, never inside `build`: recording is a write, and
    // a write driven by a rebuild would record one run per rebuild.
    if (justFinished) _recordFinishedAttempt();
  }

  /// Emits the beat, once per beat, in whichever channel is safe right now
  /// (`metronome_pulse.dart` carries the measurement behind the choice).
  void _pulseIfNewBeat() {
    final position = _position;
    if (!_playing || position == null) {
      _lastPulsedBeat = -1;
      return;
    }
    final beatUs = _beatDuration.inMicroseconds;
    if (beatUs <= 0) return;
    final beat = position.inMicroseconds ~/ beatUs;
    if (beat == _lastPulsedBeat) return;
    _lastPulsedBeat = beat;

    switch (curriculumPulseFor(
      phase: _countInNumber != null
          ? CurriculumPulsePhase.countIn
          : CurriculumPulsePhase.scoredAttempt,
      isDownbeat: beat % _grid.beatsPerBar == 0,
      muted: ref.read(metronomeMutedProvider),
    )) {
      case CurriculumPulse.none:
        return;
      case CurriculumPulse.click:
        _metronome.tick().ignore();
      case CurriculumPulse.accentClick:
        _metronome.tick(accent: true).ignore();
      case CurriculumPulse.haptic:
        HapticFeedback.lightImpact();
      case CurriculumPulse.accentHaptic:
        HapticFeedback.mediumImpact();
    }
  }

  /// Grades the finished run exactly once, credits the streak when anything
  /// was heard, and records a reportable run against today's best.
  void _recordFinishedAttempt() {
    final attempt = _gradeAttempt();
    setState(() {
      _result = attempt;
      _newBest = false;
    });
    if (attempt.heard > 0) {
      // A minute of real strumming is real practice, whatever the score.
      ref.read(streakProvider.notifier).recordPracticeToday().ignore();
    }
    // Below the coverage floor nothing is claimed, so nothing is recorded: a
    // "best of 3" over a run the microphone mostly missed would be a number
    // with no evidence behind it.
    if (!attempt.isReportable) return;
    unawaited(
      ref
          .read(strumChallengeBestProvider.notifier)
          .recordAttempt(
            score: attempt.credited,
            patterns: strumChallengeFullPatterns(attempt),
          )
          .then((newBest) {
            if (!mounted) return;
            setState(() => _newBest = newBest);
          }),
    );
  }

  /// The run as it stands, graded. One definition for the live counter and
  /// the final result, so the two can never disagree.
  RhythmAttempt _gradeAttempt() {
    final calibrationMs = ref.read(strumLatencyProvider);
    return gradeRhythm(
      _grid,
      bpm: strumChallengeBpm,
      bars: _bars,
      strokes: _strokes,
      // 0 means never measured (see `rhythm_practice_screen.dart`), and then
      // no timing is claimed at all.
      timingCalibrationUs: calibrationMs != 0 ? calibrationMs * 1000 : null,
    );
  }

  void _start() {
    setState(() {
      // Anchor the run to the engine clock's current reading, so the grid and
      // every detected stroke share one scale from the first bar.
      _startEngineSec = _engineNowSec;
      _position = Duration.zero;
      _strokes.clear();
      _finished = false;
      _result = null;
      _newBest = false;
      _lastPulsedBeat = -1;
      _playing = true;
    });
  }

  /// Abandons the run. An unfinished minute has no score — it is not graded,
  /// not recorded, and not held against the learner.
  void _stop() {
    setState(() {
      _playing = false;
      _position = null;
      _finished = false;
      _result = null;
      _newBest = false;
    });
  }

  /// Leaves the challenge: back to wherever it was opened from, or to the
  /// hub when it was the first route (the Live screen's rule).
  void _leave() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(
      ref.read(appConfigProvider).flags.adaptiveShellEnabled
          ? AppRoutes.today
          : AppRoutes.live,
    );
  }

  /// Folds a freshly arrived frame into the clock anchor and the stroke list.
  ///
  /// A stroke is placed at `latestStrumTime` — the MEASURED true onset —
  /// never at the moment this frame arrived.
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
    // On the EXERCISE timeline, not the button's: bar 1 beat 1 is zero, so
    // the count-in does not shift every expected onset by a bar.
    final atUs =
        ((live.latestStrumTime - start) * 1e6).round() -
        _countIn.durationAt(_beatDuration).inMicroseconds;
    // A stroke played while counting in is not a mistake — but one just
    // BEFORE bar 1 is bar 1 played early, and must still be graded.
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
        // The pipeline publishes a strum only once its DIRECTION is
        // confirmed, so a stroke reaching here is confirmed evidence.
        isConfirmed: true,
      ),
    );
  }

  Duration get _beatDuration =>
      Duration(microseconds: (60000000 / strumChallengeBpm).round());

  /// The whole scored run, in microseconds of the exercise timeline.
  int get _attemptMicros =>
      _beatDuration.inMicroseconds * _grid.beatsPerBar * _bars;

  /// Where the run itself stands: negative for the count-in, zero exactly at
  /// bar 1 beat 1.
  Duration? get _exercisePosition {
    final position = _position;
    if (position == null) return null;
    return _countIn.exercisePosition(
      position: position,
      beatDuration: _beatDuration,
    );
  }

  /// The number being counted, or null once the scored bars have begun.
  int? get _countInNumber {
    final position = _position;
    if (position == null || position.isNegative) return null;
    return _countIn.numberAt(position: position, beatDuration: _beatDuration);
  }

  /// Whole seconds still to play, rounded UP so the counter reaches zero only
  /// when the run really ends.
  int get _secondsLeft {
    final exercise = _exercisePosition;
    if (exercise == null || exercise.isNegative) return strumChallengeSeconds;
    final remainingUs = _attemptMicros - exercise.inMicroseconds;
    if (remainingUs <= 0) return 0;
    return (remainingUs / 1000000).ceil();
  }

  /// The notated slot currently sounding, or null on a ghost crossing. An
  /// eighth grid has one slot per crossing.
  int? _activeSlot(SsStrumPendulumFrame? pendulum) {
    if (pendulum == null || !pendulum.isStruck) return null;
    return pendulum.crossingIndex % _grid.handCrossings.length;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final text = Theme.of(context).textTheme;
    final frame = ref.watch(liveFrameProvider);
    final live = frame.asData?.value;
    _absorb(live);

    final countInNumber = _countInNumber;
    // While counting in the hand swings through pure ghosts: the arm is
    // already moving when bar 1 arrives instead of starting from rest.
    final crossings = countInNumber != null
        ? _countIn.ghostCrossings
        : _grid.handCrossings;
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
    final scoring = _playing && countInNumber == null;
    final best = ref.watch(strumChallengeBestProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.strumChallengeTitle),
        actions: [
          IconButton(
            icon: Icon(
              ref.watch(metronomeMutedProvider)
                  ? Icons.volume_off
                  : Icons.volume_up,
            ),
            tooltip: l10n.learnMetronome,
            onPressed: () => ref.read(metronomeMutedProvider.notifier).toggle(),
          ),
        ],
      ),
      // The transport sits OUTSIDE the scroll view: the start control must be
      // reachable without scrolling. A Wrap, not a Row, so the two labelled
      // buttons drop onto two lines at 2.0 text scale instead of overflowing.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SsSpacing.space3),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: SsSpacing.space3,
            runSpacing: SsSpacing.space2,
            children: [
              if (_playing)
                FilledButton.icon(
                  onPressed: _stop,
                  icon: const Icon(Icons.stop),
                  label: Text(l10n.strumChallengeStop),
                )
              else
                FilledButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    _finished
                        ? l10n.strumChallengeTryAgain
                        : l10n.strumChallengeStart,
                  ),
                ),
              TextButton(
                onPressed: _playing ? null : _leave,
                child: Text(l10n.strumChallengeDone),
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
                best == null
                    ? l10n.strumChallengeNoAttemptYet
                    : l10n.strumChallengeBestToday(best.bestScore),
                style: text.labelLarge?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: SsSpacing.space3),
              _status(l10n, text, colors, countInNumber, scoring),
              const SizedBox(height: SsSpacing.space3),
              SsStrumPendulum(
                clock: _clock,
                beatDuration: _beatDuration,
                struck: crossings,
                height: 160,
              ),
              const SizedBox(height: SsSpacing.space4),
              // The notation: which crossings strike. No chord is asked for —
              // muted strokes or any chord the learner likes.
              RhythmLane(
                grid: _grid,
                chord: null,
                fretting: FrettingState.unconfirmed,
                activeSlotIndex: scoring ? _activeSlot(pendulum) : null,
              ),
              const SizedBox(height: SsSpacing.space3),
              ..._resultLines(l10n, text, colors),
              const SizedBox(height: SsSpacing.space2),
              // The "I cannot hear you" signal is the level METER, not prose.
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

  /// Where the learner is: counting in, or inside the minute with the clock
  /// and the live score. Big, because it is read at a glance while the hand
  /// is already moving.
  Widget _status(
    AppLocalizations l10n,
    TextTheme text,
    SsColorScheme colors,
    int? countInNumber,
    bool scoring,
  ) {
    if (countInNumber != null) {
      return Text(
        key: strumChallengeCountInKey,
        l10n.strumChallengeCountIn(countInNumber),
        style: text.displaySmall?.copyWith(
          color: colors.brand,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    }
    if (!scoring) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          key: strumChallengeSecondsLeftKey,
          l10n.strumChallengeSecondsLeft(_secondsLeft),
          style: text.displaySmall?.copyWith(
            color: colors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          key: strumChallengeScoreKey,
          l10n.strumChallengeScore(_gradeAttempt().credited),
          style: text.titleLarge?.copyWith(
            color: colors.brand,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  /// What the finished minute can honestly claim.
  List<Widget> _resultLines(
    AppLocalizations l10n,
    TextTheme text,
    SsColorScheme colors,
  ) {
    final attempt = _result;
    if (!_finished || attempt == null) return const [];
    final label = text.labelMedium?.copyWith(color: colors.textSecondary);
    final accuracy = attempt.directionAccuracy;
    if (!attempt.isReportable || accuracy == null) {
      // Honest-but-kind: too little evidence is not a low score, and it is
      // never a "wrong". The remedy is named instead.
      return [
        Text(
          l10n.strumChallengeTooLittleHeard,
          style: text.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
      ];
    }
    return [
      Text(
        l10n.strumChallengeResult(
          attempt.credited,
          strumChallengeFullPatterns(attempt),
        ),
        style: text.titleLarge?.copyWith(color: colors.textPrimary),
      ),
      if (_newBest)
        Text(
          l10n.strumChallengeNewBest,
          style: text.titleMedium?.copyWith(color: colors.success),
        ),
      Text(
        l10n.strumChallengeDirectionAccuracy((accuracy * 100).round()),
        style: label,
      ),
      Text(
        l10n.strumChallengeHeard(attempt.heard, attempt.notatedStrokes),
        style: label,
      ),
      ..._timingLines(l10n, label, attempt),
    ];
  }

  /// The timing report, or an honest statement that there isn't one — the
  /// rhythm exercise's own lines, so the two screens say the same thing.
  List<Widget> _timingLines(
    AppLocalizations l10n,
    TextStyle? label,
    RhythmAttempt attempt,
  ) {
    if (!attempt.hasTimingReport) {
      if (ref.read(strumLatencyProvider) != 0) return const [];
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
}
