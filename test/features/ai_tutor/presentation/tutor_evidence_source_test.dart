import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/domain/models/debrief_fact.dart';
import 'package:strumsight/features/ai_tutor/domain/models/student_profile.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_source_ref.dart';
import 'package:strumsight/features/ai_tutor/presentation/widgets/tutor_evidence_chip.dart';
import 'package:strumsight/features/ai_tutor/presentation/widgets/tutor_source_sheet.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

AppLocalizations _l10n() => AppLocalizationsEn();

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final matrix =
      <(TutorEvidenceKind, String, IconData, Color Function(ColorScheme))>[
        (
          TutorEvidenceKind.measured,
          'measured',
          Icons.analytics_outlined,
          (scheme) => scheme.primary,
        ),
        (
          TutorEvidenceKind.trend,
          'trend',
          Icons.trending_up,
          (scheme) => scheme.tertiary,
        ),
        (
          TutorEvidenceKind.knowledge,
          'knowledge',
          Icons.menu_book_outlined,
          (scheme) => scheme.secondary,
        ),
        (
          TutorEvidenceKind.inference,
          'inference',
          Icons.psychology_alt_outlined,
          (scheme) => scheme.error,
        ),
      ];

  for (final cell in matrix) {
    testWidgets('provenance chip renders ${cell.$2} text icon and color', (
      tester,
    ) async {
      await _pump(tester, TutorEvidenceChip(kind: cell.$1));

      final label = switch (cell.$1) {
        TutorEvidenceKind.measured => _l10n().aiTutorEvidenceMeasured,
        TutorEvidenceKind.trend => _l10n().aiTutorEvidenceTrend,
        TutorEvidenceKind.knowledge => _l10n().aiTutorEvidenceKnowledge,
        TutorEvidenceKind.inference => _l10n().aiTutorEvidenceInference,
      };
      expect(find.text(label), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Icon && widget.icon == cell.$3,
        ),
        findsOneWidget,
      );

      final chip = tester.widget<ActionChip>(find.byType(ActionChip));
      expect(
        chip.backgroundColor,
        cell.$4(Theme.of(tester.element(find.byType(ActionChip))).colorScheme),
      );
    });
  }

  test('domain provenance values map to presentation kinds', () {
    expect(
      evidenceKindForDebriefProvenance(DebriefFactProvenance.measuredFact),
      TutorEvidenceKind.measured,
    );
    expect(
      evidenceKindForDebriefProvenance(DebriefFactProvenance.computedTrend),
      TutorEvidenceKind.trend,
    );
    expect(
      evidenceKindForSource(
        const TutorSourceRef(
          sourceId: 'source-1',
          title: 'Rhythm basics',
          locale: 'en',
          topic: 'rhythm',
          knowledgeVersion: 2,
          chunkIndex: 0,
          chunkHash: 'hash',
        ),
      ),
      TutorEvidenceKind.knowledge,
    );
    expect(
      evidenceKindForProfileProvenance(
        StudentProfileFieldProvenance.practiceInferred,
      ),
      TutorEvidenceKind.inference,
    );
    expect(
      evidenceKindForProfileProvenance(
        StudentProfileFieldProvenance.userExplicit,
      ),
      isNull,
    );
  });

  testWidgets('evidence sheet exposes measured detail and reference mapping', (
    tester,
  ) async {
    await _pump(
      tester,
      const TutorSourceSheet(
        kind: TutorEvidenceKind.measured,
        evidenceId: 'session-42',
        metric: '88%',
      ),
    );

    expect(find.text(_l10n().aiTutorEvidenceDetailsTitle), findsOneWidget);
    expect(find.text(_l10n().aiTutorEvidenceMeasuredBody), findsOneWidget);
    expect(
      find.text(_l10n().aiTutorEvidenceReference('session-42')),
      findsOneWidget,
    );
    expect(find.text(_l10n().aiTutorEvidenceMetric('88%')), findsOneWidget);
  });

  testWidgets('source sheet maps approved source fields without raw path', (
    tester,
  ) async {
    const source = TutorSourceRef(
      sourceId: 'rhythm-basics',
      title: '<b>Rhythm basics</b>',
      locale: 'en',
      topic: 'rhythm',
      knowledgeVersion: 2,
      chunkIndex: 3,
      chunkHash: 'sha256:private-hash',
    );
    await _pump(tester, TutorSourceSheet.forSource(source));

    expect(find.textContaining('Rhythm basics'), findsOneWidget);
    expect(find.text(_l10n().aiTutorSourceTopic('rhythm')), findsOneWidget);
    expect(
      find.text(_l10n().aiTutorSourceVersion(2, source.chunkId)),
      findsOneWidget,
    );
    expect(find.textContaining('<b>'), findsNothing);
    expect(find.textContaining('sha256:private-hash'), findsNothing);
  });

  testWidgets(
    'inference sheet shows a warning and remains usable at large text',
    (tester) async {
      await _pump(
        tester,
        const TutorSourceSheet(kind: TutorEvidenceKind.inference),
        textScale: 3,
      );

      expect(
        find.text(_l10n().aiTutorEvidenceInferenceWarning),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('evidence chip callback can open the source sheet', (
    tester,
  ) async {
    await _pump(
      tester,
      TutorEvidenceChip(
        kind: TutorEvidenceKind.knowledge,
        onPressed: () async {
          await showTutorSourceSheet(
            tester.element(find.byType(TutorEvidenceChip)),
            const TutorSourceSheet(
              kind: TutorEvidenceKind.knowledge,
              source: TutorSourceRef(
                sourceId: 'source',
                title: 'Chord source',
                locale: 'en',
                topic: 'chords',
                knowledgeVersion: 1,
                chunkIndex: 0,
                chunkHash: 'hash',
              ),
            ),
          );
        },
      ),
    );

    await tester.tap(find.text(_l10n().aiTutorEvidenceKnowledge));
    await tester.pumpAndSettle();
    expect(find.text(_l10n().aiTutorEvidenceDetailsTitle), findsOneWidget);
    expect(find.textContaining('Chord source'), findsOneWidget);
  });
}
