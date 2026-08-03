# E03-R10 — Review

Brief: `docs/rounds/e03-r10-import-flow-security-boundary.md`
Diff: `git diff origin/main...codex/e03-r10-import-flow-security-boundary`
Reviewer: Codex / Terra (Claude-quota fallback) · Dátum: 2026-08-03
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Explicit, tesztelt state transitionök | ✅ | `song_import_state.dart:4-38`; integration test teljes phase-sorrendje |
| 2 | Failure/cancel alatt nincs record vagy workspace leak | ✅ | controller `:132-205`, `:253-293`; cancel- és workspace-tesztek |
| 3 | Retry új op-ID, régi callback nem ír | ✅ | controller `:225-229`, `:301-302`; valós-sértés próba lent |
| 4 | State-ben nincs nagy byte/platform object; warning/fatal külön | ✅ | state `:12-24`, preview `:4-28`; registry `:63-75` |
| 5 | Size/event/workspace/wall-time stabil kóddal | ✅ | `import_limits.dart`, registry `:63-104`, workspace `:54-64` |

## Scope-audit

Az `origin/main...branch` diff 14 fájlja a pre-flightban engedélyezett
implementation/test/brief/ADR útvonalakra esik. Ez a review-jelentés kötelező
governance-artefaktum; production vagy router/pipeline fájl nem változott.

## Próbatesztek és gate

- Friss `/tmp/review-e03-r10` klónban `flutter pub get && flutter gen-l10n`,
  majd a kötelező `tools/round-gate.sh test/features/song_trainer/application/import test/features/song_trainer/data/importers/import_workspace_test.dart` zöld: format, analyze, 6 application teszt, 3 workspace teszt, architecture.
- Valós-sértés próba: a controller `_isCurrent` őréből ideiglenesen kivettem
  az `identical(_operation, operation)` feltételt. A stale-callback teszt
  piros lett: várt `import-2`, kapott `import-1`. Az őr pontos visszaállítása
  után ugyanaz a teszt zöld; a review klón tiszta.
- Workspace traversal/symlink guard: a célzott teszt a `../` és symlink escape
  kísérletet kontrollált `ImportWorkspaceException`-nel elutasítja.

## Megállapítások

### F1 — NOTE — A R09 importer még in-memory, ezért a workspace előkészítő lifecycle-t mér

- **Fájl:** `lib/features/song_trainer/application/import/song_import_controller.dart:132-148`
- **Megfigyelés:** A natív JSON importer szándékosan in-memory contract, ezért
  a most létrejövő workspace-be még nem ír parser. A controller a lifecycle-t
  és a cleanupot már birtokolja.
- **Követés:** E03-R11 XML/MXL parserének a workspace API-t tényleges stagingre
  kell használnia; ez nem nyitott R10 lelet.
- **Státusz:** NOTE.

## Merge-döntés

Nincs nyitott BLOCKER vagy MAJOR. A merge az exact-head CI full suite +
randomizált property gate + APK sikerére, valamint a `main`-mozgás merge előtti
ellenőrzésére vár.
