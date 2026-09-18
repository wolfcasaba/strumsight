/// Route host for the Song Trainer session Stage (E16-R01/A2 + A3).
///
/// The Stage screen itself stays a dumb surface: it renders lanes and calls
/// back. Everything that needs the route — the controller the transport
/// controls act on, and the hand-off to the result route when the scored
/// session finishes — lives here, in ONE place, so `app_router.dart` keeps a
/// single-expression builder and the session stays a top-level route
/// (the E13-R08 resource-lifecycle trap: a resource-owning screen inside a
/// shell branch never unmounts on a tab switch).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routing/app_route.dart';
import '../../application/song_trainer_providers.dart';
import '../../application/trainer/song_trainer_controller.dart';
import '../../application/trainer/song_trainer_result.dart';
import '../../application/trainer/song_trainer_session_launcher.dart';
import '../../application/trainer/song_trainer_state.dart';
import 'song_trainer_screen.dart';

/// `extra` payload of the result route.
///
/// [onPracticeAgain] is a live callback rather than data on purpose: the
/// result route sits ON TOP of the still-mounted session route, so "practice
/// again" is a restart of that live session, not a fresh navigation.
final class SongTrainerResultArgs {
  /// Stable constructor.
  const SongTrainerResultArgs({required this.result, this.onPracticeAgain});

  /// The scored outcome to render.
  final SongTrainerResult result;

  /// Restarts the session underneath. `null` when no live session owns it.
  final VoidCallback? onPracticeAgain;
}

/// Hosts one Song Trainer session.
final class SongTrainerSessionRoute extends ConsumerStatefulWidget {
  /// Stable constructor.
  const SongTrainerSessionRoute({
    required this.songId,
    required this.args,
    super.key,
  });

  /// Route path parameter, forwarded to the Stage.
  final String songId;

  /// Session data assembled by `loadSongTrainerSession`.
  final SongTrainerSessionArgs args;

  @override
  ConsumerState<SongTrainerSessionRoute> createState() =>
      _SongTrainerSessionRouteState();
}

final class _SongTrainerSessionRouteState
    extends ConsumerState<SongTrainerSessionRoute> {
  SongTrainerController? _controller;
  StreamSubscription<SongTrainerEffect>? _effects;
  bool _resultOpen = false;

  @override
  void dispose() {
    _effects?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(
      songTrainerControllerProvider(widget.args.inputs),
    );
    if (!identical(_controller, controller)) {
      _controller = controller;
      _effects?.cancel();
      _effects = controller.effects.listen(_onEffect);
    }
    return SongTrainerScreen(
      songId: widget.songId,
      inputs: widget.args.inputs,
      chordEvents: widget.args.chordEvents,
      strumEvents: widget.args.strumEvents,
      noteEvents: widget.args.noteEvents,
      sections: widget.args.sections,
      loopRangeEnd: widget.args.loopRangeEnd,
      onPause: () => unawaited(controller.pause()),
      onResume: () => unawaited(controller.resume()),
      onPlay: () => unawaited(controller.resume()),
      onSeek: (position) => unawaited(controller.seek(position)),
    );
  }

  void _onEffect(SongTrainerEffect effect) {
    if (effect is! NavigateToSongTrainerResult) return;
    if (_resultOpen || !mounted) return;
    _resultOpen = true;
    unawaited(_openResult(effect.result));
  }

  Future<void> _openResult(SongTrainerResult result) async {
    await context.push<void>(
      AppRoutes.songTrainerResult.replaceFirst(
        ':songId',
        Uri.encodeComponent(widget.args.songId.value),
      ),
      extra: SongTrainerResultArgs(
        result: result,
        onPracticeAgain: _practiceAgain,
      ),
    );
    _resultOpen = false;
  }

  /// Restarts the attempt on the session that is still mounted below the
  /// result route. `seek(Duration.zero)` is the controller's own
  /// "new attempt from the top" path — it bumps the attempt id, rewinds the
  /// transport and re-arms the scored Practice session.
  void _practiceAgain() {
    final controller = _controller;
    if (controller == null) return;
    unawaited(controller.seek(Duration.zero));
  }
}
