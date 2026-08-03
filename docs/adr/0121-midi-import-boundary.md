# ADR 0121 — Standard MIDI importer: audited native subset boundary

**Status:** accepted (E03-R12 pre-flight, 2026-08-03, Terra orchestrator).
Builds on [ADR 0091](0091-song-import-security-boundary.md) and
[ADR 0119](0119-song-import-application-orchestration.md).

## Context

E03-R12 imports untrusted Standard MIDI File (SMF) bytes. The existing
application boundary already owns the source-byte, event and wall-time budgets
through `ImportLimits` and applies them in `ImporterRegistry`. The actual
production importer list is built by `songImporterRegistryProvider`, not by
`ImporterRegistry` itself. A MIDI importer that is only adapter-tested would
therefore be unreachable in the app.

The pre-flight evaluated `dart_midi_pro` 1.0.4+2: it is a pure-Dart,
MIT-licensed parser/writer, but its pub.dev publisher is unverified, the
package has low observed use, and the current package listing reports its last
publication roughly 20 months ago. Its public API does not expose the
event-by-event parsing boundary needed to prove this round's cancellation and
resource-limit requirements. The older `dart_midi` package is Dart 3
incompatible. Adding either would make the security boundary less observable.

`ImportPartPreview` currently cannot carry the required MIDI channel, decoded
duration or suspected-drum value. Those facts have no independent production
owner; they belong to the shared importer preview contract, where they must be
optional for non-MIDI formats.

## Decision

1. R12 implements a small, data-layer-owned binary decoder for exactly SMF
   format 0/1 with PPQ division. It parses header, chunk length, delta-time,
   running status, the listed channel/meta events, and rejects malformed input
   with stable failure codes. No MIDI package is added to `pubspec`.
2. SMPTE division remains explicitly unsupported in this release. Chord
   inference, MIDI playback and editor behavior remain out of scope.
3. MIDI parsing checks cancellation at safe event/chunk boundaries and relies
   on the existing `ImporterRegistry` policy for source bytes, event count and
   wall time. It introduces no parallel or private configurable limit.
4. `ImportPartPreview` gains nullable MIDI-specific channel, duration and
   suspected-drum data. Existing formats keep their former values (`null`) and
   retain their existing equality behavior. The MIDI adapter supplies the
   fields from decoded events and `NoteTrackAnalyzer` supplies monophonic
   analysis.
5. The production provider appends `MidiImporter()` only with its importer,
   malformed-input and provider-wiring tests. Parser data structures do not
   cross into domain or application APIs.

## Alternatives

- **Use `dart_midi_pro`:** rejected for this round. Its MIT licence is
  acceptable, but its maintenance signal and opaque decoding/cancellation
  boundary do not meet the measured, fail-closed security proof required here.
- **Use legacy `dart_midi`:** rejected; the package declares Dart 3
  incompatibility.
- **Treat SMPTE as PPQ or infer chords from pitch classes:** rejected. Both
  would create an unsupported timing interpretation or unproven musical claim.

## Consequences

- The importer has a deliberately narrow, testable SMF subset and an explicit
  upgrade point if a future maintained parser can meet the same observable
  boundary.
- The generic preview contract now represents MIDI facts without falsely
  assigning them to other formats.
- R12 keeps the shared import-policy and production-registration architecture
  intact; no merged ADR or security-policy value changes.
