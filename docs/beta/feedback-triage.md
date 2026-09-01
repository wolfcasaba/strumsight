# Beta feedback triage — categories, severity, response time

> Companion to [`docs/beta/enrollment.md`](enrollment.md) (who is sending feedback) and
> [`docs/beta/tester-consent.md`](tester-consent.md) (what a diagnostics report can and cannot
> contain). This document is for whoever reads incoming beta feedback: how to sort it, how
> urgently to act on it, and — the one rule this round exists to make explicit — how to read a
> rejected diagnostics bundle correctly.

## Categories

| Category | What it covers |
|---|---|
| **Detection accuracy** | Chord/strum-direction/tempo detection disagreeing with what the tester actually played — the primary reason Lab-mode diagnostics exist at all. |
| **Crash / hard failure** | The app terminates, hangs, or a screen fails to render at all. |
| **Data / sync** | Settings not syncing, account state looking wrong, a share or export producing unexpected output. |
| **UX friction** | The app works as designed but the design itself is confusing, slow to reach, or inconsistent — no detection or data-integrity component. |
| **Consent / privacy question** | The tester is asking what a specific field is for, or wants to revoke something — triage should route this to `docs/beta/tester-consent.md` first; only escalate if that document does not answer it. |
| **Feature request** | Not a defect — logged, not triaged for urgency. |

A single report can span more than one category (e.g. a detection-accuracy report that also
attaches a diagnostics bundle is still primarily "detection accuracy"; the bundle is evidence,
not a separate report).

## Severity

| Severity | Definition | Examples |
|---|---|---|
| **Blocker** | Beta build is unusable for its primary purpose for most testers. | App fails to launch; every Analyze session crashes. |
| **High** | A core surface (detection, sign-in, sync) is measurably wrong for a subset of testers or inputs. | Chord detection consistently wrong on a common tuning; settings sync silently drops a field. |
| **Medium** | A real defect with a workaround, or affecting a narrow input/config. | A rare chord voicing misdetected; a share caption formatting glitch. |
| **Low** | Cosmetic, or a UX friction report with no functional defect. | Copy wording, spacing, a confusing but not incorrect label. |

Severity is about *impact*, not about how the report was produced — a Blocker reported with no
diagnostics bundle at all still outranks a Low severity report that includes one. A diagnostics
bundle is evidence that helps confirm and reproduce a report; its presence or absence does not by
itself change the report's severity.

## Response time (target, not contractual)

| Severity | First response | Target resolution or status update |
|---|---|---|
| Blocker | Same beta-testing day | Within 3 days, or an explicit "still investigating" update |
| High | Within 2 business days | Within 1 week |
| Medium | Within 1 week | Next beta build cut, if reproducible |
| Low | Acknowledged, batched | No individual timeline — reviewed in batch before a beta channel promotion |

These are targets a small team can actually hit, not an SLA — the beta program has no paid
support obligation attached to it.

## Reading a diagnostics bundle correctly — the one rule this round adds

`tool/release/build_diagnostics_bundle.py` (ADR 0486) enforces a hard size cap on the raw-audio
attachment — the MEASURED `DiagnosticsUploader.maxWavBytes`, 5,242,880 bytes, inclusive. **A
bundle that fails to build because the recorded clip is over that cap is a REJECTION, not data
loss.** The tool refuses to produce any output file at all rather than silently truncate the
clip (ADR 0486 D3) — this is a deliberate *difference* from the client uploader, which decimates
an over-long clip down to fit the same cap rather than refusing the upload outright. A triager
who sees "the tester says they sent a report but the packaging tool errored" should not read
that as "we have a corrupted or partial audio clip to work with" — there is no partial clip; the
tool wrote nothing. The correct next step is either: ask the tester to re-record a shorter clip,
or proceed on the `ml_dsp_comparison_events` + `device_metadata` evidence alone (still available
under diagnostics-only consent, independent of the raw-audio layer — see
`docs/beta/tester-consent.md`'s two-layer table).

Separately: raw audio only ever appears in a bundle when the tester granted BOTH
`--consent-diagnostics` and `--consent-raw-audio` (ADR 0486 D1). A bundle without an `audioClips`
entry is the tester's own consent choice, not a bug in the packaging step — do not ask a tester
"why didn't you attach audio" without first checking whether they were ever asked to grant the
raw-audio layer.

## Escalation

A Blocker or a High-severity detection-accuracy report with a reproducible diagnostics bundle is
the strongest candidate for feeding back into the model/DSP evaluation loop
(`tool/release/build_ai_report.py`, ADR 0477) ahead of the next beta cut — triage should flag
these explicitly rather than letting them sit in a general backlog next to Low-severity UX
reports.
