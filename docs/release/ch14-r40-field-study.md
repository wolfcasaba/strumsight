# Chapter 14 Kör 40 — internal Alpha field study protocol

- **Round:** `E14-R40` (Chapter 14, Kör 40)
- **Status: NOT RUN.** This document is the protocol and the machine-side
  enrolment surface only. The study itself needs **8 guitarists, several
  phone models, several guitars and a noisy room** — none of which exists in
  the container this was written in.
- **Written:** 2026-09-09, PKG-D
- **Code side shipped with it:** `lib/core/telemetry/field_session_tag.dart`
  (the closed cohort + task tag), `fieldStudyEnrolmentProvider` and
  `resolveFieldSessionTag` in `lib/features/settings/providers/telemetry_consent_provider.dart`,
  gated on `FeatureFlags.recognitionFieldSessionTaggingEnabled`
  ([ADR 0542](../adr/0542-opt-in-beta-telemetry-consent-and-recognition-rollout-flags.md) D7)

---

## 0. Why this document exists before the study does

A field study that is designed while it runs measures whatever it happened
to notice. Writing the task list, the measures and the consent rule first is
what makes the eight sessions comparable — and what makes a NEGATIVE result
(the app is not good enough yet) a usable outcome rather than an
embarrassment to be re-framed afterwards.

Nothing in this file may be filled in with a plausible number later. Every
result table below stays empty until a real session produces it.

## 1. Participants and equipment

| Dimension | Target | Why |
|---|---|---|
| Guitarists | 8 | SDD Ch14 §7.1; below that, one player's technique dominates |
| Phone models | ≥ 6 | the measured baseline corpus has ZERO phone-microphone diversity — this is the single biggest known blind spot |
| Guitars | ≥ 4 | string age and body type move the chroma more than most people expect |
| Rooms | ≥ 4, including one deliberately noisy | §7.1; the noisy room is a task, not an accident |
| Playing style | pick and finger, quiet / medium / loud | §7.1 |

Each participant runs the full task list once. A session is ~35 minutes.

## 2. Task list

| # | Task | What the participant does | What is being observed |
|---|---|---|---|
| T1 | `setup` | opens the app cold, gets to a practice session | taps to first useful screen; whether Audio Setup is understood without help |
| T2 | `freePlay` | plays freely for 5 minutes | false-visible events; whether the UI ever asserts something the participant did not play |
| T3 | `guidedPattern` | follows one strum pattern at a comfortable tempo | direction correctness as the participant perceives it; whether "uncertain" is understood as uncertain |
| T4 | `chordChanges` | plays 4 chord changes, 8 bars each | chord latch behaviour; transition latency as felt, not as measured |
| T5 | `noisyRoom` | repeats T3 in the noisy room | whether the quality warning appears BEFORE the wrong answer does |

The five task names are the five values of `FieldStudyTask` — the enum and
this table are one taxonomy, not two.

## 3. What is measured

| Measure | How | Type |
|---|---|---|
| Task completion | observer note: completed unaided / completed with a hint / abandoned | qualitative |
| Correction usefulness | after T3/T4: "did the app tell you something you could act on?" 1–5 | qualitative |
| **False-confident event** | observer counts every moment the UI asserted a chord/direction confidently that the participant did not play | **counted, and P0/P1 by rule — see §5** |
| Perceived trust | end of session: "would you practise with this?" 1–5, plus one sentence | qualitative |
| Crash / jank | observer note + the Lab capture | counted |

**No accuracy number comes out of this study.** Accuracy is measured on the
corpus (`ml-train.yml` / `chord-train.yml`); a field session measures whether
the app is USABLE and whether it LIES. Reporting a field-session accuracy
would be a number with no holdout behind it.

## 4. Consent rule

Three separate, explicit acts. None of them implies another:

1. **Study participation** — `fieldStudyEnrolmentProvider`, default OFF.
   Leaving the study does not withdraw anything else.
2. **Raw audio** — a Lab capture leaving the recording screen needs its own
   `LabConsentGranted` ([ADR 0358](../adr/0358-consented-on-device-lab-capture-package.md)).
   **Without that separate consent, only the local aggregated report exists**
   and no audio is written anywhere.
3. **Aggregate telemetry** — the Kör 41 opt-in, default OFF, revocable
   ([ADR 0542](../adr/0542-opt-in-beta-telemetry-consent-and-recognition-rollout-flags.md)).

The field-session tag carries a closed cohort value, a closed task value and
the rotating pseudonymous id — nothing else. There is no participant name,
no e-mail, no handset model and no free-text field on the tag type, so a
capture header cannot become an identity record even by accident.

`FieldSessionTag.resolve` returns `null` unless the build flag, the
enrolment and a live pseudonym are ALL present: an untagged capture is a
valid capture, a half-formed tag would be a fabricated study record.

## 5. Findings registry (fail-closed, machine-readable)

Findings are recorded in the shape `docs/accessibility/known-exceptions.yaml`
established: one entry per finding, with `id`, `owner`, `severity`, `expiry`
and the evidence. Two rules make it fail-closed:

- **A false-confident event is forced to P0 or P1.** It may not be filed as
  P2 "cosmetic" — the whole chapter exists because the UI amplifies
  recognition error (SDD Ch14 §4.2).
- **An entry without an owner or past its expiry is a blocker**, the same way
  the accessibility registry's reader treats a lapsed exception.

```yaml
# docs/release/ch14-field-study-findings.yaml — created by the FIRST real
# session, not before. Shape:
# findings:
#   - id: FS-001
#     task: guidedPattern          # a FieldStudyTask value
#     severity: P1                 # P0/P1 forced for false_confident
#     kind: false_confident        # false_confident | crash | jank | usability
#     owner: <github handle>
#     expiry: 2026-10-15
#     evidence: <capture id or observer note reference>
```

The file is deliberately absent today. An empty registry that exists would
read as "the study ran and found nothing".

## 6. Results

**EMPTY — the study has not run.**

| Participant | Phone | Guitar | Room | T1 | T2 | T3 | T4 | T5 | False-confident count | Trust 1–5 |
|---|---|---|---|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — | — | — | — | — |

## 7. What the study cannot decide

- It cannot pass any SDD Ch14 §7 threshold — those need the corpus and the
  grouped holdout (`docs/release/ch14-production-gate.md` §1–2).
- It cannot substitute for the §7.1 corpus requirement, even with 8
  guitarists: a field session is not annotated ground truth.
- It cannot approve a rollout step. It produces findings; the rollout
  decision is a separate human row in the production gate checklist.

## 8. How to run it

1. Build the Lab APK (`lab-apk.yml`) from a branch where
   `recognitionFieldSessionTaggingEnabled` has been flipped to `true` — a
   deliberate source change, reviewed together with this document.
2. Each participant enrols in the app (Privacy Center), and separately
   decides on raw-audio capture.
3. Run T1–T5 in order. The observer keeps the notes; the app keeps only what
   the consents above allow.
4. File every finding into the registry of §5 the same day.
5. Update §6 and the `docs/release/ch14-production-gate.md` §4 field-study
   row with the real state.
