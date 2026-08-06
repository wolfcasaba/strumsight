import 'package:strumsight/features/song_trainer/domain/public.dart';

import '../tutor_context_snapshot.dart';

/// Projects only public Song Trainer structure and scoring capability.
///
/// Lyrics, backing audio, asset references, source data, and track events are
/// deliberately excluded from the tutor context.
final class SongResultContextAdapter {
  const SongResultContextAdapter({
    this.schemaVersion = 'songTrainer.structure.v1',
  });

  final String schemaVersion;

  TutorContextField adapt({
    required SongDocument document,
    required SongCapabilityReport capabilityReport,
  }) => TutorContextField.available(
    key: TutorContextFieldKey.songTrainer,
    values: <String, Object?>{
      'songId': document.id.value,
      'revision': document.revision,
      'title': document.metadata.title,
      'measureCount': document.measures.length,
      'sections': <Object?>[
        for (final section in document.sections) _sectionValues(section),
      ],
      'chordScoringAvailable': capabilityReport.chord.scoring,
      'pitchScoringAvailable': capabilityReport.pitch.scoring,
      'suggestedActions': _suggestedActions(capabilityReport),
    },
    provenance: ContextProvenance(
      sourceFeature: ContextSourceFeature.songTrainer,
      schemaVersion: schemaVersion,
    ),
  );

  Map<String, Object?> _sectionValues(SongSection section) => <String, Object?>{
    'id': section.id.value,
    'name': section.name,
    'kind': section.kind.name,
    'startMeasure': section.startMeasure,
    'endMeasureExclusive': section.endMeasureExclusive,
  };

  List<Object?> _suggestedActions(SongCapabilityReport capabilityReport) =>
      <Object?>[
        'reviewStructure',
        if (capabilityReport.chord.scoring) 'reviewChords',
        if (capabilityReport.pitch.scoring) 'reviewPitch',
      ];
}
