// Javító sáv 2026-09-07 (R10, `docs/ui/apk-functionality-audit-2026-09-06.md`
// §5.2): the navigation half of the Setlist V2 wiring. `SetlistListScreenV2`
// hands a tapped setlist here, and `SetlistSessionScreen`'s per-item runner
// is built here too — both need a `BuildContext`, which is why they live in
// `presentation/` and not next to the coordinator in `application/`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routing/app_route.dart';
import '../../../../core/foundation/app_result.dart';
import '../../../../core/logging/logger_provider.dart';
import '../../application/setlist/setlist_session_launch.dart';
import '../../application/setlists/setlist_session_controller.dart';
import '../../domain/models/setlist_result.dart';
import '../../domain/models/song_setlist.dart';

/// Opens the ordered Setlist session for [setlist].
///
/// The setlist travels as `extra` (the same strongly-typed hand-off the
/// Song Trainer session route uses); the route redirects back to the list
/// when it is missing, so a deep link cannot land on a session with no
/// setlist behind it.
void openSetlistSession(BuildContext context, SongSetlist setlist) {
  unawaited(context.push<void>(AppRoutes.setlistSession, extra: setlist));
}

/// The per-item runner the Setlist session drives: prepare the item, open
/// the Song Trainer session for it, and wait until the learner comes back
/// before the next item starts. That await is what makes a setlist advance
/// item by item instead of launching everything at once.
///
/// A prepared item that runs and returns is reported `completed` with the
/// MEASURED time its session was on screen. The trainer session surface
/// pushes its own result route instead of popping a value, so "how well"
/// belongs to that result screen — what is asserted here is only that the
/// item ran. An item that cannot be prepared is reported `skipped` with the
/// NAMED reason (`missingSong` / `unsupportedTrack` / `invalidConfig`), so
/// the session list shows why it did not play.
SetlistItemRunner setlistItemRunner(BuildContext context, WidgetRef ref) {
  return (item) async {
    final coordinator = ref.read(setlistSessionCoordinatorProvider);
    final prepared = await coordinator.prepareItem(item);
    switch (prepared) {
      case Failure(:final error):
        final logger = ref.read(appLoggerProvider);
        logger.warning(
          'setlist_item_launch_failed',
          fields: <String, Object?>{'itemId': item.id, 'code': error.code},
        );
        return SetlistItemResult.skipped(
          itemId: item.id,
          availability: setlistAvailabilityForFailure(error.code),
        );
      case Success(:final value):
        if (!context.mounted) {
          return SetlistItemResult.skipped(
            itemId: item.id,
            availability: SetlistItemAvailability.invalidConfig,
          );
        }
        final location = AppRoutes.songTrainerSession.replaceFirst(
          ':songId',
          Uri.encodeComponent(item.songId.value),
        );
        // Wall clock, deliberately: this measures how long the learner
        // actually spent on the item's session, which is not derivable
        // from any injected domain clock.
        final startedAt = DateTime.now();
        await context.push<void>(location, extra: value);
        return SetlistItemResult.completed(
          itemId: item.id,
          activeDuration: DateTime.now().difference(startedAt),
        );
    }
  };
}

/// Performance mode has no playback-only session surface in the shipped
/// app: every song session the trainer offers is the SCORED one. Wiring
/// `SetlistSessionScreen`'s performance runner to that scored session would
/// contradict the screen's own promise ("microphone scoring is off"), so
/// the route below runs setlists in Practice mode and this runner stays the
/// explicit, loud placeholder for the mode the app cannot honestly offer
/// yet — the mirror image of the screen's own
/// `_unavailablePracticeRunner`.
Future<SetlistItemResult> unavailableSetlistPerformanceRunner(
  SongSetlistItem item,
) => throw StateError('Setlist performance mode has no playback session.');
