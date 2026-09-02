# Closed Beta launch checklist (E12-R27)

## Status: NOT launched — this document is a gate, not a launch announcement

The Closed Beta has NOT launched. Launching it — inviting testers, publishing the beta-channel
artifact, opening a cohort — is a human decision and a human action, made and taken outside this
repository's automation. This round, and this document, only prepare the configuration and prove
the emergency kill switch on it. Nothing below changes that status; only a person filling in the
**Human launch field** at the bottom of this document does, and that field is left blank by this
round on purpose.

> Companion documents: [`docs/beta/enrollment.md`](enrollment.md) (who is a tester, how they join
> and leave), [`docs/beta/tester-consent.md`](tester-consent.md) (what leaves the device and under
> what consent), [`docs/beta/feedback-triage.md`](feedback-triage.md) (categories, severity,
> response-time targets for what testers send back), and
> [`docs/beta/daily-triage-template.md`](daily-triage-template.md) (the daily rhythm and the
> open-P0/P1-blocks-expansion rule that starts once this checklist is actually acted on).

## 1. Pre-launch checklist — every line MEASURED, not asserted

Every line below is machine-checked by
[`test/tooling/beta_profile_test.dart`](../../test/tooling/beta_profile_test.dart)'s A5 group: a
missing reference, or a referenced repo-relative path that does not exist on the tree, fails that
test — this checklist cannot silently drift from what is actually on disk.

- [ ] Cohort profile exists and is schema-valid — `docs/beta/cohort-profiles.yaml`.
- [ ] Cohort profile validates against the measured 40-entry feature-flag catalog (A1/A2/A3) —
      run `tool/release/verify_beta_profile.py` against `docs/beta/cohort-profiles.yaml` (exact
      command: §3 below) and confirm exit 0 (captured output: §3 below).
- [ ] The feature-flag catalog itself, and its human-readable projection — measured at
      `lib/core/feature_flags/feature_flag_registry.dart` (40 entries, Kör 5, ADR 0446) and
      `docs/release/kill-switches.md`.
- [ ] Every high-risk capability (`accountEnabled`, `diagnosticsEnabled`, `aiTutorCloudEnabled`,
      `visionLabCaptureEnabled`, `communityEnabled`, `communityWritesEnabled`,
      `communityMediaEnabled`) defaults to off in every cohort — enforced by
      `tool/release/verify_beta_profile.py` A3, proven by
      `test/tooling/beta_profile_test.dart`.
- [ ] The kill switch dry-run is read-only and toggles exactly one flag — captured output: §3
      below, machine-checked by `test/tooling/beta_profile_test.dart`.
- [ ] Turning a capability off does not destroy user data — round-trip proof at
      `test/tooling/rollback_policy_test.dart` and the independent "never touches stored data"
      proof at `test/core/feature_flags/feature_flag_registry_test.dart` (ADR 0446 D7; this round
      does not duplicate either, it relies on both as already-measured evidence).
