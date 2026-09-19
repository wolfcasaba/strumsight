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
import '../../application/trainer/song_transport_state.dart';
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

/// The Stage's own measured outcome, returned to a caller that pushed
/// [SongTrainerSessionRoute] directly and asked for one (E17-R03/D4 — the
/// Setlist runner is the only caller today). Exactly one of the two
/// factories applies: a scored session reports its own [SongTrainerResult];
/// a playback-only session (no scoring, no microphone) instead reports the
/// transport's own measured elapsed active time once its timeline actually
/// reaches [SongTransportPhase.completed] — never a wall-clock guess.
final class SongTrainerSessionOutcome {
  /// A scored session's own, already-mapped result.
  const SongTrainerSessionOutcome.scored(SongTrainerResult result)
    : scoredResult = result,
      playbackActiveDuration = null;

  /// A playback-only session whose transport reached its measured end.
  const SongTrainerSessionOutcome.playback(Duration activeDuration)
    : scoredResult = null,
      playbackActiveDuration = activeDuration;

  final SongTrainerResult? scoredResult;
  final Duration? playbackActiveDuration;
}

/// Hosts one Song Trainer session.
final class SongTrainerSessionRoute extends ConsumerStatefulWidget {
  /// Stable constructor.
  const SongTrainerSessionRoute({
    required this.songId,
    required this.args,
    this.returnResultToCaller = false,
    super.key,
  });

  /// Route path parameter, forwarded to the Stage.
  final String songId;

  /// Session data assembled by `loadSongTrainerSession`.
  final SongTrainerSessionArgs args;

  /// When `true`, a naturally-reached completion pops this route back to
  /// its caller with a [SongTrainerSessionOutcome] instead of pushing the
  /// interactive result screen (E17-R03/D4). The registered
  /// `songTrainerSession` `GoRoute` never sets this, so the single-song
  /// setup→session→result path (including "practice again") stays
  /// bit-identical; only a caller that pushes this widget directly (the
  /// Setlist runner) opts in.
  final bool returnResultToCaller;

  @override
  ConsumerState<SongTrainerSessionRoute> createState() =>
      _SongTrainerSessionRouteState();
}

final class _SongTrainerSessionRouteState
    extends ConsumerState<SongTrainerSessionRoute> {
  SongTrainerController? _controller;
  StreamSubscription<SongTrainerEffect>? _effects;
  StreamSubscription<SongTrainerState>? _states;
  bool _resultOpen = false;
  bool _outcomeReturned = false;

  @override
  void dispose() {
    _effects?.cancel();
    _states?.cancel();
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
      _states?.cancel();
      // Only a playback-only session (no `NavigateToSongTrainerResult`
      // effect ever fires for it — `_finishAndFinalize` requires a scored
      // Practice session) needs this path, and only when the caller asked
      // for a returned outcome at all.
      _states = widget.returnResultToCaller && controller.isPlaybackOnly
          ? controller.states.listen(_onState)
          : null;
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
    if (widget.returnResultToCaller) {
      _returnOutcome(SongTrainerSessionOutcome.scored(effect.result));
      return;
    }
    if (_resultOpen || !mounted) return;
    _resultOpen = true;
    unawaited(_openResult(effect.result));
  }

  /// Playback-only completion signal (E17-R03/D4) — the transport's own
  /// phase transition to [SongTransportPhase.completed], never a guess.
  /// [SongTrainerController.finish] is not called automatically anywhere in
  /// this route: the Stage always drives it, so this only fires once the
  /// timeline genuinely finished playing.
  void _onState(SongTrainerState state) {
    if (state.transportState.phase != SongTransportPhase.completed) return;
    _returnOutcome(
      SongTrainerSessionOutcome.playback(state.transportState.activePosition),
    );
  }

  void _returnOutcome(SongTrainerSessionOutcome outcome) {
    if (_outcomeReturned || !mounted) return;
    _outcomeReturned = true;
    Navigator.of(context).pop(outcome);
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
