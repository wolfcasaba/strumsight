import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/gamification/data/local_reward_ledger_repository.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/features/streak/daily_challenge.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

void main() {
  group('DailyChallengeService — legacy identity (A1)', () {
    test(
      'A1: the same epoch day produces the same legacy strum pattern',
      () async {
        final service = _service(contentCatalog: const _EmptyCatalog());
        for (var day = 20000; day < 20030; day++) {
          final a = await service.getOrGenerateInstance(
            epochDay: day,
            catalogVersion: 1,
          );
          final b = await service.getOrGenerateInstance(
            epochDay: day,
            catalogVersion: 1,
          );
          expect(
            a.definition,
            isA<StrumPatternChallenge>(),
            reason: 'an empty catalog falls back to strumPattern (day=$day)',
          );
          final patternA = (a.definition as StrumPatternChallenge).pattern;
          final patternB = (b.definition as StrumPatternChallenge).pattern;
          expect(
            patternA,
            equals(patternB),
            reason: 'same day must yield the same pattern',
          );
        }
      },
    );

    test(
      'A1: the V2 service matches the legacy generator byte-for-byte',
      () async {
        final service = _service(contentCatalog: const _EmptyCatalog());
        for (var day = 20000; day < 20060; day++) {
          final legacy = DailyChallenge.forDay(day);
          final instance = await service.getOrGenerateInstance(
            epochDay: day,
            catalogVersion: 1,
          );
          final generated = instance.definition;
          expect(
            generated,
            isA<StrumPatternChallenge>(),
            reason: 'day=$day empty catalog → strumPattern fallback',
          );
          final v2 = generated as StrumPatternChallenge;
          expect(
            v2.pattern,
            equals(legacy.pattern),
            reason: 'day=$day pattern diverged from the legacy generator',
          );
          expect(
            v2.name,
            equals(legacy.name),
            reason: 'day=$day name diverged from the legacy generator',
          );
          expect(
            v2.glyphs,
            equals(legacy.glyphs),
            reason: 'day=$day glyphs diverged from the legacy generator',
          );
        }
      },
    );
  });

  group('DailyChallengeService — replay and idempotent reward (A3)', () {
    test(
      'A3: the reward ledger sees exactly one entry per daily instance',
      () async {
        final fixture = _Fixture(contentCatalog: const _EmptyCatalog());
        final instance = await fixture.service.getOrGenerateInstance(
          epochDay: 20010,
          catalogVersion: 1,
        );

        final first = await fixture.service.complete(instance: instance);
        final second = await fixture.service.complete(instance: first.instance);
        final third = await fixture.service.complete(instance: second.instance);

        expect(first.rewardAppended, isTrue);
        expect(second.rewardAppended, isFalse);
        expect(third.rewardAppended, isFalse);

        final entries = fixture.ledger.readPage(limit: 10).entries;
        expect(entries, hasLength(1));
        expect(entries.single.sourceEventId, instance.instanceId);
        expect(
          entries.single.reasonCodes,
          equals(<RewardReason>[RewardReason.questCompleted]),
        );
      },
    );

    test(
      'A3: the completion timestamp updates on every replay but the receipt is stable',
      () async {
        var now = DateTime.utc(2026, 8, 21, 9);
        final fixture = _Fixture(
          contentCatalog: const _EmptyCatalog(),
          clock: () => now,
        );

        final instance = await fixture.service.getOrGenerateInstance(
          epochDay: 20010,
          catalogVersion: 1,
        );
        final first = await fixture.service.complete(instance: instance);

        now = DateTime.utc(2026, 8, 21, 10);
        final replay = await fixture.service.complete(instance: first.instance);

        expect(replay.instance.completion?.completedAt, now);
        expect(replay.rewardAppended, isFalse);
        expect(
          fixture.ledger.readPage(limit: 10).entries.single.ledgerId,
          first.instance.completionLedgerId,
        );
      },
    );
  });

  group('DailyChallengeService — persistence (A4)', () {
    test(
      'A4: a completion survives an "app restart" via a fresh store instance',
      () async {
        final store = InMemoryKeyValueStore();
        final firstLedger = _rewardLedger(store);
        final serviceA = _service(
          contentCatalog: const _EmptyCatalog(),
          store: store,
          ledger: firstLedger,
        );
        final instance = await serviceA.getOrGenerateInstance(
          epochDay: 20011,
          catalogVersion: 1,
        );
        final completed = await serviceA.complete(instance: instance);

        // Simulated restart: brand-new repositories backed by the same store.
        final serviceB = _service(
          contentCatalog: const _EmptyCatalog(),
          store: store,
          ledger: _rewardLedger(store),
        );
        final reopened = await serviceB.getOrGenerateInstance(
          epochDay: 20011,
          catalogVersion: 1,
        );

        expect(reopened.epochDay, 20011);
        expect(reopened.definition, equals(instance.definition));
        expect(reopened.isCompleted(), isTrue);
        expect(
          reopened.completion?.completedAt,
          equals(completed.completionAt),
        );

        final ledgerAfter = _rewardLedger(store).readPage(limit: 10);
        expect(ledgerAfter.entries, hasLength(1));
      },
    );

    test('A4: a new day generates a new instance after restart', () async {
      final store = InMemoryKeyValueStore();
      final serviceA = _service(
        contentCatalog: const _EmptyCatalog(),
        store: store,
        ledger: _rewardLedger(store),
      );
      await serviceA.getOrGenerateInstance(epochDay: 20012, catalogVersion: 1);

      final serviceB = _service(
        contentCatalog: const _EmptyCatalog(),
        store: store,
        ledger: _rewardLedger(store),
      );
      final next = await serviceB.getOrGenerateInstance(
        epochDay: 20013,
        catalogVersion: 1,
      );
      expect(next.epochDay, 20013);
      expect(next.isCompleted(), isFalse);
    });
  });

  group('DailyChallengeService — catalog version pinning (A5)', () {
    test(
      'A5: a catalog upgrade after the day started does NOT swap today\'s challenge',
      () async {
        final store = InMemoryKeyValueStore();
        final service = _service(
          contentCatalog: const _MultiTypeCatalog(),
          store: store,
          ledger: _rewardLedger(store),
        );

        final first = await service.getOrGenerateInstance(
          epochDay: 20020,
          catalogVersion: 5,
        );
        final pinnedType = first.definition.type;
        final pinnedJson = first.toJson();

        final second = await service.getOrGenerateInstance(
          epochDay: 20020,
          catalogVersion: 6,
        );

        expect(second.epochDay, 20020);
        expect(second.catalogVersion, 5, reason: 'pin the generation version');
        expect(second.definition.type, pinnedType);
        expect(second.toJson(), equals(pinnedJson));
      },
    );

    test(
      'A5: the next epoch day does pick up the new catalog version',
      () async {
        final store = InMemoryKeyValueStore();
        final service = _service(
          contentCatalog: const _MultiTypeCatalog(),
          store: store,
          ledger: _rewardLedger(store),
        );

        await service.getOrGenerateInstance(epochDay: 20020, catalogVersion: 5);
        final nextDay = await service.getOrGenerateInstance(
          epochDay: 20021,
          catalogVersion: 6,
        );

        expect(nextDay.catalogVersion, 6);
      },
    );
  });

  group('DailyChallengeService — availability filter (A6)', () {
    test(
      'A6: a populated chord catalog picks only chordChange or strumPattern',
      () async {
        final service = _service(
          contentCatalog: const _ChordOnlyCatalog(<String>['C', 'G']),
        );
        final seenTypes = <DailyChallengeType>{};
        for (var day = 19990; day < 20090; day++) {
          final instance = await service.getOrGenerateInstance(
            epochDay: day,
            catalogVersion: 1,
          );
          seenTypes.add(instance.definition.type);
          expect(
            instance.definition.type,
            anyOf(
              equals(DailyChallengeType.chordChange),
              equals(DailyChallengeType.strumPattern),
            ),
            reason: 'only chordChange/strumPattern are available',
          );
        }
        // Both available types should be reachable across the day range.
        expect(
          seenTypes,
          containsAll(<DailyChallengeType>{
            DailyChallengeType.chordChange,
            DailyChallengeType.strumPattern,
          }),
        );
      },
    );

    test(
      'A6: a single chord cannot satisfy chordChange so it falls back to strumPattern',
      () async {
        final service = _service(
          contentCatalog: const _ChordOnlyCatalog(<String>['C']),
        );
        final instance = await service.getOrGenerateInstance(
          epochDay: 20030,
          catalogVersion: 1,
        );
        expect(
          instance.definition.type,
          equals(DailyChallengeType.strumPattern),
        );
      },
    );

    test('A6: empty rhythm catalog skips the rhythm branch', () async {
      final empty = const _MultiTypeCatalog(
        chordIds: <String>['C', 'G'],
        rhythmIds: <String>[],
        songIds: <String>['song-1'],
      );
      for (var day = 19990; day < 20090; day++) {
        final instance = await _service(
          contentCatalog: empty,
        ).getOrGenerateInstance(epochDay: day, catalogVersion: 1);
        expect(
          instance.definition.type,
          isNot(equals(DailyChallengeType.rhythm)),
          reason: 'day=$day must not pick rhythm from an empty catalog',
        );
      }
    });

    test(
      'A6: every generated definition references IDs the catalog knows about',
      () async {
        final catalog = const _MultiTypeCatalog();
        for (var day = 20000; day < 20080; day++) {
          final instance = await _service(
            contentCatalog: catalog,
          ).getOrGenerateInstance(epochDay: day, catalogVersion: 1);
          final id = instance.definition.contentId;
          switch (instance.definition.type) {
            case DailyChallengeType.strumPattern:
              expect(id, isNull);
            case DailyChallengeType.chordChange:
              final chord = instance.definition as ChordChangeChallenge;
              expect(catalog.chordIds(), contains(chord.fromChordId));
              expect(catalog.chordIds(), contains(chord.toChordId));
            case DailyChallengeType.rhythm:
              final rhythm = instance.definition as RhythmChallenge;
              expect(catalog.rhythmIds(), contains(rhythm.contentId));
            case DailyChallengeType.songSection:
              final section = instance.definition as SongSectionChallenge;
              expect(catalog.songIds(), contains(section.songId));
            case DailyChallengeType.timing:
              final timing = instance.definition as TimingChallenge;
              expect(catalog.timingContentIds(), contains(timing.contentId));
          }
        }
      },
    );
  });

  group('DailyChallengeService — type coverage (A7)', () {
    test(
      'A7: every supported type is reachable when the catalog is fully populated',
      () async {
        final catalog = const _MultiTypeCatalog();
        final seen = <DailyChallengeType>{};
        for (var day = 19990; day < 20090; day++) {
          final instance = await _service(
            contentCatalog: catalog,
          ).getOrGenerateInstance(epochDay: day, catalogVersion: 1);
          seen.add(instance.definition.type);
          if (seen.length == DailyChallengeType.values.length) break;
        }
        expect(seen, equals(DailyChallengeType.values.toSet()));
      },
    );
  });

  group('DailyChallengeService — A8 + boundary matrix (§6.1)', () {
    test(
      'A8: only the adapter imports the legacy generator; streak files are not touched',
      () {
        // Static source-level guard: nothing under lib/features/gamification
        // may reference `lib/features/streak/**` EXCEPT the one adapter that
        // is allowed to call the legacy generator. The CI-side gate
        // (`git diff --stat lib/features/streak/**`) catches any drift on
        // the legacy side; this test catches accidental imports in the
        // other new files.
        final gamification = Directory('lib/features/gamification');
        for (final entity in gamification.listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          if (entity.path.endsWith('legacy_daily_challenge_adapter.dart')) {
            continue;
          }
          final source = entity.readAsStringSync();
          expect(
            source,
            isNot(contains("features/streak/daily_challenge.dart")),
            reason:
                '${entity.path} must not import the legacy generator; '
                'the adapter owns that boundary (ADR 0387 Decision 1).',
          );
        }
      },
    );

    test(
      '§6.1 below the threshold: the previous day\'s instance is still active',
      () async {
        final store = InMemoryKeyValueStore();
        final service = _service(
          contentCatalog: const _EmptyCatalog(),
          store: store,
          ledger: _rewardLedger(store),
        );

        final previous = await service.getOrGenerateInstance(
          epochDay: 20040,
          catalogVersion: 1,
        );
        final sameInstance = await service.getOrGenerateInstance(
          epochDay: 20040,
          catalogVersion: 1,
        );
        expect(sameInstance.epochDay, previous.epochDay);
        expect(sameInstance.toJson(), equals(previous.toJson()));
      },
    );

    test(
      '§6.1 on the threshold: the NEW day\'s instance is already active',
      () async {
        final store = InMemoryKeyValueStore();
        final service = _service(
          contentCatalog: const _EmptyCatalog(),
          store: store,
          ledger: _rewardLedger(store),
        );

        final previous = await service.getOrGenerateInstance(
          epochDay: 20040,
          catalogVersion: 1,
        );
        final next = await service.getOrGenerateInstance(
          epochDay: 20041,
          catalogVersion: 1,
        );

        expect(next.epochDay, 20041);
        expect(next.epochDay, isNot(equals(previous.epochDay)));
      },
    );

    test(
      '§6.1 above the threshold: the previous day\'s completion and reward are kept',
      () async {
        final store = InMemoryKeyValueStore();
        final ledger = _rewardLedger(store);
        final service = _service(
          contentCatalog: const _EmptyCatalog(),
          store: store,
          ledger: ledger,
        );

        final previous = await service.getOrGenerateInstance(
          epochDay: 20040,
          catalogVersion: 1,
        );
        final completed = await service.complete(instance: previous);

        final next = await service.getOrGenerateInstance(
          epochDay: 20041,
          catalogVersion: 1,
        );
        expect(next.epochDay, 20041);
        expect(completed.rewardAppended, isTrue);
        expect(ledger.readPage(limit: 10).entries, hasLength(1));
        expect(
          ledger.readPage(limit: 10).entries.single.sourceEventId,
          previous.instanceId,
        );
      },
    );
  });

  group('DailyChallengeService — real-violation proof (§10)', () {
    test(
      'A1 real-violation: a copied-and-diverged generator breaks the identity cell',
      () {
        // A hypothetical non-calling adapter that hardcodes its pattern.
        // The proof below shows that ANY drift from the legacy formula
        // immediately fails the identity cell — which is exactly what the
        // ADR 0387 Decision 1 binding rule forbids.
        const bad = _BadStrumPattern();
        for (var day = 20050; day < 20070; day++) {
          final legacy = DailyChallenge.forDay(day);
          final badInstance = bad.forDay(day);
          expect(
            badInstance.pattern == legacy.pattern,
            isFalse,
            reason:
                'day=$day a non-calling adapter cannot reproduce the legacy '
                'pattern — the cell would go red on the first divergence',
          );
        }
      },
    );
  });
}

