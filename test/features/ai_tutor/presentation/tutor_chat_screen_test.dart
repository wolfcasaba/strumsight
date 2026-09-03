// E04-R18 §6 — Tutor Chat screen matrix.
//
// The chat screen is the most behavior-dense surface in this round: every
// state in TutorTurnStatus (idle, streaming, completed, fallback,
// consentRevoked, usageLimit, failed, cancelled) plus four banners
// (offline, consent, rate-limit, error) plus a11y (semantics, locale,
// scroll-anchoring) plus raw-block safety. The widget tests drive every
// cell against a fake controller and a ProviderScope that overrides
// `tutorChatControllerProvider`.
//
// RED-first: this file is written BEFORE the presentation package exists.
// It compiles only after `tutor_providers.dart`, `tutor_chat_screen.dart`,
// `tutor_composer.dart`, `tutor_message_bubble.dart` and
// `tutor_banners.dart` land with the exact public names referenced below.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/design_system/components/ai/ss_provenance_badge.dart';
import 'package:strumsight/core/design_system/components/feedback/ss_skeleton.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/features/ai_tutor/application/controller/tutor_state.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_content_block.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_ids.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_message.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_providers.dart';
import 'package:strumsight/features/ai_tutor/presentation/screens/tutor_chat_screen.dart';
import 'package:strumsight/features/ai_tutor/presentation/widgets/tutor_banners.dart';
import 'package:strumsight/features/ai_tutor/presentation/widgets/tutor_composer.dart';
import 'package:strumsight/features/ai_tutor/presentation/widgets/tutor_message_bubble.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';
import 'package:strumsight/l10n/app_localizations_hu.dart';

import '../../../support/preference_store.dart';

AppLocalizations l10nEn() => AppLocalizationsEn();
AppLocalizations l10nHu() => AppLocalizationsHu();

/// Matches the `Semantics` widget wrapping a banner / streaming indicator
/// with the given label — a semantics-label equivalent that doesn't
/// require `ensureSemantics` (which would leave an active handle at
/// end-of-test).
Finder _semanticsWithLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
  description: 'Semantics with label "$label"',
);

