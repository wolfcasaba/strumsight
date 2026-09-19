// Audit U7 — the Song Trainer's transport was three unlabelled icons: no
// tooltip, no semantics label, nothing a screen reader could announce, and
// the play glyph did double duty for Play and Resume with no way to tell
// which one it was about to do. Every button is named now.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/features/song_trainer/presentation/widgets/transport_controls.dart';
import 'package:strumsight/l10n/app_localizations.dart';

Future<void> _pump(
  WidgetTester tester, {
  required bool isPlaying,
  required bool isPaused,
  bool canSeek = false,
}) => tester.pumpWidget(
  MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: TransportControls(
        isPlaying: isPlaying,
        isPaused: isPaused,
        canSeek: canSeek,
        onPlay: () {},
        onPause: () {},
        onResume: () {},
        onSeek: (_) {},
      ),
    ),
  ),
);

void main() {
  testWidgets('every transport button carries a non-empty tooltip', (
    tester,
  ) async {
    await _pump(tester, isPlaying: true, isPaused: false, canSeek: true);

    final buttons = tester.widgetList<IconButton>(find.byType(IconButton));
    expect(buttons, hasLength(3)); // play, pause, seek-to-start
    for (final button in buttons) {
      expect(
        button.tooltip,
        isNotNull,
        reason: 'an icon-only transport button with no tooltip is unnamed',
      );
      expect(button.tooltip, isNotEmpty);
    }
  });

  testWidgets('the play glyph names the action it actually performs', (
    tester,
  ) async {
    await _pump(tester, isPlaying: false, isPaused: false);
    final play = tester
        .widget<IconButton>(
          find.byKey(const Key('song-trainer-transport-play')),
        )
        .tooltip;

    await _pump(tester, isPlaying: false, isPaused: true);
    final resume = tester
        .widget<IconButton>(
          find.byKey(const Key('song-trainer-transport-play')),
        )
        .tooltip;

    expect(play, isNotEmpty);
    expect(resume, isNotEmpty);
    expect(
      resume,
      isNot(play),
      reason: 'the same glyph resumes rather than starts once paused',
    );
  });
}
