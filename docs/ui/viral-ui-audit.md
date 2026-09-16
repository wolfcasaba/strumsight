# Viral UI audit — versenytársak, viral elemek és a StrumSight rése (2026-09-15)

- **Készült:** Claude (orchestrátor), a felhasználó kérésére („nézd át az UI
  dizájnokat, keress viral elemeket a versenytársakkal szemben, és fejleszd az
  UI-t minden funkcióhoz animációval, látványos elemekkel").
- **Bemenet:** `docs/sdd/13-chapter-13-ui-ux-design-system.md` (65 képernyő-spec,
  §4.6 és §9.7 motion-szabályok), `docs/rag/chunks/013-growth-virality.md`,
  `016b-animation-gamefeel.md`, `017-competitive-monetization.md`,
  `docs/ui/baseline/` (7 mért képernyőkép), ADR [0274](../adr/0274-motion-driven-by-the-audio-clock.md)
  (audio-óra hajtja a ritmus-animációt), ADR [0389](../adr/0389-reward-inbox-and-celebration-coordinator.md)
  (ünneplés nem szakít meg gyakorlást), és 2026-os webes források (lent).
- **Kimenet:** ez az audit + [`viral-motion-design-spec.md`](viral-motion-design-spec.md)
  (funkciónkénti dizájn) + [`../plans/chapter-18-viral-ui-motion.md`](../plans/chapter-18-viral-ui-motion.md)
  (körterv).

> **Ez dizájn-terv, nem rollout-döntés.** A DSP/ML/audio réteg NEM változik
> (AGENTS.md §9). Minden itt leírt mozgás a Chapter 13 §4.6 négy engedélyezett
> okának egyikébe tartozik: ritmus-érzékelés, állapotváltás-megerősítés,
> navigációs hierarchia, sikeres művelet visszajelzése.

---

## 1. Mit mértünk a saját UI-n (baseline, 2026-09)

| Terület | Mért állapot | Következmény |
|---|---|---|
| Motion tokenek | `SsMotion` 5 időtartam + 4 görbe (`instant…celebration`, ≤700 ms), `SsMotionScope` reduced-motion, `SsBeatPulse` audio-órás pulzus, `SsTransitions.route` | A **rendszer kész**, de csak 3 fájl használ `flutter_animate`-et és 1 `AnimationController` van a feature-fában → a képernyők **statikusak** |
| Live (baseline kép) | fekete üres tér, a ↓/↑ ütemsor és a 3 gomb csak alul; hero nincs, amíg nem jön akkord | Az app egyetlen „moat"-ja (↓/↑) a képernyő 10 %-án él; első benyomás = üres képernyő |
| Learn (baseline kép) | jól strukturált kártyalista, de 0 mozgás, 0 progress-vizualizáció, lakatok statikusak | A „path" nem érződik útnak — Duolingo/Simply itt nyer |
| Juice | `HitBurst` (learn highway, 14 részecske, determinisztikus), `StrumArrow` CustomPainter (shape+color), `AnalyzeSkeleton` shimmer | A juice-minta létezik, de csak a Learn highway-en; Live/Practice/Song Trainer nem kapja |
| Ünneplés | `CelebrationCoordinator` (ADR 0389) összevon és gyakorlás közben tilt; `RewardInboxScreen`, `RewardSummarySheet` | Van koordinátor, de nincs látványos „lesson-end" jelenet (score-ring felfutás, konfetti, kombó) |
| Megosztás | `StrumCard` 9:16 statikus PNG, `WrappedCard` heti recap, `WrappedPrompt` ≥80 % pontosságnál | Statikus kártya; a research #1 (animált „Strum Cam") nincs; nincs in-app preview-animáció |
| Széria | `StreakStatusCard`, `streak_badge` (🔥 a Live fejlécen), széria-freeze, Friday-copy | Nincs „flame grows" animáció, nincs milestone-jelenet, nincs home-screen widget |

## 2. Versenytárs-mátrix — ki mit csinál látványosan (2026)

| Elem | Yousician | Simply Guitar | Duolingo (referencia) | Chordify | Rocksmith+ | GuitarTuna | **StrumSight ma** | **Rés** |
|---|---|---|---|---|---|---|---|---|
| Gördülő note-highway + strike-line juice | ✅ (scrolling notes, azonnali feedback) | ✅ (világos, játékos) | — | ❌ | ✅ (3D highway, dinamikus nehézség) | ❌ | ⚠️ csak Learn highway | **Live + Song Trainer + Practice** kapja meg |
| Pontszám felfutás + csillagok + konfetti a kör végén | ✅ | ✅ (csillagok, dopamin) | ✅ (fireworks, XP counter, „lesson-end screens") | ❌ | ✅ | ❌ | ❌ statikus result-kártya | **Result-jelenet** minden módban |
| Széria-láng animáció + milestone | ✅ | ✅ (playing streaks) | ✅ (150-napos animáció, Friend Streak, widget) | ❌ | ❌ | ❌ | ⚠️ statikus 🔥 | **Flame-grow + milestone + widget** |
| Kombó / multiplier | ❌ | ⚠️ | ❌ | ❌ | ✅ | ❌ | ❌ | **Kombó-számláló** a strike-line-nál |
| Liga / leaderboard / Friend Quest | ✅ (subtle leaderboards) | ✅ (leaderboard, badges) | ✅ (leagues, Friends Quest chest) | ❌ | ❌ | ❌ | ⚠️ community flag-OFF, `ChallengeCard` | Utólag — a community sáv `hold` |
| Megosztható eredmény-kártya (9:16) | ❌ | ❌ | ✅ (Year in Review kártya, rekord install-spike) | ❌ | ❌ | ❌ | ✅ statikus | **Animált preview + „Strum Cam"** |
| **Strum-irány (↓/↑) valós idejű pontozás** | ❌ | ❌ | — | ❌ | ❌ | ❌ | ✅ **EGYEDÜL** | **Ezt kell a képernyő közepére és minden kártyára tenni** |
| Karakter / kabala reakciók | ❌ | ⚠️ | ✅ (Duo + karakterek, „pushier") | ❌ | ❌ | ❌ | ❌ | NEM másoljuk — a réz-glyph a mi kabalánk (ld. spec §0.3) |
| Hangolás: nagy tű + zöld lock | ✅ | ✅ | — | — | ✅ | ✅ (100M+ install, free-wedge) | ⚠️ `cents_gauge` statikus | **Lock-jelenet + haptika** |
| Onboarding „first win < 2 perc" | ✅ | ✅ („a few taps then play") | ✅ | ❌ | ⚠️ | — | ✅ (E17-R01 First-Win Stage) | **Látványos „aha"-pillanat** a Stage-en |
| Reduced motion / a11y | ⚠️ | ⚠️ | ✅ | — | — | — | ✅ (`SsMotionScope`, shape+color) | Megtartjuk — differenciál |

Források (2026-os webes sweep, a részleteket a chunkok őrzik):
[Yousician Play Store](https://play.google.com/store/apps/details?id=com.yousician.yousician&hl=en_US),
[Yousician blog — What's new](https://yousician.com/blog/whats-new-in-yousician-march-update),
[Simply Guitar review — gamification](https://screenwiseapp.com/guides/simply-guitar-app-deep-dive-is-it-the-best-way-to-learn-guitar),
[Simply vs Yousician](https://www.kunstplaza.de/en/music/simply-guitar-or-yousician/),
[Best guitar apps 2026](https://riff.quest/blog/best-app-for-guitar-practice),
[Duolingo product highlights 2025](https://blog.duolingo.com/product-highlights/),
[Duolingo year in review kártya](https://blog.duolingo.com/duolingo-2020-year-in-review),
[Duolingo streak-rendszer breakdown](https://medium.com/@salamprem49/duolingo-streak-system-detailed-breakdown-design-flow-886f591c953f),
[Rocksmith+ news](https://www.ubisoft.com/en-us/game/rocksmith/plus/news-updates),
[GuitarTuna](https://www.appbrain.com/app/guitartuna-tune-play-guitar/com.ovelin.guitartuna),
[Motion design & micro-interactions 2026](https://www.techqware.com/blog/motion-design-micro-interactions-what-users-expect),
[Mobile UI trends 2026](https://www.mindinventory.com/blog/mobile-app-ui-ux-design-trends/).

## 3. A hét viral elem, amit átveszünk (és hogyan lesz a miénk)

A rangsor: hatás ÷ ráfordítás, a chunk 016b P0–P7 és a 013/017 rangsor összefésülve.

| # | Viral elem | Bizonyíték | StrumSight-változat (a moat köré) | Fejezet-kör |
|---|---|---|---|---|
| V1 | **Strike-line juice** (hit-stop + spark + `PERFECT/GOOD/EARLY/LATE` pop + haptika, EGY frame-en) | 016b P0 — „misaligned juice feels worse than none"; Yousician/Simply/Rocksmith mind | A ↓/↑ nyíl maga robban: réz spark ↓-ra, zöld spark ↑-ra; **irány-hiba = `↕` badge**, nem piros X | E18-R02, R05 |
| V2 | **Result-jelenet** (score-ring felfutás → csillagok → egyetlen „következő lépés") | Duolingo lesson-end; Simply csillagok; 017 rec #4 (aha < 2 perc) | `SsScoreRing` 0→érték `celebration` alatt, a ↓/↑ pontosság KÜLÖN ringben (a moat), utána 1 CTA | E18-R03 |
| V3 | **Kombó + safe-failure** | 016b P1; Rocksmith kombó; Duolingo „no harsh X" | Kombó-számláló a strike-line felett; miss = a számláló halkan visszaesik, soha nem villog pirosan | E18-R02 |
| V4 | **Széria-láng, ami nő** + milestone-jelenet + Friday-nudge | 013: +48 % széria freeze-zel, Friday = 25 % veszteség; Duolingo 150-napos animáció | A láng 3 méret (1–3 / 4–7 / 8+ nap), milestone 7/30/100 nap = teljes képernyős réz-jelenet, amit a `CelebrationCoordinator` gyakorlás UTÁN enged | E18-R06 |
| V5 | **Animált Strum Card preview + „Strum Cam"** | 013 #1; Spotify Wrapped 21 % install-spike; Duolingo YIR | A share-preview-n a ↓/↑ minta **beúszik a hangóra ütemére**; a 9:16 export első lépésben MARAD PNG (video = külön ADR) | E18-R07 |
| V6 | **Élő „tuner lock" + metronóm-pulzus** mint free-wedge | 017: GuitarTuna 100M install a tunerrel | Tű → zöld zóna → lock-gyűrű bezárul + rövid haptika; metronóm-korong az audio-órára pulzál (ADR 0274) | E18-R04 |
| V7 | **Today hub „élő" hero** (mai cél-gyűrű, széria, egyetlen CTA, staggered belépés) | Duolingo home; 2026 motion trend: „continuous, living environment" | A hub 3 kártyája `standard` késleltetéssel lép be, a cél-gyűrű a mai percekkel felfut; nincs végtelen dekoráció | E18-R01 |

### 3.1 Paletta (a felhasználó második jelzésére)

A réz/krém alap a RecipeWiser-ből örökölt placeholder, és a felhasználó szerint
„nagyon Claude-dizájnos". A csere token-szintű javaslata (A „Midnight Stage"
ajánlott, B „Tube Amp" alternatíva, kontraszt-mérésekkel) a
[`viral-motion-design-spec.md` §0.5](viral-motion-design-spec.md#05-színpaletta-javaslat--midnight-stage-a-felhasználó-kérésére-2026-09-15)
szakaszában van; a canvas-makettek már az A) palettával készültek.

## 4. Amit TUDATOSAN nem veszünk át

- **Kabala-karakter** (Duo-stílus): idegen a Copper Stage identitástól; a
  réz ↓/↑ glyph a márkánk „arca". (Chapter 13 §9.8: production felületen
  ikon, nem emoji.)
- **Végtelen dekoratív animáció, parallax-háttér, glassmorphism-halmozás**:
  §9.7 tiltja, és a gitáros állványon lévő telefonon csak zavar.
- **Agresszív rázás / piros X hibánál**: §9.7 + 016b safe-failure.
- **Liga/leaderboard most**: az Epic 9 community sáv `hold`; a UI-elem
  (`SsLeaderboardRow`) speckója marad a Chapter 13 UI-59-ben.
- **Paywall-animáció**: nincs monetization SDD (Chapter 13 §3.2).

## 5. Kemény korlátok, amiket minden dizájn betart

1. **Audio-óra** (ADR 0274): minden ritmushoz kötött mozgás `SsBeatClock`-ból
   olvas; nincs `Timer.periodic(60000 ~/ bpm)`; vizuális eltérés ≤ 100 ms.
2. **Nem szakítjuk meg a gyakorlást** (ADR 0389): teljes képernyős ünneplés
   csak `PracticeSessionState.isActive == false` mellett; közben csak inline
   juice (V1/V3).
3. **Reduced motion** (`SsMotionScope`): a visszajelzés MEGMARAD (szín/alak
   lépés), csak a kiterjedés nullázódik; a haptika opt-in.
4. **Shape + color**: ↓ réz + lefelé-glyph, ↑ zöld + felfelé-glyph — hue
   önmagában soha nem hordoz jelentést (016b, Chapter 13 §13).
5. **Teljesítmény** (016b): a highway EGY `CustomPainter` + `RepaintBoundary`
   + egy `Ticker`; részecske ≤ 14/burst; `Paint` cache; cél 120 fps /
   8,3 ms.
6. **Ünneplés ≤ 700 ms** (`SsMotion.celebration`) egy elemre; egy jelenet
   több lépcsőből állhat, de bármikor tappal átugorható.
7. **i18n**: minden új felirat ARB-n megy (en/hu); a `PERFECT/GOOD/EARLY/LATE`
   pop is lokalizált kulcs (`hitVerdictPerfect`…).
