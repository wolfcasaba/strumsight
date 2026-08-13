# E06-R27 — Security review

- **Reviewer:** independent security pass (dedicated `security-reviewer` agent,
  separate from the main content review)
- **Reviewed tree:** isolated `/tmp/review-e06-r27` clone at the correction
  commit (content-identical across `524397de` → rebase `15363b51` → `587d68d1`;
  the rebase and the subsequent review-file commit touch no reviewed
  production file — confirmed the three fixes are present in the tree
  actually read, so the pre-rebase SHA name is cosmetic, not a wrong-tree risk)
- **Risk:** high
- **Verdict:** APPROVED — 0 CRITICAL, 0 BLOCKER, 0 MAJOR, 5 NOTE (all
  forward-looking, no live sink today).

## Scope of this independent pass

This pass did not re-confirm what the main review already verified (the
three prior findings' fixes, gate-green, scope-audit). It brought a
security-specific lens the content review does not aim at: whether the
`_allowedMessageArgKeys` allowlist is actually complete against every real
producer in the codebase (not just plausible), whether any *other* free-text
field escapes redaction, deletion-completeness honesty, the new
`ShareService` method's blast radius, secret/PII leakage through exceptions,
and network/permission surface.

## What was independently checked (with evidence)

### 1. `_allowedMessageArgKeys` completeness and argument-set tightness

Enumerated every `messageKey`/`messageArgs` producer in `lib/` (not just the
engine), via `grep -rn "messageKey:" / "messageArgs:" / "AnalysisWarning("`:
9 insight keys (`insight_rules.dart`), `analysis.stage_unavailable`
(`analysis_pipeline.dart:213`), 2 migration keys
(`legacy_analyze_adapter.dart:27-29`), 4 quality keys
(`signal_quality_stage.dart:65-88`) — all 16 match the map exactly, and every
forwarded argument value traced back to a safe source: numeric strings
(`toStringAsFixed`), a structured `hotspotId` (`timing-hotspot-<runId>:onset:<n>`,
never user input), a catalog-gated `metricId`, a fixed `stageId` enum, a
`FailureCode` string, integer counts. No argument name in the map admits a
value that could carry a filename, device id, or raw content.

### 2. Free-text scan of `analysis_export.dart` / `analysis_export_codec.dart`

Traced every `String`-typed field the redaction copies out of
`AnalysisDocument`: `documentId` is a timestamp-derived id (never a
filename), `metric.id`/`unit`, `insight.id`/`ruleId`/`ruleVersion`, and
`completion.failureCode` are all catalog- or constant-bound; every other
string field is an enum's `.name`. `AnalysisExportInput` deliberately omits
`sourceName`/`fingerprint`; capability/hotspot/metric/insight export models
omit `details`/hotspot `id`/`evidence`/`factIds` respectively — confirmed by
reading `analysis_export.dart`'s field list against the source
`AnalysisDocument`. Structurally, `AnalysisExportCodec.encode()` only ever
accepts the already-redacted `AnalysisExport`, so the codec itself cannot
widen the boundary even under future changes.

### 3. Deletion completeness (`delete_analysis_use_case.dart`)

The no-op cache/audio ports are honestly documented as unfinished
(E06-R28 follow-up), not a false persistence claim. `repository.delete` runs
first and short-circuits the ports on failure. The unchanged R21 `delete`
rewrites the index before deleting the file, so `getById` returns not-found
immediately — no stale readable copy today (no cache exists yet). See NOTE-3
for a wiring hazard the R28 cache round must handle.

### 4. `ShareService.shareExportFile` blast radius

`try` wraps the share call, `finally` deletes the file on both outcomes;
`XFile`/`ShareParams` construction happens inside the guarded region. Its
only caller today is `ExportAnalysisUseCase`, with a random-named app-private
temp file. See NOTE-4 for a forward-looking constraint on future callers.

### 5. Secret/PII in exceptions

`StorageFailure(cause: error, ...)` in `export_analysis_use_case.dart:80`
carries a `FileSystemException` whose path is the random-hex temp filename
(no user content), and `AppFailure.toString()` (`app_failure.dart:115`)
excludes `cause` from any rendered/logged output by contract — the raw
redacted JSON is never attached to an exception.

### 6. Network / permissions / mic surface

Zero `dio`/`http`/`core/network` imports across all 9 new/changed files
(read the actual import lines, not just the existing source-scan test). No
manifest/`Info.plist`/permission/gradle changes in the diff. The
`share_service.dart` diff against the pre-round base is purely additive —
zero lines removed from `shareCard`/`shareImage`/`shareText`/`capturePng`/
`_writeTemp` — so existing mic-ownership/lifecycle guarantees are untouched.

### Prior three findings — independently reconfirmed closed

Same conclusion as the main review, reached independently: the BLOCKER
(message-arg boundary) is fail-closed by construction with dual-path
(insight + warning) regression coverage; the MAJOR (confidence-as-fact) is
closed by the `0.4` threshold matching the engine's real
`minimumDegradedConfidence`; the MAJOR (write-failure cleanup) is closed by
wrapping directory-creation and write in their own try/catch ahead of the
`ShareService` handoff.

## Findings

| # | Severity | Location | Failure scenario | Fix direction |
|---|---|---|---|---|
| NOTE-1 | NOTE | `redaction_policy.dart:4-11` | The allowlist's doc-comment claims it covers "every messageKey this build's rules are known to emit", but the input-validator warning key `audio.non_finite_sample` (`analysis_input_validator.dart:105`) is absent. Fail-safe today (an absent key drops any args, never forwards them) — if that warning ever gains an argument, it would be silently dropped, not leaked. | Add the key with an empty allowed-arg set, or narrow the doc-comment to "arg-bearing keys". |
| NOTE-2 | NOTE | `share_card_builder.dart:93` | `ShareCardInsight.messageArgs` copies the domain insight's raw `messageArgs`, bypassing `_redactedMessageArgs` — no live sink today (`ShareCardContent` has no production consumer yet), and the values are upstream-safe regardless, but the bypass means the card model itself isn't independently redaction-safe. | When a future round renders/shares the card, route its args through the same allowlist rather than trusting "upstream is safe" a second time. |
| NOTE-3 | NOTE | `delete_analysis_use_case.dart:60` | `await _cache.invalidate(documentId)` is unguarded after a successful repository delete — a no-op today, but when R28 wires a real cache, a throwing invalidate would propagate uncaught instead of surfacing as a typed failure, and could in principle leave a derived readable copy behind. | R28 must wrap/order the cache call so a cache failure still returns a typed `AppResult.failure`, not an uncaught throw. |
| NOTE-4 | NOTE | `share_service.dart:112-132` | `shareExportFile` unconditionally deletes whatever `File` it is handed — a future caller passing a non-disposable path would lose it post-share. Also, if `file.exists()`/`file.delete()` itself throws inside `finally`, that exception propagates from `ExportAnalysisUseCase.share()` uncaught (the share call is outside that method's own try/catch). | Consider asserting the path is under the injected temp directory, and swallow `finally`-cleanup errors so cleanup can never mask or raise past the caller. |
| NOTE-5 | NOTE | `analysis_export_codec.dart` decode path | Decode is fail-closed against non-finite doubles and unknown enum names, but list decode has no length cap. No untrusted decode consumer exists yet (only the round-trip test decodes). | If a future round imports third-party export JSON, add a list-length cap and re-run redaction on import rather than trusting the source. |

An out-of-scope observation, not a finding against this round: unchanged R21
`repository.delete` writes the filtered index before deleting the document
file, so a `FileSystemException` on the file delete could in principle
orphan a file on disk — it stays unreadable via `getById`/cache either way,
and the code path is untouched by E06-R27.

## Bottom line

Every string that can leave the device through the export traces to a fixed
enum, a catalog id, a machine failure code, a numeric string, an
engine-generated structured id, or a timestamp — no user- or
attacker-controlled free text reaches the export, and the message-argument
allowlist fails closed rather than open. Confidence-marking, temp-file
cleanup on both outcomes, deletion honesty, no-network, no-new-permissions,
and the additive-only `ShareService` extension all hold under independent
re-derivation. **APPROVED** — merge-clear from a security/privacy standpoint;
the five NOTEs are follow-up hygiene for when this round's surfaces get a
live caller (R28 cache, a future card renderer), not blockers today.
