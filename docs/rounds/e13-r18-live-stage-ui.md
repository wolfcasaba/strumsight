# E13-R18 — Live Stage UI migráció

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ e9a2c8b2`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 18
- **Kör-azonosító:** `E13-R18`
- **Branch:** `<motor>/e13-r18-live-stage-ui`
- **Előfeltétel:** `E13-R17` merge-elve (hubok) + az R09 StageScaffold
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — az ADR 0274/0276/0280 érvényes erre a körre.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a TÉNYLEGES Live
> engine-interfészt és `autoDispose` életciklust (`lib/features/live/`), és
> jegyezd fel a jelenlegi DSP-paraméterek helyét — a §5.1 tiltás rájuk
> vonatkozik. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/live/",
  "lib/core/design_system/components/music/ss_chord_hero.dart",
  "lib/core/design_system/components/music/ss_strum_glyph.dart",
  "lib/core/design_system/components/music/ss_beat_grid.dart",
  "lib/core/design_system/components/music/ss_tempo_display.dart",
  "lib/core/design_system/components/music/ss_signal_quality_indicator.dart",
  "lib/core/design_system/public.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/live/live_stage_test.dart",
  "test/features/live/live_mic_release_test.dart",
  "test/features/live/live_announcement_throttle_test.dart",
  "test/ui/goldens/",
  "docs/rounds/e13-r18-live-stage-ui.md",
]
gate_tests = [
  "test/features/live/live_stage_test.dart",
  "test/features/live/live_mic_release_test.dart",
  "test/features/live/live_announcement_throttle_test.dart",
  "test/ui/goldens/e13_r18_screens_golden_test.dart",
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

A Live felület (UI-08) átállítása az új StageScaffoldra és a zenei
komponensekre — **a felismerési viselkedés változtatása nélkül**
(SDD Ch13 Kör 18).

## 2. Jelenlegi állapot — mért tények

- Az R09 letette a StageScaffoldot, az R12 a badge-eket, az R14 az élő régió
  költségvetését — ez a kör ezeket használja.
- A Live a termék központi képernyője: a jelenlegi motor-interfész és
  `autoDispose` életciklus **regressziós tesztekkel védett**.
- Az AGENTS.md §9 tiltja a DSP-paraméterek módosítását.

## 3. Scope

**Benne van:** `SsChordHero`, `SsStrumGlyph`, `SsBeatGrid`, `SsTempoDisplay`,
`SsSignalQualityIndicator` · a Live elrendezés portrait / landscape / expanded
változata · idle, induló, hallgató, gyenge jel, nincs akkord, degradált,
szüneteltetett, záró és hiba állapotok · az accessibility-bejelentés
**throttlingja** (a vizuális frissítés maradhat sűrűbb) · a baseline-hoz képesti
**szándékos** eltérések dokumentálása.

**NINCS benne (tilos):** **bármely DSP-paraméter módosítása** (AGENTS.md §9) ·
a motor-interfész vagy az `autoDispose` viselkedés megváltoztatása · más
képernyők migrációja · `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/live/` | a képernyő migrációja (UI-réteg) |
| `components/music/ss_chord_hero.dart` | **ÚJ** — akkord-hero |
| `components/music/ss_strum_glyph.dart` | **ÚJ** — strum-irány |
| `components/music/ss_beat_grid.dart` | **ÚJ** — ütem-rács |
| `components/music/ss_tempo_display.dart` | **ÚJ** |
| `components/music/ss_signal_quality_indicator.dart` | **ÚJ** |
| `public.dart` | az export bővítése |
| `lib/l10n/app_{en,hu}.arb` | az állapot-szövegek |
| `test/features/live/*_test.dart` (3) | a §6 cellái |
| `docs/rounds/e13-r18-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a `live/` KIVÉTELÉVEL · a DSP- és
felismerési paraméterek bárhol · `lib/core/theme/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 NINCS DSP-paraméterváltozás — a paritás fixture-rel bizonyított

A kör UI-migráció. A felismerés kimenete bit-szinten ugyanaz marad; ezt
paritás-fixture méri, nem ígéret.

**NEM elfogadható gyengítés:** „a küszöb egy hajszálnyi módosítása szebb
kijelzést ad". Az AGENTS.md §9 tiltott zónája, és a termék mérőszámát rontja el
egy UI-kör kedvéért.

### 5.2 A gyenge jel és a „nincs akkord" KÜLÖN állapot

Két különböző ok, két különböző teendő: az egyik a mikrofonhoz szólít, a másik
a játékhoz. Összevonva a felhasználó nem tudja, mit tegyen.

### 5.3 Az akkord és az irány MESSZIRŐL olvasható

A Stage-t a gitár mellől nézik. Az akkordnév az R04 adaptív méretezésével, a
strum-irány az R07 saját glyph-jével jelenik meg.

### 5.4 A confidence NEM csak szín

Az ADR 0278 §2 kikényszerítése ezen a képernyőn.

### 5.5 A bejelentés THROTTLE-olt, a vizuális frissítés NEM

Az ADR 0280 §2 költségvetése az élő régióra vonatkozik; a vizuális kép
maradhat sűrűbb.

### 5.6 A mikrofon MINDEN kilépési úton leáll

Navigáció, háttérbe kerülés, hiba, rendszer-vissza. Ez acceptance-cella (A4).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Nincs DSP-paraméterváltozás — a paritás-fixture azonos kimenetet ad | `live_stage_test.dart` + `git diff` |
| A2 | A gyenge jel és a „nincs akkord" külön állapot, külön teendővel | `live_stage_test.dart` |
| A3 | A confidence nem csak színnel jelölt | ugyanott |
| A4 | A mikrofon minden kilépési úton leáll | `live_mic_release_test.dart` |
| A5 | A bejelentés throttle-olt, a vizuális frissítés nem korlátozott | `live_announcement_throttle_test.dart` |
| A6 | Portrait, landscape és expanded elrendezésben nincs túlcsordulás | `live_stage_test.dart` |
| A7 | A motor-interfész és az `autoDispose` viselkedés változatlan | a meglévő regressziós tesztek zöldek |
| A8 | A baseline-hoz képesti eltérések szándékosként dokumentáltak | §10 |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r18_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egy küszöb „hajszálnyi" módosítása | **A1** |
| A gyenge jel és a nincs-akkord összevonva | **A2** |
| A confidence csak színes sáv | A3 |
| A háttérbe kerüléskor nyitva marad a mikrofon | **A4** |
| A vizuális frissítés is a bejelentési ütemre lassítva | **A5** |
| Fix magasságú akkord-hero | A6 |
| Az `autoDispose` lecserélése tartós providerre | **A7** |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**A bejelentés-throttling három kötelező cellája** (a küszöb: **1000 ms**, az
ADR 0280 §2 szerint):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | 200 ms-onként változó akkord | **egy** bejelentés; a vizuális kép **minden** változást követ |
| rajta (a küszöbön) | pontosan 1000 ms | **bejelentve** (a határ inkluzív) |
| a küszöb fölött | 3000 ms-onként | minden változás bejelentve |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vond össze a gyenge
jel és a „nincs akkord" állapotot → az **A2** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/live/live_stage_test.dart test/features/live/live_mic_release_test.dart test/features/live/live_announcement_throttle_test.dart test/ui/goldens/e13_r18_screens_golden_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
~/flutter/bin/flutter test --update-goldens test/ui/goldens/e13_r18_screens_golden_test.dart
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

1. A DSP-paritás fixture ELŐBB — a nem-változás mércéje.
2. A zenei komponensek (`SsChordHero`, `SsStrumGlyph`, `SsBeatGrid`,
   `SsTempoDisplay`, `SsSignalQualityIndicator`).
3. A Live elrendezés StageScaffoldon, három elrendezésben.
4. A kilenc állapot — gyenge jel és nincs-akkord KÜLÖN.
5. A bejelentés-throttling + a három cella.
6. Mikrofon-felszabadítás minden kilépési úton.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A DSP-hez nyúlás.** A UI-munka közben kézenfekvőnek tűnik „megigazítani" a
  küszöböt, és ezzel a termék mérőszámát rontja el (A1).
- **A háttérbe kerülés.** A legkönnyebben kifelejtett kilépési út, és nyitva
  hagyott mikrofont jelent (A4).
- **A throttling túlterjesztése.** Ha a vizuális képre is hat, a Stage
  akadozónak tűnik (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
