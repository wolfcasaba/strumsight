import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../model/weekly_recap.dart';

/// The shareable 9:16 "Strum Wrapped" weekly recap card (chunk 017 rec #5).
/// Same self-contained dark brand language as the other cards — card copy is
/// English-global like every exported card (hashtags/symbols travel).
class WrappedCard extends StatelessWidget {
  const WrappedCard({super.key, required this.recap, required this.weekLabel});

  final WeeklyRecap recap;

  /// Human date-range label, already localised by the caller.
  final String weekLabel;

  static const double width = 360;
  static const double height = 640;
  static const _ink = Color(0xFFE9E5DE);

  @override
  Widget build(BuildContext context) {
    final acc = recap.averageAccuracy;
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
                    child: const Icon(Icons.graphic_eq,
                        size: 16, color: Colors.white),
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
              const Text('MY STRUM WEEK',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 2,
                      color: AppColors.primary)),
              const SizedBox(height: 6),
              Text(weekLabel,
                  style: TextStyle(
                      fontSize: 12, color: _ink.withValues(alpha: 0.7))),
              const SizedBox(height: 18),
              Text('${recap.minutes}',
                  style: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontWeight: FontWeight.w900,
                      fontSize: 84,
                      height: 1,
                      color: AppColors.primary)),
              Text('MINUTES PLAYED',
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.5,
                      color: _ink.withValues(alpha: 0.7))),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                      child: _chip('${recap.daysPracticed}/7', 'DAYS')),
                  const SizedBox(width: 10),
                  Expanded(child: _chip('${recap.strokes}', 'STRUMS')),
                  const SizedBox(width: 10),
                  Expanded(
                    child: acc == null
                        ? _chip('${recap.sessions}', 'SESSIONS')
                        : _chip('${(acc * 100).round()}%', '↓↑ ACCURACY'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (recap.streak > 0)
                Text('🔥 ${recap.streak}-day streak',
                    style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: AppColors.secondary)),
              const Spacer(),
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
                    child: Text('The app that grades your strumming hand',
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
            FittedBox(
              child: Text(value,
                  style: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontWeight: FontWeight.w800,
                      fontSize: 19,
                      color: _ink)),
            ),
            const SizedBox(height: 2),
            FittedBox(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 0.6,
                      color: _ink.withValues(alpha: 0.6))),
            ),
          ],
        ),
      );
}
