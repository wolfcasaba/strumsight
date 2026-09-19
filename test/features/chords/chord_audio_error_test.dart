import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/features/chords/screens/chord_library_screen.dart';
import 'package:strumsight/features/learn/audio/chord_audio.dart';
import 'package:strumsight/features/learn/audio/clip_player.dart';
import 'package:strumsight/features/learn/providers/backing_provider.dart';
import 'package:strumsight/features/learn/widgets/audio_error_notice.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/preference_store.dart';

// Audit H20 / L12 — tapping a chord plays it, and a refused pad used to be
// swallowed by an empty `catch`: the tap was simply mute with no explanation.

class _FailingClipPlayer implements ClipPlayer {
  @override
  Future<void> play(Uint8List wav) async {
    throw StateError('decoder failed');
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

Widget _app(Backing backing) => ProviderScope(
  overrides: [
    ...preferenceOverrides(),
    backingProvider.overrideWithValue(backing),
  ],
  child: const MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: ChordLibraryScreen(),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a chord tap that cannot play says so', (tester) async {
    final backing = Backing(playerFactory: _FailingClipPlayer.new);
    addTearDown(backing.dispose);

    await tester.pumpWidget(_app(backing));
    await tester.pumpAndSettle();
    expect(find.byKey(audioOutputErrorKey), findsNothing);

    await tester.tap(find.text('C'));
    await tester.pumpAndSettle();

    expect(find.byKey(audioOutputErrorKey), findsOneWidget);
  });

  testWidgets('a chord tap that plays shows no notice', (tester) async {
    final backing = Backing(playerFactory: _SilentClipPlayer.new);
    addTearDown(backing.dispose);

    await tester.pumpWidget(_app(backing));
    await tester.pumpAndSettle();

    await tester.tap(find.text('C'));
    await tester.pumpAndSettle();

    expect(find.byKey(audioOutputErrorKey), findsNothing);
  });
}
