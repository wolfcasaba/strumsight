// Audit fixes H1/H7/H8/H11/H12/H13 — the Live screen's microphone-permission
// contract, driven through the REAL screen with a scripted gateway:
//   H12 — reading the permission is a CHECK. The system dialog is shown at
//         most once per app run, from an explicit screen entry, and NEVER for
//         a denial no dialog can repair.
//   H1  — a permission granted in the system settings takes effect on the
//         next resume, without restarting the app, and without a dialog.
//   H7  — an unresolved/errored read is NOT consent (fail-closed).
//   H13 — "Starting…" never coexists with the permission banner.
//   H8  — the "play a chord" invitation is not offered without a microphone.
//   H11 — an engine/mic failure is stated regardless of the permission read.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/platform/microphone_permission.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/core/widgets/mic_error_banner.dart';
import 'package:strumsight/core/widgets/mic_permission_banner.dart';
import 'package:strumsight/features/live/model/live_frame.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/live/screens/live_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

/// A gateway whose `currentState()` never completes until the test says so —
/// the "we do not know yet" case H7 is about.
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

const _idleFrame = LiveFrame(
  current: null,
  next: null,
  latestStrum: null,
  bar: [],
  bpm: 0,
  inputLevel: 0.4,
  tuningHz: 440,
  listening: true,
  engineTimeSec: 1.0,
);

Future<void> _pumpLive(
  WidgetTester tester, {
  required FakeStrumEngine engine,
  required MicrophonePermissionGateway gateway,
  FakeAppLifecycleEvents? lifecycle,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...preferenceOverrides(),
        ...fakeAudioOverrides(permissions: gateway, lifecycle: lifecycle),
        strumEngineProvider.overrideWithValue(engine),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const LiveScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  group('H12 — the dialog is user intent, never a side effect of a read', () {
    testWidgets('an already-granted permission is never re-asked', (
      tester,
    ) async {
      final engine = FakeStrumEngine();
      addTearDown(engine.dispose);
      final gateway = FakeMicrophonePermissionGateway();

      await _pumpLive(tester, engine: engine, gateway: gateway);

      expect(gateway.currentStateCalls, greaterThanOrEqualTo(1));
      expect(gateway.requestCalls, 0);
      expect(find.byType(MicPermissionBanner), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets(
      'a permanently denied permission is NEVER re-asked — another dialog '
      'cannot repair it, it can only burn a refusal',
      (tester) async {
        final engine = FakeStrumEngine();
        addTearDown(engine.dispose);
        final gateway = FakeMicrophonePermissionGateway(
          state: MicrophonePermissionState.permanentlyDenied,
        );

        await _pumpLive(tester, engine: engine, gateway: gateway);
        engine.emit(_idleFrame);
        await tester.pumpAndSettle();

        expect(gateway.requestCalls, 0);
        expect(find.byType(MicPermissionBanner), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 400));
      },
    );

    testWidgets(
      'a retryable denial is asked exactly once — later rebuilds do not '
      'ask again',
      (tester) async {
        final engine = FakeStrumEngine();
        addTearDown(engine.dispose);
        final gateway = FakeMicrophonePermissionGateway(
          state: MicrophonePermissionState.denied,
        );

        await _pumpLive(tester, engine: engine, gateway: gateway);
        expect(gateway.requestCalls, 1);

        // Several rebuilds: a frame is not consent to ask again.
        engine.emit(_idleFrame);
        await tester.pumpAndSettle();
        engine.emit(_idleFrame);
        await tester.pumpAndSettle();

        expect(gateway.requestCalls, 1);
        await tester.pump(const Duration(milliseconds: 400));
      },
    );
  });

  group('H1 — a permission granted in the settings lands on resume', () {
    testWidgets(
      'resuming re-reads the permission (no dialog) and the banner goes away '
      'without an app restart',
      (tester) async {
        final engine = FakeStrumEngine();
        addTearDown(engine.dispose);
        final lifecycle = FakeAppLifecycleEvents();
        final gateway = FakeMicrophonePermissionGateway(
          state: MicrophonePermissionState.permanentlyDenied,
        );

        await _pumpLive(
          tester,
          engine: engine,
          gateway: gateway,
          lifecycle: lifecycle,
        );
        expect(find.byType(MicPermissionBanner), findsOneWidget);

        // The user taps "Open settings", grants the permission there, and
        // comes back.
        gateway.state = MicrophonePermissionState.granted;
        lifecycle.emit(AppLifecycleState.resumed);
        await tester.pumpAndSettle();

        expect(
          find.byType(MicPermissionBanner),
          findsNothing,
          reason: 'the screen must stop claiming there is no microphone',
        );
        expect(
          gateway.requestCalls,
          0,
          reason: 'a resume re-reads the state, it never pops a dialog',
        );
        await tester.pump(const Duration(milliseconds: 400));
      },
    );
  });

  group('H7/H13/H8 — an unknown permission is not consent', () {
    testWidgets(
      'while the read is still in flight the screen states the missing '
      'permission and offers neither "Starting…" nor "play a chord"',
      (tester) async {
        final engine = FakeStrumEngine();
        addTearDown(engine.dispose);
        final gateway = _PendingPermissionGateway();

        await _pumpLive(tester, engine: engine, gateway: gateway);

        expect(
          find.byType(MicPermissionBanner),
          findsOneWidget,
          reason: 'unknown is fail-closed: not granted',
        );
        expect(find.text(l10n.liveStarting), findsNothing);
        expect(find.text(l10n.liveWaitingForChord), findsNothing);

        // The read finally answers "granted" — now the screen may say it is
        // starting, and may invite the player to strum.
        gateway.resolve(MicrophonePermissionState.granted);
        await tester.pumpAndSettle();

        expect(find.byType(MicPermissionBanner), findsNothing);
        expect(find.text(l10n.liveStarting), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 400));
      },
    );

    testWidgets('a denied permission hides the "play a chord" invitation', (
      tester,
    ) async {
      final engine = FakeStrumEngine();
      addTearDown(engine.dispose);

      await _pumpLive(
        tester,
        engine: engine,
        gateway: FakeMicrophonePermissionGateway(
          state: MicrophonePermissionState.denied,
        ),
      );
      engine.emit(_idleFrame);
      await tester.pumpAndSettle();

      expect(find.text(l10n.liveWaitingForChord), findsNothing);
      expect(find.byType(MicPermissionBanner), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('a granted permission keeps the "play a chord" invitation', (
      tester,
    ) async {
      final engine = FakeStrumEngine();
      addTearDown(engine.dispose);

      await _pumpLive(
        tester,
        engine: engine,
        gateway: FakeMicrophonePermissionGateway(),
      );
      engine.emit(_idleFrame);
      await tester.pumpAndSettle();

      expect(find.text(l10n.liveWaitingForChord), findsWidgets);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('H11 — a mic failure is stated even without permission', () {
    testWidgets('the error banner is not suppressed by the permission read', (
      tester,
    ) async {
      final engine = FakeStrumEngine();
      addTearDown(engine.dispose);

      await _pumpLive(
        tester,
        engine: engine,
        gateway: FakeMicrophonePermissionGateway(
          state: MicrophonePermissionState.permanentlyDenied,
        ),
      );

      engine.emitError(Exception('mic busy'));
      // Zero-duration frames (not pumpAndSettle): riverpod's own error retry
      // would otherwise fire inside the settle loop — same reasoning as
      // `tuner_screen_error_test.dart`.
      await tester.pump();
      await tester.pump();

      expect(find.byType(MicErrorBanner), findsOneWidget);
      expect(find.byType(MicPermissionBanner), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });
}
