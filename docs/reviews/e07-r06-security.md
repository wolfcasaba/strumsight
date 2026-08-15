# E07-R06 security review — SkillEstimate reducer

- **Reviewed HEAD:** `67fd0ed1` (`terra/e07-r06-skill-estimate-reducer`)
- **Risk:** high
- **Verdict:** **PASS** — no CRITICAL, BLOCKER or MAJOR security finding.

## Measured checks

- The new domain/application path has no network, storage, logging, prompt, raw-audio, raw-video, `Random`, or `DateTime.now()` dependency.
- `SkillEstimate.unknown` uses `level = null`, not a `0.0` performance assertion; the primary constructor rejects `unknown`.
- `DiscomfortReport` is counted separately and cannot change the performance level.
- Outcome IDs are the existing validated provenance IDs; `EvidenceSummary` carries counts only and no free text.
- The reducer has no production consumer yet, so this round does not create a presentation or export sink.

## MINOR-1 — future consumer must honour stale state

Many stale observations can accumulate enough reduced weight to make `uncertainty` numerically small even though `state=stale` and the summary explicitly report no current evidence. There is no current consumer, so this is non-blocking, but the future wiring/UI round must gate confidence presentation on `SkillEstimateState.stale` (and test it) rather than rendering `1 - uncertainty` alone.

## Follow-up notes

- Validate `skillId` more narrowly if it ever becomes external or serialised.
- Avoid passing a whole evidence iterable as an error value if a later model supplies data-rich `toString` output.
