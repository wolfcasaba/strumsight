import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/chords/chord_shape.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/songs/screens/song_list_screen.dart';
import 'package:music_theory/features/songs/widgets/strum_pattern_editor.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(Widget home) => ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('empty songbook shows the build-your-own nudge', (tester) async {
    await tester.pumpWidget(_app(const SongListScreen()));
    await tester.pump();
    expect(find.textContaining('Build your own song'), findsOneWidget);
  });

  testWidgets('create a song end-to-end: name → chord → save → appears',
      (tester) async {
    await tester.pumpWidget(_app(const SongListScreen()));
    await tester.pump();

    // Open the builder.
    await tester.tap(find.text('New song'));
    await tester.pumpAndSettle();

    // Name it.
    await tester.enterText(find.byType(TextField), 'Test Song');
    await tester.pump();

    // Add the first available chord.
    final label = ChordShapes.allLabels.first;
    final chip = find.widgetWithText(ActionChip, label).first;
    await tester.scrollUntilVisible(chip, 120,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(chip);
    await tester.pump();

    // Save → back to the list, where the new song shows.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Test Song'), findsOneWidget);
  });

  testWidgets('suggest-a-progression fills the chord list', (tester) async {
    await tester.pumpWidget(_app(const SongListScreen()));
    await tester.pump();
    await tester.tap(find.text('New song'));
    await tester.pumpAndSettle();

    // Open the suggestion sheet and pick the Pop progression (default key C).
    await tester.tap(find.text('Suggest'));
    await tester.pumpAndSettle();
    expect(find.text('Suggest a progression'), findsOneWidget);
    await tester.tap(find.textContaining('Pop'));
    await tester.pumpAndSettle();

    // Pop in C = C G Am F → each added as a removable InputChip.
    expect(find.widgetWithText(InputChip, 'Am'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'F'), findsOneWidget);
  });

  testWidgets('pattern editor cycles a rest slot to a down-strum on tap',
      (tester) async {
    List<StrumDirection?>? emitted;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StrumPatternEditor(
          pattern: List<StrumDirection?>.filled(8, null),
          onChanged: (p) => emitted = p,
        ),
      ),
    ));
    await tester.tap(find.byType(InkWell).first);
    expect(emitted, isNotNull);
    expect(emitted![0], StrumDirection.down); // rest → down
  });
}
