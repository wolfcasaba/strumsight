# E12-R21 — Content catalog és pedagógiai readiness

- **Státusz:** READY (pre-flight lefutva 2026-09-01, kód mérve: `main @ ca643908`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 21
- **Kör-azonosító:** `E12-R21`
- **Branch:** `sonnet-impl/e12-r21-content-catalog-and-pedagogical-readiness`
- **Előfeltétel:** `E12-R12` merge-elve (a fixture-manifest mintája adja a tartalom-manifest formáját)
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** `ADR 0485` — commitolva:
  [`docs/adr/0485-content-catalog-inventory-and-pedagogical-readiness-contract.md`](../adr/0485-content-catalog-inventory-and-pedagogical-readiness-contract.md).
  **Nem `0460`:** az előre kiosztott számot a `tools/round-slots.py reserve-adr --round E12-R21`
  atomi foglalója felülírta (`0485`) — a foglaló a lemezen lévő ÉS a már foglalt számok fölé
  megy, a `0460` pedig alatta van a vízszintjének. A mért ütközés-osztály (két munka ugyanazt a
  `0139`-et foglalta, `tools/tests/test_adr_numbering.py`) pontosan ez.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "content catalog exercise reference validation difficulty progression"` → **[ADR 0068](../adr/0068-practice-domain-model-contracts.md)** (score 3.00): Practice V2 domain contractok — validation-as-value, egész százalékok, kanonikus akkord-címkék. A tartalom-validáció ezt a MEGLÉVŐ szerződést használja mérceként, nem definiál másodikat.

## 0.0 Pre-flight revízió — MÉRT tények (Claude, 2026-09-01, `main @ ca643908`)

**Miért nem `content/catalog/`.** A SDD Kör 21 `content/catalog/` fát ír elő. A fán a tartalom
NEM egy helyen él, és `content/` fa nincs. Egy párhuzamos tartalom-fa bevezetése kettős
igazságot csinálna. A kör ezért **leltárat és validátort** ad a MEGLÉVŐ forrásokra, nem
költöztet tartalmat.

**Visszakeresés (ADR 0312, szűkítve → teljes):**
`--corpus lessons,halts,adr` → **[ADR 0068](../adr/0068-practice-domain-model-contracts.md)**
(validation-as-value, kanonikus címkék), **[ADR 0376](../adr/0376-ui-baseline-inventory-contract.md)**
(a leltár-mint-tükör minta); `--corpus lessons,halts` → **[L566](../LESSONS.md#l566)** (a kézzel
írt sor-parszer alapértelmezésben fail-OPEN: ami nem illeszkedik, az nem hibás, hanem nem
létezik — a reviewer 4-szóközös sorral 15/15 zöldet ért el), **[L116](../LESSONS.md#l116)** (az
ellenőrzéshez szükséges adat megvolt, az ellenőrzés hiányzott). Teljes korpusz → a meglévő
`builtin_practice_catalog_test.dart` és `knowledge_manifest_test.dart` cellái. Mindhárom
találat beépítve: D1 kétirányú tükör + `unparsable_line`, D4 kétirányú szótár-mérés.

### R1 — A tartalom HÁROM forrásból áll, nem kettőből

| Forrás | Hol | Mennyi | Készség-szótár | Nehézség | Locale-felület |
|---|---|---|---|---|---|
| Practice Engine | `lib/features/practice/data/builtin_practice_catalog.dart` | 10 `PracticeDefinition`, id `builtin.*.v1` | szabad `skillTags` sztringek (20 érték) | `PracticeDifficulty`: 8 beginner + 2 intermediate (a 160. és 214. sor) | `titleKey` + `descriptionKey` → ARB |
| Tutor knowledge | `assets/tutor_knowledge/manifest.json` + `en/`, `hu/` | 10 dokumentum = 5 téma × 2 locale | ZÁRT enum `KnowledgeSkill{rhythm, chord, technique, practice, safety}` (`lib/features/ai_tutor/data/knowledge/knowledge_document.dart:3`) | `KnowledgeDifficulty` (mind `beginner`) | a manifest `locale` mezője + `sourcePath` |
| Legacy Learn leckék | `lib/features/learn/model/lesson.dart` (`Lessons.all`) | 16 lecke (6 beginner / 6 intermediate / 4 advanced) + `Lessons.firstWin` a kurrikulumon kívül | nincs saját címke | `Difficulty` enum | `Lesson.name` — **beégetett angol** |

A `assets/tutor_prompts/*.json` (6 fájl) modell-bemenet, nem tanulói tartalom → nem
leltár-sor. **Dalpélda-tartalom a fán NINCS** (`assets/` = `fonts`, `ml`, `tutor_knowledge`,
`tutor_prompts`) — az SDD „dalpéldák" pontja üres halmazon teljesül, ezt a
readiness-riportnak KI KELL MONDANIA.

### R2 — A Practice Generator katalógusa hívó-táplált; a generátor-kimenet ma nem mérhető

`PracticeEngineCatalogAdapter` és `LegacyLessonCandidateAdapter` I/O-t nem végez („This
adapter intentionally does not read Practice Engine repositories or providers"), és
`PracticeCatalogReader` **implementáció a fán nincs** — csak az interfész
(`application/port/practice_catalog_reader.dart`) és egy fogyasztó mező
(`tutor_plan_proposal_adapter.dart:40`). Ezért az A2 **nem** egy generátor-futás kimenetén
mérődik, hanem a SZÁLLÍTOTT hivatkozás-halmazon (ADR 0485 D2). Ez a §0.0 revízió, nem
lista-tágítás: a brief eredeti A2-cellája („a generátor-kimenet minden hivatkozása") a mért
úton ma teljesíthetetlen lenne.

### R3 — Egyetlen kanonikus készség-szótár sincs; a `LegacyMappingTable` szótára külön áll

`LegacyMappingTable.builtIn` három bejegyzése `chord.gMajor`, `chord.cMajor`, `chord.dMajor`
készség-azonosítót ad. Ezek **egyike sem** eleme az `ai_tutor`
`SkillTaxonomy.initial` 18 csomópontjának (`chord.shapeClarity`, `chord.changeSpeed`,
`chord.progressionAccuracy`, `chord.barreFoundation`, …). A `grep -rn "'chord\.gMajor'"`
egyetlen találata maga a mapping-tábla. Ezért a szótár **forrásonként deklarált** (ADR 0485
D4), és az eltérés a leltárban rögzített tény, nem a kör által javítandó hiba.

### R4 — MÉRT GA-blokkoló: mind a 10 `descriptionKey` hiányzik MINDKÉT locale-ból

```
for k in $(grep -o "practiceCatalog[A-Za-z]*" lib/features/practice/data/builtin_practice_catalog.dart | sort -u);
  do echo "$k en=$(grep -c "\"$k\"" lib/l10n/app_en.arb) hu=$(grep -c "\"$k\"" lib/l10n/app_hu.arb)"; done
```

→ mind a 10 `practiceCatalog*Title` `en=1 hu=1`; mind a 10 `practiceCatalog*Description`
**`en=0 hu=0`**. A `practiceCatalogQuarterDownstrokesDescription` egyetlen előfordulása az
egész fán maga a Dart-katalógus. A hiba ma latens (a `practice_mode_card.dart` csak a
`titleKey`-t oldja fel), de a `descriptionKey` szerződés szerint feloldható ARB-kulcs.
**A javítás `lib/l10n/**`-t érintene → a kör tilos zónája**, tehát a lelet útja a leltár
`known_exceptions:` blokkja (owner + ISO-lejárat) és a readiness-riport. Ugyanez a második
mért locale-hiány a `Lesson.name` beégetett angolja.

### R5 — A pedagógiai út mért szerkezetei

`Lessons.all` sorrendje nehézség szerint monoton nem csökkenő (6 beginner → 6 intermediate →
4 advanced). Az unlock-lánc **tier-en belüli**:
`LessonProgressController.isUnlocked` → `i <= 0 ? true : isPassed(tier[i-1].id)`
(`lesson_progress_provider.dart:36-41`), és a `lesson_list_screen.dart` `unlockedBy`-ja
ugyanezt tükrözi. `Lessons.nextAfter('first-win') == all.first`, az utolsó lecke után `null`.
A `SkillTaxonomy` konstruktora maga validál (duplikátum, self-prereq, ismeretlen prereq,
kör). Az A4 ezekre a mért szerkezetekre mérődik (ADR 0485 D5), nem új út-fájlra.

### R6 — Python validátor + `python3`-ra shellező Dart kapu: MÉRT, CI-zöld minta

`test/tooling/security_scan_test.dart:31`, `benchmark_budget_test.dart:275`,
`ai_release_report_test.dart:87` és `device_matrix_test.dart:1636` mind
`Process.runSync('python3', …)`-szal futtat egy `tool/**.py`-t, és mind zöld a CI-ben.
[L110](../LESSONS.md#l110) a `rg`-re vonatkozik (nincs a runneren), NEM a `python3`-ra. A
`tool/validate_content_catalog.py` tehát marad Python, és a kapu-teszt viszi a szomszédok
A8-őrét: a saját forrása `Process.run`/`runSync`/`start` belépési ponton **kizárólag**
`python3`-at indíthat.

### R7 — Nincs `package:yaml`

A `pubspec.yaml`-ben nincs `yaml` függőség. A leltárt a **Python** validátor parszolja
(a `python3` `yaml` modulja sem garantált a runneren → a validátor a saját, szigorú,
fail-closed sor-parszerét használja, `unparsable_line` hibával). A Dart kapu-teszt a
validátor kilépési kódját és stdout-ját méri, nem parszolja újra a YAML-t — így nincs
kettős igazság.

### R8 — `docs/content/` és `tool/validate_content_catalog.py` nem létezik; `test/tooling/` 30 fájlos, mind gate-őr

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/content/catalog-inventory.yaml",
  "docs/content/release-readiness.md",
  "tool/validate_content_catalog.py",
  "test/tooling/content_catalog_test.dart",
  "docs/rounds/e12-r21-content-catalog-and-pedagogical-readiness.md",
]
gate_tests = [
  "test/tooling/content_catalog_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll — scope-ütközés:** ha a §4 listán kívüli fájlhoz kellene nyúlnod (bármely
`lib/**`, `assets/**`, `docs/adr/**`, `.github/**`, `tools/**`), az **nem** „gyors rendbetétel":
`tools/codex-signal.sh stopped "<egy sor>"` + jelentés a §10-be. A gépi scope-audit a kilépésed
után lefut.

**STOP-protokoll — tartalom-lelet:** ha a validátor a §0.0 R4-en FELÜL olyan törött
hivatkozást talál, ami nem létező tartalomra mutat, a kimenet szintén `stopped` + jelentés — a
tartalom javítása külön kör. A MÁR ISMERT R4-lelet (hiányzó `descriptionKey` ARB-kulcsok) NEM
`stopped`-ok: az a `known_exceptions:` úton megy (ADR 0485 D3/D7).

## 1. Cél

Bizonyítani, hogy minden ajánlott/generált gyakorlat LÉTEZŐ tartalomra mutat, a kezdő tanulási út végigjárható, és minden tartalom-elem verziózott, locale-lefedett.

## 2. Jelenlegi állapot — mért tények

A teljes mérés a §0.0 R1–R8. Röviden: `content/`, `docs/content/` és
`tool/validate_content_catalog.py` **nem létezik**; a tartalom három forrásból áll (R1); a
Practice Generator katalógusa hívó-táplált, `PracticeCatalogReader` implementáció nincs (R2);
a készség-szótárak diszjunktak (R3); mind a 10 `practiceCatalog*Description` ARB-kulcs hiányzik
mindkét locale-ból (R4); a kurrikulum-lánc tier-en belüli (R5).

## 3. Scope

**Benne van:** `docs/content/catalog-inventory.yaml` — MINDEN mért tartalom-elem: azonosító, forrás, nehézség, készség-címke, locale-lefedettség, verzió, továbbá a `skill_vocabularies:`, a `known_exceptions:` és a `content_package_version:` blokk · `tool/validate_content_catalog.py` (a leltár ↔ MÉRT forrás KÉTIRÁNYÚ összevetése; hiányzó locale, ismeretlen/nem használt készség-címke, nem létező hivatkozás, nem parszolható sor, owner/lejárat nélküli vagy lejárt kivétel → nem-nulla kilépés) · `test/tooling/content_catalog_test.dart` (a §6 cellái) · `docs/content/release-readiness.md`.

**NINCS benne (tilos):**

- Tartalom hozzáadása, átírása vagy áthelyezése (`lib/features/practice/data/**`, `assets/**`).
- Új `content/` fa létrehozása.
- A Practice Generator javítása; új `PracticeCatalogReader` implementáció.
- A mért locale-hiány (R4) JAVÍTÁSA — `lib/l10n/**` a tilos zóna; a lelet útja a
  `known_exceptions:` + readiness-riport (ADR 0485 D3/D7).
- Egyesített készség-taxonómia bevezetése (R3).
- `docs/adr/**` — az ADR 0485-öt a Claude már megírta és commitolta.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/content/catalog-inventory.yaml` | ÚJ — a tartalom-leltár |
| `docs/content/release-readiness.md` | ÚJ — a pedagógiai readiness riport |
| `tool/validate_content_catalog.py` | ÚJ — a validátor |
| `test/tooling/content_catalog_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/**` · `assets/**` · `docs/adr/**` · `.github/**` · `tools/**`

## 5. Kötött architekturális döntések (ADR 0485)

A teljes szöveg: [`docs/adr/0485-…`](../adr/0485-content-catalog-inventory-and-pedagogical-readiness-contract.md).
Kivonat — a hét döntés és a nem elfogadható gyengítésük:

### 5.1 A leltár TÜKÖR, és a tükrözés KÉTIRÁNYÚ (D1)

A validátor a FORRÁSBÓL indul: minden mért forrás-elemhez kell leltár-sor
(`missing_inventory_entry`), és minden leltár-sorhoz kell forrás-elem
(`stale_inventory_entry`). A **nem parszolható** leltár-sor is hiba (`unparsable_line`).
**NEM elfogadható gyengítés:** a leltár kanonikussá tétele; egyirányú (csak leltár→forrás)
mérés; a nem illeszkedő sor néma átugrása ([L566](../LESSONS.md#l566)).

### 5.2 A törött hivatkozás BLOKKOL (D2)

A mérendő halmaz (R2 miatt) a SZÁLLÍTOTT hivatkozásoké: a `LegacyMappingTable.builtIn`
minden `lessonId`-ja létezik `Lessons.all`-ban vagy `Lessons.firstWin`-ben, és a
tutor-manifest minden `sourcePath`-a létező fájl. **NEM elfogadható gyengítés:**
figyelmeztetés-szint; a formátum (regex) ellenőrzése a létezés helyett.

### 5.3 A locale-lefedettség mindkét nyelvre kötelező, kivétel csak ownerrel és LEJÁRATTAL (D3)

`en` ÉS `hu`. A kivétel egyetlen útja a `known_exceptions:` blokk, kötelező `owner:` és ISO-dátum
`expiry:` mezővel. **NEM elfogadható gyengítés:** „a magyar majd később" nyilvántartás nélkül;
`expiry: unscheduled` (E12-R20-ban MÉRTEN ez lett a csendes menekülő-út); lejárt `expiry`
átengedése.

### 5.4 A készség-szótár FORRÁSONKÉNT deklarált és zárt, kétirányúan mérve (D4)

`unknown_skill_tag` ÉS `unused_skill_tag`. A `KnowledgeSkill` enum értékeit a validátor a Dart
forrásból olvassa ki és veti össze a leltárral. **NEM elfogadható gyengítés:** negyedik,
egyesített taxonómia bevezetése; egyirányú szótár-mérés.

### 5.5 A pedagógiai út a SZÁLLÍTOTT szerkezeteken mérődik (D5)

R5 négy invariánsa. **NEM elfogadható gyengítés:** csak a nehézség monotonitásának mérése.

### 5.6 Python validátor, `python3`-ra shellező Dart kapu, A8-őrrel (D6)

**NEM elfogadható gyengítés:** a validátor-logika Dart-oldali második implementációja;
`skip` ág hiányzó `python3`-ra.

### 5.7 Ez a kör MÉR, nem javít (D7)

A mért GA-blokkoló `known_exceptions:` sor + readiness-riport. A leltár
`content_package_version:` mezője adja a tartalom-csomag verzióját a release-manifesthez.

## 6. Acceptance criteria

Minden cella a `test/tooling/content_catalog_test.dart` egy-egy `test(...)`-je. A validátort a
cellák IDEIGLENES (a teszt által írt, `Directory.systemTemp` alatti) leltár- és
forrás-fixtúrákon is futtatják, nem csak a valódi fán — a fixtúra nélküli „valódi fa zöld"
önmagában nem bizonyítja, hogy a hiba pirosra vált.

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A validátor a FORRÁSBÓL indul: a valódi fán a három forrás mért elemszáma (10 practice-definíció + 10 knowledge-dokumentum + 16 lecke + `first-win`) mind szerepel a leltárban; fixtúrán egy forrásban létező, leltárból hiányzó elem → `missing_inventory_entry`, kilépési kód ≠ 0 | `content_catalog_test.dart` |
| A2 | Fixtúrán egy `LegacyMappingTable`-beli `lessonId`, amely nincs `Lessons.all`-ban, ÉS egy nem létező `sourcePath` → `broken_reference`, kilépési kód ≠ 0; a valódi fán mindkettő tiszta | `content_catalog_test.dart` |
| A3 | Fixtúrán hiányzó `hu` változat → nem-nulla kilépés, ÉS hiányzó `en` változat → nem-nulla kilépés (mindkét irány külön cella); a valódi fa R4-leletét kizárólag a `known_exceptions:` bejegyzés engedi át | `content_catalog_test.dart` |
| A4 | A négy R5-invariáns négy külön cellája: (1) `Lessons.all` nehézség-sorrend monoton nem csökkenő; (2) `Lessons.byDifficulty(beginner)` minden eleme elérhető a tier első eleméből az `isUnlocked` láncon; (3) `nextAfter('first-win') == all.first` és minden nem-utolsó lecke után nem-`null`; (4) a leltár `skill_graph:` blokkja az `ai_tutor` `SkillTaxonomy.initial` MINDEN csomópontját és előfeltételét tartalmazza | `content_catalog_test.dart` |
| A5 | Fixtúrán a forrásban használt, deklarálatlan címke → `unknown_skill_tag`; a deklarált, sehol nem használt címke → `unused_skill_tag`; mindkettő nem-nulla kilépés; a `KnowledgeSkill` enum bővítése (fixtúra-Dart-forráson) → nem-nulla kilépés | `content_catalog_test.dart` |
| A6 | Minden `known_exceptions:` bejegyzésnek van `owner:`-e és ISO-dátum `expiry:`-je; fixtúrán `expiry: unscheduled` → nem-nulla kilépés, és MÚLTBELI ISO-dátum → nem-nulla kilépés | `content_catalog_test.dart` |
| A7 | Fail-closed parszer: fixtúrán egy hibás behúzású / a mintára nem illeszkedő leltár-sor → `unparsable_line`, nem-nulla kilépés (L566) | `content_catalog_test.dart` |
| A8 | A kapu-teszt saját forrása `Process.run`/`Process.runSync`/`Process.start` belépési ponton kizárólag `python3`-at indít (a szomszédos `test/tooling` őrök mintája, L110) | `content_catalog_test.dart` |
| A9 | A kör egyetlen tartalom-fájlt sem módosít | `git diff --stat` a §4 listán + gépi scope-audit |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A validátor a leltárból indul, nem a forrásból (új gyakorlat láthatatlan) | A1 |
| A hivatkozás-ellenőrzés csak formátumot néz, létezést nem | A2 |
| A locale-ellenőrzés csak az `en` ágat követeli | A3 (`hu`-ág cellája) |
| A locale-ellenőrzés csak a `hu` ágat követeli | A3 (`en`-ág cellája) |
| A progresszió-cella csak a nehézség monotonitását nézi, az unlock-láncot és a készség-gráfot nem | A4 (2) és (4) |
| A szótár-mérés egyirányú (csak az ismeretlen címkét fogja, a holt deklarációt nem) | A5 (`unused_skill_tag` cellája) |
| A `KnowledgeSkill` enum a leltárba be van égetve, nem a Dart forrásból olvasva | A5 (enum-bővítés cellája) |
| A kivétel lejárat nélkül is átmegy (`unscheduled`, üres, vagy múltbeli dátum) | A6 |
| A sor-parszer fail-OPEN: a nem illeszkedő sor „nem létezik" | A7 |
| A kapu-teszt `rg`-t vagy `gh`-t is indít | A8 |

**Küszöb-hármas az A6 lejárathoz** — a küszöb a `--today` érték, a kör napja `2026-09-01`,
a határ INKLUZÍV (a lejárat napja még érvényes). A három cella a küszöb **alatt**, **rajta**
és **fölött**:

| Cella | `expiry:` | Elvárás |
|---|---|---|
| a küszöb **alatt** (lejárt) | `2026-08-31` | nem-nulla kilépés, `expired_exception` |
| **rajta** (a határ napja) | `2026-09-01` | kilépési kód 0 |
| a küszöb **fölött** (jövőbeli) | `2026-09-02` | kilépési kód 0 |

A három dátumot `python3 -c` számolja ki, nem kézzel írod:

```bash
python3 -c "import datetime as d; t=d.date(2026,9,1); print([str(t+d.timedelta(days=k)) for k in (-1,0,1)])"
```

A „rajta" cella a határ, tehát külön teszt. A validátor a mai dátumot **paraméterből** kapja
(`--today YYYY-MM-DD`), nem `date.today()`-ből — különben a teszt egy nap múlva magától
pirosra vált (determinizmus, ADR 0257 §5-6 szelleme).

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vedd ki a leltárból egy létező
gyakorlat bejegyzését, futtasd a §7 gate-et → az **A1** cellának PIROSNAK kell lennie →
állítsd vissza. Másodikként: írj a leltár végére egy 4-szóközzel behúzott, a mintára nem
illeszkedő sort → az **A7** cellának PIROSNAK kell lennie → töröld.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/content_catalog_test.dart
```

A validátor közvetlen futtatása (kimenet a §10-be):

```bash
python3 tool/validate_content_catalog.py --inventory docs/content/catalog-inventory.yaml --today 2026-09-01
```

## 8. Implementációs sorrend

1. A MÉRÉS: a §0.0 R1 három forrásának tényleges elemei (a leltár sorai innen jönnek, nem
   fejből).
2. `test/tooling/content_catalog_test.dart` — ELŐSZÖR a fixtúra-vezérelt cellák (A1–A3, A5–A7),
   PIROSRA futtatva (a validátor még nem létezik → a cella pirosan bukik, ez a RED).
3. `tool/validate_content_catalog.py` — a cellákat zöldre.
4. `docs/content/catalog-inventory.yaml` — a mért leltár, a `skill_vocabularies:`,
   `skill_graph:`, `known_exceptions:` (R4 két bejegyzése ownerrel és ISO-lejárattal) és
   `content_package_version:` blokkokkal.
5. Az A4 és A8 cellák; a teljes gate.
6. `docs/content/release-readiness.md` + a két valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Harmadik tartalom-fa.** A `content/` bevezetése kettős igazságot csinálna (§5.1).
- **Törött hivatkozás.** Ha a MÉRÉS ilyet talál, az `stopped` — de a lelet önmagában is a kör
  értéke (A2). A már ISMERT R4-lelet NEM `stopped`-ok: az a `known_exceptions` úton megy.
- **Locale-hiány elfedése.** A „majd később" kivétel nyilvántartás nélkül GA-blokkolót rejt el
  (A3/A6).
- **Fail-open parszer.** A kézzel írt sor-parszer alapértelmezésben átenged mindent, ami nem
  illeszkedik ([L566](../LESSONS.md#l566)) — az A7 ennek a gépi őre.
- **Zöld gate ≠ mérce.** Az E12-R18/R19/R20 három egymást követő MAJOR-ja mind őr-hiba volt
  teljesen zöld gate mellett: a szövegesen előírt tartalomnak nem volt gépi cellája. A §6
  minden sorát fixtúra-vezérelt cella méri, nem a valódi fa zöldje.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
