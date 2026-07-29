import 'package:flutter/foundation.dart';

import 'app_logger.dart';
import 'log_redactor.dart';

/// Where a formatted (already redacted) log line goes.
typedef LogSink = void Function(String line);

/// Console logger for debug/dev builds (SDD Ch2 Kör 4 §4.3).
///
/// Every value passes through [LogRedactor] before it reaches the sink, so a
/// careless call site cannot leak a token, a password, an e-mail or raw audio.
/// The sink is injectable, which is how the redaction tests observe output.
final class DebugAppLogger implements AppLogger {
  DebugAppLogger({LogSink? sink, this.minLevel = LogLevel.debug, bool? enabled})
    : _sink = sink ?? _defaultSink,
      enabled = enabled ?? kDebugMode;

  static void _defaultSink(String line) => debugPrint(line);

  final LogSink _sink;

  /// Records below this level are dropped.
  final LogLevel minLevel;

  /// When false nothing is emitted at all (release builds).
  final bool enabled;

  @override
  void debug(String event, {Map<String, Object?> fields = const {}}) =>
      _emit(LogLevel.debug, event, fields: fields);

  @override
  void info(String event, {Map<String, Object?> fields = const {}}) =>
      _emit(LogLevel.info, event, fields: fields);

  @override
  void warning(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) => _emit(
    LogLevel.warning,
    event,
    fields: fields,
    error: error,
    stackTrace: stackTrace,
  );

  @override
  void error(
    String event, {
    required Object error,
    required StackTrace stackTrace,
    Map<String, Object?> fields = const {},
  }) => _emit(
    LogLevel.error,
    event,
    fields: fields,
    error: error,
    stackTrace: stackTrace,
  );

  void _emit(
    LogLevel level,
    String event, {
    required Map<String, Object?> fields,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!enabled || level.index < minLevel.index) return;

    final buffer = StringBuffer('[${level.name}] ${LogRedactor.text(event)}');
    final safeFields = LogRedactor.fields(fields);
    if (safeFields.isNotEmpty) {
      final pairs = safeFields.entries.map((e) => '${e.key}=${e.value}');
      buffer.write(' {${pairs.join(', ')}}');
    }
    if (error != null) {
      // The error object is redacted the same way a field value is — an
      // exception's message routinely carries the URL, headers or body.
      buffer.write(' error=${LogRedactor.value('error', error)}');
    }
    _sink(buffer.toString());
    // Stack traces are structure, not payload — but only for real failures.
    if (stackTrace != null && level == LogLevel.error) {
      _sink(stackTrace.toString());
    }
  }
}
