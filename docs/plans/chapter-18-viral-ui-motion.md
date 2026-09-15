# Chapter 18 — Viral UI & Motion (látványos, animált felület a moat köré)

- **Nyitva:** 2026-09-15, a felhasználó jelzésére („nézd át az UI dizájnokat,
  keress viral elemeket a versenytársakkal szemben, és fejleszd az UI-t minden
  funkcióhoz animációval, látványos elemekkel" + „a színeket is lehetne
  változtatni, nagyon Claude-dizájnos").
- **Mért alap:** `main @ c455e8ae` (E17-R01 után); `docs/ui/baseline/` 7 képernyőkép;
  `lib/core/design_system/motion/` 3 fájl; feature-fában 3 `flutter_animate`-import,
  1 `AnimationController`, 14 `CustomPainter`.
- **Terv szerzője:** Claude (orchestrátor). **Implementáció:** az auto router
  (ADR 0088) — az ADR 0055 protokoll szerint Claude briefel, az implementer
  motor kódol, Claude review-z és merge-el.
- **Dizájn-forrás:** [`../ui/viral-ui-audit.md`](../ui/viral-ui-audit.md) +
  [`../ui/viral-motion-design-spec.md`](../ui/viral-motion-design-spec.md).
- **Viszony a többi sávhoz:** a Chapter 17 (teljes bekötés) R02–R14 `hold`
  sorai és ez a sáv **nem ütköznek** fájlszinten (Ch17 = community/analysis
  V2/setlist kompozíció; Ch18 = design-system motion + képernyő-prezentáció).
  Egy session = egy kör (AGENTS.md §4); a sorrendet a pipeline-queue dönti.

## 0. Nem tárgyalható korlátok (minden körre)

1. `lib/core/audio/**`, `lib/features/audio_analysis/**`, DSP/ML — **tilos zóna**.
2. Ritmus-animáció csak `SsBeatClock`-ról (ADR 0274); `Timer.periodic` tilos.
3. Gyakorlás közben nincs teljes képernyős ünneplés (ADR 0389).
4. Reduced motion: az információ megmarad, a kiterjedés nullázódik.
5. Minden felirat ARB (en+hu). Ikon, nem emoji.
6. Egy animáció ≤ `SsMotion.celebration` (700 ms); jelenet átugorható.
7. A mérce (`tools/round-gate.sh`, CI) érintetlen — H-GATEGUARD.

## 1. Körök

| Kör | Cím | Fő fájlok (engedélyezett-lista magja) | Új komponens | ADR-hely |
|---|---|---|---|---|
| **E18-R00** | **Midnight Stage paletta** — a réz/krém tokenek cseréje token-szinten (spec §0.5 A) | `lib/core/design_system/foundations/ss_colors.dart`, `lib/core/design_system/themes/**`, `lib/core/theme/app_colors.dart`, `app_palette.dart`, `docs/ui/baseline/token-debt.md`, golden-fixture-k | — | foglalandó (`tools/round-slots.py reserve-adr`) |
| E18-R01 | Motion-alapok: `stagger` alias, `SsStaggeredEntrance`, `SsScoreRingReveal`; Today Hub hero + belépés (spec §1) | `lib/core/design_system/foundations/ss_motion.dart`, `motion/ss_staggered_entrance.dart`, `components/analytics/ss_score_ring_reveal.dart`, `lib/features/today/screens/today_hub_screen.dart`, tesztek | 3 | foglalandó |
| E18-R02 | Strike-line juice + kombó: `SsHitJuice` (a `HitBurst` általánosítása), `SsComboCounter`; Live hero bekötése (spec §3) | `motion/ss_hit_juice.dart`, `components/music/ss_combo_counter.dart`, `lib/features/live/widgets/**`, `lib/features/live/screens/live_screen.dart`, ARB (`hitVerdict*`) | 2 | foglalandó |
| E18-R03 | Result-jelenet: `SsCelebrationScene` + a `CelebrationCoordinator` hívása; Practice/Lesson/Song result közös jelenet (spec §7) | `components/overlays/ss_celebration_scene.dart`, `practice_result_screen.dart`, `lesson_score_card.dart`, `song_result_screen.dart`, gamification coordinator bridge | 1 | foglalandó |
| E18-R04 | Tuner lock + metronóm-korong: `SsLockRing`, `SsBeatDisc` (spec §4–5) | `components/music/ss_lock_ring.dart`, `ss_beat_disc.dart`, `lib/features/tuner/widgets/cents_gauge.dart`, `lib/features/metronome/screens/**` | 2 | foglalandó |
| E18-R05 | Learn highway → egy `CustomPainter` + vanishing-point + előjeles verdict (spec §6; 016b P2/P5/P6) | `lib/features/learn/widgets/lesson_highway.dart`, `hit_burst.dart` (→ `SsHitJuice`), `learn_screen.dart` | 0 | foglalandó |
| E18-R06 | Széria-láng + milestone: `SsFlame`; Streak/Gamification hub belépés (spec §11) | `components/music/ss_flame.dart`, `gamification/presentation/widgets/streak_status_card.dart`, `streak_detail_screen.dart`, `gamification_hub_screen.dart`, `lib/features/streak/widgets/streak_badge.dart` | 1 | foglalandó |
| E18-R07 | Share reveal: `SsShareReveal`; Strum Card / Wrapped preview animáció + result mini-preview (spec §12) | `motion/ss_share_reveal.dart`, `lib/features/share/screens/**`, `share/widgets/**` | 1 | foglalandó |
| E18-R08 | Chord Library/Detail: diagram-landolás, akkord-váltás csúszás (spec §10) | `components/music/ss_chord_diagram.dart`, `lib/features/chords/**` | 0 | foglalandó |
| E18-R09 | Practice Session / Speed Builder / Song Trainer: közös hero+highway+section-end (spec §8–9) | `lib/features/practice/presentation/**`, `song_trainer/presentation/screens/song_trainer_screen.dart` | 0 | foglalandó |
| E18-R10 | Onboarding aha-pillanat (spec §2) + tab fade-through (backlog #3) | `lib/features/onboarding/**`, `lib/app/home_shell.dart` | 0 | foglalandó |
| E18-R11 | Analyze/Progress reveal + golden-mátrix bővítés (A-MOTION-5) az összes érintett képernyőre | `lib/features/analyze/**`, `progress_v2/**`, `test/ui/goldens/**` | 0 | foglalandó |
| E18-R12 | Zárókör: `docs/ui/chapter-18-completion-report.md`, reduced-motion audit, LESSONS | docs | — | — |

Flag-OFF felületek (Coach, Vision, Community) csak spec-szinten (spec
§14–16); körük a saját sávjuk rollout-döntése után nyílik.

## 2. Kör-brief kötelező cellái (minden E18-körben)

A-MOTION-1…8 a spec §17 szerint, PLUSZ:

- **Frame-budget cella** (R02, R05, R09): a highway/juice `paint()` egy
  `Ticker`-rel fut; a teszt `SchedulerBinding` fake-frame-en számolja a
  `shouldRepaint` hívásokat (≤ 1/frame).
- **Óra-szinkron cella** (R02, R04, R09): fake `SsBeatClock` seek/pause után a
  fázis azonnal követ (E13-R06 §6.1 mintája).
- **Koordinátor cella** (R03, R06): `isActive == true` → nincs jelenet; két
  egyidejű esemény → egy összevont jelenet.

## 3. Amit ez a sáv NEM csinál

- Nem épít „Strum Cam" videót (külön ADR: kódoló-függőség és licenc).
- Nem nyúl a community/leaderboard UI-hoz (Epic 9 `hold`).
- Nem vezet be új csomagot `flutter_animate`-en túl; a `flutter_shaders`
  (radiális glow) opcionális, csak külön ADR-rel.
- Nem hoz paywallt vagy monetization-felületet.

## 4. Kockázatok

| Kockázat | Kezelés |
|---|---|
| A palettacsere 1152 golden-cellát baseline-ol újra (R00) | R00 CSAK tokeneket cserél; a golden-frissítés a kör része, diff-review a PNG-kre kötelező |
| Juice és hang elcsúszik Androidon (016b P3) | a `LiveFrame` timestampje az esemény-idő; a kalibrált vizuális offset (r74) érvényes |
| Ünneplés megszakítja a gyakorlást | ADR 0389 koordinátor-cella minden R03/R06 briefben |
| Túl sok mozgás → „olcsó" hatás | §9.7 tiltás: nincs végtelen dekoráció; per képernyő max 1 belépő stagger + eseményvezérelt juice |
| Reduced-motion regresszió | A-MOTION-2 cella minden új komponensre |
