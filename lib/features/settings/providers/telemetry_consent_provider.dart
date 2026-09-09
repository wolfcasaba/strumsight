import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/config/app_config.dart';
import '../../../core/storage/persisted_preference.dart';
import '../../../core/telemetry/public.dart';
import '../data/telemetry_settings_storage.dart';

/// The clock the consent layer reads, injected so the pseudonym's rotation
/// is testable without waiting seven days. Returns UTC.
final telemetryClockProvider = Provider<DateTime Function()>(
  (_) => () => DateTime.now().toUtc(),
);

/// The RNG the pseudonym is drawn from. `Random.secure()` by default — a
/// participant id derived from a predictable seed would be linkable across
/// devices, which is the one property the pseudonym exists to deny.
final telemetryRandomProvider = Provider<Random>((_) => Random.secure());

/// The user's explicit, revocable beta-telemetry consent (SDD Ch14 Kör 41).
///
/// Default is [TelemetryConsentRecord.initial] — `notAsked`, which the gate
/// treats as a refusal. Nothing here records, queues or buffers an event:
/// the notifier only holds the decision the gate reads.
///
/// Revocation is not "write `denied` and move on": [revoke] also ERASES the
/// pseudonym's three keys from the store, because a retained identifier is
/// exactly what the user just withdrew permission for. And a grant made
/// against a superseded consent copy does not silently carry over — the
/// record's version is compared, so the user is asked again.
class TelemetryConsentNotifier extends Notifier<TelemetryConsentRecord>
    with PersistedPreference<TelemetryConsentRecord> {
  @override
  TelemetryConsentRecord build() {
    final storedState = _readState();
    final version = TelemetryConsentVersion.tryParse(
      preferences.readString(TelemetryStorageKeys.consentVersion),
    );
    if (storedState == null || version == null) {
      return TelemetryConsentRecord.initial;
    }
    final pseudonym = TelemetryPseudonymId.restore(
      highBits: preferences.readInt(TelemetryStorageKeys.pseudonymHighBits),
      lowBits: preferences.readInt(TelemetryStorageKeys.pseudonymLowBits),
      issuedOnDay: preferences.readInt(
        TelemetryStorageKeys.pseudonymIssuedOnDay,
      ),
    );
    if (storedState != TelemetryConsentState.granted || pseudonym == null) {
      // A stored grant without a usable pseudonym is not a grant we can act
      // on. Fail closed rather than mint a replacement id the user never
      // agreed to (that would be a NEW identifier created without a
      // decision).
      return TelemetryConsentRecord(
        state: storedState == TelemetryConsentState.granted
            ? TelemetryConsentState.notAsked
            : storedState,
        version: version,
      );
    }
    return TelemetryConsentRecord(
      state: TelemetryConsentState.granted,
      version: version,
      pseudonym: pseudonym,
    );
  }

  /// Records an explicit grant and mints a fresh pseudonym.
  Future<void> grant() async {
    final id = TelemetryPseudonymId.generate(
      random: ref.read(telemetryRandomProvider),
      nowUtc: ref.read(telemetryClockProvider)(),
    );
    state = TelemetryConsentRecord.granted(id);
    await _persistCurrent();
  }

  /// Records an explicit refusal or revocation, and erases the pseudonym.
  Future<void> revoke() async {
    state = TelemetryConsentRecord.revoked;
    await _persistCurrent();
  }

  /// Rotates the pseudonym when it has outlived
  /// [TelemetryPseudonymId.rotationPeriod]. A no-op while consent is not
  /// granted (there is no id to rotate) and while the id is still fresh.
  Future<void> rotateIfDue() async {
    final current = state.pseudonym;
    if (state.state != TelemetryConsentState.granted || current == null) {
      return;
    }
    final now = ref.read(telemetryClockProvider)();
    if (!current.isExpiredAt(now)) return;
    state = TelemetryConsentRecord.granted(
      TelemetryPseudonymId.generate(
        random: ref.read(telemetryRandomProvider),
        nowUtc: now,
      ),
    );
    await _persistCurrent();
  }

  TelemetryConsentState? _readState() {
    final stored = preferences.readString(TelemetryStorageKeys.consentState);
    if (stored == null) return null;
    for (final value in TelemetryConsentState.values) {
      if (value.name == stored) return value;
    }
    return null;
  }

  Future<void> _persistCurrent() async {
    final record = state;
    final pseudonym = record.pseudonym;
    await persist(TelemetryStorageKeys.consentState, (store) async {
      await store.writeString(
        TelemetryStorageKeys.consentState,
        record.state.name,
      );
      await store.writeString(
        TelemetryStorageKeys.consentVersion,
        record.version.name,
      );
      if (pseudonym == null) {
        for (final key in TelemetryStorageKeys.pseudonymKeys) {
          await store.remove(key);
        }
        return;
      }
      await store.writeInt(
        TelemetryStorageKeys.pseudonymHighBits,
        pseudonym.highBits,
      );
      await store.writeInt(
        TelemetryStorageKeys.pseudonymLowBits,
        pseudonym.lowBits,
      );
      await store.writeInt(
        TelemetryStorageKeys.pseudonymIssuedOnDay,
        pseudonym.issuedOnDay,
      );
    });
  }
}

