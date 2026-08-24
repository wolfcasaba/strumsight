import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: SsLightTheme.data(),
  home: Scaffold(body: child),
);

void main() {
  late AppLocalizations en;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('A1 — every field carries a persistent label, not just a hint', () {
    testWidgets('the label stays visible once the user starts typing (§5.1)', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const SsTextField(label: 'Song title')));

      expect(find.text('Song title'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Wonderwall');
      await tester.pump();

      expect(
        find.text('Song title'),
        findsOneWidget,
        reason:
            'a real label never disappears once typing starts — a '
            'hintText would have',
      );
      expect(find.text('Wonderwall'), findsOneWidget);
    });

    testWidgets('the label is exposed to a screen reader too', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(const SsTextField(label: 'Song title')));
      await tester.pumpAndSettle();

      final matches = find.bySemanticsLabel('Song title');
      handle.dispose();

      expect(matches, findsOneWidget);
    });
  });

  group(
    'A4 — the switch row is the ENTIRE touch target, not just the thumb',
    () {
      testWidgets(
        'tapping the far edge of the row (away from the visible switch) '
        'still toggles it',
        (tester) async {
          var value = false;
          await tester.pumpWidget(
            _wrap(
              SsSwitchRow(
                label: 'Metronome click',
                value: value,
                onChanged: (v) => value = v,
              ),
            ),
          );

          final topLeft = tester.getTopLeft(find.byType(SsSwitchRow));
          // 8dp inset from the row's own top-left corner — nowhere near the
          // Switch thumb, which sits at the row's right edge.
          await tester.tapAt(topLeft + const Offset(8, 8));
          await tester.pump();

          expect(value, isTrue);
        },
      );

      testWidgets('a disabled row (onChanged: null) does not toggle on tap', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            const SsSwitchRow(
              label: 'Metronome click',
              value: false,
              onChanged: null,
            ),
          ),
        );

        await tester.tap(find.byType(SsSwitchRow));
        await tester.pump();

        final aSwitch = tester.widget<Switch>(find.byType(Switch));
        expect(aSwitch.value, isFalse);
      });

      group('touch target height boundary (§6.1 — the 48 dp threshold)', () {
        testWidgets(
          'minimal content (no subtitle) still meets the 48 dp floor',
          (tester) async {
            await tester.pumpWidget(
              _wrap(
                const SsSwitchRow(
                  label: 'Metronome',
                  value: false,
                  onChanged: null,
                ),
              ),
            );

            expect(
              tester.getSize(find.byType(SsSwitchRow)).height,
              greaterThanOrEqualTo(SsSemantics.minimumInteractiveDimension),
            );
          },
        );

        testWidgets('content that naturally needs more than the floor (a long, '
            'wrapping subtitle) is NOT clamped back down to it', (
          tester,
        ) async {
          // Narrowed so the subtitle wraps across several lines — the
          // default single-line content is dominated by the Switch's own
          // ~48 dp intrinsic height regardless of subtitle presence, so a
          // meaningful "taller than the floor" case needs real wrapping.
          Widget narrow(Widget child) =>
              _wrap(SizedBox(width: 220, child: child));

          await tester.pumpWidget(
            narrow(
              const SsSwitchRow(
                label: 'Metronome',
                value: false,
                onChanged: null,
              ),
            ),
          );
          final withoutSubtitle = tester
              .getSize(find.byType(SsSwitchRow))
              .height;

          await tester.pumpWidget(
            narrow(
              const SsSwitchRow(
                label: 'Metronome',
                subtitle:
                    'Plays an audible click on every single beat while '
                    'you are practicing along with the backing track',
                value: false,
                onChanged: null,
              ),
            ),
          );
          final withSubtitle = tester.getSize(find.byType(SsSwitchRow)).height;

          expect(withSubtitle, greaterThan(withoutSubtitle));
        });
      });
    },
  );

  group('A6 — SsSemantics.maximumTextScale (2.0) on a real 360 dp viewport '
      'never overflows (D7)', () {
    testWidgets('the form components render with no RenderFlex overflow', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(360, 1200);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        MaterialApp(
          theme: SsLightTheme.data(),
          home: MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(SsSemantics.maximumTextScale),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SsTextField(label: 'Song title'),
                    SsSwitchRow(
                      label: 'Metronome click on every beat',
                      value: true,
                      onChanged: (_) {},
                    ),
                    SsButton(label: 'Save changes', onPressed: () {}),
                    SsButton(
                      label: 'Delete this song permanently',
                      variant: SsButtonVariant.destructive,
                      destructiveSemanticHint: 'This cannot be undone',
                      onPressed: () {},
                    ),
                    SsChoice<String>(
                      style: SsChoiceStyle.segmented,
                      options: const [
                        SsChoiceOption(value: 'up', label: 'Up'),
                        SsChoiceOption(value: 'down', label: 'Down'),
                      ],
                      value: 'up',
                      onChanged: (_) {},
                    ),
                    SsValueSlider(
                      label: 'Tempo',
                      value: 120,
                      min: 40,
                      max: 220,
                      unitLabel: 'BPM',
                      onChanged: (_) {},
                    ),
                    SsValidationSummary(
                      l10n: en,
                      issues: [
                        SsValidationIssue(
                          fieldLabel: 'Song title',
                          message: 'Song title is required',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('A7 — keyboard focus order follows the visual top-to-bottom order', () {
    testWidgets('each successive Tab stop sits at or below the previous one', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SsTextField(label: 'Song title'),
              SsSwitchRow(
                label: 'Metronome click',
                value: false,
                onChanged: (_) {},
              ),
              SsButton(label: 'Save', onPressed: () {}),
            ],
          ),
        ),
      );

      // Seed focus on the first field explicitly (real Tab traversal
      // starts from "nothing focused").
      await tester.tap(find.byType(TextField));
      await tester.pump();

      final positions = <double>[tester.getTopLeft(find.byType(TextField)).dy];
      for (var step = 0; step < 2; step++) {
        final moved = FocusManager.instance.primaryFocus?.nextFocus() ?? false;
        expect(moved, isTrue, reason: 'traversal step $step must move focus');
        await tester.pump();
        final context = FocusManager.instance.primaryFocus!.context!;
        positions.add(tester.getTopLeft(_elementFinder(context)).dy);
      }

      for (var i = 1; i < positions.length; i++) {
        expect(
          positions[i],
          greaterThanOrEqualTo(positions[i - 1]),
          reason:
              'focus step $i moved UPWARD, out of visual order: '
              '$positions',
        );
      }
    });
  });
}

Finder _elementFinder(BuildContext context) =>
    find.byElementPredicate((element) => element == context);
