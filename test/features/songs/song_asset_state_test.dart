// E13-R23 — acceptance A1 (below-threshold: local song usable offline) and
// A4 (at-threshold: the backing track is missing but the rest of the song
// stays usable). §0.0/B/R20's mandatory three-cell asset-readiness matrix:
// below the threshold everything is present; AT the threshold only the
// backing asset is missing (document present, song still opens); ABOVE the
// threshold the document itself is missing (covered by A6 at the setlist
// layer, not here). Producer: `SongTrainerSetupState.hasMissingBackingAsset`,
// computed in `SongTrainerSetupController._loadDocument` straight from
// `document.tracks` vs `document.assets` (measured, R20).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/domain/models/meter_map.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_asset_reference.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_instrument.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_measure.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_section.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';
import 'package:strumsight/features/song_trainer/domain/models/tempo_map.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_overview_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;

void main() {
  // ─── A1: below the threshold — everything present, full functionality,
  // reached with zero network dependency (offline-first by construction:
  // the only provider override below is the in-memory, filesystem-free
  // song repository). ────────────────────────────────────────────────────
  testWidgets(
    'a fully local song with its backing asset present opens with full functionality offline',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final repository = InMemorySongRepository();
      final document = _document(withBackingAsset: true);
      await repository.create(document);

      await tester.pumpWidget(_app(repository, document.id.value));
      await tester.pumpAndSettle();

      expect(find.text('Below Threshold Song'), findsOneWidget);
      expect(find.text('Verse'), findsOneWidget);
      expect(
        find.byKey(const Key('song-overview-missing-backing')),
        findsNothing,
      );
      final startButton = tester.widget<FilledButton>(
        find.byKey(const Key('song-overview-start')),
      );
      expect(
        startButton.onPressed,
        isNotNull,
        reason: 'a fully-available song must offer a working trainer entry',
      );
    },
  );

  // ─── A4: at the threshold — only the backing asset is missing; the rest
  // of the song (title, sections, tracks, trainer entry) stays available.
  // The mandatory mutation probe (documented in §10) temporarily made this
  // cell block the whole song instead — it went red as expected, then the
  // fix was restored. ──────────────────────────────────────────────────────
  testWidgets(
    'a missing backing asset flags playback only — the rest of the song stays usable',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final repository = InMemorySongRepository();
      final document = _document(withBackingAsset: false);
      await repository.create(document);

      await tester.pumpWidget(_app(repository, document.id.value));
      await tester.pumpAndSettle();

      // The gap is named, not silent.
      expect(
        find.byKey(const Key('song-overview-missing-backing')),
        findsOneWidget,
      );

      // Everything else remains reachable: title, sections, tracks, and a
      // working trainer entry (the chord track is untouched by the missing
      // backing asset).
      expect(find.text('Below Threshold Song'), findsOneWidget);
      expect(find.text('Verse'), findsOneWidget);
      final startButton = tester.widget<FilledButton>(
        find.byKey(const Key('song-overview-start')),
      );
      expect(
        startButton.onPressed,
        isNotNull,
        reason:
            'a missing backing asset must not block the rest of the song '
            '(§5.3 / A4) — only playback is affected',
      );
    },
  );
}

Widget _app(InMemorySongRepository repository, String songId) => ProviderScope(
  overrides: [songRepositoryProvider.overrideWithValue(repository)],
  child: MaterialApp(
    theme: SsLightTheme.data(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: SongOverviewScreen(songId: songId),
  ),
);

SongDocument _document({required bool withBackingAsset}) {
  final now = DateTime.utc(2026, 8, 4);
  final backingAssetId = SongAssetId('backing');
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId(withBackingAsset ? 'below-threshold' : 'at-threshold'),
    revision: 0,
    metadata: SongMetadata(title: 'Below Threshold Song'),
    source: SongSource(
      type: SongSourceType.createdInApp,
      originalFileName: 'song.json',
      sha256: 'a' * 64,
      importedAt: now,
      importerVersion: 'test@1',
    ),
    createdAt: now,
    updatedAt: now,
    assets: withBackingAsset
        ? <SongAssetReference>[
            SongAssetReference(
              id: backingAssetId,
              sha256: 'b' * 64,
              extension: 'mp3',
              byteLength: 1000,
              mimeType: 'audio/mpeg',
              durationMs: 1000,
            ),
          ]
        : const <SongAssetReference>[],
    sections: <SongSection>[
      SongSection(
        id: SongSectionId('verse'),
        name: 'Verse',
        startMeasure: 0,
        endMeasureExclusive: 1,
      ),
    ],
    measures: <SongMeasure>[
      SongMeasure(index: 0, durationBeats: BeatPosition.fromBeats(4)),
    ],
    tempoMap: TempoMap.constant(Tempo(120)),
    meterMap: MeterMap.constant(Meter(4, 4)),
    tracks: <SongTrack>[
      ChordTrack(
        id: SongTrackId('chords'),
        name: 'Chords',
        instrument: SongInstrument(name: 'Guitar'),
        events: const [],
      ),
      BackingAudioTrack(
        id: SongTrackId('backing'),
        name: 'Backing',
        instrument: SongInstrument(name: 'Backing track'),
        assetId: backingAssetId,
        gridOffset: Duration.zero,
      ),
    ],
  );
}
