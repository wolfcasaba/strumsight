/// Severity of a structured log record.
enum LogLevel { debug, info, warning, error }

/// Structured application logger (SDD Ch2 §7.3).
///
/// Rules that every implementation must honour:
/// - a log is an **event name + fields**, never an interpolated sentence;
/// - the implementation redacts sensitive values (see `LogRedactor`) — call
///   sites are not trusted to remember;
/// - production must not print without bound.
///
/// Injected via `appLoggerProvider`, so the implementation is replaceable
/// (a crash reporter / remote sink) without touching call sites.
abstract interface class AppLogger {
  void debug(String event, {Map<String, Object?> fields = const {}});

  void info(String event, {Map<String, Object?> fields = const {}});

  void warning(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  });

  void error(
    String event, {
    required Object error,
    required StackTrace stackTrace,
    Map<String, Object?> fields = const {},
  });
}

/// Drops everything. The default in release builds — a shipping artifact must
/// not print unbounded diagnostics to the device log. Replace it with a real
/// sink (crash reporter) when one exists.
final class NoopAppLogger implements AppLogger {
  const NoopAppLogger();

  @override
  void debug(String event, {Map<String, Object?> fields = const {}}) {}

  @override
  void info(String event, {Map<String, Object?> fields = const {}}) {}

  @override
  void warning(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) {}

  @override
  void error(
    String event, {
    required Object error,
    required StackTrace stackTrace,
    Map<String, Object?> fields = const {},
  }) {}
}
