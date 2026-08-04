# E03-R15 — Review

Brief: `docs/rounds/e03-r15-song-library-import-ui.md`  
Diff: `git diff main...codex/e03-r15-song-library-import-ui`  
Reviewer: Codex / GPT-5.6 Terra (orchestrator fallback) · Date: 2026-08-04  
Verdict: CHANGES REQUIRED

## Summary

BLOCKER: 0 · MAJOR: 3 · MINOR: 0 · NOTE: 0

The independent review used a fresh `/tmp/review-e03-r15` clone at
`6c9dccb`. Its generated Flutter prerequisites were restored with
`tools/prepare-flutter-generated.sh`; the brief's exact `round-gate.sh`
command then passed. The first attempt accidentally invoked the clone's gate
script from the shared checkout, and therefore looked for a non-existent test
there; it was discarded and rerun from the clone root.

## Acceptance criteria

| # | Criterion | Met | Evidence |
|---|---|---|---|
| 1 | Empty/loading/error and index-only list | Partial | Controller test proves one summary list/read and no document reads; screen has empty/loading/error states. |
| 2 | Search/filter/favorite and deterministic dedupe | No | Search and local star exist, but no source-filter or sort control is rendered (F2). |
| 3 | Import state/effect combinations | No | A real picker source cannot be reopened for probe then import (F1). |
| 4 | Native export and fatal preview has no confirm | Partial | `NativeJsonExporter` is called on explicit export; fatal button is disabled. Preview mandatory file size cannot be displayed with the allowed contracts (F3). |
| 5 | HU/EN, 200% scale, semantics/focus, route re-entry | No | Localized strings and some semantics exist, but the required comprehensive tests are absent. |

## Scope audit

`origin/main...6c9dccb` changes only the brief's human §4 paths, including the
already-approved ADR/pre-flight artifacts. No model diff escapes the router
allowlist. This report path is explicitly allowed.

## Findings

### F1 — MAJOR — picker source is not reopenable

- **File:** `lib/features/song_trainer/data/importers/file_picker_adapter.dart:43-54`
- **Problem:** `fromPlatformFile` closes over one `PlatformFile.readStream` and
  returns that same stream from every `ImportSourceFile.openRead()` call.
  The import controller probes it first and later imports it (`SongImportController`
  calls the source on both paths); a normal single-subscription plugin stream
  consequently throws `Bad state: Stream has already been listened to` before
  commit.
- **Evidence:** An isolated, disposable test constructed `PlatformFile` with a
  `StreamController<List<int>>.stream`, consumed `openRead()` twice, and the
  second read failed with exactly that exception. The temporary test was
  removed before this report.
- **Required fix:** Preserve the port's reopenable contract with a source that
  produces a fresh stream on each read (without placing a platform object or
  raw bytes in presentation/application state), and retain a two-read
  regression test.
- **Status:** OPEN.

### F2 — MAJOR — required filter and sort controls are absent

- **File:** `lib/features/song_trainer/presentation/screens/song_library_screen.dart:52-70`
- **Problem:** The screen renders only a text search box. It copies the current
  `sourceType`, `favoritesOnly`, and `sort` values into each new query, but
  provides no control that can change the source filter or sort order.
- **Impact:** It fails the brief's search/filter/favorite acceptance criterion
  and the SDD §27.1 filter/sort UI requirement despite the controller having
  query fields for them.
- **Required fix:** Add localized, accessible filter and sort controls with
  widget tests proving both values alter the visible index-summary list.
- **Status:** OPEN.

### F3 — MAJOR / H3 — preview cannot display mandatory file size within the approved scope

- **Files:** `lib/features/song_trainer/application/import/import_preview.dart:5-16`,
  `lib/features/song_trainer/application/import/song_import_controller.dart:96-101`
- **Problem:** SDD §27.3 requires the preview to show file name and size. The
  source has `byteLength`, but the preview state retains only `displayName`,
  format, warnings and parts. The preview screen therefore has no truthful
  size to render.
- **Impact:** Correcting this requires adding the size to `ImportPreview` and
  copying it in the controller, but both files are outside the E03-R15 human
  and router `allowed_paths` lists.
- **Required fix:** Do not bypass the scope boundary. A self-heal/pre-flight
  must explicitly authorize these two application-contract owners plus their
  focused tests before a repair can begin.
- **Status:** OPEN — mandatory halt condition H3.

## Gate evidence

| Gate | Claimed | Independently checked |
|---|---|---|
| format | green | green in `/tmp/review-e03-r15` |
| analyze | green | green in `/tmp/review-e03-r15` |
| targeted tests + architecture | green | green in `/tmp/review-e03-r15` |
| CI full suite + property + APK | [run 30866162283](https://github.com/wolfcasaba/strumsight/actions/runs/30866162283) | in progress at review time, not merge evidence |

## Merge decision

Merge is prohibited: F1–F3 are OPEN MAJOR findings, and F3 requires a scope
expansion prohibited to this round (H3). No router resume is valid until a
self-heal authorizes the measured application-contract paths.
