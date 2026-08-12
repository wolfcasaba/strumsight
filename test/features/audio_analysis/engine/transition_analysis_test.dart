import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

ChordSegment _chord(String label, int startMs, int endMs) => ChordSegment(
  start: Duration(milliseconds: startMs),
  end: Duration(milliseconds: endMs),
  confidence: 0.9,
  label: label,
);

OnsetEvent _onset(int timeMs, {String id = 'onset'}) => OnsetEvent(
  id: '$id-$timeMs',
  time: Duration(milliseconds: timeMs),
  confidence: 0.8,
);

void main() {
  group('buildChordTransitions', () {
    test('emits one transition per adjacent label change', () {
      final segments = <ChordSegment>[
        _chord('C', 0, 1000),
        _chord('G', 1000, 2000),
        _chord('G', 2000, 2500), // repeated label: no transition
        _chord('Am', 2500, 3500),
      ];
      final transitions = buildChordTransitions(segments);
      expect(transitions.length, 2);
      expect(transitions[0].fromLabel, 'C');
      expect(transitions[0].toLabel, 'G');
      expect(transitions[0].time, const Duration(milliseconds: 1000));
      expect(transitions[1].fromLabel, 'G');
      expect(transitions[1].toLabel, 'Am');
    });

    test('sorts out-of-order segments before building transitions', () {
      final segments = <ChordSegment>[
        _chord('Am', 2000, 3000),
        _chord('C', 0, 2000),
      ];
      final transitions = buildChordTransitions(segments);
      expect(transitions.single.fromLabel, 'C');
      expect(transitions.single.toLabel, 'Am');
    });

    test('empty and single-segment input produce no transitions', () {
      expect(buildChordTransitions(const <ChordSegment>[]), isEmpty);
      expect(
        buildChordTransitions(<ChordSegment>[_chord('C', 0, 1000)]),
        isEmpty,
      );
    });
  });

  group('countTransitionRepetitions / maxTransitionRepetition', () {
    test('groups by chord-pair and counts recurrences', () {
      final transitions = <ChordTransition>[
        ChordTransition(
          time: const Duration(milliseconds: 1000),
          fromLabel: 'C',
          toLabel: 'G',
        ),
        ChordTransition(
          time: const Duration(milliseconds: 2000),
          fromLabel: 'C',
          toLabel: 'G',
        ),
        ChordTransition(
          time: const Duration(milliseconds: 3000),
          fromLabel: 'G',
          toLabel: 'Am',
        ),
      ];
      final counts = countTransitionRepetitions(transitions);
      expect(counts['C>G'], 2);
      expect(counts['G>Am'], 1);
      expect(maxTransitionRepetition(transitions), 2);
    });

    test('empty transitions yield a max repetition of 0', () {
      expect(maxTransitionRepetition(const <ChordTransition>[]), 0);
    });
  });

  group('TransitionWindow boundaries (OD-02, inclusive both ends)', () {
    // The mérce-mátrix requires exact, computed (not eyeballed) boundary
    // values: python3 -c "print(1000 - 150, 1000 - 151, 1000 - 149)".
    final transition = ChordTransition(
      time: const Duration(milliseconds: 1000),
      fromLabel: 'C',
      toLabel: 'G',
    );
    final window = TransitionWindow(transition);

    test('start is exactly -150ms and end is exactly +250ms', () {
      expect(window.start, const Duration(milliseconds: 850));
      expect(window.end, const Duration(milliseconds: 1250));
    });

    test('-150ms (850ms) is included — the boundary is inclusive', () {
      expect(window.contains(const Duration(milliseconds: 850)), isTrue);
    });

    test('-151ms (849ms) is excluded — one microsecond past the boundary', () {
      expect(window.contains(const Duration(milliseconds: 849)), isFalse);
    });

    test('-149ms (851ms) is included — well inside the window', () {
      expect(window.contains(const Duration(milliseconds: 851)), isTrue);
    });

    test('+250ms (1250ms) is included — the boundary is inclusive', () {
      expect(window.contains(const Duration(milliseconds: 1250)), isTrue);
    });

    test('+251ms (1251ms) is excluded — one microsecond past the boundary', () {
      expect(window.contains(const Duration(milliseconds: 1251)), isFalse);
    });

    test('+249ms (1249ms) is included — well inside the window', () {
      expect(window.contains(const Duration(milliseconds: 1249)), isTrue);
    });
  });

  group('onsetsInWindow', () {
    test('keeps only onsets whose time falls within the inclusive window', () {
      final transition = ChordTransition(
        time: const Duration(milliseconds: 1000),
        fromLabel: 'C',
        toLabel: 'G',
      );
      final window = TransitionWindow(transition);
      final onsets = <OnsetEvent>[
        _onset(849), // before window
        _onset(850), // start boundary
        _onset(1000),
        _onset(1250), // end boundary
        _onset(1251), // after window
      ];
      final inWindow = onsetsInWindow(window, onsets);
      expect(inWindow.map((e) => e.time.inMilliseconds), <int>[
        850,
        1000,
        1250,
      ]);
    });
  });
}
