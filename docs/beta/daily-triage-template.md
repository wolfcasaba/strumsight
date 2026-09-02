# Closed Beta daily triage template (E12-R27)

> Companion to [`docs/beta/feedback-triage.md`](feedback-triage.md) (categories, severity
> definitions, response-time targets — this document does not redefine any of those, it names
> which of them gate cohort growth) and [`docs/beta/closed-beta-launch.md`](closed-beta-launch.md)
> (the launch checklist this triage rhythm starts once a human ticks the launch field). Use one
> copy of the "Today's pass" section per day the Closed Beta is live.

## What feeds a daily pass — and what does not

Two inputs exist on this tree today:

1. **The diagnostics bundle**, built on request from a tester-submitted Lab-mode session by
   [`tool/release/build_diagnostics_bundle.py`](../../tool/release/build_diagnostics_bundle.py)
   (ADR 0486) — `ml_dsp_comparison_events` + `device_metadata`, plus a raw audio clip only when the
   tester granted both consent layers (see `docs/beta/tester-consent.md`'s two-layer table). A
   triager never has a *live* stream of these; each one arrives attached to a feedback report.
2. **Manual feedback** — whatever a tester sends through the channel
   [`docs/beta/feedback-triage.md`](feedback-triage.md) names, triaged by that document's
   categories/severity/response-time tables.

**There is no telemetry-collection pipeline on this tree today.** [E12-R19](../rounds/e12-r19-privacy-safe-observability-and-slo.md)
(referenced by round brief §0.0.1 P7) shipped a telemetry *contract* — schemas and consent
plumbing — not an ingestion or aggregation path. "Monitoring the Closed Beta" therefore means, in
full, reading the two inputs above; it does not mean a dashboard, an alert, or an aggregate metric,
because none of those exist yet. Do not read a quiet day as "no dashboard fired" — no dashboard
exists to fire. A quiet day is only evidence of an actual absence of reports, nothing more.

## Categories and severity

Use [`docs/beta/feedback-triage.md`](feedback-triage.md)'s categories (Detection accuracy, Crash /
hard failure, Data / sync, UX friction, Consent / privacy question, Feature request) and severity
tiers (Blocker, High, Medium, Low) unchanged — this template does not introduce a second taxonomy.
For the cohort-expansion decision rule below, this document names two of those tiers **P0** and
**P1**:

| This template's label | Maps to `feedback-triage.md` severity |
|---|---|
| **P0** | Blocker |
| **P1** | High |

## Today's pass (repeat daily while the beta is live)

1. **Collect.** List every feedback report received since the last pass (manual channel), and every
   diagnostics bundle attached to one of them. A bundle that failed to build (over the raw-audio
   size cap) is a rejection, not data loss — read it per `feedback-triage.md`'s "Reading a
   diagnostics bundle correctly" section before treating it as a missing report.
2. **Categorize + severity.** Apply `feedback-triage.md`'s tables to each report. Note the build
   identity (`app.version` + `app.buildNumber` + `app.shortSha`, per `docs/beta/enrollment.md`'s
   "Version enforcement" section) for every report so a fixed-in-next-build report doesn't get
   re-triaged against a stale build.
3. **Escalate.** Any Blocker (P0), or a High-severity (P1) detection-accuracy report with a
   reproducible diagnostics bundle, gets flagged for the model/DSP evaluation loop
   (`tool/release/build_ai_report.py`, ADR 0477) per `feedback-triage.md`'s "Escalation" section —
   do not let it sit in a general backlog.
4. **Count open P0/P1.** Tally every Blocker and every High-severity report still open (not
   resolved, not explicitly downgraded) as of this pass. This count is the input to the decision
   rule below.
5. **Record the decision.** Write down the open P0/P1 count and the resulting cohort-expansion
   decision (see below) so the next day's pass has a written trail, not a memory of yesterday's
   call.

## Decision rule: open P0/P1 blocks cohort expansion

**With one or more open P0 (Blocker) or P1 (High) report, there is NO cohort expansion** — no
raising a cohort's `maxTesters` in [`docs/beta/cohort-profiles.yaml`](cohort-profiles.yaml), no
inviting a new cohort, no widening a `versionRange`. This is unconditional: a P0/P1 report being
"probably fixed in the next build" does not count as resolved until it actually is (per step 4 —
still open until resolved or explicitly downgraded, not until someone expects a fix).

Cohort expansion may resume once a pass finds **zero** open P0/P1 reports. The expansion itself is
edited into `cohort-profiles.yaml` and re-validated with
[`tool/release/verify_beta_profile.py`](../../tool/release/verify_beta_profile.py) (A1/A2/A3) before
it takes effect — this template does not grant that edit any exemption from those checks.

## What this template does not do

- It does not collect or aggregate telemetry (see above — none exists to collect).
- It does not replace `feedback-triage.md`'s response-time targets — those still apply per-report,
  independent of the daily cohort-expansion pass.
- It does not itself open, close, or resize a cohort — the human step named in
  `docs/beta/closed-beta-launch.md` does that, informed by the decision recorded here.
