# E08-R17 — Review

Brief: `docs/rounds/e08-r17-daily-quest-generator.md`  
Diff: `6e4dba07...a8980cab`  
Reviewer: független Codex / `gpt-5.6-sol` · Dátum: 2026-08-21  
Verdikt: **CHANGES REQUIRED**

## Összegzés

BLOCKER: 0 · MAJOR: 1 · MINOR: 0 · NOTE: 1

A `a8980cab` Terra javítócommit közvetlen shipping-katalógus contractot és
három availability-cellát adott; az izolált round-gate 9/9 zöld, a default
katalógus kiürítése most célzottan piros, tehát F2 lezárult. F1 azonban nyitva
maradt: az `account → cloud` hibás kötés továbbra is zöld, mert a négy eligible
candidate közül a háromelemes limit épp az account questet vágja le. Ez nyitott
MAJOR a Codex/Terra javító kör után, ezért H4 és merge-tilalom.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Teljes snapshot determinisztikus, kipinnelt seed | ✅ | 100 iteráció + két golden FNV kulcs; `Random()` mutáció piros |
| A2 | 1–3 elem és legalább egy short | ✅ | 0/1/3/4 cellák és immutability cella zöld |
| A3 | Kamera/fiók/felhő külön fail-closed | ❌ | három külön cella van, de az account→cloud mutáció zöld marad (F1) |
| A4 | Nincs permission/gateway hívás | ✅ | csak `dart:convert` és gamification-internal importok; nincs plugin/network |
| A5 | Planned rest optional + rest-eligible | ✅ | A5 cella zöld |
| A6 | Terv érintetlen | ✅ | scope-audit 5/5 allowed, nincs practice-generator diff/import |
| A7 | Üres/új/hiányzó terv fallback | ✅ | A7 cella zöld |
| A8 | Seed dokumentált | ✅ | `dailyQuestSeedMaterial` + FNV doc-comment és brief §10 |

## Scope-audit és jelzés

A kezdeti wrapper-jelzés: `status=done`, `continuations=0`, `scope_audit=ok`,
`scope_audit_base=6e4dba07`, `scope_audit_changed=5`. A jelzett
`dirty_files=1` kivizsgálásakor mind az implementer-klón, mind az izolált
review-klón `git status --short` kimenete üres volt.

Kézi audit az izolált klónban:

```text
Legacy scope audit OK (6e4dba0724ce..6e5b719342cd, 5 changed path(s), 0 generated/ignored)
```

A javító wrapper `status=done`, `continuations=0`, `scope_audit=ok`,
`scope_audit_base=a5de4ea5`, `scope_audit_changed=1`. Az izolált re-review
auditja a fixer fázisra 1/1 engedélyezett útvonalat, a teljes implementer
ágra 7 változott útvonalból 2 generated/ignored review-jelentést és 0
sértést mért.

## Megállapítások

### F1 — MAJOR — Az availability-teszt nem különíti el a capability-tengelyeket

- **Fájl:** `test/features/gamification/application/daily_quest_generator_test.dart:97-111`
- **Probléma:** az első review all-false cellája után a javító három külön
  shipping-catalog cellát adott, de mindegyik négy objective-et tesz eligible
  poolba a háromelemes limit előtt. Eldobható `account → cloud` mutációnál az
  account quest hibásan eligible, de a stabil rendezés a negyedik helyre teszi,
  ezért az account-unavailable cella továbbra is zöld.
- **Hatás:** egy későbbi wiring-regresszió kameraquestet engedhet kamera nélkül,
  ha a fiók elérhető; a jelen mérce ezt nem fogja meg.
- **Kötelező javítás:** a generator-mappingot axis-onként olyan izolált
  candidate poollal mérd (short local + pontosan a vizsgált capability quest),
  ahol a max-3 truncation nem rejtheti el a hibásan eligible elemet. A
  shipping default metadata exact mappingját a már zöld F2 cella őrzi.
- **Ellenőrzés:** kamera→account, account→cloud és cloud→camera mutációk
  egyenként a saját cellájukat pirosra viszik.
- **Státusz:** OPEN az `a8980cab` javító kör után; H4.

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
- **Státusz:** FIXED (`a8980cab`). A production factory közvetlenül mért exact
  ID-, short-, rest- és capability-contractja zöld; a factory kiürítése a
  cellát pirosra viszi.

### N1 — NOTE — A 64 bites FNV signed `int` goldenje runtime-contract

A két golden érték, köztük UTF-8 inputtal egy negatív signed eredmény,
egyértelműen rögzíti a jelen Dart VM szemantikát. A kör Android-first és a
CI VM-en fut; ha a generator később web shipping út lesz, külön cross-runtime
parity mérés indokolt.

## Gate-bizonyíték

Első izolált klón: `/tmp/review-e08-r17`, exact `6e5b7193`. Javítás utáni
izolált klón: `/tmp/review-e08-r17-fix1`, exact `a8980cab`.

| Gate | Eredmény |
|---|---|
| scope-audit | OK, 5/5 implementer path allowed |
| format | 1767 fájl, 0 változás |
| analyze | No issues found |
| célzott teszt | első review 6/6; fixer re-review 9/9 zöld |
| architecture | OK, 12 allowlisted deviation |
| secrets | 3169 fájl, 0 finding |
| l10n | 1532 message parity |
| előírt FNV mutáció | PIROS az A1 cellán |
| előírt kamera-negálás | PIROS az A3 cellán |
| kamera→account mutáció | fixer után PIROS |
| account→cloud mutáció | fixer után hibásan ZÖLD, F1 nyitott |
| cloud→camera mutáció | fixer után PIROS |
| default katalógus kiürítése | fixer után PIROS, F2 zárt |

## Merge-döntés

Az ADR 0052 szerint F1 nyitott MAJOR lelet mellett merge tilos. Mivel a
nevesített Terra/Codex javító kör (`a8980cab`) után is nyitott maradt, az
ADR 0087 H4 megállási pont teljesül. További implementer-dispatch, CI vagy
merge ebben a sessionben nincs; a self-heal/humán folytatás reprodukciója az
F1 `account → cloud` mutációja.