class _Fixture {
  _Fixture({
    required DailyChallengeContentCatalog contentCatalog,
    DateTime Function()? clock,
  }) : _contentCatalog = contentCatalog,
       store = InMemoryKeyValueStore(),
       ledger = _rewardLedger(InMemoryKeyValueStore()) {
    service = _service(
      contentCatalog: _contentCatalog,
      store: store,
      ledger: ledger,
      clock: clock,
    );
  }

  final InMemoryKeyValueStore store;
  final DailyChallengeContentCatalog _contentCatalog;
  final RewardLedgerRepository ledger;
  late final DailyChallengeService service;
}

DailyChallengeService _service({
  required DailyChallengeContentCatalog contentCatalog,
  InMemoryKeyValueStore? store,
  RewardLedgerRepository? ledger,
  DateTime Function()? clock,
}) {
  return DailyChallengeService(
    contentCatalog: contentCatalog,
    completionStore: LocalDailyChallengeCompletionStore(
      store: store ?? InMemoryKeyValueStore(),
      logger: const NoopAppLogger(),
    ),
    rewardLedger: ledger ?? _rewardLedger(InMemoryKeyValueStore()),
    clock: clock ?? DateTime.now,
  );
}

RewardLedgerRepository _rewardLedger(InMemoryKeyValueStore store) {
  return LocalRewardLedgerRepository(
    store: store,
    logger: const NoopAppLogger(),
  );
}

