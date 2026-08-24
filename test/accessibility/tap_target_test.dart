import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// A5 — the five critical components §0.0/D4 names as already wired to
/// [SsSemantics.minimumInteractiveDimension]. Each cell measures the
/// ACTUAL rendered size of the built component through [SsTapTarget] — a
/// 44 dp target fails these cells; re-asserting the 48 constant against
/// itself would not (§0.0/D4).
///
/// The viewport is set ONLY through [WidgetTester.view.physicalSize]
/// (`docs/LESSONS.md` L452) — `MediaQuery(size:)` is inert for layout here.
void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  Future<void> setViewport(
    WidgetTester tester, {
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Widget wrap(Widget child, {double textScale = 1.0}) => MaterialApp(
    theme: SsLightTheme.data(),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: Center(child: child)),
    ),
  );

  testWidgets('ss_button.dart:122 — SsButton meets the minimum tap target', (
    tester,
  ) async {
    await setViewport(tester);
    await tester.pumpWidget(
      wrap(SsButton(label: 'Save changes', onPressed: () {})),
    );

    final size = tester.getSize(find.byType(SsButton));

    expect(SsTapTarget.meetsMinimum(size), isTrue, reason: 'measured $size');
  });

  testWidgets(
    'ss_icon_button.dart:62-63 — SsIconButton meets the minimum tap target '
    'on both axes',
    (tester) async {
      await setViewport(tester);
      await tester.pumpWidget(
        wrap(
          SsIconButton(
            iconName: 'close',
            semanticLabel: 'Dismiss',
            tooltip: 'Dismiss',
            onPressed: () {},
          ),
        ),
      );

      final size = tester.getSize(find.byType(SsIconButton));

      expect(SsTapTarget.meetsMinimum(size), isTrue, reason: 'measured $size');
    },
  );

  testWidgets('ss_switch_row.dart:45 — SsSwitchRow meets the minimum tap '
      'target', (tester) async {
    await setViewport(tester);
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 320,
          child: SsSwitchRow(
            label: 'Airplane mode',
            value: false,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byType(SsSwitchRow));

    expect(SsTapTarget.meetsMinimum(size), isTrue, reason: 'measured $size');
  });

  testWidgets(
    'ss_choice.dart:105 — each SsChoice radio row meets the minimum tap '
    'target',
    (tester) async {
      await setViewport(tester);
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 320,
            child: SsChoice<String>(
              style: SsChoiceStyle.radio,
              options: const [
                SsChoiceOption(value: 'a', label: 'Acoustic'),
                SsChoiceOption(value: 'b', label: 'Electric'),
              ],
              value: 'a',
              onChanged: (_) {},
            ),
          ),
        ),
      );

      final rowFinder = find
          .ancestor(
            of: find.byType(Radio<String>),
            matching: find.byType(ConstrainedBox),
          )
          .first;
      final size = tester.getSize(rowFinder);

      expect(SsTapTarget.meetsMinimum(size), isTrue, reason: 'measured $size');
    },
  );

  testWidgets('ss_coach_action_card.dart:70 — the dismiss control on '
      'SsCoachActionCard meets the minimum tap target', (tester) async {
    await setViewport(tester);
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 360,
          child: SsCoachActionCard(
            l10n: l10n,
            title: 'Try the G-to-C drill',
            message: 'Three of your last five sessions paused there.',
            actionLabel: 'Start drill',
            onAction: () {},
            onDismiss: () {},
            dismissSemanticLabel: 'Dismiss coach suggestion',
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byType(SsIconButton));

    expect(SsTapTarget.meetsMinimum(size), isTrue, reason: 'measured $size');
  });

  testWidgets(
    'the textScaler travels through MediaQuery (not physicalSize) and a '
    'grown SsButton still meets the minimum',
    (tester) async {
      await setViewport(tester);
      await tester.pumpWidget(
        wrap(SsButton(label: 'Save', onPressed: () {}), textScale: 2.0),
      );

      final size = tester.getSize(find.byType(SsButton));

      expect(SsTapTarget.meetsMinimum(size), isTrue, reason: 'measured $size');
    },
  );
}
