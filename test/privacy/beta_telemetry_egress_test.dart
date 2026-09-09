// E14-R41 (ADR 0542) — the beta telemetry path makes ZERO network calls,
// on every consent state, measured on the real provider graph rather than
// asserted in prose.
//
// This is the Ch14 Kör 41 acceptance criterion "logged-out/offline → 0
// network requests" restricted to what this round actually ships. It uses
// the existing `FakeNetworkGuard` (E12-R11, ADR 0472 D2), whose
// platform-channel path is a process-wide catch-all: a plugin reaching for
// a channel nobody anticipated still trips it.
//
// It is deliberately an honest, narrow claim. This round ships NO
// transport, so a green result here does not prove a future transport is
// consent-gated — it proves that today's path cannot send, and it will turn
// RED the moment someone wires a sender that bypasses
// `TelemetryUploadGate`.

import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/telemetry/public.dart';
import 'package:strumsight/features/settings/providers/telemetry_consent_provider.dart';

import '../support/fake_network_guard.dart';
import '../support/preference_store.dart';

const _event = TelemetryEvent(
  name: TelemetryEventName.recognitionQualityReported,
  category: TelemetryEventCategory.detection,
  result: TelemetryOperationResult.success,
  durationBucket: TelemetryDurationBucket.ms0To250,
);

AppConfig _labConfig() => AppConfig(
  environment: AppEnvironment.lab,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: const FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: true,
    labModeAvailable: true,
    betaTelemetryEnabled: true,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'debug',
  appVersion: 'test',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNetworkGuard guard;
  late InMemoryKeyValueStore store;
  late ProviderContainer container;

  setUp(() {
    guard = FakeNetworkGuard()..install();
    store = InMemoryKeyValueStore();
    container = ProviderContainer(
      overrides: <Override>[
        preferenceStoreOverride(store),
        appConfigProvider.overrideWithValue(_labConfig()),
        telemetryRandomProvider.overrideWithValue(Random(42)),
        telemetryClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 9, 9),
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    guard.uninstall();
  });

  test('recording through the beta sink sends nothing while consent is at '
      'its default (notAsked)', () {
    final sink = container.read(betaTelemetrySinkProvider);

    for (var i = 0; i < 20; i += 1) {
      sink.record(_event);
    }

    expect(container.read(telemetryUploadGateProvider).allowsUpload, isFalse);
    expect(guard.tripped, isFalse);
    expect(guard.violations, isEmpty);
  });

  test('recording through the beta sink sends nothing even after an '
      'explicit grant — this round ships no transport, and the gate being '
      'open is not the same as a sender existing', () async {
    await container.read(telemetryConsentProvider.notifier).grant();
    final sink = container.read(betaTelemetrySinkProvider);

    for (var i = 0; i < 20; i += 1) {
      sink.record(_event);
    }

    expect(container.read(telemetryUploadGateProvider).allowsUpload, isTrue);
    expect(
      guard.violations,
      isEmpty,
      reason:
          'a green cell here means "cannot send today". When a transport '
          'lands it must be constructed behind TelemetryUploadGate, and '
          'this cell must then be extended with the sender itself.',
    );
  });

  test('revoking mid-session closes the gate on the very next read — no '
      'container rebuild, no restart', () async {
    final notifier = container.read(telemetryConsentProvider.notifier);
    await notifier.grant();
    expect(container.read(telemetryUploadGateProvider).allowsUpload, isTrue);

    await notifier.revoke();

    expect(container.read(telemetryUploadGateProvider).allowsUpload, isFalse);
    expect(
      container.read(telemetryUploadGateProvider).blockReason,
      TelemetryUploadBlockReason.consentRefused,
    );
    expect(guard.violations, isEmpty);
  });

  test('the encoded aggregate carries exactly one identifier, and it is '
      'the rotating pseudonym — never a device or account id', () async {
    await container.read(telemetryConsentProvider.notifier).grant();
    final pseudonym = container.read(telemetryConsentProvider).pseudonym;

    final encoded = RecognitionTelemetryCodec.encode(
      RecognitionTelemetryEnvelope(
        event: const RecognitionTelemetryEvent(
          band: RecognitionTelemetryBand.chordLabel,
          model: RecognitionTelemetryModel.nnlsChroma,
          qualityBucket: RecognitionTelemetryQualityBucket.poor,
          acceptedCount: RecognitionTelemetryCountBucket.c20To99,
          rejectedCount: RecognitionTelemetryCountBucket.c5To19,
          verdictLatencyBucket: TelemetryDurationBucket.ms250To500,
          userCorrected: true,
        ),
        pseudonym: pseudonym!,
      ),
    );

    expect(
      encoded.keys.where((key) => key.toLowerCase().contains('id')),
      <String>['pseudonymId'],
    );
    expect(encoded['pseudonymId'], pseudonym.value);
    expect(guard.violations, isEmpty);
  });
}
