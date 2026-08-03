# ADR 0120 — MusicXML/MXL import: parser choice and shared import-policy ownership

**Status:** accepted (E03-R11 pre-flight, 2026-08-03, Terra orchestrator).
Builds on [ADR 0091](0091-song-import-security-boundary.md) and
[ADR 0119](0119-song-import-application-orchestration.md).

## Context

E03-R11 adds the first XML and ZIP based importers to the R10 content-aware
registry.  The pre-flight measured the actual production path rather than the
prepared brief: `songImporterRegistryProvider` in
`lib/features/song_trainer/application/song_trainer_providers.dart` constructs
the only production `ImporterRegistry`, with `NativeJsonImporter()` as its sole
member; `ImporterRegistry` itself does not own that production list.  The
shared, configurable resource policy is `ImportLimits` in
`data/importers/import_limits.dart`; it currently has source, event, workspace
and wall-time budgets, but no archive-entry or extracted-byte budget.

The prepared R11 allowlist contains neither owner.  Implementing a private MXL
limit or leaving the provider on JSON-only would violate ADR 0091's shared,
configurable-policy and actual-registry requirements while appearing to pass
adapter-level tests.

The dependency audit selected direct `xml` and `archive` dependencies, both
MIT-licensed and actively published on pub.dev.  `xml` explicitly does not
apply DTDs; R11 must still reject `DOCTYPE` before parsing and prove this with
an XXE fixture.  `archive` exposes ZIP metadata, including symlink information;
R11 must validate every entry before any workspace write and must not call a
convenience extraction helper.

## Decision

1. `xml` and `archive` are direct data-layer dependencies.  Parser/package
   types remain inside the R11 importer adapters; no type crosses into domain
   or application state.
2. `ImportLimits` owns the configurable MXL archive-entry and extracted-byte
   budgets and their stable failure codes, alongside the existing source,
   event, workspace and wall-time budgets.  The MXL reader consumes these
   values; it must not introduce fixed, private policy constants.
3. The production registry provider appends MusicXML and MXL importers only
   after their probes and security suites are present.  This is the production
   registration required by the R11 SDD; editing `ImporterRegistry` alone is
   insufficient.
4. The current R11 prepared allowlist does not authorize either owner.  Under
   the round-pipeline H3 rule, this round stops before model dispatch.  A
   self-heal/pre-flight correction may add the two exact paths and their
   directly affected tests to a revised, reviewable R11 brief; it must not
   weaken ADR 0091 limits or tests.

## Consequences

- A future resumed R11 can test `max-1`, `max`, and `max+1` against one shared
  policy object and has a real production registration path to test.
- This pre-flight creates no importer code and does not silently broaden the
  currently authorized implementation scope.
