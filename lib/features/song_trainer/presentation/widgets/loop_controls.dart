// A–B / section loop controls.
//
// §6 acceptance: "Section és valid A–B loop működik; invalid range nem
// indul; loop attempt elkülönül." The A–B loop is only honoured when the
// supplied range resolves inside the song bound; an invalid range is
// rejected with an explicit reason rather than silently clamped.

import 'package:flutter/material.dart';

import '../../domain/models/song_id.dart';
import '../../domain/models/song_section.dart';

/// A–B / section loop controls. The A–B markers live on the song timeline
/// expressed in measures; the section selector is a single dropdown that
/// fans out to a closed-open range.
final class LoopControls extends StatelessWidget {
  const LoopControls({
    super.key,
    required this.sections,
    required this.currentLoopIndex,
    required this.totalLoops,
    required this.onSectionSelected,
    required this.onABEntered,
    required this.onABClear,
    this.activeAB,
  });

  final List<SongSection> sections;
  final int currentLoopIndex;
  final int totalLoops;
  final ValueChanged<SongSectionId> onSectionSelected;
  final ValueChanged<List<int>> onABEntered;
  final VoidCallback onABClear;
  final List<int>? activeAB;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('song-trainer-loop-controls'),
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Semantics(
          label: 'Loop ${currentLoopIndex + 1} of $totalLoops',
          child: Text(
            '${currentLoopIndex + 1}/$totalLoops',
            key: const Key('song-trainer-loop-index'),
          ),
        ),
        DropdownButton<SongSectionId>(
          key: const Key('song-trainer-loop-section'),
          value: sections.isEmpty ? null : sections.first.id,
          items: <DropdownMenuItem<SongSectionId>>[
            for (final section in sections)
              DropdownMenuItem<SongSectionId>(
                value: section.id,
                child: Text(section.name),
              ),
          ],
          onChanged: (selected) {
            if (selected != null) onSectionSelected(selected);
          },
        ),
        if (activeAB == null)
          ElevatedButton(
            key: const Key('song-trainer-loop-ab-set'),
            onPressed: () => onABEntered(<int>[0, 0]),
            child: const Text('A–B'),
          )
        else
          TextButton(
            key: const Key('song-trainer-loop-ab-clear'),
            onPressed: onABClear,
            child: const Text('Clear A–B'),
          ),
      ],
    );
  }
}
