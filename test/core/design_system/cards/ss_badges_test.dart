import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: SsLightTheme.data(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  group('A1 — AI provenance is visible by default on AI-touched content, not '
      'behind a detail view', () {
    testWidgets(
      'SsModelStatusCard renders its provenance badge in the base tree',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            SsModelStatusCard(
              l10n: l10n,
              title: 'Chord detector',
              provenance: SsProvenanceKind.local,
            ),
          ),
        );

        expect(find.byType(SsProvenanceBadge), findsOneWidget);
        expect(find.text(l10n.dsProvenanceBadgeLocalLabel), findsOneWidget);
      },
    );

    testWidgets(
      'SsInsightCard renders its provenance badge whenever the insight '
      'carries one, without any extra interaction',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            SsInsightCard(
              l10n: l10n,
              title: 'Your G-to-C transition is slowing you down',
              message: 'Three of your last five sessions paused there.',
              provenance: SsProvenanceKind.cloud,
            ),
          ),
        );

        expect(find.byType(SsProvenanceBadge), findsOneWidget);
        expect(find.text(l10n.dsProvenanceBadgeCloudLabel), findsOneWidget);
      },
    );

    testWidgets(
      'a card with no provenance set renders no provenance badge at all '
      '(nothing to claim about content that carries none)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            SsInsightCard(
              l10n: l10n,
              title: 'Insight title',
              message: 'Insight message',
            ),
          ),
        );

        expect(find.byType(SsProvenanceBadge), findsNothing);
      },
    );
  });

  group('A2 — no badge kind is distinguished by colour alone: every kind pairs '
      'a distinct icon and/or text, and no two kinds share both', () {
    testWidgets('every SsStatusBadgeKind renders a unique (icon, text) pair', (
      tester,
    ) async {
      final seen = <(IconData, String)>{};

      for (final kind in SsStatusBadgeKind.values) {
        await tester.pumpWidget(_wrap(SsStatusBadge(l10n: l10n, kind: kind)));

        final icon = tester.widget<Icon>(find.byType(Icon)).icon!;
        final label = tester.widget<Text>(find.byType(Text)).data!;

        expect(
          seen.add((icon, label)),
          isTrue,
          reason:
              '$kind repeats the (icon, text) pair of an earlier kind — '
              'a colour-only implementation would fail here',
        );
      }
    });

    testWidgets('the two confidence extremes share the SAME icon but never the '
        'same text — the level itself is a readable fact', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SsStatusBadge(l10n: l10n, kind: SsStatusBadgeKind.confidenceHigh),
        ),
      );
      final highIcon = tester.widget<Icon>(find.byType(Icon)).icon;

      await tester.pumpWidget(
        _wrap(SsStatusBadge(l10n: l10n, kind: SsStatusBadgeKind.confidenceLow)),
      );
      final lowIcon = tester.widget<Icon>(find.byType(Icon)).icon;

      expect(lowIcon, highIcon);
      expect(
        l10n.dsStatusBadgeConfidenceHigh,
        isNot(l10n.dsStatusBadgeConfidenceLow),
      );
    });

    testWidgets('every SsProvenanceKind renders a unique (icon, text) pair', (
      tester,
    ) async {
      final seen = <(IconData, String)>{};

      for (final kind in SsProvenanceKind.values) {
        await tester.pumpWidget(
          _wrap(SsProvenanceBadge(l10n: l10n, kind: kind)),
        );

        final icon = tester.widget<Icon>(find.byType(Icon)).icon!;
        final label = tester.widget<Text>(find.byType(Text)).data!;

        expect(
          seen.add((icon, label)),
          isTrue,
          reason: '$kind repeats the (icon, text) pair of the other kind',
        );
      }
    });
  });
}
