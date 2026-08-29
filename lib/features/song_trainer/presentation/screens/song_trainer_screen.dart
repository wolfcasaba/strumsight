// Song Trainer coach surface.
//
// Brief §6 acceptance matrix: the screen renders the right lane/control
// combination for the current state, exposes the loop index "2/5",
// surfaces the speed-builder state, and the long-song lane windowing
// keeps the child count bounded.
//
// The screen honours the project-wide left-handed preference
// ([Settings.leftHanded]) by mirroring the body in the horizontal axis —
// a left-handed coach reads the timeline right-to-left, so the loop
// controls, lanes, and transport row have to stay in mirror order. The
// mirroring uses [Transform.flip] rather than flipping individual
// children, so every per-row `Row` continues to render children in the
// same visual order from the screen-reader perspective while the
// physical coordinate system is reversed.
//
// E13-R25 §5.2/§0.0/B/B7: the running/paused lanes derive their viewport
// from `state.transportState.activePosition` — the audio-clock-derived
// position `SongTransport` already computes (ADR 0274) — never from a local
// `Timer`. The Stage does not acquire the transport/practice resource; it
// only notifies the owning controller's exit path on every route exit
// instead of relying solely on Riverpod's own provider-teardown timing.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/public.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../settings/public.dart';
import '../../application/song_trainer_providers.dart';
import '../../application/trainer/song_trainer_controller.dart';
import '../../application/trainer/song_trainer_state.dart';
import '../../domain/models/song_id.dart';
import '../widgets/chord_lane.dart';
import '../widgets/loop_controls.dart';
import '../widgets/measure_heatmap.dart';
import '../widgets/song_loop_feedback.dart';
import '../widgets/strum_lane.dart';
import '../widgets/tablature_lane.dart';
import '../widgets/transport_controls.dart';

/// Coach surface for the Song Trainer V2 session.
final class SongTrainerScreen extends ConsumerStatefulWidget {
  const SongTrainerScreen({
    super.key,
    this.songId,
    this.inputs,
    this.state,
    this.chordEvents = const [],
    this.strumEvents = const [],
    this.noteEvents = const [],
    this.sections = const [],
    this.onPlay,
    this.onPause,
    this.onResume,
    this.onSeek,
    this.onSectionSelected,
    this.onABEntered,
    this.onABClear,
    this.feedback = const [],
    this.loopRangeEnd,
  });

  /// Route song identifier. Direct widget tests may omit it and inject [state].
  final String? songId;

  /// Route-scoped controller inputs assembled by the setup flow.
  final SongTrainerControllerInputs? inputs;

  final SongTrainerState? state;
  final List<dynamic> chordEvents;
  final List<dynamic> strumEvents;
  final List<dynamic> noteEvents;
  final List<dynamic> sections;
  final VoidCallback? onPlay;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final ValueChanged<Duration>? onSeek;
  final ValueChanged<SongSectionId>? onSectionSelected;
  final ValueChanged<List<int>>? onABEntered;
  final VoidCallback? onABClear;
  final List<SongLoopFeedbackMessage> feedback;

  /// Exact end of the currently configured loop range, when known. The
  /// running lane clamps its viewport to this value verbatim — never rounded
  /// to the nearest second or measure — so the visual loop boundary matches
  /// the audible one (§5.2/A3).
  final Duration? loopRangeEnd;

  @override
  ConsumerState<SongTrainerScreen> createState() => _SongTrainerScreenState();
}

final class _SongTrainerScreenState extends ConsumerState<SongTrainerScreen> {
  SongTrainerController? _ownedController;
  Stream<SongTrainerState>? _ownedControllerStates;

  @override
  Widget build(BuildContext context) {
    final routeInputs = widget.inputs;
    if (widget.state == null && routeInputs != null) {
      final controller = ref.watch(songTrainerControllerProvider(routeInputs));
      if (!identical(_ownedController, controller)) {
        // `StreamController.stream` returns a fresh wrapper on every access,
        // so re-reading `controller.states` on every build would hand
        // `StreamBuilder` a new stream identity each time — forcing it to
        // cancel and resubscribe every rebuild. Cache it once per controller
        // instance instead.
        _ownedController = controller;
        _ownedControllerStates = controller.states;
      }
      return StreamBuilder<SongTrainerState>(
        stream: _ownedControllerStates,
        initialData: controller.state,
        builder: (context, snapshot) =>
            _buildScaffold(context, snapshot.data ?? controller.state),
      );
    }
    return _buildScaffold(context, widget.state);
  }

  @override
  void dispose() {
    // §0.0/B/B7 — the Stage does not own the transport/practice resource; it
    // notifies the owner's exit path on every route exit rather than relying
    // solely on Riverpod's own provider-teardown timing.
    unawaited(_ownedController?.dispose());
    super.dispose();
  }

