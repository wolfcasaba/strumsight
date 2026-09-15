// E17-R04 (ADR 0523) — the practice-plan preview is REACHABLE from the
// Tutor chat, on the local deterministic path, and its "Start plan" action
// reuses the EXISTING Practice Setup route.
//
// Cells (brief §6):
//   A2 — the chat entry (AppBar action, and a tapped plan block inside a
//        tutor message) opens `PracticePlanPreviewScreen` with a REAL draft
//        composed by a real `ProviderContainer` (real Practice catalog, real
//        tutor profile; only the chat controller and the memory store are
//        faked — no orchestrator, no network).
//   A3 — "Start plan" drives the REAL app router to
//        `/practice/setup?id=<catalog entry>` and renders the REAL
//        `PracticeSetupScreen`; a static audit pins that the ai_tutor tree
//        carries no session launcher of its own (the §6.1 falsification
//        probe — a tutor-specific `GoRoute`/`PreparePractice` — turns the
//        audit red).
//   A4 — draft production under an `HttpOverrides` that throws on ANY
//        client creation still succeeds (no cloud call, §5.2).
//   Save — "Save plan" lands in the local tutor memory repository as one
//        inspectable fact and the screen confirms it.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/features/ai_tutor/application/controller/tutor_state.dart';
import 'package:strumsight/features/ai_tutor/data/repositories/local_tutor_memory_repository.dart';
import 'package:strumsight/features/ai_tutor/domain/models/practice_plan_block.dart';
import 'package:strumsight/features/ai_tutor/domain/models/practice_plan_draft.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_content_block.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_ids.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_message.dart';
import 'package:strumsight/features/ai_tutor/domain/services/practice_plan_validator.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_practice_plan_providers.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_privacy_providers.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_providers.dart';
import 'package:strumsight/features/ai_tutor/presentation/screens/practice_plan_preview_screen.dart';
import 'package:strumsight/features/ai_tutor/presentation/screens/tutor_chat_screen.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_setup_screen.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_auth.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

AppLocalizations l10nEn() => AppLocalizationsEn();

// ---------------------------------------------------------------------------
// Fake chat controller — the same shape `tutor_chat_screen_test.dart` uses,
// so the chat renders without the orchestrator.
// ---------------------------------------------------------------------------
class _FakeController extends ChangeNotifier implements TutorChatController {
  _FakeController({
    List<TutorMessage> initialMessages = const <TutorMessage>[],
  }) {
    _messages.addAll(initialMessages);
    _emit();
  }

  final List<TutorMessage> _messages = <TutorMessage>[];
  final StreamController<TutorChatState> _statesController =
      StreamController<TutorChatState>.broadcast();

  @override
  List<TutorMessage> get messages => List<TutorMessage>.unmodifiable(_messages);

  @override
  TutorTurnStatus status = TutorTurnStatus.idle;

  @override
  String responseText = '';

  @override
  String draft = '';

  @override
  bool isOnline = false;

  @override
  List<TutorBannerKind> banners = const <TutorBannerKind>[];

  @override
  Stream<TutorChatState> get states => _statesController.stream;

  void _emit() {
    _statesController.add(
      TutorChatState(
        status: status,
        responseText: responseText,
        banners: banners,
        isOnline: isOnline,
        draft: draft,
        messages: List<TutorMessage>.unmodifiable(_messages),
      ),
    );
    notifyListeners();
  }

  @override
  void setDraft(String value) {
    draft = value;
    _emit();
  }

  @override
  void send() {}

  @override
  void cancel() {}

  @override
  void retry() {}

  @override
  void setOnline(bool value) {
    isOnline = value;
    _emit();
  }

  @override
  void setBanners(List<TutorBannerKind> value) {
    banners = List<TutorBannerKind>.unmodifiable(value);
    _emit();
  }

  Future<void> close() => _statesController.close();
}

/// Throws on ANY client creation — the A4 probe. `HttpOverrides.runZoned`
/// routes every `HttpClient()` (dart:io, which Dio's default adapter uses)
/// through this factory inside the zone.
final class _NetworkProbe {
  int clientCreations = 0;

  HttpClient createHttpClient(SecurityContext? context) {
    clientCreations++;
    throw StateError('draft production must not create a network client');
  }
}

