// Golden snapshots of the E13-R23 Song Library, Song Overview and Setlist
// list (V2) screens, at a compact portrait phone (412×915) and the same
// frame at textScaler 2.0 — the two frames the round brief §7/A9 requires.
// Pattern and sizing follow the merged
// `test/ui/goldens/e13_r22_screens_golden_test.dart` precedent.
//
// E15-R05 correction: `theme` is `SsDarkTheme.data()`, not the original
// `AppTheme.dark()` — `song_library`/`song_overview` now use design-system
// components whose `Theme.of(context).extension<SsColorScheme>()!` null-check
// crashes under the bare legacy theme (`SsDarkTheme.data()` is additive-only,
// `AppTheme.dark()` + design-system extensions, ADR 0466 D2 — pixel-identical
// for `SetlistListScreenV2`, still unmigrated).
//
// Recorded on x86_64 (ADR 0426, §0.0/B/R14) via `tools/golden-x86.sh record`
// — NOT `flutter test --update-goldens` on this (aarch64) box.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart' show SsDarkTheme;
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/application/setlists/setlist_controller.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/domain/models/meter_map.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_instrument.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_measure.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_section.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_setlist.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';
import 'package:strumsight/features/song_trainer/domain/models/tempo_map.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/setlist_repository.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_repository.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_library_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_overview_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/setlist_list_screen_v2.dart';
import 'package:strumsight/l10n/app_localizations.dart';

