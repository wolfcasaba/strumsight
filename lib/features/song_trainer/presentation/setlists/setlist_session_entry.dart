import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routing/app_route.dart';
import '../../application/setlists/setlist_item_session_runner.dart';
import '../../application/song_trainer_providers.dart';
import '../../application/trainer/song_trainer_result.dart';
import '../../domain/models/song_id.dart';
import '../../domain/models/song_setlist.dart';
import '../screens/setlist_list_screen_v2.dart';
import '../screens/setlist_session_screen.dart';

/// Egy konkrét dal-tréner munkamenet URL-je a route-sablonból.
///
/// A sablon (`/song-trainer/session/:songId`) az EGYETLEN forrás; a
/// behelyettesítés itt történik, hogy a hívók ne írjanak kézzel útvonalat.
String songTrainerSessionLocation(String songId) =>
    AppRoutes.songTrainerSession.replaceFirst(
      ':songId',
      Uri.encodeComponent(songId),
    );

/// Egy konkrét dal-tréner eredmény-képernyő URL-je a route-sablonból.
String songTrainerResultLocation(String songId) =>
    AppRoutes.songTrainerResult.replaceFirst(
      ':songId',
      Uri.encodeComponent(songId),
    );

/// A Setlist V2 lista éles összeállítása.
///
/// A tároló a bootstrap által felülírt [setlistRepositoryProvider]-ből jön
/// (`lib/app/production_overrides.dart`), az óra a valós rendszeróra — a
/// szerkesztő ebből képzi az új tételek azonosítóit.
Widget buildSetlistListScreenV2(WidgetRef ref) => SetlistListScreenV2(
  controller: ref.watch(setlistControllerProvider),
  clock: DateTime.now,
);

/// A dalcsomag-munkamenet éles összeállítása.
///
/// Itt kapcsolódik össze a három darab: a képernyő a [SetlistSessionArgs]-ból
/// kapja a dalcsomagot és a módot, a tétel-futtatók a valódi
/// [SetlistItemSessionRunner]-t hívják, az pedig a dal-tréner munkamenet
/// ÚTVONALÁT indítja el, és megvárja, mivel tér vissza.
///
/// Az elérhetőség-feloldó a setlistben TÁROLT állapotot adja vissza — ez az,
/// amit a lista is mutat. A valóban futtathatatlan tételt nem itt, hanem a
/// futtatóban méri a rendszer (a dal ténylegesen betöltődik-e), és `failed`
/// eredményt ad, nem néma kihagyást.
Widget buildSetlistSessionScreen(
  BuildContext context,
  WidgetRef ref,
  SetlistSessionArgs args,
) {
  final runner = SetlistItemSessionRunner(
    repository: ref.watch(songRepositoryProvider),
    launchSession: (songId, inputs) => _pushSession(context, songId, inputs),
  );
  return SetlistSessionScreen(
    setlist: args.setlist,
    mode: args.mode,
    availability: (item) => item.initialAvailability,
    performanceRunner: runner.runPerformance,
    createPracticeRunner: () => runner.runPractice,
  );
}

Future<SongTrainerResult?> _pushSession(
  BuildContext context,
  SongId songId,
  SongTrainerControllerInputs inputs,
) => context.push<SongTrainerResult>(
  songTrainerSessionLocation(songId.value),
  extra: inputs,
);

/// A dalcsomag-lista indító gesztusa: átvisz a munkamenet-útvonalra a
/// választott móddal.
Future<void> openSetlistSession(
  BuildContext context, {
  required SongSetlist setlist,
  required SetlistSessionMode mode,
}) => context.push<void>(
  AppRoutes.songTrainerSetlistSession,
  extra: SetlistSessionArgs(setlist: setlist, mode: mode),
);
