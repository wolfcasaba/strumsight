# E13-R17 — Today, Practice és Profile hubok

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 6adea220`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 17
- **Kör-azonosító:** `E13-R17`
- **Branch:** `<motor>/e13-r17-today-practice-profile-hubs`
- **Előfeltétel:** `E13-R16` merge-elve (onboarding) + az R08 adaptív navigáció
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — az ADR 0275 (flag mögötti shell) érvényes.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd fel, milyen TÉNYLEGES terv- és
> gamifikációs adatforrás érhető el (Chapter 8/9 rétegei), mert a hubok fake
> repository-interfészre épülnek — ha a valódi forrás hiányzik, a §5.5 szerint
> a fake az elfogadott. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/today/",
  "lib/features/practice_hub/",
  "lib/features/profile_hub/",
  "lib/app/routing/",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/today/today_hub_test.dart",
  "test/features/today/hub_navigation_test.dart",
  "test/features/profile/profile_hub_test.dart",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "docs/rounds/e13-r17-today-practice-profile-hubs.md",
]
gate_tests = [
  "test/features/today/today_hub_test.dart",
  "test/features/today/hub_navigation_test.dart",
  "test/features/profile/profile_hub_test.dart",
  "test/ui/goldens/e13_r17_screens_golden_test.dart",
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

**Kockázat = high, indoklás:** az `lib/app/routing/` belépési pontok és route-őrök (authorization-határ) módosulnak, és a hubok a felhasználó teljes adatfelületére navigálnak.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fájából `lib/features/today/`, `lib/features/practice_hub/`, `lib/features/profile_hub/` **még nem létezik** — a képernyőket ez a kör hozza létre, tehát MINDEN szövege új.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `practice_hub` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek
- `profile_hub` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek
- `today` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek

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
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z) `lib/features/practice_hub/`, `lib/features/profile_hub/`, `lib/features/today/` könyvtár-előtag
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

Az UI-05–UI-07 cél-hubok bevezetése **flag mögött**, a legacy tartalmak
fokozatos összefogásával (SDD Ch13 Kör 17).

## 2. Jelenlegi állapot — mért tények

- Az R08 létrehozta az ötterületes shellt flag mögött, legacy adapterekkel — ez
  a kör tölti meg tartalommal a Today, Practice és Profile területet.
- Az R12 kártyái, az R10 állapotai és az R11 űrlapelemei készen állnak.
- Az ADR 0276 tiltja, hogy prezentációs réteg erőforrást nyisson — a hubokra ez
  külön acceptance-cella (A4).

## 3. Scope

**Benne van:** Today Hub összegzés-központú elrendezés · Practice Hub katalógus
és gyors eszközök **képesség-kapukkal** · Profile Hub helyi / bejelentkezett /
közösség-engedélyezett állapotai · adapter a meglévő Live/Analyze/Learn/Library/
Settings route-okhoz · offline cached, terv nélküli, új felhasználó,
sync-várakozó és letiltott képesség állapotok · compact/medium/expanded
elrendezés.

**NINCS benne (tilos):** Stage / Live / Tuner / Song képernyők migrációja
(Kör 18+) · a shell-flag **bekapcsolása** · mikrofon vagy kamera indítása ·
`lib/core/design_system/**` módosítása · `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/today/` | **ÚJ** — Today Hub |
| `lib/features/practice_hub/` | **ÚJ** — Practice Hub |
| `lib/features/profile_hub/` | **ÚJ** — Profile Hub |
| `lib/app/routing/` | a három hub bekötése a shellbe |
| `lib/l10n/base/app_{en,hu}.arb` | **FORRÁS** — a hub-szövegek (a kör feature-ei még nem migráltak, a kulcsaik itt élnek) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/**` (3) | a §6 cellái |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a kör új `lib/features/**/*_screen.dart`-ot hozhat, ezért az egzakt `hasLength(...)` elmozdul; a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4) |
| `docs/rounds/e13-r17-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a három hub KIVÉTELÉVEL ·
`lib/core/design_system/**` · `lib/core/theme/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 A hubok NEM indítanak mikrofont vagy kamerát

Áttekintő felületek. Az erőforrás a Stage-en indul, felhasználói szándékra
(ADR 0276 folytatása).

**NEM elfogadható gyengítés:** a hangoló előnézetének „élővé tétele" a Practice
Hubon. Az háttérben futó mikrofont jelentene egy listaképernyőn.

### 5.2 A Today EGY egyértelmű elsődleges akciót ad

Az R11 „egy képernyő — egy primary CTA" szabálya. A hub célja az irányítás, nem
a választék bemutatása.

### 5.3 A Profile fiók NÉLKÜL is értelmes

A termék logout állapotban teljesen használható. A Profile ilyenkor a helyi
adatokat és beállításokat mutatja, nem bejelentkezési falat.

**NEM elfogadható gyengítés:** bejelentkezési fal a Profile területen. Az egy
offline-first terméket tesz feltételessé.

### 5.4 A legacy route ELÉRHETŐ marad

Az ADR 0275 §3 szerint: a hubok nem szüntetik meg a régi utakat.

### 5.5 A hiányzó adatforrás FAKE interfésszel pótolt, nem kitalált adattal

Ha a terv- vagy gamifikációs adat még nem elérhető, a hub interfészt használ, és
a **teszt** adja a fake implementációt. A felületen nem jelenik meg kitalált
statisztika.

### 5.6 A letiltott képesség MEGMONDJA, miért

A Vision kártya letiltott állapotban elmagyarázza az okot — nem tűnik el némán,
és nem is kattinthatatlan rejtély.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A Today egyetlen egyértelmű elsődleges akciót ad | `today_hub_test.dart` |
| A2 | A Practice eszközei két érintésen belül elérhetők | `hub_navigation_test.dart` |
| A3 | A Profile fiók nélkül is értelmes tartalmat mutat | `profile_hub_test.dart` |
| A4 | A hubok NEM indítanak mikrofont/kamerát | `today_hub_test.dart` + `grep` a diffben |
| A5 | A legacy route-ok elérhetők maradnak | `hub_navigation_test.dart` |
| A6 | Offline állapotban a cached tartalom látszik (ADR 0277) | `today_hub_test.dart` |
| A7 | A letiltott képesség kártyája megmondja az okot | ugyanott |
| A8 | Nincs kitalált statisztika hiányzó adatforrás mellett | `today_hub_test.dart` |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r17_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Három egyenrangú primary gomb a Todayen | **A1** |
| A hangoló élő előnézete a Practice Hubon | **A4** |
| Bejelentkezési fal a Profile-on | **A3** |
| A legacy route törlése | **A5** |
| Offline → üres képernyő | A6 |
| A Vision kártya némán eltűnik | A7 |
| Nulla helyett kitalált „7 napos széria" | **A8** |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**A gyakorlási eszköz elérési mélységének három kötelező cellája** (a küszöb:
**2 érintés**):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | 1 érintés (közvetlen gyors eszköz) | elfogadva |
| rajta (a küszöbön) | **2 érintés** | **elfogadva** (a határ inkluzív) |
| a küszöb fölött | 3 érintés | **elutasítva** — a cella PIROS |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** tedd a metronómot egy
harmadik szint mögé → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/today/today_hub_test.dart test/features/today/hub_navigation_test.dart test/features/profile/profile_hub_test.dart test/ui/goldens/e13_r17_screens_golden_test.dart test/ui/ui_inventory_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
~/flutter/bin/flutter test --update-goldens test/ui/goldens/e13_r17_screens_golden_test.dart
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

1. A három hub repository-interfésze (fake implementáció a tesztben).
2. Today Hub — összegzés + EGY elsődleges akció.
3. Practice Hub — katalógus, gyors eszközök, képesség-kapuk + a mélység-cella.
4. Profile Hub — helyi / bejelentkezett / közösségi állapot.
5. Legacy adapterek + route-elérhetőség cellája.
6. Offline, terv nélküli, új felhasználó, sync-várakozó állapotok.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A kitalált statisztika.** Üres állapotban „szebb" egy nullánál, és
  hazugság — a projekt legveszélyesebb hibaosztálya (A8).
- **A bejelentkezési fal.** Kézenfekvő a Profile-on, és megtöri az
  offline-first ígéretet (A3).
- **Az élő előnézet.** Látványos, és háttérben futó mikrofont jelent egy
  áttekintő képernyőn (A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
