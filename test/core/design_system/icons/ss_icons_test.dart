import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';

void main() {
  group('SsIconSize (A5) — the three mandatory Stage-threshold cells', () {
    test('below the threshold: 24 dp is rejected in a Stage context', () {
      expect(SsIconSize.isValidForStage(SsIconSize.base), isFalse);
      expect(SsIconSize.resolveForStage(SsIconSize.base), SsIconSize.stageMin);
    });

    test('on the threshold: 32 dp is accepted (inclusive lower bound)', () {
      expect(SsIconSize.isValidForStage(SsIconSize.stageMin), isTrue);
      expect(
        SsIconSize.resolveForStage(SsIconSize.stageMin),
        SsIconSize.stageMin,
      );
    });

    test('above the threshold: 48 dp is accepted (inclusive upper bound)', () {
      expect(SsIconSize.isValidForStage(SsIconSize.stageMax), isTrue);
      expect(
        SsIconSize.resolveForStage(SsIconSize.stageMax),
        SsIconSize.stageMax,
      );
    });

    testWidgets('the real widget path never lets the base size reach Stage', (
      tester,
    ) async {
      const iconKey = Key('stage_icon');
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SsIcon.decorative(
              key: iconKey,
              name: SsGuitarGlyphName.downstrum.name,
              size: SsIconSize.base,
              stage: true,
            ),
          ),
        ),
      );
      await tester.pump();

      final box = tester.renderObject<RenderBox>(
        find.descendant(
          of: find.byKey(iconKey),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(box.size, const Size.square(SsIconSize.stageMin));
    });
  });

  group('guitar glyphs (A9) — one named stroke ratio for every glyph', () {
    test('every glyph reports the shared, size-derived stroke width', () {
      for (final size in [
        SsIconSize.base,
        SsIconSize.stageMin,
        SsIconSize.stageMax,
      ]) {
        for (final name in SsGuitarGlyphName.values) {
          final painter = SsGuitarGlyphs.painterFor(
            name,
            color: Colors.black,
            size: size,
          );
          expect(
            painter.strokeWidth,
            SsGuitarGlyphs.strokeWidthFor(size),
            reason:
                '$name at $size dp must derive its stroke from the '
                'shared ratio',
          );
        }
      }
    });
  });

  group('guitar glyphs (A8) — the full set renders in every theme', () {
    for (final theme in [
      SsDarkTheme.data(),
      SsLightTheme.data(),
      SsHighContrastTheme.data(),
    ]) {
      testWidgets(
        'all fourteen glyphs render under ${theme.brightness} without '
        'throwing',
        (tester) async {
          const galleryKey = Key('gallery');
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Wrap(
                  key: galleryKey,
                  children: [
                    for (final name in SsGuitarGlyphName.values)
                      SsIcon.decorative(name: name.name),
                  ],
                ),
              ),
            ),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(
            find.descendant(
              of: find.byKey(galleryKey),
              matching: find.byType(CustomPaint),
            ),
            findsNWidgets(SsGuitarGlyphName.values.length),
          );
        },
      );
    }
  });

  group('strum direction (A1) — painted, never a raw arrow character', () {
    testWidgets('downstrum/upstrum paint through SsGuitarGlyphPainter', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              SsIcon.decorative(
                key: const Key('down'),
                name: SsGuitarGlyphName.downstrum.name,
              ),
              SsIcon.decorative(
                key: const Key('up'),
                name: SsGuitarGlyphName.upstrum.name,
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('↓'), findsNothing);
      expect(find.textContaining('↑'), findsNothing);

      final downPaint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byKey(const Key('down')),
          matching: find.byType(CustomPaint),
        ),
      );
      final upPaint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byKey(const Key('up')),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(downPaint.painter, isA<SsGuitarGlyphPainter>());
      expect(upPaint.painter, isA<SsGuitarGlyphPainter>());
      expect(
        SsIcons.resolveByName(SsGuitarGlyphName.downstrum.name),
        isA<SsResolvedGuitarGlyph>(),
      );
    });
  });

  group('missing-glyph fallback (A4)', () {
    test('an unresolved name reports isFallback', () {
      expect(SsIcons.resolveByName('not-a-real-glyph').isFallback, isTrue);
      expect(
        SsIcons.resolveByName(SsGuitarGlyphName.capo.name).isFallback,
        isFalse,
      );
    });

    testWidgets('an unresolved name renders a visible, non-zero-size mark', (
      tester,
    ) async {
      const iconKey = Key('fallback_icon');
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SsIcon.decorative(key: iconKey, name: 'not-a-real-glyph'),
          ),
        ),
      );
      await tester.pump();

      final box = tester.renderObject<RenderBox>(
        find.descendant(
          of: find.byKey(iconKey),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(box.size.width, greaterThan(0));
      expect(box.size.height, greaterThan(0));
    });
  });
}
