// E12-R11 — E2E flow 1: fresh install → onboarding → first offline practice
// (ADR 0472). Runs on the REAL `StrumSightApp` tree via `bootE2eApp` — the
// same pattern `test/app/routing/onboarding_first_win_test.dart` and
// `test/app/offline_network_guard_test.dart` already exercise for a full
// app boot, extended with the E12-R11 deterministic profile (fake clock,
// global network guard).
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/e2e_harness.dart';

void main() {
  group('A1/A2 — first offline practice session (real StrumSightApp tree)', () {
    testWidgets(
      'fresh install -> onboarding -> Quick Start -> offline practice -> '
      'history persists, network guard never trips',
      (tester) async {
        final store = InMemoryKeyValueStore();
        final session = await bootE2eApp(
          tester,
          store: store,
          onboardingSeen: false,
        );

        await walkOnboardingViaSkip(tester);
        await runFirstPracticeSession(tester, session);

        final history = await loadPracticeHistory(session.container);
        expect(
          history,
          hasLength(1),
          reason:
              'the finished session must leave exactly one loadable '
              'history record',
        );
        final entry = history.single;
        expect(entry.definitionId, e2eQuickStartDefinitionId);
        expect(entry.finishReasonCode, isNotEmpty);
        expect(
          session.networkGuard.tripped,
          isFalse,
          reason:
              'the entire offline flow must never reach the network '
              'guard (${session.networkGuard.violations})',
        );

        await session.dispose(tester);
        // ADR 0472 D6 / brief §9 — flutter_animate's teardown timer.
        await tester.pump(const Duration(milliseconds: 400));
      },
    );
  });

  group('A4 — determinism: the same flow run twice yields the same result', () {
    testWidgets('two independent fresh-install runs of the flow produce an '
        'identical history snapshot', (tester) async {
      final first = await _runOnceAndSnapshot(tester);
      final second = await _runOnceAndSnapshot(tester);

      expect(
        second,
        equals(first),
        reason:
            'same deterministic inputs (fake clock, fixed catalog '
            'entry) must produce the same persisted result twice',
      );

      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('A3 — fake_network_guard blocks every channel, one cell per path', () {
    test('Dio HttpClientAdapter.fetch is blocked and recorded', () async {
      final guard = FakeNetworkGuard();

      await expectLater(
        () => guard.dioAdapter.fetch(
          RequestOptions(path: 'https://example.invalid/'),
          null,
          null,
        ),
        throwsA(isA<NetworkGuardViolation>()),
      );
      expect(guard.violations.map((v) => v.channel), contains('dio'));
    });

    test('dart:io HttpOverrides.createHttpClient is blocked and recorded', () {
      final guard = FakeNetworkGuard();

      expect(
        () => guard.httpOverrides.createHttpClient(null),
        throwsA(isA<NetworkGuardViolation>()),
      );
      expect(
        guard.violations.map((v) => v.channel),
        contains('http-overrides'),
      );
    });

    testWidgets('an unmocked platform channel is blocked and recorded', (
      tester,
    ) async {
      final guard = FakeNetworkGuard()..install();
      addTearDown(guard.uninstall);

      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const probeChannel = 'e2e-harness/unmocked-probe-channel';

      await expectLater(
        messenger.send(probeChannel, ByteData(0)),
        throwsA(isA<NetworkGuardViolation>()),
      );
      expect(guard.violations.map((v) => v.channel), contains(probeChannel));
    });
  });
}

/// Runs the whole fresh-install flow on a brand-new store/container and
/// returns the [PracticeHistorySnapshot] the A4 cell above compares.
Future<PracticeHistorySnapshot> _runOnceAndSnapshot(WidgetTester tester) async {
  final store = InMemoryKeyValueStore();
  final session = await bootE2eApp(tester, store: store, onboardingSeen: false);

  await walkOnboardingViaSkip(tester);
  await runFirstPracticeSession(tester, session);

  final history = await loadPracticeHistory(session.container);
  final snapshot = snapshotHistoryEntry(history.single);

  await session.dispose(tester);
  return snapshot;
}
