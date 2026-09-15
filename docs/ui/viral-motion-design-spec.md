# Viral motion design spec — funkciónkénti UI-fejlesztés animációval (2026-09-15)

- **Alap:** [`viral-ui-audit.md`](viral-ui-audit.md) (V1–V7 elemek, §5 kemény korlátok),
  Chapter 13 §4.6, §6, §9.7, §11, §19 (UI-01…UI-65).
- **Körterv:** [`../plans/chapter-18-viral-ui-motion.md`](../plans/chapter-18-viral-ui-motion.md).
- **Vizuális makett:** a Claude Design canvas (link a HANDOFF-ban) — a képernyők
  az alábbi §-okat rajzolják meg; a spec az irányadó, a makett illusztráció.

Ez a dokumentum **kiegészíti** a Chapter 13 képernyő-specifikációkat (nem írja
felül): minden §-ban a Chapter 13 UI-azonosító, a meglévő fájl és az ÚJ
motion-réteg szerepel. A DSP/ML/audio réteg érintetlen.

---

## 0. Közös alapok

### 0.1 Új motion-tokenek (additív, `SsMotion` alá)

A meglévő 5 időtartam marad (`instant 80 · fast 120 · standard 200 ·
emphasized 300 · celebration 700`). Új **szemantikai alias**ok — új alapérték
NÉLKÜL:

```text
SsMotion.hitStop        = instant     // 1–2 frame „freeze" a strike-line-on
SsMotion.hitPop         = fast        // PERFECT/GOOD pop be- és kiúszása
SsMotion.comboTick      = instant     // kombó-számláló +1 scale
SsMotion.ringFill       = celebration // score-ring 0→érték
SsMotion.stagger        = 60 ms       // ⚠ ÚJ: lista-elemek belépési késleltetése (≤ 5 elem → ≤ 300 ms összesen)
SsMotion.sceneStep      = emphasized  // ünneplés-jelenet egy lépcsője
```

`stagger` az egyetlen új szám; indoklás: 5 kártya × 60 ms = 300 ms =
`emphasized`, azaz a képernyő belépése soha nem hosszabb egy route-váltásnál.

### 0.2 Új közös komponensek (`lib/core/design_system/`)

| Komponens | Hely | Mit csinál | Reduced motion |
|---|---|---|---|
| `SsStaggeredEntrance` | `motion/` | gyerekek `fade + 12 dp slide-up`, `stagger` késleltetéssel, `enter` görbe | azonnal látható, késleltetés 0 |
| `SsHitJuice` | `motion/` | egy strike-line esemény: hit-stop + spark (`HitBurst` geometria általánosítva) + verdict-pop + opcionális haptika; **egyetlen frame-en indul** a hívó `onHit(time)` hívásától | spark helyett 1 frame-es szín-lépés a glyph-en; pop marad (szöveg) |
| `SsComboCounter` | `components/music/` | `combo` int + `multiplier`; +1-nél `comboTick` scale 1→1,15→1; miss-nél `contentFade` alatt visszaesik 0-ra, **soha nem villog** | scale nélkül, szám lép |
| `SsScoreRingReveal` | `components/analytics/` | a meglévő `SsScoreRing` köré: 0→érték `ringFill` alatt, `emphasizedCurve`, a szám `TweenAnimationBuilder`-rel számol fel | végérték azonnal, szám azonnal |
| `SsCelebrationScene` | `overlays/` | teljes képernyős, tappal átugorható jelenet: `sceneStep` lépcsők (háttér-réz sugár → ikon/glyph → felirat → CTA); a `CelebrationCoordinator` (ADR 0389) hívja, gyakorlás közben SOHA | egyetlen statikus kártya, ugyanazzal a szöveggel |
| `SsFlame` | `components/music/` | széria-láng 3 méretben (S 1–3 nap, M 4–7, L 8+); „nő" animáció a napi jóváírásnál (`emphasized`, scale + réz→arany szín-lépés) | méret-lépés animáció nélkül |
| `SsLockRing` | `components/music/` | tuner „in-tune lock": gyűrű bezárul (`standard`), zöld, +1 haptika tick | gyűrű azonnal zárt, szín lép |
| `SsBeatDisc` | `components/music/` | metronóm-korong, `SsBeatClock`-ról pulzál (ADR 0274): ütemen 1→1,08 scale + fény, hangsúlyos ütemen réz-perem | scale nélkül, perem-szín lép |
| `SsShareReveal` | `motion/` | a 9:16 kártya elemei (akkordok → ↓/↑ minta → stat-chipek → wordmark) `stagger`-rel épülnek fel a preview-n; az export PNG-je a VÉGÁLLAPOT | végállapot azonnal |

