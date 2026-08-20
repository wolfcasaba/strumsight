import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/storage/json_document_store.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/gamification/data/migration/legacy_streak_migrator.dart';
import 'package:strumsight/features/gamification/domain/streak/streak_policy.dart';
import 'package:strumsight/features/gamification/domain/streak/streak_state.dart';
import 'package:strumsight/features/gamification/domain/streak/streak_transition.dart';

import '../../../support/preference_store.dart';

void main() {
  const legacy = <String, Object>{
    'current': 4,
    'longest': 12,
    'last': 20004,
    'freezes': 2,
    'total': 19,
  };

  group('A1, A2, A3, A9, A10 — legacy streak migration', () {
    test('preserves every legacy field and exposes the legacy projection', () {
      final store = InMemoryKeyValueStore(<String, Object>{
        StorageKeys.streak: _envelope(legacy),
      });

      final migrated = LegacyStreakMigrator(store).migrate()!;

      expect(migrated.current, legacy['current']);
      expect(migrated.longest, legacy['longest']);
      expect(migrated.lastQualifiedDay, legacy['last']);
      expect(migrated.freezes, legacy['freezes']);
      expect(migrated.totalQualifiedDays, legacy['total']);
      expect(migrated.policyVersion, streakPolicyVersion);
      expect(migrated.graceState, StreakGraceState.none);
      expect(migrated.plannedRestDays, isEmpty);
      expect(
        migrated.toLegacyProjection(),
        const LegacyStreakProjection(
          current: 4,
          longest: 12,
          lastPracticeDay: 20004,
          freezes: 2,
          totalDays: 19,
        ),
      );
    });

    test(
      'is idempotent and leaves both source documents byte-for-byte intact',
      () {
        final namespaced = _envelope(legacy);
        final raw = jsonEncode(<String, Object>{
          ...legacy,
          'unknown': 'ignored',
        });
        final store = InMemoryKeyValueStore(<String, Object>{
          StorageKeys.streak: namespaced,
          LegacyStorageKeys.streak: raw,
        });
        final migrator = LegacyStreakMigrator(store);

        final first = migrator.migrate();
        final second = migrator.migrate();

        expect(second, first);
        expect(store.readString(StorageKeys.streak), namespaced);
        expect(store.readString(LegacyStorageKeys.streak), raw);
        expect(store.writeLog, isEmpty);
      },
    );

    test('falls back to the raw legacy body and ignores unknown fields', () {
      final raw = jsonEncode(<String, Object>{...legacy, 'unexpected': true});
      final store = InMemoryKeyValueStore(<String, Object>{
        LegacyStorageKeys.streak: raw,
      });

      expect(LegacyStreakMigrator(store).migrate(), _stateFromLegacy());
      expect(store.writeLog, isEmpty);
    });

    test('accepts equivalent namespaced and raw legacy sources', () {
      final fromEnvelope = LegacyStreakMigrator(
        InMemoryKeyValueStore(<String, Object>{
          StorageKeys.streak: _envelope(legacy),
        }),
      ).migrate();
      final fromRaw = LegacyStreakMigrator(
        InMemoryKeyValueStore(<String, Object>{
          LegacyStorageKeys.streak: jsonEncode(legacy),
        }),
      ).migrate();

      expect(fromEnvelope, fromRaw);
    });

    test(
      'does not hide a malformed or future namespaced envelope with fallback',
      () {
        final corrupt = InMemoryKeyValueStore(<String, Object>{
          StorageKeys.streak: '{',
          LegacyStorageKeys.streak: jsonEncode(legacy),
        });
        final future = InMemoryKeyValueStore(<String, Object>{
          StorageKeys.streak: jsonEncode(<String, Object>{
            'schemaVersion': documentSchemaVersion + 1,
            'data': legacy,
          }),
          LegacyStorageKeys.streak: jsonEncode(legacy),
        });

        expect(
          () => LegacyStreakMigrator(corrupt).migrate(),
          throwsFormatException,
        );
        expect(
          () => LegacyStreakMigrator(future).migrate(),
          throwsFormatException,
        );
      },
    );
  });

  group('A4 and A6 — pure qualified-day transition matrix', () {
    const policy = StreakPolicy();

    test('first qualified day starts a streak with a reason', () {
      final transition = policy.applyQualifiedDay(_emptyState(), 100);

      expect(transition.state.current, 1);
      expect(transition.reason, StreakTransitionReason.firstQualifiedDay);
    });

    test('same day and backwards clock are distinct no-op reasons', () {
      final state = _state(lastQualifiedDay: 100, current: 3, longest: 7);

      final sameDay = policy.applyQualifiedDay(state, 100);
      final backwards = policy.applyQualifiedDay(state, 99);

      expect(identical(sameDay.state, state), isTrue);
      expect(sameDay.reason, StreakTransitionReason.alreadyQualifiedToday);
      expect(identical(backwards.state, state), isTrue);
      expect(backwards.reason, StreakTransitionReason.clockMovedBackwards);
    });

    test(
      'gap one continues, gap two spends a freeze, and uncovered gaps reset',
      () {
        final prior = _state(lastQualifiedDay: 100, current: 4, longest: 9);
        final consecutive = policy.applyQualifiedDay(prior, 101);
        final covered = policy.applyQualifiedDay(
          prior.copyWith(freezes: 1),
          102,
        );
        final uncovered = policy.applyQualifiedDay(prior, 102);
        final tooLarge = policy.applyQualifiedDay(
          prior.copyWith(freezes: 1),
          103,
        );

        expect(consecutive.state.current, 5);
        expect(
          consecutive.reason,
          StreakTransitionReason.consecutiveQualifiedDay,
        );
        expect(covered.state.current, 5);
        expect(covered.state.freezes, 0);
        expect(covered.reason, StreakTransitionReason.freezeCoveredMissedDay);
        expect(uncovered.state.current, 1);
        expect(uncovered.reason, StreakTransitionReason.resetAfterMissedDays);
        expect(tooLarge.state.current, 1);
        expect(tooLarge.state.freezes, 1);
      },
    );

    test(
      'awards a freeze on every seventh qualified day and caps it at three',
      () {
        var state = _emptyState();
        for (var day = 100; day < 100 + 30; day++) {
          state = policy.applyQualifiedDay(state, day).state;
        }

        expect(state.totalQualifiedDays, 30);
        expect(state.freezes, StreakPolicy.maxFreezes);
      },
    );
  });

  group('A5 — domain isolation', () {
    test(
      'policy takes its qualified day from the caller and has no clock or IO',
      () {
        final source = File(
          'lib/features/gamification/domain/streak/streak_policy.dart',
        ).readAsStringSync();

        expect(
          source,
          contains('applyQualifiedDay(StreakState previous, int qualifiedDay)'),
        );
        expect(source, isNot(contains('DateTime.now')));
        expect(source, isNot(contains('KeyValueStore')));
      },
    );

    test('planned rest days are protected from mutation', () {
      final state = _state(plannedRestDays: <int>{3});

      expect(() => state.plannedRestDays.add(4), throwsUnsupportedError);
      expect(state.plannedRestDays, <int>{3});
    });
  });
}

String _envelope(Map<String, Object> body) => jsonEncode(<String, Object>{
  'schemaVersion': documentSchemaVersion,
  'data': body,
});

StreakState _emptyState() => _state();

StreakState _state({
  int current = 0,
  int longest = 0,
  int lastQualifiedDay = -1,
  int totalQualifiedDays = 0,
  int freezes = 0,
  Set<int> plannedRestDays = const <int>{},
}) => StreakState(
  current: current,
  longest: longest,
  lastQualifiedDay: lastQualifiedDay,
  totalQualifiedDays: totalQualifiedDays,
  freezes: freezes,
  plannedRestDays: plannedRestDays,
);

StreakState _stateFromLegacy() => StreakState(
  current: 4,
  longest: 12,
  lastQualifiedDay: 20004,
  freezes: 2,
  totalQualifiedDays: 19,
);
