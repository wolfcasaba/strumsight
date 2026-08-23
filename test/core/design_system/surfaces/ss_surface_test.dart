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

    for (final fixture in _canonicalSurfaceFixtures) {
      test('${fixture.name} pins canonical background, border, and shadow', () {
        for (final elevation in SsElevation.values) {
          final expected = fixture.styles[elevation]!;
          final actual = elevation.resolve(fixture.theme);

          expect(
            actual.background.toARGB32(),
            expected.backgroundArgb,
            reason: '$elevation',
          );
          expect(
            actual.border.toARGB32(),
            expected.borderArgb,
            reason: '$elevation',
          );
          expect(
            actual.borderWidth,
            expected.borderWidth,
            reason: '$elevation',
          );
          expect(
            actual.shadowColor.toARGB32(),
            expected.shadowArgb,
            reason: '$elevation',
          );
          expect(
            actual.shadowElevation,
            expected.shadowElevation,
            reason: '$elevation',
          );
        }
      });
    }

    test('base resolves its exact semantic surface token', () {
      final theme = _theme(
        brightness: Brightness.dark,
        colors: _colors(
          surface: const Color(0xff010203),
          surfaceRaised: const Color(0xff040506),
          border: const Color(0xff070809),
          borderStrong: const Color(0xff0a0b0c),
        ),
      );

      expect(
        SsElevation.base.resolve(theme).background,
        const Color(0xff010203),
      );
    });

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
      'high contrast selects borderStrong and no decorative shadow above base',
      () {
        final border = const Color(0xff101112);
        final borderStrong = const Color(0xffb0b1b2);
        final theme = _theme(
          brightness: Brightness.dark,
          colors: _colors(
            surface: const Color(0xff111213),
            surfaceRaised: const Color(0xff212223),
            border: border,
            borderStrong: borderStrong,
          ),
          highContrast: true,
        );

        for (final elevation in SsElevation.values.skip(1)) {
          final style = elevation.resolve(theme);
          expect(style.border, borderStrong);
          expect(style.border, isNot(border));
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

      final cardMaterials = find.descendant(
        of: find.byType(SsCard),
        matching: find.byType(Material),
      );
      expect(cardMaterials, findsOneWidget);
      final cardMaterial = tester.widget<Material>(cardMaterials);
      final heroMaterial = tester.widget<Material>(
        find.descendant(
          of: find.byType(SsHeroCard),
          matching: find.byType(Material),
        ),
      );

      expect(_radiusOf(cardMaterial), SsRadius.md);
      expect(_radiusOf(heroMaterial), SsRadius.lg);
    });

    testWidgets('card composes exactly one material surface', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: SsDarkTheme.data(),
          home: const Scaffold(body: SsCard(child: SizedBox())),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(SsCard),
          matching: find.byType(Material),
        ),
        findsOneWidget,
      );
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

