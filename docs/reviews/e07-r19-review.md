# E07-R19 — független review

**Dátum:** 2026-08-18  
**Reviewer:** Codex / gpt-5.6-terra (orchestrátor)  
**Implementer:** MiniMax, majd a kör korábbi javításai  
**Verdikt:** APPROVED

## Elvégzett mérések

- Jelzés: `.codex-round-status` = `done`, `head=0d505ca7`,
  `scope_audit=ok`. A branch az újra-review előtt a jelenlegi `origin/main`-t
  konfliktus nélkül integrálta: `4e370ebc`.
- Scope-audit, izolált klónban, az eredeti implementációs tartományon:
  `python3 tools/scope-audit.py --repo /tmp/review-e07-r19-CwdeQ6/repo
  --brief docs/rounds/e07-r19-local-plan-repository.md --base 04749442`
  a `0d505ca7` implementációs HEAD-en → `Legacy scope audit OK (7 changed
  path(s), 0 generated/ignored)`. A review utáni javítás külön auditja
  `dce4f957..45395d9f` → `OK (2 changed path(s), 0 generated/ignored)`.
- Kötelező gate, izolált klónban:
  `tools/round-gate.sh test/features/practice_generator/data/local_repository_test.dart test/features/practice_generator/data/practice_plan_migrator_test.dart`
  → format, analyze, mindkét célzott teszt, architecture, secrets és l10n
  zöld.
- Eldobható regressziós próba:
  `flutter test test/review_migration_probe_test.dart` → **zöld**: egy v0
  envelope `schemaVersion`-je a jelenlegi `1`-re változik. A próbafájl a
  mérés után törölve lett.

## Leletek

## Acceptance criteria

| # | Állapot | Bizonyíték |
|---|---|---|
| A1 | ✅ | `local_repository_test.dart`: restart utáni aktív terv olvasás |
| A2 | ✅ | rekord-szintű korrupció- és checksum-cellák; a többi rekord olvasható |
| A3 | ✅ | hibás aktívmutató-írás után az előző aktív rekord olvasható |
| A4 | ✅ | ugyanaz az `OutcomeId` pontosan egyszer marad meg |
| A5 | ✅ | draft és aktív kulcsprefixek elkülönítettek |
| A6 | ✅ | régi revíziók korlátos kilakoltatása újraírás nélkül |
| A7 | ✅ | v0→v1 migráció, aktuális és `current + 1` cellák |
| A8 | ✅ | módosított checksum kontrollált hibát eredményez |

| ID | Súlyosság | Hely | Lelet |
|---|---|---|---|
| M-01 | MAJOR — FIXED | `lib/features/practice_generator/data/local/practice_plan_migrator.dart:115` | Az előző sémájú envelope immár az aktuális sémára migrálódik. |

### M-01 — a régi envelope verziója változatlan marad

Az ADR 0267 §6 és a brief A7 cellája szerint a `current - 1` sémaértéknek
fel kell migrálódnia az aktuális támogatott verzióra. A self-heal javítás
(`45395d9f`) másolatot készít, és a v0→v1 lépésben `schemaVersion`-t
`PracticePlanMigrator.currentSupportedSchemaVersion` értékére állítja. A
tartós regressziós teszt is ezt az `1` értéket várja; az eldobható, izolált
próba ezt közvetlenül ismét megmérte.

**Státusz:** FIXED (`45395d9f`).

## Merge-döntés

Nincs nyitott BLOCKER vagy MAJOR. A helyi gate és a két scope-audit zöld;
a merge továbbra is az exact-SHA CI (full suite, property és APK), Router CI
és a kötelező security review zöld eredményétől függ.
