// Dev tool: renders the SsStrumStrings band at fixed instants after an
// onset-first strum and writes PNG frames so the motion can be LOOKED at
// (build/strings_frames/*.png). Never runs in CI: gated by
// STRINGS_FRAME_DUMP=1.
//
//   STRINGS_FRAME_DUMP=1 flutter test test/tools/strum_strings_frame_dump_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/components/music/ss_strum_strings.dart';

void main() {
  final enabled = Platform.environment['STRINGS_FRAME_DUMP'] == '1';
  final boundaryKey = GlobalKey();

  Widget host({required int onsetSeq, required int strumSeq, bool? isDown}) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: boundaryKey,
            child: Container(
              width: 360,
              height: 96,
              color: const Color(0xFF101418),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: SsStrumStrings(
                onsetSeq: onsetSeq,
                strumSeq: strumSeq,
                isDown: isDown,
                strength: 0.9,
                downColor: const Color(0xFFD08A4B),
                upColor: const Color(0xFF5FD39A),
                stringColor: const Color(0xFF9AA0A6),
                height: 72,
              ),
            ),
          ),
        ),
      );

  Future<void> dump(WidgetTester tester, String name) async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/strings_frames/$name.png');
      await file.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  testWidgets(
    'frame dump: onset → down-stroke → ring-out; then an up-stroke',
    (tester) async {
      tester.view.physicalSize = const Size(800, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(onsetSeq: 0, strumSeq: 0));
      await dump(tester, '00-idle');

      // The hit is heard: every string rings, no direction yet.
      await tester.pumpWidget(host(onsetSeq: 1, strumSeq: 0));
      await tester.pump();
      await dump(tester, '01-onset-000ms');
      await tester.pump(const Duration(milliseconds: 30));
      await dump(tester, '02-onset-030ms');
      await tester.pump(const Duration(milliseconds: 40));

      // The verdict lands 70 ms later: the pick sweeps down through the band.
      await tester.pumpWidget(host(onsetSeq: 1, strumSeq: 1, isDown: true));
      await tester.pump();
      await dump(tester, '03-down-070ms');
      for (final ms in [15, 30, 45, 60]) {
        await tester.pump(const Duration(milliseconds: 15));
        await dump(
          tester,
          '04-down-sweep-${(70 + ms).toString().padLeft(3, '0')}ms',
        );
      }
      await tester.pump(const Duration(milliseconds: 70));
      await dump(tester, '05-down-200ms');
      await tester.pump(const Duration(milliseconds: 200));
      await dump(tester, '06-down-400ms');
      await tester.pumpAndSettle();
      await dump(tester, '07-settled');

      // An up-stroke with no separate onset (a direct directed stroke).
      await tester.pumpWidget(host(onsetSeq: 1, strumSeq: 2, isDown: false));
      await tester.pump(const Duration(milliseconds: 30));
      await dump(tester, '08-up-030ms');
      await tester.pump(const Duration(milliseconds: 90));
      await dump(tester, '09-up-120ms');
      await tester.pumpAndSettle();
    },
    skip: !enabled, // set STRINGS_FRAME_DUMP=1 to write frames
  );
}
