// E12-R09 — event catalog & schema registry compatibility gate.
//
// Every cell below routes through the real `LearningActivityEvent.fromJson`/
// `toJson` entry points (via the gamification public barrel), never a
// test-local stand-in — a predicate that only calls a rewritten helper can
// stay green under a forbidden implementation (docs/LESSONS.md L443).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/public.dart';

const _fixtureDir = 'test/fixtures/events';
const _catalogPath = 'docs/contracts/event-catalog.md';

const _fixturesByType = <String, String>{
  'practice': 'practice_session_completed_v1.json',
  'song': 'song_session_completed_v1.json',
  'analysis': 'analysis_completed_v1.json',
  'plan': 'plan_completed_v1.json',
  'tutor': 'tutor_session_completed_v1.json',
  'vision': 'vision_session_completed_v1.json',
};

const _constructorNameByType = <String, String>{
  'practice': 'PracticeActivityEvent',
  'song': 'SongActivityEvent',
  'analysis': 'AnalysisActivityEvent',
  'plan': 'PlanActivityEvent',
  'tutor': 'TutorActivityEvent',
  'vision': 'VisionActivityEvent',
};

Map<String, Object?> _readFixture(String fileName) {
  final text = File('$_fixtureDir/$fileName').readAsStringSync();
  return (jsonDecode(text) as Map<Object?, Object?>).cast<String, Object?>();
}

bool _deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

void main() {
  group('A1/A2/A7 — round-trip, additive tolerance, canonical fixtures', () {
    for (final typeCode in _fixturesByType.keys) {
      final fileName = _fixturesByType[typeCode]!;

      test('$typeCode fixture is canonical and round-trips', () {
        final original = _readFixture(fileName);

        final decoded = LearningActivityEvent.fromJson(original);
        expect(
          decoded.type,
          typeCode,
          reason: 'fixture $fileName must decode to the $typeCode subtype',
        );

        final reencoded = decoded.toJson();
        expect(
          _deepEquals(reencoded, original),
          isTrue,
          reason:
              'A7: $fileName must be byte-canonical — toJson() must '
              'reproduce it field-for-field. Got $reencoded, expected $original',
        );

        final decodedAgain = LearningActivityEvent.fromJson(reencoded);
        expect(
          _deepEquals(decodedAgain.toJson(), original),
          isTrue,
          reason: 'A1: decode -> encode -> decode must be field-stable',
        );
      });

      test('$typeCode fixture with an unknown extra field still decodes and '
          'keeps every original field unchanged', () {
        final original = _readFixture(fileName);
        final withExtraField = <String, Object?>{
          ...original,
          'futureFieldNotYetInTheContract': 'must be ignored by old readers',
        };

        final decoded = LearningActivityEvent.fromJson(withExtraField);

        expect(
          _deepEquals(decoded.toJson(), original),
          isTrue,
          reason:
              'A2: an additive/unknown field must not change any decoded '
              'field and must not raise',
        );
      });
    }
  });

  group('A3/A4 — controlled failures, never a silent default', () {
    test('missing schemaVersion throws ArgumentError', () {
      final original = _readFixture(_fixturesByType['practice']!);
      final withoutVersion = Map<String, Object?>.from(original)
        ..remove('schemaVersion');

      expect(
        () => LearningActivityEvent.fromJson(withoutVersion),
        throwsArgumentError,
        reason: 'A3: a missing schemaVersion must not default to 1',
      );
    });

    test('unknown type discriminator throws ArgumentError', () {
      final original = _readFixture(_fixturesByType['practice']!);
      final unknownType = <String, Object?>{
        ...original,
        'type': 'not-a-real-type',
      };

      expect(
        () => LearningActivityEvent.fromJson(unknownType),
        throwsArgumentError,
        reason: 'A4: an unrecognised type discriminator must fail closed',
      );
    });
  });

  group('Schema-version threshold — the boundary closes on BOTH sides '
      '(§0.0/(c), V = learningActivityEventSchemaVersion = 1)', () {
    test('schemaVersion at V=1 decodes with every field unchanged', () {
      final original = _readFixture(_fixturesByType['practice']!);
      final atThreshold = <String, Object?>{...original, 'schemaVersion': 1};

      final decoded = LearningActivityEvent.fromJson(atThreshold);

      expect(_deepEquals(decoded.toJson(), original), isTrue);
    });

    test('schemaVersion below V=1 (0) throws ArgumentError — not '
        'best-effort read', () {
      final original = _readFixture(_fixturesByType['practice']!);
      final belowThreshold = <String, Object?>{...original, 'schemaVersion': 0};

      expect(
        () => LearningActivityEvent.fromJson(belowThreshold),
        throwsArgumentError,
      );
    });

    test('schemaVersion above V=1 (2) throws ArgumentError — not '
        'silently accepted', () {
      final original = _readFixture(_fixturesByType['practice']!);
      final aboveThreshold = <String, Object?>{...original, 'schemaVersion': 2};

      expect(
        () => LearningActivityEvent.fromJson(aboveThreshold),
        throwsArgumentError,
      );
    });
  });

  group('A5/A6/A8 — catalog cross-checked against the measured tree', () {
    late String catalogText;
    late List<_CatalogRow> rows;

    setUpAll(() {
      catalogText = File(_catalogPath).readAsStringSync();
      rows = _parseCatalogRows(catalogText);
    });

    test('the catalog has a row for every fixture type and no others', () {
      expect(rows.map((row) => row.type).toSet(), _fixturesByType.keys.toSet());
    });

    test('every row carries a non-empty owner Chapter and idempotency key', () {
      for (final row in rows) {
        expect(row.ownerChapter, isNotEmpty, reason: 'row ${row.type}');
        expect(row.idempotencyKey, isNotEmpty, reason: 'row ${row.type}');
      }
    });

    test('A5: every producer reference is an existing file that constructs '
        'that row\'s event type', () {
      for (final row in rows) {
        for (final producer in row.producers) {
          if (producer.noProducer) continue;
          final file = File(producer.path!);
          expect(
            file.existsSync(),
            isTrue,
            reason: '${row.type} producer ${producer.path} must exist',
          );

          final className = _constructorNameByType[row.type]!;
          expect(
            _containsConstructorCall(file.readAsStringSync(), className),
            isTrue,
            reason:
                '${producer.path} is listed as a producer for ${row.type} '
                'but does not contain a $className(...) constructor call',
          );
        }
      }
    });

    test('every consumer reference is an existing file that references '
        'LearningActivityEvent', () {
      for (final row in rows) {
        for (final consumerPath in row.consumers) {
          final file = File(consumerPath);
          expect(
            file.existsSync(),
            isTrue,
            reason: 'consumer $consumerPath for ${row.type} must exist',
          );
          expect(
            file.readAsStringSync().contains('LearningActivityEvent'),
            isTrue,
            reason:
                'consumer $consumerPath is listed for ${row.type} but does '
                'not reference LearningActivityEvent',
          );
        }
      }
    });

    test('A8: the tutor row claims no producer, and that claim is true on '
        'the measured lib/ tree', () {
      final tutorRow = rows.singleWhere((row) => row.type == 'tutor');
      expect(
        tutorRow.producers.every((producer) => producer.noProducer),
        isTrue,
        reason: 'the tutor row must not list a fabricated producer path',
      );

      final definitionFile =
          'lib/features/gamification/domain/activity/learning_activity_event.dart';
      final unexpectedProducers = <String>[];
      for (final path in _dartFilesUnder('lib')) {
        if (path == definitionFile) continue;
        if (_containsConstructorCall(
          File(path).readAsStringSync(),
          'TutorActivityEvent',
        )) {
          unexpectedProducers.add(path);
        }
      }

      expect(
        unexpectedProducers,
        isEmpty,
        reason:
            'a TutorActivityEvent producer appeared on the tree — the '
            'catalog row must be updated: $unexpectedProducers',
      );
    });
  });
}

