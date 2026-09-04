import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/live/data/evaluation/recognition_annotation_parser.dart';
import 'package:strumsight/features/live/domain/evaluation/recognition_annotation.dart';

Map<String, Object?> _event({
  String id = 'e1',
  int timeMs = 0,
  String type = 'strum',
  String? direction = 'down',
  String provenance = 'human',
}) => {
  'id': id,
  'timeMs': timeMs,
  'type': type,
  if (direction != null) 'direction': direction,
  'provenance': provenance,
};

Map<String, Object?> _chordSegment({
  String id = 'c1',
  int startMs = 0,
  int endMs = 1000,
  String label = 'C',
  String provenance = 'human',
}) => {
  'id': id,
  'startMs': startMs,
  'endMs': endMs,
  'label': label,
  'provenance': provenance,
};

Map<String, Object?> _annotation({
  String annotatorId = 'annotator-a',
  List<Map<String, Object?>> events = const [],
  List<Map<String, Object?>> chordSegments = const [],
}) => {
  'annotatorId': annotatorId,
  'events': events,
  'chordSegments': chordSegments,
};

Map<String, Object?> _pair({
  Map<String, Object?>? annotatorA,
  Map<String, Object?>? annotatorB,
}) => {
  'schemaVersion': '1.0',
  'annotatorA':
      annotatorA ??
      _annotation(
        annotatorId: 'annotator-a',
        events: [_event(id: 'a1', timeMs: 0)],
      ),
  'annotatorB':
      annotatorB ??
      _annotation(
        annotatorId: 'annotator-b',
        events: [_event(id: 'b1', timeMs: 10)],
      ),
};

