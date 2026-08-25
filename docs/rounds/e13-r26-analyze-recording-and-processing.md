# E13-R26 — Analyze Home, Recording és Processing UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ c732ec75`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 26
- **Kör-azonosító:** `E13-R26`
- **Branch:** `<motor>/e13-r26-analyze-recording-and-processing`
- **Előfeltétel:** `E13-R25` merge-elve (dal-tréner)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0285`](../adr/0285-recording-transparency-and-honest-progress.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el az elemzési feladat
> TÉNYLEGES életciklusát (szakaszok, ellenőrzőpont, megszakítás), mert a §5.2
> „nincs hamis százalék" cella a mért szakaszokra épül. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/analyze/home/",
  "lib/features/analyze/recording/",
  "lib/features/analyze/processing/",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/analyze/recording_state_test.dart",
  "test/features/analyze/processing_progress_test.dart",
  "test/features/analyze/analyze_cleanup_test.dart",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "docs/rounds/e13-r26-analyze-recording-and-processing.md",
]
gate_tests = [
  "test/features/analyze/recording_state_test.dart",
  "test/features/analyze/processing_progress_test.dart",
  "test/features/analyze/analyze_cleanup_test.dart",
  "test/ui/goldens/e13_r26_screens_golden_test.dart",
  "test/ui/ui_inventory_test.dart",
  "test/core/architecture_dependency_test.dart",
  "test/tooling/dio_factory_guard_test.dart",
  "test/tooling/preferences_plugin_import_guard_test.dart",
  "test/tooling/route_literal_guard_test.dart",
]
native_gate = false
```

## 0.0 BRIEF-REVÍZIÓ — 2026-08-25, batch pre-flight (E13-R17…R35)

A brief 2026-08-15-én készült; ez a pre-flight `main @ 41fbd40` ellen mért.
**Visszakeresett előzmény:** [L478](../LESSONS.md) (a pre-flight csak szűkíthet;
a tágítás H3), [ADR 0307 §4](../adr/0307-parallel-round-execution.md) (a
`lib/l10n/app_*.arb` GENERÁLT aggregátum, a forrás a `base/` és a
`features/` szegmens), [L481](../LESSONS.md) (a lánc remote konténerből nem
indítható). A hibaosztályt a **teljes Ch13 sávon** mérte ki egy batch-vizsgálat:
az R17–R35 MIND a generált aggregátumot sorolta fel forrásként (`agg=2, frag=0`).

**Kockázat = high, indoklás:** a felvétel mikrofon-engedélyt (authorization) kér, és nyers hangadatot tárol a feldolgozásig.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fájából `lib/features/analyze/home/`, `lib/features/analyze/recording/`, `lib/features/analyze/processing/` **még nem létezik** — a képernyőket ez a kör hozza létre, tehát MINDEN szövege új.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `analyze` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek

Az aggregátum a listán MARAD, de **kizárólag generált kimenetként**
(`dart run tool/gen_l10n_segments.dart --write`); a merge-elt precedens
egységesen a forrást ÉS a regenerált aggregátumot is commitolja (E09-R26
`df0ad3dd`, E13-R12 `376b8a1d`, E13-R10 `b11ab2ed`). **Új fragmentum NEM
készül**, ezért a `test/l10n/arb_parity_test.dart` beégetett szegmens-listáját
sem kell bővíteni — a felvett források mind szerepelnek benne.

### R2 — a kör SAJÁT feature-fáján élő, ma zöld widget-tesztek (FELVÉVE)

Ezek közvetlenül a migrálandó képernyőkre állítanak, tehát a migráció után
pirosra váltanának, ami a §0 szerint `blocked` lenne:

  - nincs ilyen.

**A jogosultság szűk:** a teszteket az ÚJ widgetekre kell ráállítani. A lefedett
viselkedést gyengíteni, cellát törölni vagy `skip`-elni **TILOS** — az a mérce
meggyengítése, amit a gate-guard emberhez eszkalál.