Mind a design system rétegében él (ADR 0274: nem importál `lib/features/**`);
az óra és a haptika-beállítás injektált (`SsBeatClock`, `hapticsEnabled`).

### 0.3 A „kabala" — a réz ↓/↑ glyph

Nincs karakter. A márka arca a `SsStrumGlyph`: a spec minden ünneplés-jelenete
és share-kártyája ezt a glyph-et animálja (forgás NÉLKÜL — a nyíl iránya
jelentés). Megengedett: scale, fény-sugár, spark, szín-lépés réz↔arany.

### 0.4 Haptika és hang (Chapter 13 §13.3)

- Haptika: `HapticFeedback.lightImpact` hit-nél, `mediumImpact` lock/milestone-nál;
  **opt-in** beállítás (`GamificationPreferences.haptics`, Kör 27 hozza a
  providert — addig caller-fed `bool`).
- Hang: az ünneplés-chime NEM megy ki a mikrofonos képernyőkön aktív hallgatás
  alatt (a felvétel szennyeződne) — csak a result-jeleneten.

### 0.5 Színpaletta-javaslat — „Midnight Stage" (a felhasználó kérésére, 2026-09-15)

**Miért:** a mai réz `#D98A46` + krém `#F3F0E9` páros a RecipeWiser-ből örökölt
placeholder (CLAUDE.md „Brand tokens … placeholders"), és a felhasználó
mérése szerint „nagyon Claude-dizájnos" (meleg terrakotta + krém = az
AI-asszisztens-esztétika). A gitáros identitáshoz színpadi fény, acélhúr és
erősítő-LED illik, nem konyhai meleg tónus. A Chapter 13 §2 („nem kell
önkényesen lecserélni") itt a felhasználó explicit utasítása (AGENTS.md §2
1. pont) alá kerül; a csere **token-szinten** történik (`SsColors` szemantikai
nevei maradnak, csak az értékek), tehát egyetlen kör, nem képernyőnkénti munka.

**A) Ajánlott — „Midnight Stage"** (hideg éjfél + két jel-szín a ↓/↑-nak + egy CTA-szín):

```text
# Dark Studio (alapértelmezett)
bg              #0B0E14   éjfél (kékes fekete, nem barna)
surface         #141925
surfaceRaised   #1C2331
track           #1A2030
border          #2A3245
ink             #F4F6FB
muted           #8B94AB

strumDown       #FF6B4A   „Ember" korall — a lefelé-pengetés (meleg = nehéz)
strumUp         #3FD8FF   „Ice" cián — a felfelé-pengetés (hideg = könnyű)
accent (CTA)    #D4FF3F   „Signal" lime — az EGYETLEN gomb-szín; szöveg rajta: ink #0E1320
confidenceHigh  #B6E83A   (a lime család — „mehet")
confidenceMed   #FFB020   borostyán
confidenceLow   #7A8299   pala
danger          #FF3D6E   rózsa-piros (a koralltól alak+ikon is elválasztja)

# Daylight (világos téma) — hideg fehér, NEM krém
bg #F4F6F9 · surface #FFFFFF · ink #0E1320 · muted #5B6478 · border #D6DBE6 · track #E9EDF3
strumDown #E8563A · strumUp #0B93C4 · accent fill #CBEF3C (ink szöveggel) · link/ikon-accent #0E7C86
confidenceHigh #5E8C00 · confidenceMed #B86E00 · confidenceLow #6B7385 · danger #D81B4E

# High Contrast
bg #000000 · surface #0A0A0A · ink #FFFFFF · strumDown #FF7A5C · strumUp #66E0FF · accent #E2FF5A · border #FFFFFF
```

Kontraszt (mért, WCAG relatív luminancia): ink/bg 18:1 · muted/bg 6,5:1 ·
strumDown/bg 7:1 · strumUp/bg 11:1 · accent/bg 16:1 · ink/accent 15:1 ·
világos témán strumDown 3,6:1 és strumUp 3,9:1 = UI-komponens/nagy szöveg
szint (a testszöveg mindig `ink`). A ↓/↑ soha nem csak szín: glyph-alak is
(§0.3, audit §5.4).

