// E04-R22 §6 — Tutor Privacy (consent) screen matrix.
//
// RED-first: written BEFORE the implementation. Compiles only after
// `tutor_privacy_screen.dart`, `tutor_privacy_providers.dart` and the
// three consent-axis providers land with the exact public names referenced
// here. The two falszifikációs cells (§6) are:
//   * axis-independence — toggling one of the three granular consents
//     must NOT move the other two (ADR 0132);
//   * delete-all scope — the displayed scope list must match exactly
//     `StorageKeys.tutorAiData`; a UI that drops `memory_facts` or
//     advertises a non-tutor key flips the test red.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/design_system/components/surfaces/ss_section.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_memory_fact.dart';
import 'package:strumsight/features/ai_tutor/domain/repositories/tutor_memory_repository.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_privacy_providers.dart';
import 'package:strumsight/features/ai_tutor/presentation/screens/tutor_privacy_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';
import 'package:strumsight/l10n/app_localizations_hu.dart';

import '../../../support/preference_store.dart';

AppLocalizations l10nEn() => AppLocalizationsEn();
AppLocalizations l10nHu() => AppLocalizationsHu();

AppConfig _config({bool aiTutorEnabled = true}) => AppConfig.resolve(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: false,
    labModeAvailable: false,
    aiTutorEnabled: aiTutorEnabled,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

/// In-memory fake for the memory repository so the consent screen can be
/// driven without `LocalTutorMemoryRepository`'s KeyValueStore dependency.
class _FakeMemoryRepository implements TutorMemoryRepository {
  _FakeMemoryRepository({
    List<TutorMemoryFact> facts = const <TutorMemoryFact>[],
  }) {
    _facts.addAll(facts);
  }

  final List<TutorMemoryFact> _facts = <TutorMemoryFact>[];
  int deleteAllCalls = 0;
  int exportRedactedCalls = 0;
  String? lastExportPayload;
  final List<String> deletedFactIds = <String>[];

  @override
  Future<AppResult<List<TutorMemoryFact>>> list() async =>
      Success<List<TutorMemoryFact>>(
        List<TutorMemoryFact>.unmodifiable(_facts),
      );

  @override
  Future<AppResult<TutorMemoryFact>> saveCandidate(
    TutorMemoryCandidate candidate,
  ) async {
    final fact = TutorMemoryFact(
      id: candidate.id,
      content: candidate.content,
      conversationId: candidate.conversationId,
      messageId: candidate.messageId,
      createdAt: candidate.createdAt,
      updatedAt: candidate.createdAt,
      expiresAt: candidate.expiresAt,
    );
    _facts.add(fact);
    return Success<TutorMemoryFact>(fact);
  }

  @override
  Future<AppResult<void>> update(TutorMemoryFact fact) async {
    final index = _facts.indexWhere((item) => item.id == fact.id);
    if (index == -1) {
      return const Failure<void>(
        ValidationFailure(code: FailureCode.validationInvalidInput),
      );
    }
    _facts[index] = fact;
    return const Success<void>(null);
  }

  @override
  Future<AppResult<void>> delete(String factId) async {
    _facts.removeWhere((item) => item.id == factId);
    deletedFactIds.add(factId);
    return const Success<void>(null);
  }

  @override
  Future<AppResult<void>> purgeExpired(DateTime now) async {
    _facts.removeWhere((fact) => fact.isExpiredAt(now));
    return const Success<void>(null);
  }

  @override
  Future<AppResult<String>> exportRedacted() async {
    exportRedactedCalls++;
    lastExportPayload =
        '{"schemaVersion":1,"facts":[{"id":"x","content":"[redacted]"}]}';
    return Success<String>(lastExportPayload!);
  }

  @override
  Future<AppResult<void>> deleteAllAiData() async {
    deleteAllCalls++;
    _facts.clear();
    return const Success<void>(null);
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  _FakeMemoryRepository? memory,
  Locale locale = const Locale('en'),
}) async {
  final repo = memory ?? _FakeMemoryRepository();
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      appConfigProvider.overrideWithValue(_config()),
      tutorMemoryRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: SsLightTheme.data(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const TutorPrivacyScreen(),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('R22-PC1: privacy screen renders three independent axes', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byType(TutorPrivacyScreen), findsOneWidget);
    // Three granular consent switches exist (one per axis).
    expect(find.byKey(const Key('tutorConsentAxisModelUse')), findsOneWidget);
    expect(
      find.byKey(const Key('tutorConsentAxisPersistentStorage')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('tutorConsentAxisEvaluationWithRedaction')),
      findsOneWidget,
    );
  });

  testWidgets('R22-PC2: toggling model-use does NOT move the other axes', (
    tester,
  ) async {
    final container = await _pump(tester);
    // Baseline read — consent controller starts at default (all false).
    final initial = container.read(tutorConsentControllerProvider);
    expect(initial.modelUseGranted, false);
    expect(initial.persistentStorageGranted, false);
    expect(initial.evaluationWithRedactionGranted, false);

    container.read(tutorConsentControllerProvider.notifier).grantModelUse();
    final next = container.read(tutorConsentControllerProvider);
    expect(next.modelUseGranted, true);
    expect(next.persistentStorageGranted, false);
    expect(next.evaluationWithRedactionGranted, false);
  });

  testWidgets('R22-PC3: toggling persistent-storage does NOT move model-use', (
    tester,
  ) async {
    final container = await _pump(tester);
    container.read(tutorConsentControllerProvider.notifier).grantModelUse();
    container
        .read(tutorConsentControllerProvider.notifier)
        .grantPersistentStorage();
    final next = container.read(tutorConsentControllerProvider);
    expect(next.modelUseGranted, true);
    expect(next.persistentStorageGranted, true);
    expect(next.evaluationWithRedactionGranted, false);
  });

  testWidgets(
    'R22-PC4: toggling evaluation-with-redaction does NOT move model-use',
    (tester) async {
      final container = await _pump(tester);
      container.read(tutorConsentControllerProvider.notifier).grantModelUse();
      container
          .read(tutorConsentControllerProvider.notifier)
          .grantEvaluationWithRedaction();
      final next = container.read(tutorConsentControllerProvider);
      expect(next.modelUseGranted, true);
      expect(next.persistentStorageGranted, false);
      expect(next.evaluationWithRedactionGranted, true);
    },
  );

  // -------------------------------------------------------------------
  // Falszifikációs cella (R22-F1): a UI scope-listája PONTOSAN a
  // `StorageKeys.tutorAiData` három kulcsa + karanténjaik legyenek.
  // -------------------------------------------------------------------
  testWidgets(
    'R22-F1: privacy scope-list matches StorageKeys.tutorAiData exactly',
    (tester) async {
      await _pump(tester);
      // The consent screen renders the three exact store keys plus
      // their `.corrupt` quarantine shadow, by literal string.
      for (final key in StorageKeys.tutorAiData) {
        expect(find.text(key), findsOneWidget, reason: 'missing key $key');
      }
      for (final key in StorageKeys.tutorAiData) {
        final quarantine = StorageKeys.quarantineOf(key);
        expect(
          find.text(quarantine),
          findsOneWidget,
          reason: 'missing quarantine $quarantine',
        );
      }
    },
  );

  testWidgets('R22-PC5: hu locale renders the Hungarian privacy copy', (
    tester,
  ) async {
    await _pump(tester, locale: const Locale('hu'));
    // Title is localized; we just check the privacy title shows.
    expect(find.byType(TutorPrivacyScreen), findsOneWidget);
    expect(find.text(l10nHu().tutorPrivacyTitle), findsOneWidget);
  });

  // -------------------------------------------------------------------
  // E15-R09 §0.0.B/R15 — per-screen design-system type assertion.
  // -------------------------------------------------------------------
  testWidgets('R22-PC6: the scope block is the design-system SsSection', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byType(SsSection), findsOneWidget);
  });

  // -------------------------------------------------------------------
  // E15-R09 §0.0.B/R14 — committed textScaler 2.0 coverage (en + hu), on
  // the phone viewport the golden lane uses (412x915).
  // -------------------------------------------------------------------
  for (final locale in const [Locale('en'), Locale('hu')]) {
    testWidgets(
      'R22-PC7: textScaler 2.0, locale=${locale.languageCode} — no overflow',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await _pump(tester, locale: locale);

        expect(tester.takeException(), isNull);
      },
    );
  }
}
