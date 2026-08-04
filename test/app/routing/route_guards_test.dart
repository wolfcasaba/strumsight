import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/route_guards.dart';

void main() {
  group('onboardingRedirect', () {
    test('unseen onboarding redirects every non-welcome path to welcome', () {
      for (final location in <String>[
        ...AppRoutes.shellTabs,
        AppRoutes.tuner,
        AppRoutes.librarySession,
        '/nope',
      ]) {
        expect(
          onboardingRedirect(seen: false, location: location),
          AppRoutes.welcome,
          reason: location,
        );
      }
      expect(
        onboardingRedirect(seen: false, location: AppRoutes.welcome),
        isNull,
      );
    });

    test(
      'seen onboarding redirects welcome to live and allows other paths',
      () {
        expect(
          onboardingRedirect(seen: true, location: AppRoutes.welcome),
          AppRoutes.live,
        );

        for (final location in <String>[
          ...AppRoutes.shellTabs,
          AppRoutes.tuner,
          AppRoutes.librarySession,
          '/nope',
        ]) {
          expect(
            onboardingRedirect(seen: true, location: location),
            isNull,
            reason: location,
          );
        }
      },
    );

    test('every redirect target is stable when evaluated again', () {
      for (final testCase in <({bool seen, String location})>[
        (seen: false, location: AppRoutes.live),
        (seen: false, location: AppRoutes.librarySession),
        (seen: false, location: '/nope'),
        (seen: true, location: AppRoutes.welcome),
      ]) {
        final target = onboardingRedirect(
          seen: testCase.seen,
          location: testCase.location,
        );

        expect(
          target,
          isNotNull,
          reason: '${testCase.seen}:${testCase.location}',
        );
        expect(
          onboardingRedirect(seen: testCase.seen, location: target!),
          isNull,
          reason: '${testCase.seen}:${testCase.location} -> $target',
        );
      }
    });
  });

  group('mayLeaveEditor', () {
    test(
      'requires an explicit discard or successful save for dirty drafts',
      () {
        expect(
          mayLeaveEditor(
            dirty: true,
            decision: UnsavedEditorDecision.stay,
            saveSucceeded: false,
          ),
          isFalse,
        );
        expect(
          mayLeaveEditor(
            dirty: true,
            decision: UnsavedEditorDecision.save,
            saveSucceeded: false,
          ),
          isFalse,
        );
        expect(
          mayLeaveEditor(
            dirty: true,
            decision: UnsavedEditorDecision.discard,
            saveSucceeded: false,
          ),
          isTrue,
        );
      },
    );
  });
}
