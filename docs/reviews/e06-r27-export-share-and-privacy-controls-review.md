# E06-R27 — Independent review

- **Review base:** `6e13e635`
- **Reviewed head:** `15363b51` (rebased onto `origin/main` `e12c3ab3`; content-identical
  to the original correction commit `524397de` — rebase replayed cleanly with
  zero conflicts, confirmed via `git merge-tree`)
- **Scope audit:** PASS — `tools/scope-audit.py --repo <isolated clone> --brief
  docs/rounds/e06-r27-export-share-and-privacy-controls.md --base 6e13e635` →
  `Legacy scope audit OK (6e13e635..524397de23f1, 22 changed path(s), 2
  generated/ignored)`. The 2 generated/ignored paths are this review file and
  the security review file (standing exemption, `GENERATED_IGNORED_PREFIXES`).
- **Independent gate:** PASS — re-run by hand in an isolated `/tmp` clone
  (`/tmp/review-e06-r27`, not the shared working tree), fresh `flutter pub get`
  + `flutter gen-l10n` via `tools/prepare-flutter-generated.sh` first:
  `tools/round-gate.sh test/features/audio_analysis test/property test/app
  test/features/share` → format ZÖLD, analyze ZÖLD, all four test targets
  ZÖLD, architecture ZÖLD, secrets ZÖLD, l10n ZÖLD. Full log:
  `/tmp/review-e06-r27-gate.log`.
- **Verdict:** APPROVED.

## Summary

BLOCKER: 0 (1 fixed) · MAJOR: 0 (2 fixed) · MINOR: 0 · NOTE: 1

## Prior findings — closure verification

All three findings below were raised against head `e4b2bde5` and are closed
by the correction commit (`524397de`, rebased to `15363b51`). Each was
verified against the corrected code and its test, not accepted on the
implementer's self-report.

### F1 — was BLOCKER — export allowlist open through message arguments — FIXED

- **File:** `lib/features/audio_analysis/domain/export/redaction_policy.dart:11-31,50-60`
- **Fix:** a finite `Map<String, Set<String>>` (`_allowedMessageArgKeys`) names
  every `messageKey` → allowed argument-name set this build's rules emit;
  `_redactedMessageArgs` drops anything not in that set and returns empty for
  an unrecognised `messageKey`. Closed by construction, not by enumerating
  dangerous names.
- **Verification:**
  - Read the corrected code — confirmed the allowlist is finite and the
    fallback for an unknown key/messageKey is empty, not passthrough.
  - `test/property/analysis_export_redaction_property_test.dart` group
    `message-argument allowlist boundary (review BLOCKER)`: 4 forbidden
    payloads (`importedFileName`, `rawAudioLike`, `deviceId`,
    `diagnosticString`) injected through **both** the insight and the warning
    branch (8 tests), plus a known-argument-name-on-unrecognised-messageKey
    case. All PASS against the corrected code.
  - **Sabotage probe (real-regression check, not just reading):** in a
    disposable third clone (`/tmp/probe-e06-r27`, deleted after use),
    temporarily reverted `_redactedMessageArgs` to `return args;` (the
    pre-fix passthrough) and ran
    `flutter test test/property/analysis_export_redaction_property_test.dart`
    directly — exactly the 9 message-argument-boundary tests went RED
    (`00:00 +7 -9: Some tests failed`), everything else stayed green. This
    proves the guard tests are load-bearing against this exact defect, not
    coincidentally green. Clone discarded after the probe.
- **Status:** FIXED (`15363b51`).

### F2 — was MAJOR — available metrics could be low-confidence facts on the card — FIXED

- **File:** `lib/features/audio_analysis/data/export/share_card_builder.dart:58-78`
- **Fix:** `_minPlainFactConfidence = 0.4` — a metric with `confidence < 0.4`
  is now marked `isDegraded: true` even when `status == available`.
  Independently confirmed this threshold matches the engine's own
  production floor, not an arbitrary new number:
  `lib/features/audio_analysis/engine/confidence/capability_thresholds.dart:9`
  (`minimumDegradedConfidence = 0.4`, also read at
  `capability_resolver.dart:289`) — measured, not assumed, per the pre-flight
  rule against trusting a doc-comment's claim.
