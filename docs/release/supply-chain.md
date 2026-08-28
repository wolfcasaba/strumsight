# Release supply chain — provenance, SBOM, versioning

**Round:** `E12-R06`. **Binding contract:** [ADR 0447](../adr/0447-release-manifest-provenance-and-sbom.md)
(D1–D7). This document explains what the three release tools produce and
why; it does not restate the ADR's decisions.

## What ships, and how it is described

| Artifact | Produced by | Committed / generated |
|---|---|---|
| Release manifest (`release-manifest.json`) | `tool/generate_release_manifest.dart` | generated at build time, not committed |
| SBOM (`sbom.json`) | `tool/release/generate_sbom.py` | generated at build time, not committed |
| Third-party notices | `tool/release/generate_sbom.py` | [`THIRD_PARTY_NOTICES.md`](../../THIRD_PARTY_NOTICES.md), regenerated each round it changes |
| Checksum + monotonicity audit | `tool/release/verify_artifacts.py` | exit code only — no artifact of its own |

## Release manifest

`tool/generate_release_manifest.dart` is a pure function of its declared
inputs (pubspec version/build number, a short git SHA, a channel label,
`assets/ml/model_manifest.json`, `assets/tutor_knowledge/manifest.json`,
and an optional list of build artifacts) — no filesystem timestamp,
environment clock, or random value ever enters the output (ADR 0447 D1).
Two runs against the same inputs produce byte-identical JSON: object keys
are written in ascending sort order at every nesting level by
`canonicalJsonBytes`, and the file carries **no generation timestamp
anywhere** — not in the top-level object, not as a sibling field. The
build's wall-clock time is CI artifact metadata (the GitHub Actions run
timestamp), not manifest content.

Neither the ML model package nor the tutor knowledge package carries a
package-level version field (measured: `assets/ml/model_manifest.json` has
`schema_version` + `models[]`; `assets/tutor_knowledge/manifest.json` has
`schemaVersion` + `documents[]` — neither has a top-level `version`). The
manifest therefore references each by its measured schema version, its
manifest file's own sha256, and its entry count (ADR 0447 D6) — never an
invented "package version".

## SBOM and third-party notices

`pubspec.lock` carries a `license` field for **none** of its 160 locked
packages, and neither `backend/requirements.txt` (11 pins) nor
`backend/requirements-dev.txt` (3 pins) does either. `generate_sbom.py`
resolves every package's license from one of two measured sources, in this
order (ADR 0447 D3):

1. **Hosted Dart package** — the resolved package version's own `LICENSE`
   file in the local pub cache (`--pub-cache`, else `$PUB_CACHE`, else
   `~/.pub-cache`). The SBOM records that file's path, its sha256, and its
   first non-empty line. It does **not** infer an SPDX identifier from that
   free-form text — SPDX-from-text inference is exactly the "unknown"
   guess ADR 0447 D3 forbids.
2. **SDK-bundled / non-hosted Dart package, or a backend Python pin** — the
   hand-curated `_CURATED_LICENSES` registry inside `generate_sbom.py`
   (SPDX identifier + provenance per entry), in the spirit of
   `tool/ci/check_song_fixture_licenses.dart`'s in-file provenance table.
   This covers exactly the five Dart SDK packages `pubspec.lock` names with
   `source: sdk` (`flutter`, `flutter_localizations`, `flutter_test`,
   `flutter_web_plugins`, `sky_engine`) and the backend's Python pins.

A package resolved by **neither** source is a hard failure: the tool exits
non-zero and names the package (measured by
`test/tooling/release_manifest_test.dart` group "A2"). Writing `"unknown"`,
`null`, or an empty license value and continuing is the exact weakening
ADR 0447 D3 forbids — a missing license blocks the SBOM, it does not
degrade silently. Extending the curated registry for a new backend
dependency requires a written SPDX identifier and provenance string in the
same commit that adds the dependency; skipping that step fails the release
build by design, not by accident.

`THIRD_PARTY_NOTICES.md` at the repository root is the generated bundle —
regenerate it with the command in `README`-style tooling docs below rather
than hand-editing it.

## Build number monotonicity

`tool/release/verify_artifacts.py --previous <manifest>` compares the new
manifest's `app.buildNumber` against a prior manifest's. The contract is
strict `>` (ADR 0447 D2): both a decrease and a re-used (equal) build
number are hard failures — a build number is a once-only ticket, not a
label that can be replayed. Without `--previous` the check does not run,
but the tool says so explicitly (`baseline: none`) and still exits zero —
a silent skip would read as "checked and clean" when nothing was checked
at all.

## Checksum audit

The same tool verifies every entry in the manifest's `artifacts` list
against the file on disk (sha256 match, file present) — a stale or
substituted artifact is a hard failure. This runs independently of the
monotonicity check, so it still applies with no `--previous` given.

## Regenerating locally

```bash
dart run tool/generate_release_manifest.dart --output build/release-manifest.json
python3 tool/release/generate_sbom.py --profile production --output-notices THIRD_PARTY_NOTICES.md
python3 tool/release/verify_artifacts.py --manifest build/release-manifest.json
```

## What is NOT wired up yet

The three commands above are not yet invoked by CI — `.github/workflows/**`
is the measure-gate's protected zone (ADR 0321), so this round ships the
proposed workflow steps as a document,
[`docs/release/workflows/release-apk-provenance.proposal.md`](workflows/release-apk-provenance.proposal.md),
rather than editing `release-apk.yml` directly (ADR 0447 D4). Applying that
proposal is a follow-up orchestrator/human step, not part of this round.

The app's version/build/SHA are not yet surfaced anywhere in the UI —
`lib/app/build_info.dart`'s `BuildInfo` class exists but is not referenced
by `main` or any screen (ADR 0447 D7); wiring it into Settings is a later
round.
