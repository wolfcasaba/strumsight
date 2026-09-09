// E14-R41 (ADR 0542) — the beta-telemetry consent as the user meets it:
// the persisted opt-in notifier, and the Privacy Center card that renders
// it.
//
// Before this round the tree had no telemetry-consent switch at all (the
// sink's own doc comment said so), so every cell here is RED-before by
// construction. What they pin is the behaviour that makes the opt-in real
// rather than decorative:
//
//   * the default is `notAsked` — a device that has never been asked does
//     not collect;
//   * a grant persists, and a revocation ERASES the pseudonym keys instead
//     of leaving a linkable identifier behind;
//   * a build that does not offer beta telemetry renders NO switch, rather
//     than a switch that silently changes nothing;
//   * the card never claims data is being sent — this round ships no
//     transport, and the copy says so.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/core/telemetry/public.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/settings/data/telemetry_settings_storage.dart';
import 'package:strumsight/features/settings/providers/telemetry_consent_provider.dart';
import 'package:strumsight/features/settings/screens/privacy_center_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/preference_store.dart';

AppConfig _config({required bool beta, required bool diagnostics}) => AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: diagnostics,
    labModeAvailable: true,
    betaTelemetryEnabled: beta,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'debug',
  appVersion: 'test',
);

List<Override> _overrides({
  required InMemoryKeyValueStore store,
  bool beta = true,
  bool diagnostics = true,
  DateTime? now,
  int seed = 42,
}) => <Override>[
  preferenceStoreOverride(store),
  appConfigProvider.overrideWithValue(
    _config(beta: beta, diagnostics: diagnostics),
  ),
  telemetryRandomProvider.overrideWithValue(Random(seed)),
  telemetryClockProvider.overrideWithValue(
    () => now ?? DateTime.utc(2026, 9, 9),
  ),
];

