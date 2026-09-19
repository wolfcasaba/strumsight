// Today's best of the 60-second strum challenge: the per-day record, its
// persistence in the streak-shaped document envelope, and the day boundary.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/storage/json_document_store.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/strum_challenge/public.dart';

import '../../support/preference_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryKeyValueStore store;
  setUp(() => store = InMemoryKeyValueStore());

  /// A container over the shared [store], with the calendar pinned to [now].
  ProviderContainer containerAt(DateTime now) {
    final container = ProviderContainer(
      overrides: [
        preferenceStoreOverride(store),
        strumChallengeClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  final monday = DateTime(2026, 9, 14, 10);

  test('the date key is the LOCAL calendar day, zero-padded', () {
    expect(
      StrumChallengeBest.dateKeyOf(DateTime(2026, 9, 4, 23, 59)),
      '2026-09-04',
    );
    expect(StrumChallengeBest.dateKeyOf(DateTime(2026, 12, 31)), '2026-12-31');
  });

  test('starts empty, records a best, and reports a new best only when '
      'beaten', () async {
    final c = containerAt(monday);
    expect(c.read(strumChallengeBestProvider), isNull);
    final n = c.read(strumChallengeBestProvider.notifier);

    expect(await n.recordAttempt(score: 40, patterns: 3), isTrue);
    expect(
      c.read(strumChallengeBestProvider),
      const StrumChallengeBest(
        dateKey: '2026-09-14',
        bestScore: 40,
        bestPatterns: 3,
        attempts: 1,
      ),
    );

    // A lower run counts as an attempt and changes nothing else — the
    // patterns travel with the run that set the score, never separately.
    expect(await n.recordAttempt(score: 30, patterns: 5), isFalse);
    expect(
      c.read(strumChallengeBestProvider),
      const StrumChallengeBest(
        dateKey: '2026-09-14',
        bestScore: 40,
        bestPatterns: 3,
        attempts: 2,
      ),
    );

    // Equal is not beaten.
    expect(await n.recordAttempt(score: 40, patterns: 6), isFalse);
    expect(c.read(strumChallengeBestProvider)!.bestPatterns, 3);

    expect(await n.recordAttempt(score: 41, patterns: 4), isTrue);
    expect(
      c.read(strumChallengeBestProvider),
      const StrumChallengeBest(
        dateKey: '2026-09-14',
        bestScore: 41,
        bestPatterns: 4,
        attempts: 4,
      ),
    );
  });

  test('a scoreless first run is recorded but is not a "new best"', () async {
    final c = containerAt(monday);
    final n = c.read(strumChallengeBestProvider.notifier);
    expect(await n.recordAttempt(score: 0, patterns: 0), isFalse);
    expect(c.read(strumChallengeBestProvider)!.attempts, 1);
    expect(c.read(strumChallengeBestProvider)!.bestScore, 0);
  });

  test('persists across a fresh container on the same day', () async {
    final c1 = containerAt(monday);
    await c1
        .read(strumChallengeBestProvider.notifier)
        .recordAttempt(score: 57, patterns: 8);
    expect(c1.read(strumChallengeBestProvider)!.bestScore, 57);

    final c2 = containerAt(monday.add(const Duration(hours: 9)));
    expect(c2.read(strumChallengeBestProvider)!.bestScore, 57);
    expect(c2.read(strumChallengeBestProvider)!.attempts, 1);
  });

  test('a new day starts fresh, and the first run of that day is '
      'attempt 1', () async {
    final c1 = containerAt(monday);
    await c1
        .read(strumChallengeBestProvider.notifier)
        .recordAttempt(score: 57, patterns: 8);

    final tuesday = containerAt(monday.add(const Duration(days: 1)));
    expect(
      tuesday.read(strumChallengeBestProvider),
      isNull,
      reason: "yesterday's best is not today's",
    );
    expect(
      await tuesday
          .read(strumChallengeBestProvider.notifier)
          .recordAttempt(score: 12, patterns: 1),
      isTrue,
    );
    expect(
      tuesday.read(strumChallengeBestProvider),
      const StrumChallengeBest(
        dateKey: '2026-09-15',
        bestScore: 12,
        bestPatterns: 1,
        attempts: 1,
      ),
    );
  });

  test('the document is the versioned envelope under the catalogue '
      'key', () async {
    final c = containerAt(monday);
    await c
        .read(strumChallengeBestProvider.notifier)
        .recordAttempt(score: 57, patterns: 8);

    final raw = store.values[StorageKeys.strumChallengeBest];
    expect(raw, isA<String>());
    final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
    expect(decoded['schemaVersion'], documentSchemaVersion);
    expect(decoded['data'], {
      'dateKey': '2026-09-14',
      'bestScore': 57,
      'bestPatterns': 8,
      'attempts': 1,
    });
  });

  test('a corrupt document yields no best, never a crash', () {
    store.values[StorageKeys.strumChallengeBest] = 'not json at all';
    final c = containerAt(monday);
    expect(c.read(strumChallengeBestProvider), isNull);
  });

  test('a record with a negative counter is rejected as a whole', () {
    store.values[StorageKeys.strumChallengeBest] = storedDocument({
      'dateKey': '2026-09-14',
      'bestScore': -1,
      'bestPatterns': 0,
      'attempts': 1,
    });
    final c = containerAt(monday);
    expect(c.read(strumChallengeBestProvider), isNull);
  });
}
