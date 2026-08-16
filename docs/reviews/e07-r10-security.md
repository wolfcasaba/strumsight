# E07-R10 — Security / Privacy Review

**Round:** E07-R10 — AdaptivePracticePlan, day, block, revision domain (Epic 7 "AI Practice Generator")
**Branch:** `terra/e07-r10-adaptive-practice-plan-domain` @ `162db400`
**Base:** `de060337` · **Diff:** `git diff de060337..HEAD -- lib/ test/`
**Reviewer:** Claude (security-reviewer agent, independent of the functional review) · **Date:** 2026-08-16
**Trigger:** brief `risk = "high"` → security review mandatory before merge (AGENTS.md §15.1)

## Verdict: **PASS** — merge not blocked on security grounds

| Severity | Count |
|---|---|
| CRITICAL | 0 |
| BLOCKER | 0 |
| MAJOR | 0 |
| MINOR | 0 |
| NOTE (forward-looking) | 4 |

This is a pure in-memory, immutable domain-model round. It is **unwired** (grep across `lib/` + `test/` finds zero consumers of the new types outside the round's own files) and has **no sink**: no `dart:io` / `dio` / `http` / `SecureStore` / `KeyValueStore` / `SharedPreferences` / `MethodChannel` / `Platform.` / `print` / `log` / `debugPrint` / `dart:convert` import in any of the 5 new files. The privacy guarantees are therefore **structural** (field shape), and this review proved that shape rather than hunting a runtime guard. All four residual items are forward-looking NOTEs for the future persistence (Kör 19) / AI-tutor / export rounds.

---

## The six flagged concerns — each resolved with evidence

### 1. `PracticeGoal.userNote` leaking into `PracticePlanSummary` — **CLEAN / EXCLUDED**

`AdaptivePracticePlan.toSummary()` (`adaptive_practice_plan.dart:79-88`) builds the summary from **id, title, status, startDate, endDate, activeRevisionId, `dayCount = days.length`, `goalCount = goals.length`** — it never touches `goals` element content, so no `userNote` (or any other `PracticeGoal` free-text: `songReference`, `normalizedTargetId`, `metricTarget`) can enter. `PracticePlanSummary.toJson()` (`:197-206`) emits exactly those 8 fields.

- **Every construction site verified:** `grep "PracticePlanSummary("` returns exactly two hits — the `const` constructor (`:177`) and the single `toSummary()` call (`:79`). No alternate builder can inject `userNote`.
- **Negative guard is real, not theater:** the fixture seeds `userNote: 'private note'` (`plan_fixtures.dart:73`) and the test asserts `original.toSummary().toJson().toString()` `isNot(contains('private note'))` (`adaptive_practice_plan_test.dart:94-97`). Unlike a forbidden-KEY list over a fixed key set, this canary is genuinely load-bearing because the summary omits the **whole goal**, so the property is structural.
- Satisfies brief §5.6 and ADR 0260 §4 (sensitive learner free-text must not reach the UI/export-facing DTO; only id + category may).
- The plan **`title`** is present in the summary — this is by design (a plan's display label is exactly what a summary card shows) and is not the ADR 0260 §4 "learner free-text note." No finding. See NOTE-1 for the one residual seam.

### 2. `PlanChange.before` / `after` (`Map<String, Object?>`) carrying unsanitised sensitive data — **no reproducible issue; forward NOTE-2**

- `PlanChange` / `PlanChangeSet` have **no `fromJson`** (construct + serialize only) and **zero active callers** (grep).
- The only construction (`plan_change_set_test.dart:7-17`) uses a **safe scalar field-diff**: `before: {'estimatedElapsedMicros': 300000000}`, `after: {'estimatedElapsedMicros': 600000000}`.
- The file header ("Structured, machine-readable differences… free-text explanations are excluded", `plan_change_set.dart:1,36`) and brief §5.5 both model the structured-diff intent. There is no careless example anywhere that dumps a `PracticeGoal` or `userNote` into `before`/`after`. The task's specific question — is there a code/doc pattern that *encourages* the leak — answers **no**.
- Residual: the map is permissive by nature (a diff bag can't be statically constrained to "safe scalars"). → NOTE-2 for the future producer/sink round.

### 3. `fromJson` fail-closed behaviour — **VERIFIED fail-closed, no silent fallback**

Every decode helper **throws** on malformed input — no `?? default` anywhere:
- `_text` (`adaptive_practice_plan.dart:315`), `_integer` (`:325`), `_number` (`:332`), `_object` (`:346`), `_list` (`:353`), `_textList` (`:360`), `_dateTime` (`:339`, `DateTime.parse` throws `FormatException` on bad input), `_dateFromJson` (`:215`) — all throw `ArgumentError`/`FormatException`. Same helper set duplicated and equally strict in `practice_block.dart` and `practice_day.dart`.
- **Unknown enum code → throw:** `PlanChangeType.fromCode` (`plan_change_set.dart:17-33`), `PlanChangeReason.fromCode` (`:49-54`), `PracticeItemStatus.fromCode` (`practice_block.dart:27-39`) all reject null/empty and unknown codes.
- **Ids → throw:** every id `fromJson` routes through `_decodeJsonId` (non-String → throw) + `_validateId` (blank or charset-violating → throw, `planner_ids.dart:158-189`).
- **NaN closed by construction:** `_number` admits `NaN`/`Infinity`, but the consuming value-types reject them — `MetricTarget` ctor throws on `!threshold.isFinite` and `minimumConfidence` outside finite `0..1` (`practice_goal.dart:104-115`), and `PlanChange.confidence` throws on `!isFinite`/out-of-range (`plan_change_set.dart:74-76`). So a `NaN` confidence/threshold from JSON fails closed (satisfies AGENTS.md §5 "weak confidence must not surface as certain").
- **Depth/bomb note:** these files never call `jsonDecode` (no `dart:convert` import) — they operate on already-decoded `Map`s, so untrusted-bytes→Map parsing (deep nesting / JSON bomb) is not in this code; it belongs to the future caller that decodes bytes.

### 4. `ExerciseCandidateResolver` / `exerciseId` injection surface — **domain clean; forward NOTE-4**

`PracticeBlock.fromJson` extracts `exerciseId` via `_text` (non-empty, trimmed) and passes it verbatim to the caller-supplied `resolveCandidate(exerciseId)` (`practice_block.dart:162,169`). The domain does nothing dangerous with it — no path I/O, no interpolation. The only resolver in the tree (test fixture) does an exact-match allowlist check (`plan_fixtures.dart:4-6`). **Asymmetry worth flagging:** id types are charset-locked to `^[A-Za-z0-9._:-]+$`, but `exerciseId` is only non-empty-validated, so it could contain `../` etc. → NOTE-4: the *future* resolver implementation must treat `exerciseId` as untrusted (map/allowlist lookup, never a filesystem path).

### 5. Prompt injection / control-channel cleanliness (AGENTS.md §5.1) — **N/A, confirmed clean**

No AI provider, no prompt construction, no tool calling, no knowledge-base retrieval, no external non-versioned content. The domain models never interpret any string as an instruction — every string (`title`, `userNote`, codes, ids, `reasonCodes`, `evidenceRefs`) is inert data copied into fields or maps. The brief/ADRs are committed, versioned content. Nothing here executes or evaluates external/AI-generated content.

### 6. Raw audio / mic / camera / secret boundaries (AGENTS.md §5) — **N/A, confirmed clean**

No audio/mic/camera/network/storage/auth code anywhere in the round. No dangerous imports (verified grep). No logging sink, so `AppFailure`/`ArgumentError` messages (which echo field names, ids, status codes, revision numbers — never secrets or valid `userNote`) cannot reach a log. The only secret-shaped literal is the fake canary `'private note'` — not a real secret; the machine `check_secrets` gate is green (per functional review §Gate).

---

## Forward-looking NOTEs (none block merge — all for future rounds)

- **NOTE-1 — dual serialization path.** `AdaptivePracticePlan.toJson()` (`:90-103`, via `_goalToJson` `:236`) **does carry `userNote`** in the canonical document. Correct for on-device persistence, but nothing prevents a future export / AI-tutor / analytics consumer from serializing the full plan off-device instead of `toSummary()`. The future sink round must route any off-device/AI path through the summary or a redactor (ADR 0260 §1: what goes into export goes off the device).
- **NOTE-2 — `before`/`after` opaque maps** have no content validation; the future producer must only place structured scalar diffs (never a raw goal/`userNote`), ideally with a redaction guard at the serialization/AI-export sink.
- **NOTE-3 — no length caps** on `fromJson` collections (`goals`, `days`, `blocks`, `skillIds`, `evidenceRefs`, `policyVersions`). Harmless while the JSON is app-local; the future untrusted-import / plan-sharing round should add caps (DoS / zip-bomb analog).
- **NOTE-4 — `exerciseId` charset asymmetry** (see concern 4): future resolver must treat it as untrusted.

---

## What was reviewed (empty-findings evidence)

5 new domain files + `public.dart` barrel + 3 tests + fixture (full read); `practice_goal.dart` `MetricTarget`/`PracticeGoal` constructors; `planner_ids.dart` id validators; ADR 0260 §1-§6 and ADR 0256; brief §0.0/§3/§4/§5.1-§5.6/§6.1/§9; the functional review (`docs/reviews/e07-r10-review.md`). Greps: all `PracticePlanSummary(` construction sites; sink/dangerous-import scan on the 5 files; consumer scan for all 12 new types (0 external); `jsonEncode`/`jsonDecode`/`dart:convert`; `TODO`/`FIXME`/`unsafe`. No CRITICAL/BLOCKER/MAJOR/MINOR reproduced.

## Merge-döntés

Biztonsági szempontból a merge **nincs blokkolva** — CRITICAL/BLOCKER lelet nulla (AGENTS.md §15.1: "CRITICAL vagy BLOCKER lelet → merge tilos" — nem áll fenn). A négy NOTE nem blokkoló, jövőbeli körökhöz (Kör 19 persistence, AI-tutor/export) van címezve.
