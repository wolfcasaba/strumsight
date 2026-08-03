import 'dart:convert';
import 'dart:typed_data';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../local/song_document_codec.dart';
import 'export_filename_sanitizer.dart';
import 'native_json_exporter.dart';
import 'song_importer.dart';

/// Native JSON imports are capped before parsing and while streaming.
const int maxNativeJsonSourceBytes = 1_048_576;

/// Stable warning codes emitted by the native importer.
abstract final class NativeJsonImportWarningCode {
  static const String extensionMismatch = 'songImport.native.extensionMismatch';
  static const String duplicateSourceHash =
      'songImport.native.duplicateSourceHash';
}

/// Stable failure codes emitted by the native importer.
abstract final class NativeJsonImportFailureCode {
  static const String sourceTooLarge = 'songImport.native.sourceTooLarge';
  static const String sourceRead = 'songImport.native.sourceRead';
  static const String invalidJson = 'songImport.native.invalidJson';
  static const String invalidRoot = 'songImport.native.invalidRoot';
  static const String unsupportedFormatVersion =
      'songImport.native.unsupportedFormatVersion';
  static const String assetManifestMismatch =
      'songImport.native.assetManifestMismatch';
  static const String duplicateId = 'songImport.native.duplicateId';
  static const String invalidDocument = 'songImport.native.invalidDocument';
}

/// Native StrumSight JSON probe and in-memory importer.
final class NativeJsonImporter implements SongImporter {
  const NativeJsonImporter({this.codec = const SongDocumentCodec()});

  final SongDocumentCodec codec;

  @override
  Set<String> get supportedExtensions => const <String>{
    nativeJsonFileExtension,
  };

  @override
  Future<ImportProbeResult> probe(
    ImportSourceFile source,
    CancellationToken cancellationToken,
  ) async {
    final read = await _readSource(source, cancellationToken);
    if (read.isCancelled) {
      return const ImportProbeResult.failure(FailureCode.cancelled);
    }
    if (read.failureCode != null) {
      return ImportProbeResult.failure(read.failureCode!);
    }
    final parsed = _parseRoot(read.bytes!);
    if (parsed.failureCode != null) {
      return ImportProbeResult.failure(parsed.failureCode!);
    }
    return ImportProbeResult.recognized(warnings: _warningsFor(source));
  }

  @override
  Future<AppResult<SongImportResult>> import(
    ImportSourceFile source,
    SongImportOptions options,
    CancellationToken cancellationToken,
  ) async {
    final read = await _readSource(source, cancellationToken);
    if (read.isCancelled) {
      return const AppResult<SongImportResult>.failure(CancelledFailure());
    }
    if (read.failureCode != null) {
      return _failure(read.failureCode!);
    }

    final parsed = _parseRoot(read.bytes!);
    if (parsed.failureCode != null) {
      return _failure(parsed.failureCode!);
    }
    if (cancellationToken.isCancelled) {
      return const AppResult<SongImportResult>.failure(CancelledFailure());
    }

    final root = parsed.root!;
    final documentJson = root['document'];
    final manifest = root['assetManifest'];
    if (documentJson is! Map<String, dynamic> || manifest is! List) {
      return _failure(NativeJsonImportFailureCode.invalidRoot);
    }
    final assets = documentJson['assets'];
    if (assets is! List || !_jsonDeepEquals(assets, manifest)) {
      return _failure(NativeJsonImportFailureCode.assetManifestMismatch);
    }
    if (_wouldDecodeLossily(documentJson)) {
      return _failure(NativeJsonImportFailureCode.invalidDocument);
    }
    if (_hasDuplicateIds(documentJson)) {
      return _failure(NativeJsonImportFailureCode.duplicateId);
    }

    try {
      final document = codec.decodeFromMap(documentJson);
      if (cancellationToken.isCancelled) {
        return const AppResult<SongImportResult>.failure(CancelledFailure());
      }
      final warnings = <String>[..._warningsFor(source)];
      if (options.knownSourceHashes.contains(document.source.sha256)) {
        warnings.add(NativeJsonImportWarningCode.duplicateSourceHash);
      }
      return AppResult<SongImportResult>.success(
        SongImportResult(document: document, warnings: warnings),
      );
    } catch (_) {
      return _failure(NativeJsonImportFailureCode.invalidDocument);
    }
  }

  Future<_SourceRead> _readSource(
    ImportSourceFile source,
    CancellationToken cancellationToken,
  ) async {
    if (cancellationToken.isCancelled) return const _SourceRead.cancelled();
    if (source.byteLength < 0 || source.byteLength > maxNativeJsonSourceBytes) {
      return const _SourceRead.failure(
        NativeJsonImportFailureCode.sourceTooLarge,
      );
    }
    final bytes = BytesBuilder(copy: false);
    var byteCount = 0;
    try {
      await for (final chunk in source.openRead()) {
        if (cancellationToken.isCancelled) return const _SourceRead.cancelled();
        byteCount += chunk.length;
        if (byteCount > maxNativeJsonSourceBytes) {
          return const _SourceRead.failure(
            NativeJsonImportFailureCode.sourceTooLarge,
          );
        }
        bytes.add(chunk);
      }
    } catch (_) {
      return const _SourceRead.failure(NativeJsonImportFailureCode.sourceRead);
    }
    if (cancellationToken.isCancelled) return const _SourceRead.cancelled();
    return _SourceRead.bytes(bytes.takeBytes());
  }

