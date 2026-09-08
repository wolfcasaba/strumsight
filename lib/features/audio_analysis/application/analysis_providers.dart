// Riverpod wiring for the Analysis V2 repository (E06-R21, ADR 0239).
//
// This file is the SINGLE boundary that resolves the production
// filesystem location for the analysis repository: a subdirectory of
// `getApplicationSupportDirectory()` (the platform's only native
// "documents" directory on both iOS and Android). Test code never
// touches `path_provider` — it injects a custom `Directory Function()`
// via the root-resolver override (the song_trainer pattern, ADR 0090
// §Döntés 1 + §5).
//
// Forbidden under the brief §4 allow-list: cross-feature imports, any
// UI/storage plugin beyond `path_provider`. All other dependencies
// are owned by the data/domain layer.

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider/path_provider.dart';

import '../../../core/audio/audio_providers.dart';
import '../../../core/audio/lifecycle/audio_session_lease.dart';
import '../../../core/foundation/app_failure.dart';
import '../../../core/foundation/app_result.dart';
import '../../../core/logging/logger_provider.dart';
import '../data/cache/analysis_cache.dart';
import '../data/capture/analysis_recorder.dart';
import '../data/input/analysis_audio_file_picker.dart';
import '../domain/analysis_mode.dart';
import '../domain/analysis_summary.dart';
import '../data/local/file_analysis_repository.dart';
import '../data/migration/analysis_migration_version_store.dart';
import '../data/migration/legacy_library_migrator.dart';
import '../domain/analysis_repository.dart';
import '../domain/analysis_document.dart';
import '../domain/analysis_event.dart';
import '../../../core/storage/storage_keys.dart';
import '../../library/public.dart' show AnalyzedSession;
import '../../progress/public.dart'
    show PracticeEntry, PracticeSource, practiceLogProvider;
import '../../streak/public.dart' show StreakLogic, streakProvider;
import 'analysis_controller.dart';
import 'analysis_isolate_runner.dart';
import 'analysis_state.dart';
import 'analyze_audio_use_case.dart';
import 'cancel_analysis_use_case.dart';
import 'import_audio_file_use_case.dart';
import 'save_analysis_use_case.dart';
import 'v2_analysis_runner.dart';

/// Sub-directory inside the app-support directory that owns the
/// analysis tree. The directory MUST exist before
/// [FileAnalysisRepository.openAtDirectory] opens it; the providers
/// below create it lazily.
const String analysisRepositoryRootDirectoryName = 'analysis';

/// Separate app-support subtree for derived entries. It is deliberately not a
/// child of the durable analysis-document repository.
const String analysisCacheRootDirectoryName = 'analysis_cache';

/// Factory that resolves the production `analysis/` directory by
/// asking `path_provider` for the app-support directory. Test code
/// overrides the provider with a `Directory Function()` returning a
/// temp path.
typedef AnalysisRepositoryRootResolver = Future<Directory> Function();

/// Production-only root resolver — tests override this provider to
/// inject a temp directory in place of `path_provider`.
final analysisRepositoryProductionRootResolverProvider =
    Provider<AnalysisRepositoryRootResolver>((_) => _defaultRootResolver);

Future<Directory> _defaultRootResolver() async {
  final appSupport = await getApplicationSupportDirectory();
  return Directory('${appSupport.path}/$analysisRepositoryRootDirectoryName');
}

/// Factory for the separate derived-cache directory. Tests override this
/// boundary rather than importing `path_provider`.
typedef AnalysisCacheRootResolver = Future<Directory> Function();

final analysisCacheProductionRootResolverProvider =
    Provider<AnalysisCacheRootResolver>((_) => _defaultCacheRootResolver);

Future<Directory> _defaultCacheRootResolver() async {
  final appSupport = await getApplicationSupportDirectory();
  return Directory('${appSupport.path}/$analysisCacheRootDirectoryName');
}

/// Override point for callers that require an already-open derived cache.
final analysisCacheProvider = Provider<AnalysisCache>((_) {
  throw StateError(
    'analysisCacheProvider must be overridden by the bootstrap layer before '
    'the rest of the app reads it. Production wires via '
    'analysisCacheBootProvider.',
  );
});

