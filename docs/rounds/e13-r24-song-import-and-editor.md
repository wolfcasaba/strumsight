# E13-R24 — Song import, preview és editor UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 74f8a8ec`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 24
- **Kör-azonosító:** `E13-R24`
- **Branch:** `<motor>/e13-r24-song-import-and-editor`
- **Előfeltétel:** `E13-R23` merge-elve (dal-könyvtár)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0284`](../adr/0284-import-preview-is-not-a-commit.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a TÉNYLEGES import-
> csővezeték kimenetét (figyelmeztetés és blokkoló hiba típusai, ideiglenes
> fájlok helye) — a §5.1 és §5.3 ezekre a mért típusokra képez felületet.
> Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/songs/import/",
  "lib/features/songs/editor/",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/songs/import/import_flow_test.dart",
  "test/features/songs/import/import_blocking_error_test.dart",
  "test/features/songs/import/editor_draft_test.dart",
  "test/features/songs/import/editor_keyboard_flow_test.dart",
  "test/fixtures/songs/import/",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "docs/rounds/e13-r24-song-import-and-editor.md",
]
gate_tests = [
  "test/features/songs/import/import_flow_test.dart",
  "test/features/songs/import/import_blocking_error_test.dart",
  "test/features/songs/import/editor_draft_test.dart",
  "test/features/songs/import/editor_keyboard_flow_test.dart",
  "test/ui/goldens/e13_r24_screens_golden_test.dart",
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

**Kockázat = high, indoklás:** a dal-import KÜLSŐ, nem megbízható fájlt olvas be (import-határ), a szerkesztő pedig felülírja a felhasználó saját tartalmát.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fájából `lib/features/songs/import/`, `lib/features/songs/editor/` **még nem létezik** — a képernyőket ez a kör hozza létre, tehát MINDEN szövege új.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `songs` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek

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
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z) `lib/features/songs/editor/`, `lib/features/songs/import/` könyvtár-előtag
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

Az UI-26–UI-28 **biztonságos** import-, leképezés- és szerkesztési felülete
(SDD Ch13 Kör 24).

## 2. Jelenlegi állapot — mért tények

- Az import csővezeték **létező** réteg: külső, nem megbízható fájlt dolgoz fel,
  és figyelmeztetéseket meg blokkoló hibákat ad vissza.
- Az R13 overlay-rendszere és az R11 űrlapelemei készen állnak.
- Az ADR 0279 kimondta: a megerősítés a következményt nevezi meg.

## 3. Scope

**Benne van:** az import folyamat (üres, választás, másolás, felismerés,
elemzés, megszakítás, hiba) · az import-előnézet sáv-választással,
figyelmeztetésekkel és **blokkoló** hibával · a szerkesztő compact strukturált
és expanded több-paneles elrendezése · mentetlen piszkozat, csak olvasható
forrás, ütközés, visszavonás/újra és mentési hiba állapotok · a húzás-műveletek
**billentyűs/gombos alternatívája** · rosszindulatú, nagy és nem támogatott
fixture-ök felületi integrációja.

**NINCS benne (tilos):** az elemző (parser) vagy az import-csővezeték logikájának
módosítása · a biztonsági ellenőrzések gyengítése · a tréner (Kör 25) ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `songs/import/` | az import és az előnézet felülete |
| `songs/editor/` | a szerkesztő |
| `lib/l10n/base/app_{en,hu}.arb` | **FORRÁS** — az import- és hibaszövegek (a kör feature-ei még nem migráltak, a kulcsaik itt élnek) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/songs/import/*_test.dart` (4) | a §6 cellái |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a kör új `lib/features/**/*_screen.dart`-ot hozhat, ezért az egzakt `hasLength(...)` elmozdul; a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4) |
| `docs/rounds/e13-r24-…md` | a §10 handoff |

**Tilos zóna:** az elemző és az import-csővezeték logikája ·
`lib/features/songs/` a két érintett almappán kívül ·
`lib/core/design_system/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` ·
`.github/**`.

## 5. Kötött architekturális döntések (ADR 0284)

### 5.1 Az előnézet NEM publikál és nem ment semmit

A preview kizárólag megmutat. Amíg a felhasználó nem erősít meg, nem keletkezik
tartós rekord, és semmi nem kerül ki a készülékről.

**NEM elfogadható gyengítés:** a dal „ideiglenes" mentése az előnézet
megnyitásakor, hogy egyszerűbb legyen az állapotkezelés. Onnantól a megszakítás
is hagy maga után adatot.

