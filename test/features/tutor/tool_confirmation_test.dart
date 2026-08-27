// E13-R29 §6 A2/A3/A6 — every tool action clears `SsToolConfirmationSheet`
// before it executes (ADR 0287 §1), the confirmation callback fires exactly
// once per confirmed proposal (§1/3), and a practice-plan modification shows
// as an explicit diff with accept/reject (§5.4).
//
// The three-cell matrix from brief §6.1 measures the EXECUTION count on the
// executor, not a widget type or key (§0.0/B4 — the service's
// `clientActionId` dedupe means a shallow, widget-shaped assertion stays
// green even behind a broken surface).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/ai_tutor/application/orchestration/action_confirmation_service.dart';
import 'package:strumsight/features/ai_tutor/application/orchestration/tutor_action_validator.dart';
import 'package:strumsight/features/ai_tutor/domain/models/practice_plan_block.dart';
import 'package:strumsight/features/ai_tutor/domain/models/practice_plan_draft.dart';
import 'package:strumsight/features/ai_tutor/domain/models/skill_node.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_action.dart';
import 'package:strumsight/features/ai_tutor/domain/services/practice_plan_validator.dart';
import 'package:strumsight/features/ai_tutor/presentation/screens/practice_plan_preview_screen.dart';
import 'package:strumsight/features/ai_tutor/presentation/widgets/tutor_action_card.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

AppLocalizations l10nEn() => AppLocalizationsEn();

class _RecordingExecutor implements TutorActionExecutor {
  final List<TutorAction> actions = <TutorAction>[];

  @override
  Future<void> execute(TutorAction action) async {
    actions.add(action);
  }
}

final _now = DateTime.utc(2026, 8, 5, 10);

TutorActionValidationContext _context() => TutorActionValidationContext(
  now: _now,
  availableCapabilities: const <TutorActionCapability>{
    TutorActionCapability.updateProfile,
  },
  activeSessionIds: const <String>{},
  songRevisions: const <String, TutorActionRevisionToken>{},
);

TutorProfileUpdateAction _proposal(String clientActionId) =>
    TutorProfileUpdateAction(
      metadata: TutorActionMetadata(
        source: TutorActionSource.modelSuggestion,
        expiresAt: _now.add(const Duration(hours: 1)),
        requiredCapability: TutorActionCapability.updateProfile,
        clientActionId: clientActionId,
      ),
      changes: const <String, Object?>{'preferredTempo': 96},
    );