void main() {
  group('TelemetryConsentNotifier — persisted, explicit, revocable', () {
    test('an untouched device is `notAsked`, and the gate refuses', () {
      final store = InMemoryKeyValueStore();
      final container = ProviderContainer(overrides: _overrides(store: store));
      addTearDown(container.dispose);

      final consent = container.read(telemetryConsentProvider);

      expect(consent.state, TelemetryConsentState.notAsked);
      expect(consent.pseudonym, isNull);
      expect(container.read(telemetryUploadGateProvider).allowsUpload, isFalse);
    });

    test('granting persists the decision, its copy version and the '
        'pseudonym', () async {
      final store = InMemoryKeyValueStore();
      final container = ProviderContainer(overrides: _overrides(store: store));
      addTearDown(container.dispose);

      await container.read(telemetryConsentProvider.notifier).grant();

      expect(
        store.readString(TelemetryStorageKeys.consentState),
        TelemetryConsentState.granted.name,
      );
      expect(
        store.readString(TelemetryStorageKeys.consentVersion),
        TelemetryConsentVersion.current.name,
      );
      expect(store.readInt(TelemetryStorageKeys.pseudonymHighBits), isNotNull);
      expect(store.readInt(TelemetryStorageKeys.pseudonymLowBits), isNotNull);
      expect(
        store.readInt(TelemetryStorageKeys.pseudonymIssuedOnDay),
        isNotNull,
      );
      expect(container.read(telemetryUploadGateProvider).allowsUpload, isTrue);
    });

    test('a persisted grant is restored on the next launch — the same '
        'pseudonym, not a freshly minted one', () async {
      final store = InMemoryKeyValueStore();
      final first = ProviderContainer(overrides: _overrides(store: store));
      await first.read(telemetryConsentProvider.notifier).grant();
      final granted = first.read(telemetryConsentProvider).pseudonym;
      first.dispose();

      final second = ProviderContainer(
        overrides: _overrides(store: store, seed: 999),
      );
      addTearDown(second.dispose);

      expect(second.read(telemetryConsentProvider).pseudonym, granted);
    });

    test('revoking ERASES the pseudonym keys — a retained identifier is '
        'exactly what the user withdrew permission for', () async {
      final store = InMemoryKeyValueStore();
      final container = ProviderContainer(overrides: _overrides(store: store));
      addTearDown(container.dispose);
      final notifier = container.read(telemetryConsentProvider.notifier);

      await notifier.grant();
      expect(store.readInt(TelemetryStorageKeys.pseudonymHighBits), isNotNull);

      await notifier.revoke();

      expect(
        store.readString(TelemetryStorageKeys.consentState),
        TelemetryConsentState.denied.name,
      );
      for (final key in TelemetryStorageKeys.pseudonymKeys) {
        expect(
          store.readInt(key),
          isNull,
          reason: '$key must be removed, not overwritten with a stale value',
        );
      }
      expect(container.read(telemetryConsentProvider).pseudonym, isNull);
      expect(container.read(telemetryUploadGateProvider).allowsUpload, isFalse);
    });

    test('a stored grant whose pseudonym is missing does NOT mint a '
        'replacement — it falls back to `notAsked` (fail-closed)', () {
      final store = InMemoryKeyValueStore(<String, Object>{
        TelemetryStorageKeys.consentState: TelemetryConsentState.granted.name,
        TelemetryStorageKeys.consentVersion:
            TelemetryConsentVersion.current.name,
      });
      final container = ProviderContainer(overrides: _overrides(store: store));
      addTearDown(container.dispose);

      final consent = container.read(telemetryConsentProvider);

      expect(consent.state, TelemetryConsentState.notAsked);
      expect(consent.pseudonym, isNull);
      expect(container.read(telemetryUploadGateProvider).allowsUpload, isFalse);
    });

    test('the pseudonym rotates once it outlives the rotation period, and '
        'stays put before that', () async {
      final store = InMemoryKeyValueStore();
      var now = DateTime.utc(2026, 9, 1);
      final container = ProviderContainer(
        overrides: <Override>[
          preferenceStoreOverride(store),
          appConfigProvider.overrideWithValue(
            _config(beta: true, diagnostics: true),
          ),
          telemetryRandomProvider.overrideWithValue(Random(1)),
          telemetryClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(telemetryConsentProvider.notifier);

      await notifier.grant();
      final original = container.read(telemetryConsentProvider).pseudonym;

      now = DateTime.utc(2026, 9, 6);
      await notifier.rotateIfDue();
      expect(container.read(telemetryConsentProvider).pseudonym, original);

      now = DateTime.utc(2026, 9, 9);
      await notifier.rotateIfDue();
      expect(
        container.read(telemetryConsentProvider).pseudonym,
        isNot(original),
      );
    });

    test('rotateIfDue is a no-op while consent is not granted — no id is '
        'created for a device that never agreed', () async {
      final store = InMemoryKeyValueStore();
      final container = ProviderContainer(overrides: _overrides(store: store));
      addTearDown(container.dispose);

      await container.read(telemetryConsentProvider.notifier).rotateIfDue();

      expect(container.read(telemetryConsentProvider).pseudonym, isNull);
      expect(store.readInt(TelemetryStorageKeys.pseudonymHighBits), isNull);
    });
  });

  group('FieldStudyEnrolmentNotifier + resolveFieldSessionTag (Kör 40)', () {
    test('with the flag off there is NO tag, even for an enrolled, '
        'consenting participant', () async {
      final store = InMemoryKeyValueStore();
      final container = ProviderContainer(overrides: _overrides(store: store));
      addTearDown(container.dispose);

      await container.read(telemetryConsentProvider.notifier).grant();
      await container
          .read(fieldStudyEnrolmentProvider.notifier)
          .setEnrolled(true);

      final flags = container.read(appConfigProvider).flags;
      expect(container.read(fieldStudyEnrolmentProvider), isTrue);
      expect(flags.recognitionFieldSessionTaggingEnabled, isFalse);
      expect(
        FieldSessionTag.resolve(
          fieldSessionTaggingEnabled:
              flags.recognitionFieldSessionTaggingEnabled,
          enrolled: container.read(fieldStudyEnrolmentProvider),
          cohort: FieldStudyCohort.ch14InternalAlpha,
          task: FieldStudyTask.guidedPattern,
          pseudonym: container.read(telemetryConsentProvider).pseudonym,
        ),
        isNull,
        reason:
            'recognitionFieldSessionTaggingEnabled is off in every '
            'environment on the shipped tree',
      );
    });

    test('with the flag on, the tag needs BOTH enrolment and a pseudonym, '
        'and carries nothing else', () {
      const pseudonym = TelemetryPseudonymId(
        highBits: 1,
        lowBits: 2,
        issuedOnDay: 20000,
      );

      expect(
        FieldSessionTag.resolve(
          fieldSessionTaggingEnabled: true,
          enrolled: false,
          cohort: FieldStudyCohort.ch14InternalAlpha,
          task: FieldStudyTask.noisyRoom,
          pseudonym: pseudonym,
        ),
        isNull,
      );
      expect(
        FieldSessionTag.resolve(
          fieldSessionTaggingEnabled: true,
          enrolled: true,
          cohort: FieldStudyCohort.ch14InternalAlpha,
          task: FieldStudyTask.noisyRoom,
          pseudonym: null,
        ),
        isNull,
      );

      final tag = FieldSessionTag.resolve(
        fieldSessionTaggingEnabled: true,
        enrolled: true,
        cohort: FieldStudyCohort.ch14InternalAlpha,
        task: FieldStudyTask.noisyRoom,
        pseudonym: pseudonym,
      );

      expect(tag, isNotNull);
      expect(tag!.toHeader().keys.toSet(), FieldSessionTag.headerKeys);
      expect(tag.toHeader()['fieldPseudonymId'], pseudonym.value);
    });
  });

  group('Privacy Center — the beta telemetry card', () {
    Future<void> pump(
      WidgetTester tester, {
      required InMemoryKeyValueStore store,
      bool beta = true,
      bool diagnostics = true,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(
            store: store,
            beta: beta,
            diagnostics: diagnostics,
          ),
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const PrivacyCenterScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a build that does not offer beta telemetry renders NO '
        'switch — not a switch that changes nothing', (tester) async {
      await pump(
        tester,
        store: InMemoryKeyValueStore(),
        beta: false,
        diagnostics: false,
      );

      expect(
        find.byKey(const Key('privacyCenterTelemetryCard')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('privacyCenterTelemetrySwitch')),
        findsNothing,
      );
    });

    testWidgets('the diagnostics flag alone also removes the switch — a '
        'production build cannot be talked into offering it', (tester) async {
      await pump(
        tester,
        store: InMemoryKeyValueStore(),
        diagnostics: false,
      );

      expect(
        find.byKey(const Key('privacyCenterTelemetrySwitch')),
        findsNothing,
      );
    });

    testWidgets('the switch starts OFF and turning it on records an '
        'explicit, persisted grant', (tester) async {
      final store = InMemoryKeyValueStore();
      await pump(tester, store: store);

      final switchRow = find.byKey(const Key('privacyCenterTelemetrySwitch'));
      expect(switchRow, findsOneWidget);
      expect(
        tester.widget<SsSwitchRow>(switchRow).value,
        isFalse,
        reason: 'an opt-in that starts on is not an opt-in',
      );

      await tester.tap(switchRow);
      await tester.pumpAndSettle();

      expect(
        store.readString(TelemetryStorageKeys.consentState),
        TelemetryConsentState.granted.name,
      );
      expect(tester.widget<SsSwitchRow>(switchRow).value, isTrue);
    });

    testWidgets('turning it back off revokes and erases the pseudonym', (
      tester,
    ) async {
      final store = InMemoryKeyValueStore();
      await pump(tester, store: store);
      final switchRow = find.byKey(const Key('privacyCenterTelemetrySwitch'));

      await tester.tap(switchRow);
      await tester.pumpAndSettle();
      await tester.tap(switchRow);
      await tester.pumpAndSettle();

      expect(
        store.readString(TelemetryStorageKeys.consentState),
        TelemetryConsentState.denied.name,
      );
      expect(store.readInt(TelemetryStorageKeys.pseudonymHighBits), isNull);
    });

    testWidgets('the card never claims data is being sent: the '
        '"nothing is sent yet" line is present even while consent is ON', (
      tester,
    ) async {
      final store = InMemoryKeyValueStore();
      await pump(tester, store: store);

      await tester.tap(find.byKey(const Key('privacyCenterTelemetrySwitch')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('privacyCenterTelemetryPendingTransport')),
        findsOneWidget,
        reason:
            'this round ships no transport — an "on" state that implies '
            'sending would be a confident claim with no mechanism behind '
            'it (SDD Ch14 §9)',
      );
    });
  });
}
