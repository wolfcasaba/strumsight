import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../../tool/ui_contrast_check.dart';

Widget _wrap(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? SsLightTheme.data(),
  home: Scaffold(body: Center(child: child)),
);

const _boxKey = Key('probe-box');

Widget _wrapConstrained(
  Widget child, {
  required double width,
  required double textScale,
  ThemeData? theme,
}) => MaterialApp(
  theme: theme ?? SsLightTheme.data(),
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(400, 800),
      textScaler: TextScaler.linear(textScale),
    ),
    child: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(key: _boxKey, width: width, child: child),
      ),
    ),
  ),
);

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  final huL10n = lookupAppLocalizations(const Locale('hu'));

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

    for (final kind in SsProvenanceKind.values) {
      testWidgets(
        'SsInsightCard ALWAYS carries a provenance badge — there is no way '
        'to construct one without it (provenance kind: $kind)',
        (tester) async {
          await tester.pumpWidget(
            _wrap(
              SsInsightCard(
                l10n: l10n,
                title: 'Insight title',
                message: 'Insight message',
                provenance: kind,
              ),
            ),
          );

          expect(find.byType(SsProvenanceBadge), findsOneWidget);
        },
      );
    }
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

  group('fix1/F1+F2 — every badge label meets the project 4.5:1 text-contrast '
      'floor, against the surface it actually renders on, in every theme', () {
    final themes = <String, ThemeData>{
      'light': SsLightTheme.data(),
      'dark': SsDarkTheme.data(),
      'highContrast': SsHighContrastTheme.data(),
    };

    for (final themeEntry in themes.entries) {
      final background = SsElevation.raised
          .resolve(themeEntry.value)
          .background
          .toARGB32();

      for (final kind in SsStatusBadgeKind.values) {
        testWidgets(
          '${themeEntry.key} — SsStatusBadgeKind.$kind label meets 4.5:1',
          (tester) async {
            await tester.pumpWidget(
              _wrap(
                SsStatusBadge(l10n: l10n, kind: kind),
                theme: themeEntry.value,
              ),
            );

            final foreground = tester
                .widget<Text>(find.byType(Text))
                .style!
                .color!
                .toARGB32();

            expect(
              ContrastCheck.meetsTextContrast(foreground, background),
              isTrue,
              reason:
                  '${themeEntry.key}/$kind ratio='
                  '${ContrastCheck.contrastRatio(foreground, background)}',
            );
          },
        );
      }

      for (final kind in SsProvenanceKind.values) {
        testWidgets(
          '${themeEntry.key} — SsProvenanceKind.$kind label meets 4.5:1',
          (tester) async {
            await tester.pumpWidget(
              _wrap(
                SsProvenanceBadge(l10n: l10n, kind: kind),
                theme: themeEntry.value,
              ),
            );

            final foreground = tester
                .widget<Text>(find.byType(Text))
                .style!
                .color!
                .toARGB32();

            expect(
              ContrastCheck.meetsTextContrast(foreground, background),
              isTrue,
              reason:
                  '${themeEntry.key}/$kind ratio='
                  '${ContrastCheck.contrastRatio(foreground, background)}',
            );
          },
        );
      }
    }
  });

  group('fix1/F3 — a badge label never overflows the surface it is '
      'constrained to, at any supported text scale', () {
    for (final width in <double>[320, 200]) {
      for (final textScale in <double>[1, 1.3, 2, 2.5]) {
        testWidgets(
          'SsStatusBadge (syncPending, hu) at width=$width scale=$textScale',
          (tester) async {
            await tester.pumpWidget(
              _wrapConstrained(
                SsStatusBadge(
                  l10n: huL10n,
                  kind: SsStatusBadgeKind.syncPending,
                ),
                width: width,
                textScale: textScale,
              ),
            );

            expect(tester.takeException(), isNull);

            final boxRect = tester.getRect(find.byKey(_boxKey));
            final textRect = tester.getRect(find.byType(Text));

            expect(boxRect.width, closeTo(width, 0.5));
            expect(
              textRect.right,
              lessThanOrEqualTo(boxRect.right + 0.5),
              reason: 'label painted box escaped the constrained container',
            );
          },
        );

        testWidgets(
          'SsProvenanceBadge (local, hu) at width=$width scale=$textScale',
          (tester) async {
            await tester.pumpWidget(
              _wrapConstrained(
                SsProvenanceBadge(l10n: huL10n, kind: SsProvenanceKind.local),
                width: width,
                textScale: textScale,
              ),
            );

            expect(tester.takeException(), isNull);

            final boxRect = tester.getRect(find.byKey(_boxKey));
            final textRect = tester.getRect(find.byType(Text));

            expect(boxRect.width, closeTo(width, 0.5));
            expect(
              textRect.right,
              lessThanOrEqualTo(boxRect.right + 0.5),
              reason: 'label painted box escaped the constrained container',
            );
          },
        );
      }
    }
  });
}