// ---------------------------------------------------------------------------
// Fake controller — overrides `tutorChatControllerProvider` in every test.
// Each test wires its own callbacks for `onSend`, `onCancel`, `onRetry` so
// we can assert the screens dispatch the right action without spinning the
// real orchestrator.
// ---------------------------------------------------------------------------
class _FakeController extends ChangeNotifier implements TutorChatController {
  _FakeController({
    List<TutorMessage> initialMessages = const <TutorMessage>[],
    this.status = TutorTurnStatus.idle,
    this.responseText = '',
    List<TutorBannerKind> banners = const <TutorBannerKind>[],
    this.isOnline = true,
  }) {
    _messages.addAll(initialMessages);
    this.banners = List<TutorBannerKind>.unmodifiable(banners);
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
  bool isOnline = true;

  @override
  List<TutorBannerKind> banners = const <TutorBannerKind>[];

  @override
  Stream<TutorChatState> get states => _statesController.stream;

  int sendCalls = 0;
  int cancelCalls = 0;
  int retryCalls = 0;

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

  void addMessage(TutorMessage message) {
    _messages.add(message);
    _emit();
  }

  @override
  void setDraft(String value) {
    draft = value;
    _emit();
  }

  @override
  void send() {
    sendCalls++;
    status = TutorTurnStatus.streaming;
    _emit();
  }

  @override
  void cancel() {
    cancelCalls++;
    status = TutorTurnStatus.cancelled;
    _emit();
  }

  @override
  void retry() {
    retryCalls++;
    status = TutorTurnStatus.streaming;
    _emit();
  }

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

  Future<void> close() async {
    await _statesController.close();
  }
}

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

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  _FakeController? controller,
  Locale locale = const Locale('en'),
  AppConfig? config,
}) async {
  final fake = controller ?? _FakeController();
  addTearDown(fake.close);
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      appConfigProvider.overrideWithValue(config ?? _config()),
      tutorChatControllerProvider.overrideWithValue(fake),
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
        home: const TutorChatScreen(),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('R18-A1: empty chat renders the empty-state prompt', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.byType(TutorChatScreen), findsOneWidget);
    expect(find.byType(TutorComposer), findsOneWidget);
    expect(find.text(l10nEn().aiTutorChatEmptyTitle), findsOneWidget);
    expect(find.text(l10nEn().aiTutorChatEmptyBody), findsOneWidget);
  });

  testWidgets(
    'R18-A2: typing then send fires controller.send and clears the draft',
    (tester) async {
      final fake = _FakeController();
      await _pump(tester, controller: fake);

      final textField = find.byType(TextField);
      await tester.enterText(textField, 'How do I tune my guitar?');
      await tester.pump();
      expect(fake.draft, 'How do I tune my guitar?');

      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      expect(fake.sendCalls, 1, reason: 'send must fire exactly once.');
    },
  );

  testWidgets(
    'R18-A3: streaming updates the bubble text and shows the typing indicator',
    (tester) async {
      final fake = _FakeController(
        status: TutorTurnStatus.streaming,
        responseText: 'Try tuning the low E string',
      );
      await _pump(tester, controller: fake);

      expect(find.text('Try tuning the low E string'), findsOneWidget);

      fake
        ..responseText = 'Try tuning the low E string first.'
        ..status = TutorTurnStatus.streaming;
      fake.setBanners(fake.banners);
      await tester.pump();

      expect(find.text('Try tuning the low E string first.'), findsOneWidget);
      expect(
        _semanticsWithLabel(l10nEn().aiTutorChatStreamingSemantics),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'R18-A4: cancel fires the controller and shows the cancelled banner',
    (tester) async {
      final fake = _FakeController(status: TutorTurnStatus.streaming);
      await _pump(tester, controller: fake);
      await tester.pump();

      await tester.tap(find.text(l10nEn().aiTutorChatCancel));
      await tester.pump();

      expect(fake.cancelCalls, 1);
      fake.setBanners(const [TutorBannerKind.cancelled]);
      await tester.pump();

      expect(
        _semanticsWithLabel(l10nEn().aiTutorBannerCancelledSemantics),
        findsOneWidget,
      );
    },
  );

  testWidgets('R18-A5: retry after a failed turn fires controller.retry', (
    tester,
  ) async {
    final fake = _FakeController(
      status: TutorTurnStatus.failed,
      banners: const [TutorBannerKind.error],
    );
    await _pump(tester, controller: fake);

    await tester.tap(find.text(l10nEn().aiTutorChatRetry));
    await tester.pump();
    expect(fake.retryCalls, 1);
  });

  testWidgets('R18-A6: offline banner shows the offline-specific label', (
    tester,
  ) async {
    final fake = _FakeController(
      banners: const [TutorBannerKind.offline],
      isOnline: false,
    );
    await _pump(tester, controller: fake);

    expect(
      _semanticsWithLabel(l10nEn().aiTutorBannerOfflineSemantics),
      findsOneWidget,
    );
  });

  testWidgets('R18-A7: consent banner shows the consent-specific label', (
    tester,
  ) async {
    final fake = _FakeController(banners: const [TutorBannerKind.consent]);
    await _pump(tester, controller: fake);

    expect(
      _semanticsWithLabel(l10nEn().aiTutorBannerConsentSemantics),
      findsOneWidget,
    );
  });

  testWidgets('R18-A8: each banner kind renders a distinct semantics label', (
    tester,
  ) async {
    final labels = <String>{
      l10nEn().aiTutorBannerOfflineSemantics,
      l10nEn().aiTutorBannerConsentSemantics,
      l10nEn().aiTutorBannerRateLimitSemantics,
      l10nEn().aiTutorBannerErrorSemantics,
    };
    expect(
      labels.length,
      4,
      reason: 'The four banner kinds MUST render four distinct labels.',
    );

    for (final kind in TutorBannerKind.values) {
      final fake = _FakeController(banners: [kind]);
      await _pump(tester, controller: fake);
      expect(find.byType(TutorBanner), findsOneWidget, reason: 'kind=$kind');
    }
  });

  testWidgets('R18-A9: rate-limit banner shows the rate-limit label', (
    tester,
  ) async {
    final fake = _FakeController(banners: const [TutorBannerKind.rateLimit]);
    await _pump(tester, controller: fake);

    expect(
      _semanticsWithLabel(l10nEn().aiTutorBannerRateLimitSemantics),
      findsOneWidget,
    );
  });

  testWidgets('R18-A10: error banner shows the error-specific label', (
    tester,
  ) async {
    final fake = _FakeController(banners: const [TutorBannerKind.error]);
    await _pump(tester, controller: fake);

    expect(
      _semanticsWithLabel(l10nEn().aiTutorBannerErrorSemantics),
      findsOneWidget,
    );
  });

  testWidgets(
    'R18-A11: unknown content block renders safely as monospaced text',
    (tester) async {
      final rawJson = <String, Object?>{
        'type': 'futureBlock',
        'payload': '<script>alert(1)</script>',
      };
      final unknown = TutorUnknownContentBlock(
        originalType: 'futureBlock',
        rawJson: rawJson,
      );
      final message = TutorMessage(
        id: TutorMessageId('m-1'),
        role: TutorMessageRole.tutor,
        createdAt: DateTime.utc(2026, 8, 5),
        sequence: 1,
        deliveryState: TutorMessageDeliveryState.complete,
        blocks: <TutorContentBlock>[unknown],
      );
      final fake = _FakeController(initialMessages: [message]);
      await _pump(tester, controller: fake);

      expect(find.byType(TutorMessageBubble), findsOneWidget);
      expect(find.textContaining('<script>alert(1)</script>'), findsOneWidget);
    },
  );

  testWidgets('R18-A12: long user message scrolls but keeps the composer', (
    tester,
  ) async {
    final longText = List<String>.filled(50, 'chord').join(' ');
    final user = TutorMessage(
      id: TutorMessageId('m-u'),
      role: TutorMessageRole.user,
      createdAt: DateTime.utc(2026, 8, 5),
      sequence: 0,
      deliveryState: TutorMessageDeliveryState.complete,
      blocks: <TutorContentBlock>[TutorTextBlock(text: longText)],
    );
    final fake = _FakeController(initialMessages: [user]);
    await _pump(tester, controller: fake);

    expect(find.byType(TutorMessageBubble), findsOneWidget);
    expect(find.textContaining('chord chord chord'), findsOneWidget);
    expect(find.byType(TutorComposer), findsOneWidget);
    expect(find.byType(Scrollable), findsWidgets);
  });

  testWidgets(
    'R18-A13: appending a new tutor message keeps the latest bubble visible',
    (tester) async {
      final earlier = TutorMessage(
        id: TutorMessageId('m-1'),
        role: TutorMessageRole.tutor,
        createdAt: DateTime.utc(2026, 8, 5),
        sequence: 1,
        deliveryState: TutorMessageDeliveryState.complete,
        blocks: <TutorContentBlock>[TutorTextBlock(text: 'Earlier answer.')],
      );
      final fake = _FakeController(initialMessages: [earlier]);
      await _pump(tester, controller: fake);

      final latest = TutorMessage(
        id: TutorMessageId('m-2'),
        role: TutorMessageRole.tutor,
        createdAt: DateTime.utc(2026, 8, 5, 0, 5),
        sequence: 2,
        deliveryState: TutorMessageDeliveryState.complete,
        blocks: <TutorContentBlock>[TutorTextBlock(text: 'Latest answer.')],
      );
      fake.addMessage(latest);
      await tester.pump();

      expect(find.text('Latest answer.'), findsOneWidget);
    },
  );

  testWidgets('R18-A14: chat surface exposes a screen-level semantics label', (
    tester,
  ) async {
    await _pump(tester);

    expect(
      _semanticsWithLabel(l10nEn().aiTutorChatScreenSemantics),
      findsOneWidget,
    );
  });

  testWidgets('R18-A15: hu locale renders Hungarian strings', (tester) async {
    await _pump(tester, locale: const Locale('hu'));

    expect(find.text(l10nHu().aiTutorChatEmptyTitle), findsOneWidget);
    expect(find.text(l10nHu().aiTutorChatEmptyBody), findsOneWidget);
  });

  testWidgets('R18-A16: streaming batches the screen-reader announcement', (
    tester,
  ) async {
    final fake = _FakeController(
      status: TutorTurnStatus.streaming,
      responseText: 'T',
    );
    await _pump(tester, controller: fake);

    for (final piece in const ['Try ', 'tuning ', 'the ', 'low E']) {
      fake.responseText = piece;
      fake.setBanners(fake.banners);
      await tester.pump();
    }

    expect(
      _semanticsWithLabel(l10nEn().aiTutorChatStreamingSemantics),
      findsOneWidget,
    );
  });

  // -------------------------------------------------------------------
  // E15-R09 §0.0.B/R15 — per-screen design-system type assertions, so
  // §6.1's first row can go red on THIS screen too, not only on the data
  // screen. A raw `CircularProgressIndicator` regression on the streaming
  // indicator, or a raw badge Row instead of `SsProvenanceBadge`, must
  // fail one of these two cells.
  // -------------------------------------------------------------------
  testWidgets(
    'R18-A17: streaming indicator is the design-system SsSkeleton, not a raw spinner',
    (tester) async {
      final fake = _FakeController(
        status: TutorTurnStatus.streaming,
        responseText: 'Try tuning the low E string',
      );
      await _pump(tester, controller: fake);

      expect(find.byType(SsSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'R18-A18: the AI-mode indicator is the design-system SsProvenanceBadge',
    (tester) async {
      await _pump(tester);

      expect(find.byType(SsProvenanceBadge), findsOneWidget);
    },
  );

  // -------------------------------------------------------------------
  // E15-R09 §0.0.B/R14 — committed textScaler 2.0 coverage (en + hu), on
  // the phone viewport the golden lane uses (412x915). Pumps the
  // fallback AI-mode + streaming state together: the longest-text path
  // on this screen (fallback trailing message + streaming pill + a
  // real message bubble).
  // -------------------------------------------------------------------
  for (final locale in const [Locale('en'), Locale('hu')]) {
    testWidgets(
      'R18-A19: textScaler 2.0, locale=${locale.languageCode} — no overflow',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final earlier = TutorMessage(
          id: TutorMessageId('m-1'),
          role: TutorMessageRole.tutor,
          createdAt: DateTime.utc(2026, 8, 5),
          sequence: 1,
          deliveryState: TutorMessageDeliveryState.complete,
          blocks: <TutorContentBlock>[
            TutorTextBlock(text: 'Try tuning the low E string first.'),
          ],
        );
        final fake = _FakeController(
          initialMessages: [earlier],
          status: TutorTurnStatus.fallback,
          responseText: 'Try tuning the low E string',
        );
        await _pump(tester, controller: fake, locale: locale);

        expect(tester.takeException(), isNull);
      },
    );
  }
}
