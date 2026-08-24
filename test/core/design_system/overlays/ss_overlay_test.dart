import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';

const _openDialogKey = ValueKey('open-dialog');
const _openSheetKey = ValueKey('open-sheet');
const _backgroundLabel = 'background probe';

/// A background probe (its own semantics label) plus a focus-tracked button
/// that opens an [SsDialog] — the harness for the host-level guarantees
/// (A4/A5/A7) that do not depend on which surface (dialog vs. sheet) is on
/// top, since [SsOverlayHost] backs all of them the same way.
Widget _dialogHarness({
  required FocusNode openFocusNode,
  required VoidCallback onConfirm,
}) {
  return MaterialApp(
    theme: SsLightTheme.data(),
    home: Builder(
      builder: (context) {
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  label: _backgroundLabel,
                  container: true,
                  child: const Text('Background content'),
                ),
                ElevatedButton(
                  key: _openDialogKey,
                  focusNode: openFocusNode,
                  onPressed: () => SsDialog.show(
                    context,
                    title: 'Delete this session?',
                    message: 'The recording will be removed.',
                    confirmLabel: 'Delete session',
                    cancelLabel: 'Cancel',
                    onConfirm: onConfirm,
                  ),
                  child: const Text('Open'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// A width-adaptive harness that opens an [SsConfirmationSheet] — used by
/// the A8 breakpoint cells.
Widget _sheetHarness() {
  return MaterialApp(
    theme: SsLightTheme.data(),
    home: Builder(
      builder: (context) {
        return Scaffold(
          body: Center(
            child: ElevatedButton(
              key: _openSheetKey,
              onPressed: () => SsConfirmationSheet.show(
                context,
                title: 'Delete this session?',
                consequence: 'The recording will be removed.',
                confirmLabel: 'Delete session',
                cancelLabel: 'Cancel',
                onConfirm: () {},
              ),
              child: const Text('Open sheet'),
            ),
          ),
        );
      },
    ),
  );
}

void main() {
  group('A4 — the background is excluded from the semantics tree while a '
      'modal overlay is open', () {
    testWidgets(
      'the background probe is reachable before opening and unreachable '
      'once the dialog is open, and reachable again once it closes',
      (tester) async {
        final handle = tester.ensureSemantics();
        final openFocusNode = FocusNode(debugLabel: 'open');
        addTearDown(openFocusNode.dispose);

        await tester.pumpWidget(
          _dialogHarness(openFocusNode: openFocusNode, onConfirm: () {}),
        );

        bool backgroundReachable() => tester.semantics
            .simulatedAccessibilityTraversal()
            .any((node) => node.label.contains(_backgroundLabel));

        expect(backgroundReachable(), isTrue);

        await tester.tap(find.byKey(_openDialogKey));
        await tester.pumpAndSettle();

        expect(
          backgroundReachable(),
          isFalse,
          reason:
              'the background probe must not be reachable while the modal '
              'barrier is up — a screen reader would otherwise be able to '
              'swipe past the dialog into the covered screen',
        );

        await tester.tap(find.byKey(const ValueKey('ss-dialog-cancel')));
        await tester.pumpAndSettle();

        expect(backgroundReachable(), isTrue);
        handle.dispose();
      },
    );
  });

  group('A5 — closing an overlay restores focus to the element that opened '
      'it', () {
    testWidgets(
      'the FocusNode that had focus before opening is primaryFocus again '
      'after the dialog closes',
      (tester) async {
        final openFocusNode = FocusNode(debugLabel: 'open');
        addTearDown(openFocusNode.dispose);

        await tester.pumpWidget(
          _dialogHarness(openFocusNode: openFocusNode, onConfirm: () {}),
        );

        openFocusNode.requestFocus();
        await tester.pump();
        expect(primaryFocus, same(openFocusNode));

        await tester.tap(find.byKey(_openDialogKey));
        await tester.pumpAndSettle();
        expect(
          primaryFocus,
          isNot(same(openFocusNode)),
          reason: 'the dialog must trap focus inside itself while open',
        );

        await tester.tap(find.byKey(const ValueKey('ss-dialog-cancel')));
        await tester.pumpAndSettle();

        expect(
          primaryFocus,
          same(openFocusNode),
          reason: 'closing must restore focus to the exact node that opened it',
        );
      },
    );
  });

  group('A7 — Android back and Escape close an overlay the same way, '
      'without confirming', () {
    testWidgets('Escape closes the dialog without running the destructive '
        'callback', (tester) async {
      var confirmCalls = 0;
      final openFocusNode = FocusNode(debugLabel: 'open');
      addTearDown(openFocusNode.dispose);

      await tester.pumpWidget(
        _dialogHarness(
          openFocusNode: openFocusNode,
          onConfirm: () => confirmCalls++,
        ),
      );
      await tester.tap(find.byKey(_openDialogKey));
      await tester.pumpAndSettle();
      expect(find.byType(SsDialog), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(SsDialog), findsNothing);
      expect(confirmCalls, 0);
    });

    testWidgets(
      'Android back closes the dialog without running the destructive '
      'callback',
      (tester) async {
        var confirmCalls = 0;
        final openFocusNode = FocusNode(debugLabel: 'open');
        addTearDown(openFocusNode.dispose);

        await tester.pumpWidget(
          _dialogHarness(
            openFocusNode: openFocusNode,
            onConfirm: () => confirmCalls++,
          ),
        );
        await tester.tap(find.byKey(_openDialogKey));
        await tester.pumpAndSettle();
        expect(find.byType(SsDialog), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.byType(SsDialog), findsNothing);
        expect(confirmCalls, 0);
      },
    );
  });

  group('A8 — a size-adaptive sheet renders as a bottom sheet below the '
      'expanded breakpoint and a side sheet at/above it (SsBreakpoints, '
      '§0.0/D6)', () {
    final cases = <double, bool>{
      SsBreakpoints.compactMax: false,
      SsBreakpoints.mediumMax: false,
      SsBreakpoints.expandedMin: true,
    };

    for (final entry in cases.entries) {
      testWidgets(
        'width=${entry.key} renders ${entry.value ? "a side sheet" : "a bottom sheet, not a side sheet"}',
        (tester) async {
          tester.view.physicalSize = Size(entry.key, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(_sheetHarness());
          await tester.tap(find.byKey(_openSheetKey));
          await tester.pumpAndSettle();

          expect(
            find.byType(SsSideSheet),
            entry.value ? findsOneWidget : findsNothing,
          );
          expect(find.byType(SsConfirmationSheet), findsOneWidget);
        },
      );
    }
  });
}
