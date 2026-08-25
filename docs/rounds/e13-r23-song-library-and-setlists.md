# E13-R23 — Song Library, Overview és Setlist lista UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 74f8a8ec`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 23
- **Kör-azonosító:** `E13-R23`
- **Branch:** `<motor>/e13-r23-song-library-and-setlists`
- **Előfeltétel:** `E13-R22` merge-elve (gyakorlási eredmények)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — az ADR 0275 (legacy route) és 0277 érvényes.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a TÉNYLEGES dal-dokumentum
> modellt és repository-t, kiemelten a **forrás/licenc** mezőket — a §5.2
> jelölés csak a mért mezőkre írható meg. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/songs/library/",
  "lib/features/songs/overview/",
  "lib/features/setlists/",
  "lib/app/routing/",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/songs/song_library_test.dart",
  "test/features/songs/song_asset_state_test.dart",
  "test/features/songs/setlist_list_test.dart",
  "test/app/navigation/",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "docs/rounds/e13-r23-song-library-and-setlists.md",
]
gate_tests = [
  "test/features/songs/song_library_test.dart",
  "test/features/songs/song_asset_state_test.dart",
  "test/features/songs/setlist_list_test.dart",
  "test/app/navigation/",
  "test/ui/goldens/e13_r23_screens_golden_test.dart",
  "test/ui/ui_inventory_test.dart",
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

**Kockázat = high, indoklás:** a dal-könyvtár és a setlistek felhasználó által létrehozott tartalmat tárolnak és törölnek.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fájából `lib/features/songs/library/`, `lib/features/songs/overview/`, `lib/features/setlists/` **még nem létezik** — a képernyőket ez a kör hozza létre, tehát MINDEN szövege új.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `setlists` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek
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

### R3 — keresztmetszeti tesztek — a shell-destination őr FELVÉVE (H3 önjavító kör, ADR 0112, 2026-08-25)

> ⚠ **Ez a szakasz revideálva.** Az eredeti szöveg „nincs ilyen"-t állított. A
> sáv-szintű mérés szerint ez **hamis** minden olyan Ch13 körre, amelyik a
> routert is engedi — ez a kör ilyen (`lib/app/routing/` az `allowed_paths`-on).

Az E13-R08 óta a `test/app/navigation/` **három** őre route-onként PINNELI,
melyik képernyő-TÍPUS renderelődik: az öt destination
(`adaptive_scaffold_test.dart:196–216`), a tizenegy alútvonal-adapter (`:223–235`),
a tab-visszaállítás (`tab_state_restoration_test.dart`) és a tizenegy legacy
redirect célja (`legacy_route_redirect_test.dart:156–166`). Ez a kör a **Songs
terület** destinationjét és alútvonalát migrálja, amiket ma a
`SongListScreen`, illetve a `SetlistListScreen` típus pinnel — a
destination-builder átkötése tehát pirosra váltja őket.

MÉRT precedens ugyanezen az őrön (E13-R17, izolált klón `main @ 52df92b3`):
`flutter test test/app/navigation/` a bázison `+33 All tests passed`, három
destination-builder átkötése után `+30 -3`. Az őr felvétele az orchestrátornak
tágítás lenne, azaz H3 ([L478](../LESSONS.md)) — ezért kerül a listára MOST.

**A jogosultság PONTOSAN a lecserélt adapter TÍPUSÁNAK átírása** a ténylegesen
érintett cellákban. Minden más állítás — primary navigation megléte, a többi
adapter, a tab-visszaállítás mechanikája, a redirect-aciklikusság — érintetlen
marad; cella törlése, `skip`-je vagy gyengítése **TILOS**. A kör saját
pre-flightja mérje ki (`tools/round-gate.sh … test/app/navigation/`), PONTOSAN
melyik cellák pirosodnak — a lista tágítása nélkül, mert az őr már rajta van.

Ami továbbra is a listán KÍVÜL van (`test/core/**`, más feature-ek fái): ha egy
elbukik, az `blocked` jelzés és célzott brief-revízió, nem csendes átírás.

### R4 — a képernyő-leltár őre (H3 önjavító kör, ADR 0112, 2026-08-25)

A `test/ui/ui_inventory_test.dart` **repó-szintű** őr: a `tool/ui_inventory.dart`
a `lib/features/**` fa `_screen.dart` végű fájljait számolja, a teszt pedig
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z) `lib/features/setlists/`, `lib/features/songs/library/`, `lib/features/songs/overview/` könyvtár-előtag
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

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Az UI-24–UI-25 és UI-32 Songs-tartalmak migrációja **offline készenlét** és
**forrás/licenc** jelöléssel (SDD Ch13 Kör 23).

## 2. Jelenlegi állapot — mért tények

- Az R08 shellje és az R12 kártyái készen állnak; a Songs terület
  a shell egyik cél-destinationje.
- Az R10 ADR 0277: az offline nem hiba, a cached tartalom látható marad.
- A dalok egy része **közösségi / csak olvasható** forrásból származhat.

## 3. Scope

**Benne van:** a dal-könyvtár folytatás / keresés / szűrés / forrás / készenlét
komponensekkel · a dal áttekintő nézete (szakaszok, haladás, hangolás, eszközök,
elsődleges gyakorlás-akció) · a setlist-lista készenléti és **hiányzó dal**
állapotokkal · compact lista és expanded lista-részlet elrendezés · közösségi /
csak olvasható forrás, hiányzó offline eszköz, elérhető frissítés állapotok ·
route-alias teszt a meglévő útvonalakról.

