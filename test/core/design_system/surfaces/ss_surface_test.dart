import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';

void main() {
  final themes = <String, ThemeData>{
    'dark': SsDarkTheme.data(),
    'light': SsLightTheme.data(),
    'high contrast': SsHighContrastTheme.data(),
  };

  group('SsElevation visual contract', () {
    test('surface radius choices are backed by the radius tokens', () {
      expect(SsSurfaceRadius.md.value, SsRadius.md);
      expect(SsSurfaceRadius.lg.value, SsRadius.lg);
    });

    test('keeps the closed base, raised, overlay, modal hierarchy', () {
      expect(SsElevation.values, <SsElevation>[
        SsElevation.base,
        SsElevation.raised,
        SsElevation.overlay,
        SsElevation.modal,
      ]);
    });

    for (final entry in themes.entries) {
      test('${entry.key} resolves every surface level deterministically', () {
        final first = <SsElevation, SsSurfaceStyle>{
          for (final elevation in SsElevation.values)
            elevation: elevation.resolve(entry.value),
        };
        final second = <SsElevation, SsSurfaceStyle>{
          for (final elevation in SsElevation.values)
            elevation: elevation.resolve(entry.value),
        };

        expect(first, second);
        expect(
          first.values.map((style) => style.background).toSet().length,
          SsElevation.values.length,
        );
      });
    }

    test(
      'surface level controls its resolved background, border, and shadow',
      () {
        final theme = SsDarkTheme.data();
        final base = SsElevation.base.resolve(theme);
        final raised = SsElevation.raised.resolve(theme);

        expect(raised.background, isNot(base.background));
        expect(raised.border, isNotNull);
        expect(raised.shadowElevation, isNotNull);
      },
    );

    test('dark studio uses lightness and border rather than a shadow', () {
      final dark = SsDarkTheme.data();
      final base = SsElevation.base.resolve(dark);
      final raised = SsElevation.raised.resolve(dark);

      expect(raised.background, isNot(base.background));
      expect(raised.border, isNot(base.border));
      expect(raised.shadowElevation, 0);
    });

    test('light surfaces use only short centralized elevated shadows', () {
      final light = SsLightTheme.data();
      final raised = SsElevation.raised.resolve(light);
      final modal = SsElevation.modal.resolve(light);

      expect(raised.shadowElevation, greaterThan(0));
      expect(modal.shadowElevation, greaterThan(raised.shadowElevation));
      expect(modal.shadowElevation, lessThanOrEqualTo(4));
    });

    test(
      'high contrast uses borderStrong and no decorative shadow above base',
      () {
        final theme = SsHighContrastTheme.data();
        final colors = theme.extension<SsColorScheme>()!;

        for (final elevation in SsElevation.values.skip(1)) {
          final style = elevation.resolve(theme);
          expect(style.border, colors.borderStrong);
          expect(style.shadowElevation, 0);
        }
      },
    );
  });

  group('SsSurface composition', () {
    testWidgets('all themes render every level without an exception', (
      tester,
    ) async {
      for (final entry in themes.entries) {
        await tester.pumpWidget(
          MaterialApp(
            theme: entry.value,
            home: Scaffold(
              body: Column(
                children: [
                  for (final elevation in SsElevation.values)
                    SsSurface(
                      elevation: elevation,
                      child: Text('${entry.key} $elevation'),
                    ),
                ],
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(
          find.byType(SsSurface),
          findsNWidgets(SsElevation.values.length),
        );
      }
    });

    testWidgets(
      'named safe-area mode applies one system inset for nested surfaces',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: SsDarkTheme.data(),
            home: MediaQuery(
              data: const MediaQueryData(padding: EdgeInsets.only(top: 24)),
              child: Scaffold(
                body: SsSurface(
                  safeArea: true,
                  child: SsSurface(child: const Text('Nested content')),
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(SafeArea), findsOneWidget);
        expect(find.text('Nested content'), findsOneWidget);
      },
    );

    testWidgets('nested surfaces remain usable at 2.0 text scale', (
      tester,
    ) async {
      const title = 'A következő gyakorlatszakasz részletes összefoglalója';
      await tester.pumpWidget(
        MaterialApp(
          theme: SsDarkTheme.data(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 800),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: 320,
                  child: SsSection(
                    title: title,
                    child: SsCard(
                      child: SsHeroCard(
                        child: const Text(title, softWrap: true),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text(title), findsNWidgets(2));
    });

    testWidgets('card and hero card use their required radius tokens', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: SsDarkTheme.data(),
          home: const Scaffold(
            body: Column(
              children: [
                SsCard(child: SizedBox()),
                SsHeroCard(child: SizedBox()),
              ],
            ),
          ),
        ),
      );

      final cardMaterial = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(SsCard),
              matching: find.byType(Material),
            )
            .last,
      );
      final heroMaterial = tester.widget<Material>(
        find.descendant(
          of: find.byType(SsHeroCard),
          matching: find.byType(Material),
        ),
      );

      expect(_radiusOf(cardMaterial), SsRadius.md);
      expect(_radiusOf(heroMaterial), SsRadius.lg);
    });

    testWidgets('section composes title and content without a card layer', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: SsDarkTheme.data(),
          home: const Scaffold(
            body: SsSection(title: 'Title', child: SizedBox()),
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(SsSection),
          matching: find.byType(Card),
        ),
        findsNothing,
      );
    });

    test('hero stays caller-fed and does not reach feature state', () {
      final source = File(
        'lib/core/design_system/components/surfaces/ss_hero_card.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('/features/')));
      expect(source, isNot(contains('riverpod')));
      expect(source, isNot(contains('Provider')));
    });
  });
}

double _radiusOf(Material material) {
  final shape = material.shape! as RoundedRectangleBorder;
  final borderRadius = shape.borderRadius as BorderRadius;
  return borderRadius.topLeft.x;
}