### R3 — keresztmetszeti tesztek (NEM kerültek listára — figyelmeztetés)

A kör fájára hivatkozó további widget-tesztek közös infrastruktúrán élnek
(`test/app/**`, `test/core/**`, más feature-ek fái) — nincs ilyen. Ezeket a kör
**NEM** szerkesztheti: ha egy elbukik, az `blocked` jelzés és célzott
brief-revízió, nem csendes átírás. A körbe húzásuk a scope-fegyelem feladása
lenne.

### R4 — a képernyő-leltár őre (H3 önjavító kör, ADR 0112, 2026-08-25)

A `test/ui/ui_inventory_test.dart` **repó-szintű** őr: a `tool/ui_inventory.dart`
a `lib/features/**` fa `_screen.dart` végű fájljait számolja, a teszt pedig
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z) `lib/features/analyze/home/`, `lib/features/analyze/processing/`, `lib/features/analyze/recording/` könyvtár-előtag
alá képernyőt hoz vagy hozhat, tehát a szám **elmozdul**, és az exact-SHA Full
Gate pirosra vált.

A `test/ui/goldens/` előtag ezt **nem** fedi (az a `test/ui/` fának csak az egyik
ága), a leltárteszt utólagos felvétele pedig tágítás, azaz **H3** — az
orchestrátor a pre-flightban nem oldhatja fel ([L478](../LESSONS.md)). Ezért
kerül a listára MOST, az önjavító körben.

