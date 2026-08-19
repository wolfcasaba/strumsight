# E07-R28 — Security / Privacy / Prompt-Injection Review (dedicated, mandatory — brief `risk = "high"`)

- **Brief:** `docs/rounds/e07-r28-planner-assist-gateway.md` (incl. §0.0 pre-flight revision)
- **Feature:** `lib/features/practice_generator/` — optional, non-authoritative **PlannerAssist** gateway (a language model proposes; the deterministic planner disposes)
- **Bound decisions:** ADR 0270 (allowlisted model output + untrusted learner text), building on ADR 0255 §2, 0262 §1, 0263
- **Diff reviewed:** `git diff e95bd937..a1a6da38` — **10 files, +1099 / −3**
- **Reviewer:** Claude (security-reviewer subagent) · Date: 2026-08-19 · Scope: **READ-ONLY**, no production edits (AGENTS.md §15.1)

## Verdict: **PASS — merge permitted (subject to the unchanged green gate).**

**CRITICAL: 0 · BLOCKER: 0 · MAJOR: 0 · MINOR: 1 · NOTE: 5**

No secret leak, no consent bypass, no path traversal / RCE, no new hardcoded
network endpoint, no new permission, and no AGENTS.md §5 non-negotiable is
touched. The round adds an **unwired** boundary: `plannerAssistEnabled` stays
`false` (`lib/app/config/feature_flags.dart:23,79`), and grep finds **zero
production consumers** of any new `PlannerAssist*` / `TutorPlan*` symbol outside
the round's own files + barrel. The five security-relevant properties the brief
names (A1 no activation, A2 exact allowlist, A6 untrusted-text isolation,
raw-output containment, `ai_tutor` non-import) all hold **structurally / by
construction**, not by a fragile allow-list. The single MINOR and the NOTEs are
defense-in-depth hardening and forward-looking constraints for the future
transport/UI wiring round; none is reachable in production today.

## Provenance / head reconciliation (read this first)

The isolated clone `git clone --branch codex/e07-r28-planner-assist-gateway
/home/ubuntu/music-theory /tmp/security-review-e07-r28` landed at
`ed197b04` — the **pre-flight commit only** (one commit above base
`e95bd937`); the implementation commit `a1a6da38 feat(planner): add validated
assist gateway` was **not on the shared branch ref** (`refs/heads` and
`refs/remotes/origin` both pinned at `ed197b04`), and `a1a6da38` did not exist
in the local main object store. The real impl commit lived in the standalone
implementer clone `/home/ubuntu/ss-codex-e07-r28` (own object store, HEAD
`a1a6da38`). Recovery (read-only on the source): `git fetch
/home/ubuntu/ss-codex-e07-r28 codex/e07-r28-planner-assist-gateway` then
`git checkout a1a6da38`. After checkout the diff is exactly the **10 files /
+1099** the task described. **This review therefore covers `a1a6da38`**; the
orchestrator must confirm the merged head is `a1a6da38` (or a content-identical
rebase), because the shared branch ref did not yet carry the reviewed code at
review time.

## What was checked (each with evidence)

### 1. Prompt-injection isolation of the learner note (A6 / ADR 0270 §3) — HOLDS (structural)
- `PlannerAssistPrompt` (`application/port/planner_assist_gateway.dart:85-117`)
  keeps a fixed `static const _instructions` (`:93-96`) and a **separate**
  `untrustedLearnerNote` field (`:101`). `toWire()` (`:105-116`) emits
  `instructions` and `untrustedLearnerNote` as **distinct map keys** via
  `Map.unmodifiable` — no string concatenation, no interpolation.
- Measured: `grep -nE "toString\(\)|\$\{|\$[a-z]"` on the port file returns
  **no `toString` override and no interpolation** anywhere — there is no code
  path that folds the instructions and the learner note into one string.
- `PlannerAssistRequest.toPrompt()` (`:64-69`) copies fields through verbatim.
- The A6 test (`planner_assist_schema_test.dart:71-83`) confirms an injection
  string in `learnerNote` lands in `untrustedLearnerNote`, never in
  `instructions`, and survives into `toWire()` under its untrusted key.
- Consequence: at this layer the separation is correct. See **NOTE-2** for the
  forward constraint on the (future) HTTP transport.

