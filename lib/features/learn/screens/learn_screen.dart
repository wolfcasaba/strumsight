import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/config/app_config.dart';
import '../../../core/design_system/public.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../chords/public.dart';
import '../../../core/music/strum.dart';
import '../../live/public.dart';
import '../../progress/public.dart';
import 'package:intl/intl.dart';

import '../../practice/public.dart' hide PracticeSource;
import '../../share/public.dart';
import '../../settings/public.dart';
import '../../streak/public.dart';
import '../providers/lesson_progress_provider.dart';
import '../providers/practice_speed_provider.dart';
import '../audio/chord_audio.dart';
import '../audio/metronome.dart';
import '../providers/metronome_pref_provider.dart';
import '../adapter/lesson_v2_scoring.dart';
import '../lesson_scorer.dart';
import '../lesson_timing.dart';
import '../model/lesson.dart';
import '../widgets/hit_burst.dart';
import '../widgets/lesson_highway.dart';
import '../widgets/wrapped_prompt.dart';
import 'lesson_score_preview_screen.dart';

/// The play-along player: a [Lesson]'s chord + ↓/↑ strokes scroll toward the
/// strike line in tempo (with a count-in), and — once playing — the real mic/DSP
/// scores each stroke on the right direction + timing (RAG chunk 014). Starts
/// paused so the animation is deterministic until the user taps play.
class LearnScreen extends ConsumerStatefulWidget {
  const LearnScreen({super.key, required this.lesson});

  final Lesson lesson;

  @override
  ConsumerState<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends ConsumerState<LearnScreen>
    with SingleTickerProviderStateMixin {
  /// One full bar of the lesson's own metre (round 111): a 3/4 waltz counts
  /// in 1-2-3 — a fixed "1-2-3-4" would misalign the player's inner clock.
  int get _countInBeats => _lesson.beatsPerBar;

  late final Ticker _ticker;
  final Metronome _metronome = Metronome();
  final Backing _backing = Backing();
  double _elapsedSec = 0;
  double _accumSec = 0;
  double _prevPlayhead = 0;
  bool _playing = false;
  bool _jam =
      false; // jam mode: chord backing, scoring off (avoids mic conflict)
  bool _easy = false; // beginner cut: on-beat down-strokes only
  double _speed = 1.0; // practice-tempo multiplier (restored in initState)

  // One source of truth for the selectable speeds (shared with the persisted
  // practiceSpeedProvider so the chips and the stored value can't drift).
  static const _speeds = PracticeSpeedController.options;

  /// The lesson actually being played — simplified to on-beat down-strokes in
  /// Easy mode. Same id/tempo/length, so timing + scoring stay consistent.
  /// Cached: `_lesson` is read on every ticker frame, and `simplified`
  /// rebuilds its event list on each call (round 114).
  Lesson? _simplifiedCache;
  Lesson get _lesson =>
      _easy ? (_simplifiedCache ??= widget.lesson.simplified) : widget.lesson;

  /// Effective tempo after the practice-speed multiplier.
  double get _bpm => _lesson.bpm * _speed;

  LessonScorer? _scorer;
  ScoreSnapshot? _score;
  final List<HitBurst> _bursts = []; // strike-line spark bursts (juice)
  int _prevMultiplier = 1; // to detect a combo-multiplier milestone
  static const double _highwayHeight = 140;
  static const double _strikeX = 68; // must match LessonHighway.strikeX default
  int _lastSeq = 0;
  final List<StrumObservation> _v2Observations = [];
  ProviderSubscription<AsyncValue<dynamic>>? _frameSub;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    // Restore the learner's preferred practice speed (round 132) — read once
    // in initState so entering a lesson doesn't fight a mid-play rebuild.
    _speed = ref.read(practiceSpeedProvider);
  }

  @override
  void dispose() {
    // Clear the expected-chord hint — a lesson bias left on the engine would
    // silently skew free-play Live detection afterwards (round 137). Uses the
    // captured engine reference: `ref` is not reliable while the tree is
    // being finalized.
    if (_sentExpected != null) {
      _hintedEngine?.setExpectedChord(null);
    }
    _frameSub?.close();
    _ticker.dispose();
    _metronome.dispose();
    _backing.dispose();
    super.dispose();
  }