void main() {
  const parser = RecognitionAnnotationParser();

  group('RecognitionAnnotationParser — typed-failure matrix', () {
    test('valid pair parses without throwing', () {
      final pair = parser.parse(_pair());
      expect(pair.schemaVersion, '1.0');
      expect(pair.annotatorA.annotatorId, 'annotator-a');
      expect(pair.annotatorB.events.single.id, 'b1');
    });

    test('unsupported schema version is a typed InvalidSchemaVersion '
        'failure (not null, not a silent default)', () {
      final broken = _pair();
      broken['schemaVersion'] = '2.0';
      expect(
        () => parser.parse(broken),
        throwsA(
          isA<RecognitionAnnotationParseException>().having(
            (e) => e.kind,
            'kind',
            RecognitionAnnotationParseErrorKind.invalidSchemaVersion,
          ),
        ),
      );
    });

    test('unknown field is a typed UnknownField failure', () {
      final broken = _pair();
      broken['unexpectedField'] = 'oops';
      expect(
        () => parser.parse(broken),
        throwsA(
          isA<RecognitionAnnotationParseException>().having(
            (e) => e.kind,
            'kind',
            RecognitionAnnotationParseErrorKind.unknownField,
          ),
        ),
      );
    });

    test(
      'missing provenance is a typed failure, never defaulted to "human"',
      () {
        final event = _event(id: 'a1', timeMs: 0)..remove('provenance');
        final broken = _pair(annotatorA: _annotation(events: [event]));
        expect(
          () => parser.parse(broken),
          throwsA(
            isA<RecognitionAnnotationParseException>().having(
              (e) => e.kind,
              'kind',
              RecognitionAnnotationParseErrorKind.missingField,
            ),
          ),
        );
      },
    );

    test('an "auto" provenance value is parsed as auto, never promoted', () {
      final pair = parser.parse(
        _pair(
          annotatorA: _annotation(
            events: [_event(id: 'a1', timeMs: 0, provenance: 'auto')],
          ),
        ),
      );
      expect(
        pair.annotatorA.events.single.provenance,
        AnnotationProvenance.auto,
      );
    });

    test(
      'a strum event without a direction is a typed missing-field failure',
      () {
        final broken = _pair(
          annotatorA: _annotation(
            events: [_event(id: 'a1', timeMs: 0, direction: null)],
          ),
        );
        expect(
          () => parser.parse(broken),
          throwsA(
            isA<RecognitionAnnotationParseException>().having(
              (e) => e.kind,
              'kind',
              RecognitionAnnotationParseErrorKind.missingField,
            ),
          ),
        );
      },
    );

    test('two overlapping events on the same lane are rejected with BOTH '
        'conflicting indices — not silently trimmed, merged, or reordered', () {
      final broken = _pair(
        annotatorA: _annotation(
          events: [
            _event(id: 'a1', timeMs: 500, direction: 'down'),
            _event(id: 'a2', timeMs: 500, direction: 'up'),
          ],
        ),
      );
      expect(
        () => parser.parse(broken),
        throwsA(
          isA<RecognitionAnnotationParseException>()
              .having(
                (e) => e.kind,
                'kind',
                RecognitionAnnotationParseErrorKind.overlappingEvents,
              )
              .having((e) => e.conflictingIndices, 'conflictingIndices', [
                0,
                1,
              ]),
        ),
      );
    });

    test('events of different types at the same timeMs do not overlap', () {
      final pair = parser.parse(
        _pair(
          annotatorA: _annotation(
            events: [
              _event(id: 'a1', timeMs: 500, type: 'onset', direction: null),
              _event(id: 'a2', timeMs: 500, type: 'strum'),
            ],
          ),
        ),
      );
      expect(pair.annotatorA.events, hasLength(2));
    });

    test('two intersecting chord segments are rejected with BOTH conflicting '
        'indices', () {
      final broken = _pair(
        annotatorA: _annotation(
          chordSegments: [
            _chordSegment(id: 'c1', startMs: 0, endMs: 1000),
            _chordSegment(id: 'c2', startMs: 500, endMs: 1500),
          ],
        ),
      );
      expect(
        () => parser.parse(broken),
        throwsA(
          isA<RecognitionAnnotationParseException>()
              .having(
                (e) => e.kind,
                'kind',
                RecognitionAnnotationParseErrorKind.overlappingEvents,
              )
              .having((e) => e.conflictingIndices, 'conflictingIndices', [
                0,
                1,
              ]),
        ),
      );
    });

    test('chord segments that only touch at a boundary do not overlap', () {
      final pair = parser.parse(
        _pair(
          annotatorA: _annotation(
            chordSegments: [
              _chordSegment(id: 'c1', startMs: 0, endMs: 1000),
              _chordSegment(id: 'c2', startMs: 1000, endMs: 2000),
            ],
          ),
        ),
      );
      expect(pair.annotatorA.chordSegments, hasLength(2));
    });
  });

  test('parseJsonString rejects malformed JSON without crashing', () {
    expect(
      () => parser.parseJsonString('{ not json'),
      throwsA(isA<RecognitionAnnotationParseException>()),
    );
  });

  group('AnnotationAgreementCalculator', () {
    test('onset-tolerance boundary is inclusive: 49ms pairs, 50ms pairs, '
        '51ms does not (falsification: swapping <= for < turns this red)', () {
      AgreementReport reportFor(int gapMs) {
        final pair = RecognitionAnnotationPair(
          schemaVersion: '1.0',
          annotatorA: RecognitionAnnotation(
            annotatorId: 'a',
            events: [
              AnnotationEvent(
                id: 'a1',
                timeMs: 1000,
                type: AnnotationEventType.strum,
                provenance: AnnotationProvenance.human,
                direction: StrumDirection.down,
              ),
            ],
          ),
          annotatorB: RecognitionAnnotation(
            annotatorId: 'b',
            events: [
              AnnotationEvent(
                id: 'b1',
                timeMs: 1000 + gapMs,
                type: AnnotationEventType.strum,
                provenance: AnnotationProvenance.human,
                direction: StrumDirection.down,
              ),
            ],
          ),
        );
        return const AnnotationAgreementCalculator(
          toleranceMs: 50,
        ).compute(pair);
      }

      expect(reportFor(49).matchedEventCount, 1);
      expect(reportFor(50).matchedEventCount, 1);
      expect(reportFor(51).matchedEventCount, 0);
    });

    test('matchedEventRatio divides by the larger annotator event count, '
        'not the count of matched pairs', () {
      final pair = RecognitionAnnotationPair(
        schemaVersion: '1.0',
        annotatorA: RecognitionAnnotation(
          annotatorId: 'a',
          events: [
            AnnotationEvent(
              id: 'a1',
              timeMs: 0,
              type: AnnotationEventType.onset,
              provenance: AnnotationProvenance.human,
            ),
            AnnotationEvent(
              id: 'a2',
              timeMs: 1000,
              type: AnnotationEventType.onset,
              provenance: AnnotationProvenance.human,
            ),
          ],
        ),
        annotatorB: RecognitionAnnotation(
          annotatorId: 'b',
          events: [
            AnnotationEvent(
              id: 'b1',
              timeMs: 5,
              type: AnnotationEventType.onset,
              provenance: AnnotationProvenance.human,
            ),
          ],
        ),
      );
      final report = const AnnotationAgreementCalculator().compute(pair);
      expect(report.matchedEventCount, 1);
      expect(report.matchedEventRatio, 0.5);
    });

    test('directionAgreement and chordAgreement are null, not zero, when '
        'there is nothing paired to divide by', () {
      final pair = RecognitionAnnotationPair(
        schemaVersion: '1.0',
        annotatorA: RecognitionAnnotation(annotatorId: 'a'),
        annotatorB: RecognitionAnnotation(annotatorId: 'b'),
      );
      final report = const AnnotationAgreementCalculator().compute(pair);
      expect(report.directionAgreement, isNull);
      expect(report.chordAgreement, isNull);
      expect(report.matchedEventRatio, isNull);
      expect(report.matchedChordRatio, isNull);
    });

    test('the fixture: 10 events each, 8 pairable within 50ms, of which 7 '
        'match direction -> directionAgreement = 0.875 (matched-pairs '
        'denominator, not the raw event count)', () async {
      final source = await File(
        'evaluation/recognition/fixtures/annotation_pair.json',
      ).readAsString();
      final pair = parser.parseJsonString(source);
      final report = const AnnotationAgreementCalculator().compute(pair);

      expect(report.eventCountA, 10);
      expect(report.eventCountB, 10);
      expect(report.matchedEventCount, 8);
      expect(report.matchedEventRatio, closeTo(0.8, 1e-9));
      expect(report.directionAgreement, closeTo(0.875, 1e-9));
    });

    test('the fixture report is byte-identical across two runs (no clock, '
        'no hash-order dependence)', () async {
      final source = await File(
        'evaluation/recognition/fixtures/annotation_pair.json',
      ).readAsString();
      final pair = parser.parseJsonString(source);
      const calculator = AnnotationAgreementCalculator();
      final first = calculator.compute(pair).toDeterministicJson();
      final second = calculator.compute(pair).toDeterministicJson();
      expect(first, second);
    });

    test('toJson uses a fixed, canonical (alphabetical) key order', () {
      final pair = RecognitionAnnotationPair(
        schemaVersion: '1.0',
        annotatorA: RecognitionAnnotation(annotatorId: 'a'),
        annotatorB: RecognitionAnnotation(annotatorId: 'b'),
      );
      final report = const AnnotationAgreementCalculator().compute(pair);
      final keys = report.toJson().keys.toList();
      final sortedKeys = [...keys]..sort();
      expect(keys, sortedKeys);
    });
  });

  test('annotation_schema.json is present and describes a draft-07 object '
      'schema for the annotation pair', () async {
    final source = await File(
      'evaluation/recognition/annotation_schema.json',
    ).readAsString();
    final schema = jsonDecode(source) as Map<String, Object?>;
    expect(schema['type'], 'object');
    expect(schema['required'], contains('schemaVersion'));
    expect(schema['required'], contains('annotatorA'));
    expect(schema['required'], contains('annotatorB'));
  });
}
