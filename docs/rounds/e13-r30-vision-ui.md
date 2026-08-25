# E13-R30 — Vision Setup, Coach és Result UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 0f7afd9a`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 30
- **Kör-azonosító:** `E13-R30`
- **Branch:** `<motor>/e13-r30-vision-ui`
- **Előfeltétel:** `E13-R29` merge-elve (coach/tutor)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0288`](../adr/0288-camera-frames-stay-on-device-and-one-cue.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd meg, hogy a vision modell-
> bináris és a képkocka-forrás TÉNYLEGESEN elérhető-e ezen a build-en (a
> projekt korábban mérte, hogy a vision rollout hiányzó modell-binárison
> BLOKKOLT). Ha nincs, a kör a **fake képkocka-folyamra** épül, és ezt a §10
> rögzíti. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/vision/presentation/guitar_calibration_screen_test.dart",
  "test/features/vision/presentation/vision_preview_overlay_test.dart",
  "test/features/vision/presentation/vision_setup_screen_test.dart",
  "test/features/vision/vision_permission_test.dart",
  "test/features/vision/vision_one_cue_test.dart",
  "test/features/vision/vision_cleanup_test.dart",
  "test/features/vision/vision_degraded_test.dart",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "docs/rounds/e13-r30-vision-ui.md",
]
gate_tests = [
  "test/features/vision/vision_permission_test.dart",
  "test/features/vision/vision_one_cue_test.dart",
  "test/features/vision/vision_cleanup_test.dart",
  "test/features/vision/vision_degraded_test.dart",
  "test/ui/goldens/e13_r30_screens_golden_test.dart",
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

**Kockázat = high, indoklás:** a vision felület a KAMERA-engedélyt (camera/authorization) kéri és élő képet dolgoz fel.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fája ma **89** l10n-kulcsot használ, és mind feloldható: `app` = 89 kulcs.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `vision` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek

Az aggregátum a listán MARAD, de **kizárólag generált kimenetként**
(`dart run tool/gen_l10n_segments.dart --write`); a merge-elt precedens
egységesen a forrást ÉS a regenerált aggregátumot is commitolja (E09-R26
`df0ad3dd`, E13-R12 `376b8a1d`, E13-R10 `b11ab2ed`). **Új fragmentum NEM
készül**, ezért a `test/l10n/arb_parity_test.dart` beégetett szegmens-listáját
sem kell bővíteni — a felvett források mind szerepelnek benne.

### R2 — a kör SAJÁT feature-fáján élő, ma zöld widget-tesztek (FELVÉVE)

Ezek közvetlenül a migrálandó képernyőkre állítanak, tehát a migráció után
pirosra váltanának, ami a §0 szerint `blocked` lenne:

  - `test/features/vision/presentation/guitar_calibration_screen_test.dart`
  - `test/features/vision/presentation/vision_preview_overlay_test.dart`
  - `test/features/vision/presentation/vision_setup_screen_test.dart`

**A jogosultság szűk:** a teszteket az ÚJ widgetekre kell ráállítani. A lefedett
viselkedést gyengíteni, cellát törölni vagy `skip`-elni **TILOS** — az a mérce
meggyengítése, amit a gate-guard emberhez eszkalál.

### R3 — keresztmetszeti tesztek (NEM kerültek listára — figyelmeztetés)

A kör fájára hivatkozó további widget-tesztek közös infrastruktúrán élnek
(`test/app/**`, `test/core/**`, más feature-ek fái) — 3 ilyen fájl van. Ezeket a kör
**NEM** szerkesztheti: ha egy elbukik, az `blocked` jelzés és célzott
brief-revízió, nem csendes átírás. A körbe húzásuk a scope-fegyelem feladása
lenne.

### R4 — a képernyő-leltár őre (H3 önjavító kör, ADR 0112, 2026-08-25)

A `test/ui/ui_inventory_test.dart` **repó-szintű** őr: a `tool/ui_inventory.dart`
a `lib/features/**` fa `_screen.dart` végű fájljait számolja, a teszt pedig
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z) `lib/features/vision/` könyvtár-előtag
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

Az UI-45–UI-47 kamera-, kalibrációs, élő-jelzés és eredmény-felülete
**adatvédelmi és hő-védelemmel** (SDD Ch13 Kör 30).

## 2. Jelenlegi állapot — mért tények

- Az R09 StageScaffoldja, az R10 engedély-állapotai és az R29 coach-akciói
  készen állnak.
- A kamera a mikrofonnál is érzékenyebb bemenet: a képkocka a felhasználó
  otthonáról készül.
- A vision képesség **eszközfüggő** — a nem támogatott készüléknek is kell út.

## 3. Scope

**Benne van:** a Vision beállítás engedély-primerrel, elhelyezési útmutatóval,
előnézettel és kalibrációs készenléttel · a Vision coach **egy-jelzéses** Stage
elrendezése gyenge fény / takarás / követés elvesztése / hő / csak-hang
állapotokkal · az eredmény követés-minőség, technikai mérőszám és korrekciós
elrendezése · **labor-only** hibakereső csontváz flag mögött, productionben
rejtve · kamera- és mikrofon-jelzés, route-takarítás és **képkocka-megőrzés**
státusz · fake képkocka-folyamon és hő-állapoton alapuló determinisztikus
tesztek.

**NINCS benne (tilos):** a vision modell vagy a képfeldolgozás módosítása
(AGENTS.md §9) · a képkockák alapértelmezett mentése · a hibakereső csontváz
production útvonalon · `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/vision/` | a három felület |
| `lib/l10n/base/app_{en,hu}.arb` | **FORRÁS** — a vision-szövegek (a kör feature-ei még nem migráltak, a kulcsaik itt élnek) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/…` (3 meglévő teszt) | ma zöld, a migrált képernyőkre állítandó — lásd §0.0 R2 |
| `test/features/vision/*_test.dart` (4) | a §6 cellái |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a kör új `lib/features/**/*_screen.dart`-ot hozhat, ezért az egzakt `hasLength(...)` elmozdul; a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4) |
| `docs/rounds/e13-r30-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a `vision/` KIVÉTELÉVEL · a vision modell és
a képfeldolgozás · `lib/core/design_system/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0288)

### 5.1 A kamera CSAK explicit felhasználói akció után indul

Nem a képernyő megnyitásakor, nem előnézet céljából. Az ADR 0276 elve a
legérzékenyebb bemenetre.

**NEM elfogadható gyengítés:** „az előnézet a beállítás megnyitásakor indul,
hogy gyorsabb legyen". Az a felhasználó otthonáról készít képet kérés nélkül.

### 5.2 A képkocka ALAPBÓL nem mentődik

A feldolgozás a készüléken, memóriában történik. Mentés csak explicit
felhasználói döntésre, és a státusz végig látható (az ADR 0285 §1 elve a
képre).

### 5.3 EGYSZERRE EGY prioritásos jelzés

Játék közben több egyidejű korrekciós jelzés használhatatlan. A felület mindig
a legfontosabbat mutatja — ez acceptance-cella (A3), nem stílus.

**NEM elfogadható gyengítés:** három jelzés egymás alatt, „mert mindegyik
hasznos". Játék közben egyik sem lesz feldolgozható.

### 5.4 Az alacsony megbízhatóság NEM kategorikus

Az ADR 0283 §1 alkalmazása a technikai mérőszámokra.

### 5.5 A nem támogatott eszköz CSAK-HANG alternatívát kap

Nem üres képernyőt és nem „a készüléked nem alkalmas" zsákutcát.

### 5.6 A hibakereső csontváz LABOR-ONLY

Flag mögött, production útvonalon nem elérhető (az R02 §5.4 mintája).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A kamera csak explicit akció után indul | `vision_permission_test.dart` |
| A2 | A képkocka alapból nem mentődik, és a státusz látható | ugyanott |
| A3 | Egyszerre pontosan egy prioritásos jelzés látszik | `vision_one_cue_test.dart` |
| A4 | Alacsony megbízhatóságnál az eredmény nem kategorikus | `vision_degraded_test.dart` |
| A5 | Hő-korlát és követés-vesztés külön, kimondott állapot | ugyanott |
| A6 | Nem támogatott eszköz csak-hang alternatívát kap | `vision_permission_test.dart` |
| A7 | A kamera és a mikrofon minden kilépési úton felszabadul | `vision_cleanup_test.dart` |
| A8 | A hibakereső csontváz productionben nem elérhető | `vision_one_cue_test.dart` |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r30_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A kamera a képernyő megnyitásakor indul | **A1** |
| A képkockák naplózásra mentve | **A2** |
| Két jelzés egyszerre | **A3** |
| Kategorikus technikai pontszám gyenge követésnél | A4 |
| A hő-korlát néma lassulásként | A5 |
| A kamera nyitva marad háttérbe kerüléskor | **A7** |
| A csontváz production route-on | A8 |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**A jelzés-prioritás három kötelező cellája** (a küszöb: egyidejű jelzések száma):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | nincs korrekciós lelet | **0** jelzés — a Stage tiszta |
| rajta (a küszöbön) | **1** lelet | 1 jelzés |
| a küszöb fölött | 3 egyidejű lelet | **1** jelzés — a legmagasabb prioritású |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** jeleníts meg két
jelzést egyszerre → az **A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision/vision_permission_test.dart test/features/vision/vision_one_cue_test.dart test/features/vision/vision_cleanup_test.dart test/features/vision/vision_degraded_test.dart test/ui/goldens/e13_r30_screens_golden_test.dart test/ui/ui_inventory_test.dart test/core/architecture_dependency_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
~/flutter/bin/flutter test --update-goldens test/ui/goldens/e13_r30_screens_golden_test.dart
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

> **Review-megjegyzés:** ez a kör kamerát és adatmegőrzést érint, ezért a
> review-ban a `security-reviewer` ügynök futtatása kötelező.

## 8. Implementációs sorrend

1. A beállítás engedély-primerrel — kamera CSAK explicit akcióra.
2. A képkocka-megőrzés státusza, alapból mentés nélkül.
3. Az egy-jelzéses Stage + a három prioritás-cella.
4. Gyenge fény / takarás / követés-vesztés / hő / csak-hang állapotok.
5. Az eredmény-felület, nem kategorikus alacsony megbízhatósággal.
6. Kamera- és mikrofon-takarítás minden kilépési úton; labor-only csontváz.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az „azonnali" előnézet.** Gyorsabbnak hat, és kérés nélkül kapcsolja be a
  kamerát a felhasználó otthonában (A1).
- **A három egyidejű jelzés.** Mindegyik hasznosnak tűnik, és együtt
  használhatatlanok játék közben (A3).
- **A hibakeresés kedvéért mentett képkocka.** A legérzékenyebb adat, és a
  fejlesztői kényelem viszi ki (A2).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
