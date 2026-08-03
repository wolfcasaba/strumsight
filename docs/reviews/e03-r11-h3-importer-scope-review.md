# E03-R11/H3 — Self-heal review

Brief: `docs/rounds/e03-r11-musicxml-mxl-importer.md`  
Diff: `origin/main...heal/E03-R11-H3-1` @ `745c10e`  
Reviewer: Terra fallback, isolated `/tmp/review-E03-R11-H3` clone  
Dátum: 2026-08-03  
Verdikt: **APPROVED, CI pending**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | A H3 két production ownerét az R11 scope engedi | ✅ | `tools/tests/test_epic3_brief_metadata.py::Epic3BriefMetadataTest.test_r11_scope_includes_measured_production_owners` |
| 2 | Közvetlen provider-wiring tesztútvonal is engedélyezett | ✅ | Ugyanaz a regressziós teszt; R11 §4 és `ai-router` metadata |
| 3 | Az implementer nem írhat normatív ADR-t | ✅ | R10/R11 TOML allowlistből az ADR-útvonalak eltávolítva; human scope-táblákban megmaradtak |
| 4 | A javítás nem lazít tesztet vagy gate-et | ✅ | A tesztek száma nőtt; `tools/round-gate.sh` és workflow-diff nincs |

## Scope-audit

Az izolált klónban futott `git diff --check origin/main...HEAD` zöld volt.
A változott utak: `HANDOFF.md`, `docs/LESSONS.md`, ADR 0120, az R10/R11
briefek és `tools/tests/test_epic3_brief_metadata.py`. Ezek mind az ADR 0112
self-heal dokumentációs/infrastruktúra jogosultságában vannak. Az R10
allowlist-egysoros javítása szükséges volt, mert a teljes router teszt a már
mainen levő tiltott ADR-utat pirosra jelezte; nem tágítja, hanem szűkíti a
modell írási jogát.

## Ejtett valódi-sértés próba

Az izolált klón R11 TOML allowlistjéből ideiglenesen eltávolítottam a
`lib/features/song_trainer/application/song_trainer_providers.dart` sort. A
célzott regresszió RED lett, és pontosan ezt a hiányzó utat jelentette.
A módosítás csak az eldobható review-klónban történt, a PR-branchet nem érintette.

## Gate-bizonyíték

| Gate | Ellenőrzött eredmény |
|---|---|
| `python -m pytest tools/tests -q` | ✅ 157 passed, 53 subtests passed (izolált klón) |
| `git diff --check origin/main...HEAD` | ✅ |
| Router CI, exact head `745c10e` | ⏳ PR #88 futása kötelező a merge előtt |

## Merge-döntés

A review-ban nincs nyitott BLOCKER vagy MAJOR. Merge csak a PR #88 exact-head
Router CI sikeres befejezése után engedélyezett.
