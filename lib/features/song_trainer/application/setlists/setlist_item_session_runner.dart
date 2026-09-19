// A mezők szándékosan privátak, a konstruktor paraméterei viszont nevesítettek
// — a kettő együtt nem fejezhető ki inicializáló formállal (privát név nem
// lehet nevesített paraméter). Ugyanaz a kivétel, mint a
// `song_trainer_controller.dart` fájlban.
// ignore_for_file: prefer_initializing_formals

import '../../../../core/foundation/app_result.dart';
import '../../domain/models/setlist_result.dart';
import '../../domain/models/song_asset_reference.dart';
import '../../domain/models/song_document.dart';
import '../../domain/models/song_id.dart';
import '../../domain/models/song_setlist.dart';
import '../../domain/models/song_track.dart';
import '../../domain/models/trainer_config.dart';
import '../../domain/repositories/song_repository.dart';
import '../song_trainer_providers.dart';
import '../trainer/song_practice_compiler.dart';
import '../trainer/song_trainer_result.dart';
import '../trainer/song_trainer_setup_controller.dart';
import '../trainer/song_trainer_setup_state.dart';
import 'setlist_session_controller.dart';

/// Elindítja egy dalcsomag-tétel dal-tréner munkamenetét, és megvárja a
/// kimenetelét.
///
/// A `null` visszatérés azt jelenti, hogy a munkamenet eredmény NÉLKÜL zárult
/// — a tanuló elhagyta a dalt, mielőtt pontozott eredmény született volna.
typedef SongTrainerSessionLauncher =
    Future<SongTrainerResult?> Function(
      SongId songId,
      SongTrainerControllerInputs inputs,
    );

/// A [SetlistItemRunner] éles implementációja.
///
/// Egy tételre pontosan azt teszi, amit a felhasználó kézzel tenne: betölti a
/// dalt, előállítja a dal-tréner beállítását (a setlist-felülírásokkal), a
/// beállításból lefordítja a munkamenet bemeneteit, majd elindítja a
/// munkamenet-útvonalat és megvárja, mivel tér vissza.
///
/// A beállítás előállítása NEM másolja le a beállító képernyő logikáját:
/// ugyanazt a [SongTrainerSetupController]-t futtatja le, amit a kézi
/// folyamat is használ (sáv- és mód-képesség, tartomány-feloldás,
/// hangolás/capo emlékeztető). Ez egy MÁSODIK dokumentum-olvasást jelent a
/// [SongRepository]-ból (a fordítónak magára a dokumentumra is szüksége van);
/// az ár tudatosan vállalt, a képesség-logika duplikálása lenne a drágább.
///
/// Mérési korlát, szándékosan kimondva: a futtató a `failed` állapotot arra
/// tartja fenn, amit MAGA mér — a tétel el sem indítható (nincs dal, hiányzó
/// kíséret, érvénytelen felülírás). Egy már futó munkamenet belső hibáját a
/// munkamenet-útvonal ma nem adja vissza kimenetelként, ezért az onnan
/// eredmény nélkül visszatérő tétel `partial` (félbehagyott) marad — hamis
/// `failed` helyett.
final class SetlistItemSessionRunner {
  SetlistItemSessionRunner({
    required SongRepository repository,
    required SongTrainerSessionLauncher launchSession,
    DateTime Function() clock = DateTime.now,
  }) : _repository = repository,
       _launchSession = launchSession,
       _clock = clock;

  final SongRepository _repository;
  final SongTrainerSessionLauncher _launchSession;
  final DateTime Function() _clock;

  /// Pontozott (Practice) tétel: a dal-tréner a mikrofonos Practice
  /// munkamenetet futtatja, és eredményt ad vissza.
  Future<SetlistItemResult> runPractice(SongSetlistItem item) =>
      _run(item, scored: true);

  /// Lejátszás-only (Performance) tétel: nincs pontozás és nincs mikrofon —
  /// a munkamenet csak a kíséretet viszi végig.
  Future<SetlistItemResult> runPerformance(SongSetlistItem item) =>
      _run(item, scored: false);