final telemetryConsentProvider =
    NotifierProvider<TelemetryConsentNotifier, TelemetryConsentRecord>(
      TelemetryConsentNotifier.new,
    );

/// The one predicate any future transport must be built behind.
///
/// It watches the consent notifier, so a mid-session revocation reaches the
/// gate on the very next read — no container rebuild, no restart (the
/// "azonnal hat" requirement the Kör 17 consent cells already pin for the
/// other three egress channels).
final telemetryUploadGateProvider = Provider<TelemetryUploadGate>((ref) {
  final flags = ref.watch(appConfigProvider).flags;
  return TelemetryUploadGate(
    consent: ref.watch(telemetryConsentProvider),
    betaTelemetryEnabled: flags.betaTelemetryEnabled,
    diagnosticsEnabled: flags.diagnosticsEnabled,
  );
});

/// The beta telemetry sink.
///
/// The delegate is [NoopTelemetrySink] and that is not a placeholder to be
/// quietly swapped later: this round ships NO transport (ADR 0484 D5 still
/// forbids `lib/core/telemetry` from mentioning one). What the round does
/// ship is the shape a transport has to arrive in — behind
/// [ConsentGatedTelemetrySink], reading [telemetryUploadGateProvider] fresh
/// on every `record`, so events dropped while consent was off are dropped,
/// never buffered for a later flush.
final betaTelemetrySinkProvider = Provider<TelemetrySink>((ref) {
  return ConsentGatedTelemetrySink(
    delegate: const NoopTelemetrySink(),
    consentGranted: () => ref.read(telemetryUploadGateProvider).allowsUpload,
  );
});

/// Whether this device is enrolled in the Ch14 Kör 40 internal field study.
///
/// Separate from telemetry consent on purpose: agreeing to take part in a
/// study is a different act from agreeing to aggregate reporting, and the
/// study can be left without withdrawing the other. Default OFF.
class FieldStudyEnrolmentNotifier extends Notifier<bool>
    with PersistedPreference<bool> {
  @override
  bool build() =>
      preferences.readBool(TelemetryStorageKeys.fieldStudyEnrolled) ?? false;

  Future<void> setEnrolled(bool enrolled) async {
    state = enrolled;
    await persist(
      TelemetryStorageKeys.fieldStudyEnrolled,
      (store) =>
          store.writeBool(TelemetryStorageKeys.fieldStudyEnrolled, enrolled),
    );
  }
}

final fieldStudyEnrolmentProvider =
    NotifierProvider<FieldStudyEnrolmentNotifier, bool>(
      FieldStudyEnrolmentNotifier.new,
    );

/// The field-session tag a Lab/diagnostics capture may carry, or `null`
/// when any gate is closed (SDD Ch14 Kör 40).
///
/// The tag is resolved here — in the settings layer that owns the opt-in —
/// so a capture site never has to re-derive the three conditions. A caller
/// that gets `null` records an untagged capture; it must not invent one.
FieldSessionTag? resolveFieldSessionTag(
  Ref ref, {
  required FieldStudyTask task,
}) {
  final flags = ref.read(appConfigProvider).flags;
  // Fail-closed AND cheap: with the flag off (every shipped environment)
  // nothing else is read, so a capture site never has to wire the preference
  // store just to be told "there is no tag".
  if (!flags.recognitionFieldSessionTaggingEnabled) return null;
  return FieldSessionTag.resolve(
    fieldSessionTaggingEnabled: true,
    enrolled: ref.read(fieldStudyEnrolmentProvider),
    cohort: FieldStudyCohort.ch14InternalAlpha,
    task: task,
    pseudonym: ref.read(telemetryConsentProvider).pseudonym,
  );
}
