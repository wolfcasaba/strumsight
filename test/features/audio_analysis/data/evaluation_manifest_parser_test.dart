import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/data/evaluation/evaluation_manifest_parser.dart';

Map<String, Object?> _validCase({String id = 'case-1'}) => {
  'id': id,
  'tempoBand': 'medium',
  'signalQualityTier': 'clean',
  'mode': 'chord',
  'expected': {
    'events': [
      {'id': 'e1', 'timeMs': 0, 'type': 'onset'},
    ],
    'chordSegments': [
      {'label': 'C', 'startMs': 0, 'endMs': 1000},
    ],
    'tempoBpm': 120.0,
    'beatsMs': [0, 500],
    'pitchPoints': <Object?>[],
  },
  'detected': {
    'events': [
      {'id': 'd1', 'timeMs': 5, 'type': 'onset'},
    ],
    'chordSegments': [
      {'label': 'C', 'startMs': 0, 'endMs': 1000},
    ],
    'tempoBpm': 121.0,
    'beatsMs': [0, 500],
    'pitchPoints': <Object?>[],
  },
  'confidenceObservations': [
    {'rawScore': 0.8, 'correct': true},
  ],
};

Map<String, Object?> _manifest(List<Map<String, Object?>> cases) => {
  'schemaVersion': '1.0',
  'cases': cases,
};

void main() {
  const parser = EvaluationManifestParser();

  group('EvaluationManifestParser — typed-failure matrix', () {
    test('valid manifest parses without throwing', () {
      final manifest = parser.parse(_manifest([_validCase()]));
      expect(manifest.schemaVersion, '1.0');
      expect(manifest.cases, hasLength(1));
      expect(manifest.cases.single.id, 'case-1');
    });

    test('missing annotation is a typed MissingAnnotation failure', () {
      final broken = _validCase()..remove('mode');
      expect(
        () => parser.parse(_manifest([broken])),
        throwsA(
          isA<ManifestParseException>().having(
            (e) => e.kind,
            'kind',
            ManifestParseErrorKind.missingAnnotation,
          ),
        ),
      );
    });

    test(
      'a strum event without a direction is a typed MissingAnnotation failure',
      () {
        final broken = _validCase();
        (broken['expected']! as Map<String, Object?>)['events'] = [
          {'id': 'e1', 'timeMs': 0, 'type': 'strum'},
        ];
        expect(
          () => parser.parse(_manifest([broken])),
          throwsA(
            isA<ManifestParseException>().having(
              (e) => e.kind,
              'kind',
              ManifestParseErrorKind.missingAnnotation,
            ),
          ),
        );
      },
    );

    test('unknown field is a typed UnknownField failure', () {
      final broken = _validCase();
      broken['unexpectedField'] = 'oops';
      expect(
        () => parser.parse(_manifest([broken])),
        throwsA(
          isA<ManifestParseException>().having(
            (e) => e.kind,
            'kind',
            ManifestParseErrorKind.unknownField,
          ),
        ),
      );
    });

    test('invalid time order (annotation end before start) is a typed '
        'InvalidChronology failure', () {
      final broken = _validCase();
      (broken['expected']! as Map<String, Object?>)['chordSegments'] = [
        {'label': 'C', 'startMs': 1000, 'endMs': 500},
      ];
      expect(
        () => parser.parse(_manifest([broken])),
        throwsA(
          isA<ManifestParseException>().having(
            (e) => e.kind,
            'kind',
            ManifestParseErrorKind.invalidChronology,
          ),
        ),
      );
    });

    test('duplicated case id is a typed DuplicateCaseId failure', () {
      expect(
        () => parser.parse(
          _manifest([_validCase(id: 'same'), _validCase(id: 'same')]),
        ),
        throwsA(
          isA<ManifestParseException>().having(
            (e) => e.kind,
            'kind',
            ManifestParseErrorKind.duplicateCaseId,
          ),
        ),
      );
    });

    test(
      'unsupported schema version is a typed InvalidSchemaVersion failure',
      () {
        final manifest = _manifest([_validCase()]);
        manifest['schemaVersion'] = '2.0';
        expect(
          () => parser.parse(manifest),
          throwsA(
            isA<ManifestParseException>().having(
              (e) => e.kind,
              'kind',
              ManifestParseErrorKind.invalidSchemaVersion,
            ),
          ),
        );
      },
    );
  });

  test('parseJsonString rejects malformed JSON without crashing', () {
    expect(
      () => parser.parseJsonString('{ not json'),
      throwsA(isA<ManifestParseException>()),
    );
  });

  test('ci_manifest.json fixture parses cleanly', () async {
    final source = await File(
      'evaluation/analysis/fixtures/ci_manifest.json',
    ).readAsString();
    final manifest = parser.parseJsonString(source);
    expect(manifest.cases.length, greaterThanOrEqualTo(12));
  });
}
