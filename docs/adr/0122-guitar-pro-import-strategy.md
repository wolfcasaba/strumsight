# ADR 0122 — Guitar Pro import strategy: evidence gate before any production parser

**Status:** accepted for E03-R13 feasibility work (2026-08-03, pre-flight).
Builds on [ADR 0091](0091-song-import-security-boundary.md) and
[ADR 0119](0119-song-import-application-orchestration.md).

## Context

Guitar Pro source formats are proprietary and span the binary GP3/GP4/GP5
family, GP6's GPX archive, and later `.gp` generations. The current production
registry contains only Native JSON, MusicXML/MXL and MIDI importers; no Guitar
Pro parser or registry extension is reachable. `SongSourceType.guitarPro` is a
reserved provenance code, not evidence of support.

R13 must compare a pure-Dart parser, a native adapter, and an explicit
conversion workflow using own or otherwise lawfully usable minimal technical
fixtures. It must record licence, source/date, supported versions, offline and
mobile viability, build-size measurement or blocker, malformed-input behavior,
and fidelity for track, tuning, measure, note, string/fret, tempo and meter.

## Decision

1. This round creates no production parser, registry entry, application
   contract, dependency, platform channel, or UI. The only executable work is
   an isolated Dart tool spike under `tool/guitar_pro_feasibility/`.
2. The R13 research report must make exactly one A/B/C recommendation. A or B
   is permitted only if its candidate's licence, reproducible Android and iOS
   integration path, offline behavior, fail-closed malformed-input behavior,
   and fixture fidelity are all directly evidenced. Missing evidence is a
   rejection, never an inferred pass.
3. Until a later R14 pre-flight accepts a fully evidenced A or B path, C is
   the release-safe user path: do not claim direct Guitar Pro import; accept
   only the already supported, offline MusicXML/MXL or MIDI conversion output.
   The conversion occurs outside the app and must not upload user content.
4. Any future native adapter must add an explicit worker/isolation boundary,
   cancellation and resource-limit proofs required by ADR 0091 before it can
   register with `ImporterRegistry`. Any Dart parser remains data-layer-owned
   and must expose the same observable cancellation and limit boundaries.
5. **R13 selects C — an explicit external conversion workflow — as the only
   release-safe path.** `dart_gp_tab_reader` 0.4.0 remains a licence-clear but
   recent pure-Dart A candidate without release/security-boundary evidence.
   The isolated alphaTab 1.8.4 probe decodes the controlled GP3, GP5 and GPX
   fixtures, but alphaTab and TuxGuitar native-adapter routes have no
   reproducible iOS and worker/isolation evidence. The detailed evidence is in
   [`epic-03-guitar-pro-feasibility.md`](../research/epic-03-guitar-pro-feasibility.md).

## Alternatives

- **A — direct Dart parser:** remains conditional; no package becomes an app
  dependency merely because it can decode a fixture.
- **B — native parser adapter:** remains conditional; a desktop, Android-only,
  or unisolated library is insufficient for the Android-first / later-iOS
  contract.
- **Use `dart_gp_tab_reader` immediately as A:** rejected for this release
  decision because a R14 pre-flight must first evidence its exact-version
  fixture fidelity, maintenance posture, Android+iOS release integration,
  measured size, resource limits, cancellation and malformed corpus behaviour.
- **Write a bespoke binary parser now:** rejected by SDD §17; it would bypass
  the required feasibility, licence and security evidence.

## Consequences

- R14 is activated only by the report's evidenced A/B/C recommendation and
  its explicit activation contract. For the selected C, R14 may provide
  honest conversion guidance to the existing local MusicXML/MXL or MIDI
  import routes but cannot introduce a hidden converter, direct GP registry
  extension or network request. A/B requires the five R14 gates in the
  research report before its own ADR amendment can replace C.
- The feasibility artifacts are deliberately outside `lib/`, so the existing
  offline importer behaviour and registry stay unchanged.
