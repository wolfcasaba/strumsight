import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/public.dart';
import 'package:strumsight/features/onboarding/public.dart';

import '../../core/storage/in_memory_key_value_store.dart';

/// ADR 0519 acceptance #4 (elavulás), #5 (migráció) és #6 (törlés).
void main() {
  AudioProfile buildProfile({
    String micRouteId = 'wired-headset',
    int sampleRateHz = 48000,
    SignalQualityState state = SignalQualityState.good,
  }) {
    return AudioProfile(
      schemaVersion: AudioProfile.currentSchemaVersion,
      micRouteId: micRouteId,
      sampleRateHz: sampleRateHz,
      suggestedInputGainDb: 1.5,
      inputLatencyMsAtCapture: 40,
      visualLatencyMsAtCapture: 20,
      qualityExpectation: state,
      confidenceProfile: 0.875,
      recordedAt: DateTime.utc(2026, 9, 5, 12),
    );
  }

  group('save/read round trip', () {
    test('a saved profile reads back with every field intact', () async {
      final store = AudioProfileStore(InMemoryKeyValueStore());
      final profile = buildProfile();

      await store.save(profile);

      expect(store.read(), profile);
    });

    test('nothing saved yet reads as null', () {
      final store = AudioProfileStore(InMemoryKeyValueStore());
      expect(store.read(), isNull);
    });
  });

  group('acceptance #6 — deletion', () {
    test('clear() removes the stored profile; it is not read back', () async {
      final backing = InMemoryKeyValueStore();
      final store = AudioProfileStore(backing);
      await store.save(buildProfile());
      expect(store.read(), isNotNull);

      await store.clear();

      expect(store.read(), isNull);
      expect(backing.contains(AudioProfileStore.storageKey), isFalse);
    });
  });

  group('acceptance #4 — staleness on mic-route/sample-rate change', () {
    test(
      'readValid returns the profile when the environment is unchanged',
      () async {
        final store = AudioProfileStore(InMemoryKeyValueStore());
        await store.save(
          buildProfile(micRouteId: 'wired-headset', sampleRateHz: 48000),
        );

        final valid = store.readValid(
          currentMicRouteId: 'wired-headset',
          currentSampleRateHz: 48000,
        );

        expect(valid, isNotNull);
      },
    );

    test('a mic-route change makes the profile stale — readValid does not '
        'return it as valid', () async {
      final store = AudioProfileStore(InMemoryKeyValueStore());
      final profile = buildProfile(
        micRouteId: 'wired-headset',
        sampleRateHz: 48000,
      );
      await store.save(profile);

      expect(
        profile.isStaleFor(
          currentMicRouteId: 'bluetooth-a2dp',
          currentSampleRateHz: 48000,
        ),
        isTrue,
      );
      expect(
        store.readValid(
          currentMicRouteId: 'bluetooth-a2dp',
          currentSampleRateHz: 48000,
        ),
        isNull,
      );
    });

    test('a sample-rate change makes the profile stale — readValid does not '
        'return it as valid', () async {
      final store = AudioProfileStore(InMemoryKeyValueStore());
      final profile = buildProfile(
        micRouteId: 'wired-headset',
        sampleRateHz: 48000,
      );
      await store.save(profile);

      expect(
        store.readValid(
          currentMicRouteId: 'wired-headset',
          currentSampleRateHz: 44100,
        ),
        isNull,
      );
    });
  });

  group('acceptance #5 — versioned decode and migration', () {
    test('an unknown (future) schemaVersion throws a typed ArgumentError', () {
      final backing = InMemoryKeyValueStore({
        AudioProfileStore.storageKey: jsonEncode({
          'schemaVersion': 999,
          'micRouteId': 'wired-headset',
          'sampleRateHz': 48000,
          'suggestedInputGainDb': 0.0,
          'inputLatencyMsAtCapture': 0,
          'visualLatencyMsAtCapture': 0,
          'qualityExpectation': 'good',
          'confidenceProfile': 1.0,
          'recordedAt': '2026-09-05T12:00:00.000Z',
        }),
      });
      final store = AudioProfileStore(backing);

      expect(() => store.read(), throwsArgumentError);
    });

    test('the supported legacy v0 schema migrates forward — every field '
        'matches the expected mapping (L70: no field is lost)', () {
      final backing = InMemoryKeyValueStore({
        AudioProfileStore.storageKey: jsonEncode({
          'schemaVersion': 0,
          'route': 'wired-headset',
          'sampleRate': 44100,
          'gainDb': 2.5,
          'inputLatencyMs': 12,
          'visualLatencyMs': 8,
          'quality': 'good',
          'confidence': 0.75,
          'recordedAtEpochMs': 1757073600000,
        }),
      });
      final store = AudioProfileStore(backing);

      final migrated = store.read();

      expect(migrated, isNotNull);
      expect(migrated!.schemaVersion, AudioProfile.currentSchemaVersion);
      expect(migrated.micRouteId, 'wired-headset');
      expect(migrated.sampleRateHz, 44100);
      expect(migrated.suggestedInputGainDb, 2.5);
      expect(migrated.inputLatencyMsAtCapture, 12);
      expect(migrated.visualLatencyMsAtCapture, 8);
      expect(migrated.qualityExpectation, SignalQualityState.good);
      expect(migrated.confidenceProfile, 0.75);
      expect(
        migrated.recordedAt,
        DateTime.fromMillisecondsSinceEpoch(1757073600000, isUtc: true),
      );
    });

    test('a missing schemaVersion is a typed ArgumentError, not a default '
        'profile', () {
      final backing = InMemoryKeyValueStore({
        AudioProfileStore.storageKey: jsonEncode({'micRouteId': 'x'}),
      });
      final store = AudioProfileStore(backing);

      expect(() => store.read(), throwsArgumentError);
    });
  });
}
