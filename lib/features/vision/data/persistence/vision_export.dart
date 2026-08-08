/// JSON export of the same allowlisted Vision history representation on disk.
library;

import 'dart:convert';

import '../../../../core/storage/key_value_store.dart';
import 'vision_session_codec.dart';
import 'vision_session_repository.dart';

/// Builds a portable, aggregate-only JSON export without network access.
final class VisionExport {
  VisionExport({
    required KeyValueStore store,
    this.codec = const VisionSessionCodec(),
  }) : _repository = VisionSessionRepository(store: store, codec: codec);

  final VisionSessionCodec codec;
  final VisionSessionRepository _repository;

  /// Canonical JSON, including the item-shape schema version for consumers.
  String exportJson() => jsonEncode(<String, dynamic>{
    'schemaVersion': VisionSessionCodec.currentSchemaVersion,
    'sessions': <Map<String, dynamic>>[
      for (final entry in _repository.list()) codec.encodeToMap(entry),
    ],
  });
}
