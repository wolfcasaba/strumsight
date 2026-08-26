// E13-R21 §6 A1, A7 — practice setup reproducibility and validation gating.
//
// A1: the same `PracticeSessionConfig` edits applied to two independent
// `PracticeSetupController`s (built fresh from the same definition) must
// produce value-equal `PreparePractice` commands — "the same configuration
// reproduces the same session" (brief §6 A1).
//
// A7: invalid input never reaches the prepare sink. `controller.start()`
// is the screen's own gate (the Start button's `onPressed` is `null` under
// the identical condition — see `practice_setup_screen_test.dart`'s
// existing "Start button is disabled when config is invalid" cell); this
// file pins the CONTROLLER-side half of that gate directly.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/application/practice_catalog_controller.dart';
import 'package:strumsight/features/practice/application/practice_session_command.dart';
import 'package:strumsight/features/practice/application/practice_setup_controller.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_difficulty.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/repository/practice_catalog_repository.dart';

import '../../../support/preference_store.dart';
import '../../../fixtures/practice/session/practice_session_test_fixtures.dart';

class _SingleDefRepository implements PracticeCatalogRepository {
  const _SingleDefRepository(this.definition);
  final PracticeDefinition definition;

  @override
  List<PracticeDefinition> all() =>
      List<PracticeDefinition>.unmodifiable([definition]);
  @override
  PracticeDefinition? byId(String id) =>
      id == definition.id ? definition : null;
  @override
  List<PracticeDefinition> byMode(PracticeMode mode) => definition.mode == mode
      ? List<PracticeDefinition>.unmodifiable([definition])
      : const <PracticeDefinition>[];
  @override
  List<PracticeDefinition> byDifficulty(PracticeDifficulty difficulty) =>
      const <PracticeDefinition>[];
}

class _RecordingSink {
  final List<PreparePractice> commands = <PreparePractice>[];
  void call(PreparePractice command) => commands.add(command);
}

ProviderContainer _containerFor(
  PracticeDefinition definition,
  _RecordingSink sink,
) => ProviderContainer(
  overrides: [
    ...preferenceOverrides(),
    practiceCatalogRepositoryProvider.overrideWithValue(
      _SingleDefRepository(definition),
    ),
    practicePrepareSinkProvider.overrideWithValue(sink.call),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A1 — reproducible from configuration', () {
    test('the same edits on two independent controllers produce a value-equal '
        'PreparePractice.config', () {
      final definition = practiceSessionFixtureDefinition(
        id: 'fixture.setup-repro',
      );
      final sinkA = _RecordingSink();
      final sinkB = _RecordingSink();
      final containerA = _containerFor(definition, sinkA);
      final containerB = _containerFor(definition, sinkB);
      addTearDown(containerA.dispose);
      addTearDown(containerB.dispose);

      void applySameEdits(ProviderContainer container) {
        final controller = container.read(
          practiceSetupControllerProvider(definition).notifier,
        );
        controller.setTempoBpm(132);
        controller.setCountInBars(2);
        controller.setLoopCount(8);
        controller.setMetronomeEnabled(false);
        controller.setAccentEnabled(true);
        controller.setChordHintEnabled(false);
      }

      applySameEdits(containerA);
      applySameEdits(containerB);

      final sentA = containerA
          .read(practiceSetupControllerProvider(definition).notifier)
          .start();
      final sentB = containerB
          .read(practiceSetupControllerProvider(definition).notifier)
          .start();

      expect(sentA, isTrue);
      expect(sentB, isTrue);
      expect(sinkA.commands.length, 1);
      expect(sinkB.commands.length, 1);
      // Value equality on PracticeSessionConfig (field-by-field, per its
      // own `==`) — same edits, same definition, same resulting config.
      expect(sinkA.commands.single.config, sinkB.commands.single.config);
      expect(
        sinkA.commands.single.definition.id,
        sinkB.commands.single.definition.id,
      );
    });

    test('a config left untouched reproduces the definition-seeded defaults '
        'on every fresh controller', () {
      final definition = practiceSessionFixtureDefinition(
        id: 'fixture.setup-repro-seed',
      );
      final sinkA = _RecordingSink();
      final sinkB = _RecordingSink();
      final containerA = _containerFor(definition, sinkA);
      final containerB = _containerFor(definition, sinkB);
      addTearDown(containerA.dispose);
      addTearDown(containerB.dispose);

      containerA
          .read(practiceSetupControllerProvider(definition).notifier)
          .start();
      containerB
          .read(practiceSetupControllerProvider(definition).notifier)
          .start();

      expect(sinkA.commands.single.config, sinkB.commands.single.config);
    });
  });

  group('A7 — invalid configuration never reaches the sink', () {
    test('out-of-range count-in bars: start() returns false, 0 commands', () {
      final definition = practiceSessionFixtureDefinition(
        id: 'fixture.setup-invalid-countin',
      );
      final sink = _RecordingSink();
      final container = _containerFor(definition, sink);
      addTearDown(container.dispose);

      final controller = container.read(
        practiceSetupControllerProvider(definition).notifier,
      );
      controller.setCountInBars(5); // domain max is 4

      final sent = controller.start();

      expect(sent, isFalse);
      expect(sink.commands, isEmpty);
      expect(
        container.read(practiceSetupControllerProvider(definition)).isValid,
        isFalse,
      );
    });

    test('out-of-range tempo: start() returns false, 0 commands', () {
      final definition = practiceSessionFixtureDefinition(
        id: 'fixture.setup-invalid-tempo',
      );
      final sink = _RecordingSink();
      final container = _containerFor(definition, sink);
      addTearDown(container.dispose);

      final controller = container.read(
        practiceSetupControllerProvider(definition).notifier,
      );
      controller.setTempoBpm(1000); // domain max is 300

      expect(controller.start(), isFalse);
      expect(sink.commands, isEmpty);
    });

    test('correcting the field back into range restores start() to true', () {
      final definition = practiceSessionFixtureDefinition(
        id: 'fixture.setup-invalid-then-fixed',
      );
      final sink = _RecordingSink();
      final container = _containerFor(definition, sink);
      addTearDown(container.dispose);

      final controller = container.read(
        practiceSetupControllerProvider(definition).notifier,
      );
      controller.setLoopCount(99); // domain max is 32
      expect(controller.start(), isFalse);

      controller.setLoopCount(4);
      expect(controller.start(), isTrue);
      expect(sink.commands.length, 1);
    });
  });
}
