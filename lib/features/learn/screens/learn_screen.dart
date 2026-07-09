import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../live/providers/live_providers.dart';
import '../../streak/providers/streak_provider.dart';
import '../lesson_scorer.dart';
import '../lesson_timing.dart';
import '../model/lesson.dart';
import '../widgets/lesson_highway.dart';

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
  double _elapsedSec = 0;
  double _accumSec = 0;
  bool _playing = false;

  LessonScorer? _scorer;
  ScoreSnapshot? _score;
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
    super.dispose();
  }

  double get _playhead =>
      LessonTiming.playhead(_elapsedSec, widget.lesson.bpm, _countInBeats);

  void _onTick(Duration elapsed) {
    setState(() {
      _elapsedSec = _accumSec + elapsed.inMicroseconds / 1e6;
      _scorer?.advance(_elapsedSec);
      _score = _scorer?.snapshot();
    });
    if (LessonTiming.isFinished(
        _playhead, widget.lesson.totalBeats, widget.lesson.beatsPerBar)) {
      _finish();
    }
  }

  void _onFrame(AsyncValue<dynamic>? _, AsyncValue<dynamic> next) {
    final frame = next.asData?.value;
    if (frame == null || _scorer == null) return;
    // A new discrete strum → score it against the nearest lesson event.
    if (frame.strumSeq > _lastSeq && frame.latestStrum != null) {
      _lastSeq = frame.strumSeq as int;
      _scorer!.registerStrum(frame.latestStrum.direction, _elapsedSec);
      setState(() => _score = _scorer!.snapshot());
    }
  }

  void _play() {
    if (_playing) return;
    _scorer ??= LessonScorer(widget.lesson, countInBeats: _countInBeats);
    // Listen to the real mic/DSP stream only while playing (starts the engine).
    _frameSub ??= ref.listenManual(liveFrameProvider, _onFrame);
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
    _scorer = LessonScorer(widget.lesson, countInBeats: _countInBeats);
    _frameSub ??= ref.listenManual(liveFrameProvider, _onFrame);
    setState(() {
      _accumSec = 0;
      _elapsedSec = 0;
      _score = null;
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
    // Playing a lesson counts as practice.
    if ((snap?.total ?? 0) > 0) {
      ref.read(streakProvider.notifier).recordPracticeToday();
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
            Text(l10n.learnScoreLine(snap.hits, snap.total, snap.maxCombo)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.learnDone),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lesson = widget.lesson;
    final countIn = LessonTiming.countInNumber(_playhead, _countInBeats);
    final chordsUsed = lesson.chordSequence.join(' · ');
    final score = _score;

    return Scaffold(
      appBar: AppBar(
        title: Text(lesson.name),
        actions: [
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
                  LessonHighway(lesson: lesson, playheadBeat: _playhead),
                  if (countIn != null) CountInOverlay(number: countIn),
                  if (countIn == null && score?.lastResult != null)
                    _FeedbackFlash(result: score!.lastResult!),
                ],
              ),
              const SizedBox(height: 8),
              Text('${lesson.bpm.round()} BPM',
                  style: Theme.of(context).textTheme.bodySmall),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _stat('${(score.accuracy * 100).round()}%', l10n.learnAccuracy),
        _stat('${score.combo}', l10n.learnCombo),
        _stat('${score.hits}/${score.total}', l10n.learnHits),
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
  const _FeedbackFlash({required this.result});
  final HitResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (text, color) = switch (result) {
      HitResult.hit => (l10n.learnHit, AppColors.confidenceHigh),
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
