# Content catalog — pedagogical release readiness (E12-R21)

- **Kör:** `E12-R21` · **ADR:** [0485](../adr/0485-content-catalog-inventory-and-pedagogical-readiness-contract.md)
- **Leltár:** [`docs/content/catalog-inventory.yaml`](catalog-inventory.yaml)
- **Validátor:** `python3 tool/validate_content_catalog.py --inventory docs/content/catalog-inventory.yaml --today YYYY-MM-DD`
- **Mérve:** 2026-09-01, `content_package_version: "2026.09.01"`, valós fán kilépési kód **0**.

Ez a riport a MÉRT állapotot mondja ki — nem javít (ADR 0485 D7). Minden szám
ebben a dokumentumban a leltár és a `tool/validate_content_catalog.py`
kimenete, nem becslés.

## 1. A tartalom három forrásból áll

| Forrás | Hol | Elemszám | Készség-szótár | Locale-felület |
|---|---|---|---|---|
| Practice Engine | `lib/features/practice/data/builtin_practice_catalog.dart` | 10 `PracticeDefinition` (8 beginner, 2 intermediate) | szabad `skillTags` — 24 egyedi érték | `titleKey` + `descriptionKey` → ARB |
| Tutor knowledge | `assets/tutor_knowledge/manifest.json` | 10 dokumentum (5 téma × 2 locale) | zárt `KnowledgeSkill` enum (5 érték) | a manifest `locale` mezője |
| Legacy Learn leckék | `lib/features/learn/model/lesson.dart` (`Lessons.all`) | 16 lecke (6 beginner / 6 intermediate / 4 advanced) + `Lessons.firstWin` a kurrikulumon kívül | nincs saját címke | `Lesson.name` — beégetett angol |

**Dalpélda-tartalom a fán NINCS.** `assets/` alatt kizárólag `fonts`, `ml`,
`tutor_knowledge` és `tutor_prompts` (az utóbbi hat fájl modell-bemenet, nem
tanulói tartalom) — ez üres halmaz, nem hiányzó mérés: az SDD „dalpéldák"
pontja triviálisan, tartalom hiányában teljesül.

A Practice Generator katalógusa hívó-táplált (`PracticeCatalogReader`
implementáció a fán nincs), ezért a törött-hivatkozás mérés (alább, §3) a
SZÁLLÍTOTT hivatkozás-halmazon fut (`LegacyMappingTable.builtIn`), nem egy
generátor-futás kimenetén (ADR 0485 D2/R2).

## 2. Négy pedagógiai-út invariáns — mind ZÖLD

A `test/tooling/content_catalog_test.dart` A4 csoportja méri közvetlenül a
szállított struktúrákon (`Lessons`, `LessonProgressController`,
`SkillTaxonomy`), nem egy új út-fájlon (ADR 0485 D5):

1. `Lessons.all` nehézség-sorrendje monoton nem csökkenő (beginner → intermediate → advanced).
2. `Lessons.byDifficulty(beginner)` mind a 6 eleme elérhető a tier első eleméből az `isUnlocked` láncon.
3. `Lessons.nextAfter('first-win') == Lessons.all.first`; minden nem-utolsó lecke után nem-`null` a következő; az utolsó után `null`.
4. A leltár `skill_graph:` blokkja az `ai_tutor` `SkillTaxonomy.initial` mind a 18 csomópontját és előfeltételét tartalmazza.

## 3. Referencia-épség — nulla törött hivatkozás

- `LegacyMappingTable.builtIn` mindhárom bejegyzése (`first-strums` →
  `chord.gMajor`, `two-chord-change` → `chord.cMajor`, `eighth-drive` →
  `chord.dMajor`) létező `Lessons.all` lecke-azonosítóra mutat.
- A tutor-knowledge manifest mind a 10 `sourcePath`-a létező fájl
  (`assets/tutor_knowledge/{en,hu}/*.json`).

## 4. Készség-szótár-eltérés — rögzített tény, nem javítandó hiba (R3)

A `LegacyMappingTable.builtIn` `chord.gMajor|cMajor|dMajor` azonosítói
**egyike sem** eleme az `ai_tutor` `SkillTaxonomy.initial` 18 csomópontjának
(`chord.shapeClarity`, `chord.changeSpeed`, `chord.progressionAccuracy`,
`chord.barreFoundation`, …). A leltár `skill_vocabularies.legacy_mapping_table`
blokkja ezt a szótárt a saját, forrásonként deklarált halmazaként rögzíti
(ADR 0485 D4) — egyesített taxonómia bevezetése ennek a körnek NEM feladata.

## 5. GA-blokkolók — a `known_exceptions:` blokk

Két, MÉRT locale-hiány landol itt (ADR 0485 D3/D7) — mindkettő a kör tilos
zónájában javítható (`lib/l10n/**` illetve `lib/features/learn/**`), ezért
NEM javítás, hanem nevesített, owner+lejárat-köteles kivétel:

### 5.1 `practice-catalog-description-key-missing-both-locales` — **GA-blokkoló**

Mind a 10 `practiceCatalog*Description` ARB-kulcs (a beépített gyakorlat-
katalógus `descriptionKey`-e) hiányzik **mind** `lib/l10n/app_en.arb`, **mind**
`lib/l10n/app_hu.arb` alól — miközben a hozzájuk tartozó mind a 10
`practiceCatalog*Title` kulcs mindkét locale-ban feloldható. A hiba ma
latens (`practice_mode_card.dart` csak a `titleKey`-t oldja fel), de a
`descriptionKey` a `PracticeDefinition` szerződése szerint feloldható
ARB-kulcs kell legyen. **Owner:** `strumsight-content`. **Expiry:**
`2026-12-31`.

### 5.2 `learn-lesson-name-hardcoded-english` — **GA-blokkoló**

`Lesson.name` (`lib/features/learn/model/lesson.dart`) mind a 16
`Lessons.all` bejegyzésen és a `firstWin`-en egy sima, beégetett angol
sztring — nincs ARB-indirekció, nincs `hu` felület. **Owner:**
`strumsight-content`. **Expiry:** `2026-12-31`.

Mindkét kivétel a leltár `known_exceptions:` blokkjában szerepel
`owner:`+ISO `expiry:` mezővel; a validátor mindkettőt fail-closed méri
(`exception_missing_owner`, `exception_missing_expiry`, `expired_exception`
— L566 ellenszere).

## 6. Mérce

```bash
tools/round-gate.sh test/tooling/content_catalog_test.dart
python3 tool/validate_content_catalog.py --inventory docs/content/catalog-inventory.yaml --today 2026-09-01
```

A valódi-sértés próbák tényleges kimenete: a kör-brief §10 (Implementation
handoff) dokumentálja mindkét mutáció pontos parancsát és kilépési kódját.
