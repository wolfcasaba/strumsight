import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/public.dart';

void main() {
  group('A1 — monoton level curve', () {
    test('a greater total XP never maps to a lower level', () {
      final curve = _curve();
      var previousLevel = curve.progressForTotalXp(0).currentLevel.number;

      for (var totalXp = 1; totalXp <= 2000; totalXp++) {
        final level = curve.progressForTotalXp(totalXp).currentLevel.number;
        expect(level, greaterThanOrEqualTo(previousLevel));
        previousLevel = level;
      }
    });

    test('the threshold belongs inclusively to the higher level', () {
      final curve = _curve();

      final below = curve.progressForTotalXp(99);
      final at = curve.progressForTotalXp(100);
      final above = curve.progressForTotalXp(101);

      expect(below.currentLevel.number, 1);
      expect(below.xpToNextLevel, 1);
      expect(at.currentLevel.number, 2);
      expect(at.xpIntoCurrentLevel, 0);
      expect(above.currentLevel.number, 2);
      expect(above.xpIntoCurrentLevel, 1);
    });
  });

  group('A2/A3 — rebuild and incremental projection', () {
    test('an empty ledger rebuild returns the initial profile', () async {
      final projector = ProfileProjector(
        curve: _curve(),
        ledger: _PagingLedger(const <RewardLedgerEntry>[]),
      );

      final rebuilt = await projector.rebuild();

      expect(rebuilt.profile.totalXp, 0);
      expect(rebuilt.profile.currentLevel.number, 1);
    });

    test('paged rebuild equals incremental projection', () async {
      final entries = <RewardLedgerEntry>[
        _entry(ledgerId: 'one', totalXp: 30),
        _entry(ledgerId: 'two', totalXp: 95),
        _entry(ledgerId: 'three', totalXp: 220),
      ];
      final projector = ProfileProjector(
        curve: _curve(),
        ledger: _PagingLedger(entries),
        pageSize: 1,
      );

      final rebuilt = await projector.rebuild();
      var incrementalProfile = projector.initialProfile;
      for (final entry in entries) {
        incrementalProfile = projector
            .projectIncrementally(profile: incrementalProfile, entry: entry)
            .profile;
      }

      expect(rebuilt.profile, incrementalProfile);
    });

    test('one ledger event reports every crossed level', () {
      final projector = ProfileProjector(
        curve: _curve(),
        ledger: _PagingLedger(const <RewardLedgerEntry>[]),
      );

      final projection = projector.projectIncrementally(
        profile: projector.initialProfile,
        entry: _entry(totalXp: 650),
      );

      expect(projection.crossedLevels.map((level) => level.number), <int>[
        2,
        3,
        4,
      ]);
      expect(projection.profile.currentLevel.number, 4);
    });

    test('a rebalance cannot lower an established profile level', () {
      final establishedProfile = GamificationProfile(
        schemaVersion: gamificationProfileSchemaVersion,
        totalXp: 250,
        progress: _curve().progressForTotalXp(250),
      );
      final rebalancedCurve = LevelCurve(<LevelDefinition>[
        LevelDefinition(
          number: 1,
          levelThreshold: 0,
          titleKey: 'gamification.level.beginner',
        ),
        LevelDefinition(
          number: 2,
          levelThreshold: 200,
          titleKey: 'gamification.level.explorer',
        ),
        LevelDefinition(
          number: 3,
          levelThreshold: 300,
          titleKey: 'gamification.level.consistent',
        ),
      ]);
      final projector = ProfileProjector(
        curve: rebalancedCurve,
        ledger: _PagingLedger(const <RewardLedgerEntry>[]),
      );

      final projection = projector.projectIncrementally(
        profile: establishedProfile,
        entry: _entry(totalXp: 0),
      );

      expect(projection.profile.totalXp, 250);
      expect(projection.profile.currentLevel.number, 3);
    });
  });

  group('A4/A5 — source-owned thresholds and saturation', () {
    test(
      'near-max total XP saturates at the highest level without negatives',
      () {
        final projector = ProfileProjector(
          curve: _curve(),
          ledger: _PagingLedger(const <RewardLedgerEntry>[]),
        );
        final nearMaximum = GamificationProfile(
          schemaVersion: gamificationProfileSchemaVersion,
          totalXp: LevelCurve.maximumSupportedTotalXp - 1,
          progress: _curve().progressForTotalXp(
            LevelCurve.maximumSupportedTotalXp - 1,
          ),
        );

        final projection = projector.projectIncrementally(
          profile: nearMaximum,
          entry: _entry(totalXp: 10),
        );

        expect(projection.profile.totalXp, LevelCurve.maximumSupportedTotalXp);
        expect(projection.profile.currentLevel.number, 4);
        expect(projection.profile.currentLevel.number, isPositive);
      },
    );

    test(
      'a changed curve changes projection without duplicated thresholds',
      () {
        final curve = LevelCurve(<LevelDefinition>[
          LevelDefinition(
            number: 1,
            levelThreshold: 0,
            titleKey: 'gamification.level.one',
          ),
          LevelDefinition(
            number: 2,
            levelThreshold: 150,
            titleKey: 'gamification.level.two',
          ),
        ]);
        final projector = ProfileProjector(
          curve: curve,
          ledger: _PagingLedger(const <RewardLedgerEntry>[]),
        );

        final projection = projector.projectIncrementally(
          profile: projector.initialProfile,
          entry: _entry(totalXp: 100),
        );

        expect(projection.profile.currentLevel.number, 1);
      },
    );
  });

  group('A6/A7/A8 — domain contract', () {
    test('level definitions reject invalid identifiers and thresholds', () {
      expect(
        () => LevelDefinition(
          number: 0,
          levelThreshold: 0,
          titleKey: 'gamification.level.invalid',
        ),
        throwsArgumentError,
      );
      expect(
        () => LevelDefinition(
          number: 1,
          levelThreshold: -1,
          titleKey: 'gamification.level.invalid',
        ),
        throwsArgumentError,
      );
      expect(
        () => LevelDefinition(number: 1, levelThreshold: 0, titleKey: ' '),
        throwsArgumentError,
      );
    });

    test('level definitions keep localized title keys, not display text', () {
      final definition = _curve().definitions.last;

      expect(definition.titleKey, 'gamification.level.advanced');
      expect(definition.titleKey, contains('.'));
    });

    test('an unknown profile schema version is rejected', () {
      expect(
        () => GamificationProfile(
          schemaVersion: gamificationProfileSchemaVersion + 1,
          totalXp: 0,
          progress: _curve().progressForTotalXp(0),
        ),
        throwsArgumentError,
      );
    });

    test('projection contracts never expose XP-level content unlocking', () {
      for (final path in <String>[
        'lib/features/gamification/domain/levels/level_definition.dart',
        'lib/features/gamification/domain/levels/level_curve.dart',
        'lib/features/gamification/domain/profile/gamification_profile.dart',
        'lib/features/gamification/application/profile_projector.dart',
      ]) {
        expect(
          File(path).readAsStringSync(),
          isNot(contains(RegExp(r'\bunlock\w*\b', caseSensitive: false))),
          reason: '$path must not turn XP levels into content gates',
        );
      }
    });
  });
}

