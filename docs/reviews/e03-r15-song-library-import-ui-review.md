# E03-R15 — Review

Brief: `docs/rounds/e03-r15-song-library-import-ui.md`
Diff: `git diff origin/main...heal/E03-R16-H2-1`
Reviewer: Codex / GPT-5.6 Terra (orchestrator fallback) · Date: 2026-08-04
Verdict: APPROVED

## Summary

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

The original R15 implementation was independently reviewed at `6c9dccb` and
correctly rejected with F1–F3. The E03-R16/H2 self-heal took the mandated
fallback path because the primary orchestrator quota was unavailable. Its
closure review used a fresh `/tmp/review-e03-r15-h2` clone at `c27aced`, not
the repair worktree.

The clone regenerated Flutter localization output, reran the brief's exact
`tools/round-gate.sh` command, and audited the full `origin/main...HEAD` diff.
Every changed path is in brief §4/`ai-router.allowed_paths`; the merge base
already contains the H3 scope revision for the two preview-contract owners.

## Closed findings

| Finding | Status | Evidence |
|---|---|---|
| F1 — source must be reopenable | CLOSED | `PlatformFilePickerAdapter.fromPlatformFile` buffers only at the data boundary and exposes a fresh stream per read. The regression feeds a real single-subscription `StreamController` and consumes `openRead()` twice. An isolated mutation replacing the stream factory with `Stream.empty` made that test fail (`Expected: [1, 2, 3]; Actual: []`), then the clean clone passed it. |
| F2 — source filter and sort controls | CLOSED | Accessible localized source and sort dropdowns update `SongLibraryQuery`. The widget regression filters MIDI to one visible summary, restores all sources, then proves title order with item positions. |
| F3 — truthful preview file size | CLOSED | `ImportPreview` now retains the source scalar `byteLength`, the controller transfers it, and the preview renders the localized byte count. Controller and preview-widget regressions assert the value. |

## Acceptance criteria

| # | Criterion | Evidence |
|---|---|---|
| 1 | Empty/loading/error and index-only list | Existing controller and screen tests in the exact gate; list remains summary-only. |
| 2 | Search/filter/favorite and deterministic dedupe | New source-filter/sort widget regression plus existing controller tests. |
| 3 | Import state/effect combinations | New two-read picker regression prevents probe→confirm failure; existing import-screen/controller tests cover operation states. |
| 4 | Native export and fatal preview has no confirm | Existing fatal-preview test remains green; new size assertion proves the mandatory metadata is displayed. |
| 5 | HU/EN, scale, semantics and re-entry | Existing route/screen tests and localized ARB additions are included in the exact gate. |

## Gate evidence

| Gate | Result |
|---|---|
| Fresh-clone format | green |
| Fresh-clone analyze | green |
| Fresh-clone targeted tests + architecture | green |
| Scope audit + `git diff --check` | green after this report's whitespace normalization |
| CI full suite, property gate, APK | pending exact final head dispatch |

## Merge decision

The local and isolated review gates are green and all previously blocking
findings are closed. Merge remains conditional on a successful exact-head
Build Android APK workflow (full Flutter suite, property gate and APK).
