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
}