/// Opens the derived cache in its own app-support subtree. This does not read,
/// write, or purge saved analysis sessions.
final analysisCacheBootProvider = FutureProvider<AnalysisCache>((ref) async {
  final rootResolver = ref.watch(analysisCacheProductionRootResolverProvider);
  final root = await rootResolver();
  return AnalysisCache.openAtDirectory(
    directory: root,
    clock: ref.watch(analysisCacheClockProvider),
  );
});

/// Production clock supplied to the cache. Tests override it for LRU order.
final analysisCacheClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

/// Override point for the [AnalysisRepository]. Tests provide an
/// `InMemoryAnalysisRepository` or a `FileAnalysisRepository` whose
/// directory has been swapped; production wires it via the boot
/// provider below.
final analysisRepositoryProvider = Provider<AnalysisRepository>((ref) {
  throw StateError(
    'analysisRepositoryProvider must be overridden by the bootstrap layer '
    'before the rest of the app reads it. Tests override directly; '
    'production wires via analysisRepositoryBootProvider.',
  );
});

/// Future-opening variant used by the bootstrap path. The bootstrap
/// produces an [AnalysisRepository] from the resolved directory, then
/// assigns the result to [analysisRepositoryProvider] via
/// `ref.read(analysisRepositoryProvider.notifier) = ...`.
final analysisRepositoryBootProvider = FutureProvider<AnalysisRepository>((
  ref,
) async {
  final rootResolver = ref.watch(
    analysisRepositoryProductionRootResolverProvider,
  );
  final clock = ref.watch(analysisRepositoryClockProvider);
  final root = await rootResolver();
  await root.create(recursive: true);
  return FileAnalysisRepository.openAtDirectory(directory: root, clock: clock);
});

/// Provider for the migration-version store. The marker lives at
/// `<analysisRoot>/migration/state.json` (ADR 0239 §Döntés 9) and is
/// written atomically by the store itself.
final analysisMigrationVersionStoreProvider =
    Provider<AnalysisMigrationVersionStore>((ref) {
      throw StateError(
        'analysisMigrationVersionStoreProvider must be overridden by the '
        'bootstrap layer before the migrator runs.',
      );
    });

/// Future-opening variant — see [analysisRepositoryBootProvider].
final analysisMigrationVersionStoreBootProvider =
    FutureProvider<AnalysisMigrationVersionStore>((ref) async {
      final rootResolver = ref.watch(
        analysisRepositoryProductionRootResolverProvider,
      );
      final root = await rootResolver();
      await root.create(recursive: true);
      return AnalysisMigrationVersionStore.open(analysisRoot: root);
    });

/// Provider for the [LegacyLibraryMigrator]. The boot path calls this
/// once; re-runs after the user explicitly retries.
final legacyLibraryMigratorProvider = Provider<LegacyLibraryMigrator>((ref) {
  throw StateError(
    'legacyLibraryMigratorProvider must be overridden by the bootstrap '
    'layer before the migrator runs.',
  );
});

/// Future-opening variant. Wires the production repository, the
/// migration-version store, and the production library repository
/// supplier. Tests override [legacyLibrarySupplierProvider] below to
/// inject a synthetic supplier.
final legacyLibraryMigratorBootProvider = FutureProvider<LegacyLibraryMigrator>(
  (ref) async {
    final repository = await ref.watch(analysisRepositoryBootProvider.future);
    final versionStore = await ref.watch(
      analysisMigrationVersionStoreBootProvider.future,
    );
    final supplier = ref.watch(legacyLibrarySupplierProvider);
    return LegacyLibraryMigrator(
      repository: repository,
      versionStore: versionStore,
      supplier: supplier,
    );
  },
);

/// Supplier the migrator uses to read legacy V1 sessions. The
/// production wiring overrides this provider with a closure that
/// calls into the library feature's `libraryRepositoryProvider.load`
/// (the audio-analysis data layer never imports `LibraryRepository`
/// — the round's `allowed_paths` does not include
/// `lib/features/library/**`). Tests inject a synthetic in-memory
/// list of [AnalyzedSession]s.
final legacyLibrarySupplierProvider = Provider<LegacyLibrarySupplier>(
  (_) => _noLegacySupplier,
);

/// Empty default — the bootstrap layer MUST override this provider
/// before any migrator run is dispatched.
Future<List<AnalyzedSession>> _noLegacySupplier() async =>
    const <AnalyzedSession>[];

