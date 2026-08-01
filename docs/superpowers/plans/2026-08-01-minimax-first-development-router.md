# MiniMax-first Development Router Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a deterministic, headless development router that gives MiniMax M3 two implementation attempts, escalates only objective code failures to one GPT-5.6 Terra repair, and hands successful code to the existing independent review and CI pipeline.

**Architecture:** The existing round pipeline continues to own task selection, worktree lifecycle, independent Claude review, CI, merge, and final status. A new Python 3.11+ standard-library router owns only the implementation attempts, structured quality-gate decisions, workspace scope enforcement, redacted escalation packets, and the globally locked Terra budget. Repository configuration is versioned; credentials, authoritative run state, and the Terra ledger live outside model-writable worktrees.

**Tech Stack:** Python 3.11+ standard library (`tomllib`, `fcntl`, `subprocess`, `urllib`), Bash, Codex CLI profiles, Git, Flutter/Dart quality gates, `unittest`.

---

## Task 1: Versioned configuration and brief contract

**Files:**
- Create: `.ai/router.toml`
- Create: `tools/ai_router/__init__.py`
- Create: `tools/ai_router/models.py`
- Create: `tools/ai_router/config.py`
- Create: `tools/ai_router/brief.py`
- Create: `tools/tests/test_router_config.py`
- Create: `tools/tests/test_brief_metadata.py`

- [ ] **Step 1: Write failing configuration tests**

Test valid loading, unknown-key rejection, missing-key rejection, invalid limits, engine/risk enums, safe relative paths, and Python 3.11 preflight.

```python
config = load_config(path)
self.assertEqual(config.routing.default_engine, "auto")
with self.assertRaises(ConfigError):
    load_config(unknown_key_path)
```

- [ ] **Step 2: Run the tests and confirm the expected import failure**

Run: `python3 -m unittest tools.tests.test_router_config tools.tests.test_brief_metadata -v`

Expected: `ModuleNotFoundError: No module named 'tools.ai_router'`.

- [ ] **Step 3: Implement immutable typed models and fail-closed TOML parsing**

The public contract is:

```python
@dataclass(frozen=True)
class BriefMetadata:
    schema_version: int
    risk: str
    allowed_paths: tuple[str, ...]
    gate_tests: tuple[str, ...]
    native_gate: bool
```

Only documented keys are accepted. Paths must be repository-relative, non-empty, normalized, and must not contain `..`.

- [ ] **Step 4: Add the production router policy**

`.ai/router.toml` sets `auto`/MiniMax-M3 defaults, two M3 attempts, one Terra attempt per task, three automatic Terra starts per UTC day, medium Terra reasoning, a 40,000-token packet target estimate, an 81,920-byte hard packet cap, explicit retryable service categories, and protected paths.

- [ ] **Step 5: Run tests and commit**

Run: `python3 -m unittest tools.tests.test_router_config tools.tests.test_brief_metadata -v`

Expected: PASS.

Commit: `git commit -m "feat(ai): add router configuration contract"`

## Task 2: Atomic authoritative state and Terra ledger

**Files:**
- Create: `tools/ai_router/state.py`
- Create: `tools/tests/test_state_store.py`

- [ ] **Step 1: Write failing state tests**

Cover atomic JSON writes, `0600` files, `0700` directories, exclusive run locks, crash-safe reload, task budget persistence, UTC-day Terra limits, and reservation transitions `reserved -> started -> finished`.

```python
reservation = ledger.reserve(task_id="EPIC3-R01", daily_limit=3)
self.assertEqual(reservation.status, "reserved")
ledger.mark_started(reservation.id)
ledger.mark_finished(reservation.id, outcome="ready_for_review")
```

- [ ] **Step 2: Run the test and confirm the expected failure**

Run: `python3 -m unittest tools.tests.test_state_store -v`

Expected: import or missing-class failure.

- [ ] **Step 3: Implement locked, atomic stores**

Use `fcntl.flock`, a same-directory temporary file, `fsync`, `os.replace`, and strict modes. Never trust `.ai/runs` for budget decisions. A stale `reserved` or `started` Terra entry still consumes the daily/task budget until explicitly reconciled.

- [ ] **Step 4: Run tests and commit**

Run: `python3 -m unittest tools.tests.test_state_store -v`

Expected: PASS.

Commit: `git commit -m "feat(ai): add atomic router state and Terra ledger"`

## Task 3: Classification, redaction, scope audit, and escalation packet

**Files:**
- Create: `tools/ai_router/classification.py`
- Create: `tools/ai_router/security.py`
- Create: `tools/ai_router/packet.py`
- Create: `tools/tests/test_classification.py`
- Create: `tools/tests/test_security.py`
- Create: `tools/tests/test_packet.py`

- [ ] **Step 1: Write failing behavior tests**