const _compactPortrait = Size(412, 915);

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  List<Override> overrides = const <Override>[],
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = _compactPortrait;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: SsDarkTheme.data(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _expectGolden(WidgetTester tester, String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('goldens/$name.png'),
);

SongDocument _overviewDocument() {
  final now = DateTime.utc(2026, 8, 4);
  final backingAssetId = SongAssetId('backing');
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId('golden-overview'),
    revision: 0,
    metadata: SongMetadata(
      title: 'Golden Overview Song',
      copyright: '© 2026 StrumSight Test Fixtures',
    ),
    source: SongSource(
      type: SongSourceType.musicXml,
      originalFileName: 'golden.musicxml',
      sha256: 'a' * 64,
      importedAt: now,
      importerVersion: 'test@1',
    ),
    createdAt: now,
    updatedAt: now,
    // No asset is referenced, so the BackingAudioTrack's assetId resolves
    // to "missing" — the golden also exercises the A4 indicator.
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

final class _LibrarySummaryRepository implements SongRepository {
  const _LibrarySummaryRepository();

  @override
  Future<AppResult<List<SongSummary>>> list(SongQuery query) async =>
      AppResult<List<SongSummary>>.success(<SongSummary>[
        SongSummary(
          documentId: SongId('golden-editable'),
          title: 'Editable Native Song',
          artist: 'StrumSight Fixtures',
          tags: const <String>[],
          updatedAt: DateTime.utc(2026, 8, 5),
          lastPracticedAt: DateTime.utc(2026, 8, 5),
          capability: SongCapabilitySummary(
            canPersist: true,
            canTrain: true,
            canExport: true,
            chordScoring: true,
            pitchScoring: false,
            lastValidatedAt: DateTime.utc(2026, 8, 5),
          ),
          sourceType: SongSourceType.strumSightJson,
          favorite: true,
          archived: false,
          revision: 1,
          documentHash: '1' * 64,
          trashed: false,
        ),
        SongSummary(
          documentId: SongId('golden-readonly'),
          title: 'Read-Only Legacy Song',
          artist: null,
          tags: const <String>[],
          updatedAt: DateTime.utc(2026, 8, 3),
          lastPracticedAt: DateTime.utc(2026, 8, 3),
          capability: SongCapabilitySummary(
            canPersist: false,
            canTrain: true,
            canExport: false,
            chordScoring: true,
            pitchScoring: false,
            lastValidatedAt: DateTime.utc(2026, 8, 3),
          ),
          sourceType: SongSourceType.legacyLocal,
          favorite: false,
          archived: false,
          revision: 0,
          documentHash: '2' * 64,
          trashed: false,
        ),
      ]);

  @override
  Future<AppResult<void>> create(SongDocument document) =>
      throw UnimplementedError();

  @override
  Future<AppResult<SongDocument?>> get(SongId id) => throw UnimplementedError();

  @override
  Future<AppResult<void>> moveToTrash(SongId id) => throw UnimplementedError();

  @override
  Future<AppResult<void>> permanentlyDelete(SongId id) =>
      throw UnimplementedError();

  @override
  Future<AppResult<void>> restore(SongId id) => throw UnimplementedError();

  @override
  Future<AppResult<void>> update(
    SongDocument document, {
    required int expectedRevision,
  }) => throw UnimplementedError();
}

final class _OverviewDocumentRepository implements SongRepository {
  _OverviewDocumentRepository(this._document);

  final SongDocument _document;

  @override
  Future<AppResult<List<SongSummary>>> list(SongQuery query) =>
      throw UnimplementedError();

  @override
  Future<AppResult<void>> create(SongDocument document) =>
      throw UnimplementedError();

  @override
  Future<AppResult<SongDocument?>> get(SongId id) async =>
      AppResult<SongDocument?>.success(_document);

  @override
  Future<AppResult<void>> moveToTrash(SongId id) => throw UnimplementedError();

  @override
  Future<AppResult<void>> permanentlyDelete(SongId id) =>
      throw UnimplementedError();

  @override
  Future<AppResult<void>> restore(SongId id) => throw UnimplementedError();

  @override
  Future<AppResult<void>> update(
    SongDocument document, {
    required int expectedRevision,
  }) => throw UnimplementedError();
}

final class _GoldenSetlistRepository implements SetlistRepository {
  const _GoldenSetlistRepository();

  @override
  Future<AppResult<List<SongSetlist>>> list() async {
    final now = DateTime.utc(2026, 8, 1);
    return AppResult<List<SongSetlist>>.success(<SongSetlist>[
      SongSetlist(
        id: 'golden-setlist',
        name: 'Saturday Gig',
        createdAt: now,
        updatedAt: now,
        items: <SongSetlistItem>[
          SongSetlistItem(id: 'item-1', songId: SongId('opener')),
          SongSetlistItem(
            id: 'item-2',
            songId: SongId('no-backing'),
            initialAvailability: SetlistItemAvailability.missingAsset,
          ),
          SongSetlistItem(
            id: 'item-3',
            songId: SongId('gone'),
            initialAvailability: SetlistItemAvailability.missingSong,
          ),
        ],
      ),
    ]);
  }

  @override
  Future<AppResult<SongSetlist?>> get(String id) => throw UnimplementedError();

  @override
  Future<AppResult<void>> save(SongSetlist setlist) =>
      throw UnimplementedError();

  @override
  Future<AppResult<void>> delete(String id) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final textScale in [1.0, 2.0]) {
    final suffix = textScale == 1.0 ? 'compact' : 'compact_scale2';

    testWidgets('song library — $suffix', (tester) async {
      await _pump(
        tester,
        const SongLibraryScreen(),
        overrides: <Override>[
          songRepositoryProvider.overrideWithValue(
            const _LibrarySummaryRepository(),
          ),
        ],
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r23_song_library_$suffix');
    });

    testWidgets('song overview — $suffix', (tester) async {
      final document = _overviewDocument();
      await _pump(
        tester,
        SongOverviewScreen(songId: document.id.value),
        overrides: <Override>[
          songRepositoryProvider.overrideWithValue(
            _OverviewDocumentRepository(document),
          ),
        ],
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r23_song_overview_$suffix');
    });

    testWidgets('setlist list v2 — $suffix', (tester) async {
      final controller = SetlistController(const _GoldenSetlistRepository());
      await _pump(
        tester,
        SetlistListScreenV2(
          controller: controller,
          clock: () => DateTime.utc(2026, 8, 1),
        ),
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r23_setlist_list_$suffix');
    });
  }
}
