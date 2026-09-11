// Crediting the held shape to the bar that asked for it, under the honesty rules.
//
// Each cell is a fork where the flattering or the punishing choice was available:
// crediting an unconfirmed guess, condemning a silent bar, or letting a learner who
// never changed chord pass a change rung.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/curriculum/public.dart';

const double _bpm = 60; // one beat a second, so a 4/4 bar is exactly 4 s
const int _beatsPerBar = 4;
const int _barUs = 4000000;

DetectedChord _at(
  int bar,
  String? label, {
  bool confirmed = true,
  int offsetUs = 0,
}) => DetectedChord(
  atUs: bar * _barUs + offsetUs,
  label: label,
  isConfirmed: confirmed,
);

ChordAttempt _grade(
  List<String> cycle,
  List<DetectedChord> detections, {
  int bars = 4,
}) => gradeChords(
  cycle: cycle,
  bars: bars,
  bpm: _bpm,
  beatsPerBar: _beatsPerBar,
  detections: detections,
);

void main() {
  group('a clean single-chord attempt', () {
    test('every bar credited, accuracy 1.0, coverage 1.0', () {
      final attempt = _grade(
        const ['Em'],
        [for (var bar = 0; bar < 4; bar++) _at(bar, 'Em')],
      );
      expect(attempt.askedBars, 4);
      expect(attempt.credited, 4);
      expect(attempt.accuracy, 1.0);
      expect(attempt.coverage, 1.0);
      expect(attempt.isReportable, isTrue);
      expect(attempt.heardInstead, isEmpty);
    });
  });

  group('only confirmed decisions count', () {
    test('an unconfirmed decision credits nothing', () {
      final attempt = _grade(
        const ['Em'],
        [for (var bar = 0; bar < 4; bar++) _at(bar, 'Em', confirmed: false)],
      );
      expect(attempt.heard, 0);
      expect(
        attempt.accuracy,
        isNull,
        reason:
            'a ratio over zero evidence would be a claim about a learner who has '
            'not been measured',
      );
      expect(attempt.isReportable, isFalse);
    });

    test('an unconfirmed WRONG decision condemns nothing either', () {
      // Rule 2: an unconfirmed detection supports no negative claim.
      final attempt = _grade(
        const ['Em'],
        [for (var bar = 0; bar < 4; bar++) _at(bar, 'Am', confirmed: false)],
      );
      expect(attempt.wrongChord, 0);
      expect(attempt.noEvidence, 4);
    });

    test('a confirmed decision with no label credits nothing', () {
      final attempt = _grade(
        const ['Em'],
        [for (var bar = 0; bar < 4; bar++) _at(bar, null)],
      );
      expect(attempt.heard, 0);
    });
  });

  group('a silent bar subtracts nothing', () {
    test('two of four bars heard, both right: accuracy stays 1.0', () {
      final attempt = _grade(const ['Em'], [_at(0, 'Em'), _at(1, 'Em')]);
      expect(attempt.accuracy, 1.0);
      expect(attempt.coverage, 0.5);
      expect(
        attempt.isReportable,
        isTrue,
        reason: 'exactly at the floor, which is inclusive',
      );
    });

    test('one of four heard is below the floor and claims nothing', () {
      final attempt = _grade(const ['Em'], [_at(0, 'Em')]);
      expect(attempt.coverage, 0.25);
      expect(attempt.isReportable, isFalse);
    });
  });

  group('a confirmed WRONG chord is reported, and named', () {
    test('it is reportable evidence, and says what was heard instead', () {
      final attempt = _grade(
        const ['Em'],
        [for (var bar = 0; bar < 4; bar++) _at(bar, 'Am')],
      );
      expect(attempt.wrongChord, 4);
      expect(attempt.heard, 4);
      expect(attempt.accuracy, 0.0);
      expect(
        attempt.heardInstead,
        ['Am', 'Am', 'Am', 'Am'],
        reason:
            'naming the shape actually heard is the actionable half; "wrong '
            'chord" on its own tells the learner nothing to change',
      );
    });

    test('the FIRST other chord is named, not the last', () {
      // A later one may be the learner correcting themselves; what they were
      // holding when the bar began is the more useful thing to say back.
      final attempt = _grade(
        const ['Em'],
        [
          _at(0, 'Am'),
          _at(0, 'C', offsetUs: 1000000),
          _at(1, 'Em'),
          _at(2, 'Em'),
          _at(3, 'Em'),
        ],
      );
      expect(attempt.heardInstead, ['Am']);
    });

    test('a match anywhere in the bar wins over an earlier mismatch', () {
      // The decoder carries its own lag, so the first confirmation in a bar can
      // still be the previous shape. A learner who DID change must not be marked
      // wrong for the decoder being late.
      final attempt = _grade(
        const ['Em', 'Am'],
        [
          _at(1, 'Em'), // stale, bar 1 asks Am
          _at(1, 'Am', offsetUs: 900000),
        ],
      );
      expect(attempt.bars[1].outcome, ChordBarOutcome.credited);
      expect(attempt.bars[1].heardInstead, isNull);
    });
  });

  group('a change rung measures the CHANGE', () {
    test('a learner who never changed cannot pass it', () {
      // Em held for all four bars of an Em/Am cycle: bars 0 and 2 credited, bars
      // 1 and 3 heard as the wrong chord.
      final attempt = _grade(
        const ['Em', 'Am'],
        [for (var bar = 0; bar < 4; bar++) _at(bar, 'Em')],
      );
      expect(attempt.credited, 2);
      expect(attempt.wrongChord, 2);
      expect(attempt.accuracy, 0.5);
      expect(attempt.heardInstead, [
        'Em',
        'Em',
      ], reason: 'the bars that asked for Am heard Em');
    });

    test('a learner who did change passes it', () {
      final attempt = _grade(
        const ['Em', 'Am'],
        [_at(0, 'Em'), _at(1, 'Am'), _at(2, 'Em'), _at(3, 'Am')],
      );
      expect(attempt.accuracy, 1.0);
    });

    test('the bar window is NOT widened by a tolerance', () {
      // This is the whole reason a chord window is the bar itself: a confirmation
      // from bar 0 is evidence about bar 0's chord. Were the window widened, the
      // learner above who never changed would have Em credited to an Am bar.
      final attempt = _grade(
        const ['Em', 'Am'],
        [_at(0, 'Em', offsetUs: _barUs - 1)],
        bars: 2,
      );
      expect(attempt.bars[0].outcome, ChordBarOutcome.credited);
      expect(attempt.bars[1].outcome, ChordBarOutcome.noEvidence);
    });
  });

  group('degenerate inputs are refused rather than guessed', () {
    test('an empty cycle grades nothing', () {
      expect(_grade(const [], [_at(0, 'Em')]).askedBars, 0);
      expect(_grade(const [], []).coverage, 0);
    });

    test('zero bars grades nothing', () {
      expect(_grade(const ['Em'], [_at(0, 'Em')], bars: 0).askedBars, 0);
    });
  });

  group('the coverage policy is the rhythm pillar\'s, not a second number', () {
    test('the two floors are the same value by construction', () {
      expect(minimumChordCoverage, minimumRhythmCoverage);
    });
  });
}