- **Verification:** `test/features/audio_analysis/data/analysis_export_codec_test.dart`
  group `low-confidence available metric — boundary at 0.4` gives the
  brief's mandatory three-cell threshold treatment: strictly below (0.39,
  `isDegraded == true`), exactly on (0.4, `isDegraded == false` — matches the
  code's strict `<`), strictly above (0.41, `isDegraded == false`). A
  `CapabilityStatus.unavailable` metric is still excluded entirely by
  `_isPublishable` (never a value on the card, unchanged from the first
  pass).
- **Status:** FIXED (`15363b51`).

### F3 — was MAJOR — write failure could strand a redacted temp export — FIXED

- **File:** `lib/features/audio_analysis/application/export_analysis_use_case.dart:62-90`
- **Fix:** `share()` now wraps directory creation and the write itself in its
  own `try`/`catch`; on failure it deletes whatever partial file resulted and
  returns a typed failure **before** `ShareService.shareExportFile` is ever
  called. Once the write succeeds, that method's own `try`/`finally` (in
  `lib/features/share/share_service.dart:112-132`, the H3 self-heal's
  additive method) owns deletion on both the share-success and share-failure
  outcomes. Together the two cover the file's entire lifetime, not just the
  share step.
- **Verification:**
  - `export_analysis_use_case_test.dart`: forced write failure (`fileWriter`
    throws before writing) → `result.isFailure`, zero calls to
    `shareExportFile`, temp dir empty; a second cell forces a **partial**
    write (bytes land, then throws) → temp dir still empty afterward — the
    two cells the review asked for (full write failure, partial write
    failure) are both present, not just one.
  - `share_service_test.dart` exercises the **real** `shareExportFile`
    against a mocked `dev.fluttercommunity.plus/share` platform channel
    (not a fake) — both the success and the `PlatformException` path delete
    the file, proving the production cleanup contract itself, independent of
    the use-case-level tests.
- **Status:** FIXED (`15363b51`).

## Acceptance criteria (brief §6)

| # | Criterion | Met | Evidence |
|---|---|---|---|
| 1 | Allowlist-redaction property | ✅ | `analysis_export_redaction_property_test.dart` — 200 randomized trials, key-set-difference assertion |
| 2 | New-field leak probe | ✅ | same file, `new-field leak probe` test — unknown `CapabilityReport.details` key never appears |
| 3 | Forbidden content matrix — 5 cells | ✅ | same file, `forbidden content matrix — five cells` group: raw PCM, imported filename, device id, internal stage-timing, Lab decoder diagnostics |
| 4 | Confidence-marking — 2 cells | ✅ | `analysis_export_codec_test.dart` `ShareCardBuilder confidence marking` group; `unavailable` excluded by `_isPublishable`, `degraded`/low-confidence marked via `isDegraded` |
| 5 | Preview gate (0→1 share call) | ✅ | `export_analysis_use_case_test.dart` (`preview()` never calls share) + `analysis_export_screen_test.dart` widget test `preview gate — the share call count stays 0 until confirm is tapped` |
| 6 | Temp-file cleanup — success and failure, 2 cells | ✅ | `share_service_test.dart` (real method, both outcomes) + `export_analysis_use_case_test.dart` (forced/partial write failure) |
| 7 | Deletion completeness — 5 cells | ✅ | `delete_analysis_use_case_test.dart`: document file gone (a), index entry gone (b), cache invalidated (c), `getById` fails/null (d), audio file gone (e) — plus a repository-failure short-circuit test |
| 8 | No network | ✅ | `analysis_export_codec_test.dart` `no network import` — source-scan across all 8 new domain/data/application/presentation files for `dio`/`http`/`core/network` |
| 9 | JSON-schema stability, byte-identical round-trip | ✅ | `analysis_export_codec_test.dart` `round trip: decode(encode(x))` + explicit `exportSchemaVersion` field test |
| 10 | UI: categories not raw JSON, hu/en parity, 320px/textScale 2.0 no overflow | ✅ | `analysis_export_screen_test.dart`: category-label test, locale-parity test, `overflow matrix` test at 320×800/scale 2.0 |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs**. `tools/scope-audit.py`
`OK`, 22 changed paths (20 declared in the brief's `allowed_paths` +
`docs/adr/0247-...md` and `docs/rounds/e06-r27-...md` itself, both expected —
the ADR is the round's own kötött architekturális döntés artefaktuma and the
brief file is explicitly listed in `allowed_paths`), 2 generated/ignored
(the two review report files, standing exemption).

