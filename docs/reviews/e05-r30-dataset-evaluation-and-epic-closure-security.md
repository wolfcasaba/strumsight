# E05-R30 — Dataset, evaluation, minőségi kapuk és Epic 5 lezárás — Security/Privacy Review

- **Reviewer:** Claude (dedicated `security-reviewer` agent, read-only, isolated `/tmp/security-review-e05-r30` clone)
- **Round:** E05-R30 · branch `codex/e05-r30-dataset-evaluation-and-epic-closure`
- **Base:** `bbb57fd8` (main, pre-round) · **Head reviewed:** `9b993f81` (implementer's final commit). The branch gained one further commit after this review (`505821ac`, orchestrator review-report-only, zero `lib`/`tool`/`ml`/`test` delta) — no re-review needed, confirmed by `git diff --stat 9b993f81..505821ac` touching only `docs/reviews/e05-r30-dataset-evaluation-and-epic-closure-review.md`.
- **Router declaration:** `risk = "high"` — mandatory per AGENTS.md §15.1.
- **Method:** independent clone, static semantic review of all 12 changed files, targeted greps (network/secret/eval/subprocess surface, prompt-injection sweep across brief/manifest/report/runbook prose), and direct inspection of the pre-existing `VisionModelManifest` validator to confirm which code branch the new integrity test actually exercises.

## Verdict: **PASS — merge-safe**

| Severity | Count |
|---|---|
| CRITICAL | 0 |
| BLOCKER | 0 |
| MAJOR | 0 |
| MINOR | 2 (both latent/forward-looking, neither blocks this round) |
| NOTE | 4 |

## Scope reviewed

`git diff --name-status bbb57fd8...9b993f81` = exactly the 12 files declared in the brief §4 allowlist. No `.github/`, `tool/ci/`, or `lib/` production code in the diff; all 11 Vision flags remain `false`. Orchestrator's independent `scope_audit=ok` (`scope_audit_changed=12`) corroborated by direct inspection.

## Findings

### F1 — MINOR — Raw-vision-payload architecture guard is an identifier-substring lint, trivially evadable by a future author

- **File:** `tool/check_architecture.dart:192-247` (`_collectRawVisionPayloadViolations`, `_rawVisionPayloadTypes`)
- **Problem:** the new guard word-boundary-matches a fixed denylist (`VisionImage`, `GrayscaleFrame`, `Uint8List`, `ByteData`, `ByteBuffer`, `VisionPixelFormat`) against trivia-stripped source text under `lib/features/vision/data/persistence/**` and `class …State {}` bodies under `application/**`. It is a textual lint, not a type- or dataflow-check.
- **Failure scenario:** a future activation-round file can persist a raw frame while evading every literal in the denylist — e.g. `typedef RawFrame = Uint8List;` declared elsewhere and consumed by name only, a base64-encoded `String` field, a wrapper class holding the bytes, or a raw field held in an `application/` Notifier/controller that isn't a `*State`-suffixed class (the state-body scanner only matches that naming convention). None of these would be caught by `dart run tool/check_architecture.dart`.
- **Impact today:** none — this round ships zero `lib/` code, so there is nothing yet for the guard to either catch or miss. It is defense-in-depth for ADR 0183/ADR 0178, correctly catching the *direct*, *accidental* case, and correctly leaving the allowlist unchanged (still the pre-existing 12 `analyze → live` entries).
- **Recommended direction (future activation round, not this one):** treat this lint as a tripwire, not the sole control — pair with an explicit review checklist item for any new Vision persistence/state file, and consider a positive allow-shape (enum/int/Duration/coordinate-free summaries only) instead of a growing raw-type denylist.
- **Status:** OPEN, non-blocking, forward-looking. No action required in this round.

### F2 — MINOR — The new model-integrity test never reaches the real cryptographic-hash comparison branch

- **File:** `test/tooling/vision_model_integrity_test.dart:16-24`; `lib/core/ml/vision_model_manifest.dart:247-271` (pre-existing validator, unmodified this round); `assets/ml/model_manifest.json:125-144` (both `vision_models` entries `status: "deferred"`, `sha256` = 64 zero-chars, backing `.tflite` assets absent from the tree).
- **Problem:** `validateVisionManifest` only performs a real disk-read + `sha256.convert()` byte comparison for `status == "active"` entries (confirmed by direct read of lines 247-271, which also self-documents this split in a comment referencing ADR 0185 §Döntés 2). For `status: "deferred"` entries — which is what both shipping vision models are today — it checks only that `sha256` matches the 64-hex-char format regex. The new test's "bad checksum fails the integrity gate" case sets `sha256 = 'invalid-checksum'` (not 64 hex chars), which fails the *format* check, not a byte-level mismatch check. A well-formed-but-wrong hash (e.g. 64 `b` characters) on a deferred entry would currently pass.
- **Impact today:** none — the checksum is inert while no asset bytes are shipped; the validator's own comment is honest about this being pre-existing, intentional scoping, not a gap this round introduced.
- **Recommended direction (before the first `active` vision entry ships):** add a fixture that writes a temporary asset under a temp `projectRoot`, declares a deliberately mismatching `sha256` on an `active` entry, and asserts the byte-comparison branch (lines 263-270) fails — so the cryptographic path has coverage the moment it becomes load-bearing, not after.
- **Status:** OPEN, non-blocking, forward-looking. No action required in this round.

### N1 — NOTE — Shadow-mode "consented aggregate metrics" language is compliant now, must stay consent-gated at activation

`docs/runbooks/vision-rollout.md:29-30`. Compliant as written (consent-gated, aggregate, and the same section explicitly says "Never upload raw frames, video, or landmark streams"). Flagged forward only: the activation round must not let this drift into raw-frame or landmark-stream telemetry.

### N2 — NOTE — CI-side model-integrity gate is intentionally absent, correctly disclosed

`docs/sdd/epic-05-completion-report.md:80-83`, `docs/runbooks/vision-rollout.md:44-49`. Both documents honestly state that the workflow-side gate is out of this round's scope (`.github/`, `tool/ci/` are forbidden zone) and name it as governance follow-up. Enforcement currently rides the test-side gate inside the full CI suite (ADR 0053). Transparent, not a finding against this round.

### N3 — NOTE — §10 handoff pastes terminal output as evidence; implementer self-disclaims and defers to a fresh gate

`docs/rounds/e05-r30-dataset-evaluation-and-epic-closure.md` §10. Correct posture per this project's own rule that pasted CLI output is not proof — the implementer explicitly asked the orchestrator to run an independent exact-SHA gate/review rather than accept the self-report. (The orchestrator did: see `docs/reviews/e05-r30-dataset-evaluation-and-epic-closure-review.md`, 8/8 gate steps green in an isolated clone.)

### N4 — NOTE — Evaluation harness ignores unknown extra JSON fields (fail-open on unknown field, not on required-field validation)

`ml/vision/evaluate_vision_metrics.py:83-121`. `parse_fixture` validates required fields strictly (fail-closed on a bad `metric` value or wrong types) but silently ignores any additional, unexpected keys in a fixture record. Privacy-safe in practice because the harness's own output (`_as_json`) only ever emits aggregate counts/rates — it never echoes fixture content back out, so an injected extra key carries no exposure path. No change requested.

## Boundary checklist (AGENTS.md §5) — evidence

1. **Raw audio/camera frame must not leave the device:** PASS. No network code anywhere in the diff; the new Python harness is stdlib-only (`argparse`/`json`/`sys`/`dataclasses`/`pathlib`/`typing` — grepped for `socket|subprocess|urllib|requests|http|ssl|pickle|eval(|exec(|Popen|urlopen`: none found). Its only I/O is a single, explicit `--input` file read. README.md addition reaffirms camera frames stay on-device.
2. **Logged-out / diagnostics-off → no hidden network request:** PASS. No new network surface introduced; `vision_offline_regression_test.dart` pins vision-off Practice/Song/Analyze/Tutor output byte-for-byte against the pre-vision baseline.
3. **Secret/token/key/raw-audio/frame must not reach logs or commits:** PASS. Secret-pattern grep across all additions (API-key prefixes, private-key headers, JWT/Bearer, cloud credential prefixes) found nothing; the harness's error paths print only static validation messages, never raw fixture values. The project's own `tool/ci/check_secrets.dart` gate is untouched and green in the independent gate run.
4. **Cloud/community feature must not degrade the offline baseline:** PASS. Byte-exact vision-off parity is the entire point of the new regression fixture.
5. **Weak confidence must never render as a certain claim:** PASS, actively reinforced. The evaluation harness treats absent evidence as failure, not success (`NO_DATA` classification, `experimental` default); the 1% inclusive false-cue cap cannot be raised post-hoc per the manifest's own documented policy; the completion report declares zero Vision capabilities production-supported.

## Prompt-injection sweep (AGENTS.md §5.1)

Read the full prose of the brief diff, `ml/vision/dataset_manifest.md` §6, the completion report, and the rollout runbook for embedded instruction-like content attempting to alter policy, gate behavior, or permissions. **None found.** The strongest imperative language in the diff is the rollout ladder and the implementer's own request for a fresh independent gate — both reinforce existing controls rather than bypass them. The architecture allowlist is unchanged (still exactly the 12 pre-existing `analyze → live` entries); the new rules only add checks, never relax one.

## What was not independently re-executed

The real SHA-256 comparison branch of `validateVisionManifest` (unreachable today — see F2) was verified correct by direct code inspection (`package:crypto` `sha256.convert(bytes)` over the actual asset bytes) rather than by execution, since no `active`-status asset exists yet to exercise it. The full Flutter suite, randomized property gate, and APK build were not re-run by this security pass — that is CI's role (ADR 0053) and is separately covered by the independent content review's isolated-clone gate run (8/8 green) plus the exact-SHA Full Gate / Router CI dispatch.
