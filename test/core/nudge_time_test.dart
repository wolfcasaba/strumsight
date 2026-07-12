import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/core/notifications/nudge_service.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// The daily practice reminder (chunk 013 retention TODO) fires at 19:00
/// local wall time. Pure scheduling maths, tested against a real tz.
void main() {
  setUpAll(tzdata.initializeTimeZones);

  test('before 19:00 → today at 19:00', () {
    final loc = tz.getLocation('Europe/Budapest');
    final now = tz.TZDateTime(loc, 2026, 7, 10, 8, 30);
    final at = NudgeService.nextInstanceOf(19, now: now);
    expect(at.hour, 19);
    expect(at.day, 10);
  });

  test('after 19:00 → tomorrow at 19:00', () {
    final loc = tz.getLocation('Europe/Budapest');
    final now = tz.TZDateTime(loc, 2026, 7, 10, 21, 5);
    final at = NudgeService.nextInstanceOf(19, now: now);
    expect(at.hour, 19);
    expect(at.day, 11);
  });

  test('exactly at 19:00 → tomorrow (never schedule in the past)', () {
    final loc = tz.getLocation('Europe/Budapest');
    final now = tz.TZDateTime(loc, 2026, 7, 10, 19, 0);
    final at = NudgeService.nextInstanceOf(19, now: now);
    expect(at.day, 11);
    expect(at.isAfter(now), isTrue);
  });

  test('stays on local wall time across a DST boundary', () {
    final loc = tz.getLocation('Europe/Budapest');
    // 2026-10-24 is the day before the EU autumn change (Oct 25).
    final now = tz.TZDateTime(loc, 2026, 10, 24, 20, 0);
    final at = NudgeService.nextInstanceOf(19, now: now);
    expect(at.day, 25);
    expect(at.hour, 19, reason: 'wall-clock hour holds through the change');
  });

  // Round 157 — per-day copy (chunk 013's Friday-aware TODO): the schedule
  // becomes 7 one-shots re-armed on every app open, so each day can carry
  // its own text.
  test('nextInstances yields 7 consecutive wall-time evenings', () {
    final loc = tz.getLocation('Europe/Budapest');
    final now = tz.TZDateTime(loc, 2026, 10, 23, 8, 0); // spans the DST change
    final ats = NudgeService.nextInstances(19, now: now);
    expect(ats, hasLength(7));
    for (var i = 0; i < 7; i++) {
      expect(ats[i].hour, 19, reason: 'day $i keeps the wall hour (DST-safe)');
      expect(ats[i].day, 23 + i);
    }
    expect(ats.first.isAfter(now), isTrue);
  });

  test('variantFor: Friday kicks off the weekend, Sat/Sun are weekend', () {
    expect(NudgeService.variantFor(DateTime.friday), NudgeCopyVariant.friday);
    expect(NudgeService.variantFor(DateTime.saturday), NudgeCopyVariant.weekend);
    expect(NudgeService.variantFor(DateTime.sunday), NudgeCopyVariant.weekend);
    for (final d in [DateTime.monday, DateTime.tuesday, DateTime.wednesday,
        DateTime.thursday]) {
      expect(NudgeService.variantFor(d), NudgeCopyVariant.regular);
    }
  });
}
