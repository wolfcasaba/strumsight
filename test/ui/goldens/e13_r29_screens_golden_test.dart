// Golden snapshots of the E13-R29 Coach Home, Chat and Debrief (practice
// plan preview) screens at a compact portrait phone (412×915) and the same
// frame at textScaler 2.0, per the round brief §7/A9.
//
// `SsDarkTheme.data()` (E15-R09 §0.0.A/R4) — the app's ACTUAL runtime dark
// theme (`lib/app/strumsight_app.dart`), not `AppTheme.dark()`: since the
// E15-R09 design-system migration, `TutorChatScreen`'s AI-mode indicator and
// empty state (and `PracticePlanPreviewScreen`, already migrated) read the
// design-system theme extensions (`SsColorScheme`/`SsTypography`), which
// `AppTheme.dark()` never carried (it only ever added `AppPalette`) — this
// golden would have rendered a broken/fallback tree under the old theme.
// `TutorHomeScreen` deliberately still resolves via plain [Theme] tokens
// (see its own file doc comment) but renders identically under either theme
// choice, so switching the shared `_pump` theme is safe for it too.
//
// Recorded on x86_64 (ADR 0426, §0.0/B7) via `tools/golden-x86.sh record` —
// NOT `flutter test --update-goldens` on this (aarch64) box.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/themes/ss_dark_theme.dart';
import 'package:strumsight/features/ai_tutor/application/controller/tutor_state.dart';
import 'package:strumsight/features/ai_tutor/domain/models/practice_plan_block.dart';
import 'package:strumsight/features/ai_tutor/domain/models/practice_plan_draft.dart';
import 'package:strumsight/features/ai_tutor/domain/models/skill_node.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_content_block.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_ids.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_message.dart';
import 'package:strumsight/features/ai_tutor/domain/services/practice_plan_validator.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_providers.dart';
import 'package:strumsight/features/ai_tutor/presentation/screens/practice_plan_preview_screen.dart';
import 'package:strumsight/features/ai_tutor/presentation/screens/tutor_chat_screen.dart';
import 'package:strumsight/features/ai_tutor/presentation/screens/tutor_home_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

const _compactPortrait = Size(412, 915);

class _GoldenChatController extends ChangeNotifier
    implements TutorChatController {
  _GoldenChatController({
    List<TutorMessage> messages = const <TutorMessage>[],
  }) {
    _messages.addAll(messages);
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
}

TutorMessage _userMessage(String text) => TutorMessage(
  id: TutorMessageId('golden-u'),
  role: TutorMessageRole.user,
  createdAt: DateTime.utc(2026, 8, 5),
  sequence: 0,
  deliveryState: TutorMessageDeliveryState.complete,
  blocks: <TutorContentBlock>[TutorTextBlock(text: text)],
);

TutorMessage _tutorMessage(String text) => TutorMessage(
  id: TutorMessageId('golden-t'),
  role: TutorMessageRole.tutor,
  createdAt: DateTime.utc(2026, 8, 5, 0, 1),
  sequence: 1,
  deliveryState: TutorMessageDeliveryState.complete,
  blocks: <TutorContentBlock>[TutorTextBlock(text: text)],
);

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  List<Override> overrides = const <Override>[],
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = _compactPortrait;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: SsDarkTheme.data(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _expectGolden(WidgetTester tester, String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('goldens/$name.png'),
);

PracticePlanValidationContext _planValidationContext() =>
    PracticePlanValidationContext(
      songIds: const <String>{},
      practiceTargetIds: const <String>{},
      userAvoidList: const <String>{},
      activeTuning: const <String>[],
      capabilities: const <PracticePlanCapability>{},
      availableSkillIds: const <SkillId>{},
    );

PracticePlanDraft _planDraft() => PracticePlanDraft(
  id: 'golden-plan',
  title: 'Rhythm focus',
  targetDuration: const Duration(minutes: 10),
  blocks: <PracticePlanBlock>[
    PracticePlanBlock.basic(
      id: 'warmup',
      type: PracticePlanBlockType.warmup,
      duration: const Duration(minutes: 2),
    ),
    PracticePlanBlock.basic(
      id: 'rhythm',
      type: PracticePlanBlockType.rhythm,
      duration: const Duration(minutes: 8),
      tempoBpm: 92,
    ),
  ],
  goalIds: const <String>[],
  rationale: 'You have been rushing chord changes in the last two sessions.',
  source: PracticePlanSource.aiSuggestion,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final textScale in [1.0, 2.0]) {
    final suffix = textScale == 1.0 ? 'compact' : 'compact_scale2';

    testWidgets('coach home — $suffix', (tester) async {
      await _pump(
        tester,
        const TutorHomeScreen(),
        overrides: [
          tutorChatControllerProvider.overrideWithValue(
            _GoldenChatController(),
          ),
        ],
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r29_coach_home_$suffix');
    });

    testWidgets('coach chat — $suffix', (tester) async {
      await _pump(
        tester,
        const TutorChatScreen(),
        overrides: [
          tutorChatControllerProvider.overrideWithValue(
            _GoldenChatController(
              messages: <TutorMessage>[
                _userMessage('How do I fix my strumming timing?'),
                _tutorMessage(
                  'Try slowing the tempo by 20% and counting out loud on '
                  'every downbeat before speeding back up.',
                ),
              ],
            ),
          ),
        ],
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r29_coach_chat_$suffix');
    });

    testWidgets('practice plan preview (debrief) — $suffix', (tester) async {
      await _pump(
        tester,
        PracticePlanPreviewScreen(
          draft: _planDraft(),
          validationContext: _planValidationContext(),
        ),
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r29_practice_plan_preview_$suffix');
    });
  }
}
