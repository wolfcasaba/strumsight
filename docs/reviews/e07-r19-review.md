# E07-R19 — független review

**Dátum:** 2026-08-18  
**Reviewer:** Codex / gpt-5.6-terra (orchestrátor)  
**Implementer:** MiniMax, majd a kör korábbi javításai  
**Verdikt:** CHANGES REQUESTED

## Elvégzett mérések

- Jelzés: `.codex-round-status` = `done`, `head=0d505ca7`,
  `scope_audit=ok`. A review előtt a branch integrálta az aktuális
  `origin/main`-t: `3bff8967`.
- Scope-audit, izolált klónban, az implementáció előtti
  `04749442..0d505ca7` tartományon:
  `python3 tools/scope-audit.py --repo /tmp/review-e07-r19-current-RYaQoX
  --brief docs/rounds/e07-r19-local-plan-repository.md --base 04749442...`
  → `Legacy scope audit OK (7 changed path(s), 0 generated/ignored)`.
- Kötelező gate, izolált klónban:
  `tools/round-gate.sh test/features/practice_generator/data/local_repository_test.dart test/features/practice_generator/data/practice_plan_migrator_test.dart`
  → format, analyze, mindkét célzott teszt, architecture, secrets és l10n
  zöld.
- Eldobható valódi-sértés próba:
  `flutter test test/review_migration_probe_test.dart` → **piros**:
  `Expected: <1>; Actual: <0>`. A próbafájl a mérés után törölve lett.

## Leletek

| ID | Súlyosság | Hely | Lelet |
|---|---|---|---|
| M-01 | MAJOR | `lib/features/practice_generator/data/local/practice_plan_migrator.dart:115` | Az előző sémájú envelope nem migrálódik az aktuális sémára. |

### M-01 — a régi envelope verziója változatlan marad

Az ADR 0267 §6 és a brief A7 cellája szerint a `current - 1` sémaértéknek
fel kell migrálódnia az aktuális támogatott verzióra. A
`_migrateVxToCurrent` jelenleg változatlanul adja vissza az envelope-ot,
így a `migrateEnvelope({'schemaVersion': 0})` eredményében a verzió továbbra
is `0`, nem `1`. Ezt a fenti eldobható Flutter-teszt közvetlenül igazolta.

A meglévő `practice_plan_migrator_test.dart` ezt nem fogja meg, mert maga is
az elavult `0` értéket várja. Javítási irány: a v0→v1 lépés készítsen másolatot
és állítsa `schemaVersion`-t
`PracticePlanMigrator.currentSupportedSchemaVersion` értékre; a checksumot
csak akkor kell a cél-séma szerint újragenerálni, ha a v1 test átalakítja a
body-t. A regressziós teszt a visszaadott envelope aktuális verzióját mérje.

## Merge-döntés

M-01 nyitott MAJOR, ezért merge és CI-dispatch tilos. A kör korábbi
MiniMax- és Codex-javítási kerete a handoff szerint már elfogyott, ezért az
ADR 0087 H4 szerint emberi/pipeline-döntés szükséges a további javításhoz.