  /// Push the current lesson target chord to the detector when it changes
  /// (the chunk-016 expected-target prior). Jam mode and a finished/idle
  /// screen hint nothing.
  String? _sentExpected;
  StrumEngine? _hintedEngine; // captured so dispose can clear without ref
  void _updateExpectedChord() {
    final active = !_jam && _scorer != null ? _activeChord() : '';
    final label = active.isEmpty ? null : active;
    if (label != _sentExpected) {
      _sentExpected = label;
      _hintedEngine = ref.read(strumEngineProvider);
      _hintedEngine!.setExpectedChord(label);
    }
  }

  double get _playhead =>
      LessonTiming.playhead(_elapsedSec, _bpm, _countInBeats);

  /// Playhead used for DRAWING the highway: shifted by the calibrated
  /// audio↔display skew (tap-vs-click − tap-vs-flash) so a card crosses the
  /// strike line exactly when its beat is HEARD (chunk 016b P3). If audio
  /// lags the display (skew > 0, e.g. Bluetooth), the visuals are drawn that
  /// much later. Scoring/metronome keep the true playhead.
  double get _drawnPlayhead {
    final skewSec =
        (ref.read(inputLatencyProvider) - ref.read(visualLatencyProvider)) /
        1000.0;
    return _playhead - skewSec * (_bpm / 60.0);
  }

  void _onTick(Duration elapsed) {
    setState(() {
      _elapsedSec = _accumSec + elapsed.inMicroseconds / 1e6;
      _scorer?.advance(_elapsedSec);
      _score = _scorer?.snapshot();
      _bursts.removeWhere((b) => b.isDone(_elapsedSec)); // prune faded sparks
    });
    // On every beat crossed since the last frame: click the metronome (accent on
    // downbeats), and in jam mode play the chord backing on each bar downbeat.
    final now = _playhead;
    final muted = ref.read(metronomeMutedProvider);
    for (final beat in LessonTiming.beatsCrossed(_prevPlayhead, now)) {
      final downbeat = beat % _lesson.beatsPerBar == 0;
      if (!muted) _metronome.tick(accent: downbeat);
      if (_jam && downbeat && beat >= 0) _backing.playChord(_activeChord());
    }
    _prevPlayhead = now;
    _updateExpectedChord();
    if (LessonTiming.isFinished(now, _lesson.totalBeats, _lesson.beatsPerBar)) {
      _finish();
    }
  }

  void _onFrame(AsyncValue<dynamic>? _, AsyncValue<dynamic> next) {
    final frame = next.asData?.value;
    if (frame == null || _scorer == null) return;
    // A new discrete strum → score it against the nearest lesson event.
    if (frame.strumSeq > _lastSeq && frame.latestStrum != null) {
      _lastSeq = frame.strumSeq as int;
      // De-jitter (r147): the frame arrives classify-delay + emit-cadence
      // after the attack; both instants ride the frame on the engine's own
      // sample clock, so subtracting their difference removes the 0–66 ms
      // cadence JITTER the constant latency calibration cannot. Bounded to
      // 0.5 s as a sanity guard; mocks without clocks (−1) skip correction.
      var at = _elapsedSec;
      final lag =
          (frame.engineTimeSec as double) - (frame.latestStrumTime as double);
      if (frame.engineTimeSec >= 0 &&
          frame.latestStrumTime >= 0 &&
          lag > 0 &&
          lag < 0.5) {
        at -= lag;
      }
      if (_migratedLearnEnabled) {
        _v2Observations.add(
          StrumObservation(
            at: Duration(
              microseconds: (at * Duration.microsecondsPerSecond).round(),
            ),
            sequence: _lastSeq,
            direction: frame.latestStrum.direction as StrumDirection,
            confidence: frame.latestStrum.confidence as double,
          ),
        );
      }
      // Only buzz when the strum actually resolved an event — a stray strum
      // with no event in range returns null and must NOT re-fire the previous
      // verdict's haptic.
      final result = _scorer!.registerStrum(frame.latestStrum.direction, at);
      final snap = _scorer!.snapshot();
      if (result != null) _fireHaptic(result, snap.lastTiming);
      // A clean hit throws a spark burst in the stroke's colour at the strike
      // line — the visible celebration that turns "a diagram" into "a game".
      if (result == HitResult.hit) {
        _emitBurst(
          frame.latestStrum.direction as StrumDirection,
          snap.lastTiming,
        );
        // Crossing a combo-multiplier tier (×2/×3/×4) fires a bigger, longer
        // golden fountain — the reward-chain milestone (chunk 016b P1).
        if (snap.multiplier > _prevMultiplier) _emitMilestone();
      }
      _prevMultiplier = snap.multiplier;
      setState(() => _score = snap);
    }
    // Track the detected chord for the (lenient, secondary) chord grade.
    final chord = frame.current?.label;
    _scorer!.observeChord(chord is String ? chord : '', _elapsedSec);
  }

