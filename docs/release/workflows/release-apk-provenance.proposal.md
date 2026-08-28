# Proposal: release manifest, SBOM & provenance steps for `release-apk.yml`

- **Status:** proposal only — NOT applied. `.github/workflows/**` is the
  measure-gate's protected zone (ADR 0321 `PROTECTED_GLOBS`), and the
  standing gate-edit authorization file (ADR 0372) does not exist on this
  tree, so an implementer session cannot edit it directly (E12-R06 §0.0).
  Applying this fragment to `.github/workflows/release-apk.yml` and
  dispatching the workflow is an orchestrator/human step that happens
  **after** this round merges (ADR 0447 D4, ADR 0112 §3).
- **Round:** `E12-R06` — `docs/adr/0447-release-manifest-provenance-and-sbom.md`
  is the binding contract (D1–D7).
- **Gate:** the YAML fragment below is machine-checked by
  `test/tooling/release_manifest_test.dart` (group "A5") with a
  restricted-subset parser living in that test file — no `package:yaml`
  import and no shell-out to `rg`/`grep`/`jq`/`gh` (ADR 0447 D5, L110).

## Insertion point

Insert the six steps below into the `release-apk` job of
`.github/workflows/release-apk.yml`, **immediately AFTER** the step named
`Read APK metadata from pubspec` (currently lines 78–96) and **BEFORE** the
step named `Materialize production keystore`. Both step names are measured
against the real workflow file by the gate test.

## What these steps do

1. **Generate release manifest** — runs
   `dart run tool/generate_release_manifest.dart`, producing the
   deterministic, timestamp-free JSON manifest (ADR 0447 D1) that
   references the app version/build/SHA/channel plus the ML model manifest
   and tutor knowledge manifest (ADR 0447 D6).
2. **Generate SBOM and third-party notices** — runs
   `python3 tool/release/generate_sbom.py`, which resolves every Dart and
   backend Python dependency's license from the pub cache or the curated
   registry and fails the build (non-zero exit) if any package's license
   cannot be resolved (ADR 0447 D3) — a missing license blocks the release,
   it does not degrade to `"unknown"`.
3. **Verify release artifacts** — runs
   `python3 tool/release/verify_artifacts.py`, checksum-auditing the staged
   artifacts and (once a previous manifest is available to diff against)
   enforcing the strictly-monotonic build number (ADR 0447 D2).
4. **Upload release manifest** / **Upload SBOM** / **Upload third-party
   notices** — three `actions/upload-artifact@v4` steps, one per generated
   file, `if-no-files-found: error` so a silently-skipped generator step
   fails the workflow rather than uploading nothing.

## Proposed YAML fragment

```yaml
steps:
  - name: Generate release manifest
    run: |
      set -euo pipefail
      mkdir -p dist
      dart run tool/generate_release_manifest.dart \
        --output dist/release-manifest.json \
        --git-sha "${GITHUB_SHA:0:7}" \
        --channel production
  - name: Generate SBOM and third-party notices
    run: |
      set -euo pipefail
      python3 tool/release/generate_sbom.py \
        --profile production \
        --output-sbom dist/sbom.json \
        --output-notices THIRD_PARTY_NOTICES.md
  - name: Verify release artifacts
    run: |
      set -euo pipefail
      python3 tool/release/verify_artifacts.py \
        --manifest dist/release-manifest.json
  - name: Upload release manifest
    uses: actions/upload-artifact@v4
    with:
      name: release-manifest
      path: dist/release-manifest.json
      if-no-files-found: error
  - name: Upload SBOM
    uses: actions/upload-artifact@v4
    with:
      name: sbom
      path: dist/sbom.json
      if-no-files-found: error
  - name: Upload third-party notices
    uses: actions/upload-artifact@v4
    with:
      name: third-party-notices
      path: THIRD_PARTY_NOTICES.md
      if-no-files-found: error
```

## Why there is no `--previous` in the fragment above

`verify_artifacts.py --previous <manifest>` needs the immediately preceding
release's manifest as a diff baseline (ADR 0447 D2). This workflow is
`workflow_dispatch`-only and does not currently persist manifests between
runs, so wiring a real baseline (e.g. downloading the previous run's
`release-manifest` artifact via the GitHub API before this step) is a
follow-up, not part of this proposal — without `--previous`, the tool
itself prints `baseline: none` and exits `0` rather than silently skipping
the check (ADR 0447 D2, measured by A3).

## Why the verify step audits zero artifacts here

At the proposed insertion point (immediately after `Read APK metadata from
pubspec`, before `Materialize production keystore`), the production APK does
not exist yet — it is produced later by `Build production APK` (currently
line 113) and renamed by `Stage versioned production APK` (currently line
123). The `Verify release artifacts` step above therefore runs
`verify_artifacts.py --manifest dist/release-manifest.json` with no
`--artifact` entries in the manifest to check, so `artifacts: 0 verified`
and exit `0` is the correct, honest output at this insertion point — not a
bug. As a checksum guard for the APK specifically, the step is a no-op here:
the insertion point is forced this early because it must run before
`Materialize production keystore` writes signing secrets to disk (ADR 0447
D4 keeps generation out of the keystore-materialized window), while the APK
itself only exists after that window closes.

**Follow-up (not part of this proposal):** move or duplicate the `Verify
release artifacts` step to run AFTER `Stage versioned production APK`, with
`--artifact dist/<apk-name>` (and `--artifact dist/sbom.json`,
`--artifact dist/THIRD_PARTY_NOTICES.md`) added to `generate_release_manifest.dart`'s
invocation so the manifest actually lists something to checksum. Until that
follow-up lands, this step's real value at the proposed insertion point is
limited to catching a malformed manifest early (`verify_checksums` still
validates manifest shape even with an empty `artifacts` list) — not
artifact tampering.

## Why no build-time timestamp

The release manifest intentionally carries no generation timestamp, in the
main object or as a sibling field (ADR 0447 D1) — the artifact upload
step's own metadata (GitHub Actions run timestamp) already carries that
information. Adding one to the manifest would break the determinism
contract A1 measures: two runs against the same commit and the same inputs
must produce a byte-identical file.
