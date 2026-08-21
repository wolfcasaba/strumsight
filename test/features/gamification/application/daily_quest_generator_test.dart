import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/public.dart';

void main() {
  group('DailyQuestGenerator', () {
    test('A1: a complete snapshot is deterministic with a pinned FNV seed', () {
      final generator = DailyQuestGenerator(catalog: _catalog());
      final snapshot = _snapshot();
      final expectedIds = generator
          .generate(snapshot)
          .map((quest) => quest.definition.id)
          .toList(growable: false);

      for (var run = 0; run < 100; run++) {
        expect(
          generator
              .generate(snapshot)
              .map((quest) => quest.definition.id)
              .toList(growable: false),
          expectedIds,
        );
      }

      expect(dailyQuestSeedMaterial(snapshot), '20686|profile_alpha|7');
      expect(dailyQuestSortKey(snapshot, 'daily_rhythm'), 2042140054537804680);
      expect(
        dailyQuestSortKey(_snapshot(profileSnapshotKey: 'pál'), 'daily_rhythm'),
        -4335421002150217356,
      );
    });

    test(
      'A2: keeps the inclusive one-to-three range and a short objective',
      () {
        final one = DailyQuestGenerator(
          catalog: _catalog(ids: <String>['daily_rhythm']),
        ).generate(_snapshot());
        final three = DailyQuestGenerator(
          catalog: _catalog(
            ids: <String>['daily_rhythm', 'daily_chords', 'daily_recovery'],
          ),
        ).generate(_snapshot());
        final four = DailyQuestGenerator(
          catalog: _catalog(
            ids: <String>[
              'daily_rhythm',
              'daily_chords',
              'daily_camera',
              'daily_account',
            ],
          ),
        ).generate(_snapshot());
        final empty = DailyQuestGenerator(
          catalog: const DailyQuestCatalog.empty(),
        ).generate(_snapshot());

        expect(one, hasLength(1));
        expect(three, hasLength(3));
        expect(four, hasLength(3));
        expect(empty, hasLength(1));
        for (final generated in <List<GeneratedDailyQuest>>[
          one,
          three,
          four,
          empty,
        ]) {
          expect(generated.any((quest) => quest.isShort), isTrue);
        }

        final noShort = DailyQuestGenerator(
          catalog: DailyQuestCatalog(
            entries: <DailyQuestCatalogEntry>[_entry('daily_chords')],
          ),
        ).generate(_snapshot());
        expect(noShort.single.definition.id, 'daily_check_in');
      },
    );

    test('A2/A7: generated and catalog views are unmodifiable', () {
      final catalog = _catalog();
      final generated = DailyQuestGenerator(
        catalog: catalog,
      ).generate(_snapshot());

      expect(
        () => catalog.entries.add(_entry('other_short', isShort: true)),
        throwsUnsupportedError,
      );
      expect(() => generated.add(generated.first), throwsUnsupportedError);
      expect(
        () =>
            _snapshot().plannedObjectives!.add(SkillTagQuestObjective('other')),
        throwsUnsupportedError,
      );
    });

    test('A3: camera unavailability only excludes the camera quest', () {
      final ids = _shippingCapabilityQuestIds(cameraAvailable: false);

      expect(ids, isNot(contains('daily_camera')));
      expect(ids, contains('daily_account'));
      expect(ids, contains('daily_cloud'));
    });

    test('A3: account unavailability only excludes the account quest', () {
      final ids = _shippingCapabilityQuestIds(accountAvailable: false);

      expect(ids, contains('daily_camera'));
      expect(ids, isNot(contains('daily_account')));
      expect(ids, contains('daily_cloud'));
    });

    test('A3: cloud unavailability only excludes the cloud quest', () {
      final ids = _shippingCapabilityQuestIds(cloudAvailable: false);

      expect(ids, contains('daily_camera'));
      expect(ids, contains('daily_account'));
      expect(ids, isNot(contains('daily_cloud')));
    });

    test(
      'F2: the shipping default catalog has the contracted quest metadata',
      () {
        final entries = defaultDailyQuestCatalog().entries;
        final expectedCapabilities = <String, Set<QuestCapability>>{
          'daily_rhythm': const <QuestCapability>{},
          'daily_chords': const <QuestCapability>{},
          'daily_camera': const <QuestCapability>{QuestCapability.camera},
          'daily_account': const <QuestCapability>{QuestCapability.account},
          'daily_cloud': const <QuestCapability>{QuestCapability.cloud},
          'daily_recovery': const <QuestCapability>{},
        };

        expect(
          entries.map((entry) => entry.id).toList(growable: false),
          expectedCapabilities.keys.toList(growable: false),
        );
        expect(
          entries.map((entry) => entry.id).toSet(),
          hasLength(entries.length),
        );
        expect(
          entries.where((entry) => entry.isShort).map((entry) => entry.id),
          unorderedEquals(<String>['daily_rhythm', 'daily_recovery']),
        );
        expect(
          entries
              .where((entry) => entry.isRestEligible)
              .map((entry) => entry.id),
          <String>['daily_recovery'],
        );
        for (final entry in entries) {
          expect(entry.requiredCapabilities, expectedCapabilities[entry.id]);
        }
      },
    );

    test('A5: planned rest only returns optional rest-eligible quests', () {
      final generated = DailyQuestGenerator(
        catalog: _catalog(),
      ).generate(_snapshot(plannedRest: true));

      expect(generated, isNotEmpty);
      expect(generated.every((quest) => quest.isOptional), isTrue);
      expect(generated.every((quest) => quest.isRestEligible), isTrue);
    });

    test(
      'A7: empty catalogs, missing plans, and new profiles receive a local fallback',
      () {
        final emptyCatalog = DailyQuestGenerator(
          catalog: const DailyQuestCatalog.empty(),
        );
        final regularCatalog = DailyQuestGenerator(catalog: _catalog());

        expect(
          emptyCatalog.generate(_snapshot()).single.definition.id,
          'daily_check_in',
        );
        expect(
          regularCatalog
              .generate(_snapshot(hasPlan: false))
              .single
              .definition
              .id,
          'daily_check_in',
        );
        expect(
          regularCatalog
              .generate(_snapshot(isNewProfile: true))
              .single
              .definition
              .id,
          'daily_check_in',
        );
      },
    );
  });
}

