# Release Candidate checklist (E12-R25, ADR 0488)

This checklist is for the human/orchestrator step that runs the
`release-candidate.yml` workflow once it has been installed from
[`docs/release/workflows/release-candidate.proposal.yml`](workflows/release-candidate.proposal.yml)
(ADR 0488 D1/D8). It does not replace any gate — it is the order in which a
person confirms the gate actually ran, and where to find the evidence
afterward.

## Before dispatching

- [ ] The target branch/tag is the one intended for this release candidate —
      `workflow_dispatch` runs against whatever ref is selected in the
      Actions UI; double-check it before clicking Run.
- [ ] `docs/release/ai-quality-gates.md`'s evidence matrix is current for
      every `ga_scope: true` capability (`tool/release/build_ai_report.py`
      reads it — a stale row fails closed at build time, not silently).
- [ ] `docs/security/exceptions.yaml` has no entry expiring before this
      release ships (`tool/release/security_scan.py` treats an expired
      entry as a critical finding, not a silent pass-through).
- [ ] The four production signing secrets
      (`ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`,
      `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`) are present in the
      repository/environment secrets the `build-release-candidate` job
      reads — `signing-prerequisites`-style checks fail the run early if
      one is missing, but confirming beforehand avoids burning a full
      quality-gate run on a signing miss.

## Dispatching

- [ ] Run `release-candidate.yml` via `workflow_dispatch`.
- [ ] The `approve-release-candidate` job pauses on the
      `release-candidate-approval` environment's required reviewers
      (ADR 0488 D3) — a release candidate is never assembled unattended.
      Approve only after independently confirming the two checklist
      sections above.
- [ ] Confirm `quality-gates` and `backend-tests` both ran (they only start
      once `approve-release-candidate` has been approved — ADR 0488 D3's
      `needs:` chain) and both finished green. A red gate must never reach
      `build-release-candidate` — that job's own `needs:` on both is the
      mechanical guarantee, not a manual read of the run log.

## After a green run

- [ ] Download the `release-candidate` artifact and confirm it contains all
      seven pieces of evidence: the signed APK, `release-manifest.json`,
      `sbom.json`, `THIRD_PARTY_NOTICES.md`, `ai-report.json`,
      `security-report.json`, `lcov.info`, plus `checksum-manifest.json`
      covering all seven (ADR 0488 D5).
- [ ] Re-run `python3 tool/release/assemble_rc.py --verify --output-dir
      <extracted-package-dir>` locally against the downloaded artifact —
      this re-derives every sha256 from the actual bytes you received, not
      from the CI log's say-so.
- [ ] Compare `release-manifest.json`'s `app.buildNumber` against the
      previous shipped release candidate with
      `python3 tool/release/verify_artifacts.py --manifest
      release-manifest.json --previous <previous-manifest>` — a
      non-strictly-increasing build number is a hard stop (ADR 0447 D2).
- [ ] Read `ai-report.json`'s top-level `findings` — non-empty means a
      `ga_scope: true` capability has an unresolved regression; the job
      itself already failed the run for this, this is a human
      double-check, not the only gate.
- [ ] Read `security-report.json`'s `findings` the same way — the scan job
      already fails the run on any critical/fatal finding.

## On a red run

- [ ] A red `quality-gates` or `backend-tests` job means `build-release-
      candidate` never started (`needs:` — ADR 0488 D3). There is no
      partial release candidate to inspect; fix the gate and re-dispatch
      from `approve-release-candidate`.
- [ ] A red `build-release-candidate` job with the failure inside
      "Assemble release candidate package" means
      `tool/release/assemble_rc.py` could not resolve a mandatory input —
      the step's own log names exactly which one (ADR 0488 D4). No
      artifact is uploaded in this case; `if-no-files-found: error` on the
      upload step is the second, redundant guarantee of that.
- [ ] A red "Verify release candidate checksum manifest" step (immediately
      after assembly, before upload) means the just-assembled package
      already diverges from its own manifest inside the SAME job run —
      treat this as a tooling bug in `assemble_rc.py`, not a release issue,
      and do not attempt to hand-patch the manifest.

## Known open item (ADR 0488, "Nyitott")

This workflow builds and packages an **APK only**. No workflow in this
repository builds an app bundle (AAB) as of this round; the proposal
documents the APK as the mandatory artifact and leaves AAB as a future,
identically-signed addition, not something this checklist can verify yet.
