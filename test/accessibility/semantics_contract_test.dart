import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: SsLightTheme.data(),
  home: Scaffold(body: child),
);

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  group(
    'A1 — the live region honours the announcement budget (ADR 0280 §2)',
    () {
      // §0.0/D3 — the exact cells, computed so no interpretation gap remains.
      test(
        'below the threshold: rapid readings collapse into the first one',
        () {
          final region = SsLiveRegion();

          region.report('C', at: const Duration(milliseconds: 0));
          region.report('G', at: const Duration(milliseconds: 400));
          region.report('D', at: const Duration(milliseconds: 800));

          expect(region.announcements, ['C']);
        },
      );

      test('exactly at the threshold (1000 ms): the boundary is inclusive', () {
        final region = SsLiveRegion();

        region.report('C', at: const Duration(milliseconds: 0));
        region.report('G', at: const Duration(milliseconds: 1000));

        expect(region.announcements, ['C', 'G']);
      });

      test('above the threshold: every distinct reading announces', () {
        final region = SsLiveRegion();

        region.report('C', at: const Duration(milliseconds: 0));
        region.report('G', at: const Duration(milliseconds: 2500));
        region.report('D', at: const Duration(milliseconds: 5000));

        expect(region.announcements, ['C', 'G', 'D']);
      });

      test(
        'the same value repeated does not announce again, even past the gap',
        () {
          final region = SsLiveRegion();

          region.report('C', at: const Duration(milliseconds: 0));
          region.report('C', at: const Duration(milliseconds: 2500));

          expect(region.announcements, ['C']);
        },
      );

      testWidgets(
        'the BUILT live-region widget speaks only the throttled announcements '
        '— not a standalone predicate (§0.0/D3, docs/LESSONS.md L443)',
        (tester) async {
          final region = SsLiveRegion();
          await tester.pumpWidget(
            _wrap(SsLiveRegionAnnouncer(controller: region)),
          );

          expect(find.bySemanticsLabel('C'), findsNothing);

          region.report('C', at: Duration.zero);
          await tester.pump();
          expect(find.bySemanticsLabel('C'), findsOneWidget);

          region.report('G', at: const Duration(milliseconds: 400));
          await tester.pump();
          expect(
            find.bySemanticsLabel('C'),
            findsOneWidget,
            reason: 'G arrived before the gap elapsed and must be suppressed',
          );
          expect(find.bySemanticsLabel('G'), findsNothing);

          region.report('D', at: const Duration(milliseconds: 1000));
          await tester.pump();
          expect(find.bySemanticsLabel('D'), findsOneWidget);

          expect(region.announcements, ['C', 'D']);
        },
      );
    },
  );

  group(
    'A3 — no success/error/confidence state is communicated by colour alone '
    '(ADR 0278 §2, enforced here in one place per ADR 0280 §5.4)',
    () {
      testWidgets('every SsStatusBadgeKind carries its own readable semantics '
          'label — never just an icon colour', (tester) async {
        final seenLabels = <String>{};

        for (final kind in SsStatusBadgeKind.values) {
          await tester.pumpWidget(_wrap(SsStatusBadge(l10n: l10n, kind: kind)));

          final expectedLabel = switch (kind) {
            SsStatusBadgeKind.offline => l10n.dsStatusBadgeOffline,
            SsStatusBadgeKind.syncPending => l10n.dsStatusBadgeSyncPending,
            SsStatusBadgeKind.confidenceHigh =>
              l10n.dsStatusBadgeConfidenceHigh,
            SsStatusBadgeKind.confidenceMedium =>
              l10n.dsStatusBadgeConfidenceMedium,
            SsStatusBadgeKind.confidenceLow => l10n.dsStatusBadgeConfidenceLow,
          };

          expect(
            find.bySemanticsLabel(expectedLabel),
            findsOneWidget,
            reason:
                '$kind must expose $expectedLabel on its OWN semantics node '
                '— a colour-only implementation would leave this unreadable',
          );
          expect(
            seenLabels.add(expectedLabel),
            isTrue,
            reason: '$kind repeats a label already used by another kind',
          );
        }
      });

      test(
        'the two confidence extremes read as distinct text, not just a colour '
        'swap',
        () {
          expect(
            l10n.dsStatusBadgeConfidenceHigh,
            isNot(l10n.dsStatusBadgeConfidenceLow),
          );
        },
      );

      test('a tuner reading in tune, sharp and flat each read distinct text '
          '(ADR 0280 §5.3) — the accuracy state is never colour-only', () {
        final inTune = SsSemantics.tunerAccuracyLabel(
          l10n,
          cents: 2,
          inTune: true,
        );
        final sharp = SsSemantics.tunerAccuracyLabel(
          l10n,
          cents: 18,
          inTune: false,
        );
        final flat = SsSemantics.tunerAccuracyLabel(
          l10n,
          cents: -18,
          inTune: false,
        );

        expect({inTune, sharp, flat}, hasLength(3));
        expect(inTune, l10n.tunerInTune);
        expect(sharp, l10n.tunerCentsSharp(18));
        expect(flat, l10n.tunerCentsFlat(18));
      });
    },
  );

  group(
    'A4 — every critical action carries a non-empty semantics label or hint '
    '(§5.5)',
    () {
      testWidgets('SsIconButton exposes the caller-supplied label as its own '
          'semantics node', (tester) async {
        await tester.pumpWidget(
          _wrap(
            SsIconButton(
              iconName: 'close',
              semanticLabel: 'Dismiss suggestion',
              tooltip: 'Dismiss suggestion',
              onPressed: () {},
            ),
          ),
        );

        expect(find.bySemanticsLabel('Dismiss suggestion'), findsOneWidget);
      });

      test('SsIconButton refuses to be constructed without a label — a '
          'critical action can never silently ship unlabeled', () {
        expect(
          () => SsIconButton(
            iconName: 'close',
            semanticLabel: '',
            tooltip: 'Dismiss',
            onPressed: () {},
          ),
          throwsArgumentError,
        );
      });

      testWidgets(
        'a destructive SsButton merges its hint into the SAME semantics node '
        'as the label — not colour alone distinguishing the intent',
        (tester) async {
          final handle = tester.ensureSemantics();

          await tester.pumpWidget(
            _wrap(
              SsButton(
                label: 'Delete recording',
                variant: SsButtonVariant.destructive,
                destructiveSemanticHint: 'This cannot be undone',
                onPressed: () {},
              ),
            ),
          );

          expect(
            tester.getSemantics(find.byType(SsButton)),
            matchesSemantics(
              label: 'Delete recording',
              hint: 'This cannot be undone',
              isButton: true,
              hasEnabledState: true,
              isEnabled: true,
              hasTapAction: true,
              isFocusable: true,
              hasFocusAction: true,
            ),
          );

          handle.dispose();
        },
      );

      testWidgets(
        'SsCoachActionCard\'s dismiss control carries its own semantics '
        'label, distinct from the card\'s main action',
        (tester) async {
          await tester.pumpWidget(
            _wrap(
              SsCoachActionCard(
                l10n: l10n,
                title: 'Try the G-to-C drill',
                message: 'Three of your last five sessions paused there.',
                actionLabel: 'Start drill',
                onAction: () {},
                onDismiss: () {},
                dismissSemanticLabel: 'Dismiss coach suggestion',
              ),
            ),
          );

          expect(
            find.bySemanticsLabel('Dismiss coach suggestion'),
            findsOneWidget,
          );
        },
      );
    },
  );

  group('A8 — reduced motion silences animation extent, not the semantics '
      'feedback (ADR 0274 §5.1, §0.0/D5)', () {
    testWidgets(
      'a live-region announcement still lands while SsMotionScope resolves '
      'reduced motion',
      (tester) async {
        final region = SsLiveRegion();
        late BuildContext capturedContext;

        await tester.pumpWidget(
          MaterialApp(
            theme: SsLightTheme.data(),
            home: SsMotionScope(
              appOverride: true,
              child: Builder(
                builder: (context) {
                  capturedContext = context;
                  return Scaffold(
                    body: SsLiveRegionAnnouncer(controller: region),
                  );
                },
              ),
            ),
          ),
        );

        expect(
          SsMotionScope.durationOf(
            capturedContext,
            const Duration(milliseconds: 300),
          ),
          Duration.zero,
          reason: 'reduced motion must zero the ANIMATION extent',
        );

        region.report('C', at: Duration.zero);
        await tester.pump();

        expect(
          region.announcements,
          ['C'],
          reason:
              'the semantics feedback itself must NOT be gated on reduced '
              'motion',
        );
        expect(find.bySemanticsLabel('C'), findsOneWidget);
      },
    );
  });
}