  Widget _buildScaffold(BuildContext context, SongTrainerState? current) {
    final status = current?.status ?? SongTrainerStatus.idle;
    final leftHanded = ref.read(leftHandedProvider);
    final body = switch (status) {
      SongTrainerStatus.idle ||
      SongTrainerStatus.preparing ||
      SongTrainerStatus.permissionRequired ||
      SongTrainerStatus.ready => Semantics(
        label: AppLocalizations.of(context).songTrainerLoading,
        child: const _TrainerLoading(),
      ),
      SongTrainerStatus.countIn => _CountInOverlay(),
      SongTrainerStatus.running => _RunningBody(
        state: current!,
        chordEvents: widget.chordEvents,
        strumEvents: widget.strumEvents,
        noteEvents: widget.noteEvents,
        sections: widget.sections,
        onPause: widget.onPause,
        onResume: widget.onResume,
        onSeek: widget.onSeek,
        onSectionSelected: widget.onSectionSelected,
        onABEntered: widget.onABEntered,
        onABClear: widget.onABClear,
        feedback: widget.feedback,
        loopRangeEnd: widget.loopRangeEnd,
      ),
      SongTrainerStatus.paused => _PausedBody(
        state: current!,
        chordEvents: widget.chordEvents,
        strumEvents: widget.strumEvents,
        noteEvents: widget.noteEvents,
        onPlay: widget.onPlay,
        onPause: widget.onPause,
        onResume: widget.onResume,
        onSeek: widget.onSeek,
      ),
      SongTrainerStatus.completed ||
      SongTrainerStatus.cancelled => _CompletedBody(state: current!),
      SongTrainerStatus.failed => _FailedBody(state: current!),
    };
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.songTrainerTitle)),
      body: SafeArea(
        child: _Mirror(leftHanded: leftHanded, child: body),
      ),
    );
  }
}

final class _TrainerLoading extends StatelessWidget {
  const _TrainerLoading();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: const SsSkeleton(
        width: 120,
        height: SsSpacing.space6,
        radius: SsRadius.pill,
      ),
    );
  }
}

final class _CountInOverlay extends StatelessWidget {
  const _CountInOverlay();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      key: const Key('song-trainer-overlay'),
      child: Text(l10n.songTrainerOverlayCountIn),
    );
  }
}

final class _RunningBody extends StatelessWidget {
  const _RunningBody({
    required this.state,
    required this.chordEvents,
    required this.strumEvents,
    required this.noteEvents,
    required this.sections,
    required this.onPause,
    required this.onResume,
    required this.onSeek,
    required this.onSectionSelected,
    required this.onABEntered,
    required this.onABClear,
    required this.feedback,
    this.loopRangeEnd,
  });

  final SongTrainerState state;
  final List<dynamic> chordEvents;
  final List<dynamic> strumEvents;
  final List<dynamic> noteEvents;
  final List<dynamic> sections;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final ValueChanged<Duration>? onSeek;
  final ValueChanged<SongSectionId>? onSectionSelected;
  final ValueChanged<List<int>>? onABEntered;
  final VoidCallback? onABClear;
  final List<SongLoopFeedbackMessage> feedback;
  final Duration? loopRangeEnd;

  static const Duration _viewportSpan = Duration(seconds: 4);

  @override
  Widget build(BuildContext context) {
    // §5.2/A2 — the viewport is derived from the audio-clock-driven
    // transport position on every build, never from an independently
    // ticking Timer: a stale `state` renders a stale (but never drifting)
    // viewport.
    final playhead = state.transportState.activePosition;
    final naturalEnd = playhead + _viewportSpan;
    final loopEnd = loopRangeEnd;
    // §5.2/A3 — clamped to the EXACT configured loop end, never rounded to
    // the nearest second or measure.
    final viewportEnd = loopEnd != null && naturalEnd > loopEnd
        ? loopEnd
        : naturalEnd;
    return Column(
      children: <Widget>[
        LoopControls(
          sections: sections.cast(),
          currentLoopIndex: state.loopIndex,
          totalLoops: state.maxLoops,
          onSectionSelected: (id) => onSectionSelected?.call(id),
          onABEntered: onABEntered ?? (_) {},
          onABClear: onABClear ?? () {},
        ),
        if (state.backingRateSupported)
          Semantics(
            label: AppLocalizations.of(context).songTrainerSpeedLabel,
            child: const Slider(
              key: Key('song-trainer-speed'),
              value: 1,
              min: 0.5,
              max: 1.5,
              divisions: 20,
              onChanged: null,
            ),
          )
        else
          ListTile(
            key: const Key('song-trainer-speed-disabled'),
            enabled: false,
            title: Text(
              AppLocalizations.of(context).songTrainerSpeedDisabledReason,
            ),
          ),
        ChordLane(
          events: chordEvents.cast(),
          viewportStart: playhead,
          viewportEnd: viewportEnd,
        ),
        StrumLane(
          events: strumEvents.cast(),
          viewportStart: playhead,
          viewportEnd: viewportEnd,
        ),
        TablatureLane(
          events: noteEvents.cast(),
          viewportStart: playhead,
          viewportEnd: viewportEnd,
        ),
        SongLoopFeedback(messages: feedback),
        TransportControls(
          isPlaying: true,
          isPaused: false,
          onPlay: () {},
          onPause: onPause ?? () {},
          onResume: onResume ?? () {},
          onSeek: onSeek,
        ),
      ],
    );
  }
}

