# E14-R10 — Azonnali direction abstention hotfix

- **Státusz:** REVIDEÁLVA ×2 (ADR 0112 önjavító kör, 2026-09-05, `main @ cc936bde`;
  majd a kör pre-flightja, 2026-09-05, `main @ 39680e1e`)
  — az eredeti PREPARED szöveg 2026-08-20-án, `main @ 88e08e65`-en készült
- **Típus:** Chapter 14 (Recognition Accuracy & Useful UI Recovery), Kör 10 — az
  „azonnali truthfulness és UX hotfix" blokk (SDD §8: R10–R14) nyitó köre
- **Kör-azonosító:** `E14-R10`
- **Branch:** `<motor>/e14-r10-direction-abstention-hotfix`
- **Előfeltétel:** `E14-R04` merge-elve (a `RecognitionDecision` állapotok **és**
  az ADR 0505 predikció-szerződés) — ez a kör ANNAK a bekötése.
- **Brief szerzője:** Claude (Opus 5); **revideálta:** ADR 0112 önjavító kör
- **A kör ADR-je:** **`0512`** — `docs/adr/0512-live-direction-abstention-wiring.md`,
  a pre-flightban MEGÍRVA. (Az előre kiosztott `0362` elavult; a foglaló a
  `0512`-t adta — lásd §0.0/8.) A `docs/adr/` az implementernek TILOS zóna.

## 0.0 Revízió (ADR 0112 önjavító kör, 2026-09-05) — MÉRT, kötelező olvasmány

Az eredeti brief **H3-ra futott a dispatch ELŐTT**: a célja csak az
`allowed_paths` tágításával volt teljesíthető, ami az orchestrátornak nem
hatásköre (ADR 0087 §2). A teljes mért diagnózis:
`.pipeline/halt-detail-E14-R10.md`. Amit a revízió megváltoztat:

