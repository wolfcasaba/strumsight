import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// E01-R06 §6.1 + E01-R07 §7.2 acceptance — no feature holds its own
/// `SharedPreferences` instance any more.
///
/// With Kör 7 the allowlist is EMPTY: the store implementation is the only
/// production file left that imports the plugin. The list may only ever shrink
/// — a new direct importer fails this test.
void main() {
  /// The one production file allowed to touch the plugin: the store itself.
  const storeImplementation = 'lib/core/storage/shared_preferences_store.dart';

  /// Nothing is waiting to be migrated any more (E01-R07 moved the last six).
  const pending = <String>{};

  test('only the storage layer imports shared_preferences', () {
    final importers = <String>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains("import 'package:shared_preferences/")) {
        importers.add(entity.path);
      }
    }

    expect(
      importers.difference({storeImplementation, ...pending}),
      isEmpty,
      reason:
          'a feature must depend on KeyValueStore, not on the plugin — '
          'inject keyValueStoreProvider instead',
    );
    expect(
      importers,
      contains(storeImplementation),
      reason: 'the store implementation is the one legitimate importer',
    );
  });

  test('every migrated feature is off the plugin', () {
    const migrated = <String>[
      'lib/core/theme/theme_mode_provider.dart',
      'lib/core/i18n/locale_provider.dart',
      'lib/features/onboarding/onboarding_provider.dart',
      'lib/features/settings/providers/confidence_threshold_provider.dart',
      'lib/features/settings/providers/left_handed_provider.dart',
      'lib/features/settings/providers/capo_provider.dart',
      'lib/features/settings/providers/tuning_reference_provider.dart',
      'lib/features/settings/providers/input_latency_provider.dart',
      'lib/features/settings/providers/visual_latency_provider.dart',
      'lib/features/settings/providers/lab_mode_provider.dart',
      'lib/features/settings/providers/nudge_enabled_provider.dart',
      'lib/features/tuner/providers/tuner_tuning_provider.dart',
      'lib/features/learn/providers/metronome_pref_provider.dart',
      'lib/features/learn/providers/practice_speed_provider.dart',
      'lib/features/chords/providers/favorite_chords_provider.dart',
      'lib/features/progress/providers/daily_goal_provider.dart',
      // E01-R07 — the user-content and progress documents.
      'lib/features/learn/data/lesson_progress_repository.dart',
      'lib/features/learn/providers/lesson_progress_provider.dart',
      'lib/features/library/data/library_repository.dart',
      'lib/features/progress/data/practice_log_repository.dart',
      'lib/features/progress/providers/practice_log_provider.dart',
      'lib/features/songs/data/setlists_repository.dart',
      'lib/features/songs/data/songs_repository.dart',
      'lib/features/songs/providers/setlists_provider.dart',
      'lib/features/songs/providers/songs_provider.dart',
      'lib/features/streak/data/streak_repository.dart',
      'lib/features/streak/providers/streak_provider.dart',
    ];

    for (final path in migrated) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path is missing');
      expect(
        file.readAsStringSync(),
        isNot(contains('shared_preferences')),
        reason: '$path was migrated in E01-R06 and must use KeyValueStore',
      );
    }
  });
}