**Tipográfia hozzá:** a Poppins/Montserrat marad (asset már van), de a
chord-hero és a score-számok **Montserrat ExtraBold, −2 % letter-spacing**,
a címek Poppins SemiBold — a kerek-barátságos Poppins Regular a body-ra
szorul vissza, hogy a stage-számok „erősítő-kijelzőnek" tűnjenek.

**B) Alternatíva — „Tube Amp"** (ha a meleg irány marad, de rézmentesen):
bg `#111111` · surface `#1B1B1B` · strumDown `#FF4F1F` (amp-narancs LED) ·
strumUp `#FFE066` (meleg sárga) · accent `#F5F1E8`-on `#111111` (inverz gomb) ·
confidenceHigh `#8BE04B`. Kevésbé különbözik a mai ránézésre, ezért NEM ez
az ajánlás.

**Döntés:** a tulajdonosé. A canvas-makettek és a Chapter 18 R00 köre az
**A) Midnight Stage** palettát viszik; a régi réz-tokenek a `SsColors`-ban
egyetlen commitban cserélődnek, a golden-mátrix (E15-R13, 1152 cella)
újra-baseline-olása a kör része.

---

## 1. Today Hub — UI-05 (`lib/features/today/screens/today_hub_screen.dart`) — V7

**Ma:** 301 soros, statikus kártyalista.

**Új dizájn:**

1. **Hero „Ma"-kártya** (`SsHeroCard`): balra a napi cél-gyűrű
   (`SsScoreRingReveal`, percek / cél), jobbra a `SsFlame` + „N napos széria",
   alatta EGY elsődleges CTA („Folytasd: First Strums · 3 perc").
2. **Belépés:** `SsStaggeredEntrance` — hero → mai kihívás → „Heti recap"
   chip → gyors-elérés sor (Tuner · Metronóm · Live). ≤ 300 ms összesen.
3. **Mai kihívás kártya** (`ChallengeCard`): a ↓/↑ mintát egy mini
   `SsBeatGrid` mutatja; tapra a minta egyszer „végigfut" (`SsBeatClock` nélkül
   nincs élő pulzus — ez egy `emphasized` egyszeri preview, nem ritmus-óra).
4. **Széria-veszély állapot** (péntek 25 %): a hero réz-perem helyett borostyán
   `SsStatusBadge` „Ma még nem gyakoroltál" — mozgás nélkül, csak szín+ikon.
5. **Üres állapot** (első nap): a glyph egyszer „lélegzik" (scale 1→1,04→1,
   `emphasized`), majd áll. Nem végtelen.

**Elfogadás:** golden light/dark/en/hu; a stagger reduced motion alatt 0;
a hero CTA az egyetlen `FilledButton` a képernyőn.

## 2. Onboarding — UI-03/04 (`lib/features/onboarding/`) — V1 + V2 előzetes

**Ma:** 3 oldal + First-Win Stage (E17-R01) — élő konfidencia, de statikus.

**Új dizájn:**

1. **Érték-oldal:** a három ígéret (akkord → ↓/↑ → széria) `SsStaggeredEntrance`;
   a ↓/↑ oldal közepén egy `SsStrumGlyph`-pár, ami tapra egyszer réz/zöld
   sparkot ad (`SsHitJuice` demo, hang nélkül) — „így fog kinézni, amikor jól
   pengetsz".
2. **Mikrofon-primer:** a mikrofon-ikon körül `SsSignalQualityIndicator`
   gyűrű; engedély megadásakor a gyűrű zöldre zár (`SsLockRing`).
