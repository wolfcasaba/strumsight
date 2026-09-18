import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/epoch_day.dart';
import 'package:strumsight/features/streak/model/streak_data.dart';
import 'package:strumsight/features/streak/streak_logic.dart';

/// ADR 0583 — the old conversion anchored the calendar date at LOCAL midnight
/// and then truncated, so at a positive offset it answered `trueDay - 1` while
/// at or west of UTC it happened to be right.
///
/// Every case here pins an EXPLICIT offset instead of the box's, and the
/// pre-fix expression is reproduced below as [oldEpochDayOf] so the assertions
/// mean the same thing on the UTC+2 dev box and on a UTC CI runner — where the
/// bug is invisible, which is precisely why it survived four copies.
void main() {
  // 2026-09-18 is 20714 days after 1970-01-01.
  const trueDay = 20714;
  const utcPlus2 = Duration(hours: 2);
  const utcMinus5 = Duration(hours: -5);

  group('the conversion this replaces', () {
    test('loses a day east of UTC and is right west of it', () {
      // The shape of the defect, measured rather than described: same instant,
      // two devices. This is what makes every "new == trueDay" assertion below
      // a real regression test on a UTC runner — the old function is right
      // there to disagree with.
      final noonUtc = DateTime.utc(2026, 9, 18, 12);

      expect(oldEpochDayOf(noonUtc, utcPlus2), trueDay - 1);
      expect(EpochDay.ofInstant(noonUtc, utcPlus2), trueDay);

      expect(oldEpochDayOf(noonUtc, utcMinus5), trueDay);
      expect(EpochDay.ofInstant(noonUtc, utcMinus5), trueDay);

      // And at UTC itself the two agree, which is the whole reason a
      // UTC-only test suite never saw this.
      expect(oldEpochDayOf(noonUtc, Duration.zero), trueDay);
      expect(EpochDay.ofInstant(noonUtc, Duration.zero), trueDay);
    });

    test('the half-hour zones lose a day too', () {
      final noonUtc = DateTime.utc(2026, 9, 18, 12);
      const kolkata = Duration(hours: 5, minutes: 30);
      expect(oldEpochDayOf(noonUtc, kolkata), trueDay - 1);
      expect(EpochDay.ofInstant(noonUtc, kolkata), trueDay);
    });
  });

  group('the canonical conversion', () {
    test('a local calendar date maps to its TRUE epoch day', () {
      expect(EpochDay.ofCalendarDate(2026, 9, 18), trueDay);
      // Midnight and midday of the same LOCAL date answer the same day —
      // this is the case the local-midnight division used to lose.
      expect(EpochDay.of(DateTime(2026, 9, 18)), trueDay);
      expect(EpochDay.of(DateTime(2026, 9, 18, 12)), trueDay);
      expect(EpochDay.of(DateTime(2026, 9, 18, 23, 59, 59)), trueDay);
    });

    test('east of UTC: the whole local day is ONE epoch day', () {
      // The instants a UTC+2 device sees as 2026-09-18 00:00 and 23:59 local.
      final firstMoment = DateTime.utc(2026, 9, 17, 22);
      final lastMoment = DateTime.utc(2026, 9, 18, 21, 59);

      expect(EpochDay.ofInstant(firstMoment, utcPlus2), trueDay);
      expect(EpochDay.ofInstant(lastMoment, utcPlus2), trueDay);
      // One minute later the local date rolls over — and the integer moves by
      // exactly one, which is what the streak's gap arithmetic relies on.
      expect(
        EpochDay.ofInstant(DateTime.utc(2026, 9, 18, 22), utcPlus2),
        trueDay + 1,
      );
    });

    test('west of UTC: the whole local day is ONE epoch day', () {
      final firstMoment = DateTime.utc(2026, 9, 18, 5);
      final lastMoment = DateTime.utc(2026, 9, 19, 4, 59);

      expect(EpochDay.ofInstant(firstMoment, utcMinus5), trueDay);
      expect(EpochDay.ofInstant(lastMoment, utcMinus5), trueDay);
      expect(
        EpochDay.ofInstant(DateTime.utc(2026, 9, 19, 5), utcMinus5),
        trueDay + 1,
      );
    });

    test('the same instant can be a different calendar day in each zone', () {
      // 2026-09-19 01:00 in Budapest is still 2026-09-18 18:00 in New York.
      final instant = DateTime.utc(2026, 9, 18, 23);
      expect(EpochDay.ofInstant(instant, utcPlus2), trueDay + 1);
      expect(EpochDay.ofInstant(instant, utcMinus5), trueDay);
    });

    test('[of] is [ofInstant] at the device\'s own offset', () {
      final now = DateTime.now();
      expect(EpochDay.of(now), EpochDay.ofInstant(now, now.timeZoneOffset));
    });
  });

  group('the inverses', () {
    test('utcMidnightOf names the epoch day it was built from', () {
      final midnight = EpochDay.utcMidnightOf(trueDay);
      expect(midnight.isUtc, isTrue);
      expect(midnight, DateTime.utc(2026, 9, 18));
      expect(EpochDay.ofCalendarDate(2026, 9, 18), trueDay);
    });

    test('localStartOf round-trips through [of] in ANY zone', () {
      // UTC midnight does not: west of UTC it reads back as the previous
      // local day, which is exactly the legacy-practice round-trip mismatch.
      for (var day = trueDay - 3; day <= trueDay + 3; day++) {
        expect(EpochDay.of(EpochDay.localStartOf(day)), day);
      }
    });
  });

  group('the streak domain speaks the same integers', () {
    test('StreakLogic.epochDayOf IS the canonical conversion', () {
      final moment = DateTime(2026, 9, 18, 7, 30);
      expect(StreakLogic.epochDayOf(moment), EpochDay.of(moment));
      expect(
        StreakLogic.epochDayOf(moment, utcOffset: moment.timeZoneOffset),
        StreakLogic.epochDayOf(moment),
        reason: 'the seam is the same function, not a second implementation',
      );
    });

    test('the shipping entry point records the TRUE day east of UTC', () {
      // The recording paths all go through `StreakLogic.epochDayOf`. Driven at
      // an explicit +02:00 this fails on the pre-fix body on ANY runner: the
      // old expression answers 20713 for the same instant.
      final practisedAt = DateTime.utc(2026, 9, 18, 5, 30); // 07:30 in Budapest

      expect(StreakLogic.epochDayOf(practisedAt, utcOffset: utcPlus2), trueDay);
      expect(oldEpochDayOf(practisedAt, utcPlus2), trueDay - 1);
    });

    test('and the same day west of UTC, where the old code was already '
        'right', () {
      final practisedAt = DateTime.utc(2026, 9, 18, 17); // 12:00 in New York

      expect(
        StreakLogic.epochDayOf(practisedAt, utcOffset: utcMinus5),
        trueDay,
      );
      expect(oldEpochDayOf(practisedAt, utcMinus5), trueDay);
    });

    test('practising on the next local calendar day extends the streak', () {
      const stored = StreakData(
        current: 7,
        longest: 9,
        lastPracticeDay: trueDay - 1,
        freezes: 1,
        totalDays: 30,
      );
      // 2026-09-18 07:30 local on a UTC+2 device — the day AFTER the stored
      // one. With the old conversion this instant answers `trueDay - 1`, which
      // equals `lastPracticeDay`, so the streak stays at 7 and the user's
      // practice is silently not counted.
      final practisedAt = DateTime.utc(2026, 9, 18, 5, 30);

      final next = StreakLogic.applyPractice(
        stored,
        StreakLogic.epochDayOf(practisedAt, utcOffset: utcPlus2),
      );

      expect(
        next.current,
        8,
        reason:
            'a 7-day streak must grow, never reset — the off-by-one made '
            'the stored day look like TODAY on a UTC+2 device',
      );
      expect(next.lastPracticeDay, trueDay);
      expect(
        StreakLogic.applyPractice(
          stored,
          oldEpochDayOf(practisedAt, utcPlus2),
        ).current,
        7,
        reason: 'this is the loss the round exists to stop',
      );
    });
  });
}

/// The pre-ADR-0583 conversion, reproduced at an EXPLICIT offset.
///
/// It was `DateTime(d.year, d.month, d.day).millisecondsSinceEpoch ~/
/// Duration.millisecondsPerDay` — a LOCAL midnight, whose epoch milliseconds
/// are the true day's minus the device's offset, truncated. Rebuilding it from
/// the offset instead of the ambient zone is what lets this file measure the
/// defect on a runner that has no zone at all.
int oldEpochDayOf(DateTime instant, Duration utcOffset) {
  final local = instant.toUtc().add(utcOffset);
  final localMidnightMs =
      DateTime.utc(local.year, local.month, local.day).millisecondsSinceEpoch -
      utcOffset.inMilliseconds;
  return localMidnightMs ~/ Duration.millisecondsPerDay;
}
