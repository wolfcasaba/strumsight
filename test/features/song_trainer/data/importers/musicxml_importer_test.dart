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
    expect(
      result.valueOrNull!.warnings,
      contains(MusicXmlImportWarningCode.repeatExpanded),
    );
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
