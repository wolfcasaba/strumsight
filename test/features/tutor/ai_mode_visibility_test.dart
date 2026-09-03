// E13-R29 §6 A1/A8 — the AI-mode (local/cloud/fallback) is always visible on
// the Coach Home screen and in the Chat screen, in every turn status; and a
// completed tutor message with no measured evidence states that fact
// explicitly instead of omitting it.
//
// Pattern follows the pinned `test/features/ai_tutor/presentation/
// tutor_chat_screen_test.dart` / `tutor_home_screen_test.dart` fakes — this
// file cannot edit those (§0.0/B2), so it carries its own small
// `TutorChatController` fake rather than sharing one.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/features/ai_tutor/application/controller/tutor_state.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_content_block.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_ids.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_message.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_providers.dart';
import 'package:strumsight/features/ai_tutor/presentation/screens/tutor_chat_screen.dart';
import 'package:strumsight/features/ai_tutor/presentation/screens/tutor_home_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

AppLocalizations l10nEn() => AppLocalizationsEn();

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
  TutorTurnStatus status;
  @override
  String responseText;
  @override
  String draft = '';
  @override
  bool isOnline;
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

// `TutorHomeScreen` reads no provider (see its own file doc comment) — a
// themed `MaterialApp` (§0.0.A/R3: `SsLightTheme.data()`, matching the
// pinned `adaptive_scaffold_test.dart`'s theme) is enough, since this
// screen resolves design-system tokens straight from the ambient theme.
Future<void> _pumpHome(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: SsLightTheme.data(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const TutorHomeScreen(),
    ),
  );
  await tester.pump();
}

Future<void> _pumpChat(WidgetTester tester, _FakeController controller) async {
  addTearDown(controller.close);
  final container = ProviderContainer(
    overrides: <Override>[
      appConfigProvider.overrideWithValue(_config()),
      tutorChatControllerProvider.overrideWithValue(controller),
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
}

TutorMessage _tutorMessage({
  required String text,
  List<TutorContentBlock>? extraBlocks,
}) => TutorMessage(
  id: TutorMessageId('m-${text.hashCode}'),
  role: TutorMessageRole.tutor,
  createdAt: DateTime.utc(2026, 8, 5),
  sequence: 1,
  deliveryState: TutorMessageDeliveryState.complete,
  blocks: <TutorContentBlock>[
    TutorTextBlock(text: text),
    ...?extraBlocks,
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('A1 — Coach Home: AI mode always visible', () {
    // The Home surface has no active turn yet — it states the mode
    // production actually wires (`local`, `LocalTutorModelGatewayStub`;
    // `tutor_providers.dart`) unconditionally, never a Riverpod-read one
    // (see the file doc comment on `TutorHomeScreen`: a sibling pinned
    // test renders this screen with no tutor-provider override at all).
    testWidgets('the model status card is always present, never behind a tap', (
      tester,
    ) async {
      await _pumpHome(tester);
      expect(find.byKey(const Key('tutorHomeModelStatus')), findsOneWidget);
      expect(find.text(l10nEn().aiTutorAiModeLocalMessage), findsOneWidget);
      expect(find.text(l10nEn().dsProvenanceBadgeLocalLabel), findsOneWidget);
    });
  });

  group('A1 — Chat screen: AI mode always visible', () {
    testWidgets('visible while idle', (tester) async {
      await _pumpChat(tester, _FakeController());
      expect(find.text(l10nEn().dsProvenanceBadgeCloudLabel), findsOneWidget);
    });

    testWidgets('visible while streaming (message-level reinforcement)', (
      tester,
    ) async {
      await _pumpChat(
        tester,
        _FakeController(
          status: TutorTurnStatus.streaming,
          responseText: 'Try the low E string',
        ),
      );
      // One in the AppBar, one alongside the streaming indicator.
      expect(find.text(l10nEn().dsProvenanceBadgeCloudLabel), findsNWidgets(2));
    });

    testWidgets('visible even when an error banner is showing', (tester) async {
      await _pumpChat(
        tester,
        _FakeController(
          status: TutorTurnStatus.failed,
          banners: const <TutorBannerKind>[TutorBannerKind.error],
        ),
      );
      expect(find.text(l10nEn().dsProvenanceBadgeCloudLabel), findsOneWidget);
    });

    testWidgets('offline switches the label to local, not hidden', (
      tester,
    ) async {
      await _pumpChat(
        tester,
        _FakeController(
          isOnline: false,
          banners: const <TutorBannerKind>[TutorBannerKind.offline],
        ),
      );
      expect(find.text(l10nEn().dsProvenanceBadgeLocalLabel), findsOneWidget);
    });
  });

  group('A8 — missing evidence is stated, not silently omitted', () {
    testWidgets('a plain completed tutor reply states it has no evidence', (
      tester,
    ) async {
      await _pumpChat(
        tester,
        _FakeController(
          initialMessages: <TutorMessage>[
            _tutorMessage(text: 'Try tuning the low E string down a touch.'),
          ],
        ),
      );
      expect(find.text(l10nEn().aiTutorEvidenceMissingNotice), findsOneWidget);
    });

    testWidgets(
      'a reply backed by a measured source does not claim missing evidence',
      (tester) async {
        await _pumpChat(
          tester,
          _FakeController(
            initialMessages: <TutorMessage>[
              _tutorMessage(
                text: 'Your last session averaged 92 BPM.',
                extraBlocks: <TutorContentBlock>[
                  TutorSourceBlock(
                    title: 'Session log',
                    reference: 'session-42',
                  ),
                ],
              ),
            ],
          ),
        );
        expect(find.text(l10nEn().aiTutorEvidenceMissingNotice), findsNothing);
      },
    );

    testWidgets('a still-streaming reply does not claim missing evidence yet', (
      tester,
    ) async {
      await _pumpChat(
        tester,
        _FakeController(
          status: TutorTurnStatus.streaming,
          responseText: 'Thinking',
        ),
      );
      expect(find.text(l10nEn().aiTutorEvidenceMissingNotice), findsNothing);
    });
  });
}