  void _play() {
    if (_playing) return;
    // Jam mode plays a chord backing and turns scoring OFF, so the mic never
    // hears (and grades) the app's own accompaniment. Closing the frame
    // subscription actually releases the mic (autoDispose) — round 100.
    if (_jam) {
      _frameSub?.close();
      _frameSub = null;
    }
    if (!_jam) {
      _scorer ??= LessonScorer(
        _lesson,
        countInBeats: _countInBeats,
        bpm: _bpm,
        inputLatencySec: ref.read(inputLatencyProvider) / 1000,
      );
      _frameSub ??= ref.listenManual(liveFrameProvider, _onFrame);
    }
    _prevPlayhead = _playhead; // don't re-click beats already passed
    _updateExpectedChord(); // hint the first target during the count-in
    setState(() => _playing = true);
    _ticker.start();
  }

  void _pause() {
    if (!_playing) return;
    // V2 path: close the live-frame subscription the moment the user pauses,
    // so the mic drops to silent (A9). The legacy path leaves _frameSub open
    // — that is the original Learn behaviour, untouched (Döntés 8).
    if (_migratedLearnEnabled) {
      _frameSub?.close();
      _frameSub = null;
    }
    _accumSec = _elapsedSec;
    _ticker.stop();
    setState(() => _playing = false);
  }

  void _restart() {
    _ticker.stop();
    _lastSeq = 0;
    _v2Observations.clear();
    if (_jam) {
      _scorer = null;
      // Release the mic — jam must not idle behind the backing (round 100).
      _frameSub?.close();
      _frameSub = null;
    } else {
      _scorer = LessonScorer(
        _lesson,
        countInBeats: _countInBeats,
        bpm: _bpm,
        inputLatencySec: ref.read(inputLatencyProvider) / 1000,
      );
      _frameSub ??= ref.listenManual(liveFrameProvider, _onFrame);
    }
    _prevPlayhead = -_countInBeats.toDouble();
    _updateExpectedChord();
    setState(() {
      _accumSec = 0;
      _elapsedSec = 0;
      _score = null;
      // Clear leftover sparks — the clock resets to 0 while bursts from the
      // finished run still carry startSec far in the "future", so an un-cleared
      // burst would re-fire as a phantom spark when the replay clock climbs
      // back to its start time.
      _bursts.clear();
      _prevMultiplier = 1;
      _playing = true;
    });
    _ticker.start();
  }

