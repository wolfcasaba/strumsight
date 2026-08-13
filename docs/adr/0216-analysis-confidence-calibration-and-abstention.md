# ADR 0216 — Analysis confidence, calibration and abstention

- **Státusz:** Elfogadva (E06-R01 pre-flight, 2026-08-11)
- **Kör:** E06-R01 — Analyze V1 baseline, mérés és ADR-ek
- **Implementer motor:** Terra — az ADR-t az orchesztrátor (Claude Sonnet 5)
  írta a pre-flightban (ADR 0055).
- **Epic:** [Chapter 7 — Epic 6: Audio Analysis 2.0](../sdd/07-epic-06-audio-analysis-2.md)
  Kör 1; §19 (Confidence és kalibráció, teljes szakasz), §18.4 (Confidence
  gate a technique-proxyknál), §7.5 (Publikációs szabály)
- **Kontext-ADR-ek:** [0219](0219-analysis-capability-aware-publication.md)
  (a confidence-küszöb a capability-döntés egyik bemenete — a két ADR
  együtt olvasandó)
- **Sorszám-jegyzet:** lásd [ADR 0215](0215-analysis-document-versioning.md)
  fejléce — a teljes hatos blokk 0200–0205-ről 0215–0220-ra tolódott.

## Kontextus

**Mért 2026-08-11-én:**

1. A jelenlegi DSP-pipeline **nyers confidence-t ad tovább kalibráció
   nélkül**: `lib/features/analyze/engine/clip_analyzer.dart:105,135` —
   `confidence: verdicts[i].confidence` és `confidence: s.confidence` —
   a `StrumDirectionClassifier`/detektor verdiktjének nyers score-ja
   közvetlenül az `AnalyzeResult` timeline elemeire kerül, kalibrációs
   verzió vagy küszöb-dokumentáció nélkül. Ez pontosan az az „a modell
   0.87-et adott, tehát 87% valószínűség" minta, amit az SDD explicit tilt.
2. Az SDD Ch7 §19.3 (Kalibráció) szó szerint: „A nyers softmax vagy cosine
   score nem publikálható automatikusan probabilityként." Megköveteli:
   calibration dataset, reliability diagram, expected calibration error,
   threshold-kiválasztás, model/version szerinti kalibráció.
3. §19.2 (Confidence összetevők) nyolc bemenetet sorol: signal quality,
   model confidence, event count, target alignment quality, hypothesis
   agreement, temporal consistency, input capability, calibration result —
   azaz a publikált confidence **nem egyenlő** a nyers modell-kimenettel,
   hanem ezek aggregátuma.
4. §19.6 (Abstention) kimondja a rendszer **jogát és kötelességét** az
   „ezt nem tudtam megbízhatóan megmérni" válaszra — ez jobb, mint egy
   hamis pontszám.
5. Nincs a repóban ma semmilyen **kalibrációs adatkészlet vagy
   reliability-diagram eszköz** (`grep -rn "calibrat" lib/ tool/` a
   `confidence_threshold_provider.dart`-on kívül csak a Practice
   `PracticeMetricReasonCode`/`MetricInsufficientData` „elégtelen adat"
   mintázatot adja vissza — az egy ROKON, de nem azonos koncepció:
   Practice esetén a hiány oka esemény-hiány, nem modell-kalibráció).
6. A `docs/eval/real-audio-dsp-baseline.md` (GOV-06/GOV-06b, E99-R04/R05)
   a **meglévő V1 DSP-t** mérte valós audión — ez az egyetlen létező
   valós-audio referenciapont, amit egy jövőbeli kalibrációs kör
   újrafelhasználhat kiindulási adatkészletként.

## Döntés

1. **Nyers score ≠ publikált confidence.** Minden `AnalysisEvent` és
   `AnalysisMetricResult` publikált `confidence` mezője egy **kalibrált**
   érték, amely egy azonosított kalibrációs verzióhoz (`calibrationVersion`
   vagy a metrika-verzió része, [ADR 0218](0218-analysis-metric-id-and-version-governance.md))
   kötött. A nyers modell-score (softmax/cosine/stb.) Lab módban, `source`
   mezővel megjelölve **kiegészítő** diagnosztikaként megjeleníthető, de
   **sosem** helyettesíti a kalibrált értéket a normál UI-ban (SDD §19.5).
2. **A confidence több forrás aggregátuma**, nem egyetlen modellkimenet
   (SDD §19.2 nyolc komponense). Az aggregációs képlet metrikánként eltérő
   lehet, de a bemenetek forrását a metrika dokumentációja rögzíti — egy
   „varázsszám" súlyozás dokumentáció nélkül nem elfogadható.