**1. A döntés MÁR LÉTEZIK — a kör nem épít másodikat.** Az eredeti §5.1 egy ÚJ
`strum_direction_gate.dart`-ot írt elő **0,150**-es margóval, ELFOGADÁS-oldalon
inkluzívan. Közben (2026-09-04, PR #568, squash `f1fced77`) merge-elve landolt
ugyanez a döntés: `StrumPrediction.decision`
(`lib/features/live/domain/recognition/strum_prediction.dart:53-60`), küszöb
**0,05**, ELUTASÍTÁS-oldalon inkluzív (`margin <= 0.05` → `uncertain`), ADR 0505
D4. Két versengő döntési hely ugyanarra a kérdésre sérti az eredeti brief SAJÁT
§5.4-ét („egy eseményre egy végleges irány"). **A `strum_direction_gate.dart` és
a hozzá tartozó `strum_direction_gate_test.dart` ezért TÖRÖLVE a scope-ból.**

**2. A kör valódi munkája a BEKÖTÉS.** Az ADR 0505 D5 kimondja
(`live_frame_adapter.dart:23-25`): „The live pipeline / engine is NOT rewired to
this adapter in this round … **that is a later round's job**." **Ez az a kör.**
Mérve: `grep -rn "StrumPrediction(\|RecognitionFrame(" lib/` → a saját ctor +
`fromJson` mellett **NULLA hívó** — a szerződésnek ma egyetlen termelője sincs.
Az „`uncertain` → nincs nyíl" (eredeti 3. acceptance) pedig MÁR SZÁLLÍTVA VAN
(`LiveFrameAdapter._strumFor` minden nem-`confirmed` döntésre `null`-t ad), tehát
nem új munka.

**3. A küszöböt ez a kör NEM változtatja meg — mert nem tudja MÉRNI.** Az
eredeti §5.2 helyesen követel mért küszöböt. A jelen fából a kért
coverage/accuracy pár **nem olvasható ki**: az
`evaluation/recognition/baseline_manifest.json` a kalibrációt
`not-measured`-ként jelöli (nincs confidence-alapigazság a 82 felvételes
korpuszon, ADR 0249 §D4), a bin-enkénti coverage pedig sehol nincs rögzítve. A
`0,150` tehát VÁLASZTOTT szám lett volna, pontosan az, amit a §5.2 tilt. **A kör
a szállított `0.05`-öt használja változatlanul**, és a `docs/eval/…` rögzíti,
mit kell lefuttatni (`ml/honest_eval.py` held-out fold) ahhoz, hogy egy KÜLÖN,
mért kalibrációs kör az ADR 0505 D4 által előre engedélyezett módon
felülírhassa. A `strum_prediction.dart` ezért **szándékosan NINCS** az
`allowed_paths`-on: a szerződés ebben a körben érintetlen.

**4. `allowed_paths` TÁGÍTÁS (ez az önjavító kör hatásköre, nem az
orchestrátoré).** A bekötéshez `pDown`/`pUp` kell, ami ma a
`LiveCrnnStrumClassifier.classifyProbs`-ban **megszületik és eldobódik**
(`live_crnn_classifier.dart:186-193` — csak `calibrate(max)` marad). A három
termelő-fájl (`live_crnn_classifier.dart`, `strum_direction_classifier.dart`,
`strum_analyzer.dart`) az eredeti briefben TILOS ZÓNA volt → ezért volt a kör
teljesíthetetlen. Felvéve, **szigorúan additív** használatra (lásd §5.1).

**5. Kivéve a scope-ból, KÜLÖN körbe (mérve: az engedélyezett fájllal
ELLENTÉTES eredményt adna).** Az eredeti 4. és 6. acceptance-pont:

- **Gyakorlás-pontozás (eredeti §5.5 / 6. pont).** A brief a
  `live_practice_observation_gateway.dart`-ot engedte, de a gateway egyetlen
  in-scope eszköze (az observation elnyomása) a scorer felől nézve `wrong`,
  `scorePerMille: 0` (`practice_direction_scorer.dart:76-82`) — vagyis PONTOSAN
  az a „hibás irány", amit a pont tiltani akar. A helyes megoldáshoz a
  `practice_direction_scorer.dart` + `practice_event_matcher.dart` +
  `practice_observation.dart` (a `StrumObservation.direction` ma nem nullable)
  EGYÜTT kell — külön kör.
- **Felhasználói küszöb (eredeti §5.3 / 4. pont).** Mérve: a
  `confidenceThresholdProvider`-t a felismerési út **egyáltalán nem olvassa**
  (csak `settings_sync.dart` + `settings_screen.dart`), tehát ez nem „szigorítás
  egy meglévő kapun", hanem ÚJ bekötés. Ráadásul a CRNN `calibrate()` knot-listája
  **0,55 alá soha nem megy** (`live_crnn_classifier.dart:212-215`), a provider
  alapértéke `0,45` — a mai felhasználói küszöb tehát a CRNN ágon egyetlen
  pengetést sem utasítana el. Ezt a `docs/eval/…` rögzíti; a bekötés külön kör.

**6. Brief-lint S12** (a `.pipeline/brief-lint-E14-R10.md` lelete): a §7 parancs
most tételesen felsorolja a `gate_tests` minden elemét.

**7. Az osztály gépi őre.** Ez a halt-osztály (előre megírt brief mért alapja
elmozdul alatta) mostantól **`brief-lint` S15**-ként mérve van
(`tools/tests/test_brief_base_sha_drift.py`, `docs/LESSONS.md` L636) — a jövőben
a kör pre-flightja kapja teendőként, nem egy elégetett session.

## 0.0b Pre-flight revízió (a kör orchestrátora, 2026-09-05, `main @ 39680e1e`)

A §0.0 minden mért állítását újramértem a jelen fán — **mind igaz** (a
`0.05`-ös, elutasítás-oldalon inkluzív döntés, a `classifyProbs` eldobott
`pDown`/`pUp`-ja, a nulla `StrumPrediction`-termelő, a `not-measured`
kalibráció, a `calibrate()` 0,55-ös alsó knotja). Két dolgot a pre-flight
javít:

**8. Az előre kiosztott `0362` ADR-szám ELAVULT — a kör ADR-je `0512`.** A
`docs/adr/0362-*.md` nem létezik, de a foglaló
(`tools/round-slots.py reserve-adr --round E14-R10`, ADR 0087 §1.0.1) a
**`0512`**-t adta, mert a lemezen a legmagasabb `0511`. Ugyanaz a mintázat,
mint az E14-R09-nél (`0361` → `0511`) és az E14-R08-nál (`0360` → `0509`): a
2026-08-20-i előre-írt hullám ADR-számai tárgytalanok. Az ADR **megírva**:
`docs/adr/0512-live-direction-abstention-wiring.md` (D1–D6). A `docs/adr/`
ettől függetlenül az implementernek TILOS zóna.

**9. A küszöb-hármas „rajta" cellája IEEE-754-ben MÉRVE nem az, aminek látszik.**
A §6/2 „rajta `0.050` → `uncertain`" cellája a naiv, 1-re összegző párral
**PIROS** lenne. Mérve (`python3`, `double(0.05) = 0.05000000000000000277…`):

| `(pDown, pUp)` | `abs(pDown - pUp)` | `decision` |
|---|---|---|
| `(0.5245, 0.4755)` | `0.04899999999999999` | `uncertain` ✅ (a „alatta" cella jó) |
| `(0.525, 0.475)` | `0.050000000000000044` | **`confirmed`** ❌ — nem „rajta" |
| `(0.55, 0.50)` | `0.050000000000000044` | **`confirmed`** ❌ |
| `(1.0, 0.95)` | `0.050000000000000044` | **`confirmed`** ❌ |
| `(2·T, T)` = `(0.1, 0.05)` | `0.05` (EGZAKT) | `uncertain` ✅ |
| `(0.5255, 0.4745)` | `0.05099999999999999` | `confirmed` ✅ (a „fölötte" cella jó) |

Az `a + b == 1.0` megkötés mellett a küszöb **egzaktan elérhetetlen**
(`a = (1+T)/2` nem reprezentálható double-ként), ezért a „rajta" cellát a
konstansból származtatott `(2 * T, T)` párral kell felírni, ahol
`T = StrumPrediction.uncertainMarginThreshold` — nem `0.525`/`0.475`-tel, és a
`T` értékét a teszt **nem** duplikálja. Ez a cella ezért a
`StrumPrediction.decision` szintjén él (a pipeline renormalizált bemenetén a
küszöb-egyenlőség elérhetetlen — ez a szerződés mért következménye, nem
gyengítés). Normatív forrás: **ADR 0512 D6**.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/live/engine/dsp/live_pipeline.dart",
  "lib/features/live/engine/dsp/strum_analyzer.dart",
  "lib/features/live/engine/dsp/strum_direction_classifier.dart",
  "lib/features/live/engine/ml/live_crnn_classifier.dart",
  "lib/features/live/public.dart",
  "test/features/live/strum_direction_abstention_test.dart",
  "test/features/live/dsp/live_pipeline_test.dart",
  "test/features/live/dsp/strum_classifier_seam_test.dart",
  "test/features/live/ml/live_crnn_classifier_test.dart",
  "docs/eval/recognition-direction-abstention.md",
  "docs/rounds/e14-r10-direction-abstention-hotfix.md",
]
gate_tests = [
  "test/features/live/strum_direction_abstention_test.dart",
  "test/features/live/dsp/live_pipeline_test.dart",
  "test/features/live/live_frame_adapter_test.dart",
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

A felhasználó **ne kapjon magabiztos nyilat bizonytalan pengetésre**. A már
merge-elt döntési szerződés (`StrumPrediction.decision`, ADR 0505) kapjon
**termelőt** a Live úton: a CRNN osztály-valószínűségei jussanak el a döntésig,
és `uncertain` döntésnél a frame ne hordozzon ↓/↑ irányt.

### 1.1 Visszakeresett előzmény (ADR 0312)

- **E14-R01 release guard:** `UNKNOWN > CONFIDENTLY WRONG` — ez a kör ennek az
  első futásidejű érvényesítése a strum-oldalon.
- **AGENTS.md §9 (DSP-tilalom):** shipping DSP/ML konstans NEM hangolható mért
  A/B és ADR nélkül — ezért a kör **egyetlen** DSP/ML konstanst sem ír át
  (sem a heurisztikus létrát, sem a `calibrate` knot-listát, sem a
  `noStrumThreshold`-ot, sem az `uncertainMarginThreshold`-ot).
- **ADR 0505 D2:** nyers valószínűséget confidence-alakú mezőbe másolni (és
  fordítva) TILOS.

Pre-flight visszakeresés (`node tools/knowledge-rag.mjs --corpus lessons,halts,adr`,
2026-09-05) — a három döntő találat:

- **`lessons/L624`** (E14-R04 review MAJOR-1, `bm25#9 emb#2`): a szerződés-kör
  felépítette a bizonytalanság szótárát, majd a SAJÁT egyetlen fogyasztójában
  csak az akkordot kapuzta, a strumot nem. **Ez a kör ennek a párja**: most a
  szótárnak TERMELŐT adunk — ha a valószínűségek eljutnak a modellig, de a
  pipeline mégis a régi közvetlen `Strum`-utat járja, ugyanaz a hibaosztály
  ismétlődik meg.
- **`lessons/L295`** (E07-R14, `emb#1`): egy publikus policy-mező
  constructor-validációja NEM bizonyítja, hogy a mező vezérli a viselkedést —
  az implementáció validálta és dokumentálta a mezőt, amit az allocator sosem
  olvasott, és a célzott gate zölden maradt. **Következmény erre a körre:** a
  `pDown`/`pUp` mezők PUSZTA jelenléte a `StrumEvent`-en nem acceptance —
  a 3. pont (nincs nyíl) az egyetlen bizonyíték, hogy vezérelnek is.
- **`lessons/L164` / `L167`** (E05-R12 / E05-R14): „additív bővítés" ne
  feltételezésből induljon — a hívókat és a pinnelt assertionöket ki kell
  grepelni. **Mérve ehhez a körhöz:** `StrumEvent` → 23 hivatkozó fájl,
  `StrumClassification` → 8, közülük a TILOS zónában
  `clip_analyzer.dart`, `strum_crnn.dart`, `test/property/dsp_property_test.dart`,
  `test/features/live/dsp/strum_analyzer_suppression_test.dart`.

## 2. Jelenlegi állapot — mért tények (`main @ cc936bde`)

- `lib/features/live/domain/recognition/strum_prediction.dart:53-60` — a
  döntés: `directionMargin = |pDown − pUp|`, `uncertainMarginThreshold = 0.05`,
  `margin <= 0.05` → `uncertain`. **Merge-elve, termelő nélkül.**
- `lib/features/live/domain/recognition/live_frame_adapter.dart:74-92` —
  `_strumFor` minden nem-`confirmed` döntésre `null`-t ad (nincs nyíl). Kész.
- `lib/features/live/engine/ml/live_crnn_classifier.dart:177-200` —
  `classifyProbs` KISZÁMOLJA a renormalizált `pDown`/`pUp`-ot, majd **eldobja**;
  csak `calibrate(max)` marad meg confidence-ként.
- `lib/features/live/engine/dsp/strum_direction_classifier.dart:27-44` —
  `StrumClassification{direction, confidence, suppressed}` — **nincs**
  osztály-valószínűség.
- `lib/features/live/engine/dsp/strum_analyzer.dart:14-24` —
  `StrumEvent{timeSec, direction, confidence}` — **nincs** osztály-valószínűség.
- `lib/features/live/engine/dsp/live_pipeline.dart:196-203` — a `StrumEvent`-ből
  KÖZVETLENÜL `Strum` épül, döntési réteg nélkül.
- A heurisztikus ág (`HeuristicStrumClassifier`) confidence-e **rögzített létra**
  (`0.8 + 0.05*gap` / `0.55` / `0.5` / `0.3`), **nem valószínűség** — ott
  `pDown`/`pUp` nem létezik és nem is fabrikálható.

## 3. Scope

**Benne:** az osztály-valószínűségek additív kivezetése a CRNN ágon a
classifier → analyzer → pipeline úton; `StrumPrediction` építése a pipeline-ban;
a döntés érvényesítése a frame felé; a küszöb-származtatás dokumentálása.

**Nincs benne:** DSP/ML konstans hangolása (a `0.05`-öt SEM), modellcsere, új
modell-asset, UI-redesign (R13), chord-oldal (R11), `ml/**`, a
gyakorlás-pontozás és a felhasználói küszöb bekötése (§0.0/5. — külön körök).

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `lib/features/live/engine/ml/live_crnn_classifier.dart` | a már kiszámolt `pDown`/`pUp` KIVEZETÉSE (additív) |
| `lib/features/live/engine/dsp/strum_direction_classifier.dart` | `StrumClassification` additív, NULLÁZHATÓ valószínűség-mezők |
| `lib/features/live/engine/dsp/strum_analyzer.dart` | `StrumEvent` továbbviszi őket |
| `lib/features/live/engine/dsp/live_pipeline.dart` | `StrumPrediction` építése + a döntés érvényesítése |
| `lib/features/live/public.dart` | additív export, ha kell |
| `test/features/live/strum_direction_abstention_test.dart` | a kör ÚJ mércéje |
| `test/features/live/dsp/live_pipeline_test.dart` | a bekötés meglévő pinjei |
| `test/features/live/dsp/strum_classifier_seam_test.dart` | a seam meglévő pinjei |
| `test/features/live/ml/live_crnn_classifier_test.dart` | a `classifyProbs` meglévő pinjei |
| `docs/eval/recognition-direction-abstention.md` | a küszöb származtatása és a HIÁNYZÓ mérés receptje |
| `docs/rounds/e14-r10-direction-abstention-hotfix.md` | §10 handoff |

**Tilos zóna:** minden más — kiemelten
`lib/features/live/domain/recognition/**` (a szerződés ebben a körben
ÉRINTETLEN, §0.0/3.), `lib/features/practice/**`,
`lib/features/settings/**`, `lib/features/live/engine/dsp/dsp_config.dart`,
`assets/**`, `ml/**`, `docs/rag/chunks/**`, `docs/adr/**`,
`.github/workflows/**`, `tools/round-gate.sh`.

## 5. Kötött architekturális döntések (ADR 0512 — a pre-flightban MEGÍRVA, olvasd el)

### 5.1 A kivezetés SZIGORÚAN ADDITÍV

`StrumClassification` és `StrumEvent` új mezői **nullázhatók és
alapértelmezettek** (`double? pDown, pUp, pNoStrum` — vagy egyetlen nullable
valószínűség-rekord), hogy a `StrumEvent`/`StrumClassification` ~20 meglévő
hívója (`test/property/**`, `audio_analysis`, `song_trainer`) **változtatás
nélkül forduljon**. Egyetlen meglévő mező típusa, neve és értéke sem változik.
**NEM elfogadható** gyengítés: a `confidence` mező újraértelmezése
valószínűségként (ADR 0505 D2).

### 5.2 A heurisztikus ág NEM kap kitalált valószínűséget

A `HeuristicStrumClassifier` confidence-e rögzített létra, nem valószínűség —
inverziója kitalált szám volna, azaz pontosan a `CONFIDENTLY WRONG`, amit a kör
meg akar szüntetni. A heurisztikus ág valószínűség-mezői **`null`**-ok, és
`null` valószínűség esetén a pipeline a **MAI viselkedést tartja** (közvetlen
`Strum`, nincs abstention). A kör hatása így a CRNN ágra korlátozódik — ez a
szállított út; a heurisztikus csak akkor fut, ha az asset-aktiválás elbukik.

### 5.3 A döntés helye EGY, és az nem ebben a körben születik

A pipeline **nem** hoz saját küszöböt: `StrumPrediction`-t épít, és a
`decision` getterét kérdezi. A `0.05` küszöb, a margó képlete és az
inkluzivitás az ADR 0505 D4 szerződése, ebben a körben **érintetlen** — a fájl
nincs az `allowed_paths`-on, tehát a szétcsúszás gépileg lehetetlen.

### 5.4 Egy eseményre egy végleges irány

Ha egy eseményre már `confirmed` irány született, ugyanaz az esemény nem válthat
a másik irányra. Az `uncertain` nem „később majd eldől" — a UI szempontjából
végleges semleges állapot.

### 5.5 A küszöb MÉRT — és ahol nincs mérés, ott az hiányként van dokumentálva

A `docs/eval/recognition-direction-abstention.md` rögzíti (a) a szállított
`0.05` forrását (ADR 0505 D4), (b) hogy a coverage/accuracy pár a jelen fából
**nem olvasható ki**, és pontosan mely mérés hiányzik
(`evaluation/recognition/baseline_manifest.json` → `calibration: not-measured`),
(c) a lefuttatandó parancsot (`ml/honest_eval.py` held-out fold) és (d) a mért
tényt, hogy a CRNN `calibrate()` 0,55 alá nem megy, tehát a `0,45`-ös
felhasználói alapérték ma egyetlen CRNN-pengetést sem utasítana el.
**NEM elfogadható:** kerek szám indoklás nélkül, vagy a hiányzó mérés
elhallgatása.

## 6. Acceptance criteria

1. **Kivezetés (CRNN ág):** `LiveCrnnStrumClassifier.classifyProbs` a
   renormalizált `pDown`/`pUp`-ot (és a 3-osztályos ágon a `pNoStrum`-ot) a
   `StrumClassification`-ön keresztül adja tovább; a `direction` és a
   `confidence` értéke **bájtra ugyanaz marad**, mint ma (a meglévő
   `live_crnn_classifier_test.dart` cellái változatlanul zöldek).
2. **Döntés-hármas a margóra** — a küszöb **alatt / rajta / fölött** mindhárom
   cella kötelező, a szerződés küszöbén (`0.05`, ELUTASÍTÁS-oldalon inkluzív).
   A cellák IEEE-754-ben MÉRT párjai (§0.0b/9, ADR 0512 D6), ahol
   `T = StrumPrediction.uncertainMarginThreshold` (a tesztben OLVASVA, nem
   duplikálva):

   | cella | `(pDown, pUp)` | `directionMargin` | elvárt `decision` |
   |---|---|---|---|
   | alatta | `(0.5245, 0.4755)` | `0.04899999999999999` | `uncertain` |
   | **rajta** | `(2 * T, T)` | `0.05` (egzakt) | `uncertain` |
   | fölötte | `(0.5255, 0.4745)` | `0.05099999999999999` | `confirmed` |

   **TILOS** a „rajta" cellát `(0.525, 0.475)`-tel felírni: az mérve
   `0.050000000000000044` → `confirmed`, tehát a cella a HELYES
   implementáción lenne piros.
3. **`uncertain` → nincs nyíl:** a pipeline által kiadott frame `latestStrum`-ja
   `null` (nincs ↓/↑), és a `latestStrumTime` **nem** lép előre egy
   bizonytalan eseményre.
4. **`confirmed` → változatlan mai viselkedés:** magabiztos pengetésre a
   `direction`, a `confidence` és a `strumSeq` léptetése azonos a mai úttal
   (regressziós cella a `live_pipeline_test.dart`-ban).
5. **Heurisztikus ág:** valószínűség nélküli `StrumEvent`-re a pipeline a mai
   viselkedést adja (van nyíl), és **nem** épít `StrumPrediction`-t kitalált
   valószínűségekből.
6. **A szerződés érintetlen:** `git diff --name-only` a körben **nem**
   tartalmazza a `lib/features/live/domain/recognition/` egyetlen fájlját sem.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A margó-határ elfogadás-oldalon inkluzív (`<`) | 2. pont **„rajta" (`2·T`, `T`)** cellája |
| `uncertain` mellett is beírja a legutóbbi irányt | 3. pont |
| A `latestStrumTime` bizonytalan eseményre is lép | 3. pont második fele |
| A kivezetés elrontja a mai confidence-t | 1. pont (a meglévő CRNN-cellák) |
| A heurisztikus ág kitalált valószínűséget kap | 5. pont |
| A kör „egyszerűbben" átírja a szerződés küszöbét | 6. pont (+ scope-audit) |
| A `confirmed` út viselkedése elmozdul | 4. pont |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/live/strum_direction_abstention_test.dart test/features/live/dsp/live_pipeline_test.dart test/features/live/live_frame_adapter_test.dart test/features/live test/features/audio_analysis
```

Külön processzben futó `format` → `analyze` → célzott tesztek → `architecture`
(AGENTS.md §12). `&&` láncolás tilos (L05/L09). A `test/features/audio_analysis`
azért van benne, mert a `StrumEvent`/`StrumClassification` hívói ott is élnek
(§5.1 additivitási követelmény mérése). CI-dispatch/PR/merge Claude-oldal.

### 7.1 Falszifikációs cella

A §10-ben dokumentáld: a döntés-lekérdezés ideiglenes megkerülésével (a
`StrumPrediction.decision` helyett közvetlen `Strum`-építés) a 3. acceptance-pont
cellája **PIROS**, visszaállítva **ZÖLD**.

## 8. Implementációs sorrend

1. `pDown`/`pUp` additív kivezetése a CRNN ágon (classifier → analyzer),
   a meglévő cellák zölden tartásával.
2. A `docs/eval/…` megírása (a szállított küszöb forrása + a HIÁNYZÓ mérés).
3. `StrumPrediction` építése a `live_pipeline.dart`-ban, a `decision`
   érvényesítése a frame felé.
4. Az új `strum_direction_abstention_test.dart` mérce-mátrixa.

## 9. Kockázatok

- **Coverage-esés:** a döntés csökkenti a megjelenített nyilak számát; ez
  SZÁNDÉKOS, de a §10-ben számszerűen jelenteni kell (hány `uncertain` a
  meglévő fixture-öntesteken).
- **A szerződés átírásának kísértése** (a `0.05` „túl szigorú"): tilos zóna,
  `stopped`; a küszöb-változtatás MÉRT kalibrációs kör dolga (§0.0/3.).
- **Az additivitás megsértése:** a `StrumEvent` ~20 hívója némán törik — ezt a
  §7 `test/features/audio_analysis` sávja méri.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