### 5.2 A megszakítás TAKARÍT

Megszakított import után nem marad ideiglenes fájl a készüléken. Ez
acceptance-cella (A2).

### 5.3 A blokkoló hiba NEM kerülhető meg

Ha az elemző blokkoló hibát ad, a felület nem kínál „mindegy, folytasd" utat. A
figyelmeztetés és a blokkoló hiba **két különböző** dolog, és a felületen is
annak látszik.

**NEM elfogadható gyengítés:** a blokkoló hiba figyelmeztetésként kezelése
„hogy a felhasználó ne akadjon el". Az egy nem megbízható fájlt engedne be.

### 5.4 A piszkozat MENTÉSI HIBA UTÁN IS megmarad

Ha a mentés elbukik, a szerkesztett tartalom nem vész el. A projekt már mérte,
hogy a `try/catch`-be fojtott írási hiba néma munkavesztést ad.

### 5.5 A csak olvasható forrás CSAK MÁSOLHATÓ

Szerkesztés helyett a felület saját másolat készítését kínálja (az R23 §5.2
folytatása).

### 5.6 A húzás-műveletnek van BILLENTYŰS/GOMBOS alternatívája

A szakaszok átrendezése nem köthető kizárólag húzáshoz — motorikusan korlátozott
és felolvasót használó felhasználónak is elérhető.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az előnézet nem hoz létre tartós rekordot és nem publikál | `import_flow_test.dart` |
| A2 | A megszakított import után nem marad ideiglenes fájl | ugyanott |
| A3 | A blokkoló hiba nem kerülhető meg | `import_blocking_error_test.dart` |
| A4 | A figyelmeztetés és a blokkoló hiba vizuálisan elkülönül | ugyanott |
| A5 | A piszkozat mentési hiba után is megmarad | `editor_draft_test.dart` |
| A6 | Csak olvasható forrásból csak másolat készíthető | ugyanott |
| A7 | Az átrendezés billentyűvel/gombbal is elvégezhető | `editor_keyboard_flow_test.dart` |
| A8 | A mentetlen kilépés következménye szövegben megjelenik | `editor_draft_test.dart` |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r24_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Az előnézet ideiglenes rekordot ment | **A1** |
| A megszakítás után marad temp fájl | **A2** |
| A blokkoló hiba „folytasd mindenképp" gombbal | **A3** |
| A figyelmeztetés és a blokkoló hiba azonos megjelenésű | A4 |
| A mentési hiba eldobja a piszkozatot | **A5** |
| Csak húzással átrendezhető szakaszok | **A7** |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**Az elemző-lelet három kötelező cellája** (a küszöb: a lelet súlyossága):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | tájékoztató lelet | látszik, az import folytatható |
| rajta (a küszöbön) | **figyelmeztetés** | látszik, kiemelten; az import **folytatható** megerősítéssel |
| a küszöb fölött | **blokkoló hiba** | az import **nem folytatható** — nincs megkerülő út |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** kezeld a blokkoló
hibát figyelmeztetésként → az **A3** cellának PIROSNAK kell lennie → állítsd
vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/songs/import/import_flow_test.dart test/features/songs/import/import_blocking_error_test.dart test/features/songs/import/editor_draft_test.dart test/features/songs/import/editor_keyboard_flow_test.dart test/ui/goldens/e13_r24_screens_golden_test.dart test/ui/ui_inventory_test.dart test/core/architecture_dependency_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
~/flutter/bin/flutter test --update-goldens test/ui/goldens/e13_r24_screens_golden_test.dart
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

1. Az import folyamat állapotai + megszakítás és takarítás.
2. Az előnézet — tartós rekord NÉLKÜL.
3. A lelet-súlyosság három cellája (tájékoztató / figyelmeztetés / blokkoló).
4. A szerkesztő compact és expanded elrendezése.
5. A piszkozat megőrzése mentési hiba után + a csak olvasható másolás.
6. Billentyűs/gombos átrendezés.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az „ideiglenes" mentés.** Egyszerűsíti az állapotkezelést, és a
  megszakítás után is adatot hagy (A1/A2).
- **A blokkoló hiba felpuhítása.** A felhasználó elakadása kellemetlen; a nem
  megbízható fájl beengedése rosszabb (A3).
- **A néma piszkozat-vesztés.** A projekt már mérte ezt a hibaosztályt: a
  `try/catch`-be fojtott írási hiba nem látszik, csak a munka tűnik el (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
