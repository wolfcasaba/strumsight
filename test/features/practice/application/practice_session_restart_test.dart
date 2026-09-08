// Audit H2 / L3 regression — a practice session must be startable more than
// once per app launch.
//
// MEASURED root cause (emulator walkthrough, release APK): the second
// Practice opened on the FIRST session's terminal state — an "empty" screen
// whose only content was the state dump and an Exit button.
//
//   * `practiceSessionControllerProvider` is a family keyed by
//     `(definition, config)`, so a second Start with unchanged settings
//     resolves to the SAME element;
//   * `practiceSessionHostProvider` is NOT auto-dispose and watches that
//     element, so it is never collected between sessions;
//   * `_reducePreparePractice` rejects `PreparePractice` from `completed`
//     and from `cancelled`.
//
// Result: the second `PreparePractice` was a no-op on a controller that was
// still `completed`. This file drives the REAL provider graph (only the
// platform edges are faked, per the E02-R21 rule) through two consecutive
// sessions on one container — it is red on the pre-fix tree.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/logging/logger_provider.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/practice/application/practice_session_command.dart';
import 'package:strumsight/features/practice/application/practice_setup_controller.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_event.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_state.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/presentation/practice_effect_listener.dart';

import '../../../support/fake_audio.dart';
import '../../../support/fake_engines.dart';
import '../../../support/preference_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('H2 — a second session starts fresh', () {
    test('a completed session restarts fresh', () async {
      final container = _buildContainer();
      addTearDown(container.dispose);

      final definition = _definition();
      final setup = container.read(
        practiceSetupControllerProvider(definition).notifier,
      );

      // --- session 1 -------------------------------------------------
      expect(setup.start(), isTrue);
      final first = container.read(practiceSessionHostProvider);
      expect(first, isNotNull, reason: 'the prepare sink publishes a host');
      await _driveToCompleted(first!);
      expect(first.state.status, PracticeSessionStatus.completed);

      // --- session 2, byte-identical settings -------------------------
      // The same `(definition, config)` pair means the same family key.
      // This is the exact repro: the user leaves the session and taps
      // Start again without touching a single control.
      expect(setup.start(), isTrue);
      final second = container.read(practiceSessionHostProvider);
      expect(second, isNotNull);
      expect(
        second!.state.status,
        isNot(PracticeSessionStatus.completed),
        reason:
            "H2: the second Start must not open on the first session's "
            'terminal state — the emulator showed "completed" before the '
            'user pressed anything.',
      );
      // Not merely "not completed": it must actually be preparing a new
      // attempt, and it must reach a startable state on its own.
      expect(second.state.status, PracticeSessionStatus.preparing);
      await _waitForStatus(second, const {
        PracticeSessionStatus.ready,
        PracticeSessionStatus.permissionRequired,
      });
      expect(
        second.state.attemptIndex,
        0,
        reason: 'a fresh session, not a resumed one',
      );
    });

    test('a cancelled session restarts fresh', () async {
      final container = _buildContainer();
      addTearDown(container.dispose);

      final definition = _definition();
      final setup = container.read(
        practiceSetupControllerProvider(definition).notifier,
      );

      expect(setup.start(), isTrue);
      final first = container.read(practiceSessionHostProvider)!;
      await _waitForStatus(first, const {
        PracticeSessionStatus.ready,
        PracticeSessionStatus.permissionRequired,
      });
      first.send(const CancelPractice());
      await _waitForStatus(first, const {PracticeSessionStatus.cancelled});

      expect(setup.start(), isTrue);
      final second = container.read(practiceSessionHostProvider)!;
      expect(
        second.state.status,
        PracticeSessionStatus.preparing,
        reason:
            'H2: `PreparePractice` is rejected from `cancelled`, so a '
            'reused controller would still report `cancelled` here.',
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Container factory — production practice wiring, faked platform edges only.
// ---------------------------------------------------------------------------

ProviderContainer _buildContainer() {
  final engine = FakeStrumEngine();
  addTearDown(engine.dispose);
  return ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      ...fakeAudioOverrides(),
      strumEngineProvider.overrideWithValue(engine),
      appConfigProvider.overrideWithValue(_config()),
      appLoggerProvider.overrideWithValue(const _NoopLogger()),
    ],
  );
}

class _NoopLogger implements AppLogger {
  const _NoopLogger();
  @override
  void debug(String event, {Map<String, Object?> fields = const {}}) {}
  @override
  void info(String event, {Map<String, Object?> fields = const {}}) {}
  @override
  void warning(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) {}
  @override
  void error(
    String event, {
    required Object error,
    required StackTrace stackTrace,
    Map<String, Object?> fields = const {},
  }) {}
}

// ---------------------------------------------------------------------------
// Drivers
// ---------------------------------------------------------------------------

Future<void> _driveToCompleted(PracticeSessionHost host) async {
  await _waitForStatus(host, const {
    PracticeSessionStatus.ready,
    PracticeSessionStatus.permissionRequired,
  });
  host.send(const StartPractice());
  await _waitForStatus(host, const {PracticeSessionStatus.running});
  host.send(const FinishPractice());
  await _waitForStatus(host, const {PracticeSessionStatus.completed});
}

Future<void> _waitForStatus(
  PracticeSessionHost host,
  Set<PracticeSessionStatus> target,
) async {
  if (target.contains(host.state.status)) return;
  await host.states
      .firstWhere((state) => target.contains(state.status))
      .timeout(const Duration(seconds: 5));
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

PracticeDefinition _definition() {
  return PracticeDefinition(
    id: 'restart.test.definition',
    schemaVersion: 1,
    titleKey: 'restart.test.title',
    descriptionKey: 'restart.test.desc',
    mode: PracticeMode.strumPattern,
    source: PracticeSource.builtin,
    meter: const Meter(beatsPerBar: 4),
    defaultTempo: const Tempo(120),
    totalBeats: BeatPosition.quarters(8),
    events: <PracticeEvent>[
      PracticeEvent(
        id: 'restart.test.e0',
        position: BeatPosition.fromTicks(0),
        direction: StrumDirection.down,
      ),
      PracticeEvent(
        id: 'restart.test.e1',
        position: BeatPosition.fromTicks(4 * 480),
        direction: StrumDirection.up,
      ),
    ],
    scoringProfile: ScoringProfile.legacyLearnParity,
    skillTags: const ['restart-test'],
    displayTitle: 'Restart test',
  );
}

AppConfig _config() {
  return AppConfig.resolve(
    environment: AppEnvironment.development,
    apiBaseUrl: AppConfig.devApiBaseUrl,
    flags: const FeatureFlags(
      accountEnabled: false,
      diagnosticsEnabled: false,
      labModeAvailable: false,
      practiceEngineV2Enabled: true,
      practiceDetailedHistoryEnabled: true,
    ),
    diagnosticsToken: AppConfig.devDiagnosticsToken,
    buildMode: 'debug',
    appVersion: 'test',
  );
}