  Future<SetlistItemResult> _run(
    SongSetlistItem item, {
    required bool scored,
  }) async {
    final loaded = await _repository.get(item.songId);
    final SongDocument document;
    switch (loaded) {
      case Failure<SongDocument?>():
        return SetlistItemResult.failed(
          itemId: item.id,
          availability: SetlistItemAvailability.missingSong,
        );
      case Success<SongDocument?>(value: null):
        return SetlistItemResult.failed(
          itemId: item.id,
          availability: SetlistItemAvailability.missingSong,
        );
      case Success<SongDocument?>(:final value?):
        document = value;
    }

    final backingAsset = _backingAssetOf(document);
    final SongTrainerControllerInputs inputs;
    if (scored) {
      final config = await _configFor(item);
      if (config == null) {
        return SetlistItemResult.failed(
          itemId: item.id,
          availability: SetlistItemAvailability.invalidConfig,
        );
      }
      final SongPracticeCompilation compilation;
      try {
        compilation = SongPracticeCompiler.compile(
          document: document,
          config: config,
        );
      } on ArgumentError {
        return SetlistItemResult.failed(
          itemId: item.id,
          availability: SetlistItemAvailability.invalidConfig,
        );
      }
      inputs = SongTrainerControllerInputs(
        compilation: compilation,
        backingAsset: backingAsset,
      );
    } else {
      // Performance módban a kíséret MAGA a munkamenet: ha a dal kíséret-sávot
      // hirdet, de az eszköz nincs meg, a tétel nem futtatható — ezt mérjük,
      // nem pedig egy néma, hangtalan lejátszást indítunk.
      if (_declaresBackingTrack(document) && backingAsset == null) {
        return SetlistItemResult.failed(
          itemId: item.id,
          availability: SetlistItemAvailability.missingAsset,
        );
      }
      inputs = SongTrainerControllerInputs(
        compilation: const SongPracticeCompilation.playbackOnly(),
        backingAsset: backingAsset,
      );
    }

    final startedAt = _clock();
    final result = await _launchSession(item.songId, inputs);
    final elapsed = _clock().difference(startedAt);
    final activeDuration = elapsed.isNegative ? Duration.zero : elapsed;
    return result == null
        ? SetlistItemResult.partial(
            itemId: item.id,
            activeDuration: activeDuration,
          )
        : SetlistItemResult.completed(
            itemId: item.id,
            activeDuration: activeDuration,
          );
  }

  /// A beállító folyamat kimenete a tétel felülírásaival.
  ///
  /// `null`, ha a dal nem tanítható, a felülírás a támogatott tartományon
  /// kívül esik, vagy a hivatkozott sáv nem játszható — mindhárom eset a
  /// hívónál `failed`-be fut, nem néma alapértelmezésbe.
  Future<TrainerConfig?> _configFor(SongSetlistItem item) async {
    final setup = SongTrainerSetupController(repository: _repository);
    try {
      await setup.load(item.songId);
      if (setup.state.status != SongTrainerSetupStatus.ready) return null;
      final overrides = item.overrides;
      final trackId = overrides.trackId;
      if (trackId != null && !setup.selectTrack(trackId)) return null;
      if (!setup.selectRange(overrides.range)) return null;
      if (!setup.setTargetSpeed(overrides.speedMultiplier)) return null;
      if (!setup.setCountInBars(overrides.countInBars)) return null;
      setup.setLoopEnabled(overrides.loopCount > 1);
      return setup.complete();
    } finally {
      setup.dispose();
    }
  }

  bool _declaresBackingTrack(SongDocument document) =>
      document.tracks.any((track) => track is BackingAudioTrack);

  SongAssetReference? _backingAssetOf(SongDocument document) {
    for (final track in document.tracks) {
      if (track is! BackingAudioTrack) continue;
      for (final asset in document.assets) {
        if (asset.id == track.assetId) return asset;
      }
    }
    return null;
  }
}
