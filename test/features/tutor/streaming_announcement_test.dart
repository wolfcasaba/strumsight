// E13-R29 §6 A5 — the streaming screen-reader announcement is consolidated,
// not token-by-token (ADR 0280 §2, ADR 0287 §5). The mátrix (§6.1) names the
// failure mode directly: "token-szintű felolvasás streaming közben" turns
// this cell red. The defence already lives in `tutor_chat_screen.dart` — a
// single `Semantics(label: ..., liveRegion: true)` whose label is the
// constant "Generating response" string, never the growing response text —
// this file is the round's own gate proof for it.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/features/ai_tutor/application/controller/tutor_state.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_message.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_providers.dart';
import 'package:strumsight/features/ai_tutor/presentation/screens/tutor_chat_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

AppLocalizations l10nEn() => AppLocalizationsEn();

Finder _liveRegionWithLabel(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.liveRegion == true &&
      widget.properties.label == label,
  description: 'live-region Semantics with label "$label"',
);

class _FakeController extends ChangeNotifier implements TutorChatController {
  _FakeController({this.status = TutorTurnStatus.idle, this.responseText = ''});

  final List<TutorMessage> _messages = <TutorMessage>[];
  final StreamController<TutorChatState> _statesController =
      StreamController<TutorChatState>.broadcast();

  @override
  List<TutorMessage> get messages => List<TutorMessage>.unmodifiable(_messages);
  @override
  TutorTurnStatus status;
  @override
  String responseText;
  @override
  String draft = '';
  @override
  bool isOnline = true;
  @override
  List<TutorBannerKind> banners = const <TutorBannerKind>[];
  @override
  Stream<TutorChatState> get states => _statesController.stream;

  void emit() {
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
  void setDraft(String value) {}
  @override
  void send() {}
  @override
  void cancel() {}
  @override
  void retry() {}
  @override
  void setOnline(bool value) {}
  @override
  void setBanners(List<TutorBannerKind> value) {
    banners = List<TutorBannerKind>.unmodifiable(value);
    emit();
  }

  Future<void> close() => _statesController.close();
}

AppConfig _config() => AppConfig.resolve(
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
);

Future<_FakeController> _pump(WidgetTester tester) async {
  final fake = _FakeController(
    status: TutorTurnStatus.streaming,
    responseText: 'T',
  );
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
  return fake;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'A5: dozens of token deltas still produce exactly one live-region node',
    (tester) async {
      final fake = await _pump(tester);
      final label = l10nEn().aiTutorChatStreamingSemantics;

      final tokens = <String>[
        'Try ',
        'tuning ',
        'the ',
        'low ',
        'E ',
        'string ',
        'down ',
        'a ',
        'touch ',
        'and ',
        'check ',
        'again.',
      ];
      var accumulated = '';
      for (final token in tokens) {
        accumulated += token;
        fake.responseText = accumulated;
        fake.emit();
        await tester.pump();
        // The live region never multiplies with each delta, and its own
        // label text is never the growing content — a screen reader that
        // re-announces on `label` change would otherwise re-speak the
        // whole message on every token.
        expect(
          _liveRegionWithLabel(label),
          findsOneWidget,
          reason: 'after "$token"',
        );
        expect(find.text(accumulated), findsOneWidget);
      }
    },
  );

  testWidgets(
    'A5: the announcement label text never equals the streamed content',
    (tester) async {
      final fake = await _pump(tester);
      fake.responseText = 'Some fairly long streamed sentence fragment';
      fake.emit();
      await tester.pump();

      final label = l10nEn().aiTutorChatStreamingSemantics;
      expect(label, isNot(contains('streamed sentence')));
      expect(_liveRegionWithLabel(label), findsOneWidget);
    },
  );

  testWidgets('A5: the live region disappears once the turn completes', (
    tester,
  ) async {
    final fake = await _pump(tester);
    final label = l10nEn().aiTutorChatStreamingSemantics;
    expect(_liveRegionWithLabel(label), findsOneWidget);

    fake.status = TutorTurnStatus.completed;
    fake.emit();
    await tester.pump();

    expect(_liveRegionWithLabel(label), findsNothing);
  });
}
