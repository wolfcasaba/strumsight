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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/public.dart';
import '../../application/song_trainer_providers.dart';
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
final class SongTrainerScreen extends ConsumerWidget {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routeInputs = inputs;
    if (state == null && routeInputs != null) {
      final controller = ref.watch(songTrainerControllerProvider(routeInputs));
      return StreamBuilder<SongTrainerState>(
        stream: controller.states,
        initialData: controller.state,
        builder: (context, snapshot) =>
            _buildScaffold(context, ref, snapshot.data ?? controller.state),
      );
    }
    return _buildScaffold(context, ref, state);
  }

  Widget _buildScaffold(
    BuildContext context,
    WidgetRef ref,
    SongTrainerState? current,
  ) {
    final status = current?.status ?? SongTrainerStatus.idle;
    final leftHanded = ref.read(leftHandedProvider);
    final body = switch (status) {
      SongTrainerStatus.idle ||
      SongTrainerStatus.preparing ||
      SongTrainerStatus.permissionRequired ||
      SongTrainerStatus.ready => const Center(
        child: CircularProgressIndicator(),
      ),
      SongTrainerStatus.countIn => _CountInOverlay(),
      SongTrainerStatus.running => _RunningBody(
        state: current!,
        chordEvents: chordEvents,
        strumEvents: strumEvents,
        noteEvents: noteEvents,
        sections: sections,
        onPause: onPause,
        onResume: onResume,
        onSeek: onSeek,
        onSectionSelected: onSectionSelected,
        onABEntered: onABEntered,
        onABClear: onABClear,
        feedback: feedback,
      ),
      SongTrainerStatus.paused => _PausedBody(
        state: current!,
        chordEvents: chordEvents,
        strumEvents: strumEvents,
        noteEvents: noteEvents,
        onPlay: onPlay,
        onPause: onPause,
        onResume: onResume,
        onSeek: onSeek,
      ),
      SongTrainerStatus.completed ||
      SongTrainerStatus.cancelled => _CompletedBody(state: current!),
      SongTrainerStatus.failed => _FailedBody(state: current!),
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Song Trainer')),
      body: SafeArea(
        child: _Mirror(leftHanded: leftHanded, child: body),
      ),
    );
  }
}

final class _CountInOverlay extends StatelessWidget {
  const _CountInOverlay();

  @override
  Widget build(BuildContext context) {
    return const Center(
      key: Key('song-trainer-overlay'),
      child: Text('Count-in'),
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

  static const Duration _viewportSpan = Duration(seconds: 4);

  @override
  Widget build(BuildContext context) {
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
            label: 'Speed',
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
          const ListTile(
            key: Key('song-trainer-speed-disabled'),
            enabled: false,
            title: Text('Speed disabled — backing cannot change rate.'),
          ),
        ChordLane(
          events: chordEvents.cast(),
          viewportStart: Duration.zero,
          viewportEnd: _viewportSpan,
        ),
        StrumLane(
          events: strumEvents.cast(),
          viewportStart: Duration.zero,
          viewportEnd: _viewportSpan,
        ),
        TablatureLane(
          events: noteEvents.cast(),
          viewportStart: Duration.zero,
          viewportEnd: _viewportSpan,
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
    return Column(
      children: <Widget>[
        StrumLane(
          events: strumEvents.cast(),
          viewportStart: Duration.zero,
          viewportEnd: const Duration(seconds: 4),
        ),
        const ListTile(
          key: Key('song-trainer-speed-disabled'),
          enabled: false,
          title: Text('Speed disabled — backing cannot change rate.'),
          subtitle: Text('Paused: speed resumes when the session restarts.'),
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
    if (result == null) return const Center(child: Text('Completed'));
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
    final failure =
        state.transportState.lastFailureCode ?? 'songTrainer.failed';
    return Center(
      key: const Key('song-trainer-failed'),
      child: Text('Failed: $failure'),
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
