# ADR 0512 — Az irány-abstention BEKÖTÉSE: a valószínűségek additívan jutnak el a MÁR MERGE-ELT döntésig, a küszöb egyetlen helyen marad

- **Státusz:** Elfogadva
- **Kör:** `E14-R10` (Chapter 14 — Recognition Accuracy & Useful UI Recovery, Kör 10)
- **Dátum:** 2026-09-05
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Kapcsolódó:**
  [ADR 0505](0505-versioned-recognition-frame-contract-and-legacy-adapter.md)
  (a szerződés, amit ez a kör BEKÖT — `StrumPrediction.decision`,
  `uncertainMarginThreshold = 0.05`, ELUTASÍTÁS-oldalon inkluzív; a D5 nevezi
  meg, hogy a bekötés „a later round's job"),
  [ADR 0271](0271-recognition-recovery-program.md)
  (`UNKNOWN > CONFIDENTLY WRONG`),
  [ADR 0355](0355-fail-visible-model-activation-telemetry.md)
  (a CRNN ág a SZÁLLÍTOTT út; a heurisztikus csak fallback),
  [ADR 0249](0249-analysis-evaluation-dataset-governance.md)
  (a kalibrációs minimum, ami miatt a küszöb ma nem mérhető újra)

## Kontextus — a pre-flight MÉRT tényei (2026-09-05, `main @ 39680e1e`)

- **Az előre kiosztott `0362` szám elavult.** A `docs/adr/0362-*.md` nem
  létezik, de a foglaló (`tools/round-slots.py reserve-adr --round E14-R10`) a
  **`0512`** számot adta. Ugyanaz a mintázat, mint az E14-R09-nél (`0361` →
  `0511`) és az E14-R08-nál (`0360` → `0509`): a 2026-08-20-i előre-írt briefek
  ADR-számai azóta tárgytalanok. A foglaló `O_CREAT|O_EXCL` markert ír, ezért ő
  a mérvadó (`tools/tests/test_adr_numbering.py`).

- **A döntésnek nincs termelője.** `grep -rn "StrumPrediction(\|RecognitionFrame("
  lib/` → a saját konstruktoron és a `fromJson`-on kívül **nulla** találat. Az
  ADR 0505 megépítette a szótárat, de a Live út egyetlen frame-je sem megy
  keresztül rajta — a felhasználó ma ugyanúgy magabiztos nyilat kap bizonytalan
  pengetésre, mint a szerződés előtt.

- **A valószínűségek megszületnek és eldobódnak.**
  `lib/features/live/engine/ml/live_crnn_classifier.dart:186-193` —
  `classifyProbs` renormalizálja a down/up tömeget (`pDown`, `pUp`), majd
  KIZÁRÓLAG a `calibrate(max)` értéket adja vissza `confidence`-ként. A
  `StrumClassification` (`strum_direction_classifier.dart:27-44`) és a
  `StrumEvent` (`strum_analyzer.dart:14-24`) egyetlen osztály-valószínűséget sem
  hordoz, a `live_pipeline.dart:196-203` pedig a `StrumEvent`-ből KÖZVETLENÜL
  `Strum`-ot épít, döntési réteg nélkül.

- **A heurisztikus ág confidence-e nem valószínűség.** A
  `HeuristicStrumClassifier` rögzített létrát ad (`0.8 + 0.05*gap` / `0.55` /
  `0.5` / `0.3`). Ennek „inverziója" kitalált `pUp` volna — pontosan az a
  `CONFIDENTLY WRONG`, amit a Chapter 14 meg akar szüntetni.

- **A küszöb ma nem mérhető újra.** Az
  `evaluation/recognition/baseline_manifest.json:310-312` a kalibrációt
  `not-measured`-ként jelöli, kimondott indoklással: nincs confidence-alapigazság
  a korpuszon, és az nem éri el az ADR 0249 §D4 30-per-bin / 300-összes
  minimumát. Bin-enkénti coverage a fában sehol nincs rögzítve.

- **A felhasználói küszöb ma nem kapuz a CRNN ágon.** A `calibrate()`
  knot-listája (`live_crnn_classifier.dart:212-215`) `0,55` alá SOHA nem megy
  (a legalsó knot `(0.50, 0.55)`), a `confidenceThresholdProvider` alapértéke
  `0,45` — a mai alapérték tehát egyetlen CRNN-pengetést sem utasítana el. Ezt
  a `docs/eval/recognition-direction-abstention.md` rögzíti; a bekötés külön kör.

## Döntés

### D1 — A kivezetés SZIGORÚAN ADDITÍV és NULLÁZHATÓ

A `StrumClassification` és a `StrumEvent` új valószínűség-mezői `double?`-ök,
alapértelmezett `null` értékkel. Egyetlen meglévő mező neve, típusa és értéke
sem változik. **Mért ok:** a `StrumEvent`-re 23, a `StrumClassification`-ra 8
fájl hivatkozik (`grep -rln`, `lib/` + `test/`), köztük a kör TILOS zónájában
lévő `lib/features/analyze/engine/clip_analyzer.dart`,
`lib/features/live/engine/ml/strum_crnn.dart`, `test/property/dsp_property_test.dart`
és `test/features/live/dsp/strum_analyzer_suppression_test.dart` — ezeknek
**változtatás nélkül** kell fordulniuk és zölden futniuk.

**Amit ez TILT:** a `confidence` mező újraértelmezését valószínűségként (ADR
0505 D2), és bármely meglévő mező `required`-ből `optional`-ba (vagy fordítva)
mozgatását.

### D2 — A heurisztikus ág valószínűség-mezői `null`-ok, és `null` esetén a mai viselkedés marad

Ha a `StrumEvent` valószínűség-mezői `null`-ok, a `live_pipeline.dart` a MAI
utat futtatja: közvetlen `Strum`-építés, nincs abstention. A kör hatása így a
CRNN ágra korlátozódik — az a szállított út (ADR 0355); a heurisztikus csak az
asset-aktiválás bukásakor fut.

**Amit ez TILT:** a rögzített létra confidence-ének `pDown`/`pUp` párrá
alakítását bármilyen képlettel (`p`, `1-p`, sigmoid, …). Kitalált valószínűség
= kitalált döntés.

### D3 — A döntés helye EGY, és az nem ebben a körben születik

A pipeline **nem** hoz saját küszöböt és nem implementálja újra a margó-képletet:
`StrumPrediction`-t épít, és a `decision` getterét kérdezi. A `0.05`, a
`|pDown − pUp|` képlet és az ELUTASÍTÁS-oldali inkluzivitás az ADR 0505 D4
szerződése. A `lib/features/live/domain/recognition/**` ezért **nincs** az
`allowed_paths`-on: a szétcsúszás gépileg lehetetlen, nem fegyelem kérdése.

**Mért ok (L624, E14-R04 review MAJOR-1):** az előző kör pontosan azért kapott
MAJOR-t, mert a szótár megépült, de a fogyasztó csak az akkordot kapuzta rá. Egy
második küszöb a pipeline-ban ugyanezt a hibaosztályt hozná vissza, csak
fordítva.

### D4 — Egy eseményre egy végleges irány; `uncertain` esetén az idő sem lép

`uncertain` döntésre a frame `latestStrum`-ja `null`, **és** a `latestStrumTime`
nem lép előre. Az `uncertain` nem „később majd eldől" — a UI szempontjából
végleges semleges állapot. Ha egy eseményre már `confirmed` irány született,
ugyanaz az esemény nem válthat a másik irányra.

**Mért ok:** a `_latestStrumTime` a 2 másodperces lejárati ablakot vezérli
(`live_pipeline.dart:282-283`). Ha egy bizonytalan esemény léptetné, egy
korábbi, magabiztos nyíl élettartamát nyújtaná meg — a bizonytalanság így
CSENDBEN erősítené a magabiztos állítást.

### D5 — A küszöböt ez a kör nem változtatja; a hiányzó mérés dokumentált hiány

A `docs/eval/recognition-direction-abstention.md` rögzíti (a) a szállított
`0.05` forrását (ADR 0505 D4), (b) hogy a coverage/accuracy pár a jelen fából
**nem olvasható ki** és pontosan mely mérés hiányzik, (c) a lefuttatandó
parancsot egy KÜLÖN, mért kalibrációs körhöz, (d) a `calibrate()` 0,55-ös alsó
korlátjának következményét a felhasználói küszöbre.

**Amit ez TILT:** kerek szám indoklás nélkül, és a hiányzó mérés elhallgatása.

### D6 — A küszöb-cellák IEEE-754-ben mértek, nem „kerek" tizedesből építettek

A `margin == uncertainMarginThreshold` cellát a tesztnek a konstansból
származtatott, **egzakt** double-párral kell előállítania. **Mérve
(`python3`, 2026-09-05):** `double(0.05) = 0.05000000000000000277…`, ezért

| `(pDown, pUp)` | `|pDown − pUp|` | döntés |
|---|---|---|
| `(0.525, 0.475)` — az „1-re összegző" naiv pár | `0.050000000000000044` | **`confirmed`** |
| `(0.55, 0.50)` | `0.050000000000000044` | **`confirmed`** |
| `(1.0, 0.95)` | `0.050000000000000044` | **`confirmed`** |
| `(2·T, T)` = `(0.1, 0.05)` | `0.05` (egzakt) | **`uncertain`** ✅ |

Az `a + b == 1.0` megkötés mellett a küszöb **egzaktan nem érhető el**: a
`2a − 1 == double(0.05)` egyenlet megoldása (`a = (1 + T)/2`) nem
reprezentálható double-ként. A `(2·T, T)` pár azért egzakt, mert
`double(0.1) == 2 × double(0.05)` bitre igaz.

**Következmény a szerződésre:** a CRNN ág renormalizált párja mindig 1-re
összegez, tehát a küszöb-egyenlőség a VALÓS úton elérhetetlen — a
`margin <= threshold` inkluzivitás gyakorlati hatása a küszöb alatti tartomány.
Ez nem gyengíti a szerződést, de a mérce-cellát a `StrumPrediction.decision`
szintjén kell elhelyezni, nem a pipeline renormalizált bemenetén.

**Amit ez TILT:** a küszöb-cella `0.525`/`0.475` alakú felírását „a 0,050 az
0,050" alapon, és a `uncertainMarginThreshold` értékének duplikálását a
tesztben.

## Következmények

**Pozitív.** A `StrumPrediction.decision` termelőt kap, tehát az ADR 0505
szótára először hat a felhasználóra: bizonytalan pengetésre nincs nyíl. A
Chapter 14 `UNKNOWN > CONFIDENTLY WRONG` szabálya a strum-oldalon futásidőben
érvényesül, nem csak dokumentumban.

**Negatív / ár.** A megjelenített nyilak száma CSÖKKEN — ez szándékos, de a kör
handoffjában számszerűen jelenteni kell. A `StrumClassification`/`StrumEvent`
két nullázható mezővel bővül, ami a heurisztikus ágon örökre `null` marad: a
modell kétféle termelőt szolgál ki egy típussal. Az alternatíva (külön típus a
CRNN ágnak) a 23 hívót érintené — aránytalan.

**Amit ez a döntés TILT (összefoglalva).**

- Új irány-küszöb bevezetését a `live_pipeline.dart`-ban vagy bárhol a
  `domain/recognition/`-ön kívül.
- A heurisztikus ág valószínűség-fabrikálását.
- A `0.05` átírását mért kalibráció és külön ADR nélkül (AGENTS.md §9).
- A `latestStrumTime` léptetését bizonytalan eseményre.
