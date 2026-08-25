import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/audio_providers.dart';
import 'package:strumsight/core/design_system/themes/ss_dark_theme.dart';
import 'package:strumsight/core/platform/microphone_permission.dart';
import 'package:strumsight/features/onboarding/screens/permission_primer_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_audio.dart';

/// E13-R16 (ADR 0281 §1/§5.1) — the mic-permission primer. A1: no request
/// reaches the platform before the user acts on the primer. A2: a final
/// denial shows the settings path, never a re-request.
void main() {
  Future<FakeMicrophonePermissionGateway> pump(
    WidgetTester tester, {
    required MicrophonePermissionState state,
    VoidCallback? onGranted,
    VoidCallback? onSkipped,
    Future<bool> Function()? openSettings,
  }) async {
    final gateway = FakeMicrophonePermissionGateway(state: state);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          microphonePermissionGatewayProvider.overrideWithValue(gateway),
        ],
        child: MaterialApp(
          theme: SsDarkTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PermissionPrimerScreen(
            onGranted: onGranted,
            onSkipped: onSkipped,
            openSettings: openSettings,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return gateway;
  }

  group('A1 — no cold request', () {
    testWidgets(
      'the primer explains why before any system dialog, and never calls '
      'request() on its own',
      (tester) async {
        final gateway = await pump(
          tester,
          state: MicrophonePermissionState.denied,
        );

        expect(
          gateway.requestCalls,
          0,
          reason: 'no request until Allow is tapped',
        );
        expect(
          find.byKey(const ValueKey('onboard-primer-allow')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('onboard-primer-not-now')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'tapping Allow requests exactly once and fires onGranted on success',
      (tester) async {
        var granted = 0;
        final gateway = await pump(
          tester,
          state: MicrophonePermissionState.denied,
          onGranted: () => granted++,
        );

        gateway.state = MicrophonePermissionState.granted;
        await tester.tap(find.byKey(const ValueKey('onboard-primer-allow')));
        await tester.pumpAndSettle();

        expect(gateway.requestCalls, 1);
        expect(granted, 1);
      },
    );

    testWidgets(
      'an already-granted permission skips the ask-UI and fires onGranted',
      (tester) async {
        var granted = 0;
        final gateway = await pump(
          tester,
          state: MicrophonePermissionState.granted,
          onGranted: () => granted++,
        );

        expect(granted, 1);
        expect(gateway.requestCalls, 0, reason: 'nothing left to prime');
        expect(
          find.byKey(const ValueKey('onboard-primer-allow')),
          findsNothing,
        );
      },
    );

    testWidgets('Not now never requests and fires onSkipped', (tester) async {
      var skipped = 0;
      final gateway = await pump(
        tester,
        state: MicrophonePermissionState.denied,
        onSkipped: () => skipped++,
      );

      await tester.tap(find.byKey(const ValueKey('onboard-primer-not-now')));
      await tester.pumpAndSettle();

      expect(gateway.requestCalls, 0);
      expect(skipped, 1);
    });
  });

  group('A2 — final denial shows the settings path, not a re-request', () {
    testWidgets(
      'a permanently denied permission shows Open settings instead of Allow',
      (tester) async {
        await pump(tester, state: MicrophonePermissionState.permanentlyDenied);

        expect(
          find.byKey(const ValueKey('onboard-primer-allow')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('ss-permission-state-openSettings')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'tapping the settings action opens settings, never re-requests',
      (tester) async {
        var openedSettings = 0;
        final gateway = await pump(
          tester,
          state: MicrophonePermissionState.permanentlyDenied,
          openSettings: () async {
            openedSettings++;
            return true;
          },
        );

        await tester.tap(
          find.byKey(const ValueKey('ss-permission-state-openSettings')),
        );
        await tester.pumpAndSettle();

        expect(openedSettings, 1);
        expect(
          gateway.requestCalls,
          0,
          reason: 'settings, never a dead re-request',
        );
      },
    );

    testWidgets('restricted (also non-retryable) shows the settings path too', (
      tester,
    ) async {
      await pump(tester, state: MicrophonePermissionState.restricted);

      expect(
        find.byKey(const ValueKey('ss-permission-state-openSettings')),
        findsOneWidget,
      );
    });
  });
}
