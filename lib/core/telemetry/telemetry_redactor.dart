import '../logging/log_redactor.dart';

/// The telemetry layer's redaction gate — the SECOND line of defence behind
/// `TelemetryEvent`'s structural closure (ADR 0484 D1/D2, SDD Ch12 §5).
///
/// This is not a second redaction policy: it calls straight through to the
/// existing, already-audited [LogRedactor] (token/JWT/e-mail masking, the
/// `>200`-char cutoff, the sensitive-key fragment list, the recursion-depth
/// and number-list caps). Declaring a second key list or pattern set here
/// would let the two drift apart — and the drift always goes the more
/// permissive way (ADR 0484 D2). Any diagnostic context a future sink
/// implementation attaches alongside a `TelemetryEvent` (never the event
/// itself, which carries no free-form field to begin with) must pass through
/// here first — but note [LogRedactor] only redacts VALUES, never the map's
/// KEYS ([sanitizeMetadata] delegates to `LogRedactor.fields`, which returns
/// each entry's own key unchanged). A caller must therefore build that map
/// from a closed, hand-picked set of key names, the same way
/// `TelemetryEvent`'s own fields are closed enums — a key sourced from user
/// input (a file path, an e-mail address used as a map key) would pass
/// through this gate completely unredacted.
abstract final class TelemetryRedactor {
  /// Redacts a field map the same way [LogRedactor.fields] redacts a log
  /// record's fields.
  static Map<String, Object?> sanitizeMetadata(Map<String, Object?> metadata) =>
      LogRedactor.fields(metadata);

  /// Redacts free text (tokens, JWTs, e-mails, over-length strings) the same
  /// way [LogRedactor.text] redacts a log message.
  static String sanitizeText(String input) => LogRedactor.text(input);

  /// Whether [key] names a field [LogRedactor] always drops the value of.
  static bool isSensitiveKey(String key) => LogRedactor.isSensitiveKey(key);
}
