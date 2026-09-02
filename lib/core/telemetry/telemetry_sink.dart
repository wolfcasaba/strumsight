import 'telemetry_event.dart';

/// A destination a `TelemetryEvent` can be recorded to.
///
/// This round ships the contract only — no implementation in this file ever
/// reaches the network OR writes to local persistence (`dart:io`,
/// `SharedPreferences`, `path_provider`, ...) (ADR 0484 D5, SDD Ch12 §5.5).
/// The D5 prohibition covers both: a sink that buffers to disk before
/// consent is checked would defeat [ConsentGatedTelemetrySink] just as
/// completely as one that reaches the network directly, since a disk
/// buffer is itself a durable, inspectable copy of the event. Wiring a
/// real transport (and the consent switch it reads) is a later,
/// feature-flagged round.
abstract interface class TelemetrySink {
  void record(TelemetryEvent event);
}

/// A sink that never records anything, under any consent state. The
/// contract's own default — used wherever no other sink is wired.
final class NoopTelemetrySink implements TelemetrySink {
  const NoopTelemetrySink();

  @override
  void record(TelemetryEvent event) {}
}

/// Gates every recording behind an injected consent read (ADR 0484 D4,
/// SDD Ch12 §0.0 R3).
///
/// [consentGranted] is read fresh on every call — it is a constructor-
/// injected function, never a provider, `SharedPreferences` read or
/// settings-repository lookup, because no telemetry-consent switch exists on
/// the tree today (measuring one would create a second, unverified consent
/// source; wiring the real one is a later round's job).
///
/// While [consentGranted] returns `false`, [record] is a pure no-op: the
/// event is not stored, queued or buffered anywhere. A later flip to `true`
/// only takes effect for events recorded AFTER the flip — there is no
/// retroactive flush of what was dropped while consent was withheld, because
/// that would be collection before consent with the sending merely delayed.
final class ConsentGatedTelemetrySink implements TelemetrySink {
  const ConsentGatedTelemetrySink({
    required this.delegate,
    required this.consentGranted,
  });

  final TelemetrySink delegate;
  final bool Function() consentGranted;

  @override
  void record(TelemetryEvent event) {
    if (!consentGranted()) return;
    delegate.record(event);
  }
}
