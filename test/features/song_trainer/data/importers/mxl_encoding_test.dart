// Regression: an .mxl whose score.xml is not valid UTF-8 (a plain ISO-8859-1
// export — byte 0xE9 for "e-acute") used to blow a FormatException straight
// out of MusicXmlParserAdapter.parse and therefore out of MxlImporter.import,
// so the registry probe loop aborted instead of moving on with the documented
// invalidXml failure. The plain-XML path already mapped this to invalidXml.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/data/importers/musicxml_importer.dart';
import 'package:strumsight/features/song_trainer/data/importers/musicxml_parser_adapter.dart';
import 'package:strumsight/features/song_trainer/data/importers/mxl_importer.dart';
import 'package:strumsight/features/song_trainer/data/importers/song_importer.dart';

const String _containerXml =
    '<container><rootfiles><rootfile full-path="score.xml"/></rootfiles></container>';

const String _fixturePath =
    'test/fixtures/song_trainer/musicxml/chord_chart_44.musicxml';

/// The committed score with its title spelled the ISO-8859-1 way: 0xE9 is a
/// standalone "e-acute" there, but an illegal continuation byte in UTF-8.
List<int> _latin1ScoreBytes(List<int> utf8Score) {
  const marker = 'Four Four Chart';
  final head = utf8.encode('<work-title>');
  final index = _indexOf(utf8Score, <int>[...head, ...utf8.encode(marker)]);
  expect(index, isNonNegative, reason: 'fixture must carry the work title');
  final titleStart = index + head.length;
  return <int>[
    ...utf8Score.sublist(0, titleStart),
    0xE9, // "é" as a lone ISO-8859-1 byte.
    ...utf8Score.sublist(titleStart + marker.length),
  ];
}

int _indexOf(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var matched = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        matched = false;
        break;
      }
    }
    if (matched) return i;
  }
  return -1;
}

ImportSourceFile _mxlSource(List<int> scoreBytes, String name) {
  final archive = Archive()
    ..addFile(ArchiveFile.string('META-INF/container.xml', _containerXml))
    ..addFile(ArchiveFile.bytes('score.xml', scoreBytes));
  final bytes = ZipEncoder().encode(archive);
  return ImportSourceFile(
    displayName: name,
    byteLength: bytes.length,
    openRead: () => Stream<List<int>>.value(bytes),
  );
}

void main() {
  late List<int> utf8Score;
  late List<int> latin1Score;

  setUpAll(() async {
    utf8Score = await File(_fixturePath).readAsBytes();
    latin1Score = _latin1ScoreBytes(utf8Score);
  });

  test('the parser adapter reports malformed encoding instead of throwing', () {
    expect(const MusicXmlParserAdapter().parse(latin1Score), isNull);
  });

  test('a non-UTF-8 .mxl score imports as invalidXml, never throws', () async {
    final result = await const MxlImporter().import(
      _mxlSource(latin1Score, 'cafe.mxl'),
      const SongImportOptions(),
      const NeverCancelledToken(),
    );

    expect(result.isSuccess, isFalse);
    expect(result.failureOrNull!.code, MusicXmlImportFailureCode.invalidXml);
  });

  test('probing a non-UTF-8 .mxl score fails without throwing', () async {
    final probe = await const MxlImporter().probe(
      _mxlSource(latin1Score, 'cafe.mxl'),
      const NeverCancelledToken(),
    );

    expect(probe.isRecognized, isFalse);
    expect(probe.failureCode, MusicXmlImportFailureCode.invalidXml);
  });

  test('the same container with a UTF-8 score still imports', () async {
    final result = await const MxlImporter().import(
      _mxlSource(utf8Score, 'plain.mxl'),
      const SongImportOptions(),
      const NeverCancelledToken(),
    );

    expect(result, isA<Success<SongImportResult>>());
    expect(result.valueOrNull!.document.metadata.title, 'Four Four Chart');
  });
}
