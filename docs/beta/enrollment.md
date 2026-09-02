# Beta enrollment — channel, cohort, joining, leaving, version enforcement

> Companion to [`docs/beta/tester-consent.md`](tester-consent.md) (what testers agree to) and
> [`docs/beta/feedback-triage.md`](feedback-triage.md) (what happens to what they send). This
> document covers the *distribution* side: who is a beta tester, how they get a build, and how
> that stops. It deliberately stays out of two neighboring rounds' territory (round brief §0.0 /
> ADR 0486 D7): it does **not** define a `beta-release.yml` CI workflow
> ([E12-R25](../rounds/e12-r25-release-candidate-assembly.md)-adjacent) and it does **not** define
> a machine-checked cohort-profile schema (`docs/beta/cohort-profiles.yaml`,
> `tool/release/verify_beta_profile.py` — both
> [E12-R27](../rounds/e12-r27-closed-beta-launch-and-monitoring.md)). Cohort below is described in
> prose only, on purpose.

## Channel

The release manifest (`tool/generate_release_manifest.dart`, ADR 0447) carries an `app.channel`
string with every build; a beta distribution build is tagged `channel: beta`, distinct from
`development` (the CLI default, local/CI smoke builds) and `production` (general-release APKs,
`docs/release/workflows/release-apk-provenance.proposal.md`). `tool/release/generate_beta_notes.py`
reads this field straight through — it never re-derives or guesses a channel, and a beta note
generated from a manifest that is not actually `channel: beta` still states whatever channel the
manifest says, so a mislabeled build is visible in the note rather than silently relabeled.

## Cohort (prose, not a machine-checked schema)

A beta cohort is a *named group of testers*, not a code artifact this round produces. Until
[E12-R27](e12-r27-closed-beta-launch-and-monitoring.md) defines a machine-checked
`cohort-profiles.yaml`, cohort membership is tracked outside this repository (an invite list —
e-mail addresses or a distribution-platform tester group), and this document is the place that
list's owner should point testers at for what they are agreeing to and how to get out.

Two cohort shapes are anticipated (implementation deferred to
[E12-R27](../rounds/e12-r27-closed-beta-launch-and-monitoring.md)), without committing to
either's implementation yet:

- **General beta** — anyone who opts in through the public beta-enrollment link, no feature
  restriction beyond the channel itself.
- **Focused cohort** — a smaller, invited group asked to exercise a specific surface (e.g. a
  particular chord-detection improvement) alongside the general beta build. A focused cohort
  still runs the same `channel: beta` build; nothing on the wire distinguishes it from general
  beta today. This is a **named gap**: there is no per-cohort feature flag or telemetry tag yet.

## Joining

1. A prospective tester reads [`docs/beta/tester-consent.md`](tester-consent.md) — what leaves
   the device under an account, under Lab-mode diagnostics, and under an explicit share, and the
   two-layer consent a diagnostics report itself requires.
2. They install a `channel: beta` build (distribution mechanism — e.g. a distribution platform's
   tester link, or a directly-shared APK — is an operational choice outside this repo's scope;
   this document does not mandate one).
3. Enrollment itself grants **no extra data collection by default** — see
   `docs/beta/tester-consent.md`'s "short version". Turning on Lab mode and granting diagnostics
   consent remain separate, explicit steps.

## Leaving

- Uninstalling the beta build, or simply not updating past the last beta version you have, ends
  your participation — there is no separate "unenroll" action the app itself performs, because
  the app holds no enrollment state of its own (today's cohort tracking lives outside the
  device, per the "Cohort" section above).
- Leaving does **not** retroactively delete data already sent under an account, a diagnostics
  report, or a share — see `docs/beta/tester-consent.md`'s "Revoking consent" section for what
  each of those channels can and cannot undo.
- If you sent a diagnostics report and want to say more about it (or ask about it), do that
  through whatever feedback channel `docs/beta/feedback-triage.md` names, referencing the report
  — the upload itself has no client-measured deletion path (a named gap, not a silent one; see
  the `retention` column for `diagnostics_upload` in `docs/privacy/data-inventory.yaml`).

## Version enforcement

- A beta build's identity is exactly what `tool/release/generate_beta_notes.py` prints from the
  release manifest: `app.version` + `app.buildNumber` + `app.shortSha`. Any bug report, feedback
  message, or diagnostics bundle should be paired with that triple, not just the marketing
  version string — `1.2.3` alone does not distinguish two different `beta` builds cut on the same
  day.
- `tool/release/verify_artifacts.py` (ADR 0447 D2, existing — not new to this round) already
  enforces that a new release manifest's `app.buildNumber` is strictly greater than the previous
  one's; a beta channel build is no exception to that monotonicity check.
- There is no separate "minimum supported beta build" enforcement mechanism in the app itself
  yet (no forced-update gate). Until one exists, the beta note's build-identifier triple is the
  only tool available for a triager to tell whether a report came from a stale build — see
  `docs/beta/feedback-triage.md`.
