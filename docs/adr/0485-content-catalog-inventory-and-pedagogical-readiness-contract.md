# ADR 0485 — Content-katalógus leltár és pedagógiai readiness szerződés

- **Státusz:** elfogadva (2026-09-01, E12-R21 pre-flight)
- **Kontextus:** SDD Chapter 12, Kör 21;
  [`docs/rounds/e12-r21-content-catalog-and-pedagogical-readiness.md`](../rounds/e12-r21-content-catalog-and-pedagogical-readiness.md)
- **Kapcsolódó:** [ADR 0068](0068-practice-domain-model-contracts.md) (Practice V2 domain
  szerződések), [ADR 0135](0135-tutor-knowledge-governance.md) (tutor knowledge
  governance), [ADR 0293](0293-legacy-evidence-adapter-identity-and-mapping-contract.md)
  (legacy lecke → készség leképezés), [ADR 0376](0376-ui-baseline-inventory-contract.md)
  (UI baseline inventory — a leltár-mint-tükör minta),
  [ADR 0473](0473-release-fixture-corpus-manifest.md) (fixture-manifest: a hivatkozott
  minta-forma)

## Kontextus

Az SDD Ch12 Kör 21 egy `content/catalog/` fát és egy
`tool/validate_content_catalog.py` validátort ír elő, amivel bizonyítható, hogy
minden ajánlott/generált gyakorlat létező tartalomra mutat, a kezdő tanulási út
végigjárható, és minden tartalom-elem verziózott és locale-lefedett.

A pre-flight MÉRÉS (2026-09-01, `main @ ca643908`) viszont azt adta, hogy a
tartalom a fán **nem egy, hanem három** helyen él, és `content/` fa nincs:

| Forrás | Hol | Mennyi | Készség-szótár | Nehézség | Locale |
|---|---|---|---|---|---|
| Practice Engine katalógus | `lib/features/practice/data/builtin_practice_catalog.dart` | 10 `PracticeDefinition` (`builtin.*.v1`) | szabad `skillTags` sztringek (20 külön érték) | `PracticeDifficulty` enum (8× beginner, 2× intermediate) | ARB-kulcs (`titleKey`/`descriptionKey`) |
| Tutor knowledge pack | `assets/tutor_knowledge/manifest.json` + `en/`, `hu/` | 10 dokumentum = 5 téma × 2 locale | ZÁRT enum: `KnowledgeSkill{rhythm, chord, technique, practice, safety}` | `KnowledgeDifficulty` enum | a manifest `locale` mezője |
| Legacy Learn leckék | `lib/features/learn/model/lesson.dart` (`Lessons.all`) | 16 lecke + `firstWin` a kurrikulumon kívül | nincs saját címke; a `LegacyMappingTable.builtIn` 3 leckét képez le | `Difficulty` enum (6/6/4) | a `name` mező beégetett angol |

Egy negyedik hely — `assets/tutor_prompts/*.json`, hat prompt-sablon — nem tanulói
tartalom, hanem modell-bemenet. Dalpélda-tartalom a fán **nincs** (`assets/`
alatt csak `fonts`, `ml`, `tutor_knowledge`, `tutor_prompts`).

Két további mért tény írja a szerződést:

1. **A Practice Generator katalógusa hívó-táplált.** A
   `PracticeEngineCatalogAdapter` és a `LegacyLessonCandidateAdapter` I/O-t nem
   végez, és a fán **nincs** `PracticeCatalogReader` implementáció (csak az
   interfész és egy fogyasztó mező). Egy generátor-futás kimenetén tehát nem
   mérhető, hogy „létező gyakorlatra mutat" — a MÉRHETŐ, szállított
   hivatkozás-halmaz a `LegacyMappingTable.builtIn` három `lessonId`-ja és három
   `skillId`-ja, valamint az adapterek `exerciseId`-forrásai
   (`PracticeDefinition.id`, `Lesson.id`).
2. **Egyetlen kanonikus készség-szótár sincs.** A három forrás szótára
   diszjunkt: `'downstrokes'` / `'quarterNotes'` (practice), `chord`/`rhythm`
   (knowledge), `'chord.gMajor'` (mapping table) — utóbbi három NEM eleme az
   `ai_tutor` `SkillTaxonomy.initial` 18 csomópontjának sem.

