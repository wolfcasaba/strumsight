import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';

const _openDialogKey = ValueKey('open-dialog');
const _openSheetKey = ValueKey('open-sheet');
const _openToolKey = ValueKey('open-tool');

/// Wordings ADR 0279 §5.1 explicitly forbids as a confirm-button label —
/// none of them names the action, so a screen reader (or a reader in a
/// hurry) learns nothing from them.
const _forbiddenGenericLabels = {
  'Yes',
  'No',
  'OK',
  'Ok',
  'Sure',
  'Igen',
  'Nem',
  'Biztos',
};

Widget _dialogHarness({
  required String confirmLabel,
  required VoidCallback onConfirm,
}) {
  return MaterialApp(
    theme: SsLightTheme.data(),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: _openDialogKey,
            onPressed: () => SsDialog.show(
              context,
              title: 'Delete this session?',
              message: 'The recording will be removed.',
              confirmLabel: confirmLabel,
              cancelLabel: 'Cancel',
              onConfirm: onConfirm,
            ),
            child: const Text('Open dialog'),
          ),
        ),
      ),
    ),
  );
}

Widget _confirmationHarness({
  required String confirmLabel,
  required VoidCallback onConfirm,
}) {
  return MaterialApp(
    theme: SsLightTheme.data(),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: _openSheetKey,
            onPressed: () => SsConfirmationSheet.show(
              context,
              title: 'Delete this session?',
              consequence: 'The recording and its chord timeline will be lost.',
              confirmLabel: confirmLabel,
              cancelLabel: 'Cancel',
              onConfirm: onConfirm,
            ),
            child: const Text('Open confirmation sheet'),
          ),
        ),
      ),
    ),
  );
}

const _readsLabel = 'Reads';
const _readsDetail = 'Your last 5 practice sessions';
const _writesLabel = 'Writes';
const _writesDetail = 'Your practice plan for next week';
const _leavesDeviceLabel = 'Leaves this device';
const _leavesDeviceDetail = 'Nothing — stays on this device';
const _recordingLabel = 'Starts recording';
const _recordingDetail = 'None';

Widget _toolHarness({required VoidCallback onConfirm}) {
  return MaterialApp(
    theme: SsLightTheme.data(),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: _openToolKey,
            onPressed: () => SsToolConfirmationSheet.show(
              context,
              actionLabel: 'Update practice plan',
              summary: 'The AI wants to adjust next week\'s practice plan.',
              reads: const SsToolDimension(
                label: _readsLabel,
                detail: _readsDetail,
              ),
              writes: const SsToolDimension(
                label: _writesLabel,
                detail: _writesDetail,
              ),
              leavesDevice: const SsToolDimension(
                label: _leavesDeviceLabel,
                detail: _leavesDeviceDetail,
              ),
              recording: const SsToolDimension(
                label: _recordingLabel,
                detail: _recordingDetail,
              ),
              cancelLabel: 'Cancel',
              onConfirm: onConfirm,
            ),
            child: const Text('Open tool confirmation sheet'),
          ),
        ),
      ),
    ),
  );
}

/// Concatenates every rendered [Text] under the row keyed `ss-tool-
/// confirmation-$dimension` — the label AND the detail together, since A2
/// requires both to be present on the built tree, not merely constructed.
String _dimensionRowText(WidgetTester tester, String dimension) {
  final rowFinder = find.byKey(ValueKey('ss-tool-confirmation-$dimension'));
  final texts = tester
      .widgetList<Text>(
        find.descendant(of: rowFinder, matching: find.byType(Text)),
      )
      .map((widget) => widget.data)
      .whereType<String>();
  return texts.join(' | ');
}

