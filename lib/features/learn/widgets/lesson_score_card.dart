import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// A shareable 9:16 "lesson complete" brag card — score, stars, combo — that
/// carries the moat + install link (RAG chunks 013 + 014). Self-contained dark
/// brand look so the exported PNG reads the same everywhere.
class LessonScoreCard extends StatelessWidget {
  const LessonScoreCard({
    super.key,
    required this.lessonName,
    required this.accuracy,
    required this.stars,
    required this.maxCombo,
    required this.hits,
    required this.total,
  });

  final String lessonName;
  final double accuracy;
  final int stars;
  final int maxCombo;
  final int hits;
  final int total;

  static const double width = 360;
  static const double height = 640;
  static const _ink = Color(0xFFE9E5DE);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF17151A), Color(0xFF111013)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child:
                        const Icon(Icons.graphic_eq, size: 16, color: Colors.white),
                  ),
                  const SizedBox(width: 9),
                  const Text('StrumSight',
                      style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                          color: _ink)),
                ],
              ),
              const Spacer(),
              const Text('LESSON COMPLETE',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 2,
                      color: AppColors.primary)),
              const SizedBox(height: 8),
              Text(lessonName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontWeight: FontWeight.w800,
                      fontSize: 26,
                      color: _ink)),
              const SizedBox(height: 20),
              Text('${(accuracy * 100).round()}%',
                  style: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontWeight: FontWeight.w900,
                      fontSize: 72,
                      height: 1,
                      color: AppColors.confidenceHigh)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 3; i++)
                    Icon(i < stars ? Icons.star : Icons.star_border,
                        size: 40, color: AppColors.secondary),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(child: _chip('$hits/$total', 'HITS')),
                  const SizedBox(width: 12),
                  Expanded(child: _chip('$maxCombo', 'BEST COMBO')),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('↓↑',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary)),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text('Graded on my strum direction',
                        style: TextStyle(
                            fontSize: 10, color: _ink.withValues(alpha: 0.7))),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String value, String label) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    fontFamily: 'Montserrat',
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: _ink)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 9, letterSpacing: 0.6,
                    color: _ink.withValues(alpha: 0.6))),
          ],
        ),
      );
}