LevelCurve _curve() => LevelCurve(<LevelDefinition>[
  LevelDefinition(
    number: 1,
    levelThreshold: 0,
    titleKey: 'gamification.level.beginner',
  ),
  LevelDefinition(
    number: 2,
    levelThreshold: 100,
    titleKey: 'gamification.level.explorer',
  ),
  LevelDefinition(
    number: 3,
    levelThreshold: 250,
    titleKey: 'gamification.level.consistent',
  ),
  LevelDefinition(
    number: 4,
    levelThreshold: 500,
    titleKey: 'gamification.level.advanced',
  ),
]);

RewardLedgerEntry _entry({String ledgerId = 'entry', int totalXp = 10}) =>
    RewardLedgerEntry(
      ledgerId: ledgerId,
      sourceEventId: 'source-$ledgerId',
      createdAt: DateTime.utc(2026, 8, 20),
      schemaVersion: rewardLedgerEntrySchemaVersion,
      policyVersion: 1,
      baseXp: totalXp,
      bonusXp: 0,
      totalXp: totalXp,
      reasonCodes: const <RewardReason>[RewardReason.baseExperience],
    );

final class _PagingLedger implements RewardLedgerRepository {
  _PagingLedger(List<RewardLedgerEntry> entries) : _entries = entries;

  final List<RewardLedgerEntry> _entries;

  @override
  Future<bool> appendIfAbsent(RewardLedgerEntry entry) async =>
      throw UnsupportedError('not needed by projection tests');

  @override
  bool hasProcessedEvent(String sourceEventId) => false;

  @override
  RewardLedgerPage readPage({required int limit, String? cursor}) {
    final start = cursor == null ? 0 : int.parse(cursor);
    final end = (start + limit).clamp(0, _entries.length);
    return RewardLedgerPage(
      entries: _entries.sublist(start, end),
      nextCursor: end == _entries.length ? null : '$end',
    );
  }
}