Cover structured gate categories, repeated error hashes, no-progress diff hashes, provider HTTP/network/quota classes, secret redaction, prompt injection delimiters, tracked/untracked/ignored/deleted/symlink scope violations, log truncation, diff allow-listing, and the byte limit.

```python
self.assertEqual(classify_provider_failure(429), FailureClass.QUOTA)
self.assertNotIn("sk-", redact_text(secret_fixture))
self.assertLessEqual(len(packet.encode()), 81_920)
```

- [ ] **Step 2: Run and observe the expected import failures**

Run: `python3 -m unittest tools.tests.test_classification tools.tests.test_security tools.tests.test_packet -v`

- [ ] **Step 3: Implement deterministic classification and packet construction**

Only `code_failure` can contribute to Terra escalation. `quota`, `rate_limit`, `network`, `provider_5xx`, `environment_failure`, `invalid_gate`, `policy_violation`, and `internal_failure` defer/block without Terra. Packet content is bounded to the original task, acceptance criteria, failed commands, redacted log tail, attempt summaries, scoped diff, relevant paths, and fixed repair constraints.

- [ ] **Step 4: Run tests and commit**

Run: `python3 -m unittest tools.tests.test_classification tools.tests.test_security tools.tests.test_packet -v`

Expected: PASS.

Commit: `git commit -m "feat(ai): secure router failure packets"`

## Task 4: Process execution and structured gate adapter

**Files:**
- Create: `tools/ai_router/execution.py`
- Create: `tools/tests/test_execution.py`
- Modify: `tools/round-gate.sh`
- Create: `tools/tests/test_round_gate.py`

- [ ] **Step 1: Write failing fake-process tests**

Generate temporary fake `codex`, `git`, `flutter`, and `dart` executables. Verify prompt delivery through stdin, explicit profile/sandbox/approval/ephemeral/JSON flags, timeout termination, sanitized event summaries, structured gate JSON, and exit mappings.

```python
self.assertIn("--profile", invocation.argv)
self.assertEqual(invocation.stdin, prompt)
self.assertNotIn(prompt, " ".join(invocation.argv))
```

- [ ] **Step 2: Run and observe expected failures**

Run: `python3 -m unittest tools.tests.test_execution tools.tests.test_round_gate -v`

- [ ] **Step 3: Implement the process runner and gate schema**

`round-gate.sh --result-json PATH` writes atomically:

```json
{"schema_version":1,"status":"failed","category":"code_failure","failed_command":"flutter test test/x_test.dart","error_hash":"sha256:..."}
```

Exit codes are `0=pass`, `10=code_failure`, `20=environment_failure`, `30=invalid_gate`, `40=internal_failure`. Legacy invocation remains supported.

- [ ] **Step 4: Run tests and shell validation, then commit**

Run: `python3 -m unittest tools.tests.test_execution tools.tests.test_round_gate -v`

Run: `bash -n tools/round-gate.sh`

Expected: PASS.

Commit: `git commit -m "feat(ai): add structured quality-gate results"`

## Task 5: Deterministic router state machine and CLI

**Files:**
- Create: `tools/ai_router/router.py`
- Create: `tools/model-router.py`
- Create: `tools/tests/test_router.py`
- Create: `tools/tests/test_router_cli.py`
- Modify: `.gitignore`

- [ ] **Step 1: Write failing state-machine tests**

Cover baseline gate failure, M3 pass, first M3 code failure then repair pass, two M3 failures then Terra pass, repeated-error/no-progress escalation, high-risk direct targeted Terra review, service/quota defer without Terra, scope violation stop, crash resume, one-Terra-per-task, and second review correction using the same attempt budget.

```python
self.assertEqual(result.status, RouterStatus.READY_FOR_REVIEW)
self.assertEqual(fake_codex.profiles, ["m3", "m3", "terra"])
```

- [ ] **Step 2: Run and observe expected failures**

Run: `python3 -m unittest tools.tests.test_router tools.tests.test_router_cli -v`

- [ ] **Step 3: Implement the router**

CLI contract:

```text
tools/model-router.py run --task TASK.md --worktree PATH --result-json PATH
tools/model-router.py status --task-id ID --json
tools/model-router.py resume --task TASK.md --worktree PATH --result-json PATH
tools/model-router.py smoke --profile m3|terra
```

Exit codes: `0=READY_FOR_REVIEW`, `20=STOPPED`, `30=DEFERRED`, `40=BLOCKED`, `50=INTERNAL_ERROR`. The CLI writes a redacted non-authoritative workspace result and authoritative state outside the worktree.

- [ ] **Step 4: Ignore only generated run/cache artifacts**

Add `.ai/runs/`, `__pycache__/`, and `*.pyc`; keep `.ai/router.toml` tracked.

- [ ] **Step 5: Run tests and commit**

