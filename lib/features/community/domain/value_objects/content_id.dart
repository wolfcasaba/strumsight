/// Stable, opaque Community content identifier (E09-R05, ADR 0399 §1).
///
/// A `ContentId` identifies one of the Community content entities:
/// a post, a comment, a share artifact reference, etc. The Community
/// domain keeps one type for all of them — the owning entity's factory
/// documents which carries what — so a future route or feed item
/// cannot accidentally mix a post ID with a comment ID. The string is
/// opaque at the domain layer; the data layer is responsible for
/// producing it.
library;

final class ContentId {
  factory ContentId(String value) {
    if (value.isEmpty) {
      throw ArgumentError.value(value, 'value', 'content id must not be empty');
    }
    if (value.length > 128) {
      throw ArgumentError.value(
        value,
        'value',
        'content id must not exceed 128 characters',
      );
    }
    return ContentId._(value);
  }

  const ContentId._(this.value);

  final String value;

  @override
  bool operator ==(Object other) => other is ContentId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'ContentId(${value.length} chars)';
}
