import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';

/// Records every draw call a [SsGuitarGlyphPainter] issues instead of
/// rasterizing, so a test can inspect the [Paint] each call used — the only
/// way to catch a glyph substituting a hand-picked `strokeWidth` instead of
/// deriving it from the shared ratio (A9). `noSuchMethod` forwards every
/// [Canvas] member this cell does not care about (transforms, clips, layers,
/// text, images) to a no-op; only the shape-drawing calls a glyph actually
/// uses are overridden and recorded.
class _RecordingCanvas implements Canvas {
  final List<Paint> paints = [];

  /// One string per draw call — shape, geometry and paint style — so a test
  /// can compare two glyphs' full call sequences for equality (A8/F3).
  final List<String> callSignatures = [];

  void _record(String signature, Paint paint) {
    paints.add(paint);
    callSignatures.add(signature);
  }

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) =>
      _record('line:$p1->$p2:${paint.style}:${paint.strokeWidth}', paint);

  @override
  void drawPath(Path path, Paint paint) =>
      _record('path:${path.getBounds()}:${paint.style}', paint);

  @override
  void drawRRect(RRect rrect, Paint paint) =>
      _record('rrect:$rrect:${paint.style}', paint);

  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      _record('circle:$c:$radius:${paint.style}', paint);

  @override
  void drawArc(
    Rect rect,
    double startAngle,
    double sweepAngle,
    bool useCenter,
    Paint paint,
  ) => _record(
    'arc:$rect:$startAngle:$sweepAngle:$useCenter:${paint.style}',
    paint,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

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

  group(
    'guitar glyphs (A9) — every painted stroke derives from the shared ratio',
    () {
      // The only two stroke-width ratios the implementation paints with: the
      // full shared width (every primary stroke) and 0.6x (the intentionally
      // thinner hammer-on/pull-off hollow note-head outline, ss_guitar_glyphs
      // .dart:179,205). A hand-picked absolute value — e.g. the 7.5 injected
      // by the round-1 review — matches neither ratio at any of the three
      // contract sizes and fails this cell.
      final allowedStrokeRatios = <double>{1.0, 0.6};

      test(
        'every recorded PaintingStyle.stroke draw call uses an allowed ratio '
        'of the shared stroke width',
        () {
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
              final canvas = _RecordingCanvas();
              painter.paint(canvas, Size.square(size));

              final strokePaints = canvas.paints.where(
                (paint) => paint.style == PaintingStyle.stroke,
              );
              expect(
                strokePaints,
                isNotEmpty,
                reason: '$name at $size dp must paint at least one stroke',
              );

              for (final paint in strokePaints) {
                // Paint.strokeWidth round-trips through a native float32
                // field, so an exact double comparison would spuriously
                // fail even for a correctly-derived width — the tolerance
                // only needs to absorb that precision loss, not a real
                // mismatch (a hand-picked width like the round-1 review's
                // 7.5 misses by orders of magnitude more than this).
                final ratio = paint.strokeWidth / painter.strokeWidth;
                final matchesAllowedRatio = allowedStrokeRatios.any(
                  (allowed) => (ratio - allowed).abs() < 1e-5,
                );
                expect(
                  matchesAllowedRatio,
                  isTrue,
                  reason:
                      '$name at $size dp painted a stroke of width '
                      '${paint.strokeWidth}, which is not one of the allowed '
                      'ratios $allowedStrokeRatios of the shared strokeWidth '
                      '(${painter.strokeWidth})',
                );
              }
            }
          }
        },
      );
    },
  );

  group('guitar glyphs (A8) — the full set renders in every theme', () {
    for (final entry in <String, ThemeData>{
      'dark': SsDarkTheme.data(),
      'light': SsLightTheme.data(),
      'highContrast': SsHighContrastTheme.data(),
    }.entries) {
      final themeLabel = entry.key;
      final theme = entry.value;

      testWidgets('all fourteen glyphs render under the $themeLabel theme '
          'without throwing', (tester) async {
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
      });
    }

    test(
      'every glyph paints a draw-call sequence distinct from all others',
      () {
        final signatures = <String>[
          for (final name in SsGuitarGlyphName.values)
            () {
              final painter = SsGuitarGlyphs.painterFor(
                name,
                color: Colors.black,
                size: SsIconSize.base,
              );
              final canvas = _RecordingCanvas();
              painter.paint(canvas, const Size.square(SsIconSize.base));
              return canvas.callSignatures.join('|');
            }(),
        ];

        expect(
          signatures.toSet().length,
          signatures.length,
          reason:
              'two or more of the fourteen glyphs painted the exact same '
              'draw-call sequence — the gallery would render duplicate '
              'marks under different names',
        );
      },
    );
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
