// Audit U6 — the metronome's stage used to stack BPM hero, beat pulse and
// beat dots against the header, leaving the centre of the screen empty while
// the content crowded top and bottom. The screen now distributes that spare
// height with token spacing of its own (a `Padding` on the hero and the
// feedback slots): purely additive, no widget key, no semantics label and no
// `SsStageScaffold` slot moves.
//
// The cells below are that change's safety net: {360×640, 412×915} ×
// {textScale 1.0, 2.0} × {stopped, running}, each asserting NO `RenderFlex`
// overflow and no other framework error — the overflow-detection approach of
// `test/ui/goldens/e15_r13_full_variant_matrix_test.dart` (capture
// `FlutterError.onError`, match the "overflowed by N pixels" message), inside
// this feature's own test directory. 360×640 is narrower AND shorter than any
// viewport that matrix covers.
//
// L558: every cell sets its own `tester.view.physicalSize` +
// `devicePixelRatio` and resets it via `addTearDown`.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/learn/audio/clip_player.dart';
import 'package:strumsight/features/learn/audio/metronome.dart';
import 'package:strumsight/features/metronome/screens/metronome_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// No real audio plugin in a layout test: the click is accepted and dropped,
/// so the screen never renders the audio-failure notice and the cells measure
/// the layout only (mirrors `metronome_audio_error_test.dart`).
class _SilentClipPlayer implements ClipPlayer {
  @override
  Future<void> play(Uint8List wav) async {}

  @override
  Future<void> dispose() async {}
}

final _overflowPattern = RegExp(r'overflowed by ([\d.]+) pixels');

void main() {
  const viewports = <String, Size>{
    'compact 360×640': Size(360, 640),
    'modern 412×915': Size(412, 915),
  };

  for (final MapEntry(key: viewportName, value: size) in viewports.entries) {
    for (final textScale in const <double>[1.0, 2.0]) {
      for (final running in const <bool>[false, true]) {
        testWidgets(
          'U6 — metronome stage lays out without overflow: $viewportName, '
          'textScale $textScale, ${running ? 'running' : 'stopped'}',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);

            final metronome = Metronome(playerFactory: _SilentClipPlayer.new);
            addTearDown(metronome.dispose);

            final captured = <FlutterErrorDetails>[];
            final previousOnError = FlutterError.onError;
            FlutterError.onError = captured.add;

            try {
              await tester.pumpWidget(
                MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: SsLightTheme.data(),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(textScale)),
                    child: child!,
                  ),
                  home: MetronomeScreen(metronome: metronome),
                ),
              );
              await tester.pump();

              if (running) {
                await tester.tap(find.text('Start'));
                await tester.pump(const Duration(milliseconds: 16));
                await tester.pump(const Duration(milliseconds: 700));
                // Leave no ticker running at teardown.
                await tester.tap(find.text('Stop'));
                await tester.pump();
              }
            } finally {
              FlutterError.onError = previousOnError;
            }

            final overflows = <String>[];
            final otherErrors = <String>[];
            for (final details in captured) {
              final message = details.exception.toString();
              if (_overflowPattern.hasMatch(message)) {
                overflows.add(message);
              } else {
                otherErrors.add(message);
              }
            }

            expect(
              overflows,
              isEmpty,
              reason:
                  'the metronome stage must not overflow at $viewportName / '
                  'textScale $textScale',
            );
            expect(otherErrors, isEmpty);
          },
        );
      }
    }
  }
}
