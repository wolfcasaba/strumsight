import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/practice/application/practice_session_providers.dart';
import 'package:strumsight/features/practice/data/local_practice_history_repository.dart';
import 'package:strumsight/features/practice/domain/model/practice_attempt_result.dart';
import 'package:strumsight/features/practice/domain/model/practice_history_entry.dart';
import 'package:strumsight/features/practice/domain/model/practice_metrics.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_result.dart';
import 'package:strumsight/features/practice/domain/model/practice_verdict.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/repository/practice_session_recorder.dart';

import '../../../support/preference_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // B2 — write-then-drop. The production recorder provider today wires
  // placeholder session-metadata codes (mode/source/definition = "unknown").
  // The serializer rejects unknown enum codes on read, so a record written
  // through the old wiring would be silently dropped on the next load
  // (write-then-drop, brief B2). The fix routes the provider through a
  // NoopPracticeSessionRecorder while the metadata is still placeholder,
  // pending R19's real session-metadata plumbing.
  group('B2 — no write-then-drop under placeholder metadata', () {
    test(
      'production provider with placeholder metadata writes 0 loadable records',
      () async {
        final store = InMemoryKeyValueStore();
        final container = ProviderContainer(
          overrides: [
            preferenceStoreOverride(store),
            // Production-shaped flag: detail-on, engine-v2 on.
            appConfigProvider.overrideWithValue(_prodLikeConfig()),
          ],
        );
        addTearDown(container.dispose);

        final recorder = container.read(practiceSessionRecorderProvider);
        final repository = container.read(practiceHistoryRepositoryProvider);

        // The wired provider must be the no-op recorder — the placeholder
        // metadata gate MUST short-circuit before the real recorder runs.
        expect(recorder, isA<NoopPracticeSessionRecorder>());

        // A real record() call (the production path the controller takes
        // on every finish) returns Success without writing anything that
        // would be discarded by the reader.
        final result = await recorder.record(_result('session-x'));
        expect(result, isA<Success<void>>());

        // The V2 document is untouched — no drop-eligible bytes are left
        // behind on disk.
        expect(
          store.values.containsKey(StorageKeys.practiceHistoryV2),
          isFalse,
        );

        // A fresh load returns zero records.
        final loadResult = await repository.load();
        expect(loadResult, isA<Success<List<PracticeHistoryEntry>>>());
        expect(
          (loadResult as Success<List<PracticeHistoryEntry>>).value,
          isEmpty,
        );
      },
    );

    test('the placeholder gate uses the documented placeholders '
        '(isPlaceholderPracticeMetadata)', () {
      expect(
        isPlaceholderPracticeMetadata(
          modeCode: 'practice.mode.unknown',
          sourceCode: 'practice.source.unknown',
          definitionId: 'practice.definition.unknown',
        ),
        isTrue,
      );
      expect(
        isPlaceholderPracticeMetadata(
          modeCode: 'strumPattern',
          sourceCode: 'builtin',
          definitionId: 'builtin.strumPattern',
        ),
        isFalse,
      );
    });
  });
}

// --- helpers ---------------------------------------------------------------

AppConfig _prodLikeConfig() {
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

PracticeSessionResult _result(String id) {
  return PracticeSessionResult(
    id: id,
    activeDuration: const Duration(seconds: 30),
    pausedDuration: Duration.zero,
    attempts: <PracticeAttemptResult>[
      PracticeAttemptResult(
        index: 0,
        tempo: const Tempo(90),
        metrics: _metrics,
        verdicts: const <PracticeVerdict>[],
        outcome: PracticeAttemptOutcome.passed,
      ),
    ],
    finishReason: PracticeFinishReason.userFinished,
    highestStableTempo: const Tempo(90),
    coachingSummary: const <String>[],
  );
}

const PracticeMetrics _metrics = PracticeMetrics(
  completion: MetricAvailable(0.9),
  rhythm: MetricAvailable(0.85),
  direction: MetricAvailable(0.95),
  chord: MetricNotApplicable(),
  overall: MetricAvailable(0.9),
  totalTargets: 16,
  resolvedTargets: 14,
  maxCombo: 8,
  scorePoints: 800,
  meanAbsoluteOffset: Duration(milliseconds: 18),
  timingBias: Duration.zero,
);
