import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/application/context/adapters/song_result_context_adapter.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_snapshot.dart';
import 'package:strumsight/features/song_trainer/domain/public.dart';

void main() {
  final document = _documentWithPrivateSongContent();

  test('projects public section and measure structure for a song debrief', () {
    final adapted = const SongResultContextAdapter(
      schemaVersion: 'songTrainer.structure.v1',
    ).adapt(document: document, capabilityReport: _capabilityReport());

    expect(adapted.key, TutorContextFieldKey.songTrainer);
    expect(adapted.availability, ContextFieldAvailability.available);
    expect(adapted.values['songId'], 'song-1');
    expect(adapted.values['revision'], 4);
    expect(adapted.values['title'], 'Safe song structure');
    expect(adapted.values['measureCount'], 3);
    expect(adapted.values['sections'], <Object?>[
      <String, Object?>{
        'id': 'intro',
        'name': 'Intro',
        'kind': 'intro',
        'startMeasure': 0,
        'endMeasureExclusive': 1,
      },
      <String, Object?>{
        'id': 'chorus',
        'name': 'Chorus',
        'kind': 'chorus',
        'startMeasure': 1,
        'endMeasureExclusive': 3,
      },
    ]);
    expect(adapted.provenance.sourceFeature, ContextSourceFeature.songTrainer);
    expect(adapted.provenance.schemaVersion, 'songTrainer.structure.v1');
  });

  test('withholds unsupported pitch and chord actions from context', () {
    final adapted =
        const SongResultContextAdapter(
          schemaVersion: 'songTrainer.structure.v1',
        ).adapt(
          document: document,
          capabilityReport: _capabilityReport(
            chordScoring: false,
            pitchScoring: false,
          ),
        );

    expect(adapted.values['suggestedActions'], <Object?>['reviewStructure']);
    expect(adapted.values['chordScoringAvailable'], isFalse);
    expect(adapted.values['pitchScoringAvailable'], isFalse);
  });

  test('redacts backing audio and complete lyrics from model context', () {
    final adapted = const SongResultContextAdapter(
      schemaVersion: 'songTrainer.structure.v1',
    ).adapt(document: document, capabilityReport: _capabilityReport());

    final serialized = adapted.toJson().toString();
    expect(serialized, isNot(contains('private lyric line')));
    expect(serialized, isNot(contains('backing-audio-private')));
    expect(serialized, isNot(contains('backingAudio')));
    expect(serialized, isNot(contains('lyrics')));
  });

  test('imports only the Song Trainer public domain boundary', () {
    const path =
        'lib/features/ai_tutor/application/context/adapters/song_result_context_adapter.dart';
    final imports = File(path)
        .readAsStringSync()
        .split('\n')
        .where((line) => line.trimLeft().startsWith('import '));

    expect(
      imports.join('\n'),
      contains('features/song_trainer/domain/public.dart'),
    );
    expect(
      imports.where((line) => line.contains('package:strumsight/features/')),
      everyElement(contains('features/song_trainer/domain/public.dart')),
    );
  });
}

SongDocument _documentWithPrivateSongContent() => SongDocument(
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
    SongMeasure(index: 2, durationBeats: BeatPosition.fromBeats(4)),
  ],
  sections: <SongSection>[
    SongSection(
      id: SongSectionId('intro'),
      name: 'Intro',
      startMeasure: 0,
      endMeasureExclusive: 1,
      kind: SongSectionKind.intro,
    ),
    SongSection(
      id: SongSectionId('chorus'),
      name: 'Chorus',
      startMeasure: 1,
      endMeasureExclusive: 3,
      kind: SongSectionKind.chorus,
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

SongCapabilityReport _capabilityReport({
  bool chordScoring = true,
  bool pitchScoring = true,
}) => SongCapabilityReport(
  profile: SongCapabilityProfile.trainer,
  chord: SongChordCapability(
    display: true,
    scoring: chordScoring,
    hasUnsupportedChord: !chordScoring,
  ),
  pitch: SongPitchCapability(
    display: true,
    scoring: pitchScoring,
    isMonophonic: pitchScoring,
  ),
  canPersist: true,
  canImportPreview: true,
  canExport: true,
  canTrain: true,
);
