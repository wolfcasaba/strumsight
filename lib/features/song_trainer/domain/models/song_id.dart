/// Typed Song Trainer V2 identifiers (E03-R02, ADR 0089 §Döntés 2, SDD §9.2).
///
/// Every ID is a final value object whose only state is a normalised
/// filename-safe string. The base class enforces the trim / non-empty / length
/// / character contract in one place; concrete subclasses exist purely so the
/// type system prevents accidental mixing (a [SongAssetId] cannot stand in
/// for a [SongId]).
///
/// IDs are framework-independent: no Flutter, Riverpod, Dio,
/// SharedPreferences, locale or storage dependency is allowed. Safe-filename
/// mapping ([safeFilename]) is a pure, deterministic, side-effect-free
/// projection intended for filesystem display — it never modifies the
/// underlying identifier (§6 acceptance criteria).
library;

/// Stable exception thrown when a typed Song ID fails validation.
class SongIdValidationException implements Exception {
  SongIdValidationException._(this.code, this.value);

  /// One of [SongIdValidationCode]'s constants.
  final String code;

  /// The offending raw value, truncated to a log-safe length.
  final String value;

  String _safeSnippet() {
    if (value.length <= 32) return value;
    return '${value.substring(0, 32)}…';
  }

  @override
  String toString() =>
      'SongIdValidationException($code, value: ${_safeSnippet()})';
}

/// Stable machine-readable codes emitted by typed Song ID validation.
abstract final class SongIdValidationCode {
  static const String empty = 'songId.empty';
  static const String tooLong = 'songId.tooLong';
  static const String invalidCharacter = 'songId.invalidCharacter';
}

/// Shared contract for every typed Song Trainer ID.
sealed class SongTypedId {
  SongTypedId(String raw) : value = SongIdValidator.normalize(raw);

  /// The normalised, validated identifier (trimmed, non-empty, length- and
  /// character-bounded). Equal [SongTypedId] instances have equal [value]s
  /// when they are of the same concrete kind.
  final String value;

  /// A deterministic, filesystem-safe projection of [value]. Suitable for
  /// display in error messages or use as a filename; never modifies [value]
  /// and never returns an empty string.
  String safeFilename() => SongIdValidator.safeFilename(value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongTypedId &&
          other.runtimeType == runtimeType &&
          other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => '${SongIdValidator.shortTypeName(runtimeType)}($value)';
}

/// Stable, locally-generated identifier of a [SongDocument] (ADR 0089 §Döntés 2).
///
/// A SongId is not derived from `DateTime.now()` alone, and the
/// [safeFilename] mapping never modifies the underlying identity. Importing
/// the same source twice therefore surfaces as a duplicate ID the user can
/// explicitly merge, not as a silent overwrite.
final class SongId extends SongTypedId {
  SongId(super.value);

  /// Maximum length of a normalised [SongId]. Picked large enough to accept
  /// long UUIDs (36 chars) plus a discriminating suffix, but small enough to
  /// reject obvious garbage.
  static const int maxLength = 128;
}

/// Stable identifier of a [SongSection]; declared ahead of the section model
/// (E03-R03) so the document can already reference sections in marker
/// payloads without a round of refactors.
final class SongSectionId extends SongTypedId {
  SongSectionId(super.value);
}

/// Stable identifier of a [SongTrack]; declared ahead of the track model
/// (E03-R04) for the same forward-compat reason as [SongSectionId].
final class SongTrackId extends SongTypedId {
  SongTrackId(super.value);
}

/// Stable identifier of a [SongEvent]; declared ahead of the event model
/// (E03-R04) for the same forward-compat reason as [SongSectionId].
final class SongEventId extends SongTypedId {
  SongEventId(super.value);
}

/// Stable identifier of an asset referenced by a [SongDocument].
final class SongAssetId extends SongTypedId {
  SongAssetId(super.value);
}

/// Stable identifier of a [SongMarker].
final class SongMarkerId extends SongTypedId {
  SongMarkerId(super.value);
}

/// Shared validation and projection logic for [SongTypedId] subclasses.
///
/// The rules below match the §6 acceptance matrix: empty / whitespace values
/// raise a stable [SongIdValidationException]; values at the documented length
/// boundary are accepted; values one over are rejected; characters that are
/// unsafe in a filesystem or that are control bytes are rejected. The
/// [safeFilename] projection is deterministic and never modifies the
/// underlying value.
abstract final class SongIdValidator {
  /// Length cap for any typed Song ID. Shared by every subclass — a single
  /// ceiling keeps the persistence layer's bound checks honest.
  static const int maxLength = 128;

