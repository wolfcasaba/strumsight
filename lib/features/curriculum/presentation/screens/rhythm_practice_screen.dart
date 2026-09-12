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
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/audio/latency_calibrator.dart';
import '../../../../core/design_system/public.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../chords/public.dart';
import '../../../learn/public.dart' show Metronome, metronomeMutedProvider;
import '../../../live/public.dart';
import '../../../settings/public.dart';
import '../../data/beginner_course.dart';
import '../../domain/course.dart';
import '../../domain/rhythm_assignment.dart';
import '../../domain/rhythm_countin.dart';
import '../../domain/rhythm_demonstration.dart';
import '../../domain/rhythm_grading.dart';
import '../../domain/rhythm_grid.dart';
import '../../domain/rhythm_mode.dart';
import '../../domain/chord_grading.dart';
import '../../domain/metronome_pulse.dart';
import '../../domain/mission_chords.dart';
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

/// The demonstration's own readout, so a test can tell "Listen — 1 of 2" from the
/// "Now you" that follows it without matching the label above as well.
@visibleForTesting
const Key demonstrationLabelKey = ValueKey('rhythm.demonstration.label');

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

  /// What the app plays BEFORE the count-in, or null for the three modes that do
  /// not demonstrate (`rhythm_demonstration.dart`).
  late final RhythmDemonstration? _demonstration;

  /// How many demonstration strokes have been sounded this run, so each sounds
  /// exactly once. Counted rather than timed: a dropped frame must not replay a
  /// stroke, and must not skip the rest of the pattern either.
  int _demoStrokesSounded = 0;

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

  /// The shipped click. WHEN it may sound is `metronome_pulse.dart`'s decision,
  /// which carries the measurement: an audible click during the scored bars is
  /// counted as a stroke on the very beat it marks (15 false strums from 16 clicks,
  /// `test/features/live/metronome_click_pollution_test.dart`).
  final Metronome _metronome = Metronome();

  /// The last beat index a pulse was emitted for, counted from the moment play was
  /// pressed so the count-in and the attempt share one monotonic sequence. -1 means
  /// nothing has pulsed yet.
  int _lastPulsedBeat = -1;

  /// What the decoder said about the held chord during the attempt, in order.
  ///
  /// Kept separately from `_strokes` because it is a different measurement on a
  /// different unit: strokes are instants, a chord is held across a bar.
  final List<DetectedChord> _chordDetections = <DetectedChord>[];

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
    // The no-argument route is a direct entry point, not a teaching decision: it
    // opens the RICHEST rung so the whole surface is reachable in one place. Most
    // chord rungs now carry an exercise too, so "the first one with a chord" no
    // longer identifies the richest — the one with the most notated strokes does,
    // and that is the pattern rung (24 strokes against a held chord's 16). Derived
    // rather than named, so adding a rung cannot leave this pointing at a thinner
    // one. The real flow always passes the learner's own mission.
    final playable = [
      for (final candidate in course.missionsInOrder)
        if (candidate.rhythm != null) candidate,
    ];
    final mission =
        widget.mission ??
        (playable.isEmpty
            ? course.missionsInOrder.first
            : playable.reduce((best, candidate) {
                final bestRichness =
                    (best.rhythm!.mode.scoresChord ? 1000 : 0) +
                    best.rhythm!.notatedStrokes;
                final richness =
                    (candidate.rhythm!.mode.scoresChord ? 1000 : 0) +
                    candidate.rhythm!.notatedStrokes;
                return richness > bestRichness ? candidate : best;
              }));
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
    // Which chords this rung asks for, derived from what it TRAINS — not a
    // hardcoded Em/Am pair, which was right only for the pattern rung and would
    // have asked an E-minor rung's learner to play A minor every other bar.
    // A damped rung gets an empty cycle, so the lane says so instead of showing a
    // shape the learner is not meant to fret.
    _chords = missionChordCycle(mission);
    _countIn = RhythmCountIn.forGrid(_assignment.grid);
    _demonstration = RhythmDemonstration.forAssignment(_assignment);
    // The pendulum follows the EXERCISE timeline, which is negative during the
    // count-in; `frameAt` wraps a negative position into the loop, so the
    // count-in is fed its own ghost-only crossing list instead (see `_crossings`).
    _clock = _PlaybackClock(
      () => _demoPosition != null || _countInNumber != null
          ? _countInClock
          : _exercisePosition,
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
    _soundDemonstration();
    _pulseIfNewBeat();
    // AFTER the state change, never inside `build`: recording is a write, and a
    // write driven by a rebuild would count one attempt again every time the
    // widget happened to rebuild.
    if (justFinished) _recordFinishedAttempt();
  }

  /// Plays the demonstration's strokes, each exactly once, while it is running.
  ///
  /// Audible and unaccented except on beat 1 of a demonstrated bar — the accent is
  /// metre, never direction, because a pitch that meant "up" would teach a cue the
  /// guitar does not make (`rhythm_demonstration.dart`).
  ///
  /// Safe to sound at full volume despite the measured 15-false-strums-from-16-clicks
  /// result, because nothing here is scored: every demonstration stroke sits at least
  /// a full bar plus a count-in before bar 1, and `RhythmCountIn.countsTowardAttempt`
  /// drops it. That separation is measured end to end in
  /// `test/features/live/demonstration_preroll_test.dart`, not assumed.
  void _soundDemonstration() {
    final demonstration = _demonstration;
    final position = _demoPosition;
    if (demonstration == null || position == null) return;
    if (ref.read(metronomeMutedProvider)) {
      // Muted silences the demonstration too, and that is not a half-measure: with
      // no sound there is nothing to repeat, so the screen says the mode cannot run
      // rather than scoring a pattern it never played.
      return;
    }
    final strokes = demonstration.strokes;
    while (_demoStrokesSounded < strokes.length &&
        strokes[_demoStrokesSounded].atUs <= position.inMicroseconds) {
      _metronome.tick(accent: strokes[_demoStrokesSounded].accent).ignore();
      _demoStrokesSounded++;
    }
  }

  /// Emits the beat, once per beat, in whichever channel is safe right now.
  ///
  /// WHICH channel is a decision with a measurement behind it, and it lives in
  /// `metronome_pulse.dart` rather than here: the case that matters most — silence
  /// during a calibration run — is the hardest one to reach from a widget test, and
  /// it is the one that stops the device calibrating against its own metronome.
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
      phase: _pulsePhase,
      isDownbeat: beat % _assignment.grid.beatsPerBar == 0,
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

  /// What is being measured at this instant, which is what decides the channel.
  ///
  /// Calibration outranks the count-in deliberately: a calibration run also counts
  /// itself in, and a click there would be registered as a tap.
  CurriculumPulsePhase get _pulsePhase {
    if (_calibrator != null) return CurriculumPulsePhase.calibration;
    if (_demoPosition != null) return CurriculumPulsePhase.demonstration;
    if (_countInNumber != null) return CurriculumPulsePhase.countIn;
    return CurriculumPulsePhase.scoredAttempt;
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
        .recordAttempt(
          mission: _mission,
          rhythm: _gradeAttempt(),
          chord: _gradeChordAttempt(),
        );
    setState(() => _attemptCounted = counted);
  }

  /// The chord side of the same run, or null when this rung asks for no chord.
  ChordAttempt? _gradeChordAttempt() {
    if (_chords.isEmpty) return null;
    return gradeChords(
      cycle: _chords,
      bars: _attemptBars,
      bpm: _assignment.bpm,
      beatsPerBar: _assignment.grid.beatsPerBar,
      detections: _chordDetections,
    );
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
      _chordDetections.clear();
      _finished = false;
      _attemptCounted = null;
      _lastPulsedBeat = -1;
      _demoStrokesSounded = 0;
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
      _chordDetections.clear();
      _finished = false;
      _attemptCounted = null;
      _lastPulsedBeat = -1;
      // A calibration run never demonstrates: the reference being calibrated
      // against is the pendulum, and a demonstration would give the learner
      // something else to follow.
      _demoStrokesSounded = _demonstration?.strokes.length ?? 0;
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

    _absorbChord(live, start);

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
          (_demoUs + _countIn.durationAt(_beatDuration).inMicroseconds) / 1e6;
      if (atSec >= 0) calibrator.registerTap(atSec);
      if (calibrator.sampleCount >= _calibrationTaps) _finishCalibration();
      return;
    }
    // On the EXERCISE timeline, not the button's: bar 1 beat 1 is zero, so the
    // count-in does not shift every expected onset by a bar.
    final atUs =
        ((live.latestStrumTime - start) * 1e6).round() -
        _demoUs -
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

  /// Records what the decoder says about the held chord, on the exercise timeline.
  ///
  /// Sampled every frame rather than at each stroke, because a chord is HELD: the
  /// decoder needs several frames of a ringing shape before it confirms one, so
  /// asking "what was confirmed at the instant of this stroke" would measure the
  /// decoder's latency instead of the learner's fingers.
  ///
  /// Placed at the frame's own engine time, and said plainly: unlike a stroke —
  /// which is placed at the measured true onset `latestStrumTime` — there is no
  /// measured decision-time to correct back to. A confirmation therefore carries
  /// the decoder's own lag. Bar-level grading is what makes that acceptable: a bar
  /// is 3.4 s at this tempo, and `gradeChords` credits a bar on ANY confirmation
  /// inside it, so a late confirmation still credits the right bar. What it cannot
  /// tell is whether a change landed ON the bar line, which is why nothing here
  /// claims that.
  void _absorbChord(LiveFrame live, double start) {
    if (_calibrator != null || _chords.isEmpty) return;
    final decision = live.chordDecision;
    if (decision == null) return;
    final atUs =
        ((live.engineTimeSec - start) * 1e6).round() -
        _countIn.durationAt(_beatDuration).inMicroseconds;
    // Before bar 1 is the count-in: the learner is being counted in, not scored.
    if (atUs < 0) return;
    _chordDetections.add(
      DetectedChord(
        atUs: atUs,
        label: live.current?.label,
        isConfirmed: decision == RecognitionDecision.confirmed,
      ),
    );
  }

  /// Crossings per loop: two per beat, across however many bars the exercise
  /// repeats, with the chord cycle laid over them.
  List<bool> get _crossings {
    // While counting in — and through a demonstration, for the same reason over a
    // longer stretch — the hand swings through pure ghosts. That is our own model
    // applied honestly: the hand never stops, so the learner's arm is already
    // moving when bar 1 arrives instead of starting from rest.
    if (_demoPosition != null || _countInNumber != null) {
      return _countIn.ghostCrossings;
    }
    if (_calibrator != null) return _calibrationCrossings;
    final perBar = _assignment.grid.handCrossings;
    final bars = _chords.isEmpty ? 1 : _chords.length;
    final crossings = [for (var bar = 0; bar < bars; bar++) ...perBar];
    // A mode with NO arrow row gets all ghosts here as well, and this is the
    // difference between hiding the notation and hiding the hand. The swing itself
    // is not notation: at a given subdivision it is identical for every pattern, and
    // the learner has to make it either way. WHICH crossings strike IS the pattern —
    // so marking them on the pendulum would hand straight back what
    // `showsArrowRow: false` took away, and the ear rung could be passed by watching.
    if (!_assignment.mode.showsArrowRow) {
      return List<bool>.filled(crossings.length, false);
    }
    return crossings;
  }

  Duration get _beatDuration =>
      Duration(microseconds: (60000000 / _assignment.bpm).round());

  /// Microseconds of pre-roll the demonstration adds before the count-in.
  ///
  /// Zero for the three non-demonstrating modes, which is what keeps this change
  /// invisible to them: their bar 1 is still the count-in's end.
  int get _demoUs => _demonstration?.totalUs ?? 0;

  /// [_position] with the demonstration subtracted — the clock the count-in and
  /// the exercise both run on. One definition, because two would be two places
  /// for bar 1 to be.
  Duration? get _countInClock =>
      _position == null ? null : _position! - Duration(microseconds: _demoUs);

  /// Where the DEMONSTRATION stands, or null once it is over (and always null for
  /// a mode that does not demonstrate).
  Duration? get _demoPosition {
    final position = _position;
    final demonstration = _demonstration;
    if (position == null || demonstration == null) return null;
    if (position.inMicroseconds >= demonstration.totalUs) return null;
    return position;
  }

  /// Where the exercise itself stands: negative for the whole pre-roll, zero
  /// exactly at bar 1 beat 1.
  Duration? get _exercisePosition => _countInClock == null
      ? null
      : _countIn.exercisePosition(
          position: _countInClock!,
          beatDuration: _beatDuration,
        );

  /// The number being counted, or null while demonstrating and once the exercise
  /// has begun.
  int? get _countInNumber {
    final clock = _countInClock;
    if (clock == null || clock.isNegative) return null;
    return _countIn.numberAt(position: clock, beatDuration: _beatDuration);
  }

  /// While calibrating, the hand strikes on EVERY beat: the learner is asked for
  /// one reference stroke per beat, so every beat yields a sample.
  List<bool> get _calibrationCrossings => [
    for (var beat = 0; beat < _assignment.grid.beatsPerBar * 2; beat++) ...[
      true,
      false,
    ],
  ];

  /// Whether the scored attempt has begun — the WHOLE pre-roll behind us, the
  /// demonstration included.
  ///
  /// Named once because three places ask it, and before the demonstration existed
  /// they each asked it as "the count-in is over". That phrasing is now wrong by one
  /// phase, and a screen that thought the attempt had started during a demonstration
  /// would ask for a chord nobody was meant to be playing yet.
  bool get _attemptRunning => _demoPosition == null && _countInNumber == null;

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
    final askedChord = (_chords.isEmpty || !_attemptRunning)
        ? null
        : _chords[barIndex];
    final fretting = _frettingFor(live, askedChord);

    return Scaffold(
      appBar: AppBar(
        // The RUNG's name, not a generic "Strumming". Opening step 6 from the
        // ladder and landing on a screen indistinguishable from step 2 leaves the
        // learner unable to tell whether the tap did what it offered.
        title: Text(curriculumMissionName(l10n, _mission.missionId)),
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
              // The notation. Withheld entirely for a mode that declares no arrow
              // row: it is the whole content of the pattern, and the ear rung exists
              // so the pillar cannot be passed by reading.
              if (_assignment.mode.showsArrowRow)
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
                      activeSlotIndex: (bar == barIndex && _attemptRunning)
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
    final demonstration = _demonstration;
    final demoPosition = _demoPosition;
    if (demonstration != null && demoPosition != null) {
      // Two states, and the silence needs its own words. A screen that showed
      // nothing through the gap bar would read as stalled at exactly the moment the
      // learner has to decide to start playing.
      final demoBar = demonstration.barNumberAt(demoPosition.inMicroseconds);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            demoBar == null
                ? l10n.curriculumNowYouLabel
                : l10n.curriculumListenLabel,
            style: text.labelMedium?.copyWith(color: colors.textSecondary),
          ),
          Text(
            key: demonstrationLabelKey,
            demoBar == null
                ? l10n.curriculumNowYouLabel
                : l10n.curriculumListenBarOf(demoBar, demonstration.bars),
            style: text.titleMedium?.copyWith(
              color: demoBar == null ? colors.brand : colors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
    }
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          bar == null
              ? (_finished ? l10n.curriculumAttemptDone : '')
              : l10n.curriculumBarOf(bar, _attemptBars),
          style: text.labelLarge?.copyWith(
            color: _finished ? colors.textSecondary : colors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        // Said once, in the first scored bar, where the learner notices the click
        // stopping and would otherwise conclude the metronome broke. Shown only
        // when there WAS a click to stop: a muted metronome has nothing to explain.
        if (bar == 1 &&
            !_finished &&
            _pulsePhase == CurriculumPulsePhase.scoredAttempt &&
            !ref.watch(metronomeMutedProvider))
          Text(
            l10n.curriculumClickStopsWhileListening,
            style: text.labelSmall?.copyWith(color: colors.textSecondary),
          ),
      ],
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
          ..._chordLines(context, l10n, colors),
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

  /// What the chord side of the run says, or an honest statement that it says
  /// nothing yet.
  ///
  /// Reported SEPARATELY from the direction lines, never blended into one
  /// "accuracy": a learner whose shape is clean but whose hand stalls, and one
  /// whose hand is even but whose fingers are wrong, need opposite advice, and a
  /// single number would hide which of the two they are.
  List<Widget> _chordLines(
    BuildContext context,
    AppLocalizations l10n,
    SsColorScheme colors,
  ) {
    final attempt = _gradeChordAttempt();
    if (attempt == null) return const [];
    final label = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: colors.textSecondary);
    final accuracy = attempt.accuracy;
    if (!attempt.isReportable || accuracy == null) {
      // Rule 4's sibling: what is not measured says so, and it costs the learner
      // nothing. Not a score of zero, which would read as "your chord was wrong".
      return [Text(l10n.curriculumChordTooLittle, style: label)];
    }
    final heardInstead = attempt.heardInstead;
    return [
      Text(
        l10n.curriculumChordAccuracy((accuracy * 100).round()),
        style: label,
      ),
      // Naming the shape the recogniser actually heard is the actionable half;
      // "wrong chord" on its own tells the learner nothing to change.
      if (heardInstead.isNotEmpty)
        Text(
          l10n.curriculumChordHeardInstead(heardInstead.first),
          style: label,
        ),
    ];
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
