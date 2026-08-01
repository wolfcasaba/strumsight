import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/domain/service/practice_session_eligibility.dart';

void main() {
  const predicate = PracticeSessionEligibility();

  group('A6 — PracticeSessionEligibility threshold matrix', () {
    group('activeDuration threshold (20s)', () {
      test('19999 ms → false', () {
        expect(
          predicate.isEligible(
            const PracticeSessionEligibilityInput(
              activeDuration: Duration(milliseconds: 19999),
              resolvedRequiredTargets: 0,
              freePracticeStrums: 0,
            ),
          ),
          isFalse,
        );
      });

      test('20000 ms → true', () {
        expect(
          predicate.isEligible(
            const PracticeSessionEligibilityInput(
              activeDuration: Duration(milliseconds: 20000),
              resolvedRequiredTargets: 0,
              freePracticeStrums: 0,
            ),
          ),
          isTrue,
        );
      });

      test('20001 ms → true', () {
        expect(
          predicate.isEligible(
            const PracticeSessionEligibilityInput(
              activeDuration: Duration(milliseconds: 20001),
              resolvedRequiredTargets: 0,
              freePracticeStrums: 0,
            ),
          ),
          isTrue,
        );
      });
    });

    group('resolvedRequiredTargets threshold (4)', () {
      test('3 targets → false', () {
        expect(
          predicate.isEligible(
            const PracticeSessionEligibilityInput(
              activeDuration: Duration.zero,
              resolvedRequiredTargets: 3,
              freePracticeStrums: 0,
            ),
          ),
          isFalse,
        );
      });

      test('4 targets → true', () {
        expect(
          predicate.isEligible(
            const PracticeSessionEligibilityInput(
              activeDuration: Duration.zero,
              resolvedRequiredTargets: 4,
              freePracticeStrums: 0,
            ),
          ),
          isTrue,
        );
      });

      test('5 targets → true', () {
        expect(
          predicate.isEligible(
            const PracticeSessionEligibilityInput(
              activeDuration: Duration.zero,
              resolvedRequiredTargets: 5,
              freePracticeStrums: 0,
            ),
          ),
          isTrue,
        );
      });
    });

    group('freePracticeStrums threshold (8)', () {
      test('7 strums → false', () {
        expect(
          predicate.isEligible(
            const PracticeSessionEligibilityInput(
              activeDuration: Duration.zero,
              resolvedRequiredTargets: 0,
              freePracticeStrums: 7,
            ),
          ),
          isFalse,
        );
      });

      test('8 strums → true', () {
        expect(
          predicate.isEligible(
            const PracticeSessionEligibilityInput(
              activeDuration: Duration.zero,
              resolvedRequiredTargets: 0,
              freePracticeStrums: 8,
            ),
          ),
          isTrue,
        );
      });

      test('9 strums → true', () {
        expect(
          predicate.isEligible(
            const PracticeSessionEligibilityInput(
              activeDuration: Duration.zero,
              resolvedRequiredTargets: 0,
              freePracticeStrums: 9,
            ),
          ),
          isTrue,
        );
      });
    });

    test('all three below thresholds → false', () {
      expect(
        predicate.isEligible(
          const PracticeSessionEligibilityInput(
            activeDuration: Duration(milliseconds: 19999),
            resolvedRequiredTargets: 3,
            freePracticeStrums: 7,
          ),
        ),
        isFalse,
      );
    });

    test('first-win: short active duration but enough targets → true', () {
      expect(
        predicate.isEligible(
          const PracticeSessionEligibilityInput(
            activeDuration: Duration(milliseconds: 1000),
            resolvedRequiredTargets: 4,
            freePracticeStrums: 0,
          ),
        ),
        isTrue,
      );
    });

    test('at least one threshold met → true', () {
      expect(
        predicate.isEligible(
          const PracticeSessionEligibilityInput(
            activeDuration: Duration(milliseconds: 20000),
            resolvedRequiredTargets: 0,
            freePracticeStrums: 0,
          ),
        ),
        isTrue,
      );
      expect(
        predicate.isEligible(
          const PracticeSessionEligibilityInput(
            activeDuration: Duration.zero,
            resolvedRequiredTargets: 4,
            freePracticeStrums: 0,
          ),
        ),
        isTrue,
      );
      expect(
        predicate.isEligible(
          const PracticeSessionEligibilityInput(
            activeDuration: Duration.zero,
            resolvedRequiredTargets: 0,
            freePracticeStrums: 8,
          ),
        ),
        isTrue,
      );
    });
  });
}
