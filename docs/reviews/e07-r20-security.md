# E07-R20 — Security / Privacy Review (dedicated, mandatory — brief `risk = "high"`)

Brief: `docs/rounds/e07-r20-plan-setup-wizard.md`
Diff: `git diff 4c4de25b..d1a7a898` (10 files, +947/−2, all under `presentation/`, `l10n/*.arb`, `public.dart`, round doc)
Reviewer: Claude (security-reviewer subagent) · Date: 2026-08-18 · Scope: READ-ONLY, no production edits

## Verdict: CHANGES REQUIRED (FAIL) — blocked by one MAJOR (a missing acceptance-mandated regression test) and one MINOR (an inaccurate security claim in a doc-comment). **No secret leak, no consent bypass, no path traversal, no boundary breach, and no active data leak was found.** The privacy property A9 relies on *holds today* — the blocker is that nothing guards it.

## Summary

CRITICAL: 0 · BLOCKER: 0 · MAJOR: 1 · MINOR: 1 · NOTE: 2

---

## Findings

### MAJOR-1 — The A9 "comfort free text is never logged" criterion has no test that can fail on the logging condition

**Where:** `test/features/practice_generator/presentation/plan_setup_screen_test.dart` — test `comfort free text is retained only in the local draft (A9)` (asserts `controller.state.request!.constraints.constraints.single.value == 'Wrist hurts after ten minutes'`).

**Failure scenario:** A future edit adds `debugPrint(request.toString())`, a crash-report breadcrumb, or an analytics event carrying the `LearnerConstraint(category: comfort, code: 'freeText', value: <raw pain text>)`. The A9-labelled test stays green because it only asserts the value is *retained in the draft* (a positive-presence assertion) — it installs no logger/`debugPrint` spy and asserts nothing about log-absence. The most sensitive datum the wizard collects (health-adjacent free text, e.g. "Wrist hurts after ten minutes") could then leak, and CI would not catch it.

**Evidence:**
- `grep -rniE "debugPrint = |DebugPrintCallback|captureLog|logger.*spy" test/` → no matches anywhere in `test/`. No collector-logger harness exists.
- The brief §6 names the A9 evidence explicitly as `plan_setup_screen_test.dart — "gyűjtő logger"` (collector/spy logger), and §6.1 defines the red-trigger "A szabad szöveg naplózva → A9". That red-trigger is currently inoperable: no test would go red if the text were logged.
- The underlying property holds right now: `grep -rniE "\b(print|debugPrint|log|logger|analytics|sentry|crashlytics|Dio|HttpClient|track|record)\b" lib/features/practice_generator/presentation/` returns only the doc-comment on `plan_setup_controller.dart:144`.

**Violated rule:** Brief §5.4 + acceptance A9; ADR 0260 §4; product boundary AGENTS.md §5 #3 (sensitive content never logged).

**Suggested direction:** Add a negative assertion over an actual sink — override `debugPrint` (or inject a logger spy), drive the comfort step with a sentinel string, and assert the sentinel never appears in captured output. No production-code change is required.

