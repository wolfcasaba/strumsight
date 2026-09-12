// The beat may only be delivered in a channel that cannot corrupt what is being
// measured at that instant.
//
// The decision table is tiny, so it is asserted exhaustively: every phase crossed
// with downbeat and muted. The case that carries the most weight is the calibration
// one, because it is the one a widget test would struggle to reach and the one whose
// failure would have the device calibrating against its own metronome.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/curriculum/public.dart';

CurriculumPulse _pulse(
  CurriculumPulsePhase phase, {
  bool downbeat = false,
  bool muted = false,
}) => curriculumPulseFor(phase: phase, isDownbeat: downbeat, muted: muted);

void main() {
  group('the count-in is the one place the click may SOUND', () {
    test('an audible click, accented on beat 1', () {
      expect(
        _pulse(CurriculumPulsePhase.countIn, downbeat: true),
        CurriculumPulse.accentClick,
      );
      expect(_pulse(CurriculumPulsePhase.countIn), CurriculumPulse.click);
    });

    test('it is safe because nothing in the count-in is scored', () {
      // The paired guarantee lives in the grading path: every stroke before bar 1
      // is dropped, so a click heard as a stroke there can be credited to nothing.
      expect(
        RhythmCountIn.countsTowardAttempt(
          atUs: -rhythmToleranceUs - 1,
          toleranceUs: rhythmToleranceUs,
        ),
        isFalse,
      );
    });
  });

  group('the scored attempt is FELT, never heard', () {
    test('a haptic pulse, stronger on beat 1', () {
      expect(
        _pulse(CurriculumPulsePhase.scoredAttempt, downbeat: true),
        CurriculumPulse.accentHaptic,
      );
      expect(
        _pulse(CurriculumPulsePhase.scoredAttempt),
        CurriculumPulse.haptic,
      );
    });

    test('nothing audible can reach a scored bar', () {
      // MEASURED: clicks alone produced 15 reported strums from 16 clicks, at every
      // level down to a gain of 0.1
      // (`test/features/live/metronome_click_pollution_test.dart`). A click lands
      // exactly where the grid expects a stroke, so a learner who played nothing
      // would be credited with a full, perfectly timed attempt.
      for (final downbeat in [false, true]) {
        expect(
          _pulse(
            CurriculumPulsePhase.scoredAttempt,
            downbeat: downbeat,
          ).isAudible,
          isFalse,
        );
      }
    });
  });

  group('a calibration run gets NOTHING', () {
    test('neither channel, downbeat or not', () {
      for (final downbeat in [false, true]) {
        expect(
          _pulse(CurriculumPulsePhase.calibration, downbeat: downbeat),
          CurriculumPulse.none,
          reason:
              'the calibrator registers taps from latestStrumTime, and clicks '
              'produce those — an audible pulse would have the device calibrating '
              'against its own metronome; and any pulse gives the learner '
              'something other than the pendulum to follow, when the pendulum is '
              'what is being calibrated against',
        );
      }
    });
  });

  group('the learner\'s switch silences BOTH channels', () {
    test('muted means nothing, in every phase', () {
      for (final phase in CurriculumPulsePhase.values) {
        for (final downbeat in [false, true]) {
          expect(
            _pulse(phase, downbeat: downbeat, muted: true),
            CurriculumPulse.none,
            reason:
                'someone who turns the metronome off wants no pulse; a second '
                'preference for a channel they cannot compare would be a setting '
                'nobody can answer ($phase)',
          );
        }
      }
    });
  });

  group('the table is total', () {
    test('every phase answers, and only the count-in answers audibly', () {
      final audible = <CurriculumPulsePhase>[];
      for (final phase in CurriculumPulsePhase.values) {
        for (final downbeat in [false, true]) {
          final pulse = _pulse(phase, downbeat: downbeat);
          // No phase is left without an answer by accident: the only `none` is the
          // calibration one, which is a decision.
          if (phase != CurriculumPulsePhase.calibration) {
            expect(pulse, isNot(CurriculumPulse.none), reason: '$phase');
          }
          if (pulse.isAudible && !audible.contains(phase)) audible.add(phase);
        }
      }
      expect(audible, [CurriculumPulsePhase.countIn]);
    });

    test('a pulse is audible or haptic, never both and never neither unless it '
        'is none', () {
      for (final pulse in CurriculumPulse.values) {
        if (pulse == CurriculumPulse.none) {
          expect(pulse.isAudible, isFalse);
          expect(pulse.isHaptic, isFalse);
          continue;
        }
        expect(pulse.isAudible != pulse.isHaptic, isTrue, reason: '$pulse');
      }
    });
  });
}
