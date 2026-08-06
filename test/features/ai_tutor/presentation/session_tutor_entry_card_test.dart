import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/application/context/context_purpose.dart';
import 'package:strumsight/features/ai_tutor/application/context/redaction_report.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_snapshot.dart';
import 'package:strumsight/features/ai_tutor/presentation/widgets/session_tutor_entry_card.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

AppLocalizations _l10n() => AppLocalizationsEn();

final _snapshot = TutorContextSnapshot(
  requestId: 'session-request-1',
  createdAt: DateTime.utc(2026, 8, 6),
  purpose: ContextPurpose.sessionDebrief,
  fields: <TutorContextField>[
    TutorContextField.available(
      key: TutorContextFieldKey.practice,
      values: const <String, Object?>{'resultId': 'practice-result-1'},
      provenance: ContextProvenance(
        sourceFeature: ContextSourceFeature.practice,
        schemaVersion: 'practice-result.v1',
      ),
    ),
  ],
  redactionReport: RedactionReport.empty(),
);

Future<void> _pump(
  WidgetTester tester, {
  required SessionTutorEntryAvailability availability,
  TutorContextSnapshot? snapshot,
  ValueChanged<SessionTutorEntryRequest>? onOpenTutor,
  VoidCallback? onOpenDeterministicDebrief,
  VoidCallback? onStartSuggestedPractice,
}) => tester.pumpWidget(
  MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SessionTutorEntryCard(
        availability: availability,
        contextSnapshot: snapshot,
        prefilledQuestion: 'What should I focus on next?',
        onOpenTutor: onOpenTutor,
        onOpenDeterministicDebrief: onOpenDeterministicDebrief,
        onStartSuggestedPractice: onStartSuggestedPractice,
      ),
    ),
  ),
);

void main() {
  testWidgets('opens chat with the same snapshot and an editable question', (
    tester,
  ) async {
    SessionTutorEntryRequest? request;
    await _pump(
      tester,
      availability: SessionTutorEntryAvailability.available,
      snapshot: _snapshot,
      onOpenTutor: (next) => request = next,
    );

    await tester.enterText(
      find.byKey(const ValueKey('session-tutor-question')),
      'Help me work on rhythm.',
    );
    await tester.tap(find.byKey(const ValueKey('session-tutor-open')));

    expect(identical(request!.contextSnapshot, _snapshot), isTrue);
    expect(request!.prefilledQuestion, 'Help me work on rhythm.');
  });

  testWidgets('uses deterministic debrief when cloud consent is unavailable', (
    tester,
  ) async {
    var debriefOpenCount = 0;
    await _pump(
      tester,
      availability: SessionTutorEntryAvailability.deterministicFallback,
      snapshot: _snapshot,
      onOpenDeterministicDebrief: () => debriefOpenCount++,
    );

    expect(
      find.text(_l10n().aiTutorSessionDeterministicDebrief),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('session-tutor-open')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('session-tutor-deterministic')));
    expect(debriefOpenCount, 1);
  });

  testWidgets('shows controlled deleted and version-mismatch states', (
    tester,
  ) async {
    await _pump(
      tester,
      availability: SessionTutorEntryAvailability.deletedResult,
    );
    expect(find.text(_l10n().aiTutorSessionDeletedResult), findsOneWidget);

    await _pump(
      tester,
      availability: SessionTutorEntryAvailability.versionMismatch,
    );
    expect(find.text(_l10n().aiTutorSessionVersionMismatch), findsOneWidget);
  });

  testWidgets('chat entry does not change streak or start suggested practice', (
    tester,
  ) async {
    var streak = 7;
    var suggestedPracticeStarts = 0;
    await _pump(
      tester,
      availability: SessionTutorEntryAvailability.available,
      snapshot: _snapshot,
      onOpenTutor: (_) {},
      onStartSuggestedPractice: () => suggestedPracticeStarts++,
    );

    await tester.tap(find.byKey(const ValueKey('session-tutor-open')));
    expect(streak, 7);
    expect(suggestedPracticeStarts, 0);

    await tester.tap(find.byKey(const ValueKey('session-tutor-practice')));
    expect(streak, 7);
    expect(suggestedPracticeStarts, 1);
  });

  test('entry card cannot mutate practice streaks itself', () {
    final source = File(
      'lib/features/ai_tutor/presentation/widgets/session_tutor_entry_card.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('recordPracticeToday')));
  });
}
