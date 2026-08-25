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
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/live/chord_timeline_golden_test.dart",
  "test/features/live/chord_timeline_test.dart",
  "test/features/live/expected_hint_cleared_on_live_test.dart",
  "test/features/live/live_background_test.dart",
  "test/features/live/live_lab_panel_test.dart",
  "test/features/live/live_screen_test.dart",
  "test/features/live/live_widgets_test.dart",
  "test/features/live/live_stage_test.dart",
  "test/features/live/live_mic_release_test.dart",
  "test/features/live/live_announcement_throttle_test.dart",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/app/routing/shell_lifecycle_test.dart",
  "test/features/ai_tutor/presentation/tutor_home_screen_test.dart",
  "test/features/practice/presentation/practice_routing_test.dart",
  "docs/rounds/e13-r18-live-stage-ui.md",
]
gate_tests = [
  "test/features/live/live_stage_test.dart",
  "test/features/live/live_mic_release_test.dart",
  "test/features/live/live_announcement_throttle_test.dart",
  "test/ui/goldens/e13_r18_screens_golden_test.dart",
  "test/ui/ui_inventory_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/app/routing/shell_lifecycle_test.dart",
  "test/features/ai_tutor/presentation/tutor_home_screen_test.dart",
  "test/features/practice/presentation/practice_routing_test.dart",
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

**Kockázat = high, indoklás:** a Live Stage a mikrofon-erőforrás (authorization) életciklusát vezérli, a jel-minőség kijelzés pedig a felismerés igazmondását közvetíti.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fája ma **13** l10n-kulcsot használ, és mind feloldható: `app` = 13 kulcs.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `live` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek

Az aggregátum a listán MARAD, de **kizárólag generált kimenetként**
(`dart run tool/gen_l10n_segments.dart --write`); a merge-elt precedens
egységesen a forrást ÉS a regenerált aggregátumot is commitolja (E09-R26
`df0ad3dd`, E13-R12 `376b8a1d`, E13-R10 `b11ab2ed`). **Új fragmentum NEM
készül**, ezért a `test/l10n/arb_parity_test.dart` beégetett szegmens-listáját
sem kell bővíteni — a felvett források mind szerepelnek benne.

### R2 — a kör SAJÁT feature-fáján élő, ma zöld widget-tesztek (FELVÉVE)

Ezek közvetlenül a migrálandó képernyőkre állítanak, tehát a migráció után
pirosra váltanának, ami a §0 szerint `blocked` lenne:

  - `test/features/live/chord_timeline_golden_test.dart`
  - `test/features/live/chord_timeline_test.dart`
  - `test/features/live/expected_hint_cleared_on_live_test.dart`
  - `test/features/live/live_background_test.dart`
  - `test/features/live/live_lab_panel_test.dart`
  - `test/features/live/live_screen_test.dart`
  - `test/features/live/live_widgets_test.dart`

**A jogosultság szűk:** a teszteket az ÚJ widgetekre kell ráállítani. A lefedett
viselkedést gyengíteni, cellát törölni vagy `skip`-elni **TILOS** — az a mérce
meggyengítése, amit a gate-guard emberhez eszkalál.

### R3 — keresztmetszeti tesztek (NEM kerültek listára — figyelmeztetés)

A kör fájára hivatkozó további widget-tesztek közös infrastruktúrán élnek
(`test/app/**`, `test/core/**`, más feature-ek fái) — 27 ilyen fájl van. Ezeket a kör
**NEM** szerkesztheti: ha egy elbukik, az `blocked` jelzés és célzott
brief-revízió, nem csendes átírás. A körbe húzásuk a scope-fegyelem feladása
lenne.

### R4 — a képernyő-leltár őre (H3 önjavító kör, ADR 0112, 2026-08-25)

A `test/ui/ui_inventory_test.dart` **repó-szintű** őr: a `tool/ui_inventory.dart`
a `lib/features/**` fa `_screen.dart` végű fájljait számolja, a teszt pedig
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z) `lib/features/live/` könyvtár-előtag
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

### S11 — az örökség-képernyőt PINNELŐ, listán kívüli tesztek (2026-08-25)

A kör lecserél legalább egy MEGLÉVŐ képernyőt, amelynek a TÍPUSÁT a brief
listáján kívül élő teszt pinneli. Mérve a `tools/brief-lint.py` `S11`
szabályával (import ÉS típusnév együtt), a `main @ b28bb1bf` fán:

- `test/app/navigation/adaptive_scaffold_test.dart`
- `test/app/navigation/legacy_route_redirect_test.dart`
- `test/app/offline_network_guard_test.dart`
- `test/app/routing/app_router_test.dart`
- `test/app/routing/shell_lifecycle_test.dart`
- `test/features/ai_tutor/presentation/tutor_home_screen_test.dart`
- `test/features/practice/presentation/practice_routing_test.dart`

Ez pontosan az a halt-osztály, amelyik az **E13-R16/F9**-et (full-gate
32867296946, `hasLength(79)` vs 81) és az **E13-R17/H3**-at (`flutter test
test/app/navigation/` +33 → +30 -3) megállította: az őr a listán kívül él, a
felvétele az orchestrátornak TÁGÍTÁS ([L478](../LESSONS.md)), tehát a kör H3-ban
áll meg, mielőtt egyetlen sor kód megszületne. A fenti fájlok ezért mostantól
az `allowed_paths`-on ÉS a `gate_tests`-en is szerepelnek.

**A jogosultság PONTOSAN a lecserélt képernyő típusának átírása.** Cella
törlése, `skip`-je, küszöb-lazítása vagy az állítás gyengítése TILOS — az a
mérce meghamisítása. Ha a kör bizonyíthatóan nem cseréli le a képernyőt, a kör
pre-flightja mondja ki ezt a mérést, és hagyja a cellákat érintetlenül.

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
| `lib/l10n/base/app_{en,hu}.arb` | **FORRÁS** — az állapot-szövegek (a kör feature-ei még nem migráltak, a kulcsaik itt élnek) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/…` (7 meglévő teszt) | ma zöld, a migrált képernyőkre állítandó — lásd §0.0 R2 |
| `test/features/live/*_test.dart` (3) | a §6 cellái |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a kör új `lib/features/**/*_screen.dart`-ot hozhat, ezért az egzakt `hasLength(...)` elmozdul; a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4) |
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
tools/round-gate.sh test/features/live/live_stage_test.dart test/features/live/live_mic_release_test.dart test/features/live/live_announcement_throttle_test.dart test/ui/goldens/e13_r18_screens_golden_test.dart test/ui/ui_inventory_test.dart
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