**MÉRVE (E13-R16, 2026-08-25):** pontosan ez a hiány állította meg a sáv első
migrációs körét — [full-gate 32867296946](https://github.com/wolfcasaba/strumsight/actions/runs/32867296946)
6366 passed / 2 failed, `hasLength(79)` a tényleges 81 ellen. A `9acd14e5`
sáv-szintű batch pre-flight azért nem találta meg, mert a `tools/brief-lint.py`
`S9` szabálya csak LITERÁLIS `*_screen.dart` útvonalat nézett, KÖNYVTÁR-előtagot
nem — a predikátumot ugyanez az önjavító kör javította, regressziós teszttel
([L483](../LESSONS.md)).

**A jogosultság PONTOSAN a szám emelése** a kör tényleges képernyőszámára; a
leltárteszt minden más állítása érintetlen marad. Kerülőút (képernyő-átnevezés
vagy a `tool/ui_inventory.dart` szabályának lazítása) **TILOS** — az a mérce
meghamisítása.

### S12 — a fa-szintű őrök a kör LOKÁLIS kapujába (2026-08-25)

A kör lokális kapuja eddig KIZÁRÓLAG a saját céltesztjeit futtatta, ezért a
teljes `lib/` fát pásztázó őrök leletei szerkezetileg csak a ~17 perces
exact-SHA Full Gate-en jelentek meg — javító kör árán. MÉRT eset: **E13-R16/F8**
(`docs/reviews/e13-r16-review.md`), ahol mind a három új képernyő közvetlenül
importálta a `design_system/foundations/**`-ot a `public.dart` helyett — **11
sértés** —, és a review szó szerint rögzíti, miért nem fogta a célzott gate:
a `tools/round-gate.sh` `architecture` lépése a `tool/check_architecture.dart`-ot
futtatja, ami egy MÁSIK, tágabb szabálykészlet; a design-system-határ mércéje
egy külön `test/core/` teszt, amit csak a teljes suite futtat.

Ezért ez a kör mostantól a `gate_tests`-ben futtatja ezeket az őröket:

- `test/core/architecture_dependency_test.dart`
- `test/tooling/dio_factory_guard_test.dart`
- `test/tooling/preferences_plugin_import_guard_test.dart`
- `test/tooling/route_literal_guard_test.dart`

A kiválasztás MÉRT, nem vaktában: a globális őrök a `Directory('lib')` teljes
fát pásztázzák (bármelyik kör diffje elmozdíthatja őket), a szűkített őrök pedig
csak akkor kerülnek fel, ha a kör `allowed_paths`-a metszi a pásztázott
gyökeret.

**Ezek az őrök NEM kerülnek az `allowed_paths`-ra** — és ez szándékos: a kör
futtatja, de NEM szerkesztheti őket, tehát a lelet javítása kizárólag a kör
SAJÁT kódjában történhet. Cella törlése, `skip`-je vagy küszöb-lazítása így
gépileg kizárt, a mérce pedig tiszta erősítést kap.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Az UI-34–UI-36 megvalósítása **egyértelmű nyers-hang megőrzéssel**, valós
haladásjelzéssel és megszakítható elemzéssel (SDD Ch13 Kör 26).

## 2. Jelenlegi állapot — mért tények

- Az elemzési feladat **szakaszokból** áll, ellenőrzőponttal és megszakítási
  ponttal — a felület ezekre képez.
- Az ADR 0276 kimondta: a Stage layout nem birtokol erőforrást; a felvétel
  indítása felhasználói szándék.
- A nyers hangfelvétel a legérzékenyebb adat, amit a termék kezel.

## 3. Scope

**Benne van:** az Analyze kezdőképernyő bemeneti módjai és a legutóbbi elemzések
előnézete · a felvételi Stage jelminőség, torzítás, csend, tárhely és
**megőrzés-jelzéssel** · a feldolgozás szakasz-haladása és hő/akkumulátor
degradált állapota · megszakítás / ellenőrzőpont / újraindítás · kapcsolódás az
engedély-átjáróhoz és az audio-session koordinátorhoz · fájl-bemenet, nem
támogatott formátum és kevés tárhely állapotok.

**NINCS benne (tilos):** DSP vagy elemzési paraméter (AGENTS.md §9) · a
feladat-életciklus módosítása · az eredmény-felületek (Kör 27) · `docs/adr/**`,
`tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `analyze/home/` | a kezdőképernyő |
| `analyze/recording/` | a felvételi Stage |
| `analyze/processing/` | a feldolgozás |
| `lib/l10n/base/app_{en,hu}.arb` | **FORRÁS** — a felvételi és haladás-szövegek (a kör feature-ei még nem migráltak, a kulcsaik itt élnek) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/analyze/*_test.dart` (3) | a §6 cellái |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a kör új `lib/features/**/*_screen.dart`-ot hozhat, ezért az egzakt `hasLength(...)` elmozdul; a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4) |
| `docs/rounds/e13-r26-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/analyze/results/` · `lib/features/**` a három
érintett almappán kívül · `lib/core/design_system/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0285)

### 5.1 A felvétel-jelzés ÁLLANDÓ, és a megőrzés végig LÁTHATÓ

Amíg a mikrofon aktív, a felületen folyamatosan látszik. A felhasználó
mindvégig tudja, **megmarad-e** a nyers hangfelvétel, vagy csak a származtatott
elemzés.

**NEM elfogadható gyengítés:** a megőrzés-jelzés kizárólag a beállításokban. A
felvétel pillanatában kell tudni, mi történik a hanggal.

### 5.2 NINCS hamis százalék

A haladás a **tényleges** szakaszokból származik. Ha egy szakasz nem ad
haladás-információt, a felület határozatlan jelzést mutat — nem kitalált
számot, és nem lassan kúszó álhaladást.

**NEM elfogadható gyengítés:** időzítőből animált százalék, „hogy történjen
valami a képernyőn". Ez magabiztos hazugság a felhasználó felé.

### 5.3 A megszakítás IDEMPOTENS

Kétszer megnyomva sem keletkezik két megszakítás, és a folyamat mindig
konzisztens állapotban áll meg.

### 5.4 Hiba után NINCS árva mikrofon vagy ideiglenes fájl

Minden hibaútvonalon felszabadul a mikrofon, és eltűnnek az ideiglenes fájlok
(az ADR 0284 §2 elve a felvételi oldalon).

### 5.5 A kevés tárhely ELŐRE jelzett

Nem a felvétel közepén derül ki. A felület indulás előtt figyelmeztet.

### 5.6 A degradált mód KIMONDJA az okát

Hő- vagy akkumulátor-korlát esetén a felhasználó megtudja, miért lassabb a
feldolgozás — nem néma teljesítményesés.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A felvétel-jelzés végig látható, amíg a mikrofon aktív | `recording_state_test.dart` |
| A2 | A nyers-hang megőrzés állapota a felvétel közben látható | ugyanott |
| A3 | Nincs hamis százalék — a haladás a tényleges szakaszokból jön | `processing_progress_test.dart` |
| A4 | A megszakítás idempotens | ugyanott |
| A5 | Hiba után nincs árva mikrofon vagy ideiglenes fájl | `analyze_cleanup_test.dart` |
| A6 | A kevés tárhely a felvétel ELŐTT jelzett | `recording_state_test.dart` |
| A7 | A torzítás és a csend külön, cselekvésre hívó állapot | ugyanott |
| A8 | A degradált mód kimondja az okát | `processing_progress_test.dart` |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r26_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A megőrzés-jelzés csak a beállításokban | **A2** |
| Időzítőből animált haladás | **A3** |
| A második megszakítás új leállítást indít | **A4** |
| Hibaágon nyitva marad a mikrofon | **A5** |
| A tárhely a felvétel közben fogy el jelzés nélkül | A6 |
| A torzítás és a csend egy „hiba" állapot | A7 |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**A haladásjelzés három kötelező cellája** (a küszöb: ad-e a szakasz mérhető
haladást):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | a szakasz nem ad haladást | **határozatlan** jelzés — nincs szám |
| rajta (a küszöbön) | a szakasz szakasz-szintű haladást ad | szakasz-szintű jelzés (pl. „3/5 szakasz") |
| a küszöb fölött | a szakasz százalékot ad | a **tényleges** százalék |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** animálj időzítőből
százalékot a határozatlan szakaszra → az **A3** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/analyze/recording_state_test.dart test/features/analyze/processing_progress_test.dart test/features/analyze/analyze_cleanup_test.dart test/ui/goldens/e13_r26_screens_golden_test.dart test/ui/ui_inventory_test.dart test/core/architecture_dependency_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
~/flutter/bin/flutter test --update-goldens test/ui/goldens/e13_r26_screens_golden_test.dart
```

