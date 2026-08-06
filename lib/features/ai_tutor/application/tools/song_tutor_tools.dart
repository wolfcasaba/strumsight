import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool.dart';
import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool_result.dart';
import 'package:strumsight/features/song_trainer/domain/public.dart';

/// Read-only Song Trainer tools built from the public domain boundary.
abstract final class SongTutorTools {
  static const String getSongSectionsName = 'getSongSections';

  static List<TutorTool> toolsFor({required SongDocument document}) =>
      List<TutorTool>.unmodifiable(<TutorTool>[_GetSongSectionsTool(document)]);
}

final class _GetSongSectionsTool implements TutorTool {
  _GetSongSectionsTool(this._document);

  final SongDocument _document;

  @override
  String get name => SongTutorTools.getSongSectionsName;

  @override
  TutorToolPermission get permission => TutorToolPermission.readLocal;

  @override
  TutorToolSchema get inputSchema =>
      TutorToolSchema(toolName: name, fields: const <TutorToolSchemaField>[]);

  @override
  TutorToolProvenance get provenance => const TutorToolProvenance(
    source: 'song_trainer.public_structure',
    schemaVersion: 'songTrainer.structure.v1',
  );

  @override
  Future<TutorToolPayload> execute(TutorToolInput input) async {
    if (input.values.isNotEmpty) throw const TutorToolInputException();
    return TutorToolPayload(<String, Object?>{
      'songId': _document.id.value,
      'revision': _document.revision,
      'title': _document.metadata.title,
      'measureCount': _document.measures.length,
      'sections': <Object?>[
        for (final section in _document.sections)
          <String, Object?>{
            'id': section.id.value,
            'name': section.name,
            'kind': section.kind.name,
            'startMeasure': section.startMeasure,
            'endMeasureExclusive': section.endMeasureExclusive,
          },
      ],
    });
  }
}