Run: `python3 -m unittest tools.tests.test_router tools.tests.test_router_cli -v`

Expected: PASS.

Commit: `git commit -m "feat(ai): implement MiniMax-first router"`

## Task 6: Pipeline and headless orchestration integration

**Files:**
- Modify: `tools/round-pipeline.sh`
- Modify: `tools/codex-signal.sh`
- Modify: `tools/pipeline-status.sh`
- Modify: `docs/execution/pipeline-orchestrator-prompt.md`
- Modify: `docs/execution/pipeline-queue.tsv`
- Create: `tools/tests/test_pipeline_integration.py`

- [ ] **Step 1: Write failing pipeline adapter tests**

Use fake router/Claude/Codex executables and a temporary queue. Assert `auto` dispatches once to the router; `codex` and `minimax` stay explicit legacy overrides; `READY_FOR_REVIEW` becomes progress rather than done; stopped/deferred/blocked mappings are stable; no prompt or secret appears in status output.

- [ ] **Step 2: Run and observe the expected failures**

Run: `python3 -m unittest tools.tests.test_pipeline_integration -v`

- [ ] **Step 3: Integrate without changing ownership boundaries**

The pipeline keeps worktree/branch, independent Claude review, CI, merge, and final completion. The router receives the existing task worktree. Review corrections resume the same task/run and cannot reset model budgets.

- [ ] **Step 4: Update operator documentation and queue enum**

Document `auto|minimax|codex`, headless behavior, router status fields, and the rule that only review+CI may emit `done`. Set new prepared Epic 3 rows to `auto` without reordering columns.

- [ ] **Step 5: Run tests and commit**

Run: `python3 -m unittest tools.tests.test_pipeline_integration -v`

Run: `bash -n tools/round-pipeline.sh tools/codex-signal.sh tools/pipeline-status.sh`

Expected: PASS.

Commit: `git commit -m "feat(ai): route automatic pipeline work through M3"`

## Task 7: Credential, quota, and machine installer

**Files:**
- Create: `tools/ai_router/credential.py`
- Create: `tools/ai_router/quota.py`
- Create: `tools/ai_router/install.py`
- Create: `tools/minimax-credential.py`
- Create: `tools/minimax-quota.py`
- Create: `tools/install-ai-router.py`
- Create: `tools/tests/test_credential.py`
- Create: `tools/tests/test_quota.py`
- Create: `tools/tests/test_install.py`

- [ ] **Step 1: Write failing security and installer tests**

Use temporary home directories. Verify ownership/symlink/mode checks, JSON credential extraction without logs, sanitized quota output, HTTP classification, atomic config merge, backups, `0700` helpers/state directories, `0600` profiles/state files, idempotency, and preservation of the existing global default model.

- [ ] **Step 2: Run and observe expected failures**

Run: `python3 -m unittest tools.tests.test_credential tools.tests.test_quota tools.tests.test_install -v`

- [ ] **Step 3: Implement fail-closed helpers and installer**

The credential helper reads only the user-owned, non-symlink `~/.mmx/config.json`. The quota helper calls `https://www.minimax.io/v1/token_plan/remains`, never prints a raw body or key, and returns a small typed status. The installer merges only the MiniMax provider block, writes `m3.config.toml` and `terra.config.toml`, installs absolute-path command-backed auth helpers, and leaves the global `model` unchanged.

- [ ] **Step 4: Run tests and commit**

Run: `python3 -m unittest tools.tests.test_credential tools.tests.test_quota tools.tests.test_install -v`

Expected: PASS.

Commit: `git commit -m "feat(ai): add secure Codex profile installer"`

## Task 8: Add executable metadata to all Epic 3 briefs

**Files:**
- Modify: `docs/rounds/e03-r01-*.md` through `docs/rounds/e03-r22-*.md`
- Modify: `tools/tests/test_brief_metadata.py`

- [ ] **Step 1: Extend the parametrized test and observe failure**

The test discovers exactly 22 ordered briefs and requires a fenced `ai-router` TOML block with `schema_version`, `risk`, `allowed_paths`, `gate_tests`, and `native_gate`. It rejects wildcard root access and gate commands outside the allow-list.

- [ ] **Step 2: Add the metadata from each brief's existing scope and quality gate**

No feature requirements change. Each allow-list is the narrow union of the brief's listed production/test/doc paths; native gates are enabled only where the brief already requires native code verification.

- [ ] **Step 3: Run tests and commit**

Run: `python3 -m unittest tools.tests.test_brief_metadata -v`

Expected: all 22 briefs PASS.

Commit: `git commit -m "docs(epic-03): add router metadata to round briefs"`

## Task 9: Architecture and operating documentation

