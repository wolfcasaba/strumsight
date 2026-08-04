import 'package:flutter/material.dart';

import '../../domain/models/note_scoring_models.dart';

/// Compact visual feedback for resolved monophonic note targets.
final class NoteLane extends StatelessWidget {
  const NoteLane({super.key, required this.targets, this.update});

  final List<NoteScoringTarget> targets;
  final NoteScoringUpdate? update;

  @override
  Widget build(BuildContext context) {
    final latestById = <String, NoteScoringNoteUpdate>{
      for (final noteUpdate in update?.noteUpdates ?? const [])
        noteUpdate.targetId: noteUpdate,
    };
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 36,
      child: Row(
        children: <Widget>[
          for (final target in targets)
            Expanded(
              flex: target.duration.inMicroseconds,
              child: _NoteSegment(
                key: ValueKey<String>('note-lane-${target.id}'),
                targetId: target.id,
                update: latestById[target.id],
                colors: colors,
              ),
            ),
        ],
      ),
    );
  }
}

final class _NoteSegment extends StatelessWidget {
  const _NoteSegment({
    super.key,
    required this.targetId,
    required this.update,
    required this.colors,
  });

  final String targetId;
  final NoteScoringNoteUpdate? update;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    final grade = update?.pitchGrade;
    return Semantics(
      label: targetId,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _colorFor(grade),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Icon(_iconFor(grade), size: 16, color: colors.onPrimary),
      ),
    );
  }

  Color _colorFor(NotePitchGrade? grade) => switch (grade) {
    NotePitchGrade.exact => colors.primary,
    NotePitchGrade.near => colors.tertiary,
    NotePitchGrade.offPitch || NotePitchGrade.wrongNote => colors.error,
    NotePitchGrade.noStablePitch => colors.surfaceContainerHighest,
    null => colors.surfaceContainerLow,
  };

  IconData _iconFor(NotePitchGrade? grade) => switch (grade) {
    NotePitchGrade.exact => Icons.check,
    NotePitchGrade.near => Icons.tune,
    NotePitchGrade.offPitch || NotePitchGrade.wrongNote => Icons.close,
    NotePitchGrade.noStablePitch => Icons.remove,
    null => Icons.circle_outlined,
  };
}