### 2. Allowlist bypass (A2 / ADR 0270 §2) — NO model-path bypass
- `PlannerAssistSchema.validate` (`planner_assist_schema.dart:39-121`) is the
  **only** producer of a validated proposal from untrusted model output, and it
  enforces exact membership: goal (`:84-88`), skill (`:89-93`), candidate
  **and** the block↔candidate cross-check (`:94-103`, every `block.candidateId`
  must be both allowlisted and present in the response's own `candidateIds`).
  No fuzzy/nearest match anywhere.
- `RemotePlannerAssistGateway.suggest` (the only transport-backed path) routes
  **every** successful response through `PlannerAssistSchema.validate`
  (`remote_planner_assist_gateway.dart:71-78`); there is no branch that builds a
  proposal from `raw` without validating.
- `TutorPlanProposalAdapter` builds a **request + allowlist** only
  (`tutor_plan_proposal_adapter.dart:42-63`) from the practice-generator public
  catalog; it constructs **no** proposal, so it cannot bypass the schema.
- The implementer's mandatory "real-violation probe" (handoff §10) weakened the
  candidate check to the block-list only → the A2 test went **RED**
  (`PlannerAssistAccepted` instead of `PlannerAssistRejected`) → restored. The
  guard is exercised, not decorative.
- `_containsUnsafeContent` is **secondary** and trivially evadable — see
  **NOTE-1** (not a bypass of the primary schema+allowlist boundary).

### 3. Activation path (A1 / ADR 0270 §1) — NO executable path exists
- `PlannerAssistProposal` (`planner_assist_gateway.dart:121-151`) is a pure data
  holder: no `activate`/`execute`/`commit`/`toPlan`/`applyTo`/`mutate` method
  (grep across the new files returns **only a doc-comment** saying it "cannot
  activate or mutate one"). Its `lifecycle` getter is hardcoded to the sole enum
  value `awaitingConfirmation` (`:149-150`, `:153`).
- `requiresLearnerConfirmation` is a **real runtime guard**: the constructor
  `throw`s `ArgumentError` when it is not `true` (`:133-139`) — a genuine
  `throw`, not an `assert`, so it survives release-mode assert stripping. The
  schema independently rejects any response where
  `requiresLearnerConfirmation != true` (`planner_assist_schema.dart:57-59`) and
  hardcodes `true` when constructing the accepted proposal (`:118`). Two
  independent gates, both fail-closed.

### 4. Errors never leak raw model output — HOLDS
- Every failure branch of `RemotePlannerAssistGateway.suggest` yields only a
  `PlannerAssistFallbackReason` **enum**: timeout (`:48-49`), rate limit
  (`:51-54`), typed network (`:56-60`), and a catch-all `catch (_)` (`:61-66`)
  that **discards the exception unbound**. Schema rejection yields
  `schemaRejected` (`:74-77`) carrying only a `PlannerAssistRejectionReason`
  enum, never `raw`. `raw` (`:45-47`) flows **only** into
  `PlannerAssistSchema.validate` (`:71`).
- Measured: `grep -nE "print\(|debugPrint\(|developer\.log|log\(|stderr|stdout|
  writeAsString|File\("` over all five new lib files returns **zero matches**;
  no `toString()`/`.message` on `raw` or on any exception.
- `PlannerAssistFallback.explanation` (`planner_assist_gateway.dart:187`,
  `:207-222`) returns fixed, offline-safe strings per enum — no model text.

### 5. `ai_tutor` non-import (brief §0.0 hard ban) — HOLDS
- `grep -rn "ai_tutor" lib/features/practice_generator/` returns **two
  doc-comment lines only** (`tutor_plan_proposal_adapter.dart:3,36`), both
  explaining that the adapter deliberately does **not** depend on `ai_tutor`.
  **Zero `import` statements.** The frozen empty `ai_tutor` boundary is
  untouched, matching the §0.0 pre-flight (L121/L133/L139 scope-narrowing).

### 6. Secrets / keys / endpoints — none
- `PlannerAssistTransport` (`remote_planner_assist_gateway.dart:10-12`) is an
  `abstract interface class` with a single `request(PlannerAssistPrompt)`
  method — **no URL, no API key, no auth header, no endpoint.**
- Measured: `grep -rniE "api[_-]?key|secret|token|bearer|https?://|password|
  authorization|endpoint"` over the new lib + test + fixture files matches only
  the identifier `PlannerAssistCancellationToken` (the substring "token"); no
  key material.
- Fixtures (`test/fixtures/.../planner_assist_fixtures.dart`) use obviously-fake
  domain identifiers (`goal.rhythm`, `rhythm.offbeatUpstroke`,
  `practiceCatalog:exercise.offbeat`, `catalog.assist.v1`) — semantically real
  fakes, nothing the `check_secrets` gate would (or should) flag.

### Offline-first (A4/A5/A7 / ADR 0270 §5) — HOLDS
- Disabled flag, cancellation, timeout, rate limit, typed + untyped network
  failure all yield a deterministic fallback event and **never** touch the
  caller-owned draft (gateway test `:41-135`; A4/A5 asserts the draft is
  byte-equal after a timeout, `:59`). `FakePlannerAssistGateway.disabled()`
  short-circuits before any transport call (`fake_planner_assist_gateway.dart:28-32`).

## Findings

### MINOR-1 — Untrusted model ID arrays are length-uncapped (schema DoS defense-in-depth gap)
- **Location:** `lib/features/practice_generator/data/ai/planner_assist_schema.dart:124-133`
  (`_readCodes`) — contrast the caps present at `:135-142` (`_readSafeText`,
  rationale ≤ 500) and `:144-149` (`_readBlocks`, ≤ `_maximumBlocks = 6`).
- **Failure scenario:** a future `PlannerAssistTransport` hands `validate` a
  parsed response whose `goalIds` (or `skillIds` / `candidateIds`) is a JSON
  array of N unique non-empty strings (e.g. N = 10⁶, first element allowlisted).
  `_readCodes` builds an N-element `List<String>` **and** an N-element `Set`
  (uniqueness check, `:131`) **before** any allowlist check runs; only then does
  the allowlist `.any` (`:84`) short-circuit at the first non-allowlisted
  element. Net: O(N) time+memory inside the validator, driven purely by
  attacker-controlled model output. The heavier nested structure (`blocks`) is
  capped at 6, so the omission is specifically the three flat ID arrays.
- **Rule:** bounded validation of untrusted input (resource-exhaustion / DoS
  hardening). Also a claim/coverage gap: handoff §10 lists "méretkorlát" among
  the validated properties, but the size limit covers only `rationale` + `blocks`,
  not the ID arrays.
- **Why MINOR, not MAJOR/BLOCKER:** unwired today (no transport exists), and the
  upstream JSON decoder already materializes the array, so the schema adds no
  unbounded asymptotic exposure beyond what a future transport accepts. Not
  reachable in production.
- **Fix direction:** add a small `maxLength` cap to `_readCodes` (mirror
  `_maximumBlocks`), rejecting oversized arrays as `schemaViolation` before
  materialization — a valid response can never legitimately reference more IDs
  than the allowlist cardinality, so capping at (or near) `allowlist.length` is
  both safe and precise.

### NOTE-1 — `_containsUnsafeContent` is trivially evadable and its name over-implies protection
- **Location:** `planner_assist_schema.dart:174-179`, applied at `:104-105` to
  the **model-response** `rationale` / `block.rationale` only (never to the
  learner note).
- **Evidence (reproduced verbatim):** only the two exact literals
  `"ignore previous instructions"` and `"<script"` (case-insensitive) plus
  control chars are caught. `"Ignore all previous instructions…"` (one word
  inserted), a paraphrase, a Hungarian-language injection, double-spacing, and a
  unicode-whitespace variant **all pass**.
- **Why NOTE, not a finding:** this is *not* the boundary — the real defenses are
  schema + exact allowlist + structural learner-note separation, and the scanned
  `rationale` has **no sink today** (unwired). The risk is a *maintainer trap*:
  the name `_containsUnsafeContent`, the enum `unsafeContent`, and the handoff's
  "unsafe tartalom" imply general injection/XSS protection that three literal
  checks do not provide. A future maintainer must **not** rely on it (e.g. must
  not use it to justify rendering `rationale` as markup/HTML).
- **Fix direction:** rename to reflect the narrow intent (e.g.
  `_hasControlCharsOrObviousMarkup`) and/or document it as best-effort cosmetic
  only; keep schema+allowlist as the load-bearing guarantee.

### NOTE-2 — Prompt-injection isolation is structural; the future HTTP transport must preserve it
- **Location:** `planner_assist_gateway.dart:105-116` (`toWire`), `:93-96`
  (`_instructions`).
- **Scenario:** `toWire()` correctly separates `instructions` and
  `untrustedLearnerNote` into distinct fields, but ADR 0270 §3's "embedded
  'forget the above' content is ineffective" guarantee only holds if the
  **future** transport serializes those as **structured** provider fields and
  does **not** flatten them into a single concatenated prompt string. A
  transport that does `"$instructions\n$untrustedLearnerNote"` re-introduces the
  injection this layer prevented.
- **Fix direction:** the transport-wiring round must be security-reviewed for
  exactly this; the provider call should carry the note as a data/user field
  distinct from the system/instruction field, never string-joined.

### NOTE-3 — Model `rationale` free text is stored verbatim; future render must be inert and on-device
- **Location:** `planner_assist_schema.dart:73,111-118`; stored at
  `planner_assist_gateway.dart:145`.
- `rationale` (≤ 500 chars) is untrusted model output with no current consumer
  (grep: zero production sinks). A future UI must render it markup-inert (Flutter
  `Text()`, cf. E07-R26) and must **not** forward it off-device or into
  logs/telemetry.

### NOTE-4 — Public `PlannerAssistProposal` constructor carries no allowlist proof
- **Location:** `planner_assist_gateway.dart:121-151`, exported via
  `public.dart:8`.
- Any caller can construct a proposal with arbitrary (non-allowlisted) IDs from
  its own typed values. This is **not** a model-path bypass — untrusted model
  output becomes a proposal **only** through `PlannerAssistSchema.validate`
  (`RemotePlannerAssistGateway.suggest:71` always validates), and ADR 0270 §1
  re-checks the proposal at the deterministic activation step. The type itself,
  however, does not self-prove allowlisting; a future consumer must not treat a
  `PlannerAssistProposal`'s IDs as catalog-valid without that deterministic
  re-validation.

### NOTE-5 — Head reconciliation (see Provenance above)
- The reviewed code `a1a6da38` was fetched from the standalone implementer clone
  because the shared branch ref lagged at the pre-flight commit `ed197b04`. The
  orchestrator must confirm the merged head equals `a1a6da38` (or a
  content-identical rebase) so that the code reviewed here is the code merged.

## Reproduction appendix

- Head recovery: `git -C /tmp/security-review-e07-r28 fetch
  /home/ubuntu/ss-codex-e07-r28 codex/e07-r28-planner-assist-gateway && git
  checkout a1a6da38`; then `git diff e95bd937 HEAD --stat` = 10 files / +1099/−3.
- Leak-sink scan (zero matches): `grep -rnE
  "print\(|debugPrint\(|developer\.log|log\(|stderr|stdout|writeAsString|File\("`
  over the five new lib files.
- `ai_tutor` ban (doc-comments only, zero imports): `grep -rn "ai_tutor"
  lib/features/practice_generator/`.
- Unwired proof (no production consumer): `grep -rnE
  "PlannerAssist|TutorPlanProposalAdapter|TutorPlanOutline" lib/` minus the new
  files + barrel = empty.
- Flag OFF: `grep -nE "plannerAssistEnabled" lib/app/config/feature_flags.dart`
  → `:23 = false`, `:79 = false`.
- `_containsUnsafeContent` bypass: verbatim-logic standalone run — only the two
  literal patterns + control chars are caught; word-inserted / paraphrased /
  Hungarian / double-space / unicode-whitespace variants pass.

## Bottom line

The boundary does the security-relevant work by **construction**: the only route
from untrusted model output to a proposal is the atomic, exact-allowlist,
fail-closed `PlannerAssistSchema.validate`; the proposal has no activation
surface and a real (non-assert) confirmation guard; every transport failure
collapses to an enum-only deterministic fallback with no raw-output leak; the
learner note is isolated into its own wire field; and the frozen `ai_tutor`
boundary and the OFF `plannerAssistEnabled` flag are both intact. **PASS** —
merge permitted under the unchanged green gate. Address MINOR-1 (a one-line cap)
opportunistically, and carry NOTE-1..NOTE-4 into the future transport/UI wiring
round, which will need its own high-risk security review.