AppConfig _config() => AppConfig.resolve(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: const FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: false,
    labModeAvailable: false,
    practiceEngineV2Enabled: true,
    aiTutorEnabled: true,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

TutorMessage _tutorMessageWithPlan() => TutorMessage(
  id: TutorMessageId('m-plan'),
  role: TutorMessageRole.tutor,
  createdAt: DateTime.utc(2026, 9, 15),
  sequence: 1,
  deliveryState: TutorMessageDeliveryState.complete,
  blocks: <TutorContentBlock>[
    TutorTextBlock(text: 'Here is a plan for today.'),
    TutorPracticePlanBlock(planId: 'p1', title: 'Rhythm focus'),
  ],
);

/// A tall surface so the preview's Save/Start row (below three block cards)
/// is inside the viewport — the same trick the preview's own large-text
/// cell uses.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// The chat on a bare `MaterialApp` (no router) with a REAL container: the
/// Practice catalog and the tutor profile are production providers; only the
/// chat controller and the memory store are faked.
Future<ProviderContainer> _pumpChat(
  WidgetTester tester, {
  _FakeController? controller,
  InMemoryKeyValueStore? store,
}) async {
  final fake = controller ?? _FakeController();
  addTearDown(fake.close);
  final keyValueStore = store ?? InMemoryKeyValueStore();
  final container = ProviderContainer(
    overrides: [
      preferenceStoreOverride(keyValueStore),
      appConfigProvider.overrideWithValue(_config()),
      tutorChatControllerProvider.overrideWithValue(fake),
      tutorMemoryRepositoryProvider.overrideWithValue(
        LocalTutorMemoryRepository(keyValueStore: keyValueStore),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: SsLightTheme.data(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const TutorChatScreen(),
      ),
    ),
  );
  await tester.pump();
  return container;
}

/// The REAL app router on the tutor chat route. Only platform edges are
/// faked (engine, audio, auth, preferences) — mirrors
/// `practice_setup_navigation_test.dart`, so the Practice side of the
/// hand-off is production wiring, not a stub route.
Future<ProviderContainer> _pumpRoutedChat(WidgetTester tester) async {
  final fake = _FakeController();
  addTearDown(fake.close);
  final engine = FakeStrumEngine();
  final keyValueStore = InMemoryKeyValueStore();
  final container = ProviderContainer(
    overrides: [
      preferenceStoreOverride(keyValueStore),
      ...fakeAudioOverrides(),
      strumEngineProvider.overrideWithValue(engine),
      onboardingSeenProvider.overrideWith(() => OnboardingController(true)),
      accountEnabledProvider.overrideWithValue(false),
      tokenStoreProvider.overrideWithValue(FakeTokenStore()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      appConfigProvider.overrideWithValue(_config()),
      tutorChatControllerProvider.overrideWithValue(fake),
      tutorMemoryRepositoryProvider.overrideWithValue(
        LocalTutorMemoryRepository(keyValueStore: keyValueStore),
      ),
    ],
  );
  final router = container.read(routerProvider);

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await engine.dispose();
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: SsLightTheme.data(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  router.go(AppRoutes.tutorChat);
  await tester.pumpAndSettle();
  expect(find.byType(TutorChatScreen), findsOneWidget);
  return container;
}

Future<void> _openPreviewFromAppBar(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('tutor-plan-preview')));
  await tester.pumpAndSettle();
  expect(find.byType(PracticePlanPreviewScreen), findsOneWidget);
}

Future<void> _confirmSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('ss-tool-confirmation-confirm')));
  await tester.pumpAndSettle();
}

