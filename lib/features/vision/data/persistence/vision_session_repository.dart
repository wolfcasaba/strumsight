/// Local-only history for completed, aggregate-only Vision sessions.
library;

import '../../../../core/logging/app_logger.dart';
import '../../../../core/ml/vision_model_manifest.dart';
import '../../../../core/storage/json_document_store.dart';
import '../../../../core/storage/key_value_store.dart';
import '../../../../core/storage/storage_keys.dart';
import '../../domain/vision_privacy_control.dart';
import '../../domain/vision_session_result.dart';
import 'vision_session_codec.dart';

/// Persists at most [VisionPrivacyControl.maxStoredSessions] newest summaries.
///
/// It deliberately accepts only local storage and a codec: no network client
/// can be introduced through this boundary.
final class VisionSessionRepository {
  VisionSessionRepository({
    required KeyValueStore store,
    this.codec = const VisionSessionCodec(),
    VisionModelManifestReader? manifestReader,
  }) : _sessions = JsonCollectionStore<VisionSessionHistoryEntry>(
         document: JsonDocumentStore(
           store: store,
           logger: const NoopAppLogger(),
           key: StorageKeys.visionSessionHistory,
           // This is a reserved non-shipped key required by the generic
           // document contract; R28 has no legacy predecessor to migrate.
           legacyKey: 'vision_session_history',
           name: 'vision_session_history',
         ),
         fromJson: codec.decodeFromMap,
         toJson: codec.encodeToMap,
         maxItems: VisionPrivacyControl.maxStoredSessions,
       ),
       _store = store,
       _manifestReader = manifestReader ?? FileVisionModelManifestReader();

  final KeyValueStore _store;
  final VisionSessionCodec codec;
  final JsonCollectionStore<VisionSessionHistoryEntry> _sessions;
  final VisionModelManifestReader _manifestReader;

  List<VisionSessionHistoryEntry> list() => _sessions.read();

  Future<void> save(VisionSessionResult result) async {
    final entry = codec.fromResult(
      result,
      modelVersions: await _readModelVersions(),
    );
    final current = list();
    await _sessions.write(<VisionSessionHistoryEntry>[
      entry,
      for (final existing in current)
        if (existing.sessionId != entry.sessionId) existing,
    ]);
  }

  /// Reads model IDs and versions before writing so a stored summary remains
  /// attributable after a later model update.
  ///
  /// A map preserves model identity when one session uses several models. An
  /// unreadable, invalid, or empty manifest fails the save before history is
  /// changed, rather than creating a record without provenance.
  Future<Map<String, String>> _readModelVersions() async {
    final report = await _manifestReader.read();
    if (!report.isClean || report.entries.isEmpty) {
      throw StateError('Vision model manifest cannot supply model versions.');
    }

    final versions = <String, String>{};
    for (final entry in report.entries) {
      if (versions.containsKey(entry.modelId)) {
        throw StateError('Vision model manifest contains duplicate model IDs.');
      }
      versions[entry.modelId] = entry.version;
    }
    return versions;
  }

  Future<void> deleteSession(String sessionId) async {
    await _sessions.write(
      list().where((entry) => entry.sessionId != sessionId).toList(),
    );
  }

  /// Permanently removes all currently persisted Vision data and quarantine
  /// shadows. This is intentionally raw key removal, never a soft delete.
  Future<void> deleteAllVisionData() async {
    for (final key in StorageKeys.visionData) {
      await _store.remove(key);
      await _store.remove(StorageKeys.quarantineOf(key));
    }
  }
}
