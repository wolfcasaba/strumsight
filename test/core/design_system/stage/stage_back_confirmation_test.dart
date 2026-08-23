import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';

const _openStageLabel = 'open stage';
const _stageMarkerLabel = 'on stage';

/// A two-route harness: a home page that pushes an [SsStageScaffold] page.
/// [hasUnsaved] is reactive so a fake feature can flip it — mirroring how a
/// real caller would mark data saved/discarded before re-attempting the pop
/// the scaffold's [PopScope] blocked.
Widget _harness({
  required ValueNotifier<bool> hasUnsaved,
  required VoidCallback onBackAttempt,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) {
        return Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (routeContext) => ValueListenableBuilder<bool>(
                    valueListenable: hasUnsaved,
                    builder: (context, unsaved, _) => SsStageScaffold(
                      statusHeader: const Text(_stageMarkerLabel),
                      hero: const SizedBox(),
                      feedback: const SizedBox(),
                      timeline: const SizedBox(),
                      bottomAction: const SizedBox(),
                      hasUnsavedSession: unsaved,
                      onUnsavedSessionBackAttempt: onBackAttempt,
                    ),
                  ),
                ),
              ),
              child: const Text(_openStageLabel),
            ),
          ),
        );
      },
    ),
  );
}

void main() {
  group('Stage back confirmation', () {
    testWidgets(
      'below the threshold: no unsaved data — the hook is not called and '
      'back proceeds immediately',
      (tester) async {
        final hasUnsaved = ValueNotifier<bool>(false);
        addTearDown(hasUnsaved.dispose);
        var attempts = 0;

        await tester.pumpWidget(
          _harness(hasUnsaved: hasUnsaved, onBackAttempt: () => attempts++),
        );
        await tester.tap(find.text(_openStageLabel));
        await tester.pumpAndSettle();
        expect(find.text(_stageMarkerLabel), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(attempts, 0);
        expect(find.text(_openStageLabel), findsOneWidget);
        expect(find.text(_stageMarkerLabel), findsNothing);
      },
    );

    testWidgets(
      'on the threshold: unsaved data, the feature confirms — the hook '
      'fires exactly once and the exit happens',
      (tester) async {
        final hasUnsaved = ValueNotifier<bool>(true);
        addTearDown(hasUnsaved.dispose);
        var attempts = 0;
        late BuildContext stageContext;

        await tester.pumpWidget(
          _harness(
            hasUnsaved: hasUnsaved,
            onBackAttempt: () {
              attempts++;
              hasUnsaved.value = false;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Navigator.of(stageContext).maybePop();
              });
            },
          ),
        );
        await tester.tap(find.text(_openStageLabel));
        await tester.pumpAndSettle();
        stageContext = tester.element(find.text(_stageMarkerLabel));

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(attempts, 1);
        expect(find.text(_openStageLabel), findsOneWidget);
        expect(find.text(_stageMarkerLabel), findsNothing);
      },
    );

    testWidgets(
      'above the threshold: unsaved data, the feature declines — the hook '
      'fires once and the exit is skipped',
      (tester) async {
        final hasUnsaved = ValueNotifier<bool>(true);
        addTearDown(hasUnsaved.dispose);
        var attempts = 0;

        await tester.pumpWidget(
          _harness(
            hasUnsaved: hasUnsaved,
            onBackAttempt: () {
              attempts++;
              // The feature declines: it neither clears the flag nor pops.
            },
          ),
        );
        await tester.tap(find.text(_openStageLabel));
        await tester.pumpAndSettle();
        expect(find.text(_stageMarkerLabel), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(attempts, 1);
        expect(find.text(_openStageLabel), findsNothing);
        expect(find.text(_stageMarkerLabel), findsOneWidget);
      },
    );
  });
}