Future<void> _pumpCard(
  WidgetTester tester, {
  required TutorActionProposal proposal,
  required ActionConfirmationService service,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: SsLightTheme.data(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: TutorToolConfirmationCard(
          proposal: proposal,
          confirmationService: service,
          validationContext: _context,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byType(SsCoachActionCard));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A2/A3 — the three-cell confirmation matrix', () {
    testWidgets('below threshold: cancelling the sheet runs nothing', (
      tester,
    ) async {
      final executor = _RecordingExecutor();
      final service = ActionConfirmationService(executor: executor);
      await _pumpCard(tester, proposal: _proposal('below-1'), service: service);

      await _openSheet(tester);
      expect(find.byType(SsToolConfirmationSheet), findsOneWidget);
      expect(
        executor.actions,
        isEmpty,
        reason: 'opening the sheet must not execute',
      );

      await tester.tap(
        find.byKey(const ValueKey('ss-tool-confirmation-cancel')),
      );
      await tester.pumpAndSettle();

      expect(executor.actions, isEmpty);
    });

    testWidgets('at threshold: one confirmation runs exactly one execution', (
      tester,
    ) async {
      final executor = _RecordingExecutor();
      final service = ActionConfirmationService(executor: executor);
      await _pumpCard(tester, proposal: _proposal('at-1'), service: service);

      await _openSheet(tester);
      await tester.tap(
        find.byKey(const ValueKey('ss-tool-confirmation-confirm')),
      );
      await tester.pumpAndSettle();

      expect(executor.actions, hasLength(1));
      expect(find.text(l10nEn().aiTutorActionConfirmed), findsOneWidget);
    });

    testWidgets(
      'above threshold: a repeated request with a NEW clientActionId needs its own confirmation',
      (tester) async {
        final executor = _RecordingExecutor();
        final service = ActionConfirmationService(executor: executor);

        await _pumpCard(
          tester,
          proposal: _proposal('above-1'),
          service: service,
        );
        await _openSheet(tester);
        await tester.tap(
          find.byKey(const ValueKey('ss-tool-confirmation-confirm')),
        );
        await tester.pumpAndSettle();
        expect(executor.actions, hasLength(1));

        // The model asks again — a fresh proposal with a fresh id. Nothing
        // has run yet just from re-proposing it.
        await _pumpCard(
          tester,
          proposal: _proposal('above-2'),
          service: service,
        );
        expect(
          executor.actions,
          hasLength(1),
          reason: 're-proposing must not silently re-run the previous action',
        );

        await _openSheet(tester);
        await tester.tap(
          find.byKey(const ValueKey('ss-tool-confirmation-confirm')),
        );
        await tester.pumpAndSettle();

        expect(
          executor.actions,
          hasLength(2),
          reason: 'the new id runs its own, independent confirmation',
        );
      },
    );
  });

  group('A6 — practice-plan changes are explicit, diff-first', () {
    PracticePlanValidationContext validationContext() =>
        PracticePlanValidationContext(
          songIds: const <String>{},
          practiceTargetIds: const <String>{},
          userAvoidList: const <String>{},
          activeTuning: const <String>[],
          capabilities: const <PracticePlanCapability>{},
          availableSkillIds: const <SkillId>{},
        );

    PracticePlanDraft draft() => PracticePlanDraft(
      id: 'plan-1',
      title: 'Rhythm focus',
      targetDuration: const Duration(minutes: 2),
      blocks: <PracticePlanBlock>[
        PracticePlanBlock.basic(
          id: 'warmup',
          type: PracticePlanBlockType.warmup,
          duration: const Duration(minutes: 2),
        ),
      ],
      goalIds: const <String>[],
      rationale: 'Measured timing evidence',
      source: PracticePlanSource.aiSuggestion,
    );

    Future<PracticePlanDraft?> pumpAndEdit(
      WidgetTester tester, {
      required void Function(PracticePlanDraft) onSave,
    }) async {
      PracticePlanDraft? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PracticePlanPreviewScreen(
            draft: draft(),
            validationContext: validationContext(),
            onSave: (value) {
              saved = value;
              onSave(value);
            },
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('plan-increase-warmup')));
      await tester.pump();
      return saved;
    }

    testWidgets(
      'saving opens a diff sheet and does not commit until confirmed',
      (tester) async {
        var saveCalls = 0;
        await pumpAndEdit(tester, onSave: (_) => saveCalls++);

        await tester.tap(find.byKey(const ValueKey('plan-save')));
        await tester.pumpAndSettle();

        expect(
          saveCalls,
          0,
          reason: 'tapping Save must open the sheet, not commit',
        );
        expect(find.byType(SsToolConfirmationSheet), findsOneWidget);
        expect(
          find.text(l10nEn().aiTutorPlanDiffChanged('Warm-up', 2, 3)),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('ss-tool-confirmation-confirm')),
        );
        await tester.pumpAndSettle();

        expect(saveCalls, 1);
      },
    );

    testWidgets('rejecting the diff sheet never commits the change', (
      tester,
    ) async {
      var saveCalls = 0;
      await pumpAndEdit(tester, onSave: (_) => saveCalls++);

      await tester.tap(find.byKey(const ValueKey('plan-save')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('ss-tool-confirmation-cancel')),
      );
      await tester.pumpAndSettle();

      expect(saveCalls, 0);
    });

    testWidgets(
      'an unmodified plan states "no changes" rather than a blank row',
      (tester) async {
        var saveCalls = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: PracticePlanPreviewScreen(
              draft: draft(),
              validationContext: validationContext(),
              onSave: (_) => saveCalls++,
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.byKey(const ValueKey('plan-save')));
        await tester.pumpAndSettle();

        expect(find.text(l10nEn().aiTutorPlanDiffNone), findsOneWidget);
        expect(saveCalls, 0);
      },
    );
  });
}
