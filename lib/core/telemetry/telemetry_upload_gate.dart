/// The single predicate that decides whether ANY beta telemetry may leave
/// the device (SDD Ch14 Kör 41, ADR 0542 D6).
///
/// **Measured state of the tree at this round: there is no transport.**
/// `telemetry_sink.dart` still ships `NoopTelemetrySink` and
/// `ConsentGatedTelemetrySink` and nothing else, and nothing under
/// `lib/core/telemetry` may even mention Dio, an `HttpClient`, `dart:io` or
/// `SharedPreferences` (ADR 0484 D5, pinned by
/// `test/core/telemetry/telemetry_redaction_test.dart` A7). This gate is
/// therefore NOT "the thing that sends": it is the thing a future transport
/// must be constructed behind, landed now so the transport cannot be wired
/// without it, and so the three conditions are written down once instead of
/// being re-derived at each call site.
///
/// All three conditions are ANDed and every one of them is fail-closed:
/// unknown, unset or missing means "no".
library;

import 'telemetry_consent.dart';

final class TelemetryUploadGate {
  const TelemetryUploadGate({
    required this.consent,
    required this.betaTelemetryEnabled,
    required this.diagnosticsEnabled,
  });

  /// The fail-closed gate: no consent record, no build flags, no upload.
  static const TelemetryUploadGate closed = TelemetryUploadGate(
    consent: TelemetryConsentRecord.initial,
    betaTelemetryEnabled: false,
    diagnosticsEnabled: false,
  );

  /// The user's own explicit, revocable decision. Defaults to
  /// [TelemetryConsentState.notAsked], which is a refusal.
  final TelemetryConsentRecord consent;

  /// `FeatureFlags.betaTelemetryEnabled` — whether this BUILD offers the
  /// beta telemetry surface at all. Flipping it off is the one-switch beta
  /// rollback.
  final bool betaTelemetryEnabled;

  /// `FeatureFlags.diagnosticsEnabled` — the pre-existing gate on the whole
  /// diagnostics/upload path. Beta telemetry deliberately rides on it
  /// rather than opening a second egress route with its own rules: a
  /// production build resolves it to `false`, so production stays silent
  /// even if a consent record somehow existed.
  final bool diagnosticsEnabled;

  /// Whether a recognition aggregate may be handed to a transport.
  bool get allowsUpload =>
      betaTelemetryEnabled && diagnosticsEnabled && consent.permitsCollection;

  /// Why an upload is refused, for the Privacy Center's honest status line
  /// and for tests. `null` when [allowsUpload] is true.
  TelemetryUploadBlockReason? get blockReason {
    if (!betaTelemetryEnabled) return TelemetryUploadBlockReason.buildDisabled;
    if (!diagnosticsEnabled) {
      return TelemetryUploadBlockReason.diagnosticsDisabled;
    }
    if (consent.needsDecision) return TelemetryUploadBlockReason.consentMissing;
    if (!consent.permitsCollection) {
      return TelemetryUploadBlockReason.consentRefused;
    }
    return null;
  }

  /// A gate identical to this one but reading [record] instead — used when
  /// the consent changes mid-session, so the new decision takes effect on
  /// the very next call rather than at the next container rebuild.
  TelemetryUploadGate withConsent(TelemetryConsentRecord record) =>
      TelemetryUploadGate(
        consent: record,
        betaTelemetryEnabled: betaTelemetryEnabled,
        diagnosticsEnabled: diagnosticsEnabled,
      );
}

/// The closed set of reasons an upload is refused.
enum TelemetryUploadBlockReason {
  /// The build does not offer beta telemetry (`betaTelemetryEnabled` off).
  buildDisabled,

  /// The build's diagnostics path is off (production always is).
  diagnosticsDisabled,

  /// No decision has been recorded yet, or the stored one answers a
  /// superseded version of the consent copy.
  consentMissing,

  /// The user declined or revoked.
  consentRefused,
}
