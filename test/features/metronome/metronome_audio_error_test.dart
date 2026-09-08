import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/learn/audio/clip_player.dart';
import 'package:strumsight/features/learn/audio/metronome.dart';
import 'package:strumsight/features/learn/widgets/audio_error_notice.dart';
import 'package:strumsight/features/metronome/screens/metronome_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

// Audit H20 / L12 — a metronome that cannot make a sound used to look
// exactly like a running one: the click failed into an empty `catch`. The
// screen now renders a localized notice from the click player's typed error.

class _FailingClipPlayer implements ClipPlayer {
  @override
  Future<void> play(Uint8List wav) async {
    throw StateError('audio focus denied');
  }

  @override
  Future<void> dispose() async {}
}

class _SilentClipPlayer implements ClipPlayer {
  @override
  Future<void> play(Uint8List wav) async {}

  @override
  Future<void> dispose() async {}
}

Widget _app(Metronome metronome) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: MetronomeScreen(metronome: metronome),
);

void main() {
  testWidgets('a metronome that cannot click says so', (tester) async {
    final metronome = Metronome(playerFactory: _FailingClipPlayer.new);
    addTearDown(metronome.dispose);

    await tester.pumpWidget(_app(metronome));
    await tester.pump();
    expect(find.byKey(audioOutputErrorKey), findsNothing);

    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump();

    expect(find.byKey(audioOutputErrorKey), findsOneWidget);

    // Leave no ticker running at teardown.
    await tester.tap(find.text('Stop'));
    await tester.pump();
  });

  testWidgets('a working metronome shows no notice', (tester) async {
    final metronome = Metronome(playerFactory: _SilentClipPlayer.new);
    addTearDown(metronome.dispose);

    await tester.pumpWidget(_app(metronome));
    await tester.pump();

    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump();

    expect(find.byKey(audioOutputErrorKey), findsNothing);

    await tester.tap(find.text('Stop'));
    await tester.pump();
  });
}
