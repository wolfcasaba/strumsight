// E14-R38 (ADR 0551 D6) — the correction the player actually reads.
//
// The parity cell is the important one: the practice banner and the Live
// uncertainty banner must say the SAME sentence for the same reject reason.
// They are two exhaustive switches over one enum (the practice domain may not
// import the Live widget layer), so without this cell they could silently
// drift into two different pieces of advice for one diagnosis — exactly the
// failure ADR 0535 removed from the Live side.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/live/domain/recognition/recognition_decision.dart';
import 'package:strumsight/features/live/widgets/uncertainty_reason_banner.dart';
import 'package:strumsight/features/practice/domain/model/practice_correction.dart';
import 'package:strumsight/features/practice/presentation/widgets/practice_correction_banner.dart';
import 'package:strumsight/l10n/app_localizations.dart';

Future<void> _pump(WidgetTester tester, PracticeCorrection correction) =>
    tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PracticeCorrectionBanner(correction: correction),
        ),
      ),
    );

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  group('reject-reason parity with the Live uncertainty banner', () {
    for (final reason in RecognitionRejectReason.values) {
      test('${reason.name} says exactly what Live says', () {
        final correction = PracticeCorrection.recognitionUnclear(
          targetIndex: 0,
          rejectReasonCode: reason.name,
        );
        expect(
          PracticeCorrectionBanner.textFor(l10n, correction),
          UncertaintyReasonBanner.textFor(l10n, reason),
        );
      });
    }

    test('an unknown or absent code degrades to the generic sentence rather '
        'than guessing a cause', () {
      for (final code in <String?>[null, '', 'someFutureReason']) {
        expect(
          PracticeCorrectionBanner.textFor(
            l10n,
            PracticeCorrection.recognitionUnclear(
              targetIndex: 0,
              rejectReasonCode: code,
            ),
          ),
          l10n.practiceCorrectionUnclear,
        );
      }
    });
  });

  group('the correction never blames the player for the app abstaining', () {
    testWidgets('an abstention states the listening problem, and names no '
        'chord at all', (tester) async {
      await _pump(
        tester,
        PracticeCorrection.recognitionUnclear(
          targetIndex: 2,
          rejectReasonCode: RecognitionRejectReason.signalTooQuiet.name,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.practiceCorrectionTitle), findsOneWidget);
      expect(find.text(l10n.liveRejectSignalTooQuiet), findsOneWidget);
      expect(find.textContaining('Play '), findsNothing);
    });
  });

  group('a confident miss states the concrete next fix', () {
    testWidgets('a wrong/missed chord target names the expected chord', (
      tester,
    ) async {
      await _pump(
        tester,
        PracticeCorrection.playExpectedChord(
          targetIndex: 1,
          expectedChord: 'Am',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.practiceCorrectionPlayChord('Am')),
        findsOneWidget,
      );
    });

    testWidgets('a chord-less target names the target, not a chord', (
      tester,
    ) async {
      await _pump(tester, PracticeCorrection.hitTheTarget(targetIndex: 3));
      await tester.pumpAndSettle();

      expect(find.text(l10n.practiceCorrectionHitTarget), findsOneWidget);
    });
  });

  test('the correction is a value: same inputs compare equal', () {
    expect(
      PracticeCorrection.playExpectedChord(targetIndex: 1, expectedChord: 'C'),
      PracticeCorrection.playExpectedChord(targetIndex: 1, expectedChord: 'C'),
    );
    expect(
      PracticeCorrection.playExpectedChord(targetIndex: 1, expectedChord: 'C'),
      isNot(
        PracticeCorrection.playExpectedChord(
          targetIndex: 2,
          expectedChord: 'C',
        ),
      ),
    );
  });
}
