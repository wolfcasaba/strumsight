import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/domain/model/learner_constraints.dart';
import 'package:strumsight/features/practice_generator/domain/model/weekly_availability.dart';
import 'package:strumsight/features/practice_generator/domain/service/request_validator.dart';

void main() {
  final validator = RequestValidator();
  final dstStart = LocalDate(2026, 3, 29);
  final dstFollowingDay = LocalDate(2026, 3, 30);

  DailyAvailability availableDay(LocalDate date) => DailyAvailability(
    date: date,
    status: AvailabilityStatus.available,
    minimumMinutes: 10,
    targetMinutes: 15,
    maximumMinutes: 20,
    maximumStrength: ConstraintStrength.hard,
  );

  group('WeeklyAvailability', () {
    test('uses local calendar dates across a DST transition (A5)', () {
      // European DST starts on 2026-03-29. These remain consecutive local
      // dates without any UTC conversion or offset-dependent shift.
      final availability = WeeklyAvailability([
        availableDay(dstStart),
        availableDay(dstFollowingDay),
      ]);

      expect(availability.forDate(dstStart)?.date, LocalDate(2026, 3, 29));
      expect(
        availability.forDate(dstFollowingDay)?.date,
        LocalDate(2026, 3, 30),
      );
      expect(availability.forDate(LocalDate(2026, 3, 31)), isNull);
    });

    test('rejects invalid local calendar dates without DateTime', () {
      expect(() => LocalDate(2026, 2, 29), throwsArgumentError);
      expect(() => LocalDate(2028, 2, 30), throwsArgumentError);
      expect(LocalDate(2028, 2, 29).toString(), '2028-02-29');
    });

    test(
      'hard daily maximum accepts below and at the inclusive boundary (A4)',
      () {
        final availability = WeeklyAvailability([availableDay(dstStart)]);

        final below = validator.validate(
          goals: const [],
          availability: availability,
          scheduledMinutes: {dstStart: 19},
        );
        final boundary = validator.validate(
          goals: const [],
          availability: availability,
          scheduledMinutes: {dstStart: 20},
        );

        expect(below.hasErrors, isFalse);
        expect(boundary.hasErrors, isFalse);
      },
    );

    test('hard daily maximum rejects minutes above the boundary (A4)', () {
      final availability = WeeklyAvailability([availableDay(dstStart)]);

      final result = validator.validate(
        goals: const [],
        availability: availability,
        scheduledMinutes: {dstStart: 21},
      );

      expect(result.hasErrors, isTrue);
      expect(
        result.findings.map((finding) => finding.code),
        contains(RequestValidationCode.hardMaximumExceeded),
      );
      expect(result.totalSoftViolationCost, 0);
    });
  });
}