A keletkezett PNG-ket **commitolni kell** — enélkül az A9 nem teljesült. A
márkabetűtípusok a teszt-hostban nem töltődnek be (fallback face); ez a
meglévő golden-teszt mért viselkedése, az elrendezést, méretezést és színeket
nem érinti. MIÉRT ez a kör dolga és nem az E13-R36-é: a záró vizuális
regressziós kör csak azt tudja megmondani, hogy valami MEGVÁLTOZOTT — azt,
hogy a képernyő eleve csúnya-e, a saját körében kell látni.

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. Az Analyze kezdőképernyő bemeneti módokkal és előnézettel.
2. A felvételi Stage — állandó jelzés + megőrzés-állapot.
3. Jelminőség: torzítás és csend KÜLÖN, cselekvésre hívón.
4. A tárhely-előrejelzés.
5. A feldolgozás szakasz-haladása + a három cella.
6. Megszakítás idempotensen, ellenőrzőponttal; takarítás minden hibaágon.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az álhaladás.** A legelterjedtebb UI-hazugság, és pont a leghosszabb
  műveletnél rombolja a bizalmat (A3).
- **A rejtett megőrzés.** A nyers hang a legérzékenyebb adat; ha a felhasználó
  csak a beállításokban tudja meg a sorsát, az nem informált beleegyezés (A2).
- **A hibaágon nyitva maradó mikrofon.** A boldog út takarít, a hibaág nem —
  ez a klasszikus kihagyás (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
