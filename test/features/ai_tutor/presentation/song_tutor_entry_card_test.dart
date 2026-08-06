import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/presentation/widgets/song_tutor_entry_card.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

AppLocalizations _l10n() => AppLocalizationsEn();

Future<void> _pump(
  WidgetTester tester, {
  required bool chordScoringAvailable,
  required bool pitchScoringAvailable,
  VoidCallback? onOpenTutor,
}) => tester.pumpWidget(
  MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SongTutorEntryCard(
        songTitle: 'Safe song structure',
        sectionCount: 2,
        measureCount: 3,
        chordScoringAvailable: chordScoringAvailable,
        pitchScoringAvailable: pitchScoringAvailable,
        onOpenTutor: onOpenTutor,
      ),
    ),
  ),
);

void main() {
  testWidgets('shows structure debrief and only supported scoring actions', (
    tester,
  ) async {
    var openCount = 0;
    await _pump(
      tester,
      chordScoringAvailable: false,
      pitchScoringAvailable: false,
      onOpenTutor: () => openCount++,
    );

    expect(find.text(_l10n().aiTutorSongEntryTitle), findsOneWidget);
    expect(
      find.text(_l10n().aiTutorSongEntryStructure('Safe song structure', 2, 3)),
      findsOneWidget,
    );
    expect(find.text(_l10n().aiTutorSongChordUnavailable), findsOneWidget);
    expect(find.text(_l10n().aiTutorSongPitchUnavailable), findsOneWidget);
    expect(find.byKey(const ValueKey('song-tutor-chord-action')), findsNothing);
    expect(find.byKey(const ValueKey('song-tutor-pitch-action')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('song-tutor-open')));
    expect(openCount, 1);
  });

  testWidgets('renders capability actions only when scoring is available', (
    tester,
  ) async {
    await _pump(
      tester,
      chordScoringAvailable: true,
      pitchScoringAvailable: true,
    );

    expect(
      find.byKey(const ValueKey('song-tutor-chord-action')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('song-tutor-pitch-action')),
      findsOneWidget,
    );
  });

  test('entry card cannot include lyrics or backing audio in presentation', () {
    final source = File(
      'lib/features/ai_tutor/presentation/widgets/song_tutor_entry_card.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('LyricsTrack')));
    expect(source, isNot(contains('BackingAudioTrack')));
  });
}
