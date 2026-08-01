import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/domain/model/practice_history_entry.dart';
import 'package:strumsight/features/practice/domain/model/practice_metric_snapshot.dart';
import 'package:strumsight/features/practice/presentation/widgets/timing_bias_chart.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

void main() {
  AppLocalizations l10n() => AppLocalizationsEn();

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
    await tester.pump();
  }

  PracticeAttemptDetail makeDetail(PracticeMetricSnapshot snapshot) {
    return PracticeAttemptDetail(index: 0, metricSnapshot: snapshot);
  }

  const PracticeMetricSnapshot snapshot = PracticeMetricSnapshot(
    completion: PracticeMetricDimensionAvailable(0.9),
    rhythm: PracticeMetricDimensionAvailable(0.85),
    direction: PracticeMetricDimensionAvailable(0.95),
    chord: PracticeMetricDimensionNotApplicable(),
    overall: PracticeMetricDimensionAvailable(0.9),
  );

  group('M3 — timing bias label is driven by the signed timingBias', () {
    testWidgets('late bias (positive) renders "late", not "balanced"', (
      tester,
    ) async {
      await pump(
        tester,
        TimingBiasChart(
          detailAttempts: <PracticeAttemptDetail>[makeDetail(snapshot)],
          timingBias: const Duration(milliseconds: 30),
        ),
      );
      expect(find.text(l10n().practiceResultTimingLate), findsOneWidget);
      expect(find.text(l10n().practiceResultTimingBalanced), findsNothing);
      expect(find.text(l10n().practiceResultTimingEarly), findsNothing);
    });

    testWidgets('early bias (negative) renders "early"', (tester) async {
      await pump(
        tester,
        TimingBiasChart(
          detailAttempts: <PracticeAttemptDetail>[makeDetail(snapshot)],
          timingBias: const Duration(milliseconds: -25),
        ),
      );
      expect(find.text(l10n().practiceResultTimingEarly), findsOneWidget);
      expect(find.text(l10n().practiceResultTimingBalanced), findsNothing);
    });

    testWidgets('a small bias within ±15 ms renders "balanced"', (
      tester,
    ) async {
      await pump(
        tester,
        TimingBiasChart(
          detailAttempts: <PracticeAttemptDetail>[makeDetail(snapshot)],
          timingBias: const Duration(milliseconds: 8),
        ),
      );
      expect(find.text(l10n().practiceResultTimingBalanced), findsOneWidget);
      expect(find.text(l10n().practiceResultTimingLate), findsNothing);
      expect(find.text(l10n().practiceResultTimingEarly), findsNothing);
    });

    testWidgets('zero bias renders "balanced"', (tester) async {
      await pump(
        tester,
        TimingBiasChart(
          detailAttempts: <PracticeAttemptDetail>[makeDetail(snapshot)],
          timingBias: Duration.zero,
        ),
      );
      expect(find.text(l10n().practiceResultTimingBalanced), findsOneWidget);
    });

    testWidgets('an empty detail list renders nothing (no chart card)', (
      tester,
    ) async {
      await pump(
        tester,
        TimingBiasChart(
          detailAttempts: const <PracticeAttemptDetail>[],
          timingBias: const Duration(milliseconds: 50),
        ),
      );
      // Empty detail ⇒ the widget collapses to a SizedBox.shrink; no
      // label is rendered regardless of the bias value.
      expect(find.text(l10n().practiceResultTimingTitle), findsNothing);
      expect(find.text(l10n().practiceResultTimingLate), findsNothing);
    });
  });
}