**NINCS benne (tilos):** a dal-import vagy a szerkesztő (Kör 24) · a tréner
(Kör 25) · a dal-dokumentum séma módosítása · `docs/adr/**`, `tools/**`,
`.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `songs/library/` | a könyvtár UI-ja |
| `songs/overview/` | a dal áttekintő nézete |
| `setlists/` | a setlist-lista |
| `lib/app/routing/` | **kizárólag** az alias/redirect bejegyzések |
| `lib/l10n/base/app_{en,hu}.arb` | **FORRÁS** — a dal-szövegek (a kör feature-ei még nem migráltak, a kulcsaik itt élnek) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/songs/*_test.dart` (3) | a §6 cellái |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a kör új `lib/features/**/*_screen.dart`-ot hozhat, ezért az egzakt `hasLength(...)` elmozdul; a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4) |
| `docs/rounds/e13-r23-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/songs/import/`, `editor/`, `trainer/` ·
`lib/core/design_system/**` · `lib/core/theme/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 A helyi dal OFFLINE elérhető

A készüléken tárolt dal hálózat nélkül is megnyitható és gyakorolható. Az
offline állapot nem tesz semmit elérhetetlenné, ami helyben megvan.

### 5.2 A forrás és a licenc-státusz LÁTHATÓ

A felhasználónak tudnia kell, saját importja, beépített vagy közösségi
tartalmat néz-e, és hogy szerkesztheti-e. Ez az ADR 0278 provenance-elvének
tartalmi megfelelője.

**NEM elfogadható gyengítés:** a forrás elrejtése „egységes lista-megjelenés"
kedvéért. A csak olvasható tartalom szerkesztési kísérlete így csak a hibánál
derülne ki.

### 5.3 A hiányzó kísérőhang NEM rejti el a többi tartalmat

Ha a backing track nincs letöltve, a dal szövege, akkordjai és szakaszai
továbbra is elérhetők. Csak az érintett funkció jelöli a hiányt.

**NEM elfogadható gyengítés:** a teljes dal letiltása hiányzó eszköz miatt.
A tartalom nagy része hangfájl nélkül is használható.

### 5.4 A setlist SORRENDJE és készenléte pontos

A sorrend a felhasználóé; a készenlét minden tételre külön látszik, a hiányzó
dal pedig **nevesítve** jelenik meg, nem néma kihagyással.

### 5.5 A legacy route MŰKÖDIK

Az ADR 0275 §3 alkalmazása a Songs területre.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A helyi dal offline megnyitható | `song_asset_state_test.dart` |
| A2 | A forrás és a licenc-státusz látható a listában és az áttekintőben | `song_library_test.dart` |
| A3 | A csak olvasható forrás szerkesztése nem indítható | ugyanott |
| A4 | Hiányzó kísérőhang mellett a többi tartalom elérhető | `song_asset_state_test.dart` |
| A5 | A setlist sorrendje és tételenkénti készenléte helyes | `setlist_list_test.dart` |
| A6 | A hiányzó dal nevesítve jelenik meg a setlistben | ugyanott |
| A7 | A legacy songs/setlists route-ok működnek | `song_library_test.dart` |
| A8 | A keresés és a szűrés állapota megmarad visszatéréskor | ugyanott |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r23_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A forrás nem jelenik meg a listában | **A2** |
| A csak olvasható dal szerkeszthető | **A3** |
| Hiányzó backing track → a dal letiltva | **A4** |
| A hiányzó setlist-tétel némán kimarad | **A6** |
| A legacy route törölve | A7 |
| A szűrő visszatéréskor nullázódik | A8 |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**Az eszköz-készenlét három kötelező cellája** (a küszöb: mely eszköz hiányzik):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | minden eszköz megvan | teljes funkcionalitás |
| rajta (a küszöbön) | **a kísérőhang hiányzik**, a dokumentum megvan | a dal **megnyitható**, csak a lejátszás jelöli a hiányt |
| a küszöb fölött | maga a dal-dokumentum hiányzik | a tétel hibásként, **nevesítve** jelenik meg |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** tiltsd le a dalt
hiányzó kísérőhang esetén → az **A4** cellának PIROSNAK kell lennie → állítsd
vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/songs/song_library_test.dart test/features/songs/song_asset_state_test.dart test/features/songs/setlist_list_test.dart test/app/navigation/ test/ui/goldens/e13_r23_screens_golden_test.dart test/ui/ui_inventory_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
~/flutter/bin/flutter test --update-goldens test/ui/goldens/e13_r23_screens_golden_test.dart
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

1. A könyvtár lista + keresés/szűrés/folytatás, állapotmegőrzéssel.
2. A forrás/licenc jelölés és a csak olvasható zárolás.
3. Az eszköz-készenlét három cellája.
4. A dal áttekintő nézete + elsődleges gyakorlás-akció.
5. A setlist-lista sorrenddel, készenléttel, nevesített hiánnyal.
6. A legacy route-aliasok + a hozzájuk tartozó cella.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A hiányzó eszköz miatti teljes letiltás.** Egyszerű szabály, és
  használhatatlanná tesz egy amúgy teljes dalt (A4).
- **A rejtett forrás.** A szerkesztési kísérlet csak hibánál derül ki, ami a
  felhasználó munkáját viszi (A2/A3).
- **A néma setlist-kihagyás.** Fellépés közben a legrosszabb: a felhasználó nem
  tudja, mi maradt ki (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