  Future<void> _finish() async {
    if (!_playing) return;
    // V2-migrated Learn closes the capture subscription before pausing so the
    // mic gap (A9) stays structurally closed on the migrated path; the legacy
    // path keeps the existing `_pause()` semantics — every §2 Learn test stays
    // green by construction.
    if (_migratedLearnEnabled) {
      _frameSub?.close();
      _frameSub = null;
    }
    _pause();
    // The run is over — stop biasing detection toward the last chord.
    _sentExpected = null;
    _hintedEngine?.setExpectedChord(null);
    _scorer?.finalize();
    final snap = _scorer?.snapshot();
    final directionAccuracy = _migratedLearnEnabled
        ? scoreLessonV2(
            _lesson,
            _v2Observations,
            inputLatency: Duration(
              milliseconds: ref.read(inputLatencyProvider),
            ),
            bpm: _bpm,
          )
        : null;
    setState(() => _score = snap);
    // Playing a lesson counts as practice, and its score updates the library.
    if ((snap?.total ?? 0) > 0) {
      if (_migratedLearnEnabled) {
        // V2 path: route through the canonical recording use case so the
        // streak gate, daily-goal ring and V1 entry shape stay identical to
        // every other Practice call site (Döntés 4 + 5). Lesson-progress
        // stays under the "best wins" controller (Easy never overwrites,
        // Döntés 6).
        await _recordLearnMomentV2(snap!, directionAccuracy!);
      } else {
        // Legacy path (today, OFF) — UNCHANGED. The current behaviour is the
        // contract; every Learn test in §2 stays green by construction.
        ref.read(streakProvider.notifier).recordPracticeToday();
        // Easy mode still counts as PRACTICE (streak + Progress), but does NOT
        // update the lesson's best-score/stars — those must reflect the FULL
        // lesson, not the simplified cut.
        if (!_easy) {
          ref
              .read(lessonProgressProvider.notifier)
              .record(widget.lesson.id, snap!.accuracy);
        }
        // Log for the Progress dashboard — Learn is the only source that scores
        // strum DIRECTION, so it carries the moat metric.
        ref
            .read(practiceLogProvider.notifier)
            .record(
              PracticeEntry(
                day: StreakLogic.epochDayOf(DateTime.now()),
                source: PracticeSource.learn,
                seconds: _elapsedSec.round(),
                strokes: snap!.total,
                chords: widget.lesson.chordSequence.toSet().length,
                directionAccuracy: snap.accuracy,
              ),
            );
      }
    }
    if (mounted && snap != null) _showSummary(snap);
  }

  /// Whether the V2-migrated Learn path is active for this build. The flag
  /// is compile-time, so caching it in a getter keeps the hot paths
  /// branch-free.
  bool get _migratedLearnEnabled =>
      ref.read(appConfigProvider).flags.migratedLearnEnabled;

  /// V2-migrated Learn post-finish recording (ADR 0085 Döntés 4 + 5 + 6).
  ///
  /// Uses the canonical [PracticeSessionRecording] use case so the streak
  /// gate, the daily-goal ring and the V1 entry shape stay identical to
  /// every other Practice call site. Lesson-progress still goes through the
  /// existing "best wins" controller (Easy-mode-rewrite-prevention, A6).
  Future<void> _recordLearnMomentV2(
    ScoreSnapshot snap,
    double directionAccuracy,
  ) async {
    final now = DateTime.now();
    final recording = ref.read(practiceSessionRecordingProvider);
    final eligibilitySnap = SessionEligibilitySnapshot(
      // The V2 session's playingElapsed (== wall minus count-in minus pause
      // minus setup — A5); the Learn path reports it as the elapsed runner
      // seconds. Lessons clear the count-in/pause-free path so we reuse the
      // measured elapsed seconds.
      activeDuration: Duration(seconds: _elapsedSec.round()),
      resolvedRequiredTargets: 0,
      // Free-practice strums = total event counts; lessons always clear the
      // 8-strum threshold when they finish.
      freePracticeStrums: snap.total,
    );
    final outcome = await recording.record(
      PracticeRecordingRequest(
        lessonId: widget.lesson.id,
        eligibility: eligibilitySnap,
        // An active Learn run always passes the coarse `eligible` flag —
        // the predicate decides whether it qualifies (A4).
        eligible: true,
        activeDuration: Duration(seconds: _elapsedSec.round()),
        // V1 stores the FULL elapsed seconds (count-in included); the
        // daily-goal budget counts only the active time via the aggregator
        // (A5 + A10 — V1 log bájtra érintetlen).
        elapsedSeconds: _elapsedSec.round(),
        strokes: snap.total,
        chords: widget.lesson.chordSequence.toSet().length,
        directionAccuracy: directionAccuracy,
        finishedAt: now,
      ),
    );
    if (!_easy && outcome.loggedEntry != null) {
      ref
          .read(lessonProgressProvider.notifier)
          .record(widget.lesson.id, directionAccuracy);
    }
  }

