import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/presentation/controllers/overview_view_model.dart';
import 'package:strumsight/features/audio_analysis/presentation/widgets/metric_card.dart';

OverviewMetricCard _card({
  required OverviewMetricCardState state,
  String value = '12 ms',
  String unit = 'ms',
  String statusLabel = 'High confidence',
  String reasonText = '',
  String tipText = '',
}) {
  return OverviewMetricCard(
    metricId: 'metric.x.v1',
    metricLabel: 'Demo metric',
    unit: unit,
    state: state,
    valueText: value,
    confidence: state == OverviewMetricCardState.available ? 0.9 : 0.4,
    statusLabel: statusLabel,
    reasonText: reasonText,
    tipText: tipText,
    isUsable: state == OverviewMetricCardState.available ||
        state == OverviewMetricCardState.degraded,
  );
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  group('MetricCard', () {
    testWidgets('renders available state with metric label and value', (
      tester,
    ) async {
      await _pump(
        tester,
        MetricCard(
          card: _card(state: OverviewMetricCardState.available),
          metricSemanticLabel: (l, v, s) => '$l:$v:$s',
        ),
      );

      expect(find.text('Demo metric'), findsOneWidget);
      expect(find.text('12 ms'), findsOneWidget);
      expect(find.text('High confidence'), findsOneWidget);
      expect(find.bySemanticsLabel('Demo metric:12 ms:High confidence'),
          findsOneWidget);
    });

    testWidgets('renders degraded state with medium-confidence label', (
      tester,
    ) async {
      await _pump(
        tester,
        MetricCard(
          card: _card(
            state: OverviewMetricCardState.degraded,
            statusLabel: 'Medium confidence',
          ),
          metricSemanticLabel: (l, v, s) => '$l:$v:$s',
        ),
      );

      expect(find.text('Medium confidence'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Icon &&
              w.icon == Icons.info_outline &&
              w.size == 18,
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'renders unavailable state with reason and tip — never hidden',
      (tester) async {
        await _pump(
          tester,
          MetricCard(
            card: _card(
              state: OverviewMetricCardState.unavailable,
              value: '—',
              statusLabel: 'Measurement unavailable',
              reasonText: 'Recording too short.',
              tipText: 'Record for longer.',
            ),
            metricSemanticLabel: (l, v, s) => '$l:$v:$s',
          ),
        );

        expect(find.text('Measurement unavailable'), findsOneWidget);
        expect(find.text('Recording too short.'), findsOneWidget);
        expect(find.text('Record for longer.'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Icon && w.icon == Icons.block && w.size == 18,
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('renders lowConfidence state with the dedicated label', (
      tester,
    ) async {
      await _pump(
        tester,
        MetricCard(
          card: _card(
            state: OverviewMetricCardState.lowConfidence,
            value: '—',
            statusLabel: 'Uncertain measurement',
            reasonText: 'Evidence too uncertain.',
            tipText: 'Re-record with clearer playing.',
          ),
          metricSemanticLabel: (l, v, s) => '$l:$v:$s',
        ),
      );

      expect(find.text('Uncertain measurement'), findsOneWidget);
      expect(find.text('Evidence too uncertain.'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Icon && w.icon == Icons.help_outline && w.size == 18,
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders notApplicable state with placeholder value', (
      tester,
    ) async {
      await _pump(
        tester,
        MetricCard(
          card: _card(
            state: OverviewMetricCardState.notApplicable,
            value: '—',
            statusLabel: 'Not applicable',
          ),
          metricSemanticLabel: (l, v, s) => '$l:$v:$s',
        ),
      );

      expect(find.text('Not applicable'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Icon &&
              w.icon == Icons.remove_circle_outline &&
              w.size == 18,
        ),
        findsOneWidget,
      );
    });

    testWidgets('every state has a Semantics label — never color-only', (
      tester,
    ) async {
      const states = <OverviewMetricCardState>[
        OverviewMetricCardState.available,
        OverviewMetricCardState.degraded,
        OverviewMetricCardState.unavailable,
        OverviewMetricCardState.lowConfidence,
        OverviewMetricCardState.notApplicable,
      ];
      for (final state in states) {
        await _pump(
          tester,
          MetricCard(
            card: _card(state: state, statusLabel: 'Status-$state'),
            metricSemanticLabel: (l, v, s) => '$l:$v:$s',
          ),
        );
        expect(
          find.bySemanticsLabel(
            'Demo metric:12 ms:Status-$state',
          ),
          findsOneWidget,
          reason: 'state=$state must expose a non-empty semantics label',
        );
      }
    });
  });
}
