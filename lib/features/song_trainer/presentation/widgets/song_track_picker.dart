import 'package:flutter/material.dart';

import '../../application/trainer/song_trainer_setup_state.dart';

/// Selects a structural song track without inspecting raw track events.
final class SongTrackPicker extends StatelessWidget {
  const SongTrackPicker({
    required this.tracks,
    required this.onSelected,
    super.key,
  });

  final List<TrainerTrackOption> tracks;
  final ValueChanged<TrainerTrackOption> onSelected;

  @override
  Widget build(BuildContext context) {
    String? selectedId;
    for (final track in tracks) {
      if (track.isSelected) {
        selectedId = track.id.value;
        break;
      }
    }
    return RadioGroup<String>(
      groupValue: selectedId,
      onChanged: (id) {
        if (id == null) return;
        for (final track in tracks) {
          if (track.id.value == id && track.isEnabled) {
            onSelected(track);
            return;
          }
        }
      },
      child: Column(
        children: <Widget>[
          for (final track in tracks)
            RadioListTile<String>(
              key: Key('song-track-${track.id.value}'),
              value: track.id.value,
              title: Text(track.name),
              enabled: track.isEnabled,
            ),
        ],
      ),
    );
  }
}
