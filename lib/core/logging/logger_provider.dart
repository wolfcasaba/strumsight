import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_logger.dart';
import 'debug_app_logger.dart';

/// The app-wide logger.
///
/// Debug builds print redacted structured lines; release builds drop them
/// ([NoopAppLogger]) so a shipping artifact never writes unbounded diagnostics
/// to the device log. Override in tests to capture what was logged — and, just
/// as importantly, to assert what was NOT.
final appLoggerProvider = Provider<AppLogger>((_) => createDefaultAppLogger());

/// The same choice, for the pre-`ProviderScope` boot path (bootstrap runs
/// before any container exists). Kept here so there is one definition of what
/// "the app's logger" means.
AppLogger createDefaultAppLogger() =>
    kDebugMode ? DebugAppLogger() : const NoopAppLogger();
