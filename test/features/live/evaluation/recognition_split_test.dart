import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/domain/evaluation/recognition_metrics.dart';
import 'package:strumsight/features/live/domain/evaluation/recognition_split.dart';

/// Four cases, two distinct values on every group dimension, so the same
/// fixture exercises all four split strategies (ADR 0509 §Döntés D1/D2).
final _cases = <RecognitionCase>[
  const RecognitionCase(
    caseId: 'c1',
    player: 'p1',
    device: 'd1',
    guitar: 'g1',
    room: 'r1',
  ),
  const RecognitionCase(
    caseId: 'c2',
    player: 'p1',
    device: 'd2',
    guitar: 'g1',
    room: 'r2',
  ),
  const RecognitionCase(
    caseId: 'c3',
    player: 'p2',
    device: 'd1',
    guitar: 'g2',
    room: 'r1',
  ),
  const RecognitionCase(
    caseId: 'c4',
    player: 'p2',
    device: 'd2',
    guitar: 'g2',
    room: 'r2',
  ),
];

void main() {
  group('RecognitionSplitBuilder — every strategy folds the full set '
      '(acceptance 1)', () {
    for (final strategy in SplitStrategy.values) {
      test('${strategy.name}: the union of every fold\'s eval set is '
          'exactly the case set, with no element lost or duplicated', () {
        final folds = const RecognitionSplitBuilder().buildFolds(
          _cases,
          strategy,
        );

        expect(folds, isNotEmpty);
        final evalIdsAcrossFolds = <String>[
          for (final fold in folds) ...fold.evalCaseIds,
        ];
        expect(
          evalIdsAcrossFolds.length,
          _cases.length,
          reason: 'each case must be held out in exactly one fold',
        );
        expect(evalIdsAcrossFolds.toSet(), _cases.map((c) => c.caseId).toSet());

        for (final fold in folds) {
          expect(
            fold.trainCaseIds.toSet().intersection(fold.evalCaseIds.toSet()),
            isEmpty,
            reason: 'a fold\'s train and eval sides must be disjoint',
          );
        }
      });
    }
  });

  group('LeakageDetector — fail-closed (acceptance 2, ADR 0509 D1)', () {
    test('the same group value on both sides of a fold throws, naming the '
        'conflicting group key and value', () {
      final groupValueByCaseId = <String, String>{
        'c1': 'p1',
        'c2': 'p1',
        'c3': 'p2',
      };
      // Hand-corrupted fold: c2 shares player p1 with eval-side c1, but was
      // wrongly left in train — this is the scenario RecognitionSplitBuilder
      // can never produce, but LeakageDetector must still catch.
      const corruptFold = RecognitionSplitFold(
        strategy: SplitStrategy.leaveOnePlayerOut,
        heldOutGroupValue: 'p1',
        trainCaseIds: ['c2', 'c3'],
        evalCaseIds: ['c1'],
      );

      expect(
        () => const LeakageDetector().validate(
          groupKey: GroupKey.player,
          groupValueByCaseId: groupValueByCaseId,
          fold: corruptFold,
        ),
        throwsA(
          isA<RecognitionSplitException>()
              .having((e) => e.kind, 'kind', RecognitionSplitErrorKind.leakage)
              .having(
                (e) => e.message,
                'message',
                allOf(contains('player="p1"'), contains('c1')),
              ),
        ),
      );
    });

    test('a correctly built leave-one-out fold never triggers leakage', () {
      // RecognitionSplitBuilder.buildFolds already runs every fold through
      // LeakageDetector.validate — reaching this line without throwing is
      // the “no leakage on a valid split” half of acceptance 2.
      expect(
        () => const RecognitionSplitBuilder().buildFolds(
          _cases,
          SplitStrategy.leaveOnePlayerOut,
        ),
        returnsNormally,
      );
    });
  });

  group('Missing group key — typed failure, never an "unknown" fold '
      '(acceptance 7, ADR 0509 D2)', () {
    test('a case missing the requested group key throws, naming the case', () {
      final cases = <RecognitionCase>[
        const RecognitionCase(caseId: 'c1', player: 'p1'),
        const RecognitionCase(caseId: 'c2'),
      ];

      expect(
        () => const RecognitionSplitBuilder().buildFolds(
          cases,
          SplitStrategy.leaveOnePlayerOut,
        ),
        throwsA(
          isA<RecognitionSplitException>()
              .having(
                (e) => e.kind,
                'kind',
                RecognitionSplitErrorKind.missingGroupKey,
              )
              .having((e) => e.message, 'message', contains('c2')),
        ),
      );
    });

    test('an empty-string group value is also missing, not a valid group', () {
      final cases = <RecognitionCase>[
        const RecognitionCase(caseId: 'c1', room: 'r1'),
        const RecognitionCase(caseId: 'c2', room: '   '),
      ];

      expect(
        () => const RecognitionSplitBuilder().buildFolds(
          cases,
          SplitStrategy.roomHoldout,
        ),
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

  group('RecognitionSplitFold — deterministic ordering (ADR 0509 D6)', () {
    test('fold case ids are sorted, not insertion order', () {
      final reordered = <RecognitionCase>[
        const RecognitionCase(caseId: 'z-case', player: 'p1'),
        const RecognitionCase(caseId: 'a-case', player: 'p1'),
        const RecognitionCase(caseId: 'm-case', player: 'p2'),
      ];
      final folds = const RecognitionSplitBuilder().buildFolds(
        reordered,
        SplitStrategy.leaveOnePlayerOut,
      );
      final p1Fold = folds.firstWhere((f) => f.heldOutGroupValue == 'p1');
      expect(p1Fold.evalCaseIds, ['a-case', 'z-case']);
    });

    test('folds themselves are ordered by group value, not hash order', () {
      final folds = const RecognitionSplitBuilder().buildFolds(
        _cases,
        SplitStrategy.leaveOnePlayerOut,
      );
      expect(folds.map((f) => f.heldOutGroupValue).toList(), ['p1', 'p2']);
    });
  });
}
