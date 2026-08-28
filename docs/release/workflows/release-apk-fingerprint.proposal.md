# Proposal: capture the production signing certificate fingerprint

- **Status:** proposal only — NOT applied. `.github/workflows/**` is the
  measure-gate's protected zone (ADR 0321 `PROTECTED_GLOBS`), and the
  standing gate-edit authorization file (ADR 0372) does not exist on this
  tree, so an implementer session cannot edit it directly (E12-R07 brief
  §0.0.1.b). Applying this fragment to `.github/workflows/release-apk.yml`
  and dispatching the workflow is an orchestrator/human step that happens
  **after** this round merges — the same deferred-application pattern the
  E12-R06 provenance proposal
  (`docs/release/workflows/release-apk-provenance.proposal.md`) already
  documents.
- **Round:** `E12-R07` —
  [`docs/adr/0448-production-signing-policy-and-secret-hardening.md`](../../adr/0448-production-signing-policy-and-secret-hardening.md)
  is the binding contract (D4/D5).
- **Gate:** the YAML fragment below is machine-checked by
  `test/tooling/signing_policy_test.dart` (group "A5") with its own
  restricted-subset parser — no `package:yaml` import and no shell-out to
  `rg`/`grep`/`jq`/`gh` (ADR 0448 D6, precedent: ADR 0447 D5, L110).

## Insertion point

Insert the two steps below into the `release-apk` job of
`.github/workflows/release-apk.yml`, **immediately AFTER** the step named
`Materialize production keystore` (currently lines 97–112) and **BEFORE**
the step named `Build production APK`. Both step names are measured against
the real workflow file by the gate test. The fingerprint is read from the
keystore only after it has been materialized to `$RUNNER_TEMP` — reading it
any earlier would have nothing to read; any later (e.g. after `Remove
production keystore`) would have nothing left to read, since that step
deletes the keystore file (`if: always()`).

## What this step does

**Capture production signing certificate fingerprint** runs `keytool
-list -v` against the already-materialized keystore (`steps.keystore.
outputs.path`, itself written by the existing `umask 077` step) to extract
the certificate's SHA-256 fingerprint, then writes it — together with the
key alias, never the password or any key material — to a small sidecar
JSON file, `dist/signing-certificate.json`. **Upload signing certificate**
uploads that sidecar as a build artifact.

## Why a sidecar file, not a release-manifest field (ADR 0448 D4)

The E12-R06 release manifest generator
(`tool/generate_release_manifest.dart`) has no certificate/signing field in
its schema (`schemaVersion` · `app{version,buildNumber,shortSha,channel}` ·
`modelPackage` · `knowledgePackage` · `artifacts[]`), and that generator is
this round's forbidden zone — it cannot be edited here, and raising
`schemaVersion` would touch the E12-R06 determinism contract. Instead this
proposal reuses the generator's existing, repeatable `--artifact <path>`
flag (`tool/generate_release_manifest.dart:57–58`): once combined with the
E12-R06 provenance proposal, adding
`--artifact dist/signing-certificate.json` to that proposal's `dart run
tool/generate_release_manifest.dart` invocation makes the manifest's
`artifacts[]` list carry the sidecar's name, path, and sha256 — the
provenance chain is complete without a schema change. (Wiring that
`--artifact` flag into the other proposal's fragment is a follow-up for
whoever applies both proposals together; this document does not edit that
file, which is outside E12-R07's allowed-files list.)

## Why no secret is ever observable (ADR 0448 D5)

This is the direct lesson of
[L528](../../LESSONS.md#l528): a *previous* hardening step (E12-R04) leaked
secrets into a boot log while implementing an unrelated tightening — a
strengthening step is not exempt from secret discipline, it is the
highest-risk place to apply it. This step:

- passes the keystore password to `keytool` via `-storepass:env
  STRUMSIGHT_RELEASE_STORE_PASSWORD` — never as a literal, observable
  command-line argument (the process list on a shared runner is
  observable; an env-var reference by name is not the value itself);
- never `echo`s, `cat`s, or otherwise dumps `keytool`'s raw output — only
  the single extracted SHA-256 line is captured into a shell variable, and
  only the already-reduced fingerprint substring (not the full `keytool
  -list -v` output) ever reaches a file;
- has no `set -x` (which would echo every subsequent command, including
  any secret-bearing ones);
- explicitly `::add-mask::`s the store password before use, on top of
  GitHub Actions' automatic masking of `secrets.*`-sourced env values —
  defense in depth, not reliance on a single layer;
- writes a sidecar JSON with exactly two keys, `keyAlias` and
  `sha256Fingerprint` — neither is secret (D4/D5: the sidecar carries the
  fingerprint and the alias, never a password or private key material).

## Proposed YAML fragment

```yaml
steps:
  - name: Capture production signing certificate fingerprint
    id: fingerprint
    shell: bash
    env:
      STRUMSIGHT_RELEASE_STORE_PASSWORD: ${{ secrets.ANDROID_STORE_PASSWORD }}
      STRUMSIGHT_RELEASE_KEY_ALIAS: ${{ secrets.ANDROID_KEY_ALIAS }}
      KEYSTORE_PATH: ${{ steps.keystore.outputs.path }}
    run: |
      set -euo pipefail
      echo "::add-mask::$STRUMSIGHT_RELEASE_STORE_PASSWORD"
      fingerprint_line="$(
        keytool -list -v \
          -keystore "$KEYSTORE_PATH" \
          -alias "$STRUMSIGHT_RELEASE_KEY_ALIAS" \
          -storepass:env STRUMSIGHT_RELEASE_STORE_PASSWORD |
          grep 'SHA256:'
      )"
      fingerprint="$(printf '%s' "$fingerprint_line" | sed -E 's/^.*SHA256: *//')"
      mkdir -p dist
      printf '{\n  "keyAlias": "%s",\n  "sha256Fingerprint": "%s"\n}\n' \
        "$STRUMSIGHT_RELEASE_KEY_ALIAS" "$fingerprint" \
        > dist/signing-certificate.json
  - name: Upload signing certificate
    uses: actions/upload-artifact@v4
    with:
      name: signing-certificate
      path: dist/signing-certificate.json
      if-no-files-found: error
```

## Why the manifest binding is a follow-up, not part of this fragment

Wiring `--artifact dist/signing-certificate.json` into
`tool/generate_release_manifest.dart`'s invocation is defined in the
E12-R06 provenance proposal
(`docs/release/workflows/release-apk-provenance.proposal.md`), a file
outside this round's allowed-files list. Combining both proposals means:
generate the release manifest AFTER this step (so
`dist/signing-certificate.json` already exists), and add
`--artifact dist/signing-certificate.json` to that generator invocation.
Until both proposals are applied together, this fragment alone still
produces a standalone, checksummable, secret-free artifact — the sidecar
is useful even before it is bound into the manifest.
