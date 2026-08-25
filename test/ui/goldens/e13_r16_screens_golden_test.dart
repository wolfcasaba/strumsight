// Golden snapshots of the E13-R16 launch/recovery/onboarding surfaces, at a
// compact-portrait phone (412×915) and the same frame at textScaler 2.0 —
// the two frames the round brief §7 requires (A9). A REAL gate: unlike
// `test/features/live/chord_timeline_golden_test.dart` (an opt-in local
// visual tool gated on GOLDENS=1), these run — and must pass — on every
// `flutter test` of this file.
//
// Regenerate: ~/flutter/bin/flutter test --update-goldens \
//   test/ui/goldens/e13_r16_screens_golden_test.dart
// (Brand fonts don't load in the test host, so labels render in a fallback
// face — layout, sizing, colours are all faithful; measured, existing
// behaviour of the chord-timeline golden precedent.)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/bootstrap/launch_screen.dart';
import 'package:strumsight/app/bootstrap/recovery_screen.dart';
import 'package:strumsight/core/audio/audio_providers.dart';
import 'package:strumsight/core/design_system/themes/ss_dark_theme.dart';
import 'package:strumsight/core/platform/microphone_permission.dart';
import 'package:strumsight/features/onboarding/first_win_engine.dart';
import 'package:strumsight/features/onboarding/first_win_providers.dart';
import 'package:strumsight/features/onboarding/screens/first_win_stage_screen.dart';
import 'package:strumsight/features/onboarding/screens/onboarding_screen.dart';
import 'package:strumsight/features/onboarding/screens/permission_primer_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_audio.dart';
import '../../support/preference_store.dart';

const _compactPortrait = Size(412, 915);

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  List<Override> overrides = const [],
  double textScale = 1.0,
  // The launch screen's CircularProgressIndicator animates forever, so
  // `pumpAndSettle` (which waits for zero pending frames) never returns for
  // it — a single bounded `pump` is enough for a static golden frame.
  bool settle = true,
}) async {
  tester.view.physicalSize = _compactPortrait;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: SsDarkTheme.data(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _expectGolden(WidgetTester tester, String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('goldens/$name.png'),
);

void main() {
  for (final textScale in [1.0, 2.0]) {
    final suffix = textScale == 1.0 ? 'compact' : 'compact_scale2';

    testWidgets('launch — $suffix', (tester) async {
      await _pump(
        tester,
        const LaunchScreen(),
        textScale: textScale,
        settle: false,
      );
      await _expectGolden(tester, 'e13_r16_launch_$suffix');
    });

    testWidgets('recovery (safe mode) — $suffix', (tester) async {
      await _pump(
        tester,
        const RecoveryScreen(
          problems: ['Local storage is unavailable (storage.unavailable).'],
        ),
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r16_recovery_$suffix');
    });

    testWidgets('onboarding — first carousel page — $suffix', (tester) async {
      await _pump(
        tester,
        const OnboardingScreen(),
        overrides: preferenceOverrides(),
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r16_onboarding_$suffix');
    });

    testWidgets('mic-permission primer — $suffix', (tester) async {
      await _pump(
        tester,
        const PermissionPrimerScreen(),
        overrides: [
          microphonePermissionGatewayProvider.overrideWithValue(
            FakeMicrophonePermissionGateway(
              state: MicrophonePermissionState.denied,
            ),
          ),
        ],
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r16_permission_primer_$suffix');
    });

    testWidgets('first-win mini Stage — $suffix', (tester) async {
      await _pump(
        tester,
        const FirstWinStageScreen(),
        overrides: [
          onboardingFirstWinEngineFactoryProvider.overrideWithValue(
            FakeOnboardingFirstWinEngine.new,
          ),
        ],
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r16_first_win_stage_$suffix');
    });
  }
}