**Files:**
- Create: `docs/adr/0088-minimax-first-development-router.md`
- Modify: `AGENTS.md`
- Modify: `docs/LESSONS.md`
- Modify: `docs/execution/02-codex-playbook.md`
- Modify: `docs/execution/04-definition-of-done.md`

- [ ] **Step 1: Write the accepted ADR**

Record boundaries, threat model, deterministic escalation, authoritative state, crash semantics, profile authentication, status vocabulary, and the exact parts of ADR 0069 superseded by `auto` routing. Preserve the independent-review requirement.

- [ ] **Step 2: Align agent and operator instructions**

Document exact test/build commands, forbidden automatic modifications, Definition of Done, headless invocation, pause/resume/recovery, manual overrides, and the distinction between `READY_FOR_REVIEW` and final `done`.

- [ ] **Step 3: Record non-obvious implementation lessons**

Add dated evidence-based bullets for bwrap constraints, command-backed authentication, quota schema handling, and crash-safe Terra reservation.

- [ ] **Step 4: Run documentation audits and commit**

Run: `rg -n "[3] MiniMax|thr[e]e MiniMax|docs/epic-03/rounds|docs/architecture/decisions/0070" AGENTS.md docs/execution/02-codex-playbook.md docs/execution/04-definition-of-done.md docs/execution/pipeline-orchestrator-prompt.md docs/adr/0088-minimax-first-development-router.md`

Expected: no stale router rules or placeholders.

Commit: `git commit -m "docs(ai): adopt MiniMax-first router operations"`

## Task 10: Install on the Oracle ARM host

**Files outside repository:**
- Modify: `/home/ubuntu/.codex/config.toml`
- Create: `/home/ubuntu/.codex/m3.config.toml`
- Create: `/home/ubuntu/.codex/terra.config.toml`
- Create: `/home/ubuntu/.local/libexec/strumsight-ai/minimax-credential`
- Create: `/home/ubuntu/.local/libexec/strumsight-ai/minimax-quota`
- Create: `/home/ubuntu/.local/state/strumsight-ai-router/`

- [ ] **Step 1: Capture a redacted before-state**

Run `codex --version`, `codex login status`, and a config-key-only audit. Record the global model/provider without printing credentials.

- [ ] **Step 2: Run the tested installer**

Run: `python3 tools/install-ai-router.py --home /home/ubuntu --source-config /home/ubuntu/.mmx/config.json`

Expected: idempotent install report containing paths and modes only.

- [ ] **Step 3: Verify permissions and unchanged defaults**

Check helpers/directories are `0700`, profiles/config/state are `0600`, source credential is not a symlink and is `0600`, ChatGPT login remains active, and the pre-install global model/provider values are unchanged.

- [ ] **Step 4: Validate configuration parsing**

Run: `codex --version`

Run: `codex exec --profile m3 --help`

Run: `codex exec --profile terra --help`

Expected: all exit 0 without configuration errors.

## Task 11: Full verification and live read-only smoke tests

**Files:**
- Modify only if verification exposes a defect in the files above.

- [ ] **Step 1: Run all deterministic tests**

Run: `python3 -m unittest discover -s tools/tests -p 'test_*.py' -v`

Run: `bash -n tools/*.sh`

Run: `git diff --check`

Expected: all PASS.

- [ ] **Step 2: Run fake end-to-end scenarios**

Run the CLI integration suite for M3 success, M3 repair, Terra escalation, quota defer, service retry/defer, scope stop, crash resume, and daily-budget exhaustion. Confirm no fake prompt/secret appears in generated status.

- [ ] **Step 3: Run sanitized quota smoke**

Run: `/home/ubuntu/.local/libexec/strumsight-ai/minimax-quota --check-only`

Expected: typed status only, no token or raw provider body.

- [ ] **Step 4: Run real M3 smoke through stdin**

Run the router smoke subcommand with `--profile m3`; it must execute Codex with `--sandbox read-only --ask-for-approval never --ephemeral --json -` and receive exactly `M3_OK` semantically.

- [ ] **Step 5: Run real Terra smoke through stdin**

Run the router smoke subcommand with `--profile terra`; it must execute Codex with the same read-only headless constraints and receive exactly `TERRA_OK` semantically.

- [ ] **Step 6: Perform a secret and workspace-scope audit**

Search tracked files and generated workspace artifacts for known credential field names and token prefixes without displaying secret values. Confirm authoritative state is outside the worktree and `.ai/runs` is ignored.

- [ ] **Step 7: Run the final verification matrix and commit any verification fix**

Repeat the full unit suite, Bash syntax checks, metadata audit, config parse, permission audit, smoke tests, `git status --short`, and `git diff --check`. If verification required a code fix, first add a regression test and commit it separately.

Expected result: the router is installed and returns `READY_FOR_REVIEW` only after scope and quality gates pass; final `done` remains owned by independent review and CI.