/// Production-only clock supplier — tests override this provider to
/// inject a deterministic clock.
final analysisRepositoryClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

/// Re-export the StorageKeys migration constant so callers do not
/// need to import the storage layer.
const String analysisMigrationStorageKey = StorageKeys.analysisMigrationState;

/// Re-export the cache storage key so callers do not import core storage.
const String analysisCacheStorageKey = StorageKeys.analysisCache;

/// Composition seam for the real V2 pipeline (ADR 0254). Runnable now, but
/// still reached only through the nine analysis-flags that stay off in every
/// environment (ADR 0254 §5.5) — this round wires the chain without
/// switching any user-facing path on.
final analysisV2RunnerProvider = Provider<AnalysisRunner>(
  (_) => V2AnalysisRunner(),
);

/// Application entry point for an injected analysis runner.
final analyzeAudioUseCaseProvider = Provider<AnalyzeAudioUseCase>(
  (ref) => AnalyzeAudioUseCase(ref.watch(analysisV2RunnerProvider)),
);

final cancelAnalysisUseCaseProvider = Provider<CancelAnalysisUseCase>(
  (_) => const CancelAnalysisUseCase(),
);

final saveAnalysisUseCaseProvider = Provider<SaveAnalysisUseCase>(
  (ref) => SaveAnalysisUseCase(ref.watch(analysisRepositoryProvider)),
);

/// The V2 form of the V1 Analyze credit side effect. The controller decides
/// eligibility and exactly-once semantics; this adapter performs the two
/// existing public-feature writes only after that decision.
final analysisPracticeCreditRecorderProvider =
    Provider<AnalysisPracticeCreditRecorder>(
      (ref) => _RiverpodAnalysisPracticeCreditRecorder(ref),
    );

final class _RiverpodAnalysisPracticeCreditRecorder
    implements AnalysisPracticeCreditRecorder {
  const _RiverpodAnalysisPracticeCreditRecorder(this._ref);

  final Ref _ref;

  @override
  void record(AnalysisDocument document) {
    final timeline = document.timeline;
    final strums = timeline.events.whereType<StrumEvent>().toList();
    _ref.read(streakProvider.notifier).recordPracticeToday();
    _ref
        .read(practiceLogProvider.notifier)
        .record(
          PracticeEntry(
            day: StreakLogic.epochDayOf(DateTime.now()),
            source: PracticeSource.analyze,
            seconds: timeline.duration.inSeconds,
            strokes: strums.length,
            chords: timeline.chordSegments
                .map((segment) => segment.label)
                .toSet()
                .length,
          ),
        );
  }
}

// ---------------------------------------------------------------------------
// Capture flow (2026-09-05) — a `presentation/capture/` hármas bekötése.
//
// A három képernyő (kezdőlap, felvétel, feldolgozás) `reachable: false` volt,
// mert a `AnalysisController`-nek NEM volt providere, a felvevőnek sem, és a
// `AnalyzeAudioUseCase` üres mintákat adott tovább. Mindhárom hiány itt zárul
// (a harmadik a use case-ben).
// ---------------------------------------------------------------------------

/// A futó elemzés állapotgépe. A `capture/` képernyők ezt figyelik.
final analysisControllerProvider =
    NotifierProvider<AnalysisController, AnalysisState>(AnalysisController.new);

/// A felvevő. `autoDispose`, és a lezárását MAGA végzi: aki a mikrofont
/// birtokló objektumot építi, az engedi is el (a `liveFrameProvider`
/// precedense — egy le nem zárt felvevő bekapcsolva hagyná a mikrofont).
final analysisCaptureRecorderProvider = Provider.autoDispose<AnalysisRecorder>((
  ref,
) {
  final recorder = AnalysisRecorder(
    mic: createMicCapture(ref, AudioOwner.analyzeRecorder),
  );
  ref.onDispose(recorder.dispose);
  return recorder;
});

