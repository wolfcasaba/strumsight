import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../analyze/model/analyze_result.dart';
import '../../learn/model/lesson.dart';
import '../../learn/widgets/lesson_highway.dart';
import '../share_content.dart';

/// A full-screen, looping, branded **replay** of a recording — chord + ↓/↑ arrows
/// flowing in tempo — made to be **screen-recorded** and shared (the "moat as
/// motion", RAG chunks 013/014). No encoder plugin, no mic: pure animation, so
/// it's buildable + testable now; a true MP4 export is a later option needing a
/// maintained video encoder.
class StrumReelScreen extends StatefulWidget {
  const StrumReelScreen({super.key, required this.result, this.capo = 0});

  final AnalyzeResult result;
  final int capo;

  @override
  State<StrumReelScreen> createState() => _StrumReelScreenState();
}

class _StrumReelScreenState extends State<StrumReelScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final Lesson _lesson;
  double _elapsed = 0;
  bool _playing = true;

  @override
  void initState() {
    super.initState();
    _lesson = Lessons.fromAnalyze(widget.result, name: 'reel');
    _ticker = createTicker((d) {
      setState(() => _elapsed = d.inMicroseconds / 1e6);
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  double get _playhead {
    final total = _lesson.totalBeats;
    if (total <= 0) return 0;
    final beat = _elapsed * _lesson.bpm / 60.0;
    return beat % total; // loop
  }

  void _toggle() {
    setState(() => _playing = !_playing);
    _playing ? _ticker.start() : _ticker.stop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chords = ShareContent.chords(widget.result, capo: widget.capo);
    return Scaffold(
      backgroundColor: const Color(0xFF111013),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.graphic_eq,
                          size: 15, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    const Text('StrumSight',
                        style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: Color(0xFFE9E5DE))),
                  ]),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFFE9E5DE)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Spacer(),
              if (chords.isNotEmpty)
                Text(chords,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontWeight: FontWeight.w800,
                        fontSize: 26,
                        color: Color(0xFFE9E5DE))),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _toggle,
                child: LessonHighway(
                  lesson: _lesson,
                  playheadBeat: _playhead,
                  height: 190,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '${l10n.reelHint}\n#StrumSightChallenge',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: const Color(0xFFE9E5DE).withValues(alpha: 0.7)),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('↓↑',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary)),
                  const SizedBox(width: 8),
                  Text(l10n.reelTagline,
                      style: TextStyle(
                          fontSize: 12,
                          color: const Color(0xFFE9E5DE).withValues(alpha: 0.7))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
