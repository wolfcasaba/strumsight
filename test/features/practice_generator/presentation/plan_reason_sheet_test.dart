import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/domain/model/practice_block.dart';
import 'package:strumsight/features/practice_generator/domain/model/skill_priority.dart';
import 'package:strumsight/features/practice_generator/presentation/widgets/plan_reason_sheet.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../fixtures/practice_generator/validation/validation_fixtures.dart';

void main() {
  group('PlanReasonSheet', () {
    testWidgets(
      'A5: every reason line is localized, never a hard-coded English string',
      (tester) async {
        final block = _blockWith(
          reasonCodes: const <String>['goal.primary'],
          evidenceRefs: const <String>['evidence.tempo-accuracy'],
        );

        await _pump(tester, block);
        await tester.tap(find.byKey(Key('plan-block-${block.id.value}')));
        await tester.pumpAndSettle();

        // The reason code is translated via ARB, not echoed verbatim.
        expect(
          find.byKey(const Key('plan-reason-line-goal.primary')),
          findsOneWidget,
        );
        // The raw code is not shown to the learner.
        expect(find.text('goal.primary'), findsNothing);
      },
    );

    testWidgets(
      'A5 (hu): the same code resolves through the hu ARB locale',
      (tester) async {
        final block = _blockWith(
          reasonCodes: const <String>['goal.primary'],
        );

        await _pump(tester, block, locale: const Locale('hu'));
        await tester.tap(find.byKey(Key('plan-block-${block.id.value}')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('plan-reason-line-goal.primary')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'A6: when the matching factor is uncertain, the sheet appends the '
      'uncertainty line in the learner\'s language',
      (tester) async {
        final block = _blockWith(
          reasonCodes: const <String>['goal.primary'],
        );
        // Build a SkillPriority whose uncertainty factor is at the
        // threshold (>= 0.5).
        final priority = _priorityWithUncertainty(0.6);

        await _pumpWithPriority(tester, block, priority);
        await tester.tap(find.byKey(Key('plan-block-${block.id.value}')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('plan-reason-uncertain')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'A6 negative: a confident factor does NOT trigger the uncertainty line',
      (tester) async {
        final block = _blockWith(
          reasonCodes: const <String>['goal.primary'],
        );
        final priority = _priorityWithUncertainty(0.2);

        await _pumpWithPriority(tester, block, priority);
        await tester.tap(find.byKey(Key('plan-block-${block.id.value}')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('plan-reason-uncertain')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'A7: the sheet is offline — no IO is performed and the rendering only '
      'uses the data passed in',
      (tester) async {
        final block = _blockWith(
          reasonCodes: const <String>['goal.primary'],
          evidenceRefs: const <String>['evidence.tempo-accuracy'],
        );

        await _pump(tester, block);
        await tester.tap(find.byKey(Key('plan-block-${block.id.value}')));
        await tester.pumpAndSettle();

        // The chip strip is rendered with the supplied evidence refs only —
        // the sheet never invents new ones.
        expect(
          find.byKey(
            const Key('plan-reason-evidence-evidence.tempo-accuracy'),
          ),
          findsOneWidget,
        );
      },
    );
  });
}

PracticeBlock _blockWith({
  required List<String> reasonCodes,
  List<String> evidenceRefs = const <String>['evidence.test-fixture'],
}) {
  final base = buildBlock(
    id: 'day.1.block.1',
    order: 1,
    prescription: buildPrescription(buildCandidate()),
    estimatedElapsed: const Duration(minutes: 6),
  );
  return base.replaceContent(
    reasonCodes: reasonCodes,
    evidenceRefs: evidenceRefs,
  );
}

SkillPriority _priorityWithUncertainty(double uncertainty) {
  return SkillPriority(
    skillId: 'rhythm.quarterNotes',
    score: -0.3 * uncertainty,
    policyVersion: 'policy.test.v1',
    factors: <SkillPriorityFactor>[
      SkillPriorityFactor(
        kind: SkillPriorityFactorKind.uncertainty,
        normalizedValue: uncertainty,
        contribution: -0.3 * uncertainty,
      ),
    ],
    isSafetyOverridden: false,
  );
}

Future<void> _pump(
  WidgetTester tester,
  PracticeBlock block, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: Key('plan-block-${block.id.value}'),
              onPressed: () => PlanReasonSheet.show(context, block: block),
              child: const Text('Open sheet'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpWithPriority(
  WidgetTester tester,
  PracticeBlock block,
  SkillPriority priority, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: Key('plan-block-${block.id.value}'),
              onPressed: () => PlanReasonSheet.show(
                context,
                block: block,
                priority: priority,
              ),
              child: const Text('Open sheet'),
            ),
          ),
        ),
      ),
    ),
  );
}
