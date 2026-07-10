import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../chords/widgets/chord_diagram.dart';
import '../../live/model/strum.dart';
import '../../live/providers/live_providers.dart';
import '../../progress/model/practice_entry.dart';
import '../../progress/providers/practice_log_provider.dart';
import '../../settings/providers/input_latency_provider.dart';
import '../../settings/providers/visual_latency_provider.dart';
import '../../streak/providers/streak_provider.dart';
import '../../streak/streak_logic.dart';
import '../providers/lesson_progress_provider.dart';
import '../audio/chord_audio.dart';
import '../audio/metronome.dart';
import '../providers/metronome_pref_provider.dart';
import '../lesson_scorer.dart';
import '../lesson_timing.dart';
import '../model/lesson.dart';
import '../widgets/hit_burst.dart';
import '../widgets/lesson_highway.dart';
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
  static const int _countInBeats = 4;

  late final Ticker _ticker;
  final Metronome _metronome = Metronome();
  final Backing _backing = Backing();
  double _elapsedSec = 0;
  double _accumSec = 0;
  double _prevPlayhead = 0;
  bool _playing = false;
  bool _jam = false; // jam mode: chord backing, scoring off (avoids mic conflict)
  bool _easy = false; // beginner cut: on-beat down-strokes only
  double _speed = 1.0; // practice-tempo multiplier

  static const _speeds = [0.5, 0.75, 1.0];

  /// The lesson actually being played — simplified to on-beat down-strokes in
  /// Easy mode. Same id/tempo/length, so timing + scoring stay consistent.
  Lesson get _lesson => _easy ? widget.lesson.simplified : widget.lesson;

  /// Effective tempo after the practice-speed multiplier.
  double get _bpm => _lesson.bpm * _speed;

  LessonScorer? _scorer;
  ScoreSnapshot? _score;
  final List<HitBurst> _bursts = []; // strike-line spark bursts (juice)
  int _prevMultiplier = 1; // to detect a combo-multiplier milestone
  static const double _highwayHeight = 140;
  static const double _strikeX = 68; // must match LessonHighway.strikeX default
  int _lastSeq = 0;
  ProviderSubscription<AsyncValue<dynamic>>? _frameSub;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _frameSub?.close();
    _ticker.dispose();
    _metronome.dispose();
    _backing.dispose();
    super.dispose();
  }

  double get _playhead =>
      LessonTiming.playhead(_elapsedSec, _bpm, _countInBeats);

  /// Playhead used for DRAWING the highway: shifted by the calibrated
  /// audio↔display skew (tap-vs-click − tap-vs-flash) so a card crosses the
  /// strike line exactly when its beat is HEARD (chunk 016b P3). If audio
  /// lags the display (skew > 0, e.g. Bluetooth), the visuals are drawn that
  /// much later. Scoring/metronome keep the true playhead.
  double get _drawnPlayhead {
    final skewSec = (ref.read(inputLatencyProvider) -
            ref.read(visualLatencyProvider)) /
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
    if (LessonTiming.isFinished(
        now, _lesson.totalBeats, _lesson.beatsPerBar)) {
      _finish();
    }
  }

  void _onFrame(AsyncValue<dynamic>? _, AsyncValue<dynamic> next) {
    final frame = next.asData?.value;
    if (frame == null || _scorer == null) return;
    // A new discrete strum → score it against the nearest lesson event.
    if (frame.strumSeq > _lastSeq && frame.latestStrum != null) {
      _lastSeq = frame.strumSeq as int;
      // Only buzz when the strum actually resolved an event — a stray strum
      // with no event in range returns null and must NOT re-fire the previous
      // verdict's haptic.
      final result =
          _scorer!.registerStrum(frame.latestStrum.direction, _elapsedSec);
      final snap = _scorer!.snapshot();
      if (result != null) _fireHaptic(result, snap.lastTiming);
      // A clean hit throws a spark burst in the stroke's colour at the strike
      // line — the visible celebration that turns "a diagram" into "a game".
      if (result == HitResult.hit) {
        _emitBurst(frame.latestStrum.direction as StrumDirection, snap.lastTiming);
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
    // hears (and grades) the app's own accompaniment.
    if (!_jam) {
      _scorer ??= LessonScorer(_lesson,
          countInBeats: _countInBeats,
          bpm: _bpm,
          inputLatencySec: ref.read(inputLatencyProvider) / 1000);
      _frameSub ??= ref.listenManual(liveFrameProvider, _onFrame);
    }
    _prevPlayhead = _playhead; // don't re-click beats already passed
    setState(() => _playing = true);
    _ticker.start();
  }

  void _pause() {
    if (!_playing) return;
    _accumSec = _elapsedSec;
    _ticker.stop();
    setState(() => _playing = false);
  }

  void _restart() {
    _ticker.stop();
    _lastSeq = 0;
    if (_jam) {
      _scorer = null;
    } else {
      _scorer = LessonScorer(_lesson,
          countInBeats: _countInBeats,
          bpm: _bpm,
          inputLatencySec: ref.read(inputLatencyProvider) / 1000);
      _frameSub ??= ref.listenManual(liveFrameProvider, _onFrame);
    }
    _prevPlayhead = -_countInBeats.toDouble();
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
    _pause();
    _scorer?.finalize();
    final snap = _scorer?.snapshot();
    setState(() => _score = snap);
    // Playing a lesson counts as practice, and its score updates the library.
    if ((snap?.total ?? 0) > 0) {
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
      ref.read(practiceLogProvider.notifier).record(PracticeEntry(
            day: StreakLogic.epochDayOf(DateTime.now()),
            source: PracticeSource.learn,
            seconds: _elapsedSec.round(),
            strokes: snap!.total,
            chords: widget.lesson.chordSequence.toSet().length,
            directionAccuracy: snap.accuracy,
          ));
    }
    if (mounted && snap != null) _showSummary(snap);
  }

  void _showSummary(ScoreSnapshot snap) {
    final l10n = AppLocalizations.of(context);
    final passed = _scorer?.passed ?? false;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(passed ? l10n.learnPassed : l10n.learnKeepGoing),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${(snap.accuracy * 100).round()}%',
                style: const TextStyle(
                    fontFamily: 'Montserrat',
                    fontWeight: FontWeight.w900,
                    fontSize: 48,
                    color: AppColors.primary)),
            if (snap.score > 0)
              Text('${snap.score} ${l10n.learnScore}'
                  '${snap.perfect > 0 ? ' · ${snap.perfect} ${l10n.learnPerfect}' : ''}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: AppColors.primary)),
            Text(l10n.learnScoreLine(snap.hits, snap.total, snap.maxCombo)),
            if (snap.hasChords)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    '${l10n.learnChords}: ${(snap.chordAccuracy * 100).round()}%'),
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
              Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => LessonScorePreviewScreen(
                  lesson: widget.lesson,
                  accuracy: snap.accuracy,
                  maxCombo: snap.maxCombo,
                  hits: snap.hits,
                  total: snap.total,
                ),
              ));
            },
            icon: const Icon(Icons.ios_share, size: 18),
            label: Text(l10n.actionShare),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _restart();
            },
            child: Text(l10n.learnPlayAgain),
          ),
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
    _bursts.add(HitBurst(
      startSec: _elapsedSec,
      color: dir == StrumDirection.down
          ? AppColors.primary
          : AppColors.confidenceHigh,
      strength: strength,
    ));
  }

  /// A bigger, longer golden burst when the combo multiplier steps up.
  void _emitMilestone() {
    _bursts.add(HitBurst(
      startSec: _elapsedSec,
      color: AppColors.primary,
      strength: 1.4,
      count: 26,
      lifeSec: 0.6,
    ));
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
            color: _easy ? AppColors.primary : null,
            tooltip: l10n.learnEasyMode,
            onPressed: () {
              setState(() => _easy = !_easy);
              if (_playing || _score != null) _restart();
            },
          ),
          IconButton(
            icon: const Icon(Icons.music_note),
            color: _jam ? AppColors.primary : null,
            tooltip: l10n.learnJam,
            onPressed: () {
              setState(() => _jam = !_jam);
              if (_playing) _restart();
            },
          ),
          IconButton(
            icon: Icon(ref.watch(metronomeMutedProvider)
                ? Icons.volume_off
                : Icons.volume_up),
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
          child: Column(
            children: [
              if (score != null)
                _ScoreHud(score: score)
              else if (chordsUsed.isNotEmpty)
                Text('${l10n.learnChords}: $chordsUsed',
                    style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Stack(
                alignment: Alignment.center,
                children: [
                  LessonHighway(
                      lesson: lesson,
                      playheadBeat: _drawnPlayhead,
                      height: _highwayHeight,
                      strikeX: _strikeX),
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
                                  _strikeX, _highwayHeight / 2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (countIn != null) CountInOverlay(number: countIn),
                  if (countIn == null && score?.lastResult != null)
                    _FeedbackFlash(
                        result: score!.lastResult!, timing: score.lastTiming),
                ],
              ),
              const SizedBox(height: 6),
              // How to fret the current chord (a beginner can't play what they
              // can't finger). Reserves height so the layout doesn't jump.
              SizedBox(
                height: 94,
                child: Center(child: ChordDiagram(label: _activeChord(), size: 66)),
              ),
              const SizedBox(height: 6),
              Text('${_bpm.round()} BPM',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${l10n.learnSpeed}  ',
                      style: Theme.of(context).textTheme.bodySmall),
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
              const Spacer(),
              FilledButton.icon(
                onPressed: _toggle,
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow, size: 24),
                label: Text(_playing ? l10n.learnPause : l10n.learnPlay),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
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
    // Combo shows its live multiplier (the reward chain) once it kicks in — a
    // 🔥 signals "you're on a hot streak".
    final combo = score.multiplier > 1
        ? '🔥 ${score.combo} ×${score.multiplier}'
        : '${score.combo}';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _stat('${score.score}', l10n.learnScore),
        _stat(combo, l10n.learnCombo),
        _stat('${(score.accuracy * 100).round()}%', l10n.learnAccuracy),
      ],
    );
  }

  Widget _stat(String value, String label) => Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  color: AppColors.primary)),
          Text(label,
              style: const TextStyle(fontSize: 10, letterSpacing: 0.5)),
        ],
      );
}

class _FeedbackFlash extends StatelessWidget {
  const _FeedbackFlash({required this.result, this.timing});
  final HitResult result;
  final Timing? timing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Hits carry a timing verdict (PERFECT/GOOD/EARLY/LATE); wrong/miss stay
    // gentle (safe-failure). Early/late add an arrow hint at which side.
    final (text, color) = switch (result) {
      HitResult.hit => switch (timing) {
          Timing.perfect => (l10n.learnPerfect, AppColors.confidenceHigh),
          Timing.good => (l10n.learnGood, AppColors.confidenceHigh),
          Timing.early => ('${l10n.learnEarly} ⟵', AppColors.confidenceMid),
          Timing.late => ('⟶ ${l10n.learnLate}', AppColors.confidenceMid),
          null => (l10n.learnHit, AppColors.confidenceHigh),
        },
      HitResult.wrongDirection => (l10n.learnWrongWay, AppColors.confidenceMid),
      HitResult.missed => (l10n.learnMiss, AppColors.confidenceLow),
    };
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text,
            style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: 16, color: color)),
      ),
    );
  }
}
