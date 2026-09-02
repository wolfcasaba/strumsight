# Open Beta canary cohort — launch preparation (E12-R29)

<!-- human-gate:begin -->
## Status: NOT launched — this document is a gate, not a launch announcement

The Open Beta canary cohort has NOT launched. Opening it — inviting testers, publishing the
canary-channel build, and widening the flag profile below onto real devices — is a human decision
and a human action, made and taken outside this repository's automation. This round, and this
document, only prepare the canary configuration and the capacity ceiling it is bounded by
(`docs/operations/capacity-review.md`). Nothing below changes that status; only a person filling in
the **Human launch field** at the bottom of this document does, and that field is left blank by
this round on purpose.
<!-- human-gate:end -->

> Companion documents: [`docs/operations/capacity-review.md`](../operations/capacity-review.md)
> (the measured ceiling this profile's `maxTesters` cites), [`docs/beta/cohort-profiles.yaml`](cohort-profiles.yaml)
> (the `internal` / `closed_beta` cohorts — UNCHANGED by this round, round brief §0.0 P7),
> [`docs/beta/closed-beta-launch.md`](closed-beta-launch.md) (the precedent this profile widens
> past), [`docs/beta/enrollment.md`](enrollment.md) / [`docs/beta/tester-consent.md`](tester-consent.md)
> / [`docs/beta/feedback-triage.md`](feedback-triage.md) / [`docs/beta/daily-triage-template.md`](daily-triage-template.md)
> (unchanged operational processes this canary reuses as-is), and
> [`docs/release/ga-scope.md`](../release/ga-scope.md) (the flag classifications the canary
> selection below respects).

## 1. Why the canary profile lives here, not in `cohort-profiles.yaml`

[`test/tooling/ga_scope_test.dart:49-56`](../../test/tooling/ga_scope_test.dart) measures that
`docs/release/ga-scope.md` classifies **exactly** the 16 flag keys named in
`docs/beta/cohort-profiles.yaml`'s two cohorts — no more, no fewer. Adding a canary cohort to that
file would add a 17th (or more) flag key and turn `ga_scope_test.dart` red immediately, over a
change unrelated to what that test actually verifies (round brief §0.0 P7). The canary profile
therefore lives in **this** document instead. Its isolation from the two stable cohorts —
`internal` and `closed_beta` must keep their exact, already-shipped flag values — is machine-checked
by [`test/tooling/canary_cohort_test.dart`](../../test/tooling/canary_cohort_test.dart)'s A5 group,
not by `ga_scope_test.dart`.

## 2. The canary cohort profile

Every flag key below is drawn from the measured 40-entry catalog
(`lib/core/feature_flags/feature_flag_registry.dart`) —
`test/tooling/canary_cohort_test.dart`'s P7 group fails the cell on an invented key. The three
flags this profile turns on beyond `closed_beta` — `migratedLearnEnabled`,
`practiceDetailedHistoryEnabled`, `adaptiveShellEnabled` — are exactly the three `preview`-classified
flags `docs/release/ga-scope.md` §2 already lists as proven in the `internal` cohort. Nothing
classified `disabled` or `postponed` there is ever turned on here, in any cohort, by this document.

`maxTesters` below is the ceiling [`docs/operations/capacity-review.md`](../operations/capacity-review.md)
§6 computes from measured backend constants — see that document for the reproducible arithmetic;
this document only cites the result, it does not re-derive it.

<!-- canary-cohort-profile:begin -->
```yaml
id: canary
description: >-
  First Open Beta widening step past closed_beta — a small, closely observed
  slice used to validate before wider exposure. Deliberately lives outside
  docs/beta/cohort-profiles.yaml (see §1 above) so it never adds a 17th flag
  key to the set test/tooling/ga_scope_test.dart classifies.
versionRange:
  min: "1.0.0"
maxTesters: 25
flags:
  accountEnabled: false
  diagnosticsEnabled: false
  labModeAvailable: true
  practiceEngineV2Enabled: true
  migratedLearnEnabled: true
  practiceDetailedHistoryEnabled: true
  songTrainerV2Enabled: false
  aiTutorEnabled: false
  aiTutorCloudEnabled: false
  visionEnabled: false
  visionLabCaptureEnabled: false
  audioAnalysisV2Enabled: false
  communityEnabled: false
  communityWritesEnabled: false
  communityMediaEnabled: false
  adaptiveShellEnabled: true
```
<!-- canary-cohort-profile:end -->

## 3. Opening steps (all human-gated — see the Status section above)

1. **Confirm the ceiling still holds.** Re-run the arithmetic in
   `docs/operations/capacity-review.md` §6 against the CURRENT `backend/app/routers/auth.py` and
   `docs/beta/cohort-profiles.yaml` — if either measured constant moved since this round, the
   ceiling above may be stale; `test/tooling/canary_cohort_test.dart`'s A1 group re-derives it on
   every gate run, so a stale ceiling turns that cell red before it reaches a human.
2. **Cut a build at or above `versionRange.min`.** Same artifact pipeline
   `docs/beta/closed-beta-launch.md` §4 already names (`tool/release/assemble_rc.py`,
   `.github/workflows/release-apk.yml`) — this round does not add a new one.
3. **Invite at most `maxTesters` testers**, per `docs/beta/enrollment.md`'s process (unchanged by
   this round).
4. **Watch the daily triage rhythm** (`docs/beta/daily-triage-template.md`, unchanged) — the
   P0/P1-blocks-cohort-expansion rule applies to the canary cohort exactly as it already does to
   `closed_beta`.
5. **Do not widen past the canary** before this document's Human launch field (§5) is filled in a
   SECOND time for the wider Open Beta step that follows a successful canary — that is a separate,
   later human decision this round does not make and this document does not pre-authorize.

## 4. Known gap this round surfaces, not fixes

`docs/operations/capacity-review.md` §3 measures that the settings-sync endpoint
(`backend/app/routers/settings.py`) carries **no rate limiter** — the only two mounted, throttled
endpoints today are `/auth/login` and `/auth/register`. This is a gap, not a guard: a future round
that widens past the canary should close it before that step, not after. This round documents the
gap; it does not implement a fix (`backend/app/**` is outside this round's `allowed_paths`).

## 5. Human launch field

- **Status:** ☐ Ready to open canary  ☐ Opened (date: __________)
- **Filled in by:** _______________________________
- **Notes:** _______________________________________________________________________________

This field is intentionally left unticked by this round. Ticking it, and everything it authorizes,
is the user's decision to make.
