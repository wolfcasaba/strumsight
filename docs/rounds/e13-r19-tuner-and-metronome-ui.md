# E13-R19 — Tuner és Metronome UI migráció

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ e9a2c8b2`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 19
- **Kör-azonosító:** `E13-R19`
- **Branch:** `<motor>/e13-r19-tuner-and-metronome-ui`
- **Előfeltétel:** `E13-R18` merge-elve (Live Stage)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — az ADR 0274 (audio óra) és 0280 érvényes.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a TÉNYLEGES hangmagasság-
> becslő kimenetét (a YIN-alapú réteg típusa és mezői), mert a §6 A1 cellája
> erre a kimenetre képez UI-állapotot. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/tuner/",
  "lib/features/metronome/",
  "lib/core/design_system/components/music/ss_tuner_gauge.dart",
  "lib/core/design_system/public.dart",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/features/tuner_en.arb",
  "lib/l10n/features/tuner_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/metronome/metronome_screen_test.dart",
  "test/features/tuner/cents_gauge_semantics_test.dart",
  "test/features/tuner/manual_string_pin_test.dart",
  "test/features/tuner/reference_tone_test.dart",
  "test/features/tuner/string_chips_test.dart",
  "test/features/tuner/tuner_screen_error_test.dart",
  "test/features/tuner/tuning_selector_test.dart",
  "test/features/tuner/tuner_ui_mapping_test.dart",
  "test/features/tuner/tuner_route_cleanup_test.dart",
  "test/features/metronome/metronome_beat_sync_test.dart",
  "test/ui/goldens/",
  "docs/rounds/e13-r19-tuner-and-metronome-ui.md",
]
gate_tests = [
  "test/features/tuner/tuner_ui_mapping_test.dart",
  "test/features/tuner/tuner_route_cleanup_test.dart",
  "test/features/metronome/metronome_beat_sync_test.dart",
  "test/ui/goldens/e13_r19_screens_golden_test.dart",
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

**Kockázat = high, indoklás:** a hangoló a mikrofon-erőforrást (authorization) tartja nyitva; a hangmagasság- és cent-kijelzés igazmondása mérce.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fája ma **19** l10n-kulcsot használ, és mind feloldható: `tuner` = 14 kulcs, `app` = 5 kulcs.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `metronome` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek
- `tuner` → a MÁR LÉTEZŐ `features/tuner_*.arb` fragmentum

Az aggregátum a listán MARAD, de **kizárólag generált kimenetként**
(`dart run tool/gen_l10n_segments.dart --write`); a merge-elt precedens
egységesen a forrást ÉS a regenerált aggregátumot is commitolja (E09-R26
`df0ad3dd`, E13-R12 `376b8a1d`, E13-R10 `b11ab2ed`). **Új fragmentum NEM
készül**, ezért a `test/l10n/arb_parity_test.dart` beégetett szegmens-listáját
sem kell bővíteni — a felvett források mind szerepelnek benne.

### R2 — a kör SAJÁT feature-fáján élő, ma zöld widget-tesztek (FELVÉVE)

Ezek közvetlenül a migrálandó képernyőkre állítanak, tehát a migráció után
pirosra váltanának, ami a §0 szerint `blocked` lenne:

  - `test/features/metronome/metronome_screen_test.dart`
  - `test/features/tuner/cents_gauge_semantics_test.dart`
  - `test/features/tuner/manual_string_pin_test.dart`
  - `test/features/tuner/reference_tone_test.dart`
  - `test/features/tuner/string_chips_test.dart`
  - `test/features/tuner/tuner_screen_error_test.dart`
  - `test/features/tuner/tuning_selector_test.dart`

**A jogosultság szűk:** a teszteket az ÚJ widgetekre kell ráállítani. A lefedett
viselkedést gyengíteni, cellát törölni vagy `skip`-elni **TILOS** — az a mérce
meggyengítése, amit a gate-guard emberhez eszkalál.

### R3 — keresztmetszeti tesztek (NEM kerültek listára — figyelmeztetés)

A kör fájára hivatkozó további widget-tesztek közös infrastruktúrán élnek
(`test/app/**`, `test/core/**`, más feature-ek fái) — 7 ilyen fájl van. Ezeket a kör
**NEM** szerkesztheti: ha egy elbukik, az `blocked` jelzés és célzott
brief-revízió, nem csendes átírás. A körbe húzásuk a scope-fegyelem feladása
lenne.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

A hangoló és a metronóm (UI-09–UI-10) átállítása a közös Stage-komponensekre,
**pontos audio-óra** és hozzáférhető viselkedés mellett (SDD Ch13 Kör 19).

## 2. Jelenlegi állapot — mért tények

- Az ADR 0274 kimondta: a ritmus-animáció az audio órából jön, nem külön
  `Timer`-ből — a metronóm ennek a legkritikusabb alkalmazása.
- Az ADR 0280 kimondta: a tuner cents-eltérése **felolvasható** kell legyen.
- A tap tempo kiugró-érték kezelése meglévő, tesztelt viselkedés.

## 3. Scope

**Benne van:** `SsTunerGauge` és hangolás/húr-választó · a hangoló idle,
hallgató, nincs hangmagasság, instabil, hangolt és referenciahang állapotai ·
a metronóm fő BPM/ütem/transport elrendezése (a haladó beállítások **lapra**
kerülnek) · az ütem-vizualizáció az **audio óra állapotához** kötve · landscape
és expanded elrendezés · a route elhagyásakor audio-fókusz és erőforrás
felszabadítása.

**NINCS benne (tilos):** a hangmagasság-becslő vagy a metronóm időzítésének
módosítása (AGENTS.md §9) · a tap tempo kiugró-kezelés viselkedésének
megváltoztatása · más képernyők migrációja · `docs/adr/**`, `tools/**`,
`.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/tuner/` | a hangoló UI-migrációja |
| `lib/features/metronome/` | a metronóm UI-migrációja |
| `components/music/ss_tuner_gauge.dart` | **ÚJ** — a mutató |
| `public.dart` | az export bővítése |
| `lib/l10n/features/tuner_{en,hu}.arb` | **FORRÁS** — a hangoló/metronóm szövegek (`tuner` MÁR migrált feature) |
| `lib/l10n/base/app_{en,hu}.arb` | **FORRÁS** — kizárólag a **metronóm** szövegei (a `metronome` még nem migrált feature; a hangolóé a `tuner` fragmentumba megy) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/…` (7 meglévő teszt) | ma zöld, a migrált képernyőkre állítandó — lásd §0.0 R2 |
| `test/features/**` (3) | a §6 cellái |
| `docs/rounds/e13-r19-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a két érintett KIVÉTELÉVEL · a DSP- és
időzítés-paraméterek bárhol · `lib/core/theme/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 A cents-eltérés IRÁNYA szöveges

„12 centtel mély" — nem csak egy elmozduló mutató. Az ADR 0280 §3
kikényszerítése.

**NEM elfogadható gyengítés:** csak a grafikus mutató, mert „az intuitívabb".
Felolvasóval használhatatlan, és nagy betűméret mellett is nehezen olvasható.

### 5.2 A „hangolt" visszajelzés TÖBBCSATORNÁS

Szín + ikon/szöveg (és ahol elérhető, haptika). Nem csak a mutató zöldre
váltása.

### 5.3 Az ütem-vizualizáció NEM külön `Timer`

Az ADR 0274 kötelező alkalmazása: a vizuális ütem az audio óra állapotát követi
— fake órával determinisztikusan tesztelve.

**NEM elfogadható gyengítés:** `Timer.periodic` a BPM-ből. Ez mérve elcsúszó
metronómot ad, ami a funkció lényegét semmisíti meg.

### 5.4 A referenciahang a route elhagyásakor LEÁLL

Nem szólhat tovább háttérben. Az audio-fókusz is felszabadul.

### 5.5 A tap tempo kiugró-kezelése VÁLTOZATLAN

Meglévő, tesztelt viselkedés — a UI-migráció nem érinti.

### 5.6 A haladó beállítások LAPRA kerülnek

A fő felület a BPM, az ütem és a transport. Az R13 overlay-rendszere adja a
lapot.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A hangmagasság-kimenet UI-állapotra képzése helyes minden ágon | `tuner_ui_mapping_test.dart` |
| A2 | A cents-eltérés iránya szövegesen is megjelenik | ugyanott |
| A3 | A „hangolt" visszajelzés több csatornán érkezik | ugyanott |
| A4 | Az ütem-vizualizáció az audio órához kötött (fake órával mérve) | `metronome_beat_sync_test.dart` |
| A5 | A referenciahang és az audio-fókusz a route elhagyásakor felszabadul | `tuner_route_cleanup_test.dart` |
| A6 | A tap tempo kiugró-kezelése változatlan | a meglévő tesztek zöldek |
| A7 | 2.0 text scale és landscape mellett nincs túlcsordulás | `tuner_ui_mapping_test.dart` |
| A8 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r19_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Csak grafikus mutató, szöveg nélkül | **A2** |
| A „hangolt" csak zöld szín | **A3** |
| `Timer.periodic` az ütemre | **A4** |
| A referenciahang tovább szól kilépés után | **A5** |
| A kiugró tap tempo átírása | A6 |
| Fix magasságú hangoló-fejléc | A7 |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A8** |

**A „hangolt" tartomány három kötelező cellája** (a küszöb: **±5 cent**):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | ±3 cent | **hangolt** |
| rajta (a küszöbön) | pontosan **±5 cent** | **hangolt** (a határ inkluzív) |
| a küszöb fölött | ±9 cent | **nem hangolt** — irány szövegesen |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** cseréld az
ütem-vizualizáció forrását `Timer.periodic`-ra → az **A4** cellának PIROSNAK
kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/tuner/tuner_ui_mapping_test.dart test/features/tuner/tuner_route_cleanup_test.dart test/features/metronome/metronome_beat_sync_test.dart test/ui/goldens/e13_r19_screens_golden_test.dart
```

**A golden-felvétel (A8) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
~/flutter/bin/flutter test --update-goldens test/ui/goldens/e13_r19_screens_golden_test.dart
```

A keletkezett PNG-ket **commitolni kell** — enélkül az A8 nem teljesült. A
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

1. A hangmagasság-kimenet → UI-állapot leképezés + a ±5 cent cellák.
2. `ss_tuner_gauge.dart` + a szöveges irány és a többcsatornás visszajelzés.
3. A hangoló hat állapota, húr- és hangolás-választóval.
4. A metronóm elrendezése; a haladó beállítások lapra.
5. Az ütem-vizualizáció audio órához kötve, fake órás cellával.
6. Route-elhagyás: referenciahang + audio-fókusz felszabadítása.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A `Timer`-es metronóm.** A legkézenfekvőbb implementáció, és mérve
  elcsúszik — pont a funkció lényegén (A4).
- **A tovább szóló referenciahang.** Kilépés után is hallható, és a
  felhasználó nem találja, mi szól (A5).
- **A csak grafikus hangoló.** Intuitívnak tűnik, és felolvasóval semmit nem
  mond (A2).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
