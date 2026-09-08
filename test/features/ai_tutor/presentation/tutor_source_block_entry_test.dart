// M13 (R33) — the tutor source block's ENTRY POINT into the source sheet.
//
// `showTutorSourceSheet` shipped with `tutor_source_sheet.dart` and then
// had ZERO `lib/**` callers: `tutor_message_bubble.dart` rendered a
// "<title> (<reference>)" line for every `TutorSourceBlock`, and tapping
// it did nothing. The citation was drawn and could not be inspected.
//
// Cells:
//   S1 — tapping the rendered source line opens the evidence sheet,
//   S2 — the sheet names THAT block's title and reference,
//   S3 — a bubble built WITHOUT `onSourceTap` (the widget's own tests and
//        the pixel-pinned `e13_r29_coach_chat_*` goldens' predecessor
//        shape) stays untappable — no gesture is added.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:strumsight/features/ai_tutor/presentation/widgets/tutor_message_bubble.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

import '../../../support/preference_store.dart';

AppLocalizations _l10n() => AppLocalizationsEn();

class _FakeController extends ChangeNotifier implements TutorChatController {
  _FakeController(List<TutorMessage> initialMessages) {
    _messages.addAll(initialMessages);
  }

  final List<TutorMessage> _messages = <TutorMessage>[];
  final StreamController<TutorChatState> _states =
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
  Stream<TutorChatState> get states => _states.stream;

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
  void setBanners(List<TutorBannerKind> value) {}

  Future<void> close() => _states.close();
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

TutorMessage _messageWithSource() => TutorMessage(
  id: TutorMessageId('t-1'),
  role: TutorMessageRole.tutor,
  createdAt: DateTime.utc(2026, 9, 8, 10),
  sequence: 0,
  deliveryState: TutorMessageDeliveryState.complete,
  blocks: <TutorContentBlock>[
    TutorTextBlock(text: 'Keep the down-strums even.'),
    TutorSourceBlock(title: 'Rhythm basics', reference: 'rhythm-basics#4'),
  ],
);

Future<void> _pumpChat(WidgetTester tester) async {
  final fake = _FakeController(<TutorMessage>[_messageWithSource()]);
  addTearDown(fake.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...preferenceOverrides(),
        appConfigProvider.overrideWithValue(_config()),
        tutorChatControllerProvider.overrideWithValue(fake),
      ],
      child: MaterialApp(
        theme: SsLightTheme.data(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const TutorChatScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('S1/S2 — tapping the source line opens its source sheet', (
    tester,
  ) async {
    await _pumpChat(tester);

    expect(find.text('Rhythm basics (rhythm-basics#4)'), findsOneWidget);
    expect(find.text(_l10n().aiTutorEvidenceDetailsTitle), findsNothing);

    await tester.tap(find.text('Rhythm basics (rhythm-basics#4)'));
    await tester.pumpAndSettle();

    expect(find.text(_l10n().aiTutorEvidenceDetailsTitle), findsOneWidget);
    expect(
      find.text(_l10n().aiTutorSourceTitle('Rhythm basics')),
      findsOneWidget,
    );
    expect(
      find.text(_l10n().aiTutorEvidenceReference('rhythm-basics#4')),
      findsOneWidget,
    );
  });

  testWidgets('S3 — a bubble without onSourceTap stays inert', (tester) async {
    // The default (what the bubble's own tests pass) must keep the old
    // behaviour exactly: the source line renders and does nothing.
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: TutorMessageBubble(message: _messageWithSource())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rhythm basics (rhythm-basics#4)'));
    await tester.pumpAndSettle();

    expect(find.text(_l10n().aiTutorEvidenceDetailsTitle), findsNothing);
  });
}
