import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/domain/models/practice_plan_block.dart';
import 'package:strumsight/features/ai_tutor/domain/models/practice_plan_draft.dart';
import 'package:strumsight/features/ai_tutor/domain/models/skill_node.dart';
import 'package:strumsight/features/ai_tutor/domain/services/practice_plan_validator.dart';
import 'package:strumsight/features/ai_tutor/presentation/screens/practice_plan_preview_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

AppLocalizations _l10n() => AppLocalizationsEn();

PracticePlanValidationContext _context() => PracticePlanValidationContext(
  songIds: const <String>{},
  practiceTargetIds: const <String>{},
  userAvoidList: const <String>{},
  activeTuning: const <String>[],
  capabilities: const <PracticePlanCapability>{},
  availableSkillIds: const <SkillId>{},
);

PracticePlanDraft _draft({bool invalid = false}) => PracticePlanDraft(
  id: 'plan-1',
  title: '<b>Rhythm focus</b>',
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
      tempoBpm: invalid ? 301 : 80,
    ),
  ],
  goalIds: const <String>[],
  rationale: 'Measured timing evidence',
  source: PracticePlanSource.aiSuggestion,
);

Future<void> _pump(
  WidgetTester tester, {
  PracticePlanDraft? draft,
  ValueChanged<PracticePlanDraft>? onChanged,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: PracticePlanPreviewScreen(
          draft: draft ?? _draft(),
          validationContext: _context(),
          onDraftChanged: onChanged,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('plan preview shows localized structure and exact total', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.textContaining('Rhythm focus'), findsOneWidget);
    expect(find.text(_l10n().aiTutorPlanTotalDuration(10)), findsOneWidget);
    expect(
      find.text(
        _l10n().aiTutorPlanBlockSummary(_l10n().aiTutorPlanBlockWarmup, 2),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        _l10n().aiTutorPlanBlockSummary(_l10n().aiTutorPlanBlockRhythm, 8),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('<b>'), findsNothing);
  });

  testWidgets('editing a block uses copyWith and marks the draft user edited', (
    tester,
  ) async {
    PracticePlanDraft? changed;
    await _pump(tester, onChanged: (value) => changed = value);

    await tester.tap(find.byKey(const ValueKey('plan-increase-rhythm')));
    await tester.pump();

    expect(changed, isNotNull);
    expect(changed!.source, PracticePlanSource.userEdited);
    expect(changed!.blocks.last.duration, const Duration(minutes: 9));
    expect(changed!.targetDuration, const Duration(minutes: 11));
  });

  testWidgets(
    'plan edit can remove a block and exposes save and start actions',
    (tester) async {
      PracticePlanDraft? changed;
      await _pump(tester, onChanged: (value) => changed = value);

      await tester.tap(find.byKey(const ValueKey('plan-delete-warmup')));
      await tester.pump();

      expect(changed!.source, PracticePlanSource.userEdited);
      expect(changed!.blocks, hasLength(1));
      expect(find.byKey(const ValueKey('plan-save')), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-start')), findsOneWidget);
    },
  );

  testWidgets('invalid plan displays validation warning and disables actions', (
    tester,
  ) async {
    await _pump(tester, draft: _draft(invalid: true));

    expect(find.text(_l10n().aiTutorPlanInvalid), findsOneWidget);
    expect(find.textContaining(_l10n().aiTutorPlanIssueTempo), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(find.byKey(const ValueKey('plan-save')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<ButtonStyleButton>(find.byKey(const ValueKey('plan-start')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('large text keeps plan controls and semantics visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pump(tester, textScale: 3);

    expect(find.byKey(const ValueKey('plan-increase-rhythm')), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-delete-warmup')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == _l10n().aiTutorPlanSemantics,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
