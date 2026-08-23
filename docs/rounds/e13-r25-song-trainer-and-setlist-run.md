# E13-R25 — Song Trainer, Result és Setlist Run UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 74f8a8ec`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 25
- **Kör-azonosító:** `E13-R25`
- **Branch:** `<motor>/e13-r25-song-trainer-and-setlist-run`
- **Előfeltétel:** `E13-R24` merge-elve (import és szerkesztő)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — az ADR 0274 (audio óra) és 0283 érvényes.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a TÉNYLEGES lejátszási és
> pontozási állapotot (`lib/features/songs/`), kiemelten azt, hogy létezik-e
> „csak lejátszás" mód — a §5.1 erre a mért állapotra épül. Eltérésnél §0.0
> revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/songs/trainer/",
  "lib/features/songs/results/",
  "lib/features/setlists/run/",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/songs/trainer/trainer_setup_test.dart",
  "test/features/songs/trainer/playhead_loop_sync_test.dart",
  "test/features/songs/trainer/playback_only_result_test.dart",
  "test/features/songs/trainer/setlist_run_test.dart",
  "test/fixtures/songs/trainer/",
  "test/ui/goldens/",
  "docs/rounds/e13-r25-song-trainer-and-setlist-run.md",
]
gate_tests = [
  "test/features/songs/trainer/trainer_setup_test.dart",
  "test/features/songs/trainer/playhead_loop_sync_test.dart",
  "test/features/songs/trainer/playback_only_result_test.dart",
  "test/features/songs/trainer/setlist_run_test.dart",
  "test/ui/goldens/e13_r25_screens_golden_test.dart",
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

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Az UI-29–UI-31 és UI-33 teljes Stage/analitika folyamata szinkron-, loop- és
csak-lejátszás állapotokkal (SDD Ch13 Kör 25).

## 2. Jelenlegi állapot — mért tények

- Az R09 StageScaffoldja és az ADR 0274 óra-szabálya adott: a lejátszófej és a
  loop az **audio órából** vezetett.
- Az R22 ADR 0283 kimondta: az eredmény nem állíthat többet, mint amit mért.
- Nagy dalnál a kotta-nézet teljesítménye külön kockázat (a Ch13 maga jelzi).

## 3. Scope

**Benne van:** a tréner beállítása (szakasz, sebesség, loop, kísérőhang-keverés,
pontozási készenlét) · a tréner portrait / landscape / expanded kotta +
lejátszófej Stage-elrendezése · a dal-eredmény szakasz-bontása, nehéz szakaszok,
korrekciós akciók · a setlist részletnézete és **folyamatos futása**
hangolás-váltással · csak-lejátszás, gyenge jel, hiányzó eszköz, audio-hiba és
folytatás állapotok · **fake lejátszási órával** mért lejátszófej/loop szinkron.

**NINCS benne (tilos):** a pontozás vagy a lejátszás logikájának módosítása ·
DSP (AGENTS.md §9) · az import/szerkesztő (Kör 24) · `docs/adr/**`,
`tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `songs/trainer/` | a tréner felülete |
| `songs/results/` | a dal-eredmény |
| `setlists/run/` | a folyamatos futás |
| `lib/l10n/app_{en,hu}.arb` | a tréner-szövegek |
| `test/features/songs/trainer/*_test.dart` (4) | a §6 cellái |
| `docs/rounds/e13-r25-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/songs/` a három érintett almappán kívül ·
`lib/core/design_system/**` · `lib/core/theme/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 A csak-lejátszás NEM kap pontszámot

Ha nem volt bemeneti jel (mikrofon kikapcsolva, csak hallgatás), az eredmény
ezt kimondja — nem ad kitalált százalékot. Az ADR 0283 §1 folytatása.

**NEM elfogadható gyengítés:** nulla vagy „N/A" helyett becsült pontszám „hogy
legyen mit mutatni". Ez a projekt legveszélyesebb hibaosztálya: magabiztos
hazugság.

### 5.2 A lejátszófej és a loop az AUDIO ÓRÁBÓL vezetett

Az ADR 0274 kötelező alkalmazása. A vizuális loop-határ és a hallható
loop-határ ugyanaz — fake órával determinisztikusan mérve.

**NEM elfogadható gyengítés:** külön `Timer` a lejátszófejnek. Hosszú dalon
látványosan elcsúszik.

### 5.3 A szünet PONTOS helyről folytat

Nem a szakasz elejéről és nem néhány másodperccel arrébb. A folytatás pozíciója
a lejátszási óráé.

### 5.4 A setlist hangolás-váltása ELŐRE jelzett

Ha a következő dal más hangolást igényel, a felhasználó **azelőtt** tudja meg,
hogy belekezdene — fellépés közben ez a legfontosabb átmenet.

### 5.5 Az orientációváltás MEGŐRZI az állapotot

Portrait ↔ landscape váltás nem indítja újra a lejátszást és nem veszíti el a
loop-beállítást.

### 5.6 A Stage route-ok takarítása zöld

Minden kilépési úton felszabadul a lejátszás és az audio-fókusz (az ADR 0276
folytatása).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A csak-lejátszás nem kap pontszámot, és ezt kimondja | `playback_only_result_test.dart` |
| A2 | A lejátszófej az audio órából vezetett (fake órával mérve) | `playhead_loop_sync_test.dart` |
| A3 | A vizuális és a hallható loop-határ egyezik | ugyanott |
| A4 | A szünet pontos helyről folytat | ugyanott |
| A5 | A setlist hangolás-váltása előre jelzett | `setlist_run_test.dart` |
| A6 | Az orientációváltás megőrzi a lejátszási és loop-állapotot | `trainer_setup_test.dart` |
| A7 | A Stage route elhagyásakor a lejátszás és az audio-fókusz felszabadul | `setlist_run_test.dart` |
| A8 | A beállítás validációja hibás szakasz/sebesség párost nem enged | `trainer_setup_test.dart` |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r25_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Becsült pontszám csak-lejátszásnál | **A1** |
| Külön `Timer` a lejátszófejnek | **A2** |
| A vizuális loop-határ a kerekített ütemhez igazítva | **A3** |
| A folytatás a szakasz elejéről | **A4** |
| A hangolás-váltás csak a dal indulásakor derül ki | **A5** |
| Az orientációváltás újraindítja a lejátszást | A6 |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**A lejátszófej-szinkron három kötelező cellája** (a küszöb: **100 ms**, az
ADR 0274 §3 szerint):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | 40 ms eltérés | **elfogadva** |
| rajta (a küszöbön) | pontosan **100 ms** | **elfogadva** (a határ inkluzív) |
| a küszöb fölött | 180 ms | **elutasítva** — a cella PIROS |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** adj becsült pontszámot
csak-lejátszás módban → az **A1** cellának PIROSNAK kell lennie → állítsd
vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/songs/trainer/trainer_setup_test.dart test/features/songs/trainer/playhead_loop_sync_test.dart test/features/songs/trainer/playback_only_result_test.dart test/features/songs/trainer/setlist_run_test.dart test/ui/goldens/e13_r25_screens_golden_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
~/flutter/bin/flutter test --update-goldens test/ui/goldens/e13_r25_screens_golden_test.dart
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

1. A tréner beállítása + validáció.
2. A Stage-elrendezés (kotta + lejátszófej) három orientációban.
3. A lejátszófej/loop szinkron fake órával + a három cella.
4. A csak-lejátszás eredmény-ága — pontszám NÉLKÜL.
5. A dal-eredmény szakasz-bontása és korrekciós akciói.
6. A setlist folyamatos futása, előre jelzett hangolás-váltással.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A kitalált pontszám.** Csak-lejátszásnál „üresnek" tűnik az eredmény, és a
  kitöltése hazugság lenne (A1).
- **A `Timer`-es lejátszófej.** Rövid teszt-dalon nem látszik, hosszún
  látványosan elcsúszik (A2).
- **A kotta-nézet teljesítménye.** Nagy dalnál külön profilozandó — ha akadozik,
  a §10-ben rögzítendő, nem elhallgatandó.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
