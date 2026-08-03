import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/data/importers/musicxml_importer.dart';
import 'package:strumsight/features/song_trainer/data/importers/song_importer.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';

void main() {
  const importer = MusicXmlImporter();

  test('imports a 4/4 chord chart with title, meter and harmony', () async {
    final bytes = await File(
      'test/fixtures/song_trainer/musicxml/chord_chart_44.musicxml',
    ).readAsBytes();

    final result = await importer.import(
      _source('chart.musicxml', bytes),
      const SongImportOptions(),
      const NeverCancelledToken(),
    );

    expect(result, isA<Success<SongImportResult>>());
    final document = result.valueOrNull!.document;
    expect(document.metadata.title, 'Four Four Chart');
    expect(document.measures, hasLength(1));
    expect(document.meterMap.changes.single.meter.numerator, 4);
    expect(document.meterMap.changes.single.meter.denominator, 4);
    expect(document.tracks.single, isA<ChordTrack>());
    expect(
      (document.tracks.single as ChordTrack).events.single.symbol.label,
      'C',
    );
  });

  test('preserves pickup, meter and tempo changes deterministically', () async {
    final bytes = await File(
      'test/fixtures/song_trainer/musicxml/tempo_meter_pickup.musicxml',
    ).readAsBytes();

    final result = await importer.import(
      _source('changes.musicxml', bytes),
      const SongImportOptions(),
      const NeverCancelledToken(),
    );

    final document = result.valueOrNull!.document;
    expect(document.measures.first.pickup, isTrue);
    expect(document.meterMap.changes, hasLength(2));
    expect(document.tempoMap.changes.map((change) => change.bpm.bpm), [
      90,
      120,
    ]);
  });

  test('preserves 3/4 and 6/8 meters', () async {
    final waltz = await File(
      'test/fixtures/song_trainer/musicxml/waltz_34.musicxml',
    ).readAsBytes();
    final compound = await File(
      'test/fixtures/song_trainer/musicxml/meter_68.musicxml',
    ).readAsBytes();

    final waltzResult = await importer.import(
      _source('waltz.musicxml', waltz),
      const SongImportOptions(),
      const NeverCancelledToken(),
    );
    final compoundResult = await importer.import(
      _source('compound.musicxml', compound),
      const SongImportOptions(),
      const NeverCancelledToken(),
    );

    expect(
      waltzResult.valueOrNull!.document.meterMap.changes.single.meter.numerator,
      3,
    );
    expect(
      waltzResult
          .valueOrNull!
          .document
          .meterMap
          .changes
          .single
          .meter
          .denominator,
      4,
    );
    expect(
      compoundResult
          .valueOrNull!
          .document
          .meterMap
          .changes
          .single
          .meter
          .numerator,
      6,
    );
    expect(
      compoundResult
          .valueOrNull!
          .document
          .meterMap
          .changes
          .single
          .meter
          .denominator,
      8,
    );
  });

  test('maps tied guitar notes, rests, lyrics and rehearsal markers', () async {
    final bytes = await File(
      'test/fixtures/song_trainer/musicxml/markers_lyrics_repeat.musicxml',
    ).readAsBytes();

    final result = await importer.import(
      _source('notes.musicxml', bytes),
      const SongImportOptions(),
      const NeverCancelledToken(),
    );

    final document = result.valueOrNull!.document;
    expect(document.markers.single.label, 'Verse');
    expect(
      document.tracks.whereType<LyricsTrack>().single.events.single.text,
      'Hello',
    );
    final notes = document.tracks.whereType<NoteTrack>().single.events;
    expect(notes, hasLength(1));
    expect(notes.single.midiPitch, 64);
    expect(notes.single.stringIndex, 5);
    expect(notes.single.fret, 0);
    expect(notes.single.tieGroupId, isNotNull);
    expect(
      result.valueOrNull!.warnings,
      contains(MusicXmlImportWarningCode.repeatExpanded),
    );
  });

  test('preserves both chord symbols in their source order', () async {
    final bytes = await File(
      'test/fixtures/song_trainer/musicxml/two_chords.musicxml',
    ).readAsBytes();

    final result = await importer.import(
      _source('two-chords.musicxml', bytes),
      const SongImportOptions(),
      const NeverCancelledToken(),
    );

    final chords = result.valueOrNull!.document.tracks
        .whereType<ChordTrack>()
        .single
        .events;
    expect(chords.map((chord) => chord.symbol.label), <String>['C', 'G']);
  });

  test(
    'preserves every part and exposes deterministic part previews',
    () async {
      final bytes = await File(
        'test/fixtures/song_trainer/musicxml/multipart_polyphonic.musicxml',
      ).readAsBytes();

      final probe = await importer.probe(
        _source('multipart.musicxml', bytes),
        const NeverCancelledToken(),
      );
      final result = await importer.import(
        _source('multipart.musicxml', bytes),
        const SongImportOptions(),
        const NeverCancelledToken(),
      );

      expect(probe.isRecognized, isTrue);
      expect(probe.parts, hasLength(2));
      expect(probe.parts[0].name, 'Guitar');
      expect(probe.parts[0].noteCount, 2);
      expect(probe.parts[0].lowestMidiPitch, 64);
      expect(probe.parts[0].highestMidiPitch, 67);
      expect(probe.parts[0].isPolyphonic, isTrue);
      expect(probe.parts[0].hasTablature, isFalse);
      expect(probe.parts[1].name, 'Bass');
      expect(probe.parts[1].noteCount, 1);
      expect(probe.parts[1].lowestMidiPitch, 40);
      expect(probe.parts[1].highestMidiPitch, 40);
      expect(probe.parts[1].isPolyphonic, isFalse);
      expect(probe.parts[1].hasTablature, isFalse);
      expect(result.valueOrNull!.parts, probe.parts);
      final noteTracks = result.valueOrNull!.document.tracks
          .whereType<NoteTrack>();
      expect(noteTracks.map((track) => track.name), <String>['Guitar', 'Bass']);
      expect(noteTracks.map((track) => track.events.length), <int>[2, 1]);
    },
  );

  test('warns once when safely ignored notation is unsupported', () async {
    const xml = '''
<score-partwise><part-list><score-part id="P1"><part-name>Guitar</part-name></score-part></part-list><part id="P1"><measure number="1"><attributes><divisions>1</divisions></attributes><direction><direction-type><words>dolce</words></direction-type></direction><note><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration><notations><ornaments><trill-mark/></ornaments></notations></note></measure></part></score-partwise>''';

    final result = await importer.import(
      _source('unsupported.musicxml', xml.codeUnits),
      const SongImportOptions(),
      const NeverCancelledToken(),
    );

    expect(result.valueOrNull!.warnings, <String>[
      MusicXmlImportWarningCode.unsupportedElement,
    ]);
  });

  test('rejects malformed XML and documents containing a doctype', () async {
    final corrupt = await File(
      'test/fixtures/song_trainer/musicxml/corrupt.musicxml',
    ).readAsBytes();
    final xxe =
        '<!DOCTYPE score-partwise [<!ENTITY xxe SYSTEM "file:///etc/passwd">]><score-partwise/>'
            .codeUnits;

    final corruptResult = await importer.import(
      _source('corrupt.musicxml', corrupt),
      const SongImportOptions(),
      const NeverCancelledToken(),
    );
    final xxeResult = await importer.import(
      _source('xxe.musicxml', xxe),
      const SongImportOptions(),
      const NeverCancelledToken(),
    );

    expect(
      corruptResult.failureOrNull?.code,
      MusicXmlImportFailureCode.invalidXml,
    );
    expect(
      xxeResult.failureOrNull?.code,
      MusicXmlImportFailureCode.doctypeForbidden,
    );
  });
}

ImportSourceFile _source(String name, List<int> bytes) => ImportSourceFile(
  displayName: name,
  byteLength: bytes.length,
  openRead: () => Stream<List<int>>.value(bytes),
);