  void _openWrapped() {
    final stats = PracticeStats(ref.read(practiceLogProvider));
    final nowDate = DateTime.now();
    final today = StreakLogic.epochDayOf(nowDate);
    final recap = WeeklyRecap.fromEntries(
      stats.entries,
      today: today,
      streak: ref.read(streakProvider).current,
    );
    final start = nowDate.subtract(const Duration(days: 6));
    final label =
        '${DateFormat.MMMd().format(start)} – '
        '${DateFormat.MMMd().format(nowDate)}';
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            WrappedPreviewScreen(recap: recap, weekLabel: label, today: today),
      ),
    );
  }

  void _showSummary(ScoreSnapshot snap) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    final passed = _scorer?.passed ?? false;
    // The finish→next retention loop (round 92): a pass offers the curriculum
    // successor; a fail keeps the focus on "Play again". One-off lessons
    // (daily challenge, Analyze imports) have no successor. Easy-mode passes
    // don't advance the curriculum (they don't record progress either —
    // round 100 review), so they get no CTA.
    final next = passed && !_easy ? Lessons.nextAfter(widget.lesson.id) : null;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(passed ? l10n.learnPassed : l10n.learnKeepGoing),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${(snap.accuracy * 100).round()}%',
              style: typography.displayScore.copyWith(color: colors.brand),
            ),
            if (snap.score > 0)
              Text(
                '${snap.score} ${l10n.learnScore}'
                '${snap.perfect > 0 ? ' · ${snap.perfect} ${l10n.learnPerfect}' : ''}',
                style: typography.labelLarge.copyWith(color: colors.brand),
              ),
            Text(l10n.learnScoreLine(snap.hits, snap.total, snap.maxCombo)),
            if (snap.hasChords)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${l10n.learnChords}: ${(snap.chordAccuracy * 100).round()}%',
                ),
              ),
            // A good run is the moment of pride — offer the weekly Wrapped
            // (chunk 017 rec #5's auto-prompt half, r153). Quiet inline row.
            WrappedPrompt(
              accuracy: snap.accuracy,
              onOpen: () {
                Navigator.of(ctx).pop();
                _openWrapped();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.learnDone),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LessonScorePreviewScreen(
                    lesson: widget.lesson,
                    accuracy: snap.accuracy,
                    maxCombo: snap.maxCombo,
                    hits: snap.hits,
                    total: snap.total,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.ios_share, size: 18),
            label: Text(l10n.actionShare),
          ),
          if (next == null)
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _restart();
              },
              child: Text(l10n.learnPlayAgain),
            )
          else ...[
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _restart();
              },
              child: Text(l10n.learnPlayAgain),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => LearnScreen(lesson: next),
                  ),
                );
              },
              child: Text(l10n.learnNextLesson),
            ),
          ],
        ],
      ),
    );
  }

  void _toggle() => _playing ? _pause() : _play();

  /// Fire a spark burst at the strike line in the stroke's colour (copper =
  /// down, green = up), sized by timing quality (PERFECT bursts biggest).
  void _emitBurst(StrumDirection dir, Timing? timing) {
    final strength = switch (timing) {
      Timing.perfect => 1.0,
      Timing.good => 0.72,
      Timing.early || Timing.late => 0.45,
      null => 0.6,
    };
    _bursts.add(
      HitBurst(
        startSec: _elapsedSec,
        color: dir == StrumDirection.down
            ? AppColors.primary
            : AppColors.confidenceHigh,
        strength: strength,
      ),
    );
  }

  /// A bigger, longer golden burst when the combo multiplier steps up.
  void _emitMilestone() {
    _bursts.add(
      HitBurst(
        startSec: _elapsedSec,
        color: AppColors.primary,
        strength: 1.4,
        count: 26,
        lifeSec: 0.6,
      ),
    );
  }

  /// Tactile confirmation aligned to the strum (chunk 016b juice): a firmer tap
  /// for a PERFECT hit, a light one for any other hit, a gentle selection tick
  /// for a wrong direction. Misses stay silent — failure should feel SAFE, not
  /// punished (Duolingo principle). Haptics are best-effort/no-op on desktop.
  void _fireHaptic(HitResult? result, Timing? timing) {
    switch (result) {
      case HitResult.hit:
        if (timing == Timing.perfect) {
          HapticFeedback.mediumImpact();
        } else {
          HapticFeedback.lightImpact();
        }
      case HitResult.wrongDirection:
        HapticFeedback.selectionClick();
      case HitResult.missed:
      case null:
        break;
    }
  }

  /// The chord to fret right now: the most recent event chord at/before the
  /// playhead (falling back to the first chord before the lesson starts).
  String _activeChord() {
    var chord = '';
    for (final e in _lesson.events) {
      if (e.chord.isEmpty) continue;
      if (e.beat <= _playhead + 0.25) {
        chord = e.chord;
      } else {
        if (chord.isEmpty) chord = e.chord; // pre-roll: show the first chord
        break;
      }
    }
    return chord;
  }

  void _setSpeed(double s) {
    if (s == _speed) return;
    _speed = s;
    ref.read(practiceSpeedProvider.notifier).set(s); // remember it (round 132)
    // Restart so the new tempo applies cleanly (playhead maths depends on it).
    if (_playing || (_score != null)) {
      _restart();
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    final lesson = _lesson;
    final countIn = LessonTiming.countInNumber(_playhead, _countInBeats);
    final chordsUsed = lesson.chordSequence.join(' · ');
    final score = _score;

    return Scaffold(
      appBar: AppBar(
        title: Text(lesson.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.school_outlined),
            color: _easy ? colors.brand : null,
            tooltip: l10n.learnEasyMode,
            onPressed: () {
              setState(() => _easy = !_easy);
              if (_playing || _score != null) _restart();
            },
          ),
          IconButton(
            icon: const Icon(Icons.music_note),
            color: _jam ? colors.brand : null,
            tooltip: l10n.learnJam,
            onPressed: () {
              setState(() => _jam = !_jam);
              if (_playing) _restart();
            },
          ),
          IconButton(
            icon: Icon(
              ref.watch(metronomeMutedProvider)
                  ? Icons.volume_off
                  : Icons.volume_up,
            ),
            tooltip: l10n.learnMetronome,
            onPressed: () => ref.read(metronomeMutedProvider.notifier).toggle(),
          ),
          IconButton(
            icon: const Icon(Icons.replay),
            tooltip: l10n.learnRestart,
            onPressed: _restart,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          // Scroll only when the fixed content is taller than the viewport
          // (landscape phones); Spacers keep working when there is room.
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      if (score != null)
                        _ScoreHud(score: score)
                      else if (chordsUsed.isNotEmpty)
                        Text(
                          '${l10n.learnChords}: $chordsUsed',
                          style: typography.titleMedium.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      // Dynamic difficulty (016b P4, r154): OFFER a switch —
                      // down after a fail streak, up when Easy is aced. Quiet
                      // inline row; the player stays in charge, and switching
                      // restarts the run (which clears the signal).
                      if (_playing &&
                          !_easy &&
                          (_scorer?.suggestsEasier ?? false))
                        _DdBanner(
                          text: l10n.ddSuggestEasy,
                          action: l10n.ddSwitch,
                          onSwitch: () {
                            setState(() => _easy = true);
                            _restart();
                          },
                        )
                      else if (_playing &&
                          _easy &&
                          score != null &&
                          score.resolved >= 8 &&
                          score.accuracy >= 0.9)
                        _DdBanner(
                          text: l10n.ddSuggestFull,
                          action: l10n.ddSwitch,
                          onSwitch: () {
                            setState(() => _easy = false);
                            _restart();
                          },
                        ),
                      const Spacer(),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          LessonHighway(
                            lesson: lesson,
                            playheadBeat: _drawnPlayhead,
                            height: _highwayHeight,
                            strikeX: _strikeX,
                          ),
                          // Spark bursts drawn on their own layer so they don't
                          // repaint the lane; centred on the strike line.
                          if (_bursts.isNotEmpty)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: RepaintBoundary(
                                  child: CustomPaint(
                                    painter: HitBurstPainter(
                                      bursts: _bursts,
                                      nowSec: _elapsedSec,
                                      center: const Offset(
                                        _strikeX,
                                        _highwayHeight / 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (countIn != null) CountInOverlay(number: countIn),
                          if (countIn == null && score?.lastResult != null)
                            _FeedbackFlash(
                              result: score!.lastResult!,
                              timing: score.lastTiming,
                              expectedDirection: score.expectedDirection,
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // How to fret the current chord (a beginner can't play what they
                      // can't finger). Reserves height so the layout doesn't jump.
                      SizedBox(
                        height: 94,
                        child: Center(
                          child: ChordDiagram(label: _activeChord(), size: 66),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_bpm.round()} BPM',
                        style: typography.labelLarge.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // scaleDown: the chip row is wider than a 320-wide screen.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${l10n.learnSpeed}  ',
                              style: typography.labelLarge.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                            for (final s in _speeds) ...[
                              ChoiceChip(
                                label: Text('${(s * 100).round()}%'),
                                selected: _speed == s,
                                onSelected: (_) => _setSpeed(s),
                              ),
                              const SizedBox(width: 6),
                            ],
                          ],
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        height: 56,
                        child: SsButton(
                          label: _playing ? l10n.learnPause : l10n.learnPlay,
                          icon: _playing ? Icons.pause : Icons.play_arrow,
                          onPressed: _toggle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The quiet dynamic-difficulty offer row (016b P4): one line + one action,
/// never a modal — a struggling player gets a hand, not an interruption.
class _DdBanner extends StatelessWidget {
  const _DdBanner({
    required this.text,
    required this.action,
    required this.onSwitch,
  });

  final String text;
  final String action;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.school_outlined, size: 16, color: colors.info),
          const SizedBox(width: SsSpacing.space2),
          Flexible(
            child: Text(
              text,
              style: typography.labelLarge.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          SsButton(
            label: action,
            variant: SsButtonVariant.tertiary,
            onPressed: onSwitch,
          ),
        ],
      ),
    );
  }
}

class _ScoreHud extends StatelessWidget {
  const _ScoreHud({required this.score});
  final ScoreSnapshot score;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    // Combo shows its live multiplier (the reward chain) once it kicks in — a
    // 🔥 signals "you're on a hot streak".
    final combo = score.multiplier > 1
        ? '🔥 ${score.combo} ×${score.multiplier}'
        : '${score.combo}';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _stat(context, '${score.score}', l10n.learnScore, colors, typography),
        _stat(context, combo, l10n.learnCombo, colors, typography),
        _stat(
          context,
          '${(score.accuracy * 100).round()}%',
          l10n.learnAccuracy,
          colors,
          typography,
        ),
      ],
    );
  }

  Widget _stat(
    BuildContext context,
    String value,
    String label,
    SsColorScheme colors,
    SsTypography typography,
  ) => Column(
    children: [
      Text(value, style: typography.metricMedium.copyWith(color: colors.brand)),
      Text(
        label,
        style: typography.labelLarge.copyWith(color: colors.textSecondary),
      ),
    ],
  );
}

class _FeedbackFlash extends StatelessWidget {
  const _FeedbackFlash({
    required this.result,
    this.timing,
    this.expectedDirection,
  });
  final HitResult result;
  final Timing? timing;
  final StrumDirection? expectedDirection;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    // Hits carry a timing verdict (PERFECT/GOOD/EARLY/LATE); wrong/miss stay
    // gentle (safe-failure). Early/late add an arrow hint at which side.
    final (text, color) = switch (result) {
      HitResult.hit => switch (timing) {
        Timing.perfect => (l10n.learnPerfect, colors.confidenceHigh),
        Timing.good => (l10n.learnGood, colors.confidenceHigh),
        Timing.early => ('${l10n.learnEarly} ⟵', colors.confidenceMedium),
        Timing.late => ('⟶ ${l10n.learnLate}', colors.confidenceMedium),
        null => (l10n.learnHit, colors.confidenceHigh),
      },
      // The badge coaches: which way the stroke SHOULD have gone (016b P6).
      HitResult.wrongDirection => (
        switch (expectedDirection) {
          StrumDirection.down => '${l10n.learnWrongWay} ↓',
          StrumDirection.up => '${l10n.learnWrongWay} ↑',
          null => l10n.learnWrongWay,
        },
        colors.confidenceMedium,
      ),
      HitResult.missed => (l10n.learnMiss, colors.confidenceLow),
    };
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text, style: typography.titleMedium.copyWith(color: color)),
      ),
    );
  }
}
