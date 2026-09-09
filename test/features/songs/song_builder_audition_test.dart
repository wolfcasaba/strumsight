import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/learn/audio/chord_audition.dart';
import 'package:strumsight/features/learn/providers/chord_audition_provider.dart';
import 'package:strumsight/features/songs/screens/song_builder_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/preference_store.dart';

/// Records every strum the screen (or its preview transport) asked for —
/// composing/auditioning by ear (ADR 0535) never touches a real speaker in
/// tests.
final class _RecordingAudition implements ChordAudition {
  final List<String> strummed = [];
  var disposed = false;

  @override
  Future<void> strum(
    String label, {
    StrumDirection direction = StrumDirection.down,
  }) async {
    strummed.add(label);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async => disposed = true;
}

/// Mirrors `reference_tone_test.dart`'s `_toneOverride`: overriding with a
/// builder (not `overrideWithValue`) keeps the real `ref.onDispose` wiring
/// so autodispose teardown is actually exercised.
Override _auditionOverride(_RecordingAudition fake) =>
    chordAuditionProvider.overrideWith((ref) {
      ref.onDispose(fake.dispose);
      return fake;
    });

Future<_RecordingAudition> _pumpBuilder(WidgetTester tester) async {
  final fake = _RecordingAudition();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...preferenceOverrides(), _auditionOverride(fake)],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SongBuilderScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tapping an ActionChip adds the chord AND strums it', (
    tester,
  ) async {
    final fake = await _pumpBuilder(tester);

    await tester.tap(find.widgetWithText(ActionChip, 'C'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InputChip, 'C'), findsOneWidget);
    expect(fake.strummed, ['C']);
  });

  testWidgets('tapping the InputChip hears it again without duplicating it', (
    tester,
  ) async {
    final fake = await _pumpBuilder(tester);
    await tester.tap(find.widgetWithText(ActionChip, 'C'));
    await tester.pumpAndSettle();
    expect(fake.strummed, ['C']);

    // Tap the LABEL, not the chip's centre: on a two-letter chip the centre
    // sits on the delete affordance, which would remove the chord instead.
    final chip = find.widgetWithText(InputChip, 'C');
    await tester.tap(find.descendant(of: chip, matching: find.text('C')));
    await tester.pumpAndSettle();

    expect(fake.strummed, ['C', 'C']);
    expect(find.widgetWithText(InputChip, 'C'), findsOneWidget);
  });

  testWidgets('deleting the InputChip removes it without strumming', (
    tester,
  ) async {
    final fake = await _pumpBuilder(tester);
    await tester.tap(find.widgetWithText(ActionChip, 'C'));
    await tester.pumpAndSettle();
    expect(fake.strummed, ['C']);

    final chip = find.widgetWithText(InputChip, 'C');
    // The chip's only Icon is its delete affordance (the label is a Text).
    final deleteIcon = find.descendant(of: chip, matching: find.byType(Icon));
    expect(deleteIcon, findsOneWidget);

    await tester.tap(deleteIcon);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InputChip, 'C'), findsNothing);
    expect(fake.strummed, ['C']); // no extra strum from the delete
  });

  testWidgets('the preview toggle is disabled with no chords', (tester) async {
    await _pumpBuilder(tester);

    final button = tester.widget<IconButton>(
      find.byKey(const Key('song-preview-toggle')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets(
    'the preview plays the progression at tempo, highlighting the sounding '
    'bar, and can be stopped',
    (tester) async {
      final fake = await _pumpBuilder(tester);
      await tester.tap(find.widgetWithText(ActionChip, 'C'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, 'G'));
      await tester.pumpAndSettle();
      expect(fake.strummed, ['C', 'G']); // just the two "add" strums so far

      await tester.tap(find.byKey(const Key('song-preview-toggle')));
      await tester.pump();

      expect(fake.strummed, ['C', 'G', 'C']); // the preview's first stroke
      expect(find.byTooltip('Stop preview'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2700));
      expect(fake.strummed, contains('G'));
      final gChip = tester.widget<InputChip>(
        find.widgetWithText(InputChip, 'G'),
      );
      expect(gChip.selected, isTrue);

      await tester.tap(find.byKey(const Key('song-preview-toggle')));
      await tester.pump();
      final strummedAtStop = List<String>.of(fake.strummed);

      await tester.pump(const Duration(seconds: 6));
      expect(fake.strummed, strummedAtStop);
    },
  );

  testWidgets('leaving the builder route disposes the audition (autodispose)', (
    tester,
  ) async {
    final fake = _RecordingAudition();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...preferenceOverrides(), _auditionOverride(fake)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SongBuilderScreen(),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(fake.disposed, isFalse);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(fake.disposed, isTrue);
  });
}
