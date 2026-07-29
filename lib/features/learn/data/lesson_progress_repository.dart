import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/logger_provider.dart';
import '../../../core/storage/json_document_store.dart';
import '../../../core/storage/storage_keys.dart';
import '../../../core/storage/storage_providers.dart';

/// Per-lesson best accuracy (0..1), keyed by lesson id (Kör 7 §7.2).
///
/// A map document rather than a record list, so it gets its own decode: one
/// unreadable entry costs that lesson's stars, never the whole progress map.
abstract interface class LessonProgressRepository {
  Map<String, double> load();
  Future<void> save(Map<String, double> progress);

  /// Documented storage bound (§7.5). The built-in curriculum plus every song
  /// ever turned into a lesson stays far below this; the cap exists so a
  /// corrupt or runaway map cannot grow without limit.
  static const int maxLessons = 500;
}

class KeyValueLessonProgressRepository implements LessonProgressRepository {
  const KeyValueLessonProgressRepository(this._document);

  final JsonDocumentStore _document;

  @override
  Map<String, double> load() {
    final body = _document.readBody();
    // `<String, double>{}`, not `const {}`: a const empty literal is a
    // `Map<Never, Never>` at runtime.
    if (body == null) return <String, double>{};
    if (body is! Map) {
      _document.logger.warning(
        'storage.document.body_not_an_object',
        fields: {'document': _document.name},
      );
      return <String, double>{};
    }

    final progress = <String, double>{};
    var skipped = 0;
    for (final entry in body.entries) {
      final key = entry.key;
      final value = entry.value;
      // An accuracy is a fraction: anything else is a value this app never
      // wrote, and guessing at it would show the user stars they never earned.
      if (key is! String ||
          key.isEmpty ||
          value is! num ||
          value.isNaN ||
          value < 0 ||
          value > 1) {
        skipped++;
        continue;
      }
      if (progress.length >= LessonProgressRepository.maxLessons) break;
      progress[key] = value.toDouble();
    }
    if (skipped > 0) {
      _document.logger.warning(
        'storage.document.records_skipped',
        fields: {
          'document': _document.name,
          'skipped': skipped,
          'kept': progress.length,
        },
      );
    }
    return progress;
  }

  @override
  Future<void> save(Map<String, double> progress) {
    final bounded = progress.length <= LessonProgressRepository.maxLessons
        ? progress
        : Map.fromEntries(
            progress.entries.take(LessonProgressRepository.maxLessons),
          );
    return _document.write(bounded);
  }
}

final lessonProgressRepositoryProvider = Provider<LessonProgressRepository>((
  ref,
) {
  return KeyValueLessonProgressRepository(
    JsonDocumentStore(
      store: ref.watch(keyValueStoreProvider),
      logger: ref.watch(appLoggerProvider),
      key: StorageKeys.lessonProgress,
      legacyKey: LegacyStorageKeys.lessonProgress,
      name: 'lesson_progress',
      bodyKey: 'data',
    ),
  );
});
