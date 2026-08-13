import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_metric_catalog.dart';
import 'package:strumsight/features/audio_analysis/domain/comparison/analysis_comparison.dart';
import 'package:strumsight/features/audio_analysis/presentation/analysis_compare_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

Future<void> _pumpAt(
  WidgetTester tester,
  Widget child, {
  required Size size,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(child);
  await tester.pumpAndSettle();
}

Widget _harness(AnalysisComparison comparison, {Locale? locale}) => MaterialApp(
  locale: locale,
  localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: AnalysisCompareScreen(comparison: comparison),
);

MetricComparison _improved({
  String metricId = AnalysisMetricId.timingTargetMeanAbsoluteError,
}) => MetricComparison(
  metricId: metricId,
  direction: MetricComparisonDirection.improved,
  confidence: 0.8,
  sampleCount: 12,
  beforeValue: 40,
  afterValue: 30,
  absoluteDelta: -10,
  relativeDelta: -0.25,
);

MetricComparison _inconclusive() => MetricComparison(
  metricId: AnalysisMetricId.dynamicsDrift,
  direction: MetricComparisonDirection.inconclusive,
  confidence: 0.5,
  sampleCount: 6,
  inconclusiveReason: ComparisonInconclusiveReason.inputQualityDiverged,
);

void main() {
  group('AnalysisCompareScreen', () {
    testWidgets('shows the empty state when no metric is comparable', (
      tester,
    ) async {
      final comparison = AnalysisComparison(
        beforeAnalysisId: 'before',
        afterAnalysisId: 'after',
        metrics: const <MetricComparison>[],
      );

      await _pumpAt(tester, _harness(comparison), size: const Size(400, 800));

      expect(
        find.text('No metric is comparable between these two sessions.'),
        findsOneWidget,
      );
    });

    testWidgets('renders before/after/delta/confidence/sampleCount for an improved metric', (
      tester,
    ) async {
      final comparison = AnalysisComparison(
        beforeAnalysisId: 'before',
        afterAnalysisId: 'after',
        metrics: <MetricComparison>[_improved()],
      );

      await _pumpAt(tester, _harness(comparison), size: const Size(400, 800));

      expect(find.textContaining('40.00'), findsOneWidget);
      expect(find.textContaining('30.00'), findsOneWidget);
      expect(find.textContaining('-10.00'), findsOneWidget);
      expect(find.text('Improved'), findsOneWidget);
      expect(find.textContaining('80%'), findsOneWidget);
      expect(find.textContaining('12'), findsOneWidget);
    });

    testWidgets('renders the inconclusive reason instead of a fabricated delta', (
      tester,
    ) async {
      final comparison = AnalysisComparison(
        beforeAnalysisId: 'before',
        afterAnalysisId: 'after',
        metrics: <MetricComparison>[_inconclusive()],
      );

      await _pumpAt(tester, _harness(comparison), size: const Size(400, 800));

      expect(find.text('Inconclusive'), findsOneWidget);
      expect(
        find.text(
          'The recording quality differs too much between the two sessions.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('hu/en parity — title translates', (tester) async {
      final comparison = AnalysisComparison(
        beforeAnalysisId: 'before',
        afterAnalysisId: 'after',
        metrics: const <MetricComparison>[],
      );

      await _pumpAt(tester, _harness(comparison), size: const Size(400, 800));
      expect(find.text('Compare sessions'), findsOneWidget);

      await _pumpAt(
        tester,
        _harness(comparison, locale: const Locale('hu')),
        size: const Size(400, 800),
      );
      expect(find.text('Sessionök összehasonlítása'), findsOneWidget);
    });

    testWidgets('overflow matrix — 320px / 2.0 scale renders without overflow', (
      tester,
    ) async {
      final comparison = AnalysisComparison(
        beforeAnalysisId: 'before',
        afterAnalysisId: 'after',
        metrics: <MetricComparison>[_improved(), _inconclusive()],
      );

      await _pumpAt(
        tester,
        _harness(comparison),
        size: const Size(320, 800),
        textScale: 2.0,
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('overflow matrix — 320px / 1.0 scale renders without overflow', (
      tester,
    ) async {
      final comparison = AnalysisComparison(
        beforeAnalysisId: 'before',
        afterAnalysisId: 'after',
        metrics: <MetricComparison>[_improved(), _inconclusive()],
      );

      await _pumpAt(
        tester,
        _harness(comparison),
        size: const Size(320, 800),
        textScale: 1.0,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
