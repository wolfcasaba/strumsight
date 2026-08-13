/// Per-run model bundle and parsed-model reuse.
library;

import 'dart:typed_data';

/// Reads raw bytes for a model manifest identifier.
typedef ModelBundleReader = Future<Uint8List> Function(String manifestId);

/// Parses one model bundle into the runner's model representation.
typedef ModelParser<T> = T Function(Uint8List bytes);

/// Single-flight parsed-model cache scoped to one analysis run.
///
/// Each [ModelByteCache] instance intentionally has a short lifetime: callers
/// create one for a run, so model changes never outlive the run provenance.
final class ModelByteCache<T> {
  ModelByteCache({required this._readBundle, required this._parse});

  final ModelBundleReader _readBundle;
  final ModelParser<T> _parse;
  final Map<String, Future<T>> _models = <String, Future<T>>{};

  /// Loads and parses [manifestId] once even with concurrent stage callers.
  Future<T> load(String manifestId) {
    if (manifestId.trim().isEmpty) {
      throw ArgumentError.value(manifestId, 'manifestId');
    }
    return _models.putIfAbsent(manifestId, () async {
      final bytes = await _readBundle(manifestId);
      return _parse(bytes);
    });
  }
}
