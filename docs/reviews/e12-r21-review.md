# E12-R21 — Review (Content catalog és pedagógiai readiness)

- **Reviewer:** Claude (Opus 5, orchestrátor) — read-only, ADR 0055
- **Implementer:** `sonnet-impl` (claude-sonnet-5)
- **Branch:** `sonnet-impl/e12-r21-content-catalog-and-pedagogical-readiness`
- **Mért HEAD:** `bec2a87c`, base `803cd3b4` (pre-flight commit)
- **Dátum:** 2026-09-01
- **Diff:** 5 fájl, +1902 sor, 0 törlés — pontosan az `allowed_paths` lista
  (`scope_audit=ok`, `scope_audit_changed=5`)
- **Módszer:** izolált klón (`/tmp/rev-e12r21`), a szállított validátor
  **mutációs** próbái a valódi fán — nem a szállított tesztek újrafuttatása

## Verdikt: **CHANGES REQUESTED** — 1 MAJOR, 1 MINOR, 2 NOTE

A kör gerince helyes és a brief legkockázatosabb előírásait teljesíti: a
kétirányú ID-tükör, a szűken hatókörözött kivétel-elnyomás, a fail-closed
sor-parszer és a lejárat-hármas mind MÉRTEN működik (lásd a „Mit mértem
zöldnek" szakaszt). A MAJOR ismét **őr-hiba, nem kódhiba**: a leltár hat
dimenziót deklarál elemenként, és ebből **négyet egyetlen mérce sem tükröz** —
tetszőlegesen hamis érték mellett is `exit 0`. Ez az E12-R18/R19/R20 mért
hibaosztályának **negyedik** egymást követő előfordulása
([L563](../LESSONS.md#l563), [L565](../LESSONS.md#l565),
[L566](../LESSONS.md#l566), [L567](../LESSONS.md#l567)).

---

## MAJOR-1 — A leltár elem-szintű mezői (`difficulty`, `skill_tags`, `locales`, `version`) NINCSENEK tükrözve: hamis érték mellett is zöld

**Hol:** `tool/validate_content_catalog.py` — `_mirror_source()` (438–450. sor)
és `run_validation()`; `test/tooling/content_catalog_test.dart` — a hiányzó
cellák helye.

**Mit ír elő a szerződés.** A brief §3: a leltár „**MINDEN mért tartalom-elem:
azonosító, forrás, nehézség, készség-címke, locale-lefedettség, verzió**". Az
[ADR 0485 D1](../adr/0485-content-catalog-inventory-and-pedagogical-readiness-contract.md):
„A leltár TÜKÖR, és a tükrözés KÉTIRÁNYÚ… a validátor **a forrásból indul**".
A §6 A1 bizonyíték-oszlopa ugyanezt kéri.

**Mit mértem.** A `_mirror_source()` **kizárólag az ID-halmazokat** veti össze
(`declared_ids` vs `measured_ids`); az `InventoryItem.fields` szótár a
`parse_inventory()`-ban feltöltődik (202., 207. sor), majd **soha nem
olvasódik el** — a `grep -n "\.fields" tool/validate_content_catalog.py`
mindössze ezt a két írási helyet adja. Négy mutációs próba az izolált klónon, a
valódi fán, mindegyik EGY sor átírása:

```
$ python3 tool/validate_content_catalog.py --inventory docs/content/catalog-inventory.yaml --today 2026-09-01
exit=0                                   # kontroll: érintetlen fa

# P1  builtin.quarterDownstrokes.v1  difficulty: beginner -> advanced
exit=0
# P2  builtin.quarterDownstrokes.v1  locales: [en] -> [en, hu, xx]
exit=0
# P3  builtin.quarterDownstrokes.v1  version: 1 -> 9
exit=0
# P4  builtin.quarterDownstrokes.v1  skill_tags: [downstrokes, quarterNotes] -> [totallyBogusTag]
exit=0
```

Négyből négy hamis állítás **átmegy**. A `skill_tags` elnyomása különösen
alattomos: a `_vocabulary_check()` a FORRÁSBÓL vett címkéket veti a
`skill_vocabularies:` blokk ellen, tehát a szótár helyes marad, miközben az
ELEM címkéi hazudhatnak — a „készség-címke" dimenzió így csak látszólag védett.

**Miért MAJOR, nem MINOR.** Pontosan az a hibaosztály, ami ellen a kör készült:
a leltár azt állítja magáról, hogy tükör, a mérce viszont csak a sorok
LÉTEZÉSÉT méri, a TARTALMUKAT nem. Egy jövőbeli tartalom-változás (nehézség
átsorolása, verzió-bump, locale-bővítés) a forrásban megtörténhet úgy, hogy a
leltár némán elavul — ez a `stale_inventory_entry` szándéka, csak elem-szinten.

**Javítás (a fix körnek).** Elem-szintű, KÉTIRÁNYÚ mező-tükör, forrásonként
mért értékekkel, fail-closed sentinellel ott, ahol a forrásnak nincs ilyen
dimenziója:

| Mező | `practice_engine` | `tutor_knowledge` | `learn_lessons` |
|---|---|---|---|
| `difficulty` | `PracticeDefinition.difficulty` kódja (default `beginner`) | manifest `difficulty` | `Lesson.difficulty` enum neve |
| `skill_tags` | `skillTags` lista, rendezve | `[manifest.skill]` | rögzített `[]` (a forrásnak nincs címkéje) |
| `locales` | a nem elnyomott lokalizációs kulcsok mért ARB-lefedettsége | `[manifest.locale]` | rögzített `[en]` (elnyomott, beégetett angol) |
| `version` | `schemaVersion` | manifest `version` | rögzített `1` |

Új leletkód **nem kell**: az eltérés `stale_inventory_entry`-ként jelentendő a
mező nevével a detailben (pl. `practice_engine:builtin.x.v1:difficulty`), így a
kódlista zárt marad (ADR 0485 D4 szelleme).

**Kötelező cellák** a `content_catalog_test.dart`-ban, fixtúrán, mind a négy
mezőre külön (a P1–P4 gépi megfelelője), plusz **egy `learn_lessons` sentinel-cella**
(`skill_tags: [x]` a `[]` helyett → nem-nulla kilépés) — különben a
sentinel-ág marad vak.

---

## MINOR-1 — A `locales:` mező szemantikája nincs kimondva, és a practice-sorok értéke vitatható

**Hol:** `docs/content/catalog-inventory.yaml` — mind a 10 `practice_engine`
sor `locales: [en]`.

A `practiceCatalog*Title` kulcsok MINDKÉT locale-ban léteznek (`en=1 hu=1`,
brief R4), a `*Description` kulcsok EGYIKBEN SEM. Az `[en]` érték tehát sem a
„van teljes lefedettség" (az `[]` lenne), sem a „nem elnyomott felületek
lefedettsége" (az `[en, hu]` lenne) olvasat szerint nem áll meg. Ma ez
ártalmatlan, mert a mezőt semmi nem méri — a MAJOR-1 javítása után viszont
ELDÖNTENDŐ. Javaslat: a `locales:` = azon kötelező locale-ok halmaza, amelyben
az elem MINDEN **nem elnyomott** lokalizációs felülete feloldódik; a
practice-sorok így `[en, hu]`-ra javulnak, a definíciót pedig a fájl fejléc-
kommentje mondja ki.

---

## NOTE-1 — Mit mértem ZÖLDNEK (a kör érdeme, nem lelet)

Mutációs próbák ugyanabban a klónban, mind a VÁRT leletet adta:

```
# P5  egy teljes item-blokk törlése a leltárból
missing_inventory_entry: practice_engine:builtin.folkPattern.v1        exit=1
# P6  egy titleKey törlése a lib/l10n/app_hu.arb-ből
missing_locale: practice_engine:builtin.folkPattern.v1:titleKey:hu     exit=1
# P7  egy item source-címkéjének átírása (practice_engine -> learn_lessons)
missing_inventory_entry: practice_engine:builtin.folkPattern.v1
stale_inventory_entry: learn_lessons:builtin.folkPattern.v1            exit=1
# P8  a kivétel lejáratának múltba állítása (2026-12-31 -> 2026-08-31)
expired_exception: practice-catalog-description-key-missing-both-locales (expiry=2026-08-31)
missing_locale: … 20 sor descriptionKey:en / :hu …                     exit=1
```

A **P6** a legfontosabb: a `known_exceptions` elnyomása szűken hatókörözött
(`locale:practice_engine:descriptionKey`), tehát egy JÖVŐBELI `titleKey`-regresszió
NEM bújik el mögötte — ez az E12-R20 `unscheduled`-menekülőút mért ellenszere.
A **P8** bizonyítja, hogy a kivétel valóban csak addig él, amíg a lejárata tart.

Az A4(4) cella (`skill_graph` ↔ `SkillTaxonomy.initial`) a Dart-oldalon
KÉTIRÁNYÚ (`declared.keys.toSet()` == `measured.keys.toSet()` + előfeltétel-
halmazok elemenként) — ez a §6.1 „csak a nehézség monotonitását nézi" sorának
valódi őre, helyesen a Dart forrásból mérve, nem a leltárból.

## NOTE-2 — A `first-win` a leltárban van, a kurrikulumban nincs — helyesen

`Lessons.firstWin` szándékosan nincs `Lessons.all`-ban („NOT in [all]: it lives
outside the curriculum/unlock chain"), a leltár mégis felsorolja, és az A2 a
`LegacyMappingTable` hivatkozásait `all ∪ {firstWin}` ellen méri. Ez helyes:
a lecke LÉTEZIK és hivatkozható, csak a progresszió-láncon kívül áll — az A4(1)
monotonitás-cellája viszont `Lessons.all`-t méri, ahol nincs benne. A két
halmaz szándékos szétválasztása dokumentált, nem lelet.

---

## Acceptance-mérleg (a fix kör előtt)

| # | Állapot |
|---|---|
| A1 | **RÉSZBEN** — az ID-tükör kétirányú és mért; az elem-szintű mezők tükre HIÁNYZIK (MAJOR-1) |
| A2 | ✅ mérve (P5/P7 kontroll + fixtúra-cellák) |
| A3 | ✅ mérve mindkét irányban (P6), a suppression szűk |
| A4 | ✅ mind a négy invariáns, a (4) kétirányúan |
| A5 | ✅ `unknown` + `unused` + enum-bővítés |
| A6 | ✅ owner + ISO-lejárat + a küszöb-hármas (P8 kontroll) |
| A7 | ✅ fail-closed parszer, `unparsable_line` |
| A8 | ✅ a spawnolt binárisok halmaza `{python3}` |
| A9 | ✅ `scope_audit=ok`, 5 fájl |

## Javító kör — mit kell szállítani

1. MAJOR-1: elem-szintű kétirányú mező-tükör a fenti táblázat szerint,
   `stale_inventory_entry` leletkóddal, mező-névvel a detailben.
2. MAJOR-1 mércéje: 5 új fixtúra-cella (`difficulty`, `skill_tags`, `locales`,
   `version`, `learn_lessons` sentinel).
3. MINOR-1: a `locales:` szemantika kimondása a leltár fejlécében + a 10
   practice-sor értékének a definícióhoz igazítása.
4. A §10 handoff kiegészítése a fenti próbák TÉNYLEGES kimenetével.

Az `allowed_paths` **nem bővül**.
