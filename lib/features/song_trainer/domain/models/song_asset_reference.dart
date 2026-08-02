import 'song_id.dart';

/// Stable exception thrown by [SongAssetReference] validation.
class SongAssetReferenceValidationException implements Exception {
  SongAssetReferenceValidationException._(this.code);

  /// One of [SongAssetReferenceValidationCode]'s constants.
  final String code;

  @override
  String toString() => 'SongAssetReferenceValidationException($code)';
}

/// Stable machine-readable codes emitted by [SongAssetReference] validation.
abstract final class SongAssetReferenceValidationCode {
  static const String extensionEmpty = 'songAssetReference.extension.empty';
  static const String extensionTooLong = 'songAssetReference.extension.tooLong';
  static const String extensionInvalid = 'songAssetReference.extension.invalid';
  static const String sha256Invalid = 'songAssetReference.sha256.invalid';
  static const String byteLengthNegative =
      'songAssetReference.byteLength.negative';
  static const String byteLengthTooLarge =
      'songAssetReference.byteLength.tooLarge';
  static const String mimeTypeTooLong = 'songAssetReference.mimeType.tooLong';
  static const String durationNegative = 'songAssetReference.duration.negative';
  static const String durationTooLong = 'songAssetReference.duration.tooLong';
}

/// Documented upper bound on a single asset's byte length. Generous next to
/// any realistic audio / image asset; rejects obvious garbage.
const int maxSongAssetByteLength = 1 << 30; // 1 GiB.

/// Documented upper bound on a single asset's claimed duration in
/// milliseconds. A backing track longer than 24 hours is almost certainly
/// corrupt.
const int maxSongAssetDurationMs = 24 * 60 * 60 * 1000;

/// Lightweight reference to a binary asset attached to a [SongDocument]
/// (ADR 0089 §Döntés 4 — the document holds the reference, the asset store
/// holds the bytes).
///
/// An asset reference is enough to address and verify the underlying file
/// without holding its content: the [id] is the typed lookup, the [sha256]
/// is the content hash used for deduplication and integrity verification,
/// the [extension] drives file-type rendering, and [byteLength] is the
/// expected size for pre-flight budget checks.
final class SongAssetReference {
  SongAssetReference({
    required this.id,
    required this.sha256,
    required this.extension,
    required this.byteLength,
    this.mimeType,
    this.durationMs,
  }) {
    if (extension.isEmpty) {
      throw SongAssetReferenceValidationException._(
        SongAssetReferenceValidationCode.extensionEmpty,
      );
    }
    if (extension.length > 16) {
      throw SongAssetReferenceValidationException._(
        SongAssetReferenceValidationCode.extensionTooLong,
      );
    }
    if (!_isAllowedExtension(extension)) {
      throw SongAssetReferenceValidationException._(
        SongAssetReferenceValidationCode.extensionInvalid,
      );
    }
    if (!_isHex64(sha256)) {
      throw SongAssetReferenceValidationException._(
        SongAssetReferenceValidationCode.sha256Invalid,
      );
    }
    if (byteLength < 0) {
      throw SongAssetReferenceValidationException._(
        SongAssetReferenceValidationCode.byteLengthNegative,
      );
    }
    if (byteLength > maxSongAssetByteLength) {
      throw SongAssetReferenceValidationException._(
        SongAssetReferenceValidationCode.byteLengthTooLarge,
      );
    }
    if (mimeType != null && mimeType!.length > 128) {
      throw SongAssetReferenceValidationException._(
        SongAssetReferenceValidationCode.mimeTypeTooLong,
      );
    }
    if (durationMs != null) {
      if (durationMs! < 0) {
        throw SongAssetReferenceValidationException._(
          SongAssetReferenceValidationCode.durationNegative,
        );
      }
      if (durationMs! > maxSongAssetDurationMs) {
        throw SongAssetReferenceValidationException._(
          SongAssetReferenceValidationCode.durationTooLong,
        );
      }
    }
  }

  /// Stable identifier of the asset record in the asset store.
  final SongAssetId id;

  /// Lower-case hex SHA-256 of the asset bytes. Used for deduplication and
  /// integrity verification; never for ID derivation.
  final String sha256;

  /// File extension WITHOUT the leading dot (e.g. `'mp3'`, `'png'`).
  /// Lower-case, ASCII letters / digits, length 1–16.
  final String extension;

  /// Documented size in bytes. Used for pre-flight budget checks.
  final int byteLength;

  /// Optional MIME type — `null` when the importer could not determine one.
  final String? mimeType;

  /// Optional playback duration in milliseconds for time-bounded assets
  /// (audio / video). `null` for static assets (images, fonts).
  final int? durationMs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongAssetReference &&
          other.id == id &&
          other.sha256 == sha256 &&
          other.extension == extension &&
          other.byteLength == byteLength &&
          other.mimeType == mimeType &&
          other.durationMs == durationMs;

  @override
  int get hashCode =>
      Object.hash(id, sha256, extension, byteLength, mimeType, durationMs);

  static bool _isHex64(String value) {
    if (value.length != 64) return false;
    for (var index = 0; index < value.length; index++) {
      final rune = value.codeUnitAt(index);
      final isDigit = rune >= 0x30 && rune <= 0x39;
      final isLowerHex = rune >= 0x61 && rune <= 0x66;
      if (!isDigit && !isLowerHex) return false;
    }
    return true;
  }

  static bool _isAllowedExtension(String value) {
    for (var index = 0; index < value.length; index++) {
      final rune = value.codeUnitAt(index);
      final isLowerLetter = rune >= 0x61 && rune <= 0x7a;
      final isDigit = rune >= 0x30 && rune <= 0x39;
      if (!isLowerLetter && !isDigit) return false;
    }
    return true;
  }
}
