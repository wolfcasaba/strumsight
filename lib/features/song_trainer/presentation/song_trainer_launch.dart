// Javító sáv 2026-09-06 (R3): the router's production handler for the
// Setup screen's Start button. Until now the route registered
// `TrainerSetupScreen(songId: ...)` without `onComplete`, so Start was a
// no-op in the shipped APK.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_route.dart';
import '../../../core/foundation/app_result.dart';
import '../../../core/logging/logger_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../application/trainer/song_trainer_launcher.dart';
import '../domain/models/trainer_config.dart';

/// Builds the session inputs for [config] and pushes the session route with
/// them. A failure (song gone, stale config) is said out loud in a snackbar
/// and logged — the user stays on the setup screen, nothing is guessed.
Future<void> launchSongTrainerSession(
  BuildContext context,
  WidgetRef ref,
  TrainerConfig config,
) async {
  final prepared = await ref.read(songTrainerLauncherProvider).prepare(config);
  if (!context.mounted) return;
  switch (prepared) {
    case Success(:final value):
      final location = AppRoutes.songTrainerSession.replaceFirst(
        ':songId',
        Uri.encodeComponent(config.songId.value),
      );
      unawaited(context.push<void>(location, extra: value));
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
