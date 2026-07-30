import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/application/practice_catalog_controller.dart';
import 'package:strumsight/features/practice/data/builtin_practice_catalog.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_difficulty.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/repository/practice_catalog_repository.dart';

void main() {
  group('practiceCatalogProvider', () {
    test('returns the full built-in catalog in declaration order', () {
      final container = ProviderContainer();

      addTearDown(container.dispose);

      final catalog = container.read(practiceCatalogProvider);

      expect(catalog, hasLength(10));
      expect(catalog.first.id, 'builtin.quarterDownstrokes.v1');
      expect(catalog.last.id, 'builtin.freePracticeTemplate.v1');
    });

    test('is backed by the BuiltinPracticeCatalog by default', () {
      final container = ProviderContainer();

      addTearDown(container.dispose);

      final repository = container.read(practiceCatalogRepositoryProvider);

      expect(repository, isA<BuiltinPracticeCatalog>());
    });

    test('rewires when practiceCatalogRepositoryProvider is overridden', () {
      final container = ProviderContainer(
        overrides: [
          practiceCatalogRepositoryProvider.overrideWithValue(
            const _SingleDefinitionRepository(),
          ),
        ],
      );

      addTearDown(container.dispose);

      final catalog = container.read(practiceCatalogProvider);

      expect(catalog, hasLength(1));
      expect(catalog.single.id, 'test.single.v1');
    });
  });
}

class _SingleDefinitionRepository implements PracticeCatalogRepository {
  const _SingleDefinitionRepository();

  static const _definition = PracticeDefinition(
    id: 'test.single.v1',
    schemaVersion: 1,
    titleKey: 'practiceCatalogTestSingleTitle',
    descriptionKey: 'practiceCatalogTestSingleDescription',
    mode: PracticeMode.freePractice,
    source: PracticeSource.builtin,
    meter: Meter(beatsPerBar: 4),
    defaultTempo: Tempo(80),
    totalBeats: BeatPosition(4 * BeatPosition.ticksPerBeat),
    events: [],
    scoringProfile: ScoringProfile.freePracticeOpen,
    skillTags: ['test'],
  );

  @override
  List<PracticeDefinition> all() =>
      List<PracticeDefinition>.unmodifiable([_definition]);

  @override
  PracticeDefinition? byId(String id) =>
      id == _definition.id ? _definition : null;

  @override
  List<PracticeDefinition> byMode(PracticeMode mode) => _definition.mode == mode
      ? List<PracticeDefinition>.unmodifiable([_definition])
      : const <PracticeDefinition>[];

  @override
  List<PracticeDefinition> byDifficulty(PracticeDifficulty difficulty) =>
      _definition.difficulty == difficulty
      ? List<PracticeDefinition>.unmodifiable([_definition])
      : const <PracticeDefinition>[];
}
