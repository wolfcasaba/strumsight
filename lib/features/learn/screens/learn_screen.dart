import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../lesson_timing.dart';
import '../model/lesson.dart';
import '../widgets/lesson_highway.dart';

/// The play-along player: a [Lesson]'s chord + ↓/↑ strokes scroll toward the
/// strike line in tempo (with a count-in). Starts paused so the animation is
/// deterministic until the user taps play.
class LearnScreen extends StatefulWidget {
  const LearnScreen({super.key, required this.lesson});

  final Lesson lesson;

  @override
  State<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends State<LearnScreen>
    with SingleTickerProviderStateMixin {
  static const int _countInBeats = 4;

  late final Ticker _ticker;
  double _elapsedSec = 0; // effective play time (excludes paused spans)
  double _accumSec = 0; // play time banked before the current run
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  double get _playhead =>
      LessonTiming.playhead(_elapsedSec, widget.lesson.bpm, _countInBeats);

  void _onTick(Duration elapsed) {
    setState(() {
      _elapsedSec = _accumSec + elapsed.inMicroseconds / 1e6;
    });
    if (LessonTiming.isFinished(
        _playhead, widget.lesson.totalBeats, widget.lesson.beatsPerBar)) {
      _pause();
    }
  }

  void _play() {
    if (_playing) return;
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
    setState(() {
      _accumSec = 0;
      _elapsedSec = 0;
      _playing = true;
    });
    _ticker.start();
  }

  void _toggle() => _playing ? _pause() : _play();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lesson = widget.lesson;
    final countIn = LessonTiming.countInNumber(_playhead, _countInBeats);
    final chordsUsed = lesson.chordSequence.join(' · ');

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
              if (chordsUsed.isNotEmpty)
                Text('${l10n.learnChords}: $chordsUsed',
                    style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Stack(
                alignment: Alignment.center,
                children: [
                  LessonHighway(lesson: lesson, playheadBeat: _playhead),
                  if (countIn != null) CountInOverlay(number: countIn),
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
