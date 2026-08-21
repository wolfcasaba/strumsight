import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/public.dart';

void main() {
  final localeKeys = _localeKeys();

  group('AchievementCatalog — curated catalog', () {
    test('A1: ships 20 to 30 stable, title-independent identifiers', () {
      final catalog = defaultAchievementCatalog;

      expect(catalog.definitions.length, inInclusiveRange(20, 30));
      expect(
        catalog.definitions.map((definition) => definition.id),
        orderedEquals(<String>[
          'first_valid_session',
          'practice_starter',
          'practice_builder',
          'practice_regular',
          'practice_devotee',
          'rhythm_first_steps',
          'rhythm_builder_one',
          'rhythm_builder_two',
          'rhythm_builder_three',
          'song_first_finish',
          'song_explorer_one',
          'song_explorer_two',
          'analysis_first_review',
          'analysis_insight',
          'plan_first_block',
          'plan_pathfinder',
          'tutor_first_checkin',
          'vision_first_observation',
          'source_explorer',
          'balanced_practice_week',
          'xp_first_hundred',
          'legacy_first_step',
        ]),
      );
      for (final definition in catalog.definitions) {
        expect(definition.id, matches(RegExp(r'^[a-z][a-z0-9_]*$')));
        expect(definition.id, isNot(definition.titleKey));
      }
    });

    test('A2: rejects the unknown objective sentinel fail-closed', () {
      final report = _catalogWith(
        _definition(
          id: 'unknown_objective',
          objective: const UnknownAchievementObjective('futureObjective'),
        ),
      ).validate(localizedKeys: localeKeys);

      expect(report.isValid, isFalse);
      expect(
        report.codes,
        contains(AchievementCatalogValidationCode.unknownObjective),
      );
    });

    test('A3: rejects an A to B to A tier cycle', () {
      final catalog = AchievementCatalog(
        contentVersion: 1,
        definitions: <AchievementDefinition>[
          _definition(
            id: 'tier_a',
            tierPrerequisiteIds: const <String>['tier_b'],
          ),
          _definition(
            id: 'tier_b',
            tierPrerequisiteIds: const <String>['tier_a'],
          ),
          ..._standardDefinitions(18),
        ],
      );

      final report = catalog.validate(localizedKeys: localeKeys);

      expect(report.isValid, isFalse);
      expect(
        report.codes,
        contains(AchievementCatalogValidationCode.tierCycle),
      );
    });

    test(
      'A4: requires every title, description, and semantics key in both locales',
      () {
        final report =
            _catalogWith(
              _definition(
                id: 'missing_hungarian',
                titleKey: 'achievementMissingKey',
              ),
            ).validate(
              localizedKeys: AchievementLocalizedKeys(
                english: <String>{
                  ...localeKeys.english,
                  'achievementMissingKey',
                },
                hungarian: localeKeys.hungarian,
              ),
            );

        expect(report.isValid, isFalse);
        expect(
          report.codes,
          contains(AchievementCatalogValidationCode.missingLocalizationKey),
        );
      },
    );

    test(
      'A5: catalog definitions only accept localization-key shaped text fields',
      () {
        expect(
          () => _definition(
            id: 'hard_coded_text',
            titleKey: 'First valid session',
          ),
          throwsArgumentError,
        );
      },
    );

    test('A6: keeps the deprecated achievement in the curated catalog', () {
      final deprecated = defaultAchievementCatalog.definitions.singleWhere(
        (definition) => definition.id == 'legacy_first_step',
      );

      expect(deprecated.deprecated, isTrue);
      expect(
        defaultAchievementCatalog.validate(localizedKeys: localeKeys).isValid,
        isTrue,
      );
    });

    test(
      'A7: a changed definition count requires an increased content version',
      () {
        final previous = AchievementCatalog(
          contentVersion: 7,
          definitions: _standardDefinitions(20),
        );
        final unchangedVersion = AchievementCatalog(
          contentVersion: 7,
          definitions: <AchievementDefinition>[..._standardDefinitions(21)],
        );
        final increasedVersion = AchievementCatalog(
          contentVersion: 8,
          definitions: <AchievementDefinition>[..._standardDefinitions(21)],
        );

        expect(
          unchangedVersion
              .validate(localizedKeys: localeKeys, previousCatalog: previous)
              .codes,
          contains(AchievementCatalogValidationCode.contentVersionNotIncreased),
        );
        expect(
          increasedVersion
              .validate(localizedKeys: localeKeys, previousCatalog: previous)
              .isValid,
          isTrue,
        );
      },
    );

    test(
      'rejects replacing a previously issued ID at the same catalog size',
      () {
        final previous = AchievementCatalog(
          contentVersion: 7,
          definitions: _standardDefinitions(20),
        );
        final replacement = AchievementCatalog(
          contentVersion: 8,
          definitions: <AchievementDefinition>[
            ..._standardDefinitions(19),
            _definition(id: 'replacement_achievement'),
          ],
        );

        final report = replacement.validate(
          localizedKeys: localeKeys,
          previousCatalog: previous,
        );

        expect(report.isValid, isFalse);
        expect(
          report.codes,
          contains(AchievementCatalogValidationCode.previousAchievementMissing),
        );
      },
    );

    test(
      'A8: every curated definition has a localized spoken description key',
      () {
        for (final definition in defaultAchievementCatalog.definitions) {
          expect(definition.accessibilityDescriptionKey, isNotEmpty);
          expect(
            localeKeys.english,
            contains(definition.accessibilityDescriptionKey),
          );
          expect(
            localeKeys.hungarian,
            contains(definition.accessibilityDescriptionKey),
          );
        }
      },
    );
  });

  group('AchievementCatalog — inclusive catalog size', () {
    for (final size in <int>[19, 20, 21, 29, 30, 31]) {
      test('validates the $size-item boundary cell', () {
        final report = AchievementCatalog(
          contentVersion: 1,
          definitions: _standardDefinitions(size),
        ).validate(localizedKeys: localeKeys);

        expect(report.isValid, size >= 20 && size <= 30);
      });
    }
  });

  group('Achievement objective vocabulary', () {
    test(
      'accepts every supported typed objective shape without mutable input',
      () {
        final objectives = <AchievementObjective>[
          CountAchievementObjective(
            eventKind: AchievementEventKind.practice,
            target: 1,
          ),
          ThresholdAchievementObjective(
            eventKind: AchievementEventKind.song,
            metric: AchievementMetric.score,
            minimum: 0.8,
          ),
          DistinctAchievementObjective(
            eventKind: AchievementEventKind.analysis,
            dimension: AchievementDistinctDimension.activitySource,
            target: 2,
          ),
          SequenceAchievementObjective(
            eventKinds: <AchievementEventKind>[
              AchievementEventKind.plan,
              AchievementEventKind.tutor,
            ],
          ),
          CompoundAchievementObjective(
            objectives: <AchievementObjective>[
              CountAchievementObjective(
                eventKind: AchievementEventKind.vision,
                target: 1,
              ),
            ],
          ),
        ];
        final definitions = <AchievementDefinition>[
          for (var index = 0; index < objectives.length; index++)
            _definition(
              id: 'objective_shape_$index',
              objective: objectives[index],
            ),
          ..._standardDefinitions(15),
        ];
        final catalog = AchievementCatalog(
          contentVersion: 1,
          definitions: definitions,
        );

        expect(catalog.validate(localizedKeys: localeKeys).isValid, isTrue);
        expect(
          () => catalog.definitions.add(_definition(id: 'mutable_catalog')),
          throwsUnsupportedError,
        );
      },
    );

    test('rejects non-positive count and distinct targets at runtime', () {
      for (final target in <int>[0, -1]) {
        expect(
          () => CountAchievementObjective(
            eventKind: AchievementEventKind.practice,
            target: target,
          ),
          throwsArgumentError,
        );
        expect(
          () => DistinctAchievementObjective(
            eventKind: AchievementEventKind.practice,
            dimension: AchievementDistinctDimension.activitySource,
            target: target,
          ),
          throwsArgumentError,
        );
      }
    });

    test('accepts a zero threshold but rejects invalid numeric thresholds', () {
      expect(
        ThresholdAchievementObjective(
          eventKind: AchievementEventKind.practice,
          metric: AchievementMetric.score,
          minimum: 0,
        ).minimum,
        0,
      );
      for (final minimum in <num>[
        -1,
        double.infinity,
        double.negativeInfinity,
        double.nan,
      ]) {
        expect(
          () => ThresholdAchievementObjective(
            eventKind: AchievementEventKind.practice,
            metric: AchievementMetric.score,
            minimum: minimum,
          ),
          throwsArgumentError,
        );
      }
    });

    test('keeps progress finite, non-negative, and monotonic at runtime', () {
      expect(
        AchievementProgress(
          achievementId: 'test_achievement',
          catalogVersion: 1,
          value: 0,
        ).value,
        0,
      );
      for (final value in <num>[
        -1,
        double.infinity,
        double.negativeInfinity,
        double.nan,
      ]) {
        expect(
          () => AchievementProgress(
            achievementId: 'test_achievement',
            catalogVersion: 1,
            value: value,
          ),
          throwsArgumentError,
        );
      }

      final progress = AchievementProgress(
        achievementId: 'test_achievement',
        catalogVersion: 1,
        value: 1,
      );
      for (final value in <num>[
        0,
        double.infinity,
        double.negativeInfinity,
        double.nan,
      ]) {
        expect(() => progress.advanceTo(value: value), throwsArgumentError);
      }
    });

    test(
      'uses only measured event kinds, metrics, and the activity-source distinct dimension',
      () {
        expect(AchievementEventKind.values.map((kind) => kind.code), <String>[
          'practice',
          'song',
          'analysis',
          'plan',
          'tutor',
          'vision',
        ]);
        expect(AchievementMetric.values.map((metric) => metric.code), <String>[
          'eventCount',
          'durationSeconds',
          'score',
          'baseXp',
          'durationXp',
          'qualityXp',
          'improvementXp',
          'diversityXp',
          'totalXp',
        ]);
        expect(
          AchievementDistinctDimension.values.single.code,
          'activitySource',
        );
      },
    );
  });
}