3. **First-Win Stage:** a `LiveFrame.confidence` a Stage közepén egy nagy
   `SsScoreRingReveal`-ben nő; **első ≥ küszöb** pillanatban `SsHitJuice`
   (réz spark + „Megvan!" pop + haptika) → 700 ms után CTA „Tovább". A
   megtagadott engedély ága változatlan (D5), animáció nélkül.

## 3. Live Stage — UI-08 (`lib/features/live/`) — V1 + V3

**Ma:** hero csak akkordnál; ütemsor alul; `ChordTimeline` és `StrumArrow`
CustomPainter; `ConfidencePill`; `UncertaintyReasonBanner` (E14-R13).

**Új dizájn (a képernyő közepe él):**

1. **Chord-hero** (`SsChordHero`): akkordváltáskor `chordChange` crossfade +
   0,96→1 scale (§9.7). Mellette a **strum-glyph 96 dp**, ami minden
   érzékelt pengetésen `SsHitJuice`-t kap: ↓ réz spark lefelé, ↑ zöld spark
   felfelé, **a felismerés frame-jén** (a `LiveFrame` timestampje az
   esemény-idő; nem UI-timer).
2. **Kombó** (`SsComboCounter`) a hero felett: egymást követő, a metronómra
   pontos pengetések; miss-nél halkan 0-ra esik.
3. **Ütemsor** (meglévő ↓/↑ sor): a *következő* várt nyíl 1,1× és világosabb
   (anticipáció, 016b P5) — az audio-óra fázisából (`SsBeatClock` a Live
   metronóm-órájával).
4. **Üres/„Listening" állapot:** a glyph-pár halványan „lélegzik" egyszer
   induláskor, utána áll; a `LISTENING` pötty a meglévő.
5. **Bizonytalanság** (`UncertaintyReasonBanner`): mozgás nélkül úszik be
   (`contentFade`) — a Stage-slot változatlan.
6. **Pause:** a mikrofon-állapot váltása = a hero `contentFade` alatt
   elszürkül + haptika (r188 megtartva).

**Tilos:** bármilyen `Timer`-alapú pulzus; a hang-elemzés érintése.

## 4. Tuner — UI-09 (`lib/features/tuner/widgets/cents_gauge.dart`) — V6

1. **Tű:** a cents-érték `fast` (120 ms) `Tween`-nel simul (nem ugrik), az
   irány marad mért.
2. **Lock:** in-tune ≥ `in_tune_lock` időn túl → `SsLockRing` bezárul, a hang
   neve zöld, `mediumImpact` haptika, a húr-jelző pipát kap. Kilépés a
   zónából: gyűrű nyílik `standard` alatt.
3. **Mind a 6 húr behangolva:** egyetlen `sceneStep` „Behangolva ✓"
   `SsInlineMessage` réz-perem-fénnyel — NEM teljes képernyős (a tuner
   utility, ne lassítsa).
4. **Referencia-hang gomb:** lenyomásra hullám-ikon 3 gyűrűs terjedés,
   `emphasized`, egyszer.

## 5. Metronóm — UI-10 (`lib/features/metronome/`) — V6

1. **`SsBeatDisc`** a képernyő közepén: az audio-óráról pulzál; hangsúlyos
   ütemen réz perem, mellékütemen halvány.
2. **BPM-változtatás:** a szám `TweenAnimationBuilder`-rel gördül (`fast`).
3. **Tap-tempo:** minden tap egy `instant` spark a korongon.
4. **Landscape:** a korong a bal panelen, a vezérlők jobbra (r188 layout
   megtartva).

## 6. Learn / Learning Path / Lesson — UI-13/14 (`lib/features/learn/`) — V1 + V2 + V3

**Ma:** `LessonHighway` (widget-Stack, per-frame layout — 016b szerint ez a
teljesítmény-plafon), `HitBurst` már fut.

**Új dizájn:**

1. **Highway → egy `CustomPainter`** (016b P2): egy `Ticker`, `RepaintBoundary`,
   `Paint` cache; a chord-nevek vékony cache-elt réteg. A látvány: kártyák
   távolról kicsik/halványak, a strike-line felé nőnek és fényesednek
   (vanishing-point, P5) — NEM 3D, csak scale + alpha.
2. **Strike-line juice** (`SsHitJuice`): a meglévő `HitBurst` általánosítva; a
   verdict-pop: `PERFECT / GOOD / EARLY / LATE / ↕` (ARB kulcsok). EARLY/LATE
   előjeles (016b P6): a pop a strike-line-tól balra/jobbra tolva jelenik meg.
3. **Kombó** a highway felett; **Easy-mód ajánlat** (r154) változatlan logika,
   csak `contentFade`-del úszik be.
4. **Learning Path lista:** `SsStaggeredEntrance`; a „Continue" kártya
   réz-perem-fénye egyszer felvillan belépéskor (`emphasized`); a lakat
   feloldásakor a lakat-ikon `standard` alatt nyílik → play-ikonná vált
   (`AnimatedSwitcher`), a kártya 1× lélegzik.
5. **Lecke-vége** → §7 result-jelenet.

## 7. Practice Result / Lesson Result / Song Result — UI-21/31 — V2

(`lib/features/practice/presentation/screens/practice_result_screen.dart`,
`learn/widgets/lesson_score_card.dart`, `song_trainer/.../song_result_screen.dart`)

**Egy közös jelenet, három hívó:**

1. **0–700 ms:** a fő `SsScoreRingReveal` felfut (összpontszám); mellette
   KÜLÖN, kisebb ring a **↓/↑ irány-pontosság** — a moat mindig látszik.
2. **+300 ms:** csillagok (0–3) egyenként `sceneStep` lépcsőkben, mindegyik
   réz spark; reduced motion: egyszerre, statikusan.
3. **+300 ms:** EGY „következő lépés" `SsCoachActionCard` úszik be
   (`contentFade`) — a Chapter 13 §4.2 „egyetlen javítás" elve.
4. **Rekord** (személyes legjobb): `SsCelebrationScene` — de CSAK ha
   `PracticeSessionState.isActive == false` (ADR 0389), és a
   `CelebrationCoordinator` egyetlen összevont jelenetet enged.
5. **Share sor:** ≥ 80 % pontosságnál a `WrappedPrompt` marad; mellé a
   Strum Card **mini-preview** (thumbnail, `SsShareReveal` egyszer lefut) —
   „a büszkeség pillanata a megosztás pillanata" (017).
6. **Részletek:** a timeline/heatmap **nem animál**, csak a summary-szint.

## 8. Practice Session / Speed Builder — UI-19/23 — V1 + V3

`practice_session_screen.dart`, `speed_builder_screen.dart`: a §3 Live
hero + §6 highway ugyanazokat a komponenseket kapja (`SsHitJuice`,
`SsComboCounter`). Speed Builder: a BPM-lépcső emelkedésekor a
`SsTempoDisplay` szám felgördül és a réz-perem egyszer felvillan;
„lépcső teljesítve" = inline `SsInlineMessage`, nem jelenet.

## 9. Song Trainer — UI-30 (`song_trainer_screen.dart`) — V1 + V3 + V5

1. A dal ütemsora a §6 highway-painteren (közös kód, a `LoopRange` réteg
   felette).
2. Szakasz-vége (verse/chorus) = **section-end** mini-ünneplés: a highway
   felett réz-sáv fut át (`emphasized`), a kombó megmarad; NEM teljes
   képernyős (016b P1).
3. Dinamikus nehézség (016b P4) ajánlat-sor változatlan logika, `contentFade`.
4. Dal vége → §7 jelenet + Strum Card preview a dal ↓/↑ mintájával.

## 10. Chord Library / Chord Detail — UI-11/12 (`lib/features/chords/`)

1. **Lista:** `SsStaggeredEntrance` a rács első 8 elemére (a többi azonnal).
2. **Diagram** (`SsChordDiagram`): a fogás-pontok `stagger`-rel „landolnak"
   (scale 0,6→1, `fast`), egyszer belépéskor; tapra „pengetés" — a húrok
   fentről lefelé `instant` késleltetéssel villannak (↓ minta), egyszer.
3. **Váltás akkordok közt:** `chordChange` crossfade, a diagram-pontok
   ténylegesen ELCSÚSZNAK az új helyre (`AnimatedPositioned`, `standard`) —
   ez tanít is (ujjmozgás), nem csak dísz.

## 11. Progress / Gamification Hub / Streak / Achievements — UI-49/51/52

(`progress_v2/`, `gamification/presentation/`)

1. **Hub:** `SsStaggeredEntrance`; `XpProgressBar` a belépéskor 0→érték
   `ringFill` alatt, szintlépésnél `SsCelebrationScene` (koordinátoron át).
2. **Széria-részlet:** `SsFlame` L méretben; a naptár-rács napjai `stagger`-rel
   gyulladnak (max 7 → ≤ 420 ms); freeze-ikon jégkék, mozgás nélkül.
3. **Milestone 7/30/100 nap:** `SsCelebrationScene` (réz sugár → láng L →
   „7 napos széria" → „Oszd meg" CTA a Wrapped-kártyára).
4. **Achievements:** feloldott jelvény `AnimatedSwitcher`-rel fordul szürkéről
   színesre (`emphasized`, flip NÉLKÜL — csak crossfade+scale); a
   `RewardInboxScreen` új eleme `SsStaggeredEntrance`-szel jön.
5. **Trend-grafikon (`WeeklyBars`):** az oszlopok belépéskor 0→érték
   `standard` alatt, egyszer; utána statikus (Chapter 13 §16).

## 12. Share Preview / Wrapped — UI-65 (`lib/features/share/`) — V5

1. **Preview:** `SsShareReveal` — a kártya elemei felépülnek; a ↓/↑ minta
   nyilai egyesével „landolnak" (réz/zöld spark nélkül — a kártyán a
   tisztaság számít). Export = végállapot PNG (a meglévő
   `RepaintBoundary` pipeline).
