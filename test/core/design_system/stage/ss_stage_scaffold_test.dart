import 'dart:io';

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

// A MediaQuery(data: MediaQueryData(size: ...)) wrapper only overrides what
// descendants READ; it does not change the actual test surface the Scaffold
// is laid out against (that stays whatever the default test view is), so a
// declared "landscape 800x400" cell was really measuring an unrelated
// 800x600 box (review E13-R09 MAJOR-2). Setting tester.view.physicalSize
// (with devicePixelRatio pinned to 1, so logical == physical) makes the
// declared size the REAL layout constraint; MediaQuery is then only needed
// to override textScaler.
Future<void> _pumpStage(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
  bool hasUnsavedSession = false,
  VoidCallback? onRequestScreenAwake,
  VoidCallback? onReleaseScreenAwake,
  VoidCallback? onUnsavedSessionBackAttempt,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
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
        await _pumpStage(
          tester,
          size: const Size(400, 800),
          onRequestScreenAwake: () => requested = true,
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

        await _pumpStage(
          tester,
          size: const Size(400, 800),
          onRequestScreenAwake: () => requestCount++,
          onReleaseScreenAwake: () => releaseCount++,
        );
        expect(requestCount, 1);
        expect(releaseCount, 0);

        // Rebuilding with the same widget must not re-request.
        await _pumpStage(
          tester,
          size: const Size(400, 800),
          onRequestScreenAwake: () => requestCount++,
          onReleaseScreenAwake: () => releaseCount++,
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
      await _pumpStage(tester, size: const Size(400, 800));

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
    });

    for (final size in [Size(800, 400), Size(1000, 500), Size(1200, 800)]) {
      testWidgets(
        'A4: no overflow at $size with ${SsSemantics.maximumTextScale}x '
        'text scale',
        (tester) async {
          await _pumpStage(
            tester,
            size: size,
            textScale: SsSemantics.maximumTextScale,
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

        await _pumpStage(tester, size: const Size(400, 800));

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

  // Review E13-R09 MAJOR-1: the wakelock_plus-only channel mock above is
  // blind to any OTHER platform channel — a scaffold that quietly opened the
  // microphone via `MethodChannel('plugins.flutter.io/record')` still passed
  // every cell above. A source-level scan is the only guard that catches an
  // arbitrary new channel/plugin call, not just the one channel the widget
  // test already knows to mock.
  group('resource ownership (source guard, E13-R09 MAJOR-1)', () {
    test(
      'the Stage scaffold and transport sources never mention a platform '
      'channel, wakelock, camera, recording, microphone, or permission API',
      () {
        const paths = [
          'lib/core/design_system/layouts/ss_stage_scaffold.dart',
          'lib/core/design_system/components/music/ss_session_transport.dart',
        ];

        final offenders = <String>[
          for (final path in paths)
            ..._forbiddenResourceTokenOffenders(
              path,
              File(path).readAsStringSync(),
            ),
        ];

        expect(
          offenders,
          isEmpty,
          reason:
              'SsStageScaffold/SsSessionTransport must stay presentation-only '
              '(ADR 0276) — found: ${offenders.join(', ')}',
        );
      },
    );

    test('the token scan actually catches the ADR 0276 autoStart mutation '
        '(regression proof for the guard itself)', () {
      const mutated = '''
class _State extends State<Widget> {
  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      const MethodChannel('plugins.flutter.io/record')
          .invokeMethod<void>('start');
    }
  }
}
''';

      expect(
        _forbiddenResourceTokenOffenders('mutated.dart', mutated),
        isNotEmpty,
      );
    });
  });
}

const _forbiddenResourceTokens = [
  'MethodChannel',
  'wakelock',
  'camera',
  'record',
  'microphone',
  'permission',
];

/// Flags any forbidden resource-acquisition token found in [content]'s
/// executable code — comments are stripped first so the doc-comment prose
/// describing this very guarantee (e.g. "starts no microphone, camera, or
/// recording") does not trip its own check. String literals are kept
/// visible, because the mutation this guards against (a direct
/// `MethodChannel('plugins.flutter.io/record')` call) hides its most
/// distinctive token inside the channel-name string.
List<String> _forbiddenResourceTokenOffenders(String path, String content) {
  final withoutComments = _withoutComments(content).toLowerCase();
  return [
    for (final token in _forbiddenResourceTokens)
      if (withoutComments.contains(token.toLowerCase()))
        '$path contains "$token"',
  ];
}

String _withoutComments(String source) {
  final buffer = StringBuffer();
  var index = 0;
  while (index < source.length) {
    if (source.startsWith('//', index)) {
      final newline = source.indexOf('\n', index);
      index = newline == -1 ? source.length : newline;
      continue;
    }
    if (source.startsWith('/*', index)) {
      final end = source.indexOf('*/', index + 2);
      index = end == -1 ? source.length : end + 2;
      continue;
    }
    buffer.write(source[index]);
    index++;
  }
  return buffer.toString();
}
