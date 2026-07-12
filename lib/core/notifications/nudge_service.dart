import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// The daily practice reminder (chunk 013's retention TODO): an OPT-IN local
/// notification at 19:00 local time, enabled from Settings. Best-effort by
/// design — on platforms without the plugin (tests, web) every call is a
/// silent no-op, which is fine for a nudge (unlike user-data writes).
///
/// Deliberately a repeating wall-time schedule (matchDateTimeComponents.time,
/// inexact — no exact-alarm permission needed) rather than a per-day re-armed
/// one-shot: it survives without any boot/app-open wiring. Trade-off: the
/// copy is static (no per-day Friday variants) — revisit with real users.
/// Which flavour of reminder copy a given day gets (chunk 013's
/// Friday-aware TODO, r157): Friday kicks off the weekend, Sat/Sun get the
/// weekend tone, weekdays the regular streak copy.
enum NudgeCopyVariant { regular, friday, weekend }

/// Localised (title, body) for one variant — resolved by the caller, which
/// has a BuildContext.
typedef NudgeCopyFor = ({String title, String body}) Function(
    NudgeCopyVariant variant);

class NudgeService {
  NudgeService._();
  static final NudgeService instance = NudgeService._();

  static const int _id = 1001;
  static const int hour = 19;

  /// One-shots armed ahead (re-armed on every app open). 7 = a full week of
  /// coverage even if the app stays closed; the honest trade-off vs the old
  /// static repeat: an app untouched for >7 days goes quiet until the next
  /// open — acceptable for per-day copy (the Duolingo-class pattern).
  static const int daysAhead = 7;

  /// The copy variant for a weekday (DateTime.monday..sunday).
  static NudgeCopyVariant variantFor(int weekday) =>
      weekday == DateTime.friday
          ? NudgeCopyVariant.friday
          : (weekday == DateTime.saturday || weekday == DateTime.sunday)
              ? NudgeCopyVariant.weekend
              : NudgeCopyVariant.regular;

  /// The next [count] occurrences of [h]:00 local wall time (calendar-added —
  /// DST-safe like [nextInstanceOf]).
  static List<tz.TZDateTime> nextInstances(int h,
      {int count = daysAhead, tz.TZDateTime? now}) {
    final first = nextInstanceOf(h, now: now);
    return [
      for (var i = 0; i < count; i++)
        tz.TZDateTime(
            first.location, first.year, first.month, first.day + i, h),
    ];
  }

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Next occurrence of [h]:00 local wall time strictly after [now]
  /// (defaults to the current instant in the initialised local zone).
  static tz.TZDateTime nextInstanceOf(int h, {tz.TZDateTime? now}) {
    final t = now ?? tz.TZDateTime.now(tz.local);
    var at = tz.TZDateTime(t.location, t.year, t.month, t.day, h);
    if (!at.isAfter(t)) {
      // Calendar-add the day (constructor normalises the overflow) — a
      // Duration(days: 1) is 24 ABSOLUTE hours and drifts the wall-clock
      // hour across a DST change (caught by the DST gate).
      at = tz.TZDateTime(t.location, t.year, t.month, t.day + 1, h);
    }
    return at;
  }

  Future<bool> _init() async {
    if (_ready) return true;
    try {
      tzdata.initializeTimeZones();
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      _ready = true;
      return true;
    } catch (_) {
      return false; // no platform channel (tests/web) → best-effort no-op
    }
  }

  /// Enable the daily reminder: asks for notification permission (Android
  /// 13+/iOS), then schedules the repeating 19:00 nudge. Returns false when
  /// the platform refused (permission denied / plugin unavailable) so the
  /// Settings toggle can reflect reality instead of lying.
  Future<bool> enable({required NudgeCopyFor copyFor}) async {
    if (!await _init()) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      if (granted == false) return false;
      // iOS: the Darwin plugin must be asked separately or a denied
      // permission would still report success (reviewer, round 82).
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final iosGranted =
          await ios?.requestPermissions(alert: true, badge: true, sound: true);
      if (iosGranted == false) return false;

      await _scheduleWeek(copyFor);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Arm the next [daysAhead] evenings as one-shots, each with its day's copy
  /// (r157 — this replaced the static wall-time repeat so Friday/weekend get
  /// their own text; ids are stable so re-arming replaces idempotently).
  Future<void> _scheduleWeek(NudgeCopyFor copyFor) async {
    final ats = nextInstances(hour);
    for (var i = 0; i < ats.length; i++) {
      final copy = copyFor(variantFor(ats[i].weekday));
      await _plugin.zonedSchedule(
        id: _id + i,
        title: copy.title,
        body: copy.body,
        scheduledDate: ats[i],
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'practice_nudge',
            'Practice reminder',
            channelDescription: 'Daily practice reminder',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  /// Startup reconcile for a persisted-ON toggle (devil-advocate, round 82):
  /// a force-stop clears the pending alarm and a system-settings revoke kills
  /// delivery — without this the toggle would lie after either. CHECKS the
  /// permission (never requests — no startup ambush) and re-arms the
  /// idempotent schedule (same id replaces). Returns whether the reminder is
  /// really live.
  Future<bool> verifyAndRearm({required NudgeCopyFor copyFor}) async {
    if (!await _init()) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final enabled = await android?.areNotificationsEnabled();
      if (enabled == false) return false;

      await _scheduleWeek(copyFor);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Cancel the daily reminder (all armed one-shots).
  Future<void> disable() async {
    if (!await _init()) return;
    try {
      for (var i = 0; i < daysAhead; i++) {
        await _plugin.cancel(id: _id + i);
      }
    } catch (_) {
      // best-effort
    }
  }
}
