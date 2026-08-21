# E08-R17 — Review

Brief: `docs/rounds/e08-r17-daily-quest-generator.md`  
Diff: `6e4dba07...6e5b7193`  
Reviewer: független Codex / `gpt-5.6-sol` · Dátum: 2026-08-21  
Verdikt: **CHANGES REQUIRED**

## Összegzés

BLOCKER: 0 · MAJOR: 2 · MINOR: 0 · NOTE: 1

A production implementáció scope-ja és dependency-határa helyes, az izolált
round-gate 6/6 zöld. Az előírt `Random()` és fordított kamera-szűrés mutációk
célzottan pirosak. Két másik, contractot sértő mutáció azonban változatlanul
zöld maradt: a capability-tengelyek összekötése és a shipping default
katalógus teljes kiürítése. A merge F1/F2 tartós regressziói nélkül tilos.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Teljes snapshot determinisztikus, kipinnelt seed | ✅ | 100 iteráció + két golden FNV kulcs; `Random()` mutáció piros |
| A2 | 1–3 elem és legalább egy short | ✅ | 0/1/3/4 cellák és immutability cella zöld |
| A3 | Kamera/fiók/felhő külön fail-closed | ❌ | all-false cella zöld, de kamera→account mutáció is zöld (F1) |
| A4 | Nincs permission/gateway hívás | ✅ | csak `dart:convert` és gamification-internal importok; nincs plugin/network |
| A5 | Planned rest optional + rest-eligible | ✅ | A5 cella zöld |
| A6 | Terv érintetlen | ✅ | scope-audit 5/5 allowed, nincs practice-generator diff/import |
| A7 | Üres/új/hiányzó terv fallback | ✅ | A7 cella zöld |
| A8 | Seed dokumentált | ✅ | `dailyQuestSeedMaterial` + FNV doc-comment és brief §10 |

## Scope-audit és jelzés

A wrapper-jelzés: `status=done`, `continuations=0`, `scope_audit=ok`,
`scope_audit_base=6e4dba07`, `scope_audit_changed=5`. A jelzett
`dirty_files=1` kivizsgálásakor mind az implementer-klón, mind az izolált
review-klón `git status --short` kimenete üres volt.

Kézi audit az izolált klónban:

```text
Legacy scope audit OK (6e4dba0724ce..6e5b719342cd, 5 changed path(s), 0 generated/ignored)
```

## Megállapítások

### F1 — MAJOR — Az availability-teszt nem különíti el a capability-tengelyeket

- **Fájl:** `test/features/gamification/application/daily_quest_generator_test.dart:97-111`
- **Probléma:** az A3 cella mindhárom availability flaget egyszerre állítja
  `false`-ra. Eldobható mutációval a kamera ágat
  `snapshot.cameraAvailable` helyett `snapshot.accountAvailable` értékre
  kötöttem; a célzott suite továbbra is 6/6 zöld lett.
- **Hatás:** egy későbbi wiring-regresszió kameraquestet engedhet kamera nélkül,
  ha a fiók elérhető; a jelen mérce ezt nem fogja meg.
- **Kötelező javítás:** capabilitynként külön cella, ahol pontosan az adott
  tengely false, a másik kettő true; az adott quest kizárt, a másik kettő
  elérhető marad. A shipping default katalógust használó út is mérje ezt.
- **Ellenőrzés:** kamera→account, account→cloud és cloud→camera mutációk
  egyenként a saját cellájukat pirosra viszik.
- **Státusz:** OPEN.

### F2 — MAJOR — A shipping default katalógust egyetlen teszt sem méri

- **Fájl:** `test/features/gamification/application/daily_quest_generator_test.dart:181-239`
- **Probléma:** minden teszt a production katalógust lemásoló `_catalog()`
  helperrel fut; `defaultDailyQuestCatalog()` nincs meghívva. Eldobható
  mutációval a production factoryt `const DailyQuestCatalog.empty()`
  eredményre cseréltem, és a suite változatlanul 6/6 zöld maradt.
- **Hatás:** a szállított katalógus eltűnhet vagy capability/rest/short
  metaadatai felcserélődhetnek úgy, hogy az összes köri gate zöld marad.
- **Kötelező javítás:** közvetlen production-catalog contract teszt stabil
  ID-kra, egyediségre, short/rest entryre és a kamera/fiók/felhő exact
  capability-hozzárendelésére; legalább egy generator-cellát is a default
  factoryval futtass.
- **Ellenőrzés:** a factory kiürítése és bármely capability-metaadat
  felcserélése célzottan piros.
- **Státusz:** OPEN.

### N1 — NOTE — A 64 bites FNV signed `int` goldenje runtime-contract

A két golden érték, köztük UTF-8 inputtal egy negatív signed eredmény,
egyértelműen rögzíti a jelen Dart VM szemantikát. A kör Android-first és a
CI VM-en fut; ha a generator később web shipping út lesz, külön cross-runtime
parity mérés indokolt.

## Gate-bizonyíték

Izolált klón: `/tmp/review-e08-r17`, exact `6e5b7193`.

| Gate | Eredmény |
|---|---|
| scope-audit | OK, 5/5 implementer path allowed |
| format | 1767 fájl, 0 változás |
| analyze | No issues found |
| célzott teszt | 6/6 zöld |
| architecture | OK, 12 allowlisted deviation |
| secrets | 3169 fájl, 0 finding |
| l10n | 1532 message parity |
| előírt FNV mutáció | PIROS az A1 cellán |
| előírt kamera-negálás | PIROS az A3 cellán |
| kamera→account mutáció | hibásan ZÖLD, F1 |
| default katalógus kiürítése | hibásan ZÖLD, F2 |

## Merge-döntés

Az ADR 0052 szerint F1 és F2 nyitott MAJOR lelet mellett merge tilos. A
következő lépés egy Terra javító kör ugyanazon a branchen, majd friss izolált
re-review és exact-SHA CI.