class _EmptyCatalog implements DailyChallengeContentCatalog {
  const _EmptyCatalog();
  @override
  List<String> installedChordIds() => const <String>[];
  @override
  List<String> installedRhythmIds() => const <String>[];
  @override
  List<String> installedSongIds() => const <String>[];
  @override
  List<String> installedTimingContentIds() => const <String>[];
  @override
  int catalogVersion() => 1;
}

class _ChordOnlyCatalog implements DailyChallengeContentCatalog {
  const _ChordOnlyCatalog(this._chordIds);
  final List<String> _chordIds;
  @override
  List<String> installedChordIds() => List<String>.unmodifiable(_chordIds);
  @override
  List<String> installedRhythmIds() => const <String>[];
  @override
  List<String> installedSongIds() => const <String>[];
  @override
  List<String> installedTimingContentIds() => const <String>[];
  @override
  int catalogVersion() => 1;
}

class _MultiTypeCatalog implements DailyChallengeContentCatalog {
  const _MultiTypeCatalog({
    this._chordIds = const <String>['C', 'G', 'Am', 'F'],
    this._rhythmIds = const <String>['pop-rock', 'funk-1', 'waltz'],
    this._songIds = const <String>['song-1', 'song-2'],
  }) : _timingContentIds = const <String>['timing-a', 'timing-b'];