  /// Normalises [raw] for use as a [SongTypedId]'s [value]. Throws a
  /// [SongIdValidationException] with a stable [SongIdValidationCode] when
  /// the value cannot be accepted.
  static String normalize(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw SongIdValidationException._(SongIdValidationCode.empty, raw);
    }
    if (trimmed.length > maxLength) {
      throw SongIdValidationException._(SongIdValidationCode.tooLong, raw);
    }
    if (!_isAllowed(trimmed)) {
      throw SongIdValidationException._(
        SongIdValidationCode.invalidCharacter,
        raw,
      );
    }
    return trimmed;
  }

  /// A deterministic, filesystem-safe projection of [value]. The mapping is
  /// intentionally tiny: it replaces every run of disallowed characters with
  /// a single hyphen, trims leading/trailing hyphens, lower-cases ASCII A–Z
  /// and falls back to a stable hex digest when the cleaned input is empty.
  static String safeFilename(String value) {
    final lowered = value.toLowerCase();
    final replaced = StringBuffer();
    var lastWasHyphen = true; // collapse leading hyphens.
    for (final rune in lowered.runes) {
      if (_isFilenameChar(rune)) {
        replaced.writeCharCode(rune);
        lastWasHyphen = false;
      } else if (!lastWasHyphen) {
        replaced.write('-');
        lastWasHyphen = true;
      }
    }
    var cleaned = replaced.toString();
    while (cleaned.endsWith('-')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    if (cleaned.isEmpty) {
      return _deterministicSlug(value);
    }
    return cleaned;
  }

  /// Short class name for [type], used by [SongTypedId.toString].
  static String shortTypeName(Type type) {
    final source = type.toString();
    final dot = source.lastIndexOf('.');
    return dot < 0 ? source : source.substring(dot + 1);
  }

  static bool _isAllowed(String value) {
    for (final rune in value.runes) {
      if (!_isFilenameChar(rune) && rune != 0x20) {
        return false;
      }
    }
    return true;
  }

  static bool _isFilenameChar(int rune) {
    // ASCII letters, digits, dot, dash, underscore, tilde.
    if ((rune >= 0x30 && rune <= 0x39) || // 0-9
        (rune >= 0x41 && rune <= 0x5a) || // A-Z
        (rune >= 0x61 && rune <= 0x7a) || // a-z
        rune == 0x2e || // .
        rune == 0x2d || // -
        rune == 0x5f || // _
        rune == 0x7e) // ~
    {
      return true;
    }
    // Latin-1 supplement letters (À, Ö, ß, etc.) and Latin Extended-A.
    if ((rune >= 0xc0 && rune <= 0xff) || (rune >= 0x100 && rune <= 0x17f)) {
      return true;
    }
    return false;
  }

  /// Stable slug for values that contain no usable filename characters —
  /// derived purely from [value] so the same input always maps to the same
  /// output (no `DateTime.now()`, no ambient randomness).
  static String _deterministicSlug(String value) {
    var hash = 0xcbf29ce484222325; // FNV-1a 64-bit offset basis.
    for (final byte in value.codeUnits) {
      hash ^= byte & 0xff;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    return 'song-${hash.toRadixString(16).padLeft(16, '0')}';
  }
}