*(This is the same underlying gap the independent functional review's F3 identified; that review has been updated to MAJOR to match this severity — see `docs/reviews/e07-r20-review.md`.)*

### MINOR-1 — Controller doc-comment claims the draft path is "encrypted"; it is plaintext `SharedPreferences`

**Where:** `lib/features/practice_generator/presentation/controller/plan_setup_controller.dart:143-144` — `/// Keeps comfort text exclusively inside the encrypted/local draft path;`

**Failure scenario:** The draft is persisted via `GenerationDraftRepository.saveDraft` → `keyValueStore.writeString(...)`. The only production `KeyValueStore` implementation is `lib/core/storage/shared_preferences_store.dart` (plaintext); encrypted storage is the separate `SecureStore`/`flutter_secure_storage` interface, reserved for the JWT (`storage_keys.dart:111 secureAuthToken`). "Encrypted" is factually false. A future maintainer trusting this comment could store additional sensitive data, or wire an export, believing the health-adjacent comfort text is encrypted at rest when it is plaintext.

**Evidence:** `grep -rlE "implements KeyValueStore" lib/` → only `shared_preferences_store.dart`; `grep -rniE "encrypt|secure" lib/core/storage/` shows encryption lives only in the unrelated `SecureStore`.

**Suggested direction:** Change "encrypted" to "plaintext local" (accurate). Fixable in one line, no scope expansion.

### NOTE-1 — Health-adjacent comfort text is persisted verbatim in plaintext local storage (pre-existing, out-of-scope backend)

Not a finding against the implementer: local-device-only (no Dio/HTTP/Supabase path touches `PracticeGenerationRequest`/`GenerationDraftRepository` anywhere in `lib/`), unwired behind a false flag, consistent with the app's existing convention (`SecureStore` reserved for the JWT only), and the storage backend was chosen in R04, outside this round's `allowed_paths`. Recorded for a future round that wires the wizard on or adds export/sync to revisit whether this field belongs in `SecureStore` and/or must be dropped from any summary/export DTO (cf. the E07-R10 summary-DTO seam for `PracticeGoal.userNote`).

### NOTE-2 — `StorageFailure(cause: e)` can embed draft source text on a decode error, but this round surfaces no sink for it

`GenerationDraftRepository.loadDraft` wraps decode errors as `StorageFailure(cause: e)`, where `e` may be a `FormatException` whose message can contain a fragment of the raw stored JSON (which includes the comfort text). This round creates no reachable leak: the screen renders only the static localized `l10n.planSetupNoDraft` string on `persistenceFailed` and never renders `cause`/`toString()`. Flagged so a future round that logs or displays `StorageFailure.cause` treats it as sensitive.

---

## What was verified clean (with evidence)

- **No new logging / analytics / crash-reporting sink** anywhere in the new `presentation/` code (word-bounded grep, only the doc-comment matched).
- **No network, no permissions, no credentials touched** — imports limited to `package:flutter/*`, `dart:math`, `l10n`, existing internal `domain/`+`data/` symbols. No `Dio`/`HttpClient`/`http`/`supabase` anywhere the request flows.
- **No new dependency, no new asset, no binary** — 10 text-file `create mode 100644` entries only; `pubspec.yaml` untouched; ID generation uses `dart:math Random.secure()`.
- **No secret/key committed** — consistent with the gate's `check_secrets.dart` clean run (2833 files, 0 findings).
- **ARB content is safe** — all 22 new `planSetup*` keys are generic UI copy; the only interpolation (`planSetupStep`) uses `int` placeholders, no user text interpolated anywhere.
- **No prompt-injection surface** — pure local presentation/controller diff, no external/untrusted content imported.
- **Unwired / dead in production** — no router/production caller anywhere in `lib/`; `practiceGeneratorEnabled` stays `false` in both the default constructor and `forEnvironment`.
- **Serializer omits sensitive values on its own error path** (positive) — `GenerationRequestSerializerException` always carries a stable code, never the offending value.

## Product-boundary checklist (AGENTS.md §5)

| Boundary | Result |
|---|---|
| Raw audio/camera never leaves device by default | N/A — no audio/camera/network in diff |
| No hidden network request when logged-out / diagnostics-off | PASS — zero network calls in diff |
| No secret/token/audio/frame in log/signal/error/commit | PASS — no logging; serializer error path omits values; no secret committed |
| Cloud/community feature must not degrade offline base | N/A — pure local feature |
| Weak confidence not shown as certainty | N/A |
| Sensitive free text never logged (§5 #3, ADR 0260 §4) | Property holds now, but unguarded → MAJOR-1 |

## Merge-döntés

Nem javasolt merge, amíg a MAJOR-1 (és a vele egy körben olcsón javítható
MINOR-1) nyitva van. Mindkettő teszt/dokumentáció-szintű javítás, nem
igényel scope-bővítést.