  _ParsedRoot _parseRoot(List<int> bytes) {
    final Object? raw;
    try {
      raw = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return const _ParsedRoot.failure(NativeJsonImportFailureCode.invalidJson);
    }
    if (raw is! Map<String, dynamic>) {
      return const _ParsedRoot.failure(NativeJsonImportFailureCode.invalidRoot);
    }
    if (raw['format'] != nativeJsonFormat) {
      return const _ParsedRoot.failure(NativeJsonImportFailureCode.invalidRoot);
    }
    if (raw['formatVersion'] != nativeJsonFormatVersion) {
      return const _ParsedRoot.failure(
        NativeJsonImportFailureCode.unsupportedFormatVersion,
      );
    }
    if (raw['document'] is! Map<String, dynamic> ||
        raw['assetManifest'] is! List) {
      return const _ParsedRoot.failure(NativeJsonImportFailureCode.invalidRoot);
    }
    return _ParsedRoot.root(raw);
  }

  List<String> _warningsFor(ImportSourceFile source) =>
      source.displayName.toLowerCase().endsWith(nativeJsonFileExtension)
      ? const <String>[]
      : const <String>[NativeJsonImportWarningCode.extensionMismatch];

  AppResult<SongImportResult> _failure(String code) =>
      AppResult<SongImportResult>.failure(ValidationFailure(code: code));
}

final class _SourceRead {
  const _SourceRead.bytes(this.bytes) : isCancelled = false, failureCode = null;
  const _SourceRead.failure(this.failureCode)
    : bytes = null,
      isCancelled = false;
  const _SourceRead.cancelled()
    : bytes = null,
      isCancelled = true,
      failureCode = null;

  final List<int>? bytes;
  final bool isCancelled;
  final String? failureCode;
}

final class _ParsedRoot {
  const _ParsedRoot.root(this.root) : failureCode = null;
  const _ParsedRoot.failure(this.failureCode) : root = null;

  final Map<String, dynamic>? root;
  final String? failureCode;
}

bool _jsonDeepEquals(Object? left, Object? right) {
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_jsonDeepEquals(left[index], right[index])) return false;
    }
    return true;
  }
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_jsonDeepEquals(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}

/// Rejects values the legacy-tolerant persistence codec would silently omit.
/// Native exchange imports are untrusted and must never report success after
/// losing a metadata, entity, event, or technique entry.
bool _wouldDecodeLossily(Map<String, dynamic> document) {
  if (!_isAbsentOrListOfMaps(document['assets']) ||
      !_isAbsentOrListOfMaps(document['markers']) ||
      !_isAbsentOrListOfMaps(document['tracks'])) {
    return true;
  }

  final metadata = document['metadata'];
  if (metadata is Map<String, dynamic> &&
      !_isAbsentOrListOfStrings(metadata['tags'])) {
    return true;
  }
  final source = document['source'];
  if (source is Map<String, dynamic> &&
      !_isAbsentOrListOfStrings(source['warningSummary'])) {
    return true;
  }

  final tracks = document['tracks'];
  if (tracks is! List) return false;
  for (final track in tracks) {
    if (track is! Map<String, dynamic>) continue;
    if (!_isAbsentOrListOfMaps(track['events'])) return true;
    final events = track['events'];
    if (events is! List) continue;
    for (final event in events) {
      if (event is Map<String, dynamic> &&
          !_isAbsentOrListOfMaps(event['techniques'])) {
        return true;
      }
    }
  }
  return false;
}

bool _isAbsentOrListOfMaps(Object? raw) =>
    raw == null ||
    raw is List && raw.every((entry) => entry is Map<String, dynamic>);

bool _isAbsentOrListOfStrings(Object? raw) =>
    raw == null || raw is List && raw.every((entry) => entry is String);

bool _hasDuplicateIds(Map<String, dynamic> document) {
  if (_listHasDuplicateIds(document['assets']) ||
      _listHasDuplicateIds(document['markers']) ||
      _listHasDuplicateIds(document['sections']) ||
      _listHasDuplicateIds(document['tracks'])) {
    return true;
  }
  final tracks = document['tracks'];
  if (tracks is! List) return false;
  for (final track in tracks) {
    if (track is Map<String, dynamic> &&
        _listHasDuplicateIds(track['events'])) {
      return true;
    }
  }
  return false;
}

bool _listHasDuplicateIds(Object? raw) {
  if (raw is! List) return false;
  final ids = <String>{};
  for (final entry in raw) {
    if (entry is! Map<String, dynamic>) continue;
    final id = entry['id'];
    if (id is String && !ids.add(id)) return true;
  }
  return false;
}