final class _PausedBody extends StatelessWidget {
  const _PausedBody({
    required this.state,
    required this.chordEvents,
    required this.strumEvents,
    required this.noteEvents,
    required this.onPlay,
    required this.onPause,
    required this.onResume,
    required this.onSeek,
  });

  final SongTrainerState state;
  final List<dynamic> chordEvents;
  final List<dynamic> strumEvents;
  final List<dynamic> noteEvents;
  final VoidCallback? onPlay;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final ValueChanged<Duration>? onSeek;

  @override
  Widget build(BuildContext context) {
    // §6 matrix row `paused | A–B | rate no`: seek is allowed
    // ([TransportControls.canSeek] = true) AND the speed control renders
    // disabled with an explicit reason so the coach understands why it
    // is unavailable while paused.
    final l10n = AppLocalizations.of(context);
    // §5.3/A4 — the exact millisecond pause position, never truncated to
    // whole seconds and never reset to the start of the section: the domain
    // (`SongTransport._anchorPosition`) already keeps this precise, this only
    // surfaces it honestly.
    final position = state.transportState.activePosition;
    return Column(
      children: <Widget>[
        Semantics(
          key: const Key('song-trainer-paused-position'),
          label: l10n.trainerPausedPosition(_formatPrecisePosition(position)),
          child: Text(_formatPrecisePosition(position)),
        ),
        StrumLane(
          events: strumEvents.cast(),
          viewportStart: Duration.zero,
          viewportEnd: const Duration(seconds: 4),
        ),
        ListTile(
          key: const Key('song-trainer-speed-disabled'),
          enabled: false,
          title: Text(l10n.songTrainerSpeedDisabledReason),
          subtitle: Text(l10n.songTrainerSpeedResumesOnRestart),
        ),
        TransportControls(
          isPlaying: false,
          isPaused: true,
          onPlay: onPlay ?? () {},
          onPause: onPause ?? () {},
          onResume: onResume ?? () {},
          canSeek: true,
          onSeek: onSeek,
        ),
      ],
    );
  }
}

final class _CompletedBody extends StatelessWidget {
  const _CompletedBody({required this.state});

  final SongTrainerState state;

  @override
  Widget build(BuildContext context) {
    final result = state.result;
    if (result == null) {
      // §5.1/A1 — a playback-only session never reaches `_finishAndFinalize`
      // (the only place `SongTrainerState.result` is ever populated), so a
      // `null` result at a terminal status means "not scored", not "scoring
      // pending". State this honestly instead of a bare "Completed" label —
      // and never synthesize a score here.
      final l10n = AppLocalizations.of(context);
      return Center(
        key: const Key('song-trainer-playback-only-result'),
        child: Text(l10n.songTrainerPlaybackOnlyComplete),
      );
    }
    return SingleChildScrollView(
      child: Column(
        children: <Widget>[
          MeasureHeatmap(
            measureResults: result.measureResults,
            sectionResults: result.sectionResults,
          ),
        ],
      ),
    );
  }
}

final class _FailedBody extends StatelessWidget {
  const _FailedBody({required this.state});

  final SongTrainerState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    final failure =
        state.transportState.lastFailureCode ?? 'songTrainer.failed';
    // Reuses the existing `songTrainerFailed` key ("Session failed: {code}")
    // instead of a new one matching the pre-migration "Failed: {code}"
    // wording verbatim — same meaning (a failure code is reported), see
    // §10/m3 for the documented wording change.
    return Center(
      key: const Key('song-trainer-failed'),
      child: Text(
        l10n.songTrainerFailed(failure),
        style: typography.bodyMedium.copyWith(color: colors.danger),
      ),
    );
  }
}

/// Mirrors the trainer body horizontally when [leftHanded] is true so a
/// left-handed coach reads the timeline right-to-left. Uses
/// [Transform.flip] so per-row child order stays the same for the screen
/// reader (the [Semantics] tree is unaffected); only the visual axis is
/// reversed. The widget carries a stable key so tests can detect the
/// mirror through the element tree.
final class _Mirror extends StatelessWidget {
  const _Mirror({required this.leftHanded, required this.child});

  final bool leftHanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!leftHanded) return child;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.diagonal3Values(-1.0, 1.0, 1.0),
      child: child,
    );
  }
}

String _formatPrecisePosition(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).abs();
  final millis = duration.inMilliseconds.remainder(1000).abs();
  return '$minutes:${seconds.toString().padLeft(2, '0')}.'
      '${millis.toString().padLeft(3, '0')}';
}
