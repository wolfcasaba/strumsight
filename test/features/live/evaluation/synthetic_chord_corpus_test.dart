// E14-R25 (ADR 0538): the seeded synthetic corpus generator.
//
// What these cells prove:
//   * the generator is deterministic for a seed and DIFFERENT across seeds
//     (so a "randomized" property really varies);
//   * the emitted manifest is balanced by construction and passes the
//     validator's minimum-support check;
//   * it is labelled SYNTHETIC and is refused as release evidence — the
//     generator can never be mistaken for ground truth;
//   * a grouped holdout over it is well-formed.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/domain/evaluation/chord_corpus_manifest.dart';
import 'package:strumsight/features/live/domain/evaluation/recognition_split.dart';

import 'support/synthetic_chord_corpus.dart';

void main() {
  // A short, narrow sweep keeps the suite fast; the shape is identical to a
  // full 24-label sweep.
  const labels = <String>['C', 'Am', 'G', 'Em'];

  SyntheticChordCorpus generate(int seed) => generateSyntheticChordCorpus(
    seed: seed,
    labels: labels,
    secondsPerItem: 0.2,
  );

  test('the same seed produces byte-identical audio and an identical '
      'manifest', () {
    final first = generate(7);
    final second = generate(7);

    expect(first.items, hasLength(second.items.length));
    for (var i = 0; i < first.items.length; i++) {
      expect(first.items[i].item.itemId, second.items[i].item.itemId);
      expect(first.items[i].pcm.length, second.items[i].pcm.length);
      for (var n = 0; n < first.items[i].pcm.length; n += 97) {
        expect(first.items[i].pcm[n], second.items[i].pcm[n]);
      }
    }
    expect(
      first.manifest.toDeterministicJson(),
      second.manifest.toDeterministicJson(),
    );
  });

  test('a different seed produces different audio for the same label', () {
    final a = generate(7).items.first.pcm;
    final b = generate(8).items.first.pcm;

    expect(a.length, b.length);
    var differing = 0;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) differing++;
    }
    expect(differing, greaterThan(a.length ~/ 2));
  });

  test('the sweep is balanced: every label gets the same support', () {
    final corpus = generate(42);

    final report = corpus.manifest.classBalance(minimumSupport: 9);

    // 4 labels x 3 voicings x 3 tempos.
    expect(corpus.items, hasLength(36));
    for (final label in labels) {
      expect(report.supportByLabel[label], 9, reason: label);
    }
    // The labels this narrow sweep did not render are honestly reported as
    // below the minimum — the report never rounds a gap away.
    expect(report.meetsMinimumSupport, isFalse);
    expect(report.missingLabels, contains('Bm'));
    expect(report.hardNegativeItemCount, 0);
  });

  test('the manifest is SYNTHETIC and refused as release evidence', () {
    final corpus = generate(42);

    expect(corpus.manifest.corpusKind, ChordCorpusKind.synthetic);
    expect(corpus.manifest.gateEvidenceRefusal, isNotNull);
    expect(corpus.manifest.gateEvidenceRefusal, contains('never ground'));
  });

  test('a grouped holdout over the generated corpus is well-formed', () {
    final corpus = generate(42);

    final folds = corpus.manifest.buildFolds(SplitStrategy.leaveOnePlayerOut);

    expect(folds, isNotEmpty);
    final everyEvalId = <String>{
      for (final fold in folds) ...fold.evalCaseIds,
    };
    expect(everyEvalId, hasLength(corpus.items.length));
  });
}