void main() {
  group('A1 — no generic Yes/No confirmation: the confirm button always '
      'names the action', () {
    testWidgets(
      'SsDialog renders the caller-provided action label on the confirm '
      'button, never a generic word',
      (tester) async {
        await tester.pumpWidget(
          _dialogHarness(confirmLabel: 'Delete session', onConfirm: () {}),
        );
        await tester.tap(find.byKey(_openDialogKey));
        await tester.pumpAndSettle();

        final confirmText = tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('ss-dialog-confirm')),
                matching: find.byType(Text),
              ),
            )
            .data;

        expect(confirmText, 'Delete session');
        expect(_forbiddenGenericLabels, isNot(contains(confirmText)));
      },
    );

    testWidgets(
      'SsConfirmationSheet renders the caller-provided action label on the '
      'confirm button, never a generic word',
      (tester) async {
        await tester.pumpWidget(
          _confirmationHarness(
            confirmLabel: 'Delete session',
            onConfirm: () {},
          ),
        );
        await tester.tap(find.byKey(_openSheetKey));
        await tester.pumpAndSettle();

        final confirmText = tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('ss-confirmation-confirm')),
                matching: find.byType(Text),
              ),
            )
            .data;

        expect(confirmText, 'Delete session');
        expect(_forbiddenGenericLabels, isNot(contains(confirmText)));
      },
    );
  });

  group('A2 — the AI-tool confirmation shows all four consequence '
      'dimensions, each independently rendered and mutually '
      'distinguishable', () {
    for (final dimension in const [
      'reads',
      'writes',
      'leaves-device',
      'recording',
    ]) {
      testWidgets(
        'the $dimension row renders on the built tree with its own detail '
        'text, absent from the other three rows',
        (tester) async {
          await tester.pumpWidget(_toolHarness(onConfirm: () {}));
          await tester.tap(find.byKey(_openToolKey));
          await tester.pumpAndSettle();

          expect(
            find.byKey(ValueKey('ss-tool-confirmation-$dimension')),
            findsOneWidget,
          );

          final own = _dimensionRowText(tester, dimension);
          final others = const [
            'reads',
            'writes',
            'leaves-device',
            'recording',
          ].where((other) => other != dimension);

          final ownDetail = switch (dimension) {
            'reads' => _readsDetail,
            'writes' => _writesDetail,
            'leaves-device' => _leavesDeviceDetail,
            'recording' => _recordingDetail,
            _ => throw StateError('unreachable'),
          };
          expect(own, contains(ownDetail));

          for (final other in others) {
            expect(
              _dimensionRowText(tester, other),
              isNot(contains(ownDetail)),
              reason: '$other must not repeat the $dimension detail text',
            );
          }
        },
      );
    }
  });

  group('A3 — Cancel is always available on every confirmation surface, and '
      'never runs the destructive callback', () {
    testWidgets('SsDialog always renders a tappable cancel control', (
      tester,
    ) async {
      var confirmCalls = 0;
      await tester.pumpWidget(
        _dialogHarness(
          confirmLabel: 'Delete session',
          onConfirm: () => confirmCalls++,
        ),
      );
      await tester.tap(find.byKey(_openDialogKey));
      await tester.pumpAndSettle();

      final cancel = find.byKey(const ValueKey('ss-dialog-cancel'));
      expect(cancel, findsOneWidget);

      await tester.tap(cancel);
      await tester.pumpAndSettle();

      expect(find.byType(SsDialog), findsNothing);
      expect(confirmCalls, 0);
    });

    testWidgets('SsConfirmationSheet always renders a tappable cancel '
        'control', (tester) async {
      var confirmCalls = 0;
      await tester.pumpWidget(
        _confirmationHarness(
          confirmLabel: 'Delete session',
          onConfirm: () => confirmCalls++,
        ),
      );
      await tester.tap(find.byKey(_openSheetKey));
      await tester.pumpAndSettle();

      final cancel = find.byKey(const ValueKey('ss-confirmation-cancel'));
      expect(cancel, findsOneWidget);

      await tester.tap(cancel);
      await tester.pumpAndSettle();

      expect(find.byType(SsConfirmationSheet), findsNothing);
      expect(confirmCalls, 0);
    });

    testWidgets('SsToolConfirmationSheet always renders a tappable cancel '
        'control', (tester) async {
      var confirmCalls = 0;
      await tester.pumpWidget(_toolHarness(onConfirm: () => confirmCalls++));
      await tester.tap(find.byKey(_openToolKey));
      await tester.pumpAndSettle();

      final cancel = find.byKey(const ValueKey('ss-tool-confirmation-cancel'));
      expect(cancel, findsOneWidget);

      await tester.tap(cancel);
      await tester.pumpAndSettle();

      expect(find.byType(SsToolConfirmationSheet), findsNothing);
      expect(confirmCalls, 0);
    });
  });

  group('A6 — the destructive callback runs exactly once, per the three '
      'threshold cells (§6.1)', () {
    testWidgets('below threshold — Cancel: 0 calls', (tester) async {
      var confirmCalls = 0;
      await tester.pumpWidget(
        _confirmationHarness(
          confirmLabel: 'Delete session',
          onConfirm: () => confirmCalls++,
        ),
      );
      await tester.tap(find.byKey(_openSheetKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('ss-confirmation-cancel')));
      await tester.pumpAndSettle();

      expect(confirmCalls, 0);
    });

    testWidgets('below threshold — Android back: 0 calls', (tester) async {
      var confirmCalls = 0;
      await tester.pumpWidget(
        _confirmationHarness(
          confirmLabel: 'Delete session',
          onConfirm: () => confirmCalls++,
        ),
      );
      await tester.tap(find.byKey(_openSheetKey));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(confirmCalls, 0);
    });

    testWidgets('below threshold — Escape: 0 calls', (tester) async {
      var confirmCalls = 0;
      await tester.pumpWidget(
        _confirmationHarness(
          confirmLabel: 'Delete session',
          onConfirm: () => confirmCalls++,
        ),
      );
      await tester.tap(find.byKey(_openSheetKey));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(confirmCalls, 0);
    });

    testWidgets('on threshold — a single confirm tap: exactly 1 call', (
      tester,
    ) async {
      var confirmCalls = 0;
      await tester.pumpWidget(
        _confirmationHarness(
          confirmLabel: 'Delete session',
          onConfirm: () => confirmCalls++,
        ),
      );
      await tester.tap(find.byKey(_openSheetKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('ss-confirmation-confirm')));
      await tester.pumpAndSettle();

      expect(confirmCalls, 1);
    });

    testWidgets(
      'above threshold — a double tap on confirm before it closes: exactly '
      '1 call, the second tap does not count',
      (tester) async {
        var confirmCalls = 0;
        await tester.pumpWidget(
          _confirmationHarness(
            confirmLabel: 'Delete session',
            onConfirm: () => confirmCalls++,
          ),
        );
        await tester.tap(find.byKey(_openSheetKey));
        await tester.pumpAndSettle();

        final confirmButton = find.byKey(
          const ValueKey('ss-confirmation-confirm'),
        );
        await tester.tap(confirmButton);
        // The first tap starts disabling/animating the button away, so the
        // second may legitimately miss it — that miss is what "the second
        // tap does not count" should look like, not a test-harness error.
        await tester.tap(confirmButton, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(confirmCalls, 1);
      },
    );

    testWidgets('a throwing onConfirm followed by a responsive reshape past '
        'expandedMin does not let a second tap run the destructive callback '
        'again (ADR 0279 §5.5, the exactly-once guard must survive the '
        'bottom-sheet/side-sheet subtree swap)', (tester) async {
      var confirmCalls = 0;
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _confirmationHarness(
          confirmLabel: 'Delete session',
          onConfirm: () {
            confirmCalls++;
            throw StateError('backend unreachable');
          },
        ),
      );
      await tester.tap(find.byKey(_openSheetKey));
      await tester.pumpAndSettle();

      final confirmButton = find.byKey(
        const ValueKey('ss-confirmation-confirm'),
      );
      await tester.tap(confirmButton);
      await tester.pump();

      expect(
        tester.takeException(),
        isNotNull,
        reason:
            'the synthetic "backend unreachable" throw is expected on '
            'the first tap',
      );
      expect(confirmCalls, 1);
      expect(
        find.byType(SsConfirmationSheet),
        findsOneWidget,
        reason: 'a failed confirm must not pop the sheet (MINOR-1)',
      );

      // Below expandedMin the host renders a bottom sheet; above it, a
      // side sheet — a different widget subtree, which used to reset a
      // State-owned "confirmed" guard back to false (MAJOR-3).
      tester.view.physicalSize = const Size(1000, 700);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('ss-confirmation-confirm')));
      await tester.pumpAndSettle();

      expect(
        confirmCalls,
        1,
        reason:
            'the destructive callback must run exactly once even after a '
            'responsive reshape re-enables the confirm button (ADR 0279 '
            '§5.5)',
      );
    });
  });

  group('BLOCKER-1 (fix2) — a throwing onConfirm, retried with UP TO THREE '
      'un-resized confirm taps, must run the destructive callback exactly '
      'once on every confirmation surface (ADR 0279 §5.5) — fix1 durably '
      'guarded the two sheets via a show()-closure but left SsDialog.show '
      'passing the raw onConfirm through, so a failed confirm re-armed a '
      'callback with no guard behind it at all', () {
    testWidgets('SsDialog: exactly 1 call', (tester) async {
      var confirmCalls = 0;
      await tester.pumpWidget(
        _dialogHarness(
          confirmLabel: 'Delete session',
          onConfirm: () {
            confirmCalls++;
            throw StateError('backend unreachable');
          },
        ),
      );
      await tester.tap(find.byKey(_openDialogKey));
      await tester.pumpAndSettle();

      final confirmButton = find.byKey(const ValueKey('ss-dialog-confirm'));
      for (var i = 0; i < 3; i++) {
        if (confirmButton.evaluate().isEmpty) break;
        await tester.tap(confirmButton, warnIfMissed: false);
        await tester.pumpAndSettle();
        tester.takeException();
      }

      expect(
        confirmCalls,
        1,
        reason:
            'the destructive callback must run exactly once no matter how '
            'many times a failed confirm is retried, with no resize '
            'involved (§5.5)',
      );
    });

    testWidgets('SsConfirmationSheet: exactly 1 call', (tester) async {
      var confirmCalls = 0;
      await tester.pumpWidget(
        _confirmationHarness(
          confirmLabel: 'Delete session',
          onConfirm: () {
            confirmCalls++;
            throw StateError('backend unreachable');
          },
        ),
      );
      await tester.tap(find.byKey(_openSheetKey));
      await tester.pumpAndSettle();

      final confirmButton = find.byKey(
        const ValueKey('ss-confirmation-confirm'),
      );
      for (var i = 0; i < 3; i++) {
        if (confirmButton.evaluate().isEmpty) break;
        await tester.tap(confirmButton, warnIfMissed: false);
        await tester.pumpAndSettle();
        tester.takeException();
      }

      expect(
        confirmCalls,
        1,
        reason:
            'the destructive callback must run exactly once no matter how '
            'many times a failed confirm is retried, with no resize '
            'involved (§5.5)',
      );
    });

    testWidgets('SsToolConfirmationSheet: exactly 1 call', (tester) async {
      var confirmCalls = 0;
      await tester.pumpWidget(
        _toolHarness(
          onConfirm: () {
            confirmCalls++;
            throw StateError('backend unreachable');
          },
        ),
      );
      await tester.tap(find.byKey(_openToolKey));
      await tester.pumpAndSettle();

      final confirmButton = find.byKey(
        const ValueKey('ss-tool-confirmation-confirm'),
      );
      for (var i = 0; i < 3; i++) {
        if (confirmButton.evaluate().isEmpty) break;
        await tester.tap(confirmButton, warnIfMissed: false);
        await tester.pumpAndSettle();
        tester.takeException();
      }

      expect(
        confirmCalls,
        1,
        reason:
            'the destructive callback must run exactly once no matter how '
            'many times a failed confirm is retried, with no resize '
            'involved (§5.5)',
      );
    });
  });

  group('A9 — every confirmation surface keeps its critical content and '
      'buttons fully on-screen at the supported width and text-scale range '
      '(§5.1–§5.3) — measured on the rendered geometry, not merely '
      'findsOneWidget', () {
    const portraitPhone = Size(411, 891);
    const landscapePhone = Size(915, 412);
    final textScales = <double>[1.0, SsSemantics.maximumTextScale];

    Future<void> setSurface(
      WidgetTester tester,
      Size size,
      double textScale,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    void expectOnScreen(
      WidgetTester tester,
      Size screen,
      ValueKey<String> key,
    ) {
      final rect = tester.getRect(find.byKey(key));
      final onScreen =
          rect.left >= -0.5 &&
          rect.top >= -0.5 &&
          rect.right <= screen.width + 0.5 &&
          rect.bottom <= screen.height + 0.5;
      expect(
        onScreen,
        isTrue,
        reason:
            '${key.value} rect $rect must be fully inside the '
            '${screen.width}x${screen.height} screen — findsOneWidget '
            'alone does not prove visibility',
      );
    }

    for (final size in [portraitPhone, landscapePhone]) {
      for (final scale in textScales) {
        final label =
            '${size.width.toInt()}x${size.height.toInt()} @ '
            'textScale=$scale';

        testWidgets('SsDialog $label: Cancel and Confirm stay on-screen', (
          tester,
        ) async {
          await setSurface(tester, size, scale);
          await tester.pumpWidget(
            _dialogHarness(confirmLabel: 'Delete session', onConfirm: () {}),
          );
          await tester.tap(find.byKey(_openDialogKey));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expectOnScreen(tester, size, const ValueKey('ss-dialog-cancel'));
          expectOnScreen(tester, size, const ValueKey('ss-dialog-confirm'));
        });

        testWidgets(
          'SsConfirmationSheet $label: Cancel and Confirm stay on-screen',
          (tester) async {
            await setSurface(tester, size, scale);
            await tester.pumpWidget(
              _confirmationHarness(
                confirmLabel: 'Delete session',
                onConfirm: () {},
              ),
            );
            await tester.tap(find.byKey(_openSheetKey));
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
            expectOnScreen(
              tester,
              size,
              const ValueKey('ss-confirmation-cancel'),
            );
            expectOnScreen(
              tester,
              size,
              const ValueKey('ss-confirmation-confirm'),
            );
          },
        );

        testWidgets(
          'SsToolConfirmationSheet $label: Cancel and Confirm always stay '
          'on-screen, and leaves-device/recording are reachable by '
          'scrolling the body (BLOCKER-1 — the body must have a real '
          'Scrollable ancestor, not just render the row somewhere off-tree)',
          (tester) async {
            await setSurface(tester, size, scale);
            await tester.pumpWidget(_toolHarness(onConfirm: () {}));
            await tester.tap(find.byKey(_openToolKey));
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
            // Cancel and Confirm are pinned outside the scrollable body —
            // they must be on-screen immediately, with no scrolling.
            expectOnScreen(
              tester,
              size,
              const ValueKey('ss-tool-confirmation-cancel'),
            );
            expectOnScreen(
              tester,
              size,
              const ValueKey('ss-tool-confirmation-confirm'),
            );

            // The two most privacy-critical rows may legitimately require a
            // scroll on a short/landscape viewport at maximumTextScale —
            // what BLOCKER-1 forbids is there being NO way to reach them at
            // all (the old tree had zero Scrollable ancestors). ensureVisible
            // scrolls the nearest Scrollable until the target is on-screen;
            // on the old tree (no Scrollable) it is a no-op and the
            // assertion below stays red.
            for (final key in const [
              'ss-tool-confirmation-leaves-device',
              'ss-tool-confirmation-recording',
            ]) {
              await tester.ensureVisible(find.byKey(ValueKey(key)));
              await tester.pumpAndSettle();
              expectOnScreen(tester, size, ValueKey(key));
            }
          },
        );
      }
    }
  });
}