2. **Share-gomb:** lenyomásra a kártya 0,98 scale (`instant`), utána a
   natív sheet.
3. **„Strum Cam" (videó):** KÜLÖN ADR és kör; a kódoló-függőség
   (`ffmpeg_kit_flutter_new`) licenc/méret-döntés — ebben a sávban NEM.

## 13. Analyze / Analysis Overview / Timeline — UI-34/37/38

1. **Feldolgozás:** a meglévő `AnalyzeSkeleton` shimmer marad; a processing
   képernyőn a glyph-pár egyszer lélegzik, majd `SsProgressIndicator`.
2. **Overview:** a 3 metrika-kártya `SsStaggeredEntrance`; a fő ring
   `SsScoreRingReveal`.
3. **Timeline:** NEM animál (adat-hűség); a kiválasztott esemény
   `contentFade` alatt kap réz-peremet.

## 14. Coach / AI Tutor — UI-42/43 (flag-OFF; csak spec)

1. `SsStreamingMessage`: karakterenkénti megjelenés helyett **szó-blokkok**
   `fast` fade-del (olvashatóbb, olcsóbb).
2. `SsCoachActionCard`: belépéskor `contentFade`; a „Próbáld ki" CTA
   réz-perem egyszer.
3. Provenance-badge (local/cloud) mozgás nélkül — bizalmi jelzés, ne
   „ugráljon".

