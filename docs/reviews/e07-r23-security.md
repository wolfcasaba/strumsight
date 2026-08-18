# E07-R23 — Security / Privacy / Prompt-Injection Review (dedicated, mandatory — brief `risk = "high"`)

- **Brief:** `docs/rounds/e07-r23-plan-compiler-and-execution.md` (incl. §0.0 pre-flight revision)
- **ADR:** `docs/adr/0268-technical-failure-is-not-skill-failure.md`
- **Diff reviewed:** `git diff 4eb098d8 4bb62a62` — 8 files, +1026/−1, in the isolated clone `/tmp/review-e07-r23`, branch `codex/e07-r23-plan-compiler-and-execution`, HEAD `4bb62a62` (see provenance note below)
- **Reviewer:** Claude (security-reviewer subagent) · Date: 2026-08-18 · Scope: **READ-ONLY**, no production edits (AGENTS.md §15.1)

## Provenance reconciliation (done before reviewing — the clone was stale)

The clone as handed to me was at `9c2aa9bb` (the **docs-only pre-flight** commit — only the round brief changed) and `git cat-file -t 4bb62a62` **failed** in it. I verified `4bb62a62` ("feat(practice-generator): compile executable plan blocks") exists in the local main repo's object store on `origin/codex/e07-r23-plan-compiler-and-execution`, with merge-base `4eb098d8` and exactly the 8 files / 1026 insertions the task described; no GitHub PR exists yet (`gh pr list --head … = []`). I recovered the real code by `git -C /tmp/review-e07-r23 fetch origin && git checkout 4bb62a62` **inside the isolated clone** (fetch reads from, never modifies, the source), then re-verified the diff file-set. The main working tree was not touched. Reviewing the clone as-handed would have been a false clearance of the entire implementation.

## Verdict: **PASS — merge permitted (subject to the unchanged green gate).**

**CRITICAL: 0 · BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 5**

