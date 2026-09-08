// Audit U7 + U9 for the metronome's own chrome.
//
// U7 — the tempo ± buttons were unlabelled icons: no tooltip, no semantics
// label, nothing a screen reader (or a hesitating beginner) could read. Every
// `IconButton` on the screen now carries a localized tooltip, which is also
// what the button exposes to accessibility services.
//
// U9 — the per-bar beat dots flashed `AppColors.confidenceHigh`, a teal-green
// from the SEPARATE confidence ramp, inside a copper/amber stage. The dots are
// brand tokens now: copper on the downbeat, warm amber on the other beats.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/theme/app_colors.dart';
import 'package:strumsight/features/learn/audio/clip_player.dart';
import 'package:strumsight/features/learn/audio/metronome.dart';
import 'package:strumsight/features/metronome/screens/metronome_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

class _SilentClipPlayer implements ClipPlayer {
  @override
  Future<void> play(Uint8List wav) async {}

  @override
  Future<void> dispose() async {}
}

Future<void> _pump(WidgetTester tester) async {
  final metronome = Metronome(playerFactory: _SilentClipPlayer.new);
  addTearDown(metronome.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MetronomeScreen(metronome: metronome),
    ),
  );
  await tester.pump();
}

/// The dots are the screen's only [AnimatedContainer]s (one per beat in the
/// bar) — the same handle `metronome_screen_test.dart` uses to count them.
List<Color?> _dotColors(WidgetTester tester) => [
  for (final container in tester.widgetList<AnimatedContainer>(
    find.byType(AnimatedContainer),
  ))
    (container.decoration! as BoxDecoration).color,
];

void main() {
  testWidgets('U7 — every icon button on the metronome is named', (
    tester,
  ) async {
    await _pump(tester);

    final buttons = tester.widgetList<IconButton>(find.byType(IconButton));
    expect(
      buttons,
      isNotEmpty,
      reason: 'the tempo ± and advanced-settings buttons must be present',
    );
    for (final button in buttons) {
      expect(
        button.tooltip,
        isNotNull,
        reason: 'an icon-only button with no tooltip is unnamed',
      );
      expect(button.tooltip, isNotEmpty);
    }
    // The two tempo nudges are named, and each says which way it goes.
    final minus = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.remove),
    );
    final plus = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.add),
    );
    expect(minus.tooltip, isNotEmpty);
    expect(plus.tooltip, isNotEmpty);
    expect(minus.tooltip, isNot(plus.tooltip));
  });

  testWidgets('U9 — the beat dots are brand tokens, never the teal-green of '
      'the confidence ramp', (tester) async {
    await _pump(tester);

    final colors = _dotColors(tester);
    expect(colors, hasLength(4)); // default 4/4 bar

    // Stopped: every dot is its base colour at the resting alpha.
    expect(colors.first, AppColors.primary.withValues(alpha: 0.22));
    for (final color in colors.skip(1)) {
      expect(color, AppColors.secondary.withValues(alpha: 0.22));
    }
    for (final color in colors) {
      expect(color, isNot(AppColors.confidenceHigh));
      expect(color, isNot(Colors.green));
    }

    // Running: the active dot lights up in the SAME brand hue, at full alpha.
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_dotColors(tester).first, AppColors.primary);
    await tester.tap(find.text('Stop'));
    await tester.pump();
  });
}
