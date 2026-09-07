// Production host of [SongResultScreen] (javító sáv 2026-09-06, audit §5.2
// "A `SongResultScreen` retry/next callbackjei").
//
// The router used to build the screen with `result` alone, so both CTAs were
// rendered with `onPressed: null` — two visible, permanently dead buttons on
// the screen the user reaches at the end of every session. This route is the
// missing composition: it carries the session's `TrainerConfig` through the
// result payload, so Retry can relaunch the exact same song + config and
// Next can move on to the following section (falling back to the song
// overview when the song has none left).
//
// It also supplies the progress projection the screen has always accepted:
// the per-measure records the trainer now commits are read back through
// `songProgressAggregateProvider`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/progress/song_progress_aggregator.dart';
import '../../application/song_trainer_providers.dart';
import '../../domain/models/trainer_config.dart';
import '../song_trainer_launch.dart';
import 'song_result_screen.dart';

/// Route-level composition for the Song Trainer result screen.
final class SongTrainerResultRoute extends ConsumerWidget {
  const SongTrainerResultRoute({super.key, required this.args});

  final SongTrainerResultArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = args.config;
    final progress = _progress(ref);
    if (config == null) {
      // No configuration travelled with the result (a restored stack, or a
      // hand-built payload): the CTAs stay disabled rather than guessing a
      // song and a range to restart.
      return SongResultScreen(result: args.result, progress: progress);
    }
    return SongResultScreen(
      result: args.result,
      progress: progress,
      onRetry: () => _retry(context, ref, config),
      onNextSection: () => _next(context, ref, config),
    );
  }

  void _retry(BuildContext context, WidgetRef ref, TrainerConfig config) {
    unawaited(launchSongTrainerSession(context, ref, config, replace: true));
  }

  void _next(BuildContext context, WidgetRef ref, TrainerConfig config) {
    unawaited(advanceSongTrainerSession(context, ref, config));
  }

  /// The stored projection for the song this result belongs to, or `null`
  /// while it loads / when there is nothing to show. Never a fabricated
  /// aggregate: an empty projection renders no card.
  SongProgressAggregate? _progress(WidgetRef ref) {
    final reference = args.result.verdicts.firstOrNull?.reference;
    if (reference == null) return null;
    final key = SongProgressKey(
      songId: reference.songId,
      revision: reference.songRevision,
    );
    final aggregate = ref.watch(songProgressAggregateProvider(key)).value;
    if (aggregate == null || aggregate.measures.isEmpty) return null;
    return aggregate;
  }
}
