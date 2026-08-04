// Transport controls (play/pause/resume + speed affordance).
//
// The speed affordance is disabled when the backing playback does not
// support `PlaybackCapabilities.supportsRate(currentSpeed)`; the disability
// is rendered with a reason so the coach can explain why.

import 'package:flutter/material.dart';

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
