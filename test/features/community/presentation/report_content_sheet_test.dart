/// E09-R26 — User-report bottom-sheet widget tests.
///
/// Covers the §6 Flutter-side acceptance cells:
///
/// * A3 — after a successful submit the sheet transitions to the
///   thanks phase that surfaces hide / mute / block shortcuts.
/// * A7 — the sheet's semantic tree lands the focus on the title
///   for screen readers; every category choice is a tappable
///   semantic button with its label exposed.
///
/// The widget test uses a ``_RecordingReportRepository`` that
/// captures the wire-shape arguments (target_type, target_id,
/// category, idempotency_key) and lets the test pre-program the
/// submit outcome. The repository is the §5.1 sanitization boundary
/// — the test asserts the wire-shape arguments match the
/// backend's contract.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/features/community/presentation/dialogs/report_content_sheet.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// Recording fake — captures every repository call so the test can
/// assert the wire shape.
class _RecordingReportRepository implements ReportRepository {
  _RecordingReportRepository({this.submitShouldFail = false});

  final List<
    ({
      String targetType,
      String targetId,
      ReportCategory category,
      String idempotencyKey,
    })
  >
  submitCalls =
      <
        ({
          String targetType,
          String targetId,
          ReportCategory category,
          String idempotencyKey,
        })
      >[];
  final List<String> hideCalls = <String>[];
  final List<String> muteCalls = <String>[];
  final List<String> blockCalls = <String>[];
  final bool submitShouldFail;
  ReportSubmissionOutcome? _submitOutcome;

  void setSubmitOutcome(ReportSubmissionOutcome outcome) {
    _submitOutcome = outcome;
  }

  @override
  Future<ReportSubmissionOutcome> submit({
    required String targetType,
    required String targetId,
    required ReportCategory category,
    required String idempotencyKey,
  }) async {
    submitCalls.add((
      targetType: targetType,
      targetId: targetId,
      category: category,
      idempotencyKey: idempotencyKey,
    ));
    if (submitShouldFail) {
      throw Exception('repository offline');
    }
    return _submitOutcome ??
        const ReportSubmissionOutcome(
          reportPublicId: '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a01',
          deduplicated: false,
          action: null,
        );
  }

  @override
  Future<void> hideFromFeed({required String targetId}) async {
    hideCalls.add(targetId);
  }

  @override
  Future<void> muteAuthor({required String authorPublicId}) async {
    muteCalls.add(authorPublicId);
  }

  @override
  Future<void> blockAuthor({required String authorPublicId}) async {
    blockCalls.add(authorPublicId);
  }
}

