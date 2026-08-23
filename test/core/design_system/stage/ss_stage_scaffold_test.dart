import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';

const _longHungarianStatus =
    'Élő figyelés folyamatban — a mikrofonjel elemzése zajlik éppen most';
const _longHungarianHero = 'Am hangzat felismerve magas megbízhatósággal';
const _longHungarianFeedback =
    'A jelminőség kiváló, folytasd a gyakorlást ugyanezzel a tempóval';
const _longHungarianTimeline =
    'Az elmúlt tizenkét ütem üteme stabil, nincs szükség korrekcióra';
const _bottomActionMarker = 'Pause / Finish';

Widget _harness({
  required Size size,
  double textScale = 1,
  bool hasUnsavedSession = false,
  VoidCallback? onRequestScreenAwake,
  VoidCallback? onReleaseScreenAwake,
  VoidCallback? onUnsavedSessionBackAttempt,
}) {
  return MediaQuery(
    data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
    child: MaterialApp(
      home: SsStageScaffold(
        statusHeader: const Text(_longHungarianStatus, softWrap: true),
        hero: const Text(_longHungarianHero, softWrap: true),
        feedback: const Text(_longHungarianFeedback, softWrap: true),
        timeline: const Text(_longHungarianTimeline, softWrap: true),
        bottomAction: const Text(_bottomActionMarker),
        hasUnsavedSession: hasUnsavedSession,
        onUnsavedSessionBackAttempt: onUnsavedSessionBackAttempt,
        onRequestScreenAwake: onRequestScreenAwake,
        onReleaseScreenAwake: onReleaseScreenAwake,
      ),
    ),
  );
}

void main() {
  group('SsStageScaffold', () {
    testWidgets(
      'A1: building the Stage tree makes no wakelock platform-channel call',
      (tester) async {
        final channelCalls = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('wakelock_plus'),
          (call) async {
            channelCalls.add(call);
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('wakelock_plus'),
            null,
          ),
        );

        var requested = false;
        await tester.pumpWidget(
          _harness(
            size: const Size(400, 800),
            onRequestScreenAwake: () => requested = true,
          ),
        );

        expect(tester.takeException(), isNull);
        expect(requested, isTrue);
        expect(
          channelCalls,
          isEmpty,
          reason:
              'the scaffold must request screen-awake via callback only, '
              'never via a direct wakelock_plus channel call (ADR 0276)',
        );
      },
    );

    testWidgets(
      'A7: screen-awake is requested once on mount and released once on '
      'unmount, never more',
      (tester) async {
        var requestCount = 0;
        var releaseCount = 0;

        await tester.pumpWidget(
          _harness(
            size: const Size(400, 800),
            onRequestScreenAwake: () => requestCount++,
            onReleaseScreenAwake: () => releaseCount++,
          ),
        );
        expect(requestCount, 1);
        expect(releaseCount, 0);

        // Rebuilding with the same widget must not re-request.
        await tester.pumpWidget(
          _harness(
            size: const Size(400, 800),
            onRequestScreenAwake: () => requestCount++,
            onReleaseScreenAwake: () => releaseCount++,
          ),
        );
        expect(requestCount, 1);
        expect(releaseCount, 0);

        await tester.pumpWidget(const SizedBox());
        expect(requestCount, 1);
        expect(releaseCount, 1);
      },
    );

    testWidgets('A6: the Stage tree has no primary navigation surface', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(size: const Size(400, 800)));

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
    });

    for (final size in [Size(800, 400), Size(1000, 500), Size(1200, 800)]) {
      testWidgets(
        'A4: no overflow at $size with ${SsSemantics.maximumTextScale}x '
        'text scale',
        (tester) async {
          await tester.pumpWidget(
            _harness(size: size, textScale: SsSemantics.maximumTextScale),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'A8: the status → hero → feedback → timeline → bottom slots each '
      'carry semantics, and paint top to bottom in that declared order',
      (tester) async {
        final handle = tester.ensureSemantics();

        await tester.pumpWidget(_harness(size: const Size(400, 800)));

        final slotFinders = [
          find.text(_longHungarianStatus),
          find.text(_longHungarianHero),
          find.text(_longHungarianFeedback),
          find.text(_longHungarianTimeline),
          find.text(_bottomActionMarker),
        ];

        // Every slot participates in the semantics tree...
        for (final finder in slotFinders) {
          expect(tester.getSemantics(finder).label, isNotEmpty);
        }

        // ...and paints strictly top-to-bottom in the declared slot order —
        // the order Flutter's default semantics traversal follows for a
        // plain, non-overlapping vertical layout such as this one.
        final positions = [
          for (final finder in slotFinders) tester.getTopLeft(finder).dy,
        ];
        for (var i = 1; i < positions.length; i++) {
          expect(
            positions[i],
            greaterThan(positions[i - 1]),
            reason: 'slot $i must paint below slot ${i - 1}',
          );
        }

        handle.dispose();
      },
    );
  });
}
