# E07-R06 review — SkillEstimate reducer és konfliktuskezelés

- **Kör:** E07-R06
- **Branch / reviewed HEAD:** `terra/e07-r06-skill-estimate-reducer` / `67fd0ed1`
- **Verdikt:** **CHANGES REQUESTED**
- **Scope-audit:** PASS — `python3 tools/scope-audit.py --repo /tmp/review-e07-r06 --brief docs/rounds/e07-r06-skill-estimate-reducer.md --base 903e7a7dd2bf66bdd256a30bf80b8b9c67e1a930` (`9 changed path(s), 1 generated/ignored`).
- **Gate:** PASS after formatting the disposable review probe; format, analyze, all three specified test files, architecture, secret and l10n checks passed in `/tmp/review-e07-r06`.

## Acceptance evidence

| Criterion | Evidence | Result |
|---|---|---|
| A1, A3 | canonical sort + outcome-ID dedup; target tests | PASS |
| A2 | explicit `singleEvidenceInfluenceCap`; policy test | PASS |
| A5 | deliberate `unknown.level = 0` mutation made `skill_estimate_test.dart` fail (`Expected: null; Actual: 0.0`), then restored | PASS |
| A6–A8 | target reducer/model tests and review inspection | PASS |

## Findings

### MAJOR-1 — Time-separated improvement is misclassified as conflict

- **Location:** `lib/features/practice_generator/application/service/skill_estimate_reducer.dart:91-99`, `_spread` at `:218-222`.
- **Evidence:** a disposable isolated-clone probe with sequential values `0.20, 0.25, 0.85, 0.90` at four distinct timestamps produced `state=SkillEstimateState.conflicted`, `uncertainty=0.5`, although the reducer also reports `trend=improving`.
- **Why this blocks:** the Ch8/R06 contract requires a bounded history trend *and* conflict/outlier handling. Treating all historic range as contradictory means a genuine sustained improvement is routed to the conservative conflict path (`assessment/repeat`, no aggressive progression), rather than being represented as a trend.
- **Requested correction:** detect disagreement among comparable observations (or otherwise account for time/trend before assigning `conflicted`); add a regression test proving monotonic time-separated improvement is not conflict.

### MAJOR-2 — Equal-time disagreement invents a directional trend from outcome-ID order

- **Location:** `lib/features/practice_generator/application/service/skill_estimate_reducer.dart:144-174`.
- **Evidence:** the same probe supplied equal-time contradictory observations `0.20, 0.25, 0.90`; output was `state=conflicted`, `trend=improving`. With equal timestamps, chronological order falls back to `sourceOutcomeId`, so a lexical identifier changes the apparent direction.
- **Why this blocks:** an ID is provenance, not temporal evidence. Reporting an improving/declining trend from it violates the deterministic evidence meaning and can create a false progression claim.
- **Requested correction:** tied timestamps must not create directional trend; add a regression test covering equal-time conflicting evidence and ID permutations.

## Review protocol notes

- Review ran in the isolated `/tmp/review-e07-r06` clone. The exploratory probe was deleted before scope audit; it is not part of the branch.
- The high-risk security review is recorded separately in `e07-r06-security.md`; it has no CRITICAL/BLOCKER/MAJOR and one non-blocking stale-evidence MINOR for a future consumer.
- A Terra corrective pass must commit the repair to this branch, after which this review and the gate must be rerun.
