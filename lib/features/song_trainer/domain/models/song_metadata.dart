library;

import '../../../../core/music/tuning.dart';

import 'song_id.dart';

/// Authoring metadata attached to a [SongDocument] (ADR 0089 §Döntés 4, SDD
/// §9.3).
///
/// The metadata is the only authoring-side face of the document: titles,
/// credits, tags, capo / tuning defaults and the optional artwork reference.
/// It is intentionally minimal — structural data (sections, measures, tracks,
/// events) lives in E03-R03/R04/R05; importer warnings live in [SongSource].
/// Every mutable field is exposed only as an immutable view.

/// Stable exceptions for [SongMetadata] validation.
class SongMetadataValidationException implements Exception {
  SongMetadataValidationException._(this.code);

  /// One of [SongMetadataValidationCode]'s constants.
  final String code;

  @override
  String toString() => 'SongMetadataValidationException($code)';
}

/// Stable machine-readable codes emitted by [SongMetadata] validation.
abstract final class SongMetadataValidationCode {
  static const String titleEmpty = 'songMetadata.title.empty';
  static const String titleTooLong = 'songMetadata.title.tooLong';
  static const String artistEmpty = 'songMetadata.artist.empty';
  static const String albumEmpty = 'songMetadata.album.empty';
  static const String composerEmpty = 'songMetadata.composer.empty';
  static const String copyrightEmpty = 'songMetadata.copyright.empty';
  static const String notesEmpty = 'songMetadata.notes.empty';
  static const String capoOutOfRange = 'songMetadata.capo.outOfRange';
  static const String tagEmpty = 'songMetadata.tag.empty';
  static const String tagTooLong = 'songMetadata.tag.tooLong';
  static const String tagCountExceeded = 'songMetadata.tagCount.exceeded';
}

/// Authoring metadata of a [SongDocument]. The constructor trims every text
/// field and case-normalises tags; mutations are not supported (an edited
/// copy is built by constructing a fresh instance and replacing the field
/// on the owning document).
final class SongMetadata {
  /// Maximum length of the trimmed title. Generous next to any authored song,
  /// small enough to reject obvious garbage.
  static const int maxTitleLength = 256;

  /// Maximum length of a single credit / note / copyright string.
  static const int maxTextLength = 1024;

  /// Maximum number of tags persisted on the document.
  static const int maxTagCount = 32;

  /// Maximum length of a single tag (case-normalised).
  static const int maxTagLength = 48;

  /// Documented capo range. A capo above this fret cannot be represented
  /// accurately on a standard six-string guitar.
  static const int maxCapo = 15;

  SongMetadata({
    required String title,
    this.artist,
    this.album,
    this.composer,
    this.copyright,
    List<String> tags = const <String>[],
    this.notes,
    this.defaultTuning,
    this.defaultCapo = 0,
    this.originalKey,
    this.artworkAssetId,
  }) : title = _normalizeTitle(title),
       _tags = _normalizeTags(tags) {
    _validateText('artist', artist, SongMetadataValidationCode.artistEmpty);
    _validateText('album', album, SongMetadataValidationCode.albumEmpty);
    _validateText(
      'composer',
      composer,
      SongMetadataValidationCode.composerEmpty,
    );
    _validateText(
      'copyright',
      copyright,
      SongMetadataValidationCode.copyrightEmpty,
    );
    _validateText('notes', notes, SongMetadataValidationCode.notesEmpty);
    if (defaultCapo < 0 || defaultCapo > maxCapo) {
      throw SongMetadataValidationException._(
        SongMetadataValidationCode.capoOutOfRange,
      );
    }
  }

  /// Non-empty trimmed title (the only strictly required field).
  final String title;

  final String? artist;
  final String? album;
  final String? composer;
  final String? copyright;

  /// Immutable, case-normalised, deduplicated tag list.
  List<String> get tags => _tags;
  final List<String> _tags;

  final String? notes;

  /// Optional default tuning reference. Lives in the shared music core so
  /// the tuner, the import preview and the editor all see the same set of
  /// presets.
  final Tuning? defaultTuning;

  /// Default capo fret (0 means "no capo"). Range-checked at construction.
  final int defaultCapo;

  /// Optional original key (locale-independent symbolic representation —
  /// the actual key/value object arrives in E03-R03).
  final String? originalKey;

  /// Optional [SongAssetId] pointing to the document artwork.
  final SongAssetId? artworkAssetId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongMetadata &&
          other.title == title &&
          other.artist == artist &&
          other.album == album &&
          other.composer == composer &&
          other.copyright == copyright &&
          _listEquals(other.tags, tags) &&
          other.notes == notes &&
          other.defaultTuning == defaultTuning &&
          other.defaultCapo == defaultCapo &&
          other.originalKey == originalKey &&
          other.artworkAssetId == artworkAssetId;

  @override
  int get hashCode => Object.hash(
    title,
    artist,
    album,
    composer,
    copyright,
    Object.hashAll(tags),
    notes,
    defaultTuning,
    defaultCapo,
    originalKey,
    artworkAssetId,
  );

  // ---------------------------------------------------------------------
  // Validation helpers
  // ---------------------------------------------------------------------

  static String _normalizeTitle(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw SongMetadataValidationException._(
        SongMetadataValidationCode.titleEmpty,
      );
    }
    if (trimmed.length > maxTitleLength) {
      throw SongMetadataValidationException._(
        SongMetadataValidationCode.titleTooLong,
      );
    }
    return trimmed;
  }

  static void _validateText(String field, String? value, String emptyCode) {
    if (value == null) return;
    if (value.length > maxTextLength) {
      throw SongMetadataValidationException._(emptyCode);
    }
  }

  static List<String> _normalizeTags(List<String> raw) {
    if (raw.length > maxTagCount) {
      throw SongMetadataValidationException._(
        SongMetadataValidationCode.tagCountExceeded,
      );
    }
    final seen = <String>{};
    final normalized = <String>[];
    for (final entry in raw) {
      final trimmed = entry.trim().toLowerCase();
      // Empty / whitespace-only entries are silently dropped: an empty tag
      // cell from a UI grid is not a validation failure, and forcing the
      // user to clean them up here would be hostile. A separate test
      // asserts that a wholly empty tag list is still accepted.
      if (trimmed.isEmpty) continue;
      if (trimmed.length > maxTagLength) {
        throw SongMetadataValidationException._(
          SongMetadataValidationCode.tagTooLong,
        );
      }
      if (seen.add(trimmed)) {
        normalized.add(trimmed);
      }
    }
    return List<String>.unmodifiable(normalized);
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}
