# E03-R08 — Review

Brief: `docs/rounds/e03-r08-persistent-v2-migration.md`
Diff: `git diff origin/main...codex/e03-r08-persistent-v2-migration`
Reviewer: Codex / GPT-5.6 Terra
Date: 2026-08-02
Verdict: APPROVED

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

The prior F1 BLOCKER is closed by the merged structural-codec heal
(`c2707c1`, included in this branch through `origin/main`). The same isolated
review now exercises the actual `FileSongRepository` read-back path and
completes normally; the migration parity guard remains strict.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Üres, egy- és többdalos storage determinisztikusan migrálható | ✅ | `song_storage_migrator_test.dart`: empty, single-record and multi-record restart cases; isolated migration tests: 10 pass, 1 explicit skip. |
| 2 | Write/read-back hiba utáni restart nem veszít és nem duplikál | ✅ | `song_storage_migrator_test.dart`: `mid-run write failure...` and `read-back parity failure...`; persistent checkpoint is re-opened in the restart path. |
| 3 | Corrupt rekord redacted recoveryt ad, a jó checkpoint megmarad | ✅ | `song_storage_migrator_test.dart`: `corrupt song record redacts recovery and keeps the good checkpoint`. |
| 4 | Setlist csak teljes song mapping után fut; missing ID unresolved | ✅ | `song_storage_migrator_test.dart`: setlist success, missing reference and failed-song guard cases. |
| 5 | Production wiring friss példányból visszaolvasható | ✅ | `song_storage_migrator_wiring_test.dart`: production provider → file marker → fresh provider container → completed no-op. |

## Scope-audit

The implementation diff is limited to the pre-flight allowlist: ADR 0117,
the R08 brief, three migration implementation files, provider wiring, and two
migration tests. This review report is the required independent-review
artifact. No prohibited feature internals, pipeline files, or CI files change.

## Independent probes

- Isolated clone: `/tmp/review-e03-r08-6xE3tM`, branch head `a88e447`.
- A throwaway mutation weakened `_hasStableParity` to compare only song ID and
  title. The required test
  `read-back parity rejects an altered document with the same id and title`
  failed as expected (`expected needsResume`, `actual completed`). The mutation
  was reverted with no remaining tracked diff.
- The original F1 scenario was re-run through the production provider and now
  passes because `SongDocumentCodec` preserves the full structural timeline;
  parity remains `actual == expected`, rather than accepting normalized loss.

## Gate evidence

| Gate | Independent result |
|---|---|
| format | ✅ `dart format --output=none --set-exit-if-changed lib test tool`: 706 files, 0 changed. |
| analyze | ✅ `flutter analyze lib/ test/ tool/`: no issues. |
| targeted tests | ✅ application/migration: 10 pass, 1 explicit skip; data/migration: 33 pass; songs: 49 pass. |
| architecture | ✅ `dart run tool/check_architecture.dart`: dependencies OK (12 allowlisted deviations). |
| round gate | ✅ `tools/round-gate.sh --result-json ... test/features/song_trainer/application/migration test/features/song_trainer/data/migration test/features/songs`: structured result `{outcome: pass, exit_code: 0}`. |
| CI full suite, property, APK | Pending dispatch on the exact review head; merge remains prohibited until green. |

## Merge decision

The review contains no open BLOCKER or MAJOR. Dispatch CI for the exact branch
head, verify its `headSha`, and merge only after the full suite, randomised
property gate, and APK build are green.
