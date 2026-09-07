// Javító sáv 2026-09-06 (R3): the router's production handler for the
// Setup screen's Start button. Until now the route registered
// `TrainerSetupScreen(songId: ...)` without `onComplete`, so Start was a
// no-op in the shipped APK.
//
// R8 adds the two navigation verbs the result screen needs (audit §5.2,
// "A `SongResultScreen` retry/next callbackjei"): restart the SAME song and
// config, and move on to the next section of the song.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:meta/meta.dart';

import '../../../app/routing/app_route.dart';
import '../../../core/foundation/app_result.dart';
import '../../../core/logging/logger_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../application/song_trainer_providers.dart';
import '../application/trainer/song_trainer_launcher.dart';
import '../application/trainer/song_trainer_result.dart';
import '../domain/models/loop_config.dart';
import '../domain/models/song_id.dart';
import '../domain/models/song_section.dart';
import '../domain/models/trainer_config.dart';
import '../domain/models/trainer_range.dart';

/// Everything the result route needs as `extra`.
///
/// Before R8 the route received a bare [SongTrainerResult], which is why its
/// retry / next buttons had nothing to act on — the configuration the
/// finished session was compiled from never travelled with the result.
@immutable
final class SongTrainerResultArgs {
  const SongTrainerResultArgs({required this.result, this.config});

  /// Accepts the payload itself or the pre-R8 bare-result shape, so a route
  /// restored from an older stack still renders.
  factory SongTrainerResultArgs.from(Object? extra) {
    if (extra is SongTrainerResultArgs) return extra;
    if (extra is SongTrainerResult) {
      return SongTrainerResultArgs(result: extra);
    }
    throw ArgumentError.value(extra, 'extra', 'Not a Song Trainer result.');
  }

  final SongTrainerResult result;

  /// The setup configuration the finished session ran with, when known.
  final TrainerConfig? config;
}

/// Builds the session inputs for [config] and pushes the session route with
/// them. A failure (song gone, stale config) is said out loud in a snackbar
/// and logged — the user stays on the setup screen, nothing is guessed.
///
/// [replace] swaps the current route instead of stacking on top of it: the
/// result screen's Retry must not leave a finished result underneath the new
/// session.
Future<void> launchSongTrainerSession(
  BuildContext context,
  WidgetRef ref,
  TrainerConfig config, {
  bool replace = false,
}) async {
  final prepared = await ref.read(songTrainerLauncherProvider).prepare(config);
  if (!context.mounted) return;
  switch (prepared) {
    case Success(:final value):
      final location = AppRoutes.songTrainerSession.replaceFirst(
        ':songId',
        Uri.encodeComponent(config.songId.value),
      );
      if (replace) {
        context.pushReplacement(location, extra: value);
      } else {
        unawaited(context.push<void>(location, extra: value));
      }
    case Failure(:final error):
      ref
          .read(appLoggerProvider)
          .warning(
            'song_trainer_launch_failed',
            fields: <String, Object?>{'code': error.code},
          );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).songTrainerLaunchFailed),
        ),
      );
  }
}

/// The result screen's "Next section": starts the section that follows the
/// range just played, or returns to the song overview when there is none.
///
/// The overview is the honest fallback: it is where the user picks what to
/// practise next, and it keeps the song in front of them instead of dropping
/// them back into a finished result.
Future<void> advanceSongTrainerSession(
  BuildContext context,
  WidgetRef ref,
  TrainerConfig config,
) async {
  final loaded = await ref.read(songRepositoryProvider).get(config.songId);
  if (!context.mounted) return;
  final document = loaded.valueOrNull;
  final section = document == null
      ? null
      : nextSongSectionAfter(document.sections, config.range);
  if (section == null) {
    returnToSongOverview(context, config.songId);
    return;
  }
  await launchSongTrainerSession(
    context,
    ref,
    songTrainerConfigForSection(config, section),
    replace: true,
  );
}

/// Replaces the stack with the song's overview route.
void returnToSongOverview(BuildContext context, SongId songId) {
  final location = AppRoutes.songTrainerOverview.replaceFirst(
    ':songId',
    Uri.encodeComponent(songId.value),
  );
  context.go(location);
}

/// The first section that starts at or after [range]'s end, or `null`.
///
/// Sections are not required to be stored in playing order, so the search is
/// a minimum over the candidates rather than a scan of the list order.
@visibleForTesting
SongSection? nextSongSectionAfter(
  List<SongSection> sections,
  MeasureRange range,
) {
  SongSection? best;
  for (final section in sections) {
    if (section.startMeasure < range.endExclusive) continue;
    if (best == null || section.startMeasure < best.startMeasure) {
      best = section;
    }
  }
  return best;
}

/// [config] retargeted at [section]. Every other setup choice (track, mode,
/// speed, count-in, metronome, loop shape, tuning/capo reminders) is carried
/// over verbatim — "next section" must not silently change how the user
/// practises.
@visibleForTesting
TrainerConfig songTrainerConfigForSection(
  TrainerConfig config,
  SongSection section,
) {
  final range = MeasureRange(
    start: section.startMeasure,
    endExclusive: section.endMeasureExclusive,
  );
  return TrainerConfig(
    songId: config.songId,
    songRevision: config.songRevision,
    trackId: config.trackId,
    selection: SectionRange(section.id),
    range: range,
    mode: config.mode,
    targetSpeed: config.targetSpeed,
    countInBars: config.countInBars,
    metronomeEnabled: config.metronomeEnabled,
    loopConfig: LoopConfig(
      range: range,
      maxRepeats: config.loopConfig.maxRepeats,
      pauseBetweenLoops: config.loopConfig.pauseBetweenLoops,
      countInEachLoop: config.loopConfig.countInEachLoop,
      autoAdvance: config.loopConfig.autoAdvance,
    ),
    tuningReminder: config.tuningReminder,
    capo: config.capo,
    capoReminder: config.capoReminder,
  );
}
