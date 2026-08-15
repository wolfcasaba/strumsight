import 'learner_constraints.dart';

/// A timezone-neutral local calendar date. It deliberately has no instant or
/// offset; availability belongs to the learner's calendar day, not UTC.
final class LocalDate implements Comparable<LocalDate> {
  LocalDate(this.year, this.month, this.day) {
    if (month < 1 || month > 12) {
      throw ArgumentError.value(month, 'month', 'must be between 1 and 12');
    }
    final maximumDay = _daysInMonth(year, month);
    if (day < 1 || day > maximumDay) {
      throw ArgumentError.value(
        day,
        'day',
        'must be between 1 and $maximumDay for $year-$month',
      );
    }
  }

  final int year;
  final int month;
  final int day;

  @override
  int compareTo(LocalDate other) {
    final yearComparison = year.compareTo(other.year);
    if (yearComparison != 0) return yearComparison;
    final monthComparison = month.compareTo(other.month);
    if (monthComparison != 0) return monthComparison;
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      year == other.year &&
      month == other.month &&
      day == other.day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() =>
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}

/// Whether a local day is available for practice.
enum AvailabilityStatus {
  available('available'),
  unavailable('unavailable');

  const AvailabilityStatus(this.code);

  final String code;

  static AvailabilityStatus fromCode(String? code) {
    if (code == null || code.trim().isEmpty) {
      throw ArgumentError.value(
        code,
        'code',
        'AvailabilityStatus code must not be empty',
      );
    }
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw ArgumentError.value(
      code,
      'code',
      'Unknown AvailabilityStatus code: $code',
    );
  }
}

/// Availability and time preferences for one local calendar day.
final class DailyAvailability {
  DailyAvailability({
    required this.date,
    required this.status,
    required this.minimumMinutes,
    required this.targetMinutes,
    required this.maximumMinutes,
    required this.maximumStrength,
    this.preferredStartMinute,
    String? note,
    this.softExcessMinuteCost = 0,
  }) : note = _normalizeOptionalText(note) {
    if (minimumMinutes < 0 || targetMinutes < 0 || maximumMinutes < 0) {
      throw ArgumentError('availability minutes must not be negative');
    }
    if (minimumMinutes > targetMinutes || targetMinutes > maximumMinutes) {
      throw ArgumentError(
        'minimumMinutes <= targetMinutes <= maximumMinutes is required',
      );
    }
    if (preferredStartMinute != null &&
        (preferredStartMinute! < 0 ||
            preferredStartMinute! >= _minutesPerDay)) {
      throw ArgumentError.value(
        preferredStartMinute,
        'preferredStartMinute',
        'must be between 0 and ${_minutesPerDay - 1}',
      );
    }
    if (status == AvailabilityStatus.unavailable && maximumMinutes != 0) {
      throw ArgumentError.value(
        maximumMinutes,
        'maximumMinutes',
        'must be zero when unavailable',
      );
    }
    if (maximumStrength == ConstraintStrength.hard &&
        softExcessMinuteCost != 0) {
      throw ArgumentError.value(
        softExcessMinuteCost,
        'softExcessMinuteCost',
        'must be zero for a hard maximum',
      );
    }
    if (maximumStrength == ConstraintStrength.soft &&
        softExcessMinuteCost <= 0) {
      throw ArgumentError.value(
        softExcessMinuteCost,
        'softExcessMinuteCost',
        'must be positive for a soft maximum',
      );
    }
  }

  static const int _minutesPerDay = 24 * 60;

  final LocalDate date;
  final AvailabilityStatus status;
  final int minimumMinutes;
  final int targetMinutes;
  final int maximumMinutes;
  final ConstraintStrength maximumStrength;
  final int? preferredStartMinute;
  final String? note;
  final int softExcessMinuteCost;

  bool get isAvailable => status == AvailabilityStatus.available;

  @override
  bool operator ==(Object other) =>
      other is DailyAvailability &&
      date == other.date &&
      status == other.status &&
      minimumMinutes == other.minimumMinutes &&
      targetMinutes == other.targetMinutes &&
      maximumMinutes == other.maximumMinutes &&
      maximumStrength == other.maximumStrength &&
      preferredStartMinute == other.preferredStartMinute &&
      note == other.note &&
      softExcessMinuteCost == other.softExcessMinuteCost;

  @override
  int get hashCode => Object.hash(
    date,
    status,
    minimumMinutes,
    targetMinutes,
    maximumMinutes,
    maximumStrength,
    preferredStartMinute,
    note,
    softExcessMinuteCost,
  );
}

/// A variable, local-date-based availability set for a planning week.
final class WeeklyAvailability {
  WeeklyAvailability(Iterable<DailyAvailability> days)
    : days = List<DailyAvailability>.unmodifiable(days) {
    final dates = <LocalDate>{};
    for (final day in this.days) {
      if (!dates.add(day.date)) {
        throw ArgumentError.value(days, 'days', 'contains duplicate date');
      }
    }
  }

  final List<DailyAvailability> days;

  DailyAvailability? forDate(LocalDate date) {
    for (final day in days) {
      if (day.date == date) return day;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is WeeklyAvailability && _sameList(days, other.days);

  @override
  int get hashCode => Object.hashAll(days);
}

String? _normalizeOptionalText(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

bool _isLeapYear(int year) =>
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);

int _daysInMonth(int year, int month) {
  switch (month) {
    case 2:
      return _isLeapYear(year) ? 29 : 28;
    case 4:
    case 6:
    case 9:
    case 11:
      return 30;
    default:
      return 31;
  }
}
