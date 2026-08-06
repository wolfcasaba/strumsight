import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/application/tools/song_tutor_tools.dart';
import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool.dart';
import 'package:strumsight/features/song_trainer/domain/public.dart';

void main() {
  final document = _document();

  test('getSongSections returns only public section structure', () async {
    final tool = SongTutorTools.toolsFor(document: document).single;

    final payload = await tool.execute(
      TutorToolInput(const <String, Object?>{}),
    );

    expect(tool.name, SongTutorTools.getSongSectionsName);
    expect(payload.values, <String, Object?>{
      'songId': 'song-1',
      'revision': 4,
      'title': 'Safe song structure',
      'measureCount': 2,
      'sections': <Object?>[
        <String, Object?>{
          'id': 'verse',
          'name': 'Verse',
          'kind': 'verse',
          'startMeasure': 0,
          'endMeasureExclusive': 2,
        },
      ],
    });
    expect(payload.values.toString(), isNot(contains('private lyric line')));
    expect(payload.values.toString(), isNot(contains('backing-audio-private')));
  });

  test('getSongSections rejects unexpected input', () async {
    final tool = SongTutorTools.toolsFor(document: document).single;

    expect(
      () =>
          tool.execute(TutorToolInput(const <String, Object?>{'section': '1'})),
      throwsA(isA<TutorToolInputException>()),
    );
  });

  test('imports only the Song Trainer public domain boundary', () {
    const path =
        'lib/features/ai_tutor/application/tools/song_tutor_tools.dart';
    final imports = File(path)
        .readAsStringSync()
        .split('\n')
        .where((line) => line.trimLeft().startsWith('import '));

    expect(
      imports.join('\n'),
      contains('features/song_trainer/domain/public.dart'),
    );
    expect(
      imports.where((line) => line.contains('features/song_trainer/')),
      everyElement(contains('features/song_trainer/domain/public.dart')),
    );
  });
}

SongDocument _document() => SongDocument(
  schemaVersion: songDocumentSchemaVersion,
  id: SongId('song-1'),
  revision: 4,
  metadata: SongMetadata(title: 'Safe song structure'),
  source: SongSource(
    type: SongSourceType.createdInApp,
    originalFileName: 'song.strum',
    sha256: 'a' * 64,
    importedAt: DateTime.utc(2026, 8, 6),
    importerVersion: 'test@1',
  ),
  createdAt: DateTime.utc(2026, 8, 6),
  updatedAt: DateTime.utc(2026, 8, 6),
  measures: <SongMeasure>[
    SongMeasure(index: 0, durationBeats: BeatPosition.fromBeats(4)),
    SongMeasure(index: 1, durationBeats: BeatPosition.fromBeats(4)),
  ],
  sections: <SongSection>[
    SongSection(
      id: SongSectionId('verse'),
      name: 'Verse',
      startMeasure: 0,
      endMeasureExclusive: 2,
      kind: SongSectionKind.verse,
    ),
  ],
  tracks: <SongTrack>[
    LyricsTrack(
      id: SongTrackId('lyrics'),
      name: 'Lyrics',
      instrument: SongInstrument(name: 'Vocals'),
      events: <SongLyricEvent>[
        SongLyricEvent(
          id: SongEventId('lyric-1'),
          at: Duration.zero,
          text: 'private lyric line',
        ),
      ],
    ),
    BackingAudioTrack(
      id: SongTrackId('backing'),
      name: 'Backing audio',
      instrument: SongInstrument(name: 'Backing'),
      assetId: SongAssetId('backing-audio-private'),
      gridOffset: Duration.zero,
    ),
  ],
);
