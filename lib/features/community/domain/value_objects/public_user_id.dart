/// Stable, public Community user identifier (E09-R05, ADR 0399 §1, SDD §8.1).
///
/// This is the *only* user identifier the Community feature exposes across
/// its public boundary — backend internal bigints, e-mail addresses and
/// numeric primary keys MUST NOT travel through this value object. The
/// string is accepted as opaque at the domain layer; a producer in the
/// data layer is responsible for generating a real value (UUIDv7 per
/// ADR 0396 §3). The string form is what crosses the API surface.
library;

final class PublicUserId {
  factory PublicUserId(String value) {
    if (value.isEmpty) {
      throw ArgumentError.value(
        value,
        'value',
        'public user id must not be empty',
      );
    }
    if (value.length > 128) {
      throw ArgumentError.value(
        value,
        'value',
        'public user id must not exceed 128 characters',
      );
    }
    if (value.contains('@')) {
      // An '@' is a structural giveaway for an e-mail-shaped identifier;
      // the §8.1 invariant forbids e-mail as a public Community id.
      throw ArgumentError.value(
        value,
        'value',
        'public user id must not be e-mail shaped',
      );
    }
    return PublicUserId._(value);
  }

  const PublicUserId._(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is PublicUserId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'PublicUserId(${value.length} chars)';
}