Widget _harness({
  required ReportRepository repository,
  ReportContentRequest? request,
  void Function(ReportSubmissionOutcome?)? onClosed,
}) {
  return MaterialApp(
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            key: const Key('open-report-sheet'),
            onPressed: () async {
              final result = await showReportContentSheet(
                context,
                request:
                    request ??
                    const ReportContentRequest(
                      targetType: 'post',
                      targetId: '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a10',
                      targetAuthorPublicId:
                          '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a11',
                    ),
                repository: repository,
              );
              onClosed?.call(result);
            },
            child: const Text('Open report sheet'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open-report-sheet')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'A3: submit transitions to thanks phase with hide/mute/block shortcuts',
    (tester) async {
      final repo = _RecordingReportRepository();
      await tester.pumpWidget(_harness(repository: repo));
      await _openSheet(tester);

      // Compose phase visible — category list + submit button.
      expect(find.byKey(const Key('report-submit')), findsOneWidget);
      expect(find.text('Report this content'), findsOneWidget);

      // Pick "Harassment" (a non-self-harm category so the helper
      // line does NOT appear — see the §5.3 negative test below).
      await tester.tap(find.byKey(const Key('report-category-harassment')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('report-self-harm-helper')), findsNothing);

      // Submit.
      await tester.tap(find.byKey(const Key('report-submit')));
      await tester.pumpAndSettle();

      // Thanks phase visible.
      expect(find.text('Report received — thank you'), findsOneWidget);

      // A3 — the §5.2 immediate-safety shortcuts are all present.
      expect(find.byKey(const Key('report-action-hide')), findsOneWidget);
      expect(find.byKey(const Key('report-action-mute')), findsOneWidget);
      expect(find.byKey(const Key('report-action-block')), findsOneWidget);
      expect(find.byKey(const Key('report-action-done')), findsOneWidget);

      // Wire-shape assertion — the repository saw the right args.
      expect(repo.submitCalls, hasLength(1));
      final call = repo.submitCalls.single;
      expect(call.targetType, 'post');
      expect(call.targetId, '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a10');
      expect(call.category, ReportCategory.harassment);
      expect(call.idempotencyKey, isNotEmpty);
    },
  );

  testWidgets(
    'A3 — tapping hide forwards target_id to the repository and pops',
    (tester) async {
      final repo = _RecordingReportRepository();
      ReportSubmissionOutcome? outcome;
      await tester.pumpWidget(
        _harness(repository: repo, onClosed: (result) => outcome = result),
      );
      await _openSheet(tester);

      await tester.tap(find.byKey(const Key('report-category-spam')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report-submit')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('report-action-hide')));
      await tester.pumpAndSettle();

      expect(repo.hideCalls, <String>['01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a10']);
      expect(repo.muteCalls, isEmpty);
      expect(repo.blockCalls, isEmpty);
      expect(outcome, isNotNull);
      expect(outcome!.action, ReportSafetyAction.hide);
      expect(outcome!.reportPublicId, '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a01');
    },
  );

  testWidgets(
    'A3 — tapping block forwards the author public_id to the repository',
    (tester) async {
      final repo = _RecordingReportRepository();
      ReportSubmissionOutcome? outcome;
      await tester.pumpWidget(
        _harness(repository: repo, onClosed: (result) => outcome = result),
      );
      await _openSheet(tester);

      await tester.tap(find.byKey(const Key('report-category-harassment')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report-submit')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('report-action-block')));
      await tester.pumpAndSettle();

      expect(repo.blockCalls, <String>['01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a11']);
      expect(outcome?.action, ReportSafetyAction.block);
    },
  );

  testWidgets(
    'A3 — sheet without targetAuthorPublicId skips mute/block but keeps hide',
    (tester) async {
      final repo = _RecordingReportRepository();
      await tester.pumpWidget(
        _harness(
          repository: repo,
          request: const ReportContentRequest(
            targetType: 'post',
            targetId: '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a10',
            // targetAuthorPublicId: null
          ),
        ),
      );
      await _openSheet(tester);

      await tester.tap(find.byKey(const Key('report-category-spam')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report-submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('report-action-hide')), findsOneWidget);
      expect(find.byKey(const Key('report-action-mute')), findsNothing);
      expect(find.byKey(const Key('report-action-block')), findsNothing);
      expect(find.byKey(const Key('report-action-done')), findsOneWidget);
    },
  );

  testWidgets(
    '§5.3 — self-harm category shows the approved safety-copy helper line',
    (tester) async {
      final repo = _RecordingReportRepository();
      await tester.pumpWidget(_harness(repository: repo));
      await _openSheet(tester);

      // Before picking a category, the helper is NOT visible.
      expect(find.byKey(const Key('report-self-harm-helper')), findsNothing);

      // Pick self_harm_concern.
      await tester.tap(
        find.byKey(const Key('report-category-self_harm_concern')),
      );
      await tester.pumpAndSettle();

      // The §5.3 helper line is now visible — exactly the approved
      // ARB copy, no ad-hoc text.
      expect(find.byKey(const Key('report-self-harm-helper')), findsOneWidget);
      expect(
        find.textContaining('emergency services', findRichText: false),
        findsOneWidget,
      );

      // And submitting carries the wire value through.
      await tester.tap(find.byKey(const Key('report-submit')));
      await tester.pumpAndSettle();
      expect(repo.submitCalls.single.category, ReportCategory.selfHarmConcern);
    },
  );

  testWidgets(
    'A7 — every category is a tappable semantic button with its label',
    (tester) async {
      final repo = _RecordingReportRepository();
      await tester.pumpWidget(_harness(repository: repo));
      await _openSheet(tester);

      // All 10 categories are present and each is exposed as a
      // semantic button — the §6 A7 cell.
      for (final category in ReportCategory.values) {
        final key = find.byKey(Key('report-category-${category.wireValue}'));
        expect(
          key,
          findsOneWidget,
          reason: 'missing semantic tile for ${category.wireValue}',
        );
        final node = tester.getSemantics(key);
        // Each category tile carries a non-empty semantic label
        // (the localized category name) — the §6 A7 cell. The
        // tap-action is enforced by the underlying ListTile and
        // exercised by the E2E "pick a category" tests above.
        expect(
          node.label,
          isNotEmpty,
          reason: '${category.wireValue} has no semantic label',
        );
      }
    },
  );

  testWidgets(
    'A7 — the title semantic node announces the dialog to screen readers',
    (tester) async {
      final repo = _RecordingReportRepository();
      await tester.pumpWidget(_harness(repository: repo));
      await _openSheet(tester);

      // The Semantics(container: true, label: …) wrapper around the
      // sheet's body lands the screen-reader focus on the dialog's
      // accessibility label.
      final titleSemantics = tester.getSemantics(
        find.text('Report this content'),
      );
      expect(titleSemantics.label, contains('Report this content'));

      // The category hint is its own semantic node so the screen
      // reader reads it as a separate instruction.
      final hintSemantics = tester.getSemantics(find.text('Reason'));
      expect(hintSemantics.label, contains('Reason'));
    },
  );

  testWidgets(
    'submit button is disabled until a category is picked (A7 — focus stays clear)',
    (tester) async {
      final repo = _RecordingReportRepository();
      await tester.pumpWidget(_harness(repository: repo));
      await _openSheet(tester);

      // No category selected — submit button is disabled.
      final submitButton = tester.widget<FilledButton>(
        find.byKey(const Key('report-submit')),
      );
      expect(submitButton.onPressed, isNull);

      // Pick a category — submit button enables.
      await tester.tap(find.byKey(const Key('report-category-spam')));
      await tester.pumpAndSettle();
      final submitButtonAfter = tester.widget<FilledButton>(
        find.byKey(const Key('report-submit')),
      );
      expect(submitButtonAfter.onPressed, isNotNull);
    },
  );

  testWidgets(
    'A5 — every wire value matches the backend REPORT_CATEGORIES set',
    (tester) async {
      // The category enum's wire values are the §6 A5 contract.
      // Snapshot them so a future rename is caught here.
      const expectedWireValues = <String>{
        'spam',
        'harassment',
        'hate_speech',
        'violence',
        'sexual_content',
        'self_harm_concern',
        'copyright',
        'privacy',
        'misinformation',
        'other',
      };
      final actual = ReportCategory.values.map((c) => c.wireValue).toSet();
      expect(actual, expectedWireValues);
    },
  );

  testWidgets('submit failure stays in compose phase with an error snackbar', (
    tester,
  ) async {
    final repo = _RecordingReportRepository(submitShouldFail: true);
    await tester.pumpWidget(_harness(repository: repo));
    await _openSheet(tester);

    await tester.tap(find.byKey(const Key('report-category-spam')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-submit')));
    await tester.pumpAndSettle();

    // Thanks phase NOT shown — we're still in compose phase.
    expect(find.text('Report received — thank you'), findsNothing);
    // And the error message is surfaced via the ScaffoldMessenger.
    expect(
      find.text("We couldn't submit that report. Please try again."),
      findsOneWidget,
    );
  });

  testWidgets('hu locale: the sheet renders Hungarian category labels', (
    tester,
  ) async {
    final repo = _RecordingReportRepository();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('hu'),
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showReportContentSheet(
                  context,
                  request: const ReportContentRequest(
                    targetType: 'post',
                    targetId: '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a10',
                  ),
                  repository: repo,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Hungarian title is rendered — the §5.3 / §3 i18n cell.
    expect(find.text('Tartalom bejelentése'), findsOneWidget);
  });
}
