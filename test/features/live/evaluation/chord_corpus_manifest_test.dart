// E14-R25 (ADR 0538): the balanced chord-corpus manifest contract.
//
// What these cells prove:
//   * every metadata field SDD Ch14 §7.1 asks for is REQUIRED — a manifest
//     missing `device` or `room` cannot parse at all;
//   * the class-balance report names the classes below the minimum instead
//     of returning a single "unbalanced" boolean;
//   * the grouped split runs through the SHIPPED leakage detector, so a
//     player crossing the train/eval boundary is a typed failure;
//   * a SYNTHETIC corpus is refused as release evidence, by name;
//   * the supported vocabulary mirrors `assets/ml/model_manifest.json` —
//     the two cannot drift apart silently.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/domain/evaluation/chord_corpus_manifest.dart';
import 'package:strumsight/features/live/domain/evaluation/recognition_split.dart';

void main() {
  group('parsing', () {
    test('a complete manifest parses', () {
      final manifest = ChordCorpusManifest.parseJsonString(
        jsonEncode(_manifestJson()),
      );

      expect(manifest.corpusId, 'test-corpus');
      expect(manifest.corpusKind, ChordCorpusKind.realAudio);
      expect(manifest.items, hasLength(3));
      expect(manifest.items.first.voicing, ChordVoicing.open);
      expect(manifest.items.first.pickStyle, ChordPickStyle.pick);
    });

    test('a missing recording-condition field is a typed error naming it', () {
      final json = _manifestJson();
      final items = (json['items']! as List<Object?>)
          .cast<Map<String, Object?>>();
      items.first.remove('device');

      expect(
        () => ChordCorpusManifest.parse(json),
        throwsA(
          isA<ChordCorpusConfigException>()
              .having(
                (e) => e.kind,
                'kind',
                ChordCorpusConfigErrorKind.missingField,
              )
              .having((e) => e.path, 'path', 'corpus.items[0].device'),
        ),
      );
    });

    test('an out-of-vocabulary label is rejected — it belongs in the '
        'open-set corpus, not in a balanced maj/min one', () {
      final json = _manifestJson();
      final items = (json['items']! as List<Object?>)
          .cast<Map<String, Object?>>();
      items.first['label'] = 'Csus4';

      expect(
        () => ChordCorpusManifest.parse(json),
        throwsA(
          isA<ChordCorpusConfigException>().having(
            (e) => e.kind,
            'kind',
            ChordCorpusConfigErrorKind.unknownLabel,
          ),
        ),
      );
    });

    test('a duplicate itemId is rejected', () {
      final json = _manifestJson();
      final items = (json['items']! as List<Object?>)
          .cast<Map<String, Object?>>();
      items[1]['itemId'] = items[0]['itemId'];

      expect(
        () => ChordCorpusManifest.parse(json),
        throwsA(
          isA<ChordCorpusConfigException>().having(
            (e) => e.kind,
            'kind',
            ChordCorpusConfigErrorKind.duplicateItemId,
          ),
        ),
      );
    });

    test('a hard negative must carry the no-chord label', () {
      final json = _manifestJson();
      final items = (json['items']! as List<Object?>)
          .cast<Map<String, Object?>>();
      items.first['hardNegativeCategory'] = 'speech';

      expect(
        () => ChordCorpusManifest.parse(json),
        throwsA(isA<ChordCorpusConfigException>()),
      );
    });
  });

  group('class balance', () {
    test('names every class below the minimum instead of a bare boolean', () {
      final manifest = ChordCorpusManifest.parse(_manifestJson());

      final report = manifest.classBalance(minimumSupport: 2);

      expect(report.totalItemCount, 3);
      expect(report.supportByLabel['C'], 1);
      expect(report.supportByLabel['Am'], 1);
      expect(report.noChordItemCount, 1);
      expect(report.hardNegativeItemCount, 1);
      expect(report.meetsMinimumSupport, isFalse);
      expect(report.labelsBelowMinimum, contains('C'));
      expect(report.labelsBelowMinimum, contains('Bm'));
      expect(report.missingLabels, contains('Bm'));
      expect(report.missingLabels, isNot(contains('C')));
      expect(report.supportByLabel.keys, hasLength(24));
    });

    test('an empty corpus has a null hard-negative share, not zero', () {
      const empty = ChordCorpusManifest(
        schemaVersion: '1',
        corpusId: 'empty',
        corpusKind: ChordCorpusKind.realAudio,
        corpusSha256: 'none',
        items: <ChordCorpusItem>[],
      );

      expect(empty.classBalance(minimumSupport: 1).hardNegativeShare, isNull);
    });
  });

  group('grouped split', () {
    test('a leave-one-player-out fold never lets a player cross the '
        'boundary (the shipped leakage detector runs)', () {
      final manifest = ChordCorpusManifest.parse(_manifestJson());

      final folds = manifest.buildFolds(SplitStrategy.leaveOnePlayerOut);

      expect(folds, hasLength(2));
      for (final fold in folds) {
        expect(fold.evalCaseIds, isNotEmpty);
        expect(
          fold.trainCaseIds.toSet().intersection(fold.evalCaseIds.toSet()),
          isEmpty,
        );
      }
    });

    test('an item with a blank player is a typed split failure, never an '
        '"unknown" bucket', () {
      final json = _manifestJson();
      final items = (json['items']! as List<Object?>)
          .cast<Map<String, Object?>>();
      items.first['player'] = ' ';
      final manifest = ChordCorpusManifest.parse(json);

      expect(
        () => manifest.buildFolds(SplitStrategy.leaveOnePlayerOut),
        throwsA(
          isA<RecognitionSplitException>().having(
            (e) => e.kind,
            'kind',
            RecognitionSplitErrorKind.missingGroupKey,
          ),
        ),
      );
    });
  });

  group('gate admissibility', () {
    test('a real-audio corpus is admissible', () {
      final manifest = ChordCorpusManifest.parse(_manifestJson());

      expect(manifest.gateEvidenceRefusal, isNull);
    });

    test('a SYNTHETIC corpus is refused as release evidence, by name', () {
      final json = _manifestJson()..['corpusKind'] = 'synthetic';
      final manifest = ChordCorpusManifest.parse(json);

      expect(manifest.gateEvidenceRefusal, isNotNull);
      expect(manifest.gateEvidenceRefusal, contains('SYNTHETIC'));
      expect(manifest.gateEvidenceRefusal, contains('test-corpus'));
    });
  });

  test('the supported vocabulary mirrors the shipped chord model manifest '
      'minus its N.C. class — one vocabulary, two files', () {
    final root = _findProjectRoot();
    final source = File(
      '${root.path}/assets/ml/model_manifest.json',
    ).readAsStringSync();
    final manifest = jsonDecode(source) as Map<String, Object?>;
    final models = (manifest['models']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final chord = models.firstWhere(
      (model) => model['filename'] == 'chord_crnn.bin',
    );
    final classes = (chord['output_classes']! as List<Object?>).cast<String>();

    expect(classes.first, 'N.C.');
    expect(classes.sublist(1), chordCorpusMajMin24Labels);
  });
}

Directory _findProjectRoot() {
  var candidate = Directory.current.absolute;
  while (true) {
    final pubspec = File('${candidate.path}/pubspec.yaml');
    final agents = File('${candidate.path}/AGENTS.md');
    if (pubspec.existsSync() && agents.existsSync()) {
      return candidate;
    }
    final parent = candidate.parent;
    if (parent.path == candidate.path) {
      throw StateError('Could not find the StrumSight repository root.');
    }
    candidate = parent;
  }
}

Map<String, Object?> _manifestJson() => <String, Object?>{
  'schemaVersion': '1',
  'corpusId': 'test-corpus',
  'corpusKind': 'realAudio',
  'corpusSha256': 'abc123',
  'items': <Object?>[
    _item(itemId: 'i1', label: 'C', player: 'p1'),
    _item(itemId: 'i2', label: 'Am', player: 'p2'),
    _item(
      itemId: 'i3',
      label: 'noChord',
      player: 'p2',
      hardNegativeCategory: 'speech',
    ),
  ],
};

Map<String, Object?> _item({
  required String itemId,
  required String label,
  required String player,
  String? hardNegativeCategory,
}) => <String, Object?>{
  'itemId': itemId,
  'label': label,
  'voicing': 'open',
  'capo': 0,
  'pickStyle': 'pick',
  'loudness': 'medium',
  'room': 'living-room',
  'distanceCm': 60,
  'guitar': 'dreadnought-1',
  'player': player,
  'device': 'pixel-7',
  'durationMs': 2000,
  'tempoBpm': 90,
  'hardNegativeCategory': hardNegativeCategory,
};
