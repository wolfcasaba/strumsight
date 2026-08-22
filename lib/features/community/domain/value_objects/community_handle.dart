/// Stable Community handle value object (E09-R05, ADR 0399 §1, SDD §8.2).
///
/// The handle is the user-facing '@'-prefixed identifier a Community
/// profile is searchable by. The backend (ADR 0397 / `handle_policy.py`)
/// owns NFKC + casefold normalization against the DB unique index — this
/// value object enforces the **structural** invariants (length, character
/// set) at the domain layer so a malformed handle never reaches the wire.
///
/// Normalization is intentionally NOT reimplemented here; the data layer
/// passes the raw input through `CommunityHandle.normalizeForBackend`,
/// which mirrors the backend's NFKC + casefold + strip — but the
/// canonical comparison form lives on the server, not the client.
library;

final class CommunityHandle {
  factory CommunityHandle(String value) {
    if (value.isEmpty) {
      throw ArgumentError.value(
        value,
        'value',
        'community handle must not be empty',
      );
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
        value,
        'value',
        'community handle must not be whitespace only',
      );
    }
    // The backend's `_HANDLE_RE` is anchored on the normalized form; the
    // structural pre-check above (~3-24 chars, leading/trailing word-char)
    // is the safety net that stops a malformed handle from leaving the
    // device at all.
    final normalized = CommunityHandle.normalizeForBackend(trimmed);
    if (normalized.length < 3 || normalized.length > 24) {
      throw ArgumentError.value(
        value,
        'value',
        'community handle must be between 3 and 24 characters after normalization',
      );
    }
    if (!_allowedShape.hasMatch(normalized)) {
      throw ArgumentError.value(
        value,
        'value',
        'community handle must contain only letters, digits, "_" or "-" '
            'and must start and end with a letter or digit',
      );
    }
    return CommunityHandle._(trimmed);
  }

  const CommunityHandle._(this.value);

  /// The raw, untrimmed-from-trimming input supplied to the factory. The
  /// backend's database index is the normalized form; comparison anywhere
  /// in the domain layer or above MUST go through [normalized].
  final String value;

  /// Returns the NFKC + casefold + strip form the backend uses for its
  /// unique `handle_normalized` column. Mirrors
  /// `backend.app.community.policies.handle_policy.normalize` — a
  /// structural pre-check, not a security boundary.
  static String normalizeForBackend(String raw) {
    // The Dart core library has no NFKC helper; the data-layer mapper is
    // responsible for the full Unicode normalization. The structural
    // .trim() + casefold below is the minimál pre-check that mirrors
    // the *intent* of the backend rule for ASCII-only inputs.
    return raw.trim().toLowerCase();
  }

  String get normalized => CommunityHandle.normalizeForBackend(value);

  @override
  bool operator ==(Object other) =>
      other is CommunityHandle &&
      CommunityHandle.normalizeForBackend(other.value) == normalized;

  @override
  int get hashCode => normalized.hashCode;

  @override
  String toString() => 'CommunityHandle($value)';
}

final RegExp _allowedShape = RegExp(r'^[\w][\w\-]{1,22}[\w]$|^[\w]$');