AchievementCatalog _catalogWith(AchievementDefinition definition) =>
    AchievementCatalog(
      contentVersion: 1,
      definitions: <AchievementDefinition>[
        definition,
        ..._standardDefinitions(19),
      ],
    );

List<AchievementDefinition> _standardDefinitions(int count) =>
    List<AchievementDefinition>.generate(
      count,
      (index) => _definition(id: 'test_achievement_$index'),
      growable: false,
    );

AchievementDefinition _definition({
  required String id,
  AchievementObjective? objective,
  String titleKey = 'achievementTestTitle',
  List<String> tierPrerequisiteIds = const <String>[],
}) => AchievementDefinition(
  id: id,
  category: AchievementCategory.practice,
  titleKey: titleKey,
  descriptionKey: 'achievementTestDescription',
  accessibilityDescriptionKey: 'achievementTestSemantics',
  objectives: <AchievementObjective>[
    objective ??
        CountAchievementObjective(
          eventKind: AchievementEventKind.practice,
          target: 1,
        ),
  ],
  tierPrerequisiteIds: tierPrerequisiteIds,
  hidden: false,
  version: 1,
  deprecated: false,
);

AchievementLocalizedKeys _localeKeys() => AchievementLocalizedKeys(
  english: _keysFrom('lib/l10n/features/gamification_en.arb')
    ..addAll(<String>[
      'achievementTestTitle',
      'achievementTestDescription',
      'achievementTestSemantics',
    ]),
  hungarian: _keysFrom('lib/l10n/features/gamification_hu.arb')
    ..addAll(<String>[
      'achievementTestTitle',
      'achievementTestDescription',
      'achievementTestSemantics',
    ]),
);

Set<String> _keysFrom(String path) {
  final decoded =
      jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
  return decoded.keys.where((key) => !key.startsWith('@')).toSet();
}
