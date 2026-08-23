import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';

void main() {
  group('interactive icon semantics (A2) — the caller-supplied strings', () {
    testWidgets(
      'exposes the caller-supplied semantic label and tooltip verbatim',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SsIcon.interactive(
                  name: SsGuitarGlyphName.downstrum.name,
                  semanticLabel: 'Play the down strum',
                  tooltip: 'Preview the down strum sound',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final labelMatches = find.bySemanticsLabel('Play the down strum');
        final tooltipMatches = find.byTooltip('Preview the down strum sound');
        handle.dispose();

        expect(labelMatches, findsOneWidget);
        expect(tooltipMatches, findsOneWidget);
      },
    );

    test('rejects an empty semantic label', () {
      expect(
        () => SsIcon.interactive(
          name: SsGuitarGlyphName.capo.name,
          semanticLabel: '',
          tooltip: 'Capo',
        ),
        throwsArgumentError,
      );
    });

    test('rejects an empty tooltip', () {
      expect(
        () => SsIcon.interactive(
          name: SsGuitarGlyphName.capo.name,
          semanticLabel: 'Capo',
          tooltip: '',
        ),
        throwsArgumentError,
      );
    });
  });

  group('decorative icon semantics (A3) — excluded from the tree', () {
    testWidgets('adds no label to the semantics tree', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SsIcon.decorative(name: SsGuitarGlyphName.metronome.name),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final anyLabelled = find.bySemanticsLabel(RegExp('.+'));
      handle.dispose();

      expect(anyLabelled, findsNothing);
    });
  });
}
