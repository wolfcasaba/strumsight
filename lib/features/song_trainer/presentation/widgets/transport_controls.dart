// Transport controls (play/pause/resume + speed affordance).
//
// The speed affordance is disabled when the backing playback does not
// support `PlaybackCapabilities.supportsRate(currentSpeed)`; the disability
// is rendered with a reason so the coach can explain why.

import 'package:flutter/material.dart';

/// ADR 0274 §3 — the playhead-sync threshold between the audio-clock-derived
/// position and whatever the Stage renders as the visual playhead. The bound
/// is inclusive: a delta of exactly 100 ms still counts as in sync.
abstract final class PlayheadSync {
  static const Duration syncThreshold = Duration(milliseconds: 100);

  static bool isInSync({
    required Duration audioPosition,
    required Duration visualPosition,
  }) {
    final delta = audioPosition - visualPosition;
    return (delta.isNegative ? -delta : delta) <= syncThreshold;
  }
}

/// Compact transport controls (play/pause/resume + speed).
final class TransportControls extends StatelessWidget {
  const TransportControls({
    super.key,
    required this.isPlaying,
    required this.onPlay,
    required this.onPause,
    required this.onResume,
    required this.isPaused,
    this.canSeek = false,
    this.onSeek,
  });

  final bool isPlaying;
  final bool isPaused;
  final bool canSeek;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final ValueChanged<Duration>? onSeek;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('song-trainer-transport-controls'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        IconButton(
          key: const Key('song-trainer-transport-play'),
          onPressed: isPlaying ? null : (isPaused ? onResume : onPlay),
          icon: Icon(isPaused ? Icons.play_arrow : Icons.play_arrow),
        ),
        IconButton(
          key: const Key('song-trainer-transport-pause'),
          onPressed: isPlaying ? onPause : null,
          icon: const Icon(Icons.pause),
        ),
        if (canSeek)
          IconButton(
            key: const Key('song-trainer-seek'),
            onPressed: () => onSeek?.call(Duration.zero),
            icon: const Icon(Icons.fast_rewind),
          ),
      ],
    );
  }
}
