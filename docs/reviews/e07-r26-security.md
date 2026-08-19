# E07-R26 — Security / Privacy / Prompt-Injection Review (dedicated, mandatory — brief `risk = "high"`)

- **Brief:** `docs/rounds/e07-r26-outcome-ingestion-and-revision.md` (incl. §0.0 pre-flight revision)
- **Diff reviewed:** `git diff 26cdad92..d3c337e5` — 10 files, +851/−0
- **Reviewer:** Claude (security-reviewer subagent) · Date: 2026-08-19 · Scope: **READ-ONLY**, no production edits (AGENTS.md §15.1)

## Verdict: **PASS — merge permitted (subject to the unchanged green gate).**

**CRITICAL: 0 · BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 5**

No secret leak, no consent bypass, no path traversal / RCE, no new network /
permission / storage / imported-file surface, and no AGENTS.md §5
non-negotiable is touched. The round is a **pure, caller-fed
application/presentation layer**: `practiceGeneratorEnabled` stays `false`
(`lib/app/config/feature_flags.dart:22,78`), grep finds **zero production
consumers** of the new symbols outside the round's own tests, and the four
new lib files contain **no sink** (no serialization/log/network/file). The
privacy- and integrity-relevant properties the brief names hold
**structurally** (by construction / by data shape), not by a fragile
allow-list.

## What was checked (five questions, each with evidence)

1. **Prompt injection / untrusted free text** — N/A (no AI-provider/tool/KB
   call anywhere in the diff). Untrusted-text surfaces (`PlanChange.target`,
   `evidenceRefs`, `before`/`after`, `reason.code`) are validated
   (non-empty `target`, strict regex + cross-check against the real
   plan, `PlanChangeReason` enum, NaN-closed `confidence`) and rendered via
   markup-inert Flutter `Text()` on-device to the owning learner.
2. **Secrets / PII / raw media** — none referenced or constructed anywhere
   in the diff.
3. **Data-boundary discipline (§5/§6)** — `domain/**` untouched (0 files);
   the four new files only import domain types (correct
   application→domain direction); `public.dart` additive-only, no new
   `PracticeOutcome` ambiguity; no top-level mutable global.
4. **Dedup / determinism / resource-exhaustion** — `outcome.id.value` is
   charset-locked; `processedOutcomeIds` is read-only in this code (never
   mutated — caller-owned); time enters only via an injected
   `DateTime Function() clock`, no hidden `DateTime.now()`/RNG.
5. **`dart:io`/network/file APIs** — none in any of the four new files.

## Findings — all NOTE (forward-looking; no reproducible issue this round)

- **NOTE-1** — `PlanChange.before`/`after` are untyped `Map<String,Object?>`;
  safe today (no sink, on-device render only), but a future
  persistence/export/AI-tutor round must treat them as caller-untrusted and
  route any off-device path through a redactor.
- **NOTE-2** — the review screen shows `reason.code` and raw map keys
  un-localized (i18n/UX gap, not a security boundary — every static label
  correctly uses `AppLocalizations`). Handed to the correctness reviewer
  (tracked there as F3).
- **NOTE-3** — `processedOutcomeIds` has no cap in the contract; this
  code only reads it, so no growth is introduced here, but a future
  accumulating persistence layer should scope/prune it per active revision.
- **NOTE-4** — the two same-named `PracticeOutcome` types (R23
  execution-side vs. repository-local) still coexist; this round's
  additive exports don't reintroduce ambiguity (`hide` intact). Collapse
  when the serializer record is eventually replaced.
- **NOTE-5** — `StateError`/`ArgumentError.value` messages interpolate the
  caller-fed `target` string; inert today (no log/telemetry sink), but a
  future error/telemetry wiring round should redact before logging.

## Positive integrity properties (recorded, not findings)

- Immutable-past enforcement rejects any candidate that drops or mutates a
  **completed** day/block (`StateError`).
- Confirmation-before-activation: structural or `>= 2`-count changes yield
  `revision == null` until explicit `accepted` confirmation — no silent
  major-change activation.
- All returned collections (`reviewItems`, `changes`, `before`/`after`) are
  `List/Map.unmodifiable`.

## Closing

Nothing in this diff crosses an AGENTS.md §5 non-negotiable, leaks a
secret/PII/raw-media, or opens a network/permission/storage surface.
**Merge permitted on security grounds**, subject to the unchanged green
gate. The five NOTEs are hand-offs to future wiring rounds; none blocks
this merge.
