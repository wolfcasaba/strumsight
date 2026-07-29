/// Masks anything that must never reach a log sink (SDD Ch2 §7.3).
///
/// Forbidden in logs: passwords, JWTs, the diagnostics token, full e-mail
/// addresses, raw audio, base64 WAV payloads and secure-storage contents.
///
/// The redactor is applied by the logger itself, not by call sites — a caller
/// that forgets is still safe. It is deliberately conservative: when in doubt
/// the value is replaced, because a missing log line is cheap and a leaked
/// token is not.
abstract final class LogRedactor {
  static const String redacted = '[redacted]';
  static const String redactedEmail = '[redacted-email]';
  static const String redactedToken = '[redacted-token]';

  /// Strings longer than this are replaced wholesale — a base64 WAV clip or a
  /// serialized PCM buffer must never be printed, whatever the field is called.
  static const int maxStringLength = 200;

  /// Number lists longer than this are summarised instead of printed (raw PCM).
  static const int maxNumberListLength = 16;

  /// Nested maps/lists deeper than this are collapsed (cheap cycle guard).
  static const int maxDepth = 4;

  /// Field names (or fragments of them) whose VALUE is always dropped.
  /// Matching is case-insensitive and ignores `_`, `-` and `.`.
  static const Set<String> sensitiveKeyFragments = {
    'password',
    'passwd',
    'token',
    'jwt',
    'authorization',
    'auth', // e.g. `authHeader`
    'secret',
    'apikey',
    'credential',
    'cookie',
    'session', // e.g. `sessionKey`
    'signature',
    'pcm',
    'audio',
    'wav',
    'clip',
    'samples',
  };

  static final RegExp _bearer = RegExp(
    r'bearer\s+[A-Za-z0-9._~+/=-]+',
    caseSensitive: false,
  );
  static final RegExp _jwt = RegExp(
    r'eyJ[A-Za-z0-9_=-]+\.[A-Za-z0-9_=-]+(?:\.[A-Za-z0-9_.+/=-]*)?',
  );
  static final RegExp _email = RegExp(
    r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',
  );

  /// Redact a whole field map — the entry point used by the loggers.
  static Map<String, Object?> fields(Map<String, Object?> fields) {
    final out = <String, Object?>{};
    for (final entry in fields.entries) {
      out[entry.key] = value(entry.key, entry.value, 0);
    }
    return out;
  }

  /// Redact one [input] belonging to [key], recursing into maps and lists.
  static Object? value(String key, Object? input, [int depth = 0]) {
    if (isSensitiveKey(key)) return redacted;
    if (input == null || input is bool || input is num) return input;
    if (input is String) return text(input);
    if (depth >= maxDepth) return redacted;
    if (input is Map) {
      final out = <String, Object?>{};
      for (final entry in input.entries) {
        final k = '${entry.key}';
        out[k] = value(k, entry.value, depth + 1);
      }
      return out;
    }
    if (input is Iterable) {
      final list = input.toList();
      if (list.length > maxNumberListLength && list.every((e) => e is num)) {
        return '[redacted:${list.length} numbers]';
      }
      if (list.length > maxNumberListLength) {
        return '[redacted:${list.length} items]';
      }
      return [for (final e in list) value(key, e, depth + 1)];
    }
    // An arbitrary object: only its type is safe to print — `toString()` may
    // embed a request body, a URL with a token or a whole payload.
    return '<${input.runtimeType}>';
  }

  /// Mask secrets inside free text (the event name, an error's message, …).
  static String text(String input) {
    var out = input
        .replaceAll(_bearer, 'Bearer $redactedToken')
        .replaceAll(_jwt, redactedToken)
        .replaceAll(_email, redactedEmail);
    if (out.length > maxStringLength) {
      out = '[redacted:${out.length} chars]';
    }
    return out;
  }

  /// Whether a field name looks sensitive.
  static bool isSensitiveKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[_\-.\s]'), '');
    for (final fragment in sensitiveKeyFragments) {
      if (normalized.contains(fragment)) return true;
    }
    return false;
  }
}
