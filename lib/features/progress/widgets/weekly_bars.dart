import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../model/practice_stats.dart';

/// A dependency-light weekly practice bar chart (hand-drawn, so it can't overflow
/// a tight viewport the way a full chart lib can). Shows practice **minutes** per
/// day for the last 7 days, oldest→newest, today highlighted in the copper accent.
class WeeklyBars extends StatelessWidget {
  const WeeklyBars({super.key, required this.days});

  /// Oldest-first, exactly one entry per day (see `PracticeStats.lastDays`).
  final List<DayTotal> days;

  static const double _maxBar = 92;
  static const double _minBar = 4;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    // Scale to the busiest day so a light week still reads; 1 min minimum so a
    // single short session doesn't render as a hairline.
    final peakMinutes = days
        .map((d) => (d.seconds / 60).round())
        .fold<int>(1, (m, v) => v > m ? v : m);
    final todayDay = days.isEmpty ? 0 : days.last.day;

    // Headroom above the tallest bar for the value label + weekday label + gaps
    // (two ~15px text lines + 8px spacing) so a full-height bar never overflows.
    return SizedBox(
      height: _maxBar + 46,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in days)
            Expanded(child: _Bar(
              day: d,
              isToday: d.day == todayDay,
              peakMinutes: peakMinutes,
              localeName: locale,
            )),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.day,
    required this.isToday,
    required this.peakMinutes,
    required this.localeName,
  });

  final DayTotal day;
  final bool isToday;
  final int peakMinutes;
  final String localeName;

  @override
  Widget build(BuildContext context) {
    final minutes = (day.seconds / 60).round();
    final frac = peakMinutes == 0 ? 0.0 : minutes / peakMinutes;
    final height = day.isEmpty
        ? WeeklyBars._minBar
        : (WeeklyBars._minBar + frac * (WeeklyBars._maxBar - WeeklyBars._minBar));
    final color = isToday
        ? AppColors.primary
        : day.isEmpty
            ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.25)
            : AppColors.primary.withValues(alpha: 0.45);

    // A screen reader would otherwise hear disconnected "12" / "M" fragments
    // with no unit or day (round 127); speak the whole bar as one fact.
    return Semantics(
      label: AppLocalizations.of(context)
          .progressBarSemantic(_weekdayFull(day.day, localeName), minutes),
      excludeSemantics: true,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
        Text(
          minutes > 0 ? '$minutes' : '',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: isToday ? AppColors.primary : Theme.of(context).hintColor,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: 14,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
          const SizedBox(height: 6),
          Text(
            _weekdayLetter(day.day, localeName),
            style: TextStyle(
              fontSize: 11,
              fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
              color: isToday
                  ? AppColors.primary
                  : Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  /// The reference [DateTime] whose weekday matches [epochDay]. Derived purely
  /// from the integer (epoch day 0 = 1970-01-01 = Thursday) so no timezone
  /// reconstruction can shift it. 2024-01-01 is a Monday anchor.
  static DateTime _weekdayRef(int epochDay) {
    final mon0 = ((epochDay % 7) + 3) % 7; // 0 = Monday
    return DateTime(2024, 1, 1).add(Duration(days: mon0));
  }

  /// Calendar-correct localized single-letter weekday (the visual label).
  static String _weekdayLetter(int epochDay, String localeName) {
    final name = DateFormat.E(localeName).format(_weekdayRef(epochDay));
    return name.isEmpty ? '' : name.substring(0, 1);
  }

  /// The full localized weekday name — spoken to a screen reader (round 127),
  /// where a bare letter would be ambiguous.
  static String _weekdayFull(int epochDay, String localeName) =>
      DateFormat.EEEE(localeName).format(_weekdayRef(epochDay));
}
