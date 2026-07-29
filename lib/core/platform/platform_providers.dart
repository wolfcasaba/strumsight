import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_lifecycle.dart';
import 'screen_wakelock.dart';

/// App lifecycle transitions. Real binding in the app, fake in tests — this is
/// how a widget test can say "the user switched apps" (E01-R09 §9.4).
final appLifecycleEventsProvider = Provider<AppLifecycleEvents>((ref) {
  final events = BindingAppLifecycleEvents();
  ref.onDispose(events.dispose);
  return events;
});

/// Screen wakelock behind an interface so a test can assert it was released.
final screenWakelockProvider = Provider<ScreenWakelock>(
  (_) => const WakelockPlusScreenWakelock(),
);