## 15. Vision Coach — UI-46 (flag-OFF; csak spec)

`SsVisionOverlay`: a kalibrációs keret sarkai `standard` alatt zárulnak
zöldre, ha a gitár a keretben; technika-cue (`SsTechniqueCue`) `contentFade`.
Nincs részecske a kamerakép felett (olvashatóság).

## 16. Settings / Profile / Community — UI-07/53–63

- `SsSwitchRow` toggle `instant`; téma-váltás `contentFade` crossfade a
  teljes scaffoldon (M3 fade-through, backlog #3 zárása).
- Profile hero: `SsFlame` + szint-badge, `SsStaggeredEntrance`.
- Community (hold): a `SsPostCard` reaction-bar +1 `comboTick`-szerű scale;
  minden más a Chapter 13 UI-54…60 szerint, ebben a sávban NEM épül.

---

## 17. Elfogadási mátrix (minden körre közös)

| Cella | Mérce |
|---|---|
| A-MOTION-1 | Minden ritmushoz kötött komponens `SsBeatClock`-ról olvas; grep `Timer.periodic` a `lib/core/design_system/motion/**` és a kör fájljaiban = 0 találat |
| A-MOTION-2 | Reduced motion alatt minden új komponens ugyanazt az információt adja (widget-teszt: szöveg/ikon/szín jelen van, `Duration.zero`) |
| A-MOTION-3 | Egyetlen animáció sem hosszabb `SsMotion.celebration`-nél; a jelenetek tappal átugorhatók |
| A-MOTION-4 | Gyakorlás közben (`isActive`) nincs `SsCelebrationScene` (koordinátor-teszt) |
| A-MOTION-5 | Golden light/dark × en/hu × compact/landscape × textScale 1,0/2,0 minden érintett képernyőre (E15-R13 mátrix bővítése) |
| A-MOTION-6 | A highway painter `shouldRepaint` csak playhead-változásra igaz; 1 `Ticker` |
| A-MOTION-7 | Minden új felirat ARB-kulcs (en+hu), `l10n` guard zöld |
| A-MOTION-8 | Shape+color: minden ↓/↑ vizuál glyph-et is hordoz (semantics label + alak) |
