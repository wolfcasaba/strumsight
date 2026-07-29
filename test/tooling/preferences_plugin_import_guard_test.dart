import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// E01-R06 acceptance §6.1 — the migrated providers must not hold their own
/// `SharedPreferences` instance any more.
///
/// The guard is a whitelist rather than a per-file assertion so it keeps
/// working as Kör 7 lands: every file that still talks to the plugin is listed
/// here with the round that will move it. The list may only ever shrink — a new
/// direct importer fails this test.
void main() {
  /// The one production file allowed to touch the plugin: the store itself.
  const storeImplementation = 'lib/core/storage/shared_preferences_store.dart';

  /// JSON-blob stores still on the plugin; SDD Ch2 Kör 7 migrates them.
  const pendingKor7 = <String>{
    'lib/features/learn/providers/lesson_progress_provider.dart',
    'lib/features/library/data/library_repository.dart',
    'lib/features/progress/providers/practice_log_provider.dart',
    'lib/features/songs/providers/setlists_provider.dart',
    'lib/features/songs/providers/songs_provider.dart',
    'lib/features/streak/providers/streak_provider.dart',
  };

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
      importers.difference({storeImplementation, ...pendingKor7}),
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

  test('every preference migrated in Kör 6 is off the plugin', () {
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
