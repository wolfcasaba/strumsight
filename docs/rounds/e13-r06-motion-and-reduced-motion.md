# E13-R06 — Motion rendszer és reduced motion

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 903e7a7d`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 6
- **Kör-azonosító:** `E13-R06`
- **Branch:** `<motor>/e13-r06-motion-and-reduced-motion`
- **Előfeltétel:** `E13-R05` merge-elve (felületi primitívek)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0274`](../adr/0274-motion-driven-by-the-audio-clock.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd fel, MELYIK óra a mérvadó a
> jelenlegi lejátszási/analízis útvonalon (a `lib/features/audio_analysis/`
> alatti idővonal-forrás), mert az §5.2 erre köti a beat-animációt. Eltérésnél
> §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/core/design_system/foundations/ss_motion.dart",
  "lib/core/design_system/motion/ss_motion_scope.dart",
  "lib/core/design_system/motion/ss_beat_pulse.dart",
  "lib/core/design_system/motion/ss_transitions.dart",
  "lib/core/design_system/documentation/component_catalog_screen.dart",
  "lib/core/design_system/public.dart",
  "test/core/design_system/motion/ss_motion_scope_test.dart",
  "test/core/design_system/motion/ss_beat_pulse_test.dart",
  "docs/rounds/e13-r06-motion-and-reduced-motion.md",
]
gate_tests = [
  "test/core/design_system/motion/ss_motion_scope_test.dart",
  "test/core/design_system/motion/ss_beat_pulse_test.dart",
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

Egységes, **hozzáférhető** mozgásrendszer: duration/curve tokenek, reduced
motion, és a zenei ritmusra kötött animáció (SDD Ch13 Kör 6).

## 2. Jelenlegi állapot — mért tények

- Az R02 letette az `SsMotion` konstans-vázat; a jelen kör tölti fel
  szemantikus tokenekkel és viselkedéssel.
- A Ch13 §9.6 megadja a duration- és curve-készletet, valamint a reduced-motion
  szabályokat.
- A projekt már többször mérte, hogy **külön `Timer`-rel hajtott vizuális beat
  elcsúszik** a hangtól — ezért köti az §5.2 az audio órához.

## 3. Scope

**Benne van:** szemantikus duration- és curve-tokenek · `SsMotionScope`
reduced-motion resolver (rendszer-beállítás + alkalmazás-szintű felülbírálás) ·
`SsBeatPulse` — az **audio órából** vezetett ritmus-animáció · közös
képernyő- és elem-átmenetek · a controller-életciklus szabálya.

**NINCS benne (tilos):** DSP- vagy időzítés-logika módosítása
(`lib/features/audio_analysis/**` — AGENTS.md §9) · `lib/features/**` ·
`lib/core/theme/**` · dekoratív animáció a felismerési útvonalon ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `foundations/ss_motion.dart` | duration/curve tokenek |
| `motion/ss_motion_scope.dart` | **ÚJ** — reduced-motion resolver |
| `motion/ss_beat_pulse.dart` | **ÚJ** — audio órához kötött pulzus |
| `motion/ss_transitions.dart` | **ÚJ** — közös átmenetek |
| `documentation/component_catalog_screen.dart` | a mozgások bemutatása |
| `public.dart` | az export bővítése |
| `test/…/motion/*_test.dart` (2) | a §6 cellái |
| `docs/rounds/e13-r06-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` (kiemelten `audio_analysis`) ·
`lib/core/theme/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` ·
`tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0274)

### 5.1 A reduced motion CSÖKKENT, nem KIKAPCSOLT visszajelzés

Ha a felhasználó csökkentett mozgást kér, a mozgás helyét **állapotváltás**
veszi át (szín, opacitás-lépcső, szöveg) — nem tűnik el a visszajelzés.

**NEM elfogadható gyengítés:** `if (reduceMotion) return child;` minden
animációnál. Az a felhasználó elveszítené a beat-visszajelzést is, ami itt
funkcionális információ.

### 5.2 A ritmus-animáció az AUDIO ÓRÁBÓL jön, nem külön `Timer`-ből

Egy független `Timer` percek alatt elcsúszik a hangtól. A pulzus a lejátszási
idővonalat kérdezi.

**NEM elfogadható gyengítés:** `Timer.periodic(Duration(milliseconds: 60000 ~/
bpm))`. Ez mérve elcsúszó vizuális ritmust ad.

### 5.3 A design system NEM módosítja az időzítés-forrást

Csak OLVASSA. A DSP és az időzítés az AGENTS.md §9 tiltott zónája.

### 5.4 Minden controller `dispose`-olva

Nincs szivárgó `AnimationController` és nincs `setState` `dispose` után. Ez
acceptance-cella (A4).

### 5.5 A felismerési útvonalon nincs dekoratív animáció

Ami mozog, az információt hordoz. A Stage Mode nem dekoratív felület.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Reduced motion mellett a visszajelzés MEGMARAD (más modalitásban) | `ss_motion_scope_test.dart` |
| A2 | A beat-pulzus az audio órából vezetett, nem független `Timer`-ből | `ss_beat_pulse_test.dart` |
| A3 | Az óra megállása/ugrása után a pulzus szinkronban marad | ugyanott |
| A4 | `dispose` után nincs élő controller és nincs `setState` | `ss_beat_pulse_test.dart` |
| A5 | A rendszer-beállítást az alkalmazás-szintű felülbírálás felülírja | `ss_motion_scope_test.dart` |
| A6 | A design system NEM módosít `lib/features/audio_analysis/**`-t | `git diff --stat` |
| A7 | Az átmenetek a token-készletből jönnek, nincs nyers `Duration` literál | `grep` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Reduced motion → a visszajelzés eltűnik | **A1** |
| `Timer.periodic` a BPM-ből | **A2** |
| A pulzus nem követi az óra ugrását | **A3** |
| A controller nem `dispose`-olt | **A4** |
| A felülbírálás nem hat | A5 |
| Nyers `Duration(milliseconds: 250)` | A7 |

**Az óra-szinkron három kötelező cellája** (a küszöb: a megengedett vizuális
lag, **100 ms**):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | 60 ms eltérés az órától | **elfogadva** |
| rajta (a küszöbön) | pontosan **100 ms** | **elfogadva** (a határ inkluzív) |
| a küszöb fölött | 140 ms | **elutasítva** — a cella PIROS |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** cseréld a pulzus
forrását független `Timer`-re → az **A2** és **A3** cellának PIROSNAK kell
lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/design_system/motion/ss_motion_scope_test.dart test/core/design_system/motion/ss_beat_pulse_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `ss_motion.dart` — szemantikus duration/curve tokenek.
2. `ss_motion_scope.dart` — resolver, rendszer + alkalmazás-szintű forrással.
3. `ss_beat_pulse.dart` — az audio órából, injektálható idő-forrással.
4. Az óra-szinkron három cellája + a dispose-cella.
5. `ss_transitions.dart` — közös átmenetek.
6. A valódi-sértés próba, §10-be dokumentálva.
7. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A független `Timer` kényelme.** Nem kell hozzá idő-forrás injekció, és
  mérve elcsúszik — pont a termék lényegén (A2).
- **A reduced motion mint kapcsoló.** A legkönnyebb implementáció egyben
  információvesztés a rászoruló felhasználónak (A1).
- **A szivárgó controller.** Csak hosszabb sessionben látszik, teszttel viszont
  azonnal (A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
