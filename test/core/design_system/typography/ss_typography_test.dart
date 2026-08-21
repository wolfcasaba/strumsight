import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';

void main() {
  group('SsTypography', () {
    test(
      'provides every Chapter 13 scale token in every design-system theme',
      () {
        for (final theme in <ThemeData>[
          SsDarkTheme.data(),
          SsLightTheme.data(),
          SsHighContrastTheme.data(),
        ]) {
          final typography = theme.extension<SsTypography>();

          expect(typography, isNotNull);
          expect(typography!.displayChord.fontSize, 80);
          expect(typography.displayScore.fontSize, 56);
          expect(typography.headlineLarge.fontSize, 32);
          expect(typography.headlineMedium.fontSize, 26);
          expect(typography.titleLarge.fontSize, 22);
          expect(typography.titleMedium.fontSize, 18);
          expect(typography.bodyLarge.fontSize, 16);
          expect(typography.bodyMedium.fontSize, 14);
          expect(typography.labelLarge.fontSize, 14);
          expect(typography.metricLarge.fontSize, 28);
          expect(typography.metricMedium.fontSize, 18);
          expect(typography.metricSmall.fontSize, 12);
        }
      },
    );

    test('assigns Poppins to content and tabular Montserrat to metrics', () {
      final typography = SsDarkTheme.data().extension<SsTypography>()!;

      expect(typography.displayChord.fontFamily, SsTypography.poppinsFamily);
      expect(typography.headlineLarge.fontFamily, SsTypography.poppinsFamily);
      expect(typography.bodyLarge.fontFamily, SsTypography.poppinsFamily);
      expect(typography.metricLarge.fontFamily, SsTypography.montserratFamily);
      expect(
        typography.metricLarge.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      expect(
        typography.metricMedium.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      expect(
        typography.metricSmall.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });

    test(
      'adapts the display chord base size to the viewport without capping text scale',
      () {
        final typography = SsDarkTheme.data().extension<SsTypography>()!;

        expect(
          typography.displayChordForViewport(viewportWidth: 320).fontSize,
          80,
        );
        expect(
          typography.displayChordForViewport(viewportWidth: 840).fontSize,
          128,
        );
      },
    );

    test(
      'keeps metric values and units together with a non-breaking space',
      () {
        expect(SsTypography.metricLabel(120, 'BPM'), '120\u00a0BPM');
      },
    );

    test(
      'new typography production sources do not introduce ad hoc TextStyle',
      () {
        for (final path in const [
          'lib/core/design_system/components/music/ss_chord_hero_text.dart',
        ]) {
          final source = File(path).readAsStringSync();
          expect(source, isNot(contains('TextStyle(')));
        }
      },
    );
  });

  testWidgets(
    'chord hero keeps the full label at a platform 200 percent text scale',
    (tester) async {
      await _pumpChordHero(tester, width: 1200, textScale: 1);
      final baselineHeight = tester.getSize(find.byType(FittedBox)).height;

      await _pumpChordHero(tester, width: 1200, textScale: 2);
      final scaledHeight = tester.getSize(find.byType(FittedBox)).height;
      final chordText = tester.widget<Text>(find.text('Cmaj7#11'));
      final chordRichText = tester.widget<RichText>(find.byType(RichText));
      final heroRect = tester.getRect(find.byType(SsChordHeroText));
      final textRect = tester.getRect(find.text('Cmaj7#11'));

      expect(scaledHeight, greaterThan(baselineHeight));
      expect(chordRichText.textScaler.scale(1), 2);
      expect(chordText.overflow, isNot(TextOverflow.ellipsis));
      expect(find.text('Cmaj7#11'), findsOneWidget);
      expect(heroRect.left, lessThanOrEqualTo(textRect.left));
      expect(heroRect.right, greaterThanOrEqualTo(textRect.right));
      expect(heroRect.top, lessThanOrEqualTo(textRect.top));
      expect(heroRect.bottom, greaterThanOrEqualTo(textRect.bottom));

      await _pumpChordHero(tester, width: 120, textScale: 2);
      expect(tester.takeException(), isNull);
      expect(find.text('Cmaj7#11'), findsOneWidget);
    },
  );
}

Future<void> _pumpChordHero(
  WidgetTester tester, {
  required double width,
  required double textScale,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: SsDarkTheme.data(),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 400),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: SizedBox(
            width: width,
            child: const SsChordHeroText(chordName: 'Cmaj7#11'),
          ),
        ),
      ),
    ),
  );
}