No secret leak, no consent bypass, no path traversal/RCE, no new network/permission/storage/imported-file surface, and no AGENTS.md §5 non-negotiable is touched. The round is an **unwired** domain/application/data layer (grep: 0 consumers of the new symbols outside the round's own tests), and the four privacy- and integrity-relevant properties the brief and ADR 0268 name are satisfied **structurally** (by construction), not by a fragile allow-list. All five findings are forward NOTEs for later wiring rounds, matching the established E07-R10 bar for a sink-free round.

---

## Findings (all NOTE — forward-looking, no reproducible issue this round)

### NOTE-1 — Free-form `String` surfaces (`metricEvidence` keys, `failureCode`, `exerciseSnapshotReference`) are inert now but must stay machine-derived at the future sink

**Where:** `practice_outcome_adapter.dart:205-207` (`_metricEvidence` validates keys only for non-emptiness), `:98-99` (`TechnicalFailurePracticeOutcome.failureCode`), `plan_compiler.dart:93-97` (`sourceRevision`/`exerciseSnapshotReference`).

**Why not higher:** these are the only free-form strings in the new types; all are validated non-empty (values additionally forced finite & 0..1), and there is **no sink** in the round (no serialization/log/network — proven below), so nothing can leak this round. Crucially, `failureCode` is **structurally dropped** by normalization (see the clean table), so it never reaches the evidence type. Same class as the E07-R10 `exerciseId` / E07-R18 `evidenceRefs` forward-NOTE.

**Rule / direction:** ADR 0260 §1 (nothing sensitive off-device without redaction). The future persistence/analytics/AI-tutor round must treat these as caller-untrusted and keep them machine-derived (metric IDs, catalog codes) — never let a `userNote`-style value be interpolated into a metric key or failure code, and route any off-device path through a redactor.

### NOTE-2 — Two same-named `PracticeOutcome` types now coexist in the feature (maintainer-confusion, not a defect)

**Where:** `public.dart:18` (exports the **new** execution `PracticeOutcome` from `data/adapter/practice_outcome_adapter.dart`) + `:24` (`export '…/practice_plan_serializer.dart' hide PracticeOutcome;`).

**Verified clean:** `PracticeOutcome` is the **only** overlapping top-level name between the serializer and the adapter (diffed both files' `class/enum` declaration lists), so `hide` is sufficient — no second ambiguous export slips through. Every bare-`PracticeOutcome` reference lives in `data/local/` (serializer + `local_practice_plan_repository.dart` + their two tests) — **same feature, direct file imports**, never via the barrel; and no cross-feature / `lib/app` consumer imports the barrel expecting the old type. So the hide-and-direct-import swap has **zero victim** and cannot silently hand a caller the wrong `PracticeOutcome`.

**Direction:** when the serializer's record is eventually replaced by a real domain type (its own doc-comment anticipates this), delete the `hide` and the duplicate name to remove the latent confusion.

### NOTE-3 — `_validateLaunch` skips the tempo cross-check when the prescription has no tempo

**Where:** `plan_execution_coordinator.dart:181-182` — `(step.config.tempoBpm != null && sessionConfig.effectiveTempo.bpm != step.config.tempoBpm)`.

**Scenario:** a compiled step whose `tempoBpm == null` (a tempo-less exercise) accepts **any** engine `effectiveTempo` without validation. This is defensible (no prescribed tempo ⇒ nothing to deviate from, so it is not a "körülbelüli konfig" violation of §5.4 / ADR 0268 §4), and the enforceable engine-config surface (`definitionId`, `loopCount`, `sessionTimeout == (active+rest)*loopCount`, tempo-when-set) **is** checked and throws on mismatch. Recorded so the wiring round confirms a null prescribed tempo is always intentional and never a dropped constraint.

### NOTE-4 — Dedup/idempotence residuals (benign under the current guards)

**Where:** `plan_execution_coordinator.dart:134-157` (`recordOutcome`), `:191-205` (`_validateOutcomeContext`), `:26-55` (`BlockExecutionId`).

Two observations, neither reproducible as an attack: (a) `recordOutcome` does not assert that `blockExecutionId` was issued by **this** coordinator instance (`_issuedExecutionIds` is checked only in `start()`); (b) the outcome's own `OutcomeId` (`context.id`) is neither part of the dedup key nor checked across replays — a replay may carry a different `OutcomeId` and even a different input variant and is still absorbed (exactly what test A4 exercises). Both are safe **because** `BlockExecutionId._` is library-private (unforgeable), `_validateOutcomeContext` forces the context's plan/rev/day/block to equal the id's location, and ingestion is **first-write-wins** (`:140-141`), so no replay can overwrite another block's outcome. Direction for the persistence-wiring round: if outcomes become durably persisted, consider asserting issuance and/or keying durable dedup on the source `OutcomeId` (ADR 0260 §3's layer) in addition to the in-process `blockExecutionId`.

### NOTE-5 — Adaptation is correctly deferred; the future round must honor the disposition flags

**Where:** `plan_execution_coordinator.dart:144-146` (`contributesSkillEvidence`), `:153` (`requestsRegression: false` always).

This round only normalizes; `requestsRegression` is hardcoded `false` and evidence is gated to `completionState == completed && metricEvidence.isNotEmpty`. The later bounded-adaptation round must consume `PlanOutcomeIngestion` and preserve ADR 0268 §1/§2: a `failedTechnical` or `partial` outcome must not lower the estimate or trigger a regression. Forward pointer, not a gap.

---

## What was verified clean (positive evidence — the empty half of the report)

| Area | Evidence |
|---|---|
| **Concern #1 — free-text / `userNote` leak into evidence** | **Closed structurally.** The normalized `PracticeOutcome` (`practice_outcome_adapter.dart:114-143`) carries only charset-locked ids, a fixed `source` (`'practiceEngine'`), timestamps, a `Duration`, a `PracticeCompletionState` enum, `Map<String,double>` metrics, and `List<PracticeUserFeedback>` (an **enum** — doc `:23` "raw user text is intentionally out of scope"). It has **no** free-text user field. `adapt()` (`:150-173`) reads only `finishReason` off the source `PracticeSessionResult` (`:177`, `:186-202`); that source object carries free-text surfaces (`coachingSummary: List<String>`, `attempts`, `VisionSessionResult? vision`) and **none propagate** — the outcome has no `sessionResult` field. `TechnicalFailurePracticeOutcome.failureCode` is likewise **not** copied in. This is the E07-R10 "summary omits the whole goal" seam applied at the adapter. |
| **Concern #3 — fail-closed everywhere** | `PlanCompiler.compile` (`plan_compiler.dart:124-183`) returns an explicit `UnavailablePlanStep` on every reject path (unsupported source / wrong exercise / **stale revision** A2 / **missing capability** A3) and only reaches `CompiledPlanStep` after all pass — no silent success, no `?? default`. `_completeCapabilities` (`:186-200`) throws if the availability map omits any `ExerciseCapability` (incomplete map ⇒ reject); `CapabilitySupport` is `{supported, unsupported}` and anything `!= supported` blocks launch. Both `switch`es in the adapter (`:175-202`) are exhaustive over the sealed input / enum with **no `default`** (new variant ⇒ compile error). `start()` throws on a duplicate execution id (`:124-126`); `_validateLaunch`/`_validateOutcomeContext` throw on any mismatch. |
| **Concern #4 — idempotence / dedup key manipulation** | Dedup key = `BlockExecutionId.value` = `[planId,revisionId,dayId,blockId,token].join('/')` (`:41-47`). All id value-types **including `OutcomeId`** are charset-locked to `^[A-Za-z0-9._:-]+$` (`planner_ids.dart:158`, `:132-134`) ⇒ no `/` in the first four fields; the only free-form component (`token`) is **last**, so it cannot spill into another field's identity — no cross-field collision. `BlockExecutionId._` is **library-private** ⇒ a caller cannot forge one. First-write-wins + context-location validation ⇒ no replay can overwrite another block's outcome (test A4 confirms). |
| **Concern #2 — barrel name collision** | Resolved cleanly; only overlapping name is `PracticeOutcome`, old type stays same-feature direct-import (NOTE-2). |
| **Concern #5 — network / storage / secrets / imported files** | **None added.** `grep -nE "print|debugPrint|Logger|dart:io|dio|http|File\(|jsonEncode|jsonDecode|toJson|fromJson|SecureStorage|SharedPreferences|analytics|Sentry|Repository"` over the 3 new `lib/` files → only a doc-comment match ("…or repository" on `:146`), zero real sinks. No `toString` override in any of the 3 files (no field-dump). `pubspec.yaml`/`.lock` **not** in the diff (zero new dependencies/assets). No platform permission, no `dart:io`/mic/camera reference. The offline base experience is untouched. |
| **Prompt injection (ADR 0131–0136)** | **N/A, verified.** The diff touches no AI provider, no tool-calling allowlist, no knowledge-base retrieval, no prompt template, and no importer/parser of external song content (MusicXML/MIDI/GP/zip). External content cannot influence policy, permissions or the outcome. |
| **Cross-feature import legality** | `practice_outcome_adapter.dart:4` and `plan_execution_coordinator.dart:4` import `package:strumsight/features/practice/public.dart` — the **allowed public-barrel** path (brief §4), not another feature's internals. Only `PracticeSessionResult`, `PracticeSessionConfig`, `PracticeFinishReason` are consumed. |
| **Error-message hygiene (§5.3)** | The `ArgumentError.value(...)` sites embed only config/id/enum/double values and generic messages ("must exactly match…", "must not be empty or blank"); no audio, token, secret or user free-text exists in any of these types to leak, and errors are thrown (not logged). |
| **Secrets (semantic)** | No key/token/credential-shaped literal in the 3 lib files or the tests/fixture; the only "token" occurrences are the `String Function() createExecutionToken` factory name and the synthetic `'execution-token-N'` test values. Fixtures use synthetic charset-safe ids (`plan.execution.1`, `practice.strum.v1`, `outcome.execution.1`). |
| **Scope** | Diff = exactly the brief's `allowed_paths` (8 files). `lib/app/**`, `docs/adr/**`, `docs/sdd/**`, `tools/**`, `.github/**`, the Practice Engine, and `feature_flags.dart` are untouched. No flag flipped to `true`. |
| **Tests are operable red-triggers** | A1 (`plan_execution_coordinator_test.dart:17-44`) asserts a technical failure yields `failedTechnical` + `contributesSkillEvidence=false` + `requestsRegression=false`; A6 (`:79-109`) asserts `interrupted → partial`, no contribution even with metrics; A2/A3 (`plan_compiler_test.dart:10-38`) assert `UnavailablePlanStep` with the correct reason; A4 (`:46-77`) proves first-write-wins. The §6.1 mandatory real-violation test (§10) drove A1 red by forcing `failedTechnical`'s flag true, then restored it. |

## Reproduction

No temporary probe was needed to reach a finding: every property above is proven by static tracing plus targeted `grep`/`git` over the checked-out `4bb62a62` in the isolated clone (commands quoted inline). The clone's working tree is clean apart from this review being delivered inline; nothing in `/home/ubuntu/music-theory` was modified and no git remote operation was run against it.

## Merge recommendation

**Merge permitted** once the unchanged ADR 0052 green gate passes in CI (`tools/round-gate.sh` over the two gate tests + the full CI suite). The five NOTEs are non-blocking and belong in the next wiring round's brief as explicit inputs — chiefly NOTE-1 (keep `metricEvidence` keys / `failureCode` machine-derived and route off-device paths through a redactor) and NOTE-5 (the adaptation round must honor `contributesSkillEvidence`/`requestsRegression`). None must be inherited silently.

## Addendum (orchestrátor, 2026-08-18) — F1 javító kör a security review UTÁN

A `docs/reviews/e07-r23-review.md` (correctness review) egy F1 MAJORt talált
(A5 hiba-ág tesztelve nincs) a jelen security review lezárása UTÁN — időben a
két review párhuzamosan futott, és az F1 nem biztonsági/adatvédelmi jellegű
(teszt-lefedettségi hiány, nem viselkedési vagy adatszivárgási hiba), ezért a
fenti biztonsági verdiktet NEM érinti. Az F1-et a `codex` motor javította
(`a6e0436f`), a correctness review saját kézzel újramérte. Ez a security
review a `4bb62a62`-n futott, változatlanul érvényes: az `a6e0436f` javítás
kizárólag egy tesztfájlt és egy tesztfixture-t bővített (ld. a correctness
review diffjét), production-kódot nem érintett — új biztonsági felület nem
keletkezett.

### Verdict summary (< 150 words)

**PASS — no CRITICAL/BLOCKER/MAJOR/MINOR; 5 forward NOTEs.** First the reviewer had to fix a stale clone: it sat on the docs-only pre-flight commit and `4bb62a62` was absent, so the real implementation was fetched into the isolated clone and the 8-file/1026-line diff was reconciled before reviewing. The privacy property holds **structurally**: normalization reads only `finishReason` and drops the whole `PracticeSessionResult` (incl. `coachingSummary`/`vision`) and `failureCode`; user feedback is an enum, not free text. The `PracticeOutcome` barrel collision is resolved cleanly (`hide` on the only overlapping name; old type stays same-feature direct-import; no external victim). Every compiler/coordinator reject path is fail-closed; the dedup key is `/`-safe (charset-locked ids + unforgeable private ctor + first-write-wins). No network, storage, secret, permission, imported-file, or prompt surface added. NOTEs are all for the future wiring round.
