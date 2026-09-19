// Audit U9 — the Song Trainer's status badges painted themselves with raw
// `Colors.green`, a Material hue that belongs to no StrumSight palette: it
// reads as a foreign colour next to the copper/amber brand and it ignores the
// light/dark contrast tuning every other semantic colour goes through. They
// use the brand's success token now (`AppColors.successOn(brightness)` — the
// same one the tuner's IN TUNE confirmation and the Live LISTENING dot use).
//
// The second cell is a source guard: a green literal that creeps back into
// one of these feature trees fails the suite instead of shipping.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/theme/app_colors.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_setlist.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_repository.dart';
import 'package:strumsight/features/song_trainer/presentation/widgets/setlist_item_availability_badge.dart';
import 'package:strumsight/features/song_trainer/presentation/widgets/song_capability_badges.dart';
import 'package:strumsight/l10n/app_localizations.dart';

SongSummary _summary() => SongSummary(
  documentId: SongId('song-1'),
  title: 'Fixture',
  artist: null,
  tags: const <String>[],
  updatedAt: DateTime.utc(2026, 9, 1),
  lastPracticedAt: DateTime.utc(2026, 9, 1),
  capability: SongCapabilitySummary(
    canPersist: true,
    canTrain: true,
    canExport: true,
    chordScoring: true,
    pitchScoring: true,
    lastValidatedAt: DateTime.utc(2026, 9, 1),
  ),
  sourceType: SongSourceType.createdInApp,
  favorite: false,
  archived: false,
  revision: 0,
  documentHash: '0' * 64,
  trashed: false,
);

Future<void> _pump(WidgetTester tester, Widget child, Brightness brightness) =>
    tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

/// Every icon colour rendered by the widget under test.
List<Color?> _iconColors(WidgetTester tester) => [
  for (final icon in tester.widgetList<Icon>(find.byType(Icon))) icon.color,
];

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'U9 — the capability badges use the success token (${brightness.name})',
      (tester) async {
        await _pump(
          tester,
          SongCapabilityBadges(summary: _summary()),
          brightness,
        );

        final expected = AppColors.successOn(brightness);
        final colors = _iconColors(tester);
        expect(colors, hasLength(2)); // trainer + export, both available
        for (final color in colors) {
          expect(color, expected);
          expect(color, isNot(Colors.green));
        }
      },
    );

    testWidgets(
      'U9 — a ready setlist item uses the success token (${brightness.name})',
      (tester) async {
        await _pump(
          tester,
          const SetlistItemAvailabilityBadge(
            availability: SetlistItemAvailability.ready,
            songId: 'song-1',
          ),
          brightness,
        );

        expect(_iconColors(tester).single, AppColors.successOn(brightness));
        expect(_iconColors(tester).single, isNot(Colors.green));
      },
    );
  }

  test('U9 — no raw Material green literal in the owned feature trees', () {
    const roots = <String>[
      'lib/features/song_trainer',
      'lib/features/songs',
      'lib/features/metronome',
    ];
    final offenders = <String>[];
    for (final root in roots) {
      final dir = Directory(root);
      expect(dir.existsSync(), isTrue, reason: '$root must exist');
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains('Colors.green')) {
            offenders.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'use a theme token (AppColors.successOn / AppColors.primary), not a '
          'raw Material green:\n${offenders.join('\n')}',
    );
  });
}