DailyQuestGenerationSnapshot _snapshot({
  String profileSnapshotKey = 'profile_alpha',
  bool hasPlan = true,
  bool plannedRest = false,
  bool cameraAvailable = true,
  bool accountAvailable = true,
  bool cloudAvailable = true,
  bool isNewProfile = false,
  List<QuestObjective>? objectives,
}) => DailyQuestGenerationSnapshot(
  schedule: QuestSchedule(
    schemaVersion: questScheduleSchemaVersion,
    generationEpochDay: 20686,
    timezoneOffsetMinutes: 120,
    catalogVersion: 7,
    expiresAt: DateTime.utc(2026, 8, 22),
  ),
  profileSnapshotKey: profileSnapshotKey,
  plannedObjectives: hasPlan ? objectives ?? _objectives() : null,
  plannedRest: plannedRest,
  cameraAvailable: cameraAvailable,
  accountAvailable: accountAvailable,
  cloudAvailable: cloudAvailable,
  isNewProfile: isNewProfile,
);

Set<String> _shippingCapabilityQuestIds({
  bool cameraAvailable = true,
  bool accountAvailable = true,
  bool cloudAvailable = true,
}) => DailyQuestGenerator(catalog: defaultDailyQuestCatalog())
    .generate(
      _snapshot(
        cameraAvailable: cameraAvailable,
        accountAvailable: accountAvailable,
        cloudAvailable: cloudAvailable,
        objectives: <QuestObjective>[
          SkillTagQuestObjective('rhythm'),
          SkillTagQuestObjective('camera'),
          SkillTagQuestObjective('account'),
          SkillTagQuestObjective('cloud'),
        ],
      ),
    )
    .map((quest) => quest.definition.id)
    .toSet();

DailyQuestCatalog _catalog({List<String>? ids}) {
  final entries = <DailyQuestCatalogEntry>[
    _entry('daily_rhythm', isShort: true),
    _entry('daily_chords'),
    _entry(
      'daily_camera',
      capabilities: const <QuestCapability>{QuestCapability.camera},
    ),
    _entry(
      'daily_account',
      capabilities: const <QuestCapability>{QuestCapability.account},
    ),
    _entry(
      'daily_cloud',
      capabilities: const <QuestCapability>{QuestCapability.cloud},
    ),
    _entry('daily_recovery', isShort: true, restEligible: true),
  ];
  return DailyQuestCatalog(
    entries: ids == null
        ? entries
        : entries
              .where((entry) => ids.contains(entry.id))
              .toList(growable: false),
  );
}

DailyQuestCatalogEntry _entry(
  String id, {
  bool isShort = false,
  bool restEligible = false,
  Set<QuestCapability> capabilities = const <QuestCapability>{},
}) => DailyQuestCatalogEntry(
  id: id,
  objective: SkillTagQuestObjective(_skillTagFor(id)),
  reward: QuestReward(baseXp: 10, bonusXp: 0, policyVersion: 1),
  requiredCapabilities: capabilities,
  isShort: isShort,
  isRestEligible: restEligible,
);

List<QuestObjective> _objectives() => <QuestObjective>[
  SkillTagQuestObjective('rhythm'),
  SkillTagQuestObjective('chords'),
  SkillTagQuestObjective('camera'),
  SkillTagQuestObjective('account'),
  SkillTagQuestObjective('cloud'),
  SkillTagQuestObjective('recovery'),
];

String _skillTagFor(String id) => switch (id) {
  'daily_rhythm' => 'rhythm',
  'daily_chords' => 'chords',
  'daily_camera' => 'camera',
  'daily_account' => 'account',
  'daily_cloud' => 'cloud',
  'daily_recovery' => 'recovery',
  _ => 'other',
};