## Architecture + product boundaries (AGENTS.md §5/§6)

- `RedactionPolicy.apply` only reads named fields off `AnalysisDocument` —
  never iterates `CapabilityReport.details` or forwards `provenance`/
  `AnalysisInputSummary.sourceName`/`fingerprint`. Confirmed by reading the
  full method body (no loop over an open-ended map survives outside the
  message-arg allowlist path, which is itself now closed per F1).
  `AnalysisExportCodec`'s own key set is independently declared in the
  property test (`_allowedKeys`) and diffed against actual output — a
  codec change that adds an unreviewed key fails that test, not just this
  reading.
- `ShareService` product boundary honoured: exactly one new public method
  (`shareExportFile`), `shareCard`/`shareImage`/`shareText` unchanged in
  signature and body (confirmed by diff — only an addition, no edits to the
  three existing methods); `share_service_test.dart` includes an explicit
  compile-shape guard for this.
- No `dio`/`http`/`core/network` import anywhere in the new files (own
  reading + the codec test's source-scan, which is a real regression guard,
  not a one-time check).
- Resource lifecycle: the temp export file's owner is unambiguous at every
  stage — `ExportAnalysisUseCase.share` owns it until the write succeeds,
  `ShareService.shareExportFile` owns it from a successful write onward,
  `try`/`finally` on the latter guarantees release on both outcomes.
- `DeleteAnalysisUseCase` calls `_repository.delete` first and short-circuits
  cache/audio port calls on failure (verified by the dedicated
  `_FailingRepository` test) — no partial-delete state where the index
  updates but cache/audio don't get a chance to run in the success path, and
  no cache/audio touch on a failed document delete.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (implementer, brief §10) | Ellenőrizve (reviewer, saját futtatás) |
|---|---|---|
| format | ZÖLD | ✅ ZÖLD (isolated `/tmp` clone) |
| analyze | ZÖLD | ✅ ZÖLD |
| test test/features/audio_analysis | ZÖLD | ✅ ZÖLD |
| test test/property | ZÖLD | ✅ ZÖLD |
| test test/app | ZÖLD | ✅ ZÖLD |
| test test/features/share | ZÖLD | ✅ ZÖLD |
| architecture | ZÖLD (12 allowlisted deviations, unchanged) | ✅ ZÖLD |
| secrets | ZÖLD | ✅ ZÖLD |
| l10n parity | ZÖLD | ✅ ZÖLD |
| CI (teljes suite + property + APK/full-gate) | pending dispatch on rebased head | — dispatch happens as part of merge flow, exact-SHA on `15363b51` |

## Notes

- **NOTE:** `fileNameGenerator` on `ExportAnalysisUseCase` is injectable and
  the injected function's output is not itself validated for path
  separators. Not exploitable today (the default generator is a fixed-length
  hex string, and the only caller uses the default), but if a future round
  wires a caller-controlled name in, it should constrain or reject
  separators rather than trust the injected function. Carried over from the
  first pass; not new. Non-blocking.

## Merge-döntés

ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge.
Ezen a fejen (`15363b51`) mindkét feltétel teljesül a review oldaláról; a
CI-exact-SHA dispatch és a squash-merge az orchestrátor következő lépése.
