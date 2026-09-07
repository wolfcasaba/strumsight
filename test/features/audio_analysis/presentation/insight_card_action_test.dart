// R22 (re-audit 2026-09-07 §3, MI3) — every Overview insight card rendered
// its CTA as `onPressed: null`, so the Analysis V2 surface had no live
// action at all. The CTA is now live wherever the caller wires a handler,
// and the COARSE persisted action (all the document keeps — the rule's
// hotspot/metric payload is dropped by `document_stages.dart`) maps to a
// route the app really registers.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_insight.dart';
import 'package:strumsight/features/audio_analysis/presentation/analysis_metric_detail_screen.dart';
import 'package:strumsight/features/audio_analysis/presentation/controllers/overview_view_model.dart';
import 'package:strumsight/features/audio_analysis/presentation/insight_action_route.dart';
import 'package:strumsight/features/audio_analysis/presentation/widgets/insight_card.dart';
import 'package:strumsight/l10n/app_localizations.dart';

const _delegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

OverviewInsightCard _card(AnalysisRecommendedAction action) =>
    OverviewInsightCard(
      title: 'Rush bias',
      body: 'You are rushing by 12 ms on average.',
      kindLabel: 'Recommendation',
      actionLabel: 'Slow down',
      actionTooltip: 'Not interactive here',
      action: action,
    );

Future<void> _pumpCard(WidgetTester tester, InsightCard card) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: card)));
  await tester.pumpAndSettle();
}

/// Minimal router around the OTHER screen that renders insight cards, so the
/// tap is proven to navigate and not merely to fire a callback.
Widget _detailHarness(OverviewInsightCard card) {
  final router = GoRouter(
    initialLocation: AppRoutes.analysisMetricDetail,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.analysisMetricDetail,
        builder: (_, _) => AnalysisMetricDetailScreen(
          remainingInsights: <OverviewInsightCard>[card],
        ),
      ),
      GoRoute(
        path: AppRoutes.analysisCapture,
        builder: (_, _) => const Scaffold(key: Key('capture-stub')),
      ),
    ],
  );
  return MaterialApp.router(
    routerConfig: router,
    theme: SsLightTheme.data(),
    localizationsDelegates: _delegates,
    supportedLocales: AppLocalizations.supportedLocales,
  );
}

void main() {
  group('insightActionRoute — every action has a real destination', () {
    test('the four persisted actions map to the documented routes', () {
      expect(
        insightActionRoute(AnalysisRecommendedAction.repeatSection),
        AppRoutes.practiceHub,
      );
      expect(
        insightActionRoute(AnalysisRecommendedAction.slowDown),
        AppRoutes.metronome,
      );
      expect(
        insightActionRoute(AnalysisRecommendedAction.adjustInput),
        AppRoutes.analysisCapture,
      );
      expect(
        insightActionRoute(AnalysisRecommendedAction.continuePractice),
        AppRoutes.practiceHub,
      );
    });

    test('no enum value is left without a destination', () {
      for (final action in AnalysisRecommendedAction.values) {
        expect(insightActionRoute(action), isNotEmpty, reason: '$action');
      }
    });
  });

  group('InsightCard — the CTA is honest in both states', () {
    testWidgets('no handler keeps the CTA disabled and tooltip-explained', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        InsightCard(card: _card(AnalysisRecommendedAction.slowDown)),
      );

      final cta = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(cta.onPressed, isNull);
      expect(find.byType(Tooltip), findsOneWidget);
    });

    testWidgets('a wired handler enables the CTA and forwards the action', (
      tester,
    ) async {
      final tapped = <AnalysisRecommendedAction>[];
      await _pumpCard(
        tester,
        InsightCard(
          card: _card(AnalysisRecommendedAction.adjustInput),
          onAction: tapped.add,
        ),
      );

      final cta = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(cta.onPressed, isNotNull);
      // No "becomes interactive in a future update" tooltip over a button
      // that IS interactive.
      expect(find.byType(Tooltip), findsNothing);

      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      expect(tapped.single, AnalysisRecommendedAction.adjustInput);
    });
  });

  testWidgets('AnalysisMetricDetailScreen — the CTA really navigates', (
    tester,
  ) async {
    await tester.pumpWidget(
      _detailHarness(_card(AnalysisRecommendedAction.adjustInput)),
    );
    await tester.pumpAndSettle();

    final cta = find.byKey(const Key('insight-action-adjustInput'));
    expect(cta, findsOneWidget);
    await tester.ensureVisible(cta);
    await tester.pumpAndSettle();
    await tester.tap(cta);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('capture-stub')), findsOneWidget);
  });
}
