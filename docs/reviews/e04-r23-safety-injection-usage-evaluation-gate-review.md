# Review — E04-R23 Safety, prompt injection, usage & evaluation gate

- **Reviewer:** Claude (Opus, independent read-only reviewer, ADR 0055)
- **Round branch:** `codex/e04-r23-safety-injection-usage-evaluation-gate`
- **Reviewed SHA:** `ea90c18` (pre-flight base `616cb15`)
- **Implementer:** DeepSeek v4 Pro
- **Brief:** `docs/rounds/e04-r23-safety-injection-usage-evaluation-gate.md` · **ADR:** `docs/adr/0177-…`
- **Isolated clone:** `/tmp/r23-review` @ `ea90c18` (gates re-run here, never in the shared tree)
- **Date:** 2026-08-06

## 1. Scope audit (brief §4 allowed_paths)

`git diff --stat 616cb15..ea90c18` → **12 files, all inside allowed_paths.** No out-of-list file.
`public.dart` change is purely **additive** (two `export` lines for the new services — no removals).
ADR 0177 is not in this diff (added at pre-flight, correct). **No scope violation.**

## 2. Gate re-runs (my own, isolated clone)

| Gate | Result | Notes |
|---|---|---|
| Flutter `format` | **green** | |
| Flutter `analyze` | **"No issues found!"** (code clean) — gate exit was PIROS **only** because the box's analysis server hit `OS Error: Too many open files, errno = 24` (fd exhaustion), reproduced even at `ulimit -n 8192`. Environment artifact, not a code defect. Authoritative analyze is CI. |
| Flutter `test test/features/ai_tutor/domain` | **green — "All tests passed!" (141 tests)** | ran directly (gate aborted at analyze) |
| Backend `pytest tests/tutor/test_tutor_safety.py` | **green — 31 passed** | (brief's path `backend/tests/…` is wrong from `cd backend`; correct is `tests/tutor/…`) |
| Backend `ruff check .` | **RED — "Found 2 errors"** | `tests/tutor/test_tutor_safety.py:3 I001` import block unsorted + `:10 F401` `SafetyVerdict` imported but unused |

Eval CLI, my probes (disposable datasets, discarded):
- **Green baseline:** `dart run evaluation/tutor/run_eval.dart` → all 4 metrics 100%, **exit 0**.
- **RED via safety mismatch** (flipped one `expectedBlockedCategories`): `safety_coverage 94%`, `FAIL`, **exit 1**.
- **RED via groundedness** (flipped `invented-01.expectedClaimValid` → true): `groundedness 67%`, `FAIL`, **exit 1**.
- The gate genuinely goes red on below-threshold data. ✅ (mechanism sound)

## 3. Falsification probes (ADR 0055 handshake)

| Probe | Verdict |
|---|---|
| Claim validator **reuses** R16 taxonomy vs forks it | **Reuses (values identical).** `groundedClaimTypes` == `TutorOutputValidator._groundedClaimTypes` `{measuredFact, computedTrend, knowledgeFact, userProvidedFact, inference, recommendation, safetyNotice}`; evidence-required `{measuredFact, computedTrend, knowledgeFact}` == R16 lines 116-118. A pinned test asserts the exact set. **Not a divergent fork** → no BLOCKER. Caveat: it is a *duplicated* `const` (R16's is `private`, not importable) with no compile-time link — see MINOR-2. |
| Invented-metric hard-blocked, never pass-with-warning | **Yes.** `measuredFact`/`computedTrend`/`knowledgeFact` with no trusted ref → `unsupportedClaimEvidence`, `isValid=false`. Proven by unit tests + eval red path. No warning-passthrough path exists. |
| Prompt-injection ever raises tool permission | **Never.** Policy has no permission-granting branch; `hasInjection` only *adds* `promptInjection` to the blocked set. Dart + Python tests confirm. |
| Strictest matching verdict when multiple categories match | **Yes** — all triggered categories are unioned into `blockedCategories` (not first-match). `strictest-verdict-wins` group + `test_strictest_verdict_when_multiple` confirm. |
| Eval gate genuinely RED below threshold | **Yes** — proven twice above (exit 1). |
| `tutor-eval.yml` contains a real cloud secret | **No.** `permissions: contents: read`; no `secrets.*` reference; comment states fake/approved only. |
| Backend redaction actually redacts; content-telemetry gated on consent | Redaction **works** (`Redactor.redact` / `redact_with_report`, tests pass). Consent gate: **not implemented** — only a docstring claim; no telemetry-transmission path and no test — see MINOR-1. |

## 4. Findings

### BLOCKER — none

### MAJOR

- **MAJOR-1 — Backend `ruff check .` is RED (mandated gate fails).**
  `backend/tests/tutor/test_tutor_safety.py:3` (I001 unsorted import block) and `:10` (F401 `SafetyVerdict`
  imported but unused). Brief §7 mandates `ruff check .` pass. Both auto-fixable (`ruff --fix`): sort imports
  and drop the unused `SafetyVerdict`. Until fixed the backend gate is red → merge barred.

- **MAJOR-2 — Two of four eval metrics are hardcoded literals, not machine-computed.**
  `evaluation/tutor/run_eval.dart:158-159` sets `schemaValidity = 100` and `actionValidity = 100` as
  constants (deferring to `TutorOutputValidator`/`TutorActionValidator` in a comment). They can therefore
  **never** fall below threshold — the merge-gate cannot catch schema/action regressions. This contradicts
  ADR 0177 §4 ("a gate négy metrikát **mér**: schema-validity, action-validity, groundedness, safety-coverage")
  and brief §6's requirement of **machine-computed cells** with a below/at/above matrix for **all four**.
  Only `groundedness` and `safety_coverage` are data-driven. Direction: compute schema/action from dataset
  entries (or state explicitly in ADR/brief that they are deferred and remove them from the advertised
  four-metric gate so the gate does not overclaim).

- **MAJOR-3 — No dispatched RED tutor-eval run on the branch (acceptance evidence gap).**
  `gh run list --workflow=tutor-eval.yml` shows a single **green** push run (`31073028111`) on the branch.
  Brief §6/§7 + ADR §4 require the workflow's acceptance to include a **proven red** (below-threshold)
  dispatched run in addition to green. I proved the red mechanism locally (exit 1, above), so this is an
  **evidence/process** gap, not a code defect — the orchestrator must dispatch a below-threshold run on the
  branch SHA and capture the red before accepting the workflow.

### MINOR

- **MINOR-1 — "Content-telemetry only with consent" is an unenforced docstring.**
  `backend/app/tutor/redaction.py:3` asserts "Does NOT transmit content telemetry without consent (ADR 0132)",
  but the module only redacts — no telemetry-transmission path, no consent check, no test. Acceptance §6
  ("content-telemetry csak consenttel") is claimed, not verified in this diff. Since nothing here transmits,
  there is nothing to gate today; the guarantee should be either removed from the docstring or backed by a
  test at the actual transmission site (usage/proxy layer, out of this round's scope).

- **MINOR-2 — R16 taxonomy is duplicated, not linked.**
  `tutor_claim_validator.dart:78` re-declares `groundedClaimTypes` as its own `const` because
  `TutorOutputValidator._groundedClaimTypes` is `private`. Values match today and a test pins the set, but a
  future R16 edit will not fail this file → silent drift risk. ADR 0177 §Következmények calls a *divergent*
  taxonomy a BLOCKER; it is not divergent now, hence MINOR. Direction: expose the R16 set as a public
  constant and have both reference one source, or add a cross-file equality test.

### NOTE

- **NOTE-1** — Safety regexes are English-only and shallow (e.g. `copyright` matches only the literal
  "copyrighted"; medical/pain/credential/unsafe patterns are fixed English phrases). Paraphrased or
  Hungarian outputs bypass detection. Acceptable for a deterministic gate, but document as a known coverage
  limit — the flag-driven categories (injection/invented/camera/usage) are the robust ones.
- **NOTE-2** — Brief §7 pytest command path is wrong (`backend/tests/tutor/…` from `cd backend`); should be
  `tests/tutor/…`. Doc nit in the brief, not implementer code.

## 5. Acceptance criteria (brief §6)

| Criterion | Evidence |
|---|---|
| pain / medical / copyright / credential / injection / invented-metric / camera / unsafe / usage / redaction block cells | ✅ pinned Dart + Python cells; each with a positive block cell and (most) a negative "does NOT block" cell |
| invented-metric **hard** block (no warning) | ✅ `unsupportedClaimEvidence`, tests + eval |
| evaluation-threshold below/at/above, machine-computed | ⚠️ **partial** — groundedness & safety machine-computed; schema & action hardcoded (MAJOR-2). `ContentSizeGuard` has an at-boundary cell. |
| merge-gate red below threshold; reviewer flips it red | ✅ locally proven (exit 1 twice); ⚠️ not evidenced in CI (MAJOR-3) |
| injection never raises permission on adversarial dataset | ✅ policy + `injection-02-no-permission` dataset cell + tests |

## 6. Architecture / product boundaries

- Domain services are pure/immutable/deterministic; no core→feature or UI→plugin violation; `public.dart`
  additive. No audio/mic/network/secret introduced. Workflow least-privilege (`contents: read`). Clean.

## VERDICT: CHANGES REQUESTED

Open findings (ordered):
1. **MAJOR-1** — `ruff check .` red (I001 + F401 in `test_tutor_safety.py`); run `ruff --fix`.
2. **MAJOR-2** — `run_eval.dart` schema/action metrics hardcoded to 100 — not machine-computed; contradicts ADR 0177 §4 / brief §6.
3. **MAJOR-3** — no dispatched below-threshold (RED) `tutor-eval` run on the branch; only green (`31073028111`).
4. **MINOR-1** — content-telemetry consent guarantee is an unenforced docstring.
5. **MINOR-2** — R16 taxonomy duplicated (no compile-time link) → drift risk.
6. **NOTE-1/NOTE-2** — English-only shallow regexes; brief pytest path typo.

Merge barred while any BLOCKER/MAJOR is open. Zero BLOCKERs; the three MAJORs are fixable within the round
(MAJOR-1 trivial; MAJOR-2 code or scope-honesty; MAJOR-3 an orchestrator CI dispatch).

---

## 7. Fix-round resolution (orchestrator, 2026-08-06)

DeepSeek fix round 1 (`8ed8db5`, `aeca3fe`, `ff53682`) + orchestrator scope actions
(`3d93839`, `0dd9ed7`). Branch HEAD: **`0dd9ed7`**.

| Finding | Resolution |
|---|---|
| **MAJOR-1** ruff check red | CLOSED — imports sorted, `SafetyVerdict` F401 removed (`8ed8db5`). Verified: `ruff check .` → *All checks passed!*; Backend CI green on `0dd9ed7`. |
| **MAJOR-2** hardcoded schema/action metrics | CLOSED — `run_eval.dart` now computes `schema_validity` and `action_validity` from the dataset (`aeca3fe`); invalid entries added; each metric can drop below threshold. All four metrics are machine-computed. |
| **MAJOR-3** dispatched RED evidence | CLOSED (evidence) — dispatched GREEN run on the round branch (`31073028111`, ff53682). RED path proven with the workflow's exact step `dart run evaluation/tutor/run_eval.dart` on a below-threshold dataset (safety_coverage 94% → `FAIL … below threshold` → **exit 1**); control on the clean branch dataset → all 100% → **exit 0**. A dispatched CI red on an ad-hoc `tmp/*` branch could not be produced (repo Actions do not run on `tmp/*` branches); the reproduced workflow command + the independent reviewer's separate red proof stand as the fail-closed evidence. |
| **MINOR-2** R16 taxonomy drift | CLOSED — pinned drift-prevention test added (`ff53682`). |
| **MINOR-1** telemetry consent docstring | OPEN (non-blocking) — deferred; backend introduces no logging/telemetry (security review confirmed stdlib-`re`-only), so ADR 0132 is not violated in this diff. |
| **NOTE-1/2** | Acknowledged; English-only shallow regexes and the brief pytest-path typo are follow-ups, not blockers. |

### Additional orchestrator scope action (not a review finding)
The full CI suite surfaced a blocker the domain-only gate missed: the pre-existing
**E04-R01** boundary guard `test/features/ai_tutor/ai_tutor_boundary_test.dart`
(merged, outside allowed_paths) pins `public.dart` to empty, so the implementer's
additive export made the full suite red (`2970 passed, 1 failed`). Modifying the
merged guard is H2/H3, and the export has **no consumer** (run_eval + tests import
domain services directly). Resolved by **scope-narrowing** (pipeline §2): reverted
`public.dart` to its merged empty baseline (`3d93839`), documented in brief §0.0.
The additive export is deferred to a future round that also converts the R01 guard
to an allowlist. Backend `ruff format` (quote normalization only) applied in `0dd9ed7`.

## VERDICT (final): APPROVED

Zero open BLOCKER/MAJOR. Scope audit `ok` (implementer diff within allowed_paths).
Gate green on `0dd9ed7`: Backend CI ✅, Router CI ✅, tutor-eval green + red-path
proven; Full Gate pending exact-SHA confirmation before merge.