/// A legutóbbi elemzések a kezdőlaphoz.
///
/// A képernyő SZÁNDÉKOSAN nem olvas repository-t („This screen never reads
/// the analysis repository itself" — a saját docstringje), ezért a lista
/// betöltése a kompozíciós gyökér dolga.
///
/// `retry: (retryCount, error) => null` (R35) — a Riverpod 3 alapból
/// ÚJRAPRÓBÁLJA a dobó `FutureProvider`-t, növekvő várakozással. Emiatt ez a
/// provider hiba után soha nem áll le: kb. 200 ms-onként újraolvas, a
/// hibakeret alatt végtelen időzítő fut, és egy widget-teszt sem tud rajta
/// `pumpAndSettle`-t hívni. Egy olvasási hiba itt nem is retryable
/// önmagától (a tár nem lesz olvashatóvá attól, hogy megint megnézzük), és
/// a felhasználónak VAN saját újrapróbálás-vezérlője: a `/analysis/capture`
/// hibakerete (`app_router.dart`, `analysis-home-route-error`) egy
/// `_RouteErrorScaffold`-ot rajzol, aminek a látható „Újra" gombja
/// `ref.invalidate(analysisRecentSummariesProvider)`-t hív — MÉRT, nem
/// feltételezett. Ugyanaz a precedens, mint az `activePracticePlanProvider`
/// és a `practiceHistoryV2ListProvider`.
final analysisRecentSummariesProvider =
    FutureProvider.autoDispose<List<AnalysisSummary>>((ref) async {
      final result = await ref.watch(analysisRepositoryProvider).list();
      return switch (result) {
        Success<List<AnalysisSummary>>(:final value) => value,
        // A hiba NEM üres listaként jelenik meg: az azt állítaná, hogy nincs
        // korábbi elemzés. A `FutureProvider` hibaága a képernyőn megkülön-
        // böztethető állapot.
        Failure<List<AnalysisSummary>>(:final error) => throw error,
      };
    }, retry: (retryCount, error) => null);

// ---------------------------------------------------------------------------
// Hang-import (R26, audit MI4) — a „Fájl importálása" belépő.
//
// A kezdőlap CTA-ja eddig egy ŐSZINTE hiány-üzenetet mutatott, mert a fához
// nem tartozott import-folyamat. A hiányzó darab NEM a dekóder volt (a
// `WavDecoderAdapter` és a `FileAnalysisInput` az E06-R05 óta megvan és
// tesztelt), hanem a platform-szedő és a kettőt összekötő use case.
// ---------------------------------------------------------------------------

/// A hang-import platform-határa. A widget-teszt saját, a fájlrendszert nem
/// érintő szedőt injektál ide.
final analysisAudioFilePickerProvider = Provider<AnalysisAudioFilePicker>(
  (_) => const PlatformAnalysisAudioFilePicker(),
);

/// Fájl → validált PCM az elemzés bemeneti határán. Elemzést NEM indít: a
/// visszaadott mintákat a hívó ugyanabba a futásba adja, amit egy mikrofonos
/// felvétel indít.
final importAudioFileUseCaseProvider = Provider<ImportAudioFileUseCase>(
  (ref) => ImportAudioFileUseCase(
    picker: ref.watch(analysisAudioFilePickerProvider),
  ),
);

/// Melyik bemenetből indult a LEGUTÓBB elindított futás.
///
/// A feldolgozó képernyő „Kezdés elölről" gombjának kell: egy importált
/// futás után a felvevő képernyőre dobni a felhasználót azt állítaná, hogy
/// az elemzés mikrofonból jött. A dokumentum ezt nem mondja meg — a futó
/// állapot csak a `AnalysisState`-et hordozza, a seedet nem.
final class AnalysisCaptureOrigin extends Notifier<AnalysisInputSource> {
  @override
  AnalysisInputSource build() => AnalysisInputSource.microphone;

  void markStarted(AnalysisInputSource source) => state = source;
}

final analysisCaptureOriginProvider =
    NotifierProvider<AnalysisCaptureOrigin, AnalysisInputSource>(
      AnalysisCaptureOrigin.new,
    );

// ---------------------------------------------------------------------------
// A befejezett futás MENTÉSE (R26, audit MI4).
//
// A `saveAnalysisUseCaseProvider`-nek egyetlen éles hívója sem volt a fában
// (mért), tehát a V2 repository-ba KIZÁRÓLAG a V1-migráció írt: egy friss
// futás — felvett vagy importált — eltűnt abban a pillanatban, amikor a
// felhasználó elhagyta a feldolgozó képernyőt, miközben a kezdőlap
// „legutóbbi elemzések" listát ígért.
//
// A mentés a VEZÉRLŐBEN dől el (`AnalysisController._persistOnce`), nem egy
// képernyőn: egy képernyő csak addig lát, amíg fel van építve, az import
// viszont elindítja a futást és a következő képkockán navigál — egy
// útvonal-szintű figyelő lemaradna egy közben befejeződő futásról.
// ---------------------------------------------------------------------------