final List<_SurfaceFixture> _canonicalSurfaceFixtures = <_SurfaceFixture>[
  _SurfaceFixture(
    name: 'dark',
    theme: _theme(
      brightness: Brightness.dark,
      colors: _colors(
        surface: const Color(0xff101112),
        surfaceRaised: const Color(0xff202122),
        border: const Color(0xff303132),
        borderStrong: const Color(0xff606162),
      ),
    ),
    styles: <SsElevation, _ExpectedSurfaceStyle>{
      SsElevation.base: _style(0xff101112, 0xff303132, 0),
      SsElevation.raised: _style(0xff28292a, 0xff323334, 0),
      SsElevation.overlay: _style(0xff313233, 0xff343536, 0),
      SsElevation.modal: _style(0xff393a3b, 0xff363738, 0),
    },
  ),
  _SurfaceFixture(
    name: 'light',
    theme: _theme(
      brightness: Brightness.light,
      colors: _colors(
        surface: const Color(0xfffefdfc),
        surfaceRaised: const Color(0xfff0efee),
        border: const Color(0xffa0a1a2),
        borderStrong: const Color(0xff505152),
      ),
    ),
    styles: <SsElevation, _ExpectedSurfaceStyle>{
      SsElevation.base: _style(0xfffefdfc, 0xffa0a1a2, 0),
      SsElevation.raised: _style(0xffefeeed, 0xff9d9e9f, 1),
      SsElevation.overlay: _style(0xffefeeed, 0xff9a9b9c, 2),
      SsElevation.modal: _style(0xffeeedec, 0xff969798, 4),
    },
  ),
  _SurfaceFixture(
    name: 'high contrast',
    theme: _theme(
      brightness: Brightness.dark,
      colors: _colors(
        surface: const Color(0xff111213),
        surfaceRaised: const Color(0xff212223),
        border: const Color(0xff101112),
        borderStrong: const Color(0xffb0b1b2),
      ),
      highContrast: true,
    ),
    styles: <SsElevation, _ExpectedSurfaceStyle>{
      SsElevation.base: _style(0xff111213, 0xff101112, 0, borderWidth: 2),
      SsElevation.raised: _style(0xff292a2b, 0xffb0b1b2, 0, borderWidth: 2),
      SsElevation.overlay: _style(0xff323334, 0xffb0b1b2, 0, borderWidth: 2),
      SsElevation.modal: _style(0xff3a3b3c, 0xffb0b1b2, 0, borderWidth: 2),
    },
  ),
];

_ExpectedSurfaceStyle _style(
  int background,
  int border,
  double shadowElevation, {
  double borderWidth = 1,
}) => _ExpectedSurfaceStyle(
  backgroundArgb: background,
  borderArgb: border,
  borderWidth: borderWidth,
  shadowArgb: 0x29000000,
  shadowElevation: shadowElevation,
);

ThemeData _theme({
  required Brightness brightness,
  required SsColorScheme colors,
  bool highContrast = false,
}) => ThemeData(
  brightness: brightness,
  extensions: <ThemeExtension<Object?>>[
    colors,
    SsThemeBehavior(
      borderWidth: highContrast ? 2 : 1,
      focusRingWidth: highContrast ? 4 : 2,
      surfaceOpacity: 1,
      decorativeEffectsEnabled: !highContrast,
    ),
  ],
);

SsColorScheme _colors({
  required Color surface,
  required Color surfaceRaised,
  required Color border,
  required Color borderStrong,
}) => SsColorScheme(
  brand: const Color(0xff000001),
  brandStrong: const Color(0xff000002),
  onBrand: const Color(0xff000003),
  canvas: const Color(0xffe0dfde),
  surface: surface,
  surfaceRaised: surfaceRaised,
  surfaceSunken: const Color(0xff000004),
  border: border,
  borderStrong: borderStrong,
  textPrimary: const Color(0xfff0f1f2),
  textSecondary: const Color(0xff000005),
  textDisabled: const Color(0xff000006),
  success: const Color(0xff000007),
  warning: const Color(0xff000008),
  danger: const Color(0xff000009),
  info: const Color(0xff00000a),
  confidenceHigh: const Color(0xff00000b),
  confidenceMedium: const Color(0xff00000c),
  confidenceLow: const Color(0xff00000d),
  offline: const Color(0xff00000e),
  localAi: const Color(0xff00000f),
  cloudAi: const Color(0xff000010),
  syncPending: const Color(0xff000011),
);

final class _SurfaceFixture {
  const _SurfaceFixture({
    required this.name,
    required this.theme,
    required this.styles,
  });

  final String name;
  final ThemeData theme;
  final Map<SsElevation, _ExpectedSurfaceStyle> styles;
}

final class _ExpectedSurfaceStyle {
  const _ExpectedSurfaceStyle({
    required this.backgroundArgb,
    required this.borderArgb,
    required this.borderWidth,
    required this.shadowArgb,
    required this.shadowElevation,
  });

  final int backgroundArgb;
  final int borderArgb;
  final double borderWidth;
  final int shadowArgb;
  final double shadowElevation;
}