Iterable<String> _dartFilesUnder(String root) sync* {
  for (final entity in Directory(root).listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      yield entity.path;
    }
  }
}

/// True only for a real `ClassName(eventId: ..., ...)` invocation — a bare
/// substring match on `'ClassName('` also fires on the Dart 3 object-pattern
/// `case ClassName():` used by achievement_evaluator.dart's exhaustive
/// switch, which takes no arguments and constructs nothing.
bool _containsConstructorCall(String source, String className) {
  final callOpen = RegExp('${RegExp.escape(className)}\\(\\s*');
  for (final match in callOpen.allMatches(source)) {
    if (!source.startsWith(')', match.end)) return true;
  }
  return false;
}

final class _Producer {
  const _Producer.path(this.path) : noProducer = false;
  const _Producer.none() : path = null, noProducer = true;

  final String? path;
  final bool noProducer;
}

final class _CatalogRow {
  const _CatalogRow({
    required this.type,
    required this.producers,
    required this.consumers,
    required this.idempotencyKey,
    required this.ownerChapter,
  });

  final String type;
  final List<_Producer> producers;
  final List<String> consumers;
  final String idempotencyKey;
  final String ownerChapter;
}

List<_CatalogRow> _parseCatalogRows(String markdown) {
  final rows = <_CatalogRow>[];
  for (final line in markdown.split('\n')) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('| `')) continue;

    final cells = trimmed
        .split('|')
        .map((cell) => cell.trim())
        .where((cell) => cell.isNotEmpty)
        .toList();
    if (cells.length < 7) continue;

    rows.add(
      _CatalogRow(
        type: cells[0].replaceAll('`', ''),
        producers: _parseProducerCell(cells[2]),
        consumers: _parseRefCell(cells[3]),
        idempotencyKey: cells[4].replaceAll('`', ''),
        ownerChapter: cells[5],
      ),
    );
  }
  return rows;
}

List<String> _parseRefCell(String cell) {
  return cell
      .split(',')
      .map((part) => part.trim().replaceAll('`', ''))
      .where((part) => part.isNotEmpty)
      .map((part) => part.split(':').first)
      .toList();
}

List<_Producer> _parseProducerCell(String cell) {
  if (cell.toLowerCase().contains('no producer')) {
    return const [_Producer.none()];
  }
  return _parseRefCell(cell).map(_Producer.path).toList();
}
