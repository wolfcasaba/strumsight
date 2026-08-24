import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: SsLightTheme.data(),
  home: Scaffold(body: Center(child: child)),
);

/// A minimal controlled-loading harness: [onPressed] flips [loading] to
/// true synchronously (mirroring how a real caller wires an AsyncNotifier),
/// and counts how many times it actually fired.
final class _LoadingHarness extends StatefulWidget {
  const _LoadingHarness({required this.onTapCount});

  final ValueChanged<int> onTapCount;

  @override
  State<_LoadingHarness> createState() => _LoadingHarnessState();
}

class _LoadingHarnessState extends State<_LoadingHarness> {
  var _loading = false;
  var _tapCount = 0;

  @override
  Widget build(BuildContext context) {
    return SsButton(
      label: 'Submit',
      loading: _loading,
      onPressed: () {
        setState(() => _loading = true);
        _tapCount++;
        widget.onTapCount(_tapCount);
      },
    );
  }
}

void main() {
  group('A2 — the loading button never changes size and blocks re-entry', () {
    testWidgets('reports the same size loading or not, for the same label', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(SsButton(label: 'Save changes', onPressed: () {})),
      );
      final idleSize = tester.getSize(find.byType(SsButton));

      await tester.pumpWidget(
        _wrap(SsButton(label: 'Save changes', onPressed: () {}, loading: true)),
      );
      final loadingSize = tester.getSize(find.byType(SsButton));

      expect(loadingSize, idleSize);
    });

    testWidgets('a loading button ignores taps entirely', (tester) async {
      var tapCount = 0;
      await tester.pumpWidget(
        _wrap(
          SsButton(
            label: 'Save changes',
            loading: true,
            onPressed: () => tapCount++,
          ),
        ),
      );

      await tester.tap(find.byType(SsButton));
      await tester.pump();

      expect(tapCount, 0);
    });

    testWidgets('a fast second tap right after the first — once the caller has '
        'flipped loading to true — never resubmits (§5.2)', (tester) async {
      var lastTapCount = 0;
      await tester.pumpWidget(
        _wrap(_LoadingHarness(onTapCount: (count) => lastTapCount = count)),
      );

      await tester.tap(find.byType(SsButton));
      await tester.pump();
      expect(lastTapCount, 1);
      // The button is now disabled (loading == true); a second tap must
      // land on a disabled control and NOT resubmit.
      await tester.tap(find.byType(SsButton), warnIfMissed: false);
      await tester.pump();

      expect(lastTapCount, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group(
    'A5 — the destructive button differs in semantics, not just colour',
    () {
      testWidgets(
        'merges destructiveSemanticHint onto the SAME node as the label',
        (tester) async {
          final handle = tester.ensureSemantics();
          await tester.pumpWidget(
            _wrap(
              SsButton(
                label: 'Delete song',
                variant: SsButtonVariant.destructive,
                destructiveSemanticHint: 'This cannot be undone',
                onPressed: () {},
              ),
            ),
          );
          await tester.pumpAndSettle();

          final data = tester
              .getSemantics(find.bySemanticsLabel('Delete song').first)
              .getSemanticsData();
          handle.dispose();

          expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
          expect(data.hint, 'This cannot be undone');
          expect(data.label, contains('Delete song'));
        },
      );

      testWidgets(
        'non-destructive variants carry no hint at all — colour is the only '
        'difference otherwise',
        (tester) async {
          final handle = tester.ensureSemantics();
          await tester.pumpWidget(
            _wrap(SsButton(label: 'Save', onPressed: () {})),
          );
          await tester.pumpAndSettle();

          final data = tester
              .getSemantics(find.bySemanticsLabel('Save').first)
              .getSemanticsData();
          handle.dispose();

          expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
          expect(data.hint, isEmpty);
        },
      );

      test('requires a non-null hint for the destructive variant', () {
        expect(
          () => SsButton(
            label: 'Delete',
            variant: SsButtonVariant.destructive,
            onPressed: () {},
          ),
          throwsA(isA<AssertionError>()),
        );
      });
    },
  );

  group('A9 — SsIconButton is a button node, never an image node', () {
    testWidgets(
      'exposes exactly one tooltip and a button-flagged, non-image node',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _wrap(
            SsIconButton(
              iconName: 'close',
              semanticLabel: 'Close',
              tooltip: 'Close the dialog',
              onPressed: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        final data = tester
            .getSemantics(find.bySemanticsLabel('Close').first)
            .getSemanticsData();
        final tooltipCount = find
            .byTooltip('Close the dialog')
            .evaluate()
            .length;
        handle.dispose();

        expect(tooltipCount, 1);
        expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
        expect(data.hasFlag(SemanticsFlag.isImage), isFalse);
        expect(data.label, 'Close');
      },
    );

    test('rejects an empty semantic label', () {
      expect(
        () => SsIconButton(
          iconName: 'close',
          semanticLabel: '',
          tooltip: 'Close',
          onPressed: () {},
        ),
        throwsArgumentError,
      );
    });

    test('rejects an empty tooltip', () {
      expect(
        () => SsIconButton(
          iconName: 'close',
          semanticLabel: 'Close',
          tooltip: '',
          onPressed: () {},
        ),
        throwsArgumentError,
      );
    });
  });
}
