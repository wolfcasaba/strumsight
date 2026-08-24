import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

Widget _wrap(Widget child, {double width = 320}) => MaterialApp(
  theme: SsLightTheme.data(),
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width, child: child),
    ),
  ),
);

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  group('A3 — the card background is tappable only at exactly one action', () {
    testWidgets('zero actions: no tap target exists anywhere on the card', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SsContentCard(
            title: 'Setlist synced',
            message: 'Your Friday setlist is ready offline.',
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(SsContentCard),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
    });

    testWidgets(
      'one action: the whole card is a single tap target that fires it',
      (tester) async {
        var tapped = 0;
        await tester.pumpWidget(
          _wrap(
            SsContentCard(
              title: 'Setlist synced',
              actions: [SsCardAction(label: 'Open', onPressed: () => tapped++)],
            ),
          ),
        );

        expect(
          find.descendant(
            of: find.byType(SsContentCard),
            matching: find.byType(InkWell),
          ),
          findsOneWidget,
        );

        await tester.tap(find.byType(SsContentCard));
        await tester.pump();

        expect(tapped, 1);
      },
    );

    testWidgets(
      'two or more actions: the background is not tappable — only the '
      'explicit buttons are (exactly one InkWell per button, none for the '
      'background)',
      (tester) async {
        var openTapped = 0;
        var shareTapped = 0;
        await tester.pumpWidget(
          _wrap(
            SsContentCard(
              title: 'Setlist synced',
              actions: [
                SsCardAction(label: 'Open', onPressed: () => openTapped++),
                SsCardAction(label: 'Share', onPressed: () => shareTapped++),
              ],
            ),
          ),
        );

        // Exactly two InkWells (one per SsButton) — a background wrap would
        // add a THIRD one and turn this cell red (§6.1 real-violation probe).
        expect(
          find.descendant(
            of: find.byType(SsContentCard),
            matching: find.byType(InkWell),
          ),
          findsNWidgets(2),
        );

        await tester.tap(find.widgetWithText(SsButton, 'Open'));
        await tester.pump();

        expect(openTapped, 1);
        expect(shareTapped, 0);
      },
    );
  });

  group('A4 — an embedded action tap never fires the card action', () {
    testWidgets('tapping the dismiss icon fires onDismiss only', (
      tester,
    ) async {
      var actionCount = 0;
      var dismissCount = 0;
      await tester.pumpWidget(
        _wrap(
          SsCoachActionCard(
            l10n: l10n,
            title: 'Ready for a tempo check?',
            message: 'Your strum timing has been steady for a week.',
            actionLabel: 'Start tempo check',
            onAction: () => actionCount++,
            onDismiss: () => dismissCount++,
            dismissSemanticLabel: 'Dismiss suggestion',
          ),
        ),
      );

      await tester.tap(find.byTooltip('Dismiss suggestion'));
      await tester.pump();

      expect(dismissCount, 1);
      expect(actionCount, 0);
    });

    testWidgets(
      'tapping the card background, away from the dismiss icon, fires '
      'onAction only',
      (tester) async {
        var actionCount = 0;
        var dismissCount = 0;
        await tester.pumpWidget(
          _wrap(
            SsCoachActionCard(
              l10n: l10n,
              title: 'Ready for a tempo check?',
              message: 'Your strum timing has been steady for a week.',
              actionLabel: 'Start tempo check',
              onAction: () => actionCount++,
              onDismiss: () => dismissCount++,
              dismissSemanticLabel: 'Dismiss suggestion',
            ),
          ),
        );

        // The dismiss icon sits in the top-right corner; this point is the
        // top-left of the card, comfortably clear of it.
        await tester.tapAt(
          tester.getTopLeft(find.byType(SsCoachActionCard)) +
              const Offset(16, 16),
        );
        await tester.pump();

        expect(actionCount, 1);
        expect(dismissCount, 0);
      },
    );
  });

  group('A5 — the metric-card skeleton holds the exact loaded geometry', () {
    testWidgets('expanded density: identical size, loaded vs skeleton', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SsMetricCard(label: 'Practice streak', value: 12, unit: 'days'),
        ),
      );
      final loadedSize = tester.getSize(find.byType(SsMetricCard));

      await tester.pumpWidget(_wrap(const SsMetricCardSkeleton()));
      final skeletonSize = tester.getSize(find.byType(SsMetricCardSkeleton));

      expect(skeletonSize, loadedSize);
    });

    testWidgets('compact density: identical size, loaded vs skeleton', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SsMetricCard(
            label: 'Accuracy',
            value: 87,
            unit: '%',
            density: SsCardDensity.compact,
          ),
        ),
      );
      final loadedSize = tester.getSize(find.byType(SsMetricCard));

      await tester.pumpWidget(
        _wrap(const SsMetricCardSkeleton(density: SsCardDensity.compact)),
      );
      final skeletonSize = tester.getSize(find.byType(SsMetricCardSkeleton));

      expect(skeletonSize, loadedSize);
    });

    testWidgets('the skeleton contributes nothing to the semantics tree', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _wrap(
          Semantics(
            key: const ValueKey('probe-semantics'),
            container: true,
            label: 'probe',
            child: const SsMetricCardSkeleton(),
          ),
        ),
      );

      // Only the outer probe label reaches semantics — the skeleton itself
      // announces nothing.
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('probe-semantics')))
            .label,
        'probe',
      );

      handle.dispose();
    });
  });

  group('A6 — a long Hungarian title never overflows the card, in either '
      'density', () {
    const longHungarianTitle =
        'A G-ről C-re való átváltás jelentősen lelassítja a pengetésed '
        'ritmusát minden gyakorlás közben';

    for (final density in SsCardDensity.values) {
      testWidgets('density: ${density.name}', (tester) async {
        await tester.pumpWidget(
          _wrap(
            SsContentCard(
              title: longHungarianTitle,
              message:
                  'Az utolsó öt gyakorlásod közül háromban itt álltál meg.',
              density: density,
            ),
            width: 220,
          ),
        );

        expect(tester.takeException(), isNull);
      });
    }
  });
}