/// A LEGUTÓBBI mentési kísérlet hibája, vagy null, ha a legutóbb befejezett
/// futás tárolásra került.
///
/// A hiba NEM marad néma: a feldolgozó útvonal ezt figyeli és kimondja. Egy
/// elnyelt írási hiba a mért „a felhő-írást elnyeli a try/catch" csapda helyi
/// változata lenne — a felhasználó úgy hagyná ott a képernyőt, hogy azt hiszi,
/// az elemzés megmaradt.
final class AnalysisPersistenceStatus extends Notifier<AppFailure?> {
  @override
  AppFailure? build() => null;

  void markSaved() => state = null;

  void markFailed(AppFailure failure) => state = failure;
}

final analysisPersistenceStatusProvider =
    NotifierProvider<AnalysisPersistenceStatus, AppFailure?>(
      AnalysisPersistenceStatus.new,
    );

/// A befejezett dokumentum írója.
///
/// A cím a V1 akkord-összefoglaló ([_autoTitle]), NEM az importált fájlnév:
/// a fájlnév a dokumentum `input.sourceName` mezőjében marad, amit az
/// export-engedélylista kihagy — az indexre viszont az engedélylista nem
/// vonatkozik, tehát ott a névnek nincs helye.
final analysisDocumentPersisterProvider = Provider<AnalysisDocumentPersister>(
  (ref) => _RiverpodAnalysisDocumentPersister(ref),
);

final class _RiverpodAnalysisDocumentPersister
    implements AnalysisDocumentPersister {
  const _RiverpodAnalysisDocumentPersister(this._ref);

  final Ref _ref;

  @override
  void persist(AnalysisDocument document) => unawaited(_save(document));

  Future<void> _save(AnalysisDocument document) async {
    final save = _ref.read(saveAnalysisUseCaseProvider);
    final result = await save(
      AnalysisSaveRequest(
        document: document,
        title: _autoTitle(document),
        customTitle: false,
      ),
    );
    final status = _ref.read(analysisPersistenceStatusProvider.notifier);
    if (result case Failure<void>(:final error)) {
      status.markFailed(error);
      // Csak a KÓD kerül naplóba. Maga a kivétel hordozhat fájl-útvonalat (a
      // `FileSystemException` a sajátját), a dokumentum pedig az importált
      // fájl nevét — egyik sem való diagnosztikába.
      final logger = _ref.read(appLoggerProvider);
      logger.warning(
        'analysis_persist_failed',
        fields: <String, Object?>{'code': error.code},
      );
      return;
    }
    status.markSaved();
    // A friss bejegyzés csak akkor JELENIK MEG a kezdőlapon, ha az
    // index-olvasás újrafut: a lista `FutureProvider`-je a repository-t
    // egyszer kérdezi meg, és a mentésről magától nem értesül.
    _ref.invalidate(analysisRecentSummariesProvider);
  }
}

/// The V1 auto-title, rebuilt from a V2 document: consecutive chord labels,
/// de-duplicated and joined — "C · G · Am · F".
///
/// `AnalysisSummary.title` documents exactly this shape ("auto-title like
/// `C · G`", with `customTitle` false), and mirroring
/// `AnalyzeResult.chordSummary` keeps a migrated V1 session and a fresh V2
/// run reading the same way inside one list.
///
/// It stays EMPTY when the run found no chord: a made-up name would claim
/// content the analysis did not find, and the empty string is the documented
/// value for "not titled yet" (the home screen falls back to the id). The
/// imported FILE NAME is deliberately NOT a candidate — the index is not
/// covered by the export allowlist that keeps `input.sourceName` out of a
/// shared export.
String _autoTitle(AnalysisDocument document) {
  final labels = <String>[];
  for (final segment in document.timeline.chordSegments) {
    if (labels.isEmpty || labels.last != segment.label) {
      labels.add(segment.label);
    }
  }
  return labels.join(' · ');
}