PracticePlanPreviewScreen _previewWidget(WidgetTester tester) =>
    tester.widget<PracticePlanPreviewScreen>(
      find.byType(PracticePlanPreviewScreen),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('A2 — entry from the chat', () {
    testWidgets('the AppBar entry opens the preview with the local '
        'deterministic draft and a composed validation context', (
      tester,
    ) async {
      final container = await _pumpChat(tester);

      await _openPreviewFromAppBar(tester);

      final screen = _previewWidget(tester);
      expect(screen.draft.source, PracticePlanSource.deterministicTemplate);
      expect(screen.draft.targetDuration, tutorPracticePlanDefaultDuration);
      expect(screen.draft.blocks, isNotEmpty);
      expect(find.text(l10nEn().aiTutorPlanTotalDuration(10)), findsOneWidget);

      // The context is composed from REAL sources, not the empty fixture the
      // screen's own test uses: the Practice catalog and the profile tuning.
      final catalogIds = container
          .read(practiceCatalogProvider)
          .map((definition) => definition.id)
          .toSet();
      expect(catalogIds, isNotEmpty);
      expect(screen.validationContext.practiceTargetIds, catalogIds);
      expect(
        screen.validationContext.capabilities,
        contains(PracticePlanCapability.practiceTarget),
      );
      expect(screen.validationContext.activeTuning, <String>[
        'E2',
        'A2',
        'D3',
        'G3',
        'B3',
        'E4',
      ]);
      // A valid template: Start is enabled.
      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(const ValueKey('plan-start')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('a plan block inside a tutor message opens the same preview', (
      tester,
    ) async {
      final fake = _FakeController(initialMessages: [_tutorMessageWithPlan()]);
      await _pumpChat(tester, controller: fake);

      await tester.tap(find.byKey(const ValueKey('tutor-plan-block-p1')));
      await tester.pumpAndSettle();

      expect(find.byType(PracticePlanPreviewScreen), findsOneWidget);
      expect(
        _previewWidget(tester).draft.source,
        PracticePlanSource.deterministicTemplate,
      );
    });

    testWidgets('the entry never watches the plan graph while the chat '
        'merely renders (pinned chat containers carry no Practice overrides)', (
      tester,
    ) async {
      // A container WITHOUT the memory repository or preferences — exactly
      // what `ai_mode_visibility_test.dart` builds. Rendering must not touch
      // the plan providers; only the tap does.
      final fake = _FakeController();
      addTearDown(fake.close);
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(_config()),
          tutorChatControllerProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const TutorChatScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('tutor-plan-preview')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('A3 — Start reuses the existing Practice launch route', () {
    testWidgets('Start plan drives the real router to /practice/setup?id= '
        'and renders the real PracticeSetupScreen', (tester) async {
      _useTallSurface(tester);
      final container = await _pumpRoutedChat(tester);
      await _openPreviewFromAppBar(tester);

      await tester.tap(find.byKey(const ValueKey('plan-start')));
      await tester.pumpAndSettle();
      await _confirmSheet(tester);

      final uri = container
          .read(routerProvider)
          .routeInformationProvider
          .value
          .uri;
      expect(uri.path, AppRoutes.practiceSetup);
      // The 10-minute template opens with a warm-up block, which the launch
      // resolver maps onto the catalog's first rhythm-only exercise — a
      // REAL catalog id, looked up the same way the Setup screen does.
      final expectedId = container
          .read(practiceCatalogProvider)
          .firstWhere(
            (definition) => definition.mode == PracticeMode.rhythmOnly,
          )
          .id;
      expect(uri.queryParameters['id'], expectedId);
      expect(find.byType(PracticeSetupScreen), findsOneWidget);
      expect(find.byType(PracticePlanPreviewScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with Practice Engine V2 off, Start reports instead of '
        'routing to an unregistered practice route', (tester) async {
      _useTallSurface(tester);
      final fake = _FakeController();
      addTearDown(fake.close);
      final keyValueStore = InMemoryKeyValueStore();
      final container = ProviderContainer(
        overrides: [
          preferenceStoreOverride(keyValueStore),
          appConfigProvider.overrideWithValue(
            AppConfig.resolve(
              environment: AppEnvironment.development,
              apiBaseUrl: AppConfig.devApiBaseUrl,
              flags: const FeatureFlags(
                accountEnabled: false,
                diagnosticsEnabled: false,
                labModeAvailable: false,
                aiTutorEnabled: true,
              ),
              diagnosticsToken: AppConfig.devDiagnosticsToken,
              buildMode: 'test',
              appVersion: 'test',
            ),
          ),
          tutorChatControllerProvider.overrideWithValue(fake),
          tutorMemoryRepositoryProvider.overrideWithValue(
            LocalTutorMemoryRepository(keyValueStore: keyValueStore),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const TutorChatScreen(),
          ),
        ),
      );
      await tester.pump();
      await _openPreviewFromAppBar(tester);
      expect(
        _previewWidget(tester).validationContext.capabilities,
        isNot(contains(PracticePlanCapability.practiceTarget)),
      );

      await tester.tap(find.byKey(const ValueKey('plan-start')));
      await tester.pumpAndSettle();
      await _confirmSheet(tester);

      expect(find.text(l10nEn().tutorPlanStartUnavailable), findsOneWidget);
      expect(find.byType(PracticePlanPreviewScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Let the SnackBar's own dismiss timer elapse before teardown.
      await tester.pump(const Duration(seconds: 5));
    });

    test('the ai_tutor tree carries no session launcher of its own '
        '(§6.1 falsification guard)', () {
      final sources = Directory('lib/features/ai_tutor')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      expect(sources, isNotEmpty);
      const launcherMarkers = <String>[
        'GoRoute(',
        'PreparePractice(',
        'practicePrepareSinkProvider',
        'practiceSessionControllerProvider',
        'practiceActiveSessionInputsProvider',
        'AppRoutes.practiceSession',
      ];
      for (final file in sources) {
        final source = file.readAsStringSync();
        for (final marker in launcherMarkers) {
          expect(
            source,
            isNot(contains(marker)),
            reason:
                '${file.path} must not build a Tutor-specific practice '
                'launcher (ADR 0523 §5.1); found "$marker"',
          );
        }
      }
      final chat = File(
        'lib/features/ai_tutor/presentation/screens/tutor_chat_screen.dart',
      ).readAsStringSync();
      expect(
        chat,
        contains('AppRoutes.practiceSetup'),
        reason: 'Start plan must hand off to the existing Setup route',
      );
    });
  });

  group('A4 — no cloud call on the local path', () {
    test('draft production succeeds under a throwing HttpOverrides', () {
      final probe = _NetworkProbe();
      final container = ProviderContainer(
        overrides: [
          ...preferenceOverrides(),
          appConfigProvider.overrideWithValue(_config()),
        ],
      );
      addTearDown(container.dispose);

      final proposal = HttpOverrides.runZoned(
        () => container.read(
          tutorPracticePlanProposalProvider(const Duration(minutes: 10)),
        ),
        createHttpClient: probe.createHttpClient,
      );

      expect(probe.clientCreations, 0);
      expect(proposal.draft.source, PracticePlanSource.deterministicTemplate);
      expect(proposal.draft.blocks, hasLength(3));
      expect(
        const PracticePlanValidator()
            .validate(proposal.draft, context: proposal.validationContext)
            .isValid,
        isTrue,
      );
      expect(proposal.validationContext.songIds, isEmpty);
      expect(proposal.validationContext.availableSkillIds, isEmpty);
    });

    test('every supported template duration composes', () {
      final container = ProviderContainer(
        overrides: [
          ...preferenceOverrides(),
          appConfigProvider.overrideWithValue(_config()),
        ],
      );
      addTearDown(container.dispose);
      for (final minutes in const <int>[5, 10, 20, 30]) {
        final proposal = container.read(
          tutorPracticePlanProposalProvider(Duration(minutes: minutes)),
        );
        expect(proposal.draft.targetDuration, Duration(minutes: minutes));
        expect(
          const PracticePlanValidator()
              .validate(proposal.draft, context: proposal.validationContext)
              .isValid,
          isTrue,
          reason: '$minutes-minute template',
        );
      }
    });
  });

  group('Save — persists through the tutor memory repository', () {
    testWidgets('Save plan writes one inspectable fact and confirms it', (
      tester,
    ) async {
      _useTallSurface(tester);
      final store = InMemoryKeyValueStore();
      final container = await _pumpChat(tester, store: store);
      await _openPreviewFromAppBar(tester);

      await tester.tap(find.byKey(const ValueKey('plan-save')));
      await tester.pumpAndSettle();
      await _confirmSheet(tester);

      final facts = await container.read(tutorMemoryRepositoryProvider).list();
      final saved = facts.valueOrNull;
      expect(saved, isNotNull);
      expect(saved, hasLength(1));
      expect(saved!.single.content, contains('10-minute practice plan'));
      expect(saved.single.content, contains('warmup 2 min'));
      expect(find.text(l10nEn().tutorPlanSaved), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