3. **Abstention elsőbbséget élvez a hamis pontszámmal szemben.** Ha egy
   metrika confidence-e a kalibrált küszöb alatt marad, vagy a bemenet
   minősége kizárja, a rendszer `unavailable`-t jelent
   ([ADR 0219](0219-analysis-capability-aware-publication.md) publikációs
   szabálya), **nem** egy alacsony, de számszerű értéket.
4. **A kalibráció verziózott és modellhez kötött** (SDD §10.2: a confidence
   kalibráció inkompatibilis változása **major** analyzer-version bumpot
   igényel). Egy modellváltás vagy újrakalibrálás nélkül a régi kalibrációs
   görbe marad érvényben — hallgatólagos újrakalibrálás tilos.
5. **A kalibrációs munka maga NEM ennek a körnek a scope-ja** (docs-only,
   `lib/` diff nulla). Ez az ADR a **szerződést** rögzíti; a tényleges
   kalibrációs dataset/reliability-diagram/threshold-számítás egy jövőbeli
   Epic 6 kör (SDD §29.6-29.7 „Real-audio evaluation"/„Ground truth")
   feladata, a meglévő `docs/eval/real-audio-dsp-baseline.md` korpuszra
   építve.

**NEM elfogadható:** „a modell 0.87-et adott, tehát 87% valószínűség" —
azaz egy nyers softmax/cosine/heurisztikus score közvetlen bemutatása
felhasználó-facing probability-ként; kalibrációs verzió nélküli confidence
mező; egy metrika erőltetett számszerű megjelenítése abstention helyett,
csak azért, hogy az UI-ban ne legyen üres mező.

## Következmények

**E06-R30 (2026-08-13):** E06-R19 megvalósította a resolver szerződését, de valódi kalibrációs dataset nélkül a mérés `identity.v1` marad; EVAL-06 továbbra is PENDING.

- A V2 `AnalysisMetricResult`/`AnalysisEvent` modellek (E06-R02, E06-R19)
  `confidence` mezője a kalibrált értéket hordozza; a nyers score külön,
  Lab-only diagnosztikai mezőbe kerül, ha egyáltalán szükséges.
- A `ConfidenceCalibrationCapabilityResolver` (E06-R19, SDD Kör 19 —
  „Confidence calibration, capability resolver") ennek az ADR-nek a
  szerződését implementálja; ez a kör csak a döntést rögzíti.
- A `docs/manual-testing/analysis-eval-matrix.md` (ez a kör hozza létre)
  PENDING sort kap a kalibrációs dataset/reliability-diagram méréséhez —
  felelős és mérendő szám megnevezve, nem „ellenőrizni kell" placeholder.
- A jelenlegi V1 `clip_analyzer.dart` nyers-confidence-átadása **érintetlen
  marad** — ez a döntés csak a V2 útra vonatkozik
  ([ADR 0220](0220-audio-analysis-v2-parallel-rollout-boundary.md)).

## Elutasított alternatívák

- **A nyers modell-score közvetlen publikálása, „egyelőre".** Elvetve:
  pontosan ez a jelenlegi V1 minta ([Kontextus] 1. pont), amit az SDD §19.3
  kifejezetten kizár a V2 útra — egy „ideiglenes" kivétel a V2 teljes
  epicjében soha nem kerülne sorra javításra (a projekt mért mintája: az
  „ideiglenesen X, majd egy későbbi kör Y" indoklás [ADR 0217](0217-analysis-raw-audio-retention.md)-ben is tiltott ugyanezen okból).
- **Egyetlen globális confidence-küszöb minden metrikára.** Elvetve: az
  SDD §19.2 metrikánként eltérő komponens-súlyozást sugall (pl. a
  `timingAccuracy` esemény-számtól, a `monophonicPitch` bemenet-tisztaságtól
  függ más mértékben) — egy közös küszöb vagy túl megengedő, vagy túl
  szigorú lenne a legtöbb metrikára.
- **Ezt a kört kalibrációs adatkészlet gyűjtésével bővíteni.** Elvetve: a
  kör `ai-router` szerződése `native_gate=false`, `lib/`/`test/` diff nulla —
  egy valódi kalibrációs dataset-gyűjtés kódot és mérést igényelne, ami
  kívül esik a §3 „TILOS" listáján.

## A visszavonás feltétele

Felülvizsgálandó, ha a jövőbeli kalibrációs kör (SDD §29.6-29.7) azt méri,
hogy a nyolc §19.2 komponens valamelyike gyakorlatban nem különböztethető
meg megbízhatóan a többitől (pl. „hypothesis agreement" és „temporal
consistency" mindig együtt mozog) — ekkor a komponens-listát az ADR
felülvizsgálatával, mért indoklással kell szűkíteni, nem hallgatólagosan
összevonni a kódban.
