// Audit fixes H1/H7/H8/H11/H12 on the Tuner — parity with the Live screen's
// microphone-permission contract (`live_permission_truthfulness_test.dart`):
//   H7/H8 — an unknown or denied permission is fail-closed, and the idle
//           "Play a string…" prompt does not invite playing into a dead mic.
//   H1    — granting the permission in the system settings lands on the next
//           resume, without an app restart and without a dialog.
//   H12   — reading the permission never shows the system dialog; a denial no
//           dialog can repair is never re-asked.
//   H11   — a mic failure is stated even while the permission reads missing.
//   F1    — an UNRESOLVED read is a THIRD state: while the check is in
//           flight the screen shows neither the banner nor the prompt.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/core/platform/microphone_permission.dart';
import 'package:strumsight/core/widgets/mic_error_banner.dart';
import 'package:strumsight/core/widgets/mic_permission_banner.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/features/tuner/screens/tuner_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

/// A gateway whose `currentState()` stays unanswered until the test says
/// so — the "we do not know yet" first frame every mount goes through.
final class _PendingPermissionGateway implements MicrophonePermissionGateway {
  final Completer<MicrophonePermissionState> _pending =
      Completer<MicrophonePermissionState>();

  int requestCalls = 0;

  @override
  Future<MicrophonePermissionState> currentState() => _pending.future;

  @override
  Future<MicrophonePermissionState> request() async {
    requestCalls++;
    return MicrophonePermissionState.denied;
  }

  void resolve(MicrophonePermissionState state) => _pending.complete(state);
}

Future<void> _pumpTuner(
  WidgetTester tester, {
  required FakeTunerEngine engine,
  required MicrophonePermissionGateway gateway,
  FakeAppLifecycleEvents? lifecycle,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...preferenceOverrides(),
        ...fakeAudioOverrides(permissions: gateway, lifecycle: lifecycle),
        tunerEngineProvider.overrideWithValue(engine),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TunerScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a denied permission hides the "play a string" invitation', (
    tester,
  ) async {
    final engine = FakeTunerEngine();
    addTearDown(engine.dispose);

    await _pumpTuner(
      tester,
      engine: engine,
      gateway: FakeMicrophonePermissionGateway(
        state: MicrophonePermissionState.denied,
      ),
    );

    expect(find.text(l10n.tunerListening), findsNothing);
    expect(find.byType(MicPermissionBanner), findsOneWidget);
  });

  // F1 — `micPermissionProvider` is an AsyncNotifier, so its FIRST frame is
  // `AsyncLoading`. Rendering the settings banner from that frame made every
  // Tuner mount flash "the microphone is off" (and, in a test that pumps
  // once, say it forever) — a claim about the device made before the device
  // had answered. Unknown is still fail-closed for ACTIONS: no invitation.
  testWidgets(
    'while the check is in flight neither the banner nor the prompt is '
    'shown — and once the answer is "denied", the banner appears',
    (tester) async {
      final engine = FakeTunerEngine();
      addTearDown(engine.dispose);
      final gateway = _PendingPermissionGateway();

      await _pumpTuner(tester, engine: engine, gateway: gateway);

      expect(
        find.byType(MicPermissionBanner),
        findsNothing,
        reason: 'an unanswered read is not a measured denial',
      );
      expect(find.text(l10n.tunerListening), findsNothing);

      gateway.resolve(MicrophonePermissionState.permanentlyDenied);
      await tester.pumpAndSettle();

      expect(find.byType(MicPermissionBanner), findsOneWidget);
      expect(find.text(l10n.tunerListening), findsNothing);
    },
  );

  testWidgets(
    'while the check is in flight neither the banner nor the prompt is '
    'shown — and once the answer is "granted", the prompt appears',
    (tester) async {
      final engine = FakeTunerEngine();
      addTearDown(engine.dispose);
      final gateway = _PendingPermissionGateway();

      await _pumpTuner(tester, engine: engine, gateway: gateway);

      expect(find.byType(MicPermissionBanner), findsNothing);
      expect(find.text(l10n.tunerListening), findsNothing);

      gateway.resolve(MicrophonePermissionState.granted);
      await tester.pumpAndSettle();

      expect(find.byType(MicPermissionBanner), findsNothing);
      expect(find.text(l10n.tunerListening), findsOneWidget);
    },
  );

  testWidgets('a granted permission keeps the invitation', (tester) async {
    final engine = FakeTunerEngine();
    addTearDown(engine.dispose);

    await _pumpTuner(
      tester,
      engine: engine,
      gateway: FakeMicrophonePermissionGateway(),
    );

    expect(find.text(l10n.tunerListening), findsOneWidget);
    expect(find.byType(MicPermissionBanner), findsNothing);
  });

  testWidgets(
    'H1 — granting in the settings lands on the next resume, no dialog and '
    'no app restart',
    (tester) async {
      final engine = FakeTunerEngine();
      addTearDown(engine.dispose);
      final lifecycle = FakeAppLifecycleEvents();
      final gateway = FakeMicrophonePermissionGateway(
        state: MicrophonePermissionState.permanentlyDenied,
      );

      await _pumpTuner(
        tester,
        engine: engine,
        gateway: gateway,
        lifecycle: lifecycle,
      );
      expect(find.byType(MicPermissionBanner), findsOneWidget);

      gateway.state = MicrophonePermissionState.granted;
      lifecycle.emit(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.byType(MicPermissionBanner), findsNothing);
      expect(find.text(l10n.tunerListening), findsOneWidget);
      expect(
        gateway.requestCalls,
        0,
        reason: 'a resume re-reads the state, it never pops a dialog',
      );
    },
  );

  testWidgets('H12 — an already-granted permission is never re-asked', (
    tester,
  ) async {
    final engine = FakeTunerEngine();
    addTearDown(engine.dispose);
    final gateway = FakeMicrophonePermissionGateway();

    await _pumpTuner(tester, engine: engine, gateway: gateway);

    expect(gateway.currentStateCalls, greaterThanOrEqualTo(1));
    expect(gateway.requestCalls, 0);
  });

  testWidgets('H11 — a mic failure is stated even without permission', (
    tester,
  ) async {
    final engine = FakeTunerEngine();
    addTearDown(engine.dispose);

    await _pumpTuner(
      tester,
      engine: engine,
      gateway: FakeMicrophonePermissionGateway(
        state: MicrophonePermissionState.permanentlyDenied,
      ),
    );

    engine.emitError(Exception('mic busy'));
    // Zero-duration frames, not pumpAndSettle: riverpod's own error retry
    // would otherwise fire inside the settle loop (see the sibling
    // `tuner_screen_error_test.dart` for the measured reasoning).
    await tester.pump();
    await tester.pump();

    expect(find.byType(MicErrorBanner), findsOneWidget);
    expect(find.byType(MicPermissionBanner), findsOneWidget);
  });
}