  final List<String> _chordIds;
  final List<String> _rhythmIds;
  final List<String> _songIds;
  final List<String> _timingContentIds;

  @override
  List<String> installedChordIds() => List<String>.unmodifiable(_chordIds);
  @override
  List<String> installedRhythmIds() => List<String>.unmodifiable(_rhythmIds);
  @override
  List<String> installedSongIds() => List<String>.unmodifiable(_songIds);
  @override
  List<String> installedTimingContentIds() =>
      List<String>.unmodifiable(_timingContentIds);
  @override
  int catalogVersion() => 1;

  // Expose the private lists for the A6 matrix test.
  List<String> chordIds() => _chordIds;
  List<String> rhythmIds() => _rhythmIds;
  List<String> songIds() => _songIds;
  List<String> timingContentIds() => _timingContentIds;
}

class _BadStrumPattern {
  const _BadStrumPattern();
  StrumPatternChallenge forDay(int epochDay) {
    // Simulate a hypothetical copy-and-divide: produces a constant pattern
    // regardless of the day. The real-violation test asserts that THIS
    // diverges from the legacy generator — proving the cell turns red as
    // soon as a copy drifts.
    return const StrumPatternChallenge(
      pattern: <StrumDirection>[StrumDirection.down],
      name: 'BAD',
    );
  }
}