- [ ] Beta enrollment process is documented — `docs/beta/enrollment.md`.
- [ ] Tester consent (what leaves the device, what's redacted, how to revoke) is documented —
      `docs/beta/tester-consent.md`.
- [ ] Feedback triage categories/severity/response-time are documented —
      `docs/beta/feedback-triage.md`.
- [ ] Daily triage rhythm and the P0/P1-blocks-cohort-expansion decision rule are documented —
      `docs/beta/daily-triage-template.md`.
- [ ] Release Candidate assembly is proven end-to-end — `docs/release/rc-checklist.md` and
      `tool/release/assemble_rc.py`.
- [ ] The Release Candidate CI workflow that produces the artifact this checklist assumes exists —
      `.github/workflows/release-apk.yml`.
- [ ] A disaster-recovery / rollback drill has actually been run and recorded, not just planned —
      `docs/operations/disaster-recovery-drill.md` and `tool/release/verify_rollback.py`.
- [ ] The diagnostics-bundle tool triage will lean on is available and tested —
      `tool/release/build_diagnostics_bundle.py`.

## 2. Monitoring — the real boundary, stated plainly

There is **no telemetry-collection pipeline** on this tree today.
[E12-R19](../rounds/e12-r19-privacy-safe-observability-and-slo.md) shipped a telemetry *contract*
(schemas, consent plumbing), not ingestion or aggregation. "Monitoring the Closed Beta" therefore
means exactly two things, both manual: reading whatever a tester sends through the channel
`docs/beta/feedback-triage.md` names, and the diagnostics bundle attached to a report (built by
`tool/release/build_diagnostics_bundle.py`, never a live stream). There is no dashboard, no alert,
and no aggregate metric. `docs/beta/daily-triage-template.md` is the full monitoring procedure —
not a placeholder for one that will exist later.

## 3. Kill-switch dry-run — captured output

Subject: `labModeAvailable` in the `closed_beta` cohort — a **low**-risk flag the profile turns
**on** for that cohort (every `high`-risk flag is off by default, so a dry-run against one of those
would prove nothing new). Command:

```bash
python3 tool/release/verify_beta_profile.py --profile docs/beta/cohort-profiles.yaml \
  --kill-switch labModeAvailable --cohort closed_beta
```

The block below is this command's real, unedited stdout on this tree. It is read-only (nothing on
disk changed when it ran) and toggles exactly one line (`labModeAvailable`) between `before:` and
`after:` — both properties are re-measured by `test/tooling/beta_profile_test.dart`'s A4 group,
which also re-runs the exact command above and fails if its output ever drifts from the block
below.

<!-- beta-kill-switch-dry-run:begin -->
```text
kill-switch dry-run: cohort=closed_beta flag=labModeAvailable (read-only, nothing written to disk)
before:
accountEnabled: false
adaptiveShellEnabled: false
aiTutorCloudEnabled: false
aiTutorEnabled: false
audioAnalysisV2Enabled: false
communityEnabled: false
communityMediaEnabled: false
communityWritesEnabled: false
diagnosticsEnabled: false
labModeAvailable: true
migratedLearnEnabled: false
practiceDetailedHistoryEnabled: false
practiceEngineV2Enabled: true
songTrainerV2Enabled: false
visionEnabled: false
visionLabCaptureEnabled: false
after:
accountEnabled: false
adaptiveShellEnabled: false
aiTutorCloudEnabled: false
aiTutorEnabled: false
audioAnalysisV2Enabled: false
communityEnabled: false
communityMediaEnabled: false
communityWritesEnabled: false
diagnosticsEnabled: false
labModeAvailable: false
migratedLearnEnabled: false
practiceDetailedHistoryEnabled: false
practiceEngineV2Enabled: true
songTrainerV2Enabled: false
visionEnabled: false
visionLabCaptureEnabled: false
```
<!-- beta-kill-switch-dry-run:end -->

**Turning it back off in a real incident does not destroy any tester's data** — this is the same
resolver mechanism `test/tooling/rollback_policy_test.dart`'s A3 group and
`test/core/feature_flags/feature_flag_registry_test.dart`'s A6 group already measure (ADR 0446 D7);
this dry-run proves the *profile-level* view stays single-flag and read-only, it does not re-run
that underlying data-safety proof a third time.

## 4. What this round could NOT do on this box, and why

- **No APK was built or installed.** Assembling a signed release/beta artifact is
  `tool/release/assemble_rc.py` / `.github/workflows/release-apk.yml`'s job (Kör 25), not this
  round's. This checklist assumes that artifact exists by the time a human acts on it; it does not
  produce one.
- **No tester was actually invited, and no cohort was actually opened.** Both are the human step
  named in the Status section above — outside this repository's automation by design (round brief
  §0.0).
- **`maxTesters` and `versionRange` in `docs/beta/cohort-profiles.yaml` are not enforced by any
  tool on this tree.** They are read by a human running the daily triage pass, the same way
  `docs/beta/enrollment.md`'s cohort section already names cohort membership itself as tracked
  outside the repository.
- **No live monitoring dashboard exists to demonstrate.** §2 above is not an abbreviated
  description of one — it is the complete, current monitoring capability.

## 5. Human launch field

- **Status:** ☐ Ready to launch  ☐ Launched (date: __________)
- **Filled in by:** _______________________________
- **Notes:** _______________________________________________________________________________

This field is intentionally left unticked by this round. Ticking it, and everything it authorizes,
is the user's decision to make.
