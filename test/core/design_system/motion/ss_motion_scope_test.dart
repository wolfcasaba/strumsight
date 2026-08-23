import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';

void main() {
  group(
    'SsMotionScope.resolve — A5, the app override wins in both directions',
    () {
      test(
        'appOverride true reduces even when the system does not request it',
        () {
          expect(
            SsMotionScope.resolve(appOverride: true, systemReduced: false),
            isTrue,
          );
        },
      );

      test(
        'appOverride false is NOT reduced even when the system requests it',
        () {
          expect(
            SsMotionScope.resolve(appOverride: false, systemReduced: true),
            isFalse,
          );
        },
      );

      test('appOverride null defers to the system setting', () {
        expect(
          SsMotionScope.resolve(appOverride: null, systemReduced: true),
          isTrue,
        );
        expect(
          SsMotionScope.resolve(appOverride: null, systemReduced: false),
          isFalse,
        );
      });
    },
  );

  group('SsMotionScope.reduceMotionOf — resolved through a widget tree', () {
    Widget harness({
      required bool? appOverride,
      required bool systemDisablesAnimations,
      required ValueChanged<bool> onResolved,
    }) {
      return MediaQuery(
        data: MediaQueryData(disableAnimations: systemDisablesAnimations),
        child: SsMotionScope(
          appOverride: appOverride,
          child: Builder(
            builder: (context) {
              onResolved(SsMotionScope.reduceMotionOf(context));
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    }

    testWidgets('appOverride true overrides system false', (tester) async {
      var resolved = false;
      await tester.pumpWidget(
        harness(
          appOverride: true,
          systemDisablesAnimations: false,
          onResolved: (value) => resolved = value,
        ),
      );
      expect(resolved, isTrue);
    });

    testWidgets('appOverride false overrides system true', (tester) async {
      var resolved = true;
      await tester.pumpWidget(
        harness(
          appOverride: false,
          systemDisablesAnimations: true,
          onResolved: (value) => resolved = value,
        ),
      );
      expect(resolved, isFalse);
    });

    testWidgets('appOverride null defers to the system setting', (
      tester,
    ) async {
      var resolved = false;
      await tester.pumpWidget(
        harness(
          appOverride: null,
          systemDisablesAnimations: true,
          onResolved: (value) => resolved = value,
        ),
      );
      expect(resolved, isTrue);
    });

    testWidgets('durationOf collapses to zero exactly when reduced', (
      tester,
    ) async {
      const base = SsMotion.emphasized;
      Duration? reducedResult;
      Duration? allowedResult;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: SsMotionScope(
            appOverride: true,
            child: Builder(
              builder: (context) {
                reducedResult = SsMotionScope.durationOf(context, base);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: SsMotionScope(
            appOverride: false,
            child: Builder(
              builder: (context) {
                allowedResult = SsMotionScope.durationOf(context, base);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(reducedResult, Duration.zero);
      expect(allowedResult, base);
    });
  });
}
