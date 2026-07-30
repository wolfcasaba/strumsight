import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/domain/model/practice_verdict.dart';

void main() {
  group('PracticeVerdict validation', () {
    test(
      'accepts matched and unmatched consistent verdicts at score bounds',
      () {
        expect(_verdict(eventScore: 0).validate(), isEmpty);
        expect(_verdict(eventScore: 1).validate(), isEmpty);
        expect(
          _verdict(
            matchedObservationSequence: null,
            observedAt: null,
            timingOffset: null,
            timingGrade: TimingGrade.missed,
            directionOutcome: DirectionOutcome.notApplicable,
            chordOutcome: ChordOutcome.notApplicable,
          ).validate(),
          isEmpty,
        );
      },
    );

    test('reports an empty target event ID', () {
      expect(
        _verdict(targetEventId: '').validate().map((failure) => failure.code),
        contains('verdict.targetEventId.empty'),
      );
    });

    test(
      'reports non-finite event score without a duplicate range failure',
      () {
        for (final score in [
          double.nan,
          double.infinity,
          double.negativeInfinity,
        ]) {
          expect(
            _verdict(
              eventScore: score,
            ).validate().map((failure) => failure.code),
            ['verdict.eventScore.notFinite'],
          );
        }
      },
    );

    test('rejects finite event scores outside zero through one', () {
      for (final score in [-0.01, 1.01]) {
        expect(
          _verdict(eventScore: score).validate().map((failure) => failure.code),
          contains('verdict.eventScore.outOfRange'),
        );
      }
    });

    test('rejects unmatched verdicts with observed time or matched grades', () {
      expect(
        _verdict(
          matchedObservationSequence: null,
          observedAt: const Duration(seconds: 1),
          timingOffset: null,
          timingGrade: TimingGrade.missed,
        ).validate().map((failure) => failure.code),
        contains('verdict.match.inconsistent'),
      );
      expect(
        _verdict(
          matchedObservationSequence: null,
          observedAt: null,
          timingOffset: null,
          timingGrade: TimingGrade.perfect,
        ).validate().map((failure) => failure.code),
        contains('verdict.match.inconsistent'),
      );
    });

    test('accepts and pins all five canonical coaching codes', () {
      for (final code in [
        'practice.coach.early',
        'practice.coach.late',
        'practice.coach.wrong_direction',
        'practice.coach.chord_not_stable',
        'practice.coach.no_signal',
      ]) {
        expect(_verdict(coachingCode: code).validate(), isEmpty, reason: code);
      }
    });

    test('rejects an unknown coaching code', () {
      expect(
        _verdict(
          coachingCode: 'practice.coach.unknown',
        ).validate().map((failure) => failure.code),
        contains('verdict.coachingCode.unknown'),
      );
    });
  });

  group('PracticeVerdict value semantics', () {
    test('compares all scalar, enum, and nullable fields', () {
      final verdict = _verdict(coachingCode: PracticeCoachingCode.early);
      final sameValue = _verdict(coachingCode: PracticeCoachingCode.early);
      final different = _verdict(coachingCode: PracticeCoachingCode.late);

      expect(verdict, sameValue);
      expect(verdict.hashCode, sameValue.hashCode);
      expect(verdict, isNot(different));
    });
  });
}

PracticeVerdict _verdict({
  String targetEventId = 'event',
  int? matchedObservationSequence = 0,
  Duration targetAt = const Duration(seconds: 1),
  Duration? observedAt = const Duration(seconds: 1),
  Duration? timingOffset = Duration.zero,
  TimingGrade timingGrade = TimingGrade.perfect,
  StrumDirection? expectedDirection = StrumDirection.down,
  StrumDirection? observedDirection = StrumDirection.down,
  DirectionOutcome directionOutcome = DirectionOutcome.correct,
  String? expectedChord = 'C',
  String? observedChord = 'C',
  ChordOutcome chordOutcome = ChordOutcome.correct,
  double eventScore = 1,
  String? missReasonCode,
  String? coachingCode,
}) => PracticeVerdict(
  targetEventId: targetEventId,
  matchedObservationSequence: matchedObservationSequence,
  targetAt: targetAt,
  observedAt: observedAt,
  timingOffset: timingOffset,
  timingGrade: timingGrade,
  expectedDirection: expectedDirection,
  observedDirection: observedDirection,
  directionOutcome: directionOutcome,
  expectedChord: expectedChord,
  observedChord: observedChord,
  chordOutcome: chordOutcome,
  eventScore: eventScore,
  missReasonCode: missReasonCode,
  coachingCode: coachingCode,
);