## Döntés

### D1 — A leltár TÜKÖR, és a tükrözés KÉTIRÁNYÚ

A tartalom forrása marad a Dart-katalógus, az asset-manifest és a Learn
lecke-katalógus. A `docs/content/catalog-inventory.yaml` ezekből ellenőrződik, és
a validátor **a forrásból indul**: minden mért forrás-elemhez kell leltár-sor
(különben `missing_inventory_entry`), és minden leltár-sorhoz kell forrás-elem
(különben `stale_inventory_entry`).

A kétirányúság nem stílus, hanem a mért fail-open ellenszere
([L566](../LESSONS.md#l566)): egy kézzel írt sor-parszer alapértelmezésben azt
mondja, hogy ami nem illeszkedik a mintára, az nem hibás, hanem nem létezik.
Ezért a validátornak a **nem parszolható** leltár-sor is hiba
(`unparsable_line`), nem néma átugrás.

**NEM elfogadható gyengítés:** a leltár kanonikussá tétele (a kód-oldali
katalógus onnan való feltöltése) — az kettős igazság; és az egyirányú
(csak leltár→forrás) ellenőrzés — az az új, be nem jelentett tartalomra vak.

### D2 — A törött hivatkozás BLOKKOL

Nem létező tartalomra mutató hivatkozás nem-nulla kilépés. A mérendő
hivatkozás-halmaz a D-táblázat szerinti, MÉRT halmaz: a
`LegacyMappingTable.builtIn` minden `lessonId`-ja szerepel `Lessons.all`-ban vagy
`Lessons.firstWin`-ben, és minden asset-manifest `sourcePath` fájlként létezik.

**NEM elfogadható gyengítés:** figyelmeztetés-szintre sorolás; vagy a
hivatkozás formátumának (regex) ellenőrzése a létezés helyett.

### D3 — Locale-lefedettség: `en` ÉS `hu`, kivétel csak ownerrel és LEJÁRATTAL

Minden GA-scope tartalom-elemnek mindkét locale-ban léteznie kell. A mérés
forrásonként más felületet néz:

- Practice Engine: a `titleKey` ÉS a `descriptionKey` szerepel-e a
  `lib/l10n/app_en.arb` **és** `lib/l10n/app_hu.arb` aggregátumban;
- tutor knowledge: van-e azonos témájú `en` és `hu` dokumentum, és létezik-e a
  `sourcePath`;
- Learn leckék: a `Lesson.name` beégetett angol — ez ismert, mért hiányosság.

A kivétel egyetlen útja a leltár `known_exceptions:` blokkja, ahol **kötelező**
az `owner:` és egy ISO-dátum `expiry:`. A `unscheduled` (vagy bármely nem
ISO-dátum) lejárat **maga is hiba** — az E12-R20-ban mérten pontosan ez lett a
csendes menekülő-út. Lejárt `expiry` szintén hiba.

**NEM elfogadható gyengítés:** „a magyar majd később" nyilvántartás nélkül;
`expiry: unscheduled`; vagy a kivétel nélküli, hallgatólagos átengedés.

### D4 — A készség-szótár FORRÁSONKÉNT deklarált és zárt

Mivel a fán nincs kanonikus taxonómia (Kontextus 2. pont), a leltár
`skill_vocabularies:` blokkja deklarálja forrásonként a megengedett
címke-halmazt. A validátor mindkét irányban méri: a forrásban használt,
deklarálatlan címke `unknown_skill_tag`, a deklarált, de sehol nem használt
címke `unused_skill_tag`.

A `KnowledgeSkill` enum értékeit a leltár nem találhatja ki: azt a validátor a
`lib/features/ai_tutor/data/knowledge/knowledge_document.dart` `enum
KnowledgeSkill` soraiból olvassa ki, és a leltárban deklarált halmazzal veti
össze — így egy jövőbeli enum-bővítés a leltárt pirosra váltja, nem csendben
átcsúszik.

**NEM elfogadható gyengítés:** egy negyedik, „egyesített" készség-taxonómia
bevezetése ebben a körben — az normatív döntés, nem leltár.

### D5 — A pedagógiai út a SZÁLLÍTOTT szerkezeteken mérődik, nem új út-fájlon

A „kezdő tanulási út végigjárható, nincs zsákutca" négy, MÉRT invariáns:

1. `Lessons.all` nehézség-sorrendje monoton nem csökkenő
   (beginner → intermediate → advanced), tehát a lineáris kurrikulum nem lép
   vissza;
2. `Lessons.byDifficulty(beginner)` minden eleme elérhető a tier első eleméből a
   `isUnlocked` láncon (`i <= 0 → true`, különben az `i-1` teljesítése), azaz a
   tier egyetlen szigetre sem esik szét;
3. `Lessons.nextAfter` a `first-win`-t a kurrikulumba fűzi és minden nem-utolsó
   lecke után nem-`null` — az utolsó `null` a lezárás, nem zsákutca;
4. az `ai_tutor` `SkillTaxonomy.initial` minden csomópontjának minden
   előfeltétele létezik és a gráf körmentes (a típus maga validálja; a leltár ezt
   a 18 csomópontot listázza, hogy a listából-kihullás pirosra váltson).

**NEM elfogadható gyengítés:** csak a nehézség monotonitásának mérése — az a
készség-előfeltételre és az unlock-lánc szigetekre vak (a brief §6.1 mátrix
sora).

### D6 — Python validátor + `python3`-ra shellező Dart kapu

A validátor `tool/validate_content_catalog.py` (az SDD által megnevezett fájl), a
kapu pedig `test/tooling/content_catalog_test.dart`, amely `Process.runSync('python3', …)`-szal
hívja. Ez a fán MÉRT, CI-zöld minta: `test/tooling/security_scan_test.dart`,
`benchmark_budget_test.dart`, `ai_release_report_test.dart` és
`device_matrix_test.dart` mind így fut. [L110](../LESSONS.md#l110) a `rg`-re
vonatkozik (az nincs a runneren), nem a `python3`-ra.

A kapu-teszt viszi tovább a szomszédok A8-őrét is: a saját forrása a
`Process.run`/`runSync`/`start` belépési pontokon **kizárólag** `python3`-at
indíthat.

**NEM elfogadható gyengítés:** a validátor logikájának Dart-oldali második
implementációja (kettős igazság), vagy a `skip` ág hiányzó `python3`-ra.

### D7 — Ez a kör MÉR, nem javít

A mért GA-blokkoló nem javítható ebben a körben (a tartalom-források a kör tilos
zónája). Az ilyen lelet útja: `known_exceptions:` sor (D3 szerint ownerrel és
lejárattal) + nevesítés a `docs/content/release-readiness.md`-ben. A leltár
`content_package_version:` mezője adja a release-manifesthez a
tartalom-csomag verzióját.

## Következmények

- A `docs/content/catalog-inventory.yaml` a tartalom egyetlen gépi leltára; a
  forrás marad a kód és az asset — a kettőt a validátor tartja szinkronban.
- A pre-flight már MÉRT egy GA-blokkolót: a beépített gyakorlat-katalógus mind a
  **10 `descriptionKey`-e** (`practiceCatalog*Description`) egyetlen ARB-rétegben
  sem létezik, sem `en`, sem `hu` alatt — miközben mind a 10 `titleKey` létezik
  mindkettőben. A javítás `lib/l10n/**`-t érint, ami a kör tilos zónája, tehát a
  D3/D7 úton, `known_exceptions` bejegyzésként és a readiness-riportban
  nevesítve landol.
- A Learn leckék beégetett angol `name` mezője a második mért, nyilvántartandó
  locale-hiány.
- A `LegacyMappingTable` `chord.gMajor|cMajor|dMajor` készség-azonosítói nem
  elemei az `ai_tutor` `SkillTaxonomy.initial`-jának; a leltár ezt a
  szótár-eltérést rögzíti (D4), az egyesítés külön, normatív kör dolga.
- Egy jövőbeli, valódi `PracticeCatalogReader` bekötése után a D2 mérése
  kiterjeszthető a generátor tényleges kimenetére; addig a szállított
  hivatkozás-halmaz a mérce.
