import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/i18n/locale_provider.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/logging/logger_provider.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/core/theme/theme_mode_provider.dart';
import 'package:strumsight/features/chords/providers/favorite_chords_provider.dart';
import 'package:strumsight/features/learn/providers/metronome_pref_provider.dart';
import 'package:strumsight/features/learn/providers/practice_speed_provider.dart';
import 'package:strumsight/features/progress/providers/daily_goal_provider.dart';
import 'package:strumsight/features/settings/providers/capo_provider.dart';
import 'package:strumsight/features/settings/providers/confidence_threshold_provider.dart';
import 'package:strumsight/features/settings/providers/input_latency_provider.dart';
import 'package:strumsight/features/settings/providers/lab_mode_provider.dart';
import 'package:strumsight/features/settings/providers/left_handed_provider.dart';
import 'package:strumsight/features/settings/providers/tuning_reference_provider.dart';
import 'package:strumsight/features/settings/providers/visual_latency_provider.dart';
import 'package:strumsight/features/tuner/model/tuning.dart';
import 'package:strumsight/features/tuner/providers/tuner_tuning_provider.dart';

import '../../support/preference_store.dart';

/// E01-R06 — the preference providers now read and write through the injected
/// [KeyValueStore]. Each case pins the same three things: the stored value is
/// visible on the FIRST read (no async gap), a change lands under the
/// namespaced key, and an absent/garbage value degrades to the default.
void main() {
  ProviderContainer containerWith(InMemoryKeyValueStore store) {
    final c = ProviderContainer(overrides: [preferenceStoreOverride(store)]);
    addTearDown(c.dispose);
    return c;
  }

  group('reads the stored value synchronously', () {
    test('theme mode', () {
      final c = containerWith(
        InMemoryKeyValueStore({StorageKeys.themeMode: 'light'}),
      );
      expect(c.read(themeModeProvider), ThemeMode.light);
    });

    test('locale', () {
      final c = containerWith(
        InMemoryKeyValueStore({StorageKeys.locale: 'hu'}),
      );
      expect(c.read(localeProvider), const Locale('hu'));
    });

    test('confidence threshold', () {
      final c = containerWith(
        InMemoryKeyValueStore({StorageKeys.confidenceThreshold: 0.8}),
      );
      expect(c.read(confidenceThresholdProvider), 0.8);
    });

    test('capo', () {
      final c = containerWith(InMemoryKeyValueStore({StorageKeys.capoFret: 4}));
      expect(c.read(capoProvider), 4);
    });

    test('tuning reference', () {
      final c = containerWith(
        InMemoryKeyValueStore({StorageKeys.tuningA4: 442}),
      );
      expect(c.read(tuningReferenceProvider), 442);
    });

    test('left handed', () {
      final c = containerWith(
        InMemoryKeyValueStore({StorageKeys.leftHanded: true}),
      );
      expect(c.read(leftHandedProvider), isTrue);
    });

    test('input + visual latency', () {
      final c = containerWith(
        InMemoryKeyValueStore({
          StorageKeys.inputLatencyMs: -35,
          StorageKeys.visualLatencyMs: 20,
        }),
      );
      expect(c.read(inputLatencyProvider), -35);
      expect(c.read(visualLatencyProvider), 20);
    });

    test('lab mode', () {
      final c = containerWith(
        InMemoryKeyValueStore({StorageKeys.labMode: true}),
      );
      expect(c.read(labModeProvider), isTrue);
    });

    test('tuner tuning', () {
      final c = containerWith(
        InMemoryKeyValueStore({StorageKeys.tunerTuning: Tunings.dropD.id}),
      );
      expect(c.read(tunerTuningProvider).id, Tunings.dropD.id);
    });

    test('favorite chords', () {
      final c = containerWith(
        InMemoryKeyValueStore({
          StorageKeys.favoriteChords: <String>['Am', 'G'],
        }),
      );
      expect(c.read(favoriteChordsProvider), {'Am', 'G'});
    });

    test('metronome muted + practice speed', () {
      final c = containerWith(
        InMemoryKeyValueStore({
          StorageKeys.metronomeMuted: true,
          StorageKeys.practiceSpeed: 0.75,
        }),
      );
      expect(c.read(metronomeMutedProvider), isTrue);
      expect(c.read(practiceSpeedProvider), 0.75);
    });

    test('daily goal', () {
      final c = containerWith(
        InMemoryKeyValueStore({StorageKeys.dailyGoalMinutes: 30}),
      );
      expect(c.read(dailyGoalProvider), 30);
    });
  });

  group('persists under the namespaced key', () {
    test('theme, locale, capo, A4, thresholds and toggles', () async {
      final store = InMemoryKeyValueStore();
      final c = containerWith(store);

      await c.read(themeModeProvider.notifier).setMode(ThemeMode.system);
      await c.read(localeProvider.notifier).set(const Locale('en'));
      await c.read(capoProvider.notifier).set(2);
      await c.read(tuningReferenceProvider.notifier).set(438);
      await c.read(confidenceThresholdProvider.notifier).set(0.6);
      await c.read(leftHandedProvider.notifier).set(true);
      await c.read(inputLatencyProvider.notifier).set(-20);
      await c.read(visualLatencyProvider.notifier).set(15);
      await c.read(labModeProvider.notifier).setEnabled(true);
      await c.read(tunerTuningProvider.notifier).set(Tunings.dropD);
      await c.read(favoriteChordsProvider.notifier).toggle('Em');
      await c.read(metronomeMutedProvider.notifier).toggle();
      await c.read(practiceSpeedProvider.notifier).set(0.5);
      await c.read(dailyGoalProvider.notifier).setGoal(45);

      expect(store.values[StorageKeys.themeMode], 'system');
      expect(store.values[StorageKeys.locale], 'en');
      expect(store.values[StorageKeys.capoFret], 2);
      expect(store.values[StorageKeys.tuningA4], 438);
      expect(store.values[StorageKeys.confidenceThreshold], 0.6);
      expect(store.values[StorageKeys.leftHanded], true);
      expect(store.values[StorageKeys.inputLatencyMs], -20);
      expect(store.values[StorageKeys.visualLatencyMs], 15);
      expect(store.values[StorageKeys.labMode], true);
      expect(store.values[StorageKeys.tunerTuning], Tunings.dropD.id);
      expect(store.values[StorageKeys.favoriteChords], ['Em']);
      expect(store.values[StorageKeys.metronomeMuted], true);
      expect(store.values[StorageKeys.practiceSpeed], 0.5);
      expect(store.values[StorageKeys.dailyGoalMinutes], 45);

      // Nothing wrote to a pre-namespace key: the legacy names are history.
      expect(store.values.keys.where((k) => !k.startsWith('ss.')), isEmpty);
    });

    test(
      'clearing the locale removes the key rather than storing ""',
      () async {
        final store = InMemoryKeyValueStore({StorageKeys.locale: 'hu'});
        final c = containerWith(store);

        await c.read(localeProvider.notifier).set(null);

        expect(store.contains(StorageKeys.locale), isFalse);
        expect(c.read(localeProvider), isNull);
      },
    );
  });

  group('degrades to the default', () {
    test('an empty store gives every provider its documented default', () {
      final c = containerWith(InMemoryKeyValueStore());
      expect(c.read(themeModeProvider), ThemeMode.dark);
      expect(c.read(localeProvider), isNull);
      expect(c.read(capoProvider), CapoNotifier.defaultValue);
      expect(
        c.read(tuningReferenceProvider),
        TuningReferenceNotifier.defaultValue,
      );
      expect(
        c.read(confidenceThresholdProvider),
        ConfidenceThresholdNotifier.defaultValue,
      );
      expect(c.read(leftHandedProvider), isFalse);
      expect(c.read(labModeProvider), isFalse);
      expect(c.read(favoriteChordsProvider), isEmpty);
      expect(
        c.read(practiceSpeedProvider),
        PracticeSpeedController.defaultValue,
      );
      expect(c.read(dailyGoalProvider), DailyGoalController.defaultMinutes);
    });

    test('a value of the wrong type does not crash the provider', () {
      // The store answers null for a type mismatch; the provider must treat
      // that as "not set" (the bytes stay on disk for a later migration).
      final c = containerWith(
        InMemoryKeyValueStore({
          StorageKeys.capoFret: 'three',
          StorageKeys.themeMode: 42,
        }),
      );
      expect(c.read(capoProvider), CapoNotifier.defaultValue);
      expect(c.read(themeModeProvider), ThemeMode.dark);
    });

    test('an out-of-range stored value is clamped', () {
      final c = containerWith(
        InMemoryKeyValueStore({
          StorageKeys.capoFret: 99,
          StorageKeys.tuningA4: 10,
          StorageKeys.confidenceThreshold: 5.0,
          StorageKeys.dailyGoalMinutes: 9999,
        }),
      );
      expect(c.read(capoProvider), CapoNotifier.maxFret);
      expect(c.read(tuningReferenceProvider), TuningReferenceNotifier.minHz);
      expect(c.read(confidenceThresholdProvider), 1.0);
      expect(c.read(dailyGoalProvider), DailyGoalController.maxMinutes);
    });

    test('a practice speed no longer offered falls back', () {
      final c = containerWith(
        InMemoryKeyValueStore({StorageKeys.practiceSpeed: 0.9}),
      );
      expect(
        c.read(practiceSpeedProvider),
        PracticeSpeedController.defaultValue,
      );
    });
  });

  group('race protection (§6.2)', () {
    test('a change made immediately at startup survives', () async {
      // The old providers loaded asynchronously and needed a `_userSet` flag so
      // a late read could not clobber a fresh edit. The read is synchronous
      // now, so there is no window at all — assert the outcome that matters.
      final store = InMemoryKeyValueStore({StorageKeys.capoFret: 5});
      final c = containerWith(store);

      final pending = c.read(capoProvider.notifier).set(7);
      expect(c.read(capoProvider), 7);
      await pending;
      await Future<void>.delayed(Duration.zero);

      expect(c.read(capoProvider), 7);
      expect(store.values[StorageKeys.capoFret], 7);
    });

    test('a favourite toggled at startup merges onto the stored set', () async {
      final store = InMemoryKeyValueStore({
        StorageKeys.favoriteChords: <String>['Am', 'C'],
      });
      final c = containerWith(store);

      await c.read(favoriteChordsProvider.notifier).toggle('G');

      expect(c.read(favoriteChordsProvider), {'Am', 'C', 'G'});
      expect(store.values[StorageKeys.favoriteChords], ['Am', 'C', 'G']);
    });
  });

  test(
    'a rejected write is logged, never swallowed and never thrown',
    () async {
      final store = InMemoryKeyValueStore()
        ..failingKeys.add(StorageKeys.capoFret);
      final logger = _RecordingLogger();
      final c = ProviderContainer(
        overrides: [
          preferenceStoreOverride(store),
          appLoggerProvider.overrideWithValue(logger),
        ],
      );
      addTearDown(c.dispose);

      await c.read(capoProvider.notifier).set(3);

      expect(
        c.read(capoProvider),
        3,
        reason: 'the session keeps the value the user chose',
      );
      expect(logger.events, contains('storage.preference.write_failed'));
    },
  );
}

class _RecordingLogger implements AppLogger {
  final List<String> events = [];

  @override
  void debug(String event, {Map<String, Object?> fields = const {}}) =>
      events.add(event);

  @override
  void info(String event, {Map<String, Object?> fields = const {}}) =>
      events.add(event);

  @override
  void warning(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) => events.add(event);

  @override
  void error(
    String event, {
    required Object error,
    required StackTrace stackTrace,
    Map<String, Object?> fields = const {},
  }) => events.add(event);
}
