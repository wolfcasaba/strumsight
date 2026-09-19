# Epic 14 (Chapter 14) — befejezési terv, R20–R42

- **Készült:** 2026-09-09, `claude/laptop-apk-debug-prompt-kys4oa` @ `93f70de`
- **Szerző:** Claude (Opus 5), tervezői szerep (ADR 0055)
- **Bemenet:** `docs/sdd/14-chapter-14-recognition-ui-recovery.md` §7 (kapuk),
  §8 (sorrend), Kör 20–42; `docs/rounds/e14-r01…r19`; `HANDOFF.md`;
  a fa MÉRT állapota (lásd §1).
- **Cél:** megmondani körönként, mi készíthető el **kód-szinten ebben a
  konténerben**, mi készült el MÁS epicben, és mi az, amihez **adat, x86 gép
  vagy ember** kell. Nem terv-kozmetika: ahol nincs mérés, ott a kör
  `PARTIAL` vagy `NOT-POSSIBLE-HERE` marad.

---

## 0. A környezet mért korlátai (ez a terv alapja)

| Képesség | Állapot |
|---|---|
| Flutter / Dart SDK | **NINCS** — egyetlen sor sem fordul le; a `dart` MCP szerver `ENOENT`. |
| `flutter analyze` / `test` / golden | **CSAK CI** (`full-gate.yml`, `build-apk.yml`) — a session VÉGÉN egyszer. |
| Python 3.11 | van, **numpy NINCS** (`ModuleNotFoundError`), TF sincs → `ml/**` írható, **futtathatatlan**. |
| Hálózat | csak GitHub (MCP) — se dataset, se checkpoint, se pub-cache letöltés. |
| Android eszköz / GPU / mikrofon | nincs. |
| **Tilos zóna** | `tools/**`, `tool/**`, `.github/**`, `.ai/**`, `schemas/**`, `.claude/**` |

Két következmény, amit végig komolyan kell venni:

1. **Nem adható új CI-workflow és nem adható új CLI belépési pont.**
   A `tool/recognition_evaluate.dart`, `tool/benchmarks/**`, `tool/release/*.py`
   NEM bővíthető. Minden új logika `lib/**`-be (dart:io-mentesen) és `test/**`-be
   kerül; a CLI-bekötés a felhasználó külön köre.
2. **A meglévő tanító-workflow-k viszont HASZNÁLHATÓK, ahogy vannak:**
   - `ml-train.yml` — `workflow_dispatch`, egyetlen bemenet: `sections`
     (`ml/honest_eval.py::SECTIONS` = threeway, logo, logo_aug, threeway_aug,
     bootstrap, seeds, **calib**, noreject_fast, noreject). Új strum-mérés →
     **új SECTION az `ml/honest_eval.py`-ban**, nem új script.
   - `chord-train.yml` — `workflow_dispatch` **és push a `main`-re, ha
     `ml/chords/**` változik**. Klangio (pinned SHA) + **GuitarSet** (Zenodo,
     valódi gitár, valódi akkordcímke, guitarist-szintű LOGO) letöltésével.
     Vagyis a **chord-sáv tanítása/mérése ténylegesen kiváltható innen**, csak
     a *telefon-mikrofonos* diverzitás hiányzik belőle (§7.1: 6 telefonmodell).

---

## 1. Mért repo-állapot, amire a terv épül

**Felismerési mag (E14-R01…R19 leszállítva)**

| Elem | Fájl | Állapot |
|---|---|---|
| Döntési állapotgép | `lib/features/live/domain/recognition/recognition_decision.dart` | 6 állapot + 8 tipizált reject-ok (ADR 0505/0535) ✅ |
| Strum-predikció | `…/strum_prediction.dart` | `decision` SZÁRMAZTATOTT (margin ≤ 0.05 → uncertain); `calibratedConfidence` **null by design** |
| Chord-predikció | `…/chord_prediction.dart` | `decision`/`rejectReason` konstruktor-kapott; `calibratedConfidence` **null** |
| Jelminőség | `…/signal_quality_snapshot.dart`, `engine/quality/**` | 8 állapot, hat tipizált ok (ADR 0535) ✅ |
| Stabilizer | `engine/recognition_stabilizer.dart` | `StabilizerProfile.free(3)/guided(5)` — CSAK label-flicker szűrő, nincs provisional/confirmed chord-profil |
| Kiértékelő fa | `domain/evaluation/recognition_metrics.dart` | onset P/R/F1 tűrésenként, direction macro-F1, chord weighted/macro/N.C., coverage, **ECE**, **Brier**, reliability-bin, per-group bontás (ADR 0509) ✅ |
| Release-kapu | `evaluation/recognition/recognition_release_gate.json` + `domain/evaluation/recognition_release_gate.dart` | 10 küszöb, `ch14-alpha-v1` ✅ |
| Baseline | `evaluation/recognition/baseline_manifest.json` | Klangio, 82 felvétel, 11 767 esemény, `corpusSha256=4880fac…`; **chord accuracy 0,671** (kapu: 0,80) |
| Hard-negatívok | `evaluation/recognition/negative_taxonomy.json` (ADR 0521) ✅ |
| Onset A/B seam | `engine/dsp/onset_detector_variant.dart` (ADR 0524) ✅ |
| Referencia-audit | `docs/eval/reference-model-audit.md` — licenc-alapon konklúzív |
| Joint prototípus | `docs/eval/joint-strum-prototype.md` — **verdict: NO-GO** (ADR 0517) |
| Augmentáció | `ml/augment.py`, `ml/augmentation_manifest.json` (ADR 0525) ✅ |

**Modellek (`assets/ml/model_manifest.json`, sha256-tal)**
`strum_crnn.bin`, `strum_crnn_live.bin`, `strum_crnn_live_3c.bin` (down/up/no-strum,
15×128 log-mel), `chord_crnn.bin` (**CCRN, 100×144 CQT, 25 osztály: N.C. + 12 dúr +
12 moll**).

**Kritikus mért lelet: a `chord_crnn.bin` a Live-ban NEM fut.**
Egyetlen betöltője a `lib/features/analyze/providers/analyze_providers.dart`
(`rootBundle.load('assets/ml/chord_crnn.bin')` → `ml_chord_decoder.dart`).
A Live izolátum csak a **strum** súlyokat kapja meg
(`real_strum_engine.dart::_liveCrnnWeights`, `strum_crnn_live_3c` → `_live` fallback).
A Live akkordútja végig NNLS-chroma → `ChordDictionary` → `ViterbiChordDecoder`.
Ez pontosan a Ch14 §4.5 állítása, ma is igaz.

**Kritikus mért lelet: a shadow-mód CSAK zászló.**
`recognitionShadowModeEnabled` és `recognitionRecoveryEnabled`
(`lib/app/config/feature_flags.dart`, `core/feature_flags/feature_flag_registry.dart`)
**egyetlen fogyasztóval sem rendelkezik** a `lib/**`-ben — a `grep` csak a
definíciót és a teszteket találja. Shadow-plumbing tehát **nincs**, meg kell írni.

**Kritikus mért lelet: kalibráció van, de in-sample és eldugva.**
`engine/ml/live_crnn_classifier.dart::calibrate` piecewise-lineáris knot-listát
tartalmaz (`0,7→0,58 … 0,9825→0,86`), amit — az `ml/honest_eval.py::section_calib`
saját fejléce szerint — **ugyanazon a foldon fittelték, amin az accuracy-t
jelentették** (in-sample). Ez a szám ma a `Strum.confidence`-be megy, viszont a
`StrumPrediction.calibratedConfidence` `null`. Két igazságforrás, egyik sem
verziózott a modellhez kötve.

**Kritikus mért lelet: az expected-chord prior FELÜLÍRHATJA az audiót.**
`viterbi_chord_decoder.dart` 96./108. sor: `_delta[s] = sim[s] + (s == _expectedIdx ? expectedPrior : 0)`
— additív bias a trellis-ben, nem tie-breaker. Beállítói:
`practice_session_controller` → `live_practice_observation_gateway` → `real_strum_engine`
→ `live_pipeline.setExpectedChord`, illetve `learn_screen`. A Live képernyő
belépéskor `null`-ozza (`live_screen.dart:93`) — **konvenció, nem gépi őr**.
`RecognitionMode` típus nincs a fán.

**Kritikus mért lelet: a gyakorlás akkord-konfidenciája HAZUDIK.**
`live_practice_observation_gateway.dart:249`:
`ChordObservation(at: at, label: chordLabel, confidence: 1.0)` — a saját
kommentje mondja ki, hogy azért 1.0, mert a `LiveFrame`-nek nincs
chord-confidence mezője. A `LiveFrame` viszont MA MÁR hordozza a
`chordDecision`/`chordRejectReason` mezőt (ADR 0516). Ezen kívül az
`uncertain` szó a teljes `lib/features/practice/**`-ben nem fordul elő.

**H3 / L2 (HANDOFF, nem javítva):** a chord-latch nem húz be Karplus–Strong
szintetikus jelen. A mért gyanúsítottak most már névvel:
`chord_matcher.dart:99–100` — `margin = (best-second)/best`,
`confidence = best*(0.5 + 2*margin)`; közel egyforma két legjobb template esetén
`margin≈0` → `conf ≈ 0,5·best`, ami a `chordConfRise = 0,54` alatt marad, tehát a
`_applyChordConfEma` sosem latchel.

**UI (E13/E15/E16/E17 leszállítva)**

| Ch14 kör-igény | Mit szállított már el más epic |
|---|---|
| Chapter 13 a repóban | `docs/sdd/13-chapter-13-ui-ux-design-system.md` + `lib/core/design_system/{foundations,themes,motion,icons,accessibility,components,layouts}`; E13-R02…R07 |
| Adaptív shell | `lib/app/home_shell.dart` (`SsAdaptiveDestination` × 5: Today/Practice/Songs/Coach/Profile, `showCoachDestination`), `lib/app/routing/adaptive_shell_routes.dart` (11 legacy redirect, `isStageRoute`) — E13-R08 (ADR 0275), E15-R02 (ADR 0467), E16-R06, E17-R01 (ADR 0508) |
| Today hub | `lib/features/today/**` — E13-R17 + audit-L1 (egyetlen elsődleges CTA → `/practice/setup?id=`) |
| Live Stage | `lib/features/live/screens/live_screen.dart` `SsStageScaffold`-on + `widgets/{confidence_pill,uncertainty_reason_banner,live_status_bar,chord_timeline}` — E13-R18, E14-R13, E17-R15 |
| Gyakorlás-eredmény | `practice_result_screen.dart`: coaching-kódok, „Practice again", Speed Builder, history — E02-R18, E13-R22 |
| Akadálymentesség | `test/accessibility/{tap_target,semantics_contract,screen_reader_copy,release_flow_*}`, `docs/accessibility/{release-audit.md,known-exceptions.yaml}` (gépi registry-őr), `test/ui/goldens/e13_r36_variant_matrix_test.dart` (compact 412×915 / landscape 915×412 / medium 700×1000 / expanded 1024×1366 × textScale 1,0/2,0), `SsMotionScope.reduceMotionOf` — E12-R20, E13-R14/R36 |

**Telemetria / privacy (R41 kiindulás)**
`lib/core/telemetry/{telemetry_event,telemetry_redactor,telemetry_sink}.dart` —
`ConsentGatedTelemetrySink` KÉSZ, de a saját doksija mondja ki: **„no
telemetry-consent switch exists on the tree today"**, és **nincs transport**.
Van `privacy_center_screen.dart`, `lab_consent.dart`, `test/privacy/consent_enforcement_test.dart`,
`test/support/fake_network_guard.dart`, `docs/release/**` (kill-switches, rollout-decision,
beta-findings, rollback runbook + `tool/release/verify_rollback.py`).

---

## 2. Körönkénti státusz és szállítható tartalom

Jelölés: **DONE-ELSEWHERE** · **CODE** (itt kódolható) · **PARTIAL** (a
mechanizmus itt, a szám nem) · **BLOCKED** (adat/x86/ember kell).

### R20 — Strum tanítás grouped holdouttal — **BLOCKED (+ CODE: repro-szerződés)**

- **Miért blocked:** nincs numpy/TF, nincs dataset, nincs hálózat. A §7.1
  minimum (8 gitáros / 6 telefon / 4 gitár) **egyetlen elérhető korpuszban sem
  teljesül**: a Klangio 82 felvétel / 3 gitáros, egy rögzítési elrendezés.
  A grouped holdout eszköz/gitár szerint tehát ma **nem is definiálható**.
- **Itt megírható:** (a) új `SECTION` az `ml/honest_eval.py`-ban a
  grouped-holdout futáshoz + a hozzá tartozó `ml/`-oldali pytest (futtatás nélkül);
  (b) **training-run manifest** szerződés (`ml/model_card.json` mellé:
  config, seed, dependency lock hash, git SHA, dataset hash, metrikák) és a
  `ml/make_model_card.py` bővítése; (c) **`assets/ml/`-őr teszt**:
  minden `model_manifest.json`-beli modellhez KÖTELEZŐ model card + gate-rekord,
  különben piros („a modell nem kerül app assetbe gate nélkül").
- **Teszttel rögzíthető:** a manifest/model-card teljessége, a
  „nincs asset gate nélkül" invariáns, a split-diszjunktság ellenőrző logikája.
- **Méréshez kell:** `gh workflow run ml-train.yml -f sections="<új section>"`
  és — a §7.1-hez — **a felhasználó valós felvételei** 8 gitárostól / 6 telefonról.

### R21 — Strum konfidencia-kalibráció és selective prediction — **PARTIAL**

- **Itt megírható:** `lib/features/live/domain/recognition/strum_calibration_profile.dart`
  — verziózott, **modelId+sha-hoz kötött** profil (temperature · Platt ·
  isotonic/piecewise), a `live_crnn_classifier.dart::calibrate` mai knot-listájával
  mint `legacy-in-sample-v0` bemenettel, kimondva, hogy **in-sample** (ismert
  korlát, nem kapu); `StrumPrediction.calibratedConfidence` ebből a profilból;
  risk–coverage görbe + „92% accepted accuracy melletti coverage-maximalizálás"
  szelektor tiszta függvényként a `domain/evaluation/`-ban (a meglévő ECE/Brier/
  reliability-bin fa MELLÉ, nem helyette).
- **Teszttel rögzíthető:** monotonitás, `0..1` tartomány, profil↔modell kötés
  (rossz sha → fail-closed, nem néma fallback), risk–coverage szelektor
  determinizmusa, „degradált jel → nő az abstention, nem a confidence".
- **Méréshez kell:** ECE/Brier javulás, subgroup accepted-accuracy/coverage kapu
  → `ml-train.yml` `calib` section (kibővítve) + valós holdout.

### R22 — Mobil distillation, quantization, performance-kapu — **BLOCKED**

- **Miért:** low/mid/high tier Android p50/p95, memória-csúcs, thermal throttling
  — eszköz nélkül nincs értelmes szám; a Dart inferencia-út nem is kvantált.
- **Itt megírható (szűken):** a modell **load/unload életciklus** biztonságossá
  tétele és tesztje (izolátum-leállás → súlyok elengedése), valamint a
  „low tier → legacy fallback explicit `RecognitionRuntimeInfo`-val" ág.
  A perf-budget rekord sajnos `tool/benchmarks/**`-ben él → **tilos zóna**,
  tehát a budget-összehasonlítás CLI-ja nem bővíthető.
- **Méréshez kell:** valós telefonok; `build-apk.yml`/`lab-apk.yml` APK + kézi mérés.

### R23 — Strum shadow mode az alkalmazásban — **CODE** ✅ (a legnagyobb tiszta nyereség)

- **Itt megírható:** `RecognitionShadowObserver` seam a `live_pipeline`-ban
  (egyetlen hívási pont, a MEGLÉVŐ log-mel frontendből — nincs második FFT);
  `lib/features/live/data/shadow/**`: körkörös metrics-buffer (latency,
  disagreement, accepted/rejected, quality-state), export a Lab-panelbe;
  `recognitionShadowModeEnabled` **valódi fogyasztóval**.
- **Teszttel rögzíthető:** flag OFF → **nulla extra inferencia** (hívásszámláló),
  a shadow-kimenet SOHA nem ér el `LiveFrame`-et/score-t (gépi őr),
  a disagreement-report determinisztikus ugyanarra a PCM-re, a buffer korlátos
  (nem nő 10 perces szimulált folyamon).
- **Méréshez kell:** a valós 10 perces A/B memória-mérés eszközön.

### R24 — Strum release gate és kontrollált rollout — **PARTIAL**

- **Itt megírható:** rollout-fokozat típus (`internalAlpha → optInBeta → percentage`)
  + a `recognition_release_gate.json` fail-closed kötése a fokozathoz;
  rollback-kapcsoló (asset-visszaváltás új release nélkül, ha a manifest engedi,
  különben dokumentált app-rollback terv); model card + known limitations sablon.
- **Teszttel rögzíthető:** fail-closed viselkedés (hiányzó metrika = FAIL, nem
  „nincs adat = PASS"), a legacy modell egy release-ig elérhető marad.
- **Méréshez kell:** minden kapu PASS-a, subgroup-regresszió hiánya, rollback-gyakorlat.

### R25 — Kiegyensúlyozott chord corpus — **PARTIAL**

- **Itt megírható:** korpusz-**manifest szerződés** (a `baseline_manifest_schema.json`
  mintájára, kézi validátorral — ADR 0354 D8 precedens): kötelező `voicing`
  (open/barre/alt), `capo`, `pick|finger`, `loudness`, `room`, `distance`,
  `guitar`, `player`, `device`; **minimum-support validátor** osztályonként;
  grouped-split diszjunktság-ellenőrző; N.C./hard-negatív arány riport.
  Determinisztikus **szintetikus smoke-korpusz** a validátor hajtásához
  (`test/support/synth.dart::chordSignal` bővítése) — kizárólag a validátor
  tesztelésére, **soha nem ground truthként** (Ch14 §12/2).
- **Reális bővítés adat felé:** a `chord-train.yml` már letölti a **GuitarSet**-et
  (valós gitár, valódi akkordcímke, guitarist-szintű LOGO) → az osztályonkénti
  minimum-support és a grouped split ott TÉNYLEG mérhető; a `ml/chords/**` push
  a `main`-re magától indítja a workflow-t.
- **Amit a GuitarSet NEM ad:** telefon-mikrofon, szoba/távolság, capo, pick/finger
  variáció → a §7.1 corpus **csak a felhasználó felvételeivel** teljesíthető.

### R26 — A szállított Chord CRNN élő shadow bekötése — **CODE** ✅

- **Itt megírható:** `chord_crnn.bin` betöltése a fő izolátumon (mint a strumnál),
  bájtok átadása a DSP izolátumnak, **manifest-integritás** (`model_manifest.json`
  sha256 ellenőrzése a ténylegesen beolvasott bájtokon); streaming-window adapter
  a meglévő `engine/dsp/cqt_extractor.dart`-ra (100×144 ablak, hop-illesztés);
  a kimenet **kizárólag** az R23 shadow-bufferbe; `RecognitionRuntimeInfo` bővítése
  `chordModelId`/`chordModelSha256`/`chordFallbackReason` mezőkkel (fail-visible).
- **Teszttel rögzíthető:** asset-paritás (a meglévő `chord_crnn_parity_test`
  mintájára), élő wiring-teszt, shadow OFF → nulla költség, hibás/csonka asset →
  tipizált `FallbackReason`, nem néma no-op.
- **Méréshez kell:** latency/memória riport eszközön; az NNLS↔CRNN↔ground-truth
  időben illesztett egyezés valós korpuszon.

### R27 — NNLS vs CRNN vs hybrid — **PARTIAL**

- **Itt megírható:** a **hybrid kombinátor tiszta függvényként** (consensus ·
  confidence-weighted · onset-aligned switch · quality-aware fallback), teljesen
  determinisztikusan és unit-tesztelve; háromutas riport-renderer (per-label,
  per-condition, failure-cluster) a meglévő `recognition_report_renderer` mellé.
- **Teszttel rögzíthető:** a kombinátor determinizmusa és minden ága; a riport
  alakja; hogy a választás **nem hardkódolt** (a stratégia adat által választható).
- **Méréshez kell:** a három rendszer száma ugyanazon korpuszon → **ADR-döntés
  itt NEM hozható meg** (Ch14 §12/1: „thresholdok vak átírása" tilos).

### R28 — Hybrid chord stabilizer és onset-aligned transition — **CODE** ✅

- **Itt megírható:** `FreeChordProfile` / `GuidedChordProfile` (a mai
  `StabilizerProfile.free/guided` kibővítése: provisional-küszöb, confirmed-küszöb,
  ring-out hold, quality-aware release, csend-timeout); provisional chord halvány
  állapotban gyorsan, confirmed csak küszöb után; **valódi csendben a chord a
  megadott határon belül törlődik**.
- **H3/L2 ide tartozik:** a `chord_matcher.dart:99–100` konfidencia-képlet
  (`best*(0.5+2·margin)`) diagnosztikai kivezetése (`debugChordConfEma`,
  `debugTonalness`, `winSim`, `margin` frame-enként) + determinisztikus,
  frame-szintű teszt a latch rise-határára. **A képlet átírása mérés nélkül
  tilos** — a diagnosztika viszont pont azt teszi mérhetővé, amit a HANDOFF kér.
- **Teszttel rögzíthető:** state-machine property-tesztek (`test/property/`,
  `PROPERTY_SEED`): sustained chord nem villog; csend → törlés N ms-on belül;
  provisional soha nem renderelhető confirmedként.
- **Méréshez kell:** a transition-latency és false-flip **számok** (kapu).

### R29 — Strukturált root + quality fej, class balancing — **BLOCKED**

- **Miért:** kutatási tanítás. Az `ml/chords/**` (dataset, augment, train_chord,
  labels, cqt, guitarset) **írható itt**, de nem futtatható.
- **Itt megírható:** a 12-root + quality + N.C./unknown fej, reweighted/focal loss,
  balanced sampling kódja + `ml/chords/test_*.py` cellák; a `chord-train.yml`
  a `main`-re push-ra magától lefuttatja.
- **Méréshez kell:** `gh workflow run chord-train.yml` (vagy `ml/chords/**` push),
  majd per-class recall összevetés → go/no-go.

### R30 — Expected chord prior szigorú izolációja — **CODE** ✅ (a legfontosabb tisztán kódolható kör)

- **Itt megírható:** `RecognitionMode { free, guided, lab }` a
  `domain/recognition/`-ban; a mód a motor **konstrukciós** paramétere, nem
  futásidejű setter; `free` alatt a `setExpectedChord` **hatástalan a
  típusrendszer szintjén** (a hint-út a guided motorra szűkül); guided alatt a
  prior **tie-breaker-re korlátozva** (felső korlát, ami nem képes egy tiszta
  audio-győztest megfordítani) vagy explicit scorer-input; a mód **minden
  exportban** rögzül (`RecognitionRuntimeInfo` + evaluation manifest:
  `audioOnly` vs `guidedPrior` metrika külön).
- **Teszttel rögzíthető (mind a négy elfogadási feltétel):**
  free-mód **bit-paritás** prior nélkül / SZÁNDÉKOSAN ROSSZ priorral (property,
  randomizált chroma-folyam); guided „wrong chord" eset **nem javul automatikusan
  helyesre**; minden export hordozza a mode-ot; leakage-őr az evaluation úton.
- **Méréshez kell:** semmi. Ez a kör **teljes egészében itt zárható**.

### R31 — Quality-aware preprocessing és device adaptation — **PARTIAL**

- **Itt megírható:** `LivePreprocessingConfig` (DC-eltávolítás, high-pass,
  loudness-normalizálás, opcionális noise-suppression) a
  `lib/features/audio_analysis/engine/preprocessing/preprocessing_config.dart`
  mintájára, **egyetlen zászlóval teljesen kikapcsolható** (rollback);
  device-profil, ami **csak technikai audio-route adatot** tárol;
  „degradált minőség → nő az abstention, nem a confidence" gépi őr.
- **Teszttel rögzíthető:** kikapcsolt állapotban **bájtazonos** jel (paritás-teszt);
  a preprocessing nem tolja el az onset-időt (szintetikus attack, tűréssel);
  a degradált→abstention irány.
- **Méréshez kell:** **legalább 5 telefonon** mért A/B; AGC-detektálás valós
  eszközön — ez ember + hardver.

### R32 — Chord kalibráció, unknown/open-set, selective prediction — **PARTIAL**

- **Itt megírható:** `ChordCalibrationProfile` (modelId-hoz kötve, mint R21);
  `ChordPrediction.calibratedConfidence` ebből; **open-set döntés stratégia-seamként**
  (energy · entropy · margin · külön head) — a stratégia adat által választható,
  nem hardkódolt; a `N.C.` és az **„Ismeretlen akkord"** UI-állapot **szétválasztása**
  (ARB-kulcsok en/hu, külön szemantika).
- **Teszttel rögzíthető:** a két állapot sosem esik egybe; a nem támogatott
  akkord (sus7/add9) `unknown`-ra megy, nem a legközelebbi maj/min-re
  (szintetikus chroma-fixtúrákkal); reliability-diagram renderelése.
- **Méréshez kell:** per-class minimum recall, accepted accuracy/coverage,
  hard-negatív false-accept ráta → korpusz + `chord-train.yml`.

### R33 — Chord release gate és rollout — **PARTIAL**

- **Itt megírható:** új sorok a `recognition_release_gate.json`-ban
  (leggyengébb támogatott chord recall ≥ 0,55; confirmed accepted accuracy ≥ 0,88;
  chord transition p50 ≤ 350 ms; false-confident ≤ 2/perc) + **külön threshold
  profile free/guided módra**; a legacy NNLS út egy release-ig megmarad;
  model card a támogatott vocabularyval (a `model_manifest.json` 25 osztálya).
- **Teszttel rögzíthető:** a kapu fail-closed; a két profil nem keveredik;
  a model card ↔ manifest osztálylista egyezése (gépi tükör).
- **Méréshez kell:** a PASS maga + device matrix + rollback-gyakorlat.

### R34 — Chapter 13 repositoryba emelése — **DONE-ELSEWHERE** ✅

- **Bizonyíték:** `docs/sdd/13-chapter-13-ui-ux-design-system.md` a fán;
  `lib/core/design_system/{foundations,themes,motion,icons,accessibility,components,layouts,documentation}`;
  körök: `docs/rounds/e13-r02-design-system-foundation.md`,
  `e13-r03-semantic-colors-and-themes.md`, `e13-r04-typography-and-text-scale.md`,
  `e13-r05-spacing-and-surfaces.md`, `e13-r06-motion-and-reduced-motion.md`,
  `e13-r07-iconography-and-guitar-glyphs.md`, `e13-r14-accessibility-toolkit.md`,
  `e13-r36-visual-regression-and-closure.md`; theme-goldenek + variant-matrix;
  `docs/ui/chapter-13-completion-report.md`.
- **Az „SDD index + traceability" feltétel MÉRVE TELJESÜL:** `docs/sdd/00-index.md`
  27. sor (Ch13, 36/36 done) és a `06-requirements-traceability-matrix.md`
  **E13-R02…R36 összes sora**. Egyetlen apró hiba: az E13-R02 sor egy már
  nem létező fájlra mutat (`docs/sdd/13-ui-ux-design-system.md` — a valódi név
  `13-chapter-13-ui-ux-design-system.md`). Egysoros link-javítás, PKG-C.

### R35 — Új adaptív app shell — **DONE-ELSEWHERE, egy nyitott ponttal** ⚠️

- **Bizonyíték:** `docs/rounds/e13-r08-adaptive-scaffold-and-navigation.md` (ADR 0275),
  `e15-r02-adaptive-shell-default-and-overflow-fixes.md` (ADR 0467),
  `e16-r06-shell-backbone-navigation-hotfix.md`, `e17-r01-…` (ADR 0508, `entryLocationFor`).
  Today/Practice/Songs/Coach/Profile megvan; 11 legacy route redirectként él;
  `showCoachDestination` gátolja a no-op Coach gombot; `isStageRoute` védi a
  mikrofon-életciklust; a variant-matrix golden lefedi a compact/landscape/
  medium/expanded + 200% text esetet; `test/app/placeholder_wiring_test.dart`
  partíció-őre tiltja a redirect-loopot és a nem elért képernyőt.
- **NYITOTT:** `feature_flags.dart:138` — `adaptiveShellEnabled: nonProd`, tehát
  **productionben még a régi Live-belépő él**. Ez szándékos (Ch12 Kör 28 GA-döntés),
  de a Ch14 §13 DoD („Az app shell Today/…/Profile struktúrát HASZNÁL") csak a
  flip után pipálható. **Emberi GA-döntés, nem kódfeladat.**

### R36 — Today és „10 perces hasznos gyakorlás" flow — **PARTIAL (CODE)**

- **Kész:** `TodayHubScreen` egy elsődleges CTA-val (audit L1), streak/napi cél,
  determinisztikus ajánlás AI nélkül, `TodayPlanSnapshot` empty/loading/error
  állapotokkal, `practiceCatalogProvider` const-lookup; új user 2 tapon belül indít.
- **HIÁNYZIK (itt kódolható):** a nevesített **10 perces LÁNC**:
  `hangolás → ritmus/akkord gyakorlat → rövid eredmény` egyetlen vezetett
  folyamként. Ma a CTA a `/practice/setup?id=`-re megy; a tuner külön sziget
  (`/practice/tuner`). Kell: egy `TenMinuteFlow` állapotgép (lépések, továbblépés,
  megszakítás, folytatás), a Today-kártya CTA-ja rá, és a lépések végén a
  meglévő `practice_result_screen`.
- **Teszttel rögzíthető:** 2-tap indítás, minden CTA valós route-ra mutat
  (a meglévő `placeholder_wiring` őr kiterjesztése), offline `fake_network_guard`
  zöld, minden kártyának van empty/loading/error/degraded ága.

### R37 — Live Stage V2 teljes képernyő — **PARTIAL (CODE)**

- **Kész:** `SsStageScaffold`, `confidence_pill`, `uncertainty_reason_banner`
  (ADR 0520/0535 hat oka), `live_status_bar`, `chord_timeline`, Lab-panel
  csak Lab módban, mikrofon-engedély banner (2. hullám).
- **HIÁNYZIK (itt kódolható):** (1) a **három mód** — Free Play / Guided Pattern /
  Accuracy Check — mint valódi Live-mód (ma nincs mód-fogalom a képernyőn),
  az R30 `RecognitionMode`-jára ültetve; (2) expected target **csak** Guided-ban;
  (3) history opcionális bottom sheet (ma fix timeline); (4) a `newLiveStageEnabled`
  zászlónak **nincs fogyasztója** — ez lesz az; (5) landscape stage-layout
  2 méteres olvashatósággal (tipográfia-skála a `SsTypography`-ból).
- **Teszttel rögzíthető:** „false confident state" UI-teszttel tiltva (uncertain
  soha nem renderelődik nyílként/akkordként); direction- és chord-bizonytalanság
  **külön** szemantikával; tap-target ≥48×48 és kontraszt (meglévő őrök);
  új golden-cellák a variant-matrixban.
- **Méréshez kell:** a 10 perces valós eszközös session (overflow/jank/mic-leak).

### R38 — Guided practice target + correction loop — **PARTIAL (CODE)** ⚠️ *igazságossági hiba a fán*

- **Kész:** Practice Engine V2, coaching-kódok
  (`practiceInsightDirectionError`, `…ChordError`, `…ChordPairProblem`, …),
  „Practice again", Speed Builder, history, `chord_pair_stats.dart`.
- **HIÁNYZIK (itt kódolható), sorrendben fontosság szerint:**
  1. **`ChordObservation.confidence = 1.0` hazugság megszüntetése**
     (`live_practice_observation_gateway.dart:249`) — a `LiveFrame` ma már hordozza
     a `chordDecision`-t; az observation vegye át, és az `uncertain`
     megfigyelés **ne számítson hibának** (ma se nem talált, se nem kihagyott:
     a `strumMinConfidence` szűrő némán eldobja).
  2. `PracticeSessionResult` bővítése **recognition coverage + quality**
     mezővel a score MELLETT (nem helyette).
  3. **Egy tapos ismétlés a gyenge szakaszra** (ma a „Practice again" az egészet
     újraindítja) — a `chord_pair_stats`/insight-kódokból már azonosítható a
     leggyengébb szakasz.
- **Teszttel rögzíthető (mind a négy elfogadási feltétel):** a score **nem
  változik** pusztán attól, hogy a modell bizonytalan (property: ugyanaz a
  játék, változó abstention-arány → azonos score); egy tapos újrapróba;
  minden result-action valós route-ra mutat; Practice/Song/Live integrációs teszt.

### R39 — Adaptív, akadálymentességi és kültéri audit — **PARTIAL**

- **Kész:** compact 412 / landscape / medium / expanded × textScale 1,0–2,0
  golden-mátrix; TalkBack-szimulált traversal + fókuszsorrend; „nincs
  csak-színnel közölt állapot" cella; 48×48 tap-target teszt; kontraszt-eszköz;
  `SsMotionScope` reduced-motion; gépi `known-exceptions.yaml` registry;
  nincs orientation lock.
- **HIÁNYZIK (itt kódolható):** (1) **360 px** profil a mátrixba (ma a legkisebb
  412); (2) **grayscale / color-vision** cella; (3) reduced-motion **állítás a
  Live beat-pulse-ra és a feedback-animációra** (ma csak a komponens tudja);
  (4) high-contrast téma cellája a Live/Today képernyőkre.
- **Méréshez kell:** a **valódi kinti fény + 1–2 m olvashatósági checklist
  legalább 3 telefonon** — ez ember, nem teszt.

### R40 — Belső Alpha field study — **BLOCKED (+ CODE: protokoll és registry)**

- **Miért:** 8 tesztelő, több telefon, több gitár, zajos szoba.
- **Itt megírható:** a study-protokoll (`docs/release/alpha-field-study.md`):
  feladatlista (setup / free play / guided pattern / chord changes / noisy room),
  mérendők (task completion, correction usefulness, **false-confident event**,
  perceived trust, crash/jank), consent-szabály (**nyers audio csak külön
  consenttel**, egyébként csak helyi aggregált riport); **gépi találat-registry**
  a `docs/accessibility/known-exceptions.yaml` bevált mintájára (id/owner/
  severity/expiry, fail-closed olvasó teszt), amiben a **false-confident hiba
  kényszerítetten P0/P1**.
- **Méréshez kell:** a felhasználó + 8 gitáros + `lab-apk.yml` build.

### R41 — Opt-in Beta, telemetria és privacy gate — **PARTIAL (CODE, nagyrészt itt)**

- **Itt megírható:** (1) a hiányzó **telemetria-consent kapcsoló** (helyi opt-in,
  Settings/Privacy Center-ben, alapból KI) — a `ConsentGatedTelemetrySink`
  `consentGranted` függvénye végre valódi forrást kap; (2) a **recognition
  quality event** mezői (model version, quality bucket, accepted/rejected count,
  latency, user correction flag) a `telemetry_event.dart`-ban, a
  `telemetry_redactor` szabályaival; (3) **retention / export / deletion** folyam
  a meglévő privacy-center mellé; (4) beta feature flag + **egykapcsolós rollback**.
- **Teszttel rögzíthető (három elfogadási feltételből három):**
  logged-out/offline → **0 hálózati kérés** (`fake_network_guard`, meglévő minta);
  opt-out → azonnal minden telemetria leáll, **és nincs visszamenőleges flush**
  (a sink doksija ezt már kimondja, most gépi cella lesz belőle);
  a beta-rollback egy kapcsolóval.
- **Nem itt:** a privacy review + threat model **PASS** aláírása (emberi döntés),
  és **nyers audio upload SOHA nem alapértelmezett** — ezt a terv nem is építi meg.
- **FONTOS korlát:** a `tool/release/*.py` (verify_beta_profile, verify_rollback)
  **tilos zóna** → a beta-profil gépi ellenőrzése nem bővíthető; a doksi-oldal igen.

### R42 — Program lezárása és production gate — **PARTIAL (doksi itt, PASS nem)**

- **Két MÉRT, ma is hamis állítás, amit ez a kör javít:**
  1. `docs/sdd/00-index.md` **28. sora** azt írja Chapter 14-ről: *„nyitva
     (1/42 done, 18 prepared nem futtatva; **R20–R42 briefjei meg sem íródtak**)"*
     — a `docs/rounds/e14-r01…r19` és a `HANDOFF.md` szerint ez **elavult**.
  2. A `docs/execution/06-requirements-traceability-matrix.md`-ben **egyetlen
     `E14-R*` sor sincs** (mérve: 0 találat), és az E15/E16/E17 sávból is csak
     töredék (E15-R01/02/03/06/07/09/14, E17-R01; E16 egyáltalán nem).
     A Ch14 §13 DoD „traceability friss" pontja emiatt ma **nem teljesül**.
- **Itt megírható:** README / HANDOFF / `docs/sdd/00-index.md` /
  `docs/execution/06-requirements-traceability-matrix.md` (E14-R01…R19 sorok
  visszamenőleges pótlása) / model cards /
  `docs/execution/07-risk-register.md` / release-runbook frissítése;
  a megtévesztő régi UI-screenshotok archiválása; a **megmaradt korlátok** és a
  **támogatott chord vocabulary** (a `model_manifest.json` 25 osztálya) kimondása;
  a production rollout 1% → 5% → 20% → 50% → 100% **stop-conditionökkel**.
- **Nem itt:** „minden release gate PASS és bizonyítékkal linkelt",
  rollback-próba, „nincs nyitott P0/P1" — mindhez mérés és emberi jóváhagyás kell.

---

## 3. Összefoglaló tábla

| Kör | Státusz | Mérés nélkül lezárható? |
|---|---|---|
| R20 | BLOCKED + CODE (repro-szerződés) | nem |
| R21 | PARTIAL | nem |
| R22 | BLOCKED | nem |
| R23 | **CODE** | **igen** (a 10 perces memória-mérés kivételével) |
| R24 | PARTIAL | nem |
| R25 | PARTIAL (manifest + validátor igen, felvétel nem) | nem |
| R26 | **CODE** | **igen** (latency-riport kivételével) |
| R27 | PARTIAL (kombinátor igen, döntés nem) | nem |
| R28 | **CODE** | **igen** (a kapu-számok kivételével) |
| R29 | BLOCKED (kód írható, futás nem) | nem |
| R30 | **CODE** | **IGEN, teljesen** |
| R31 | PARTIAL | nem |
| R32 | PARTIAL | nem |
| R33 | PARTIAL | nem |
| R34 | **DONE-ELSEWHERE** | igen (egy dead link javítása) |
| R35 | DONE-ELSEWHERE + GA-flip nyitva | emberi döntés |
| R36 | PARTIAL (CODE) | **igen** |
| R37 | PARTIAL (CODE) | **igen** (eszközös session kivételével) |
| R38 | PARTIAL (CODE) | **igen** |
| R39 | PARTIAL (CODE) | kültéri checklist nélkül igen |
| R40 | BLOCKED + CODE (protokoll) | nem |
| R41 | PARTIAL (CODE, nagyrészt) | **igen** (privacy-aláírás kivételével) |
| R42 | PARTIAL (doksi) | nem |

**Amit a felhasználónak kell futtatnia:**

```bash
# strum tanítás/kalibráció (x86 CI, TF wheel, Klangio pinned SHA)
gh workflow run ml-train.yml -f sections="logo calib <új grouped section>"

# chord tanítás/kiértékelés (Klangio + GuitarSet; ml/chords/** push is indítja)
gh workflow run chord-train.yml

# teljes Flutter kapu + APK (a session VÉGÉN, EGYSZER)
gh workflow run full-gate.yml --ref <branch>
gh workflow run build-apk.yml --ref <branch>
```

**Amit csak ember tud:** valós gitáros felvételek (8 gitáros / 6 telefon /
4 gitár / 4 szoba — §7.1), 5+ telefonos device-adaptációs A/B (R31),
low/mid/high tier perf-mérés (R22), Alpha field study (R40), kültéri
olvashatósági checklist (R39), privacy review aláírása (R41), GA-flip (R35).

---

## 4. Párhuzamos agent-csomagok, DISZJUNKT fájltulajdonnal

### PKG-A — Felismerési mag: mód-izoláció és chord-stabilizer
**Körök:** R30 (teljes), R28 (mechanizmus + H3 diagnosztika), R31 (2. hullám).
**Kizárólagos tulajdon:**
`lib/features/live/domain/recognition/**` ·
`lib/features/live/engine/dsp/**` ·
`lib/features/live/engine/recognition_stabilizer.dart` ·
`lib/features/live/engine/{strum_engine,real_strum_engine,mock_strum_engine}.dart` ·
`lib/features/live/model/live_frame.dart` ·
**`lib/features/live/public.dart` (barrel — egyetlen tulajdonos)** ·
`test/features/live/{domain,engine}/**` · `test/property/{chord_*,dsp_*}` ·
`docs/rag/chunks/{003,004,012}-*.md` · `docs/rounds/e14-r28*.md`, `e14-r30*.md`, `e14-r31*.md`
**Kötelező extra szállítmány (más csomagok ettől függnek):** a
`RecognitionShadowObserver` **seam** (interfész + egyetlen hívási pont a
`live_pipeline`-ban, alapértelmezetten no-op) — implementációt NEM ír hozzá.

### PKG-B — Mérés, kalibráció, open-set, release-kapu
**Körök:** R21, R24, R25 (manifest+validátor), R27 (kombinátor+riport), R32, R33; R20/R29 `ml/`-oldali repro-szerződés.
**Kizárólagos tulajdon:**
`lib/features/live/domain/evaluation/**` · `lib/features/live/data/evaluation/**` ·
**`evaluation/recognition/**` (benne a `recognition_release_gate.json` — egyetlen tulajdonos)** ·
`ml/**` (honest_eval section, chords, model card, manifest) ·
`test/features/live/evaluation/**` · `test/tooling/**` ·
`docs/eval/**` · `docs/rounds/e14-r2{0,1,4,5,7}*.md`, `e14-r3{2,3}*.md`
**Tilos neki:** `lib/features/live/engine/**`, `…/domain/recognition/**` (PKG-A).
A kalibrációs profil TÍPUSA a `domain/evaluation/`-ban születik; a
`StrumPrediction`/`ChordPrediction` bekötése **PKG-A 2. hullámos** feladata.

### PKG-C — Termék-UI: Today-flow és akadálymentességi hézagok
**Körök:** R36, R39, R34/R35 bizonyíték-audit.
**Kizárólagos tulajdon:**
`lib/features/today/**` · `lib/features/tuner/**` · `lib/features/metronome/**` ·
`test/accessibility/**` · `test/ui/goldens/**` · `test/ui/**` ·
`docs/accessibility/**` · `docs/ui/**` ·
`docs/rounds/e14-r3{4,5,6,9}*.md`
**Megjegyzés:** az E13-R02 sor dead linkje a traceability mátrixban van, amit
**PKG-D birtokol** — a javítást PKG-C a `.pipeline/scratch/docs/pkg-c.md`-n kéri.

### PKG-D — Zászlók, telemetria, privacy, beta, program-zárás
**Körök:** R41, R40 (protokoll+registry), R42 (doksi), R24/R33 rollout-doksi.
**Kizárólagos tulajdon:**
**`lib/app/config/feature_flags.dart` + `lib/core/feature_flags/feature_flag_registry.dart`
(egyetlen tulajdonos — MINDEN csomag zászlóigénye rajta megy át)** ·
`lib/core/telemetry/**` · `lib/features/settings/**` ·
`test/privacy/**` · `test/app/config/**` · `test/core/telemetry/**` ·
`docs/release/**` · `docs/execution/07-risk-register.md` ·
**`docs/execution/06-requirements-traceability-matrix.md`** · `README.md` ·
`docs/rounds/e14-r4{0,1,2}*.md`
**1. hullámos kötelezettség:** a teljes E14 zászlókészletet (shadow-al,
`newLiveStageEnabled` fogyasztóval, chord-shadow, beta opt-in, preprocessing
rollback) **egyben landolja**, mielőtt a 2. hullám indul.

### PKG-E — Shadow-mód és a Chord CRNN élő bekötése
**Körök:** R23, R26, R22 (életciklus-rész). **2. hullám.**
**Kizárólagos tulajdon:**
`lib/features/live/engine/ml/**` · `lib/features/live/data/shadow/**` (új) ·
`lib/features/live/model/recognition_runtime_info.dart` ·
`lib/features/live/widgets/live_lab_panel.dart` ·
`assets/ml/model_manifest.json` ·
`test/features/live/ml/**` · `test/tools/**` ·
`docs/rag/chunks/{015,018}-*.md` · `docs/rounds/e14-r2{2,3,6}*.md`
**Függés:** PKG-A `RecognitionShadowObserver` seam-je; PKG-B riport-típusai;
PKG-D shadow-zászlói. A `live_pipeline.dart`-ot **NEM** módosítja.

### PKG-F — Live Stage V2 és a gyakorlás javító-hurokja
**Körök:** R37, R38. **2. hullám.**
**Kizárólagos tulajdon:**
`lib/features/live/screens/**` · `lib/features/live/widgets/**` (a `live_lab_panel.dart` KIVÉTELÉVEL — az PKG-E-é) ·
`lib/features/live/providers/**` ·
`lib/features/practice/**` · `lib/features/learn/screens/learn_screen.dart` ·
`test/features/practice/**` · `test/features/live/{screens,widgets}/**` · `test/e2e/**` ·
`docs/rounds/e14-r3{7,8}*.md`
**Függés:** PKG-A `RecognitionMode` + chord-profilok; PKG-D `newLiveStageEnabled`.

### Hullámok

```
1. hullám (párhuzamos, nincs közös fájl):
   PKG-A (R30, R28+H3)   PKG-B (R21/R24/R25/R27/R32/R33 + ml/)
   PKG-C (R36, R39, R34/R35 audit)   PKG-D (zászlók, R41, R40, R42)

   integrációs pont: ARB-merge + PKG-A seam + PKG-D zászlók a fán

2. hullám (párhuzamos, az 1.-re épül):
   PKG-E (R23, R26, R22-lifecycle)   PKG-F (R37, R38)
   PKG-A folytatás (R31 preprocessing + a kalibrációs profil bekötése)

   integrációs pont: ARB-merge #2

3. lépés (orchestrátor, egyszer):
   HANDOFF + git-notes + `gh workflow run full-gate.yml` + `build-apk.yml`
```

### Közös fájlok protokollja (kötelező)

| Fájl | Szabály |
|---|---|
| `lib/l10n/app_en.arb`, `app_hu.arb` | **Egyetlen csomag sem írja.** Minden új kulcs a `.pipeline/scratch/l10n/<pkg>.{en,hu}.json` scratch fájlba megy (kulcs + `@`-metaadat + magyar fordítás együtt). Az **orchestrátor** olvasztja be hullámonként EGYSZER, a meglévő szegmens-sorrendet megtartva (`test/l10n/arb_parity_test.dart` + a magyar plural-nyelvtan őr piros lesz, ha nem). |
| `lib/app/config/feature_flags.dart`, `core/feature_flags/feature_flag_registry.dart` | **Csak PKG-D.** Zászlóigény: `.pipeline/scratch/flags/<pkg>.md`, PKG-D landolja az 1. hullámban. |
| `evaluation/recognition/recognition_release_gate.json` | **Csak PKG-B.** Új küszöbigény scratch-en át. |
| `lib/features/live/public.dart` | **Csak PKG-A.** Export-igény: `.pipeline/scratch/barrel/<pkg>.md`. |
| `assets/ml/model_manifest.json` | **Csak PKG-E.** |
| `HANDOFF.md` | **Csak orchestrátor**, a hullám végén. |
| `docs/sdd/00-index.md` | **Csak PKG-D** (R42), a 2. hullám után — a 28. sor Ch14-állapota ma hamis. |
| `docs/adr/**` | Csomagonként **saját** ADR, számfoglalás kötelezően: `python3 tools/round-slots.py reserve-adr --round E14-R<nn>` (a `tools/**` futtatása engedélyezett, szerkesztése nem). |
| `live_pipeline.dart` | **Csak PKG-A.** PKG-E a seam-en keresztül dolgozik. |

### Verifikáció

Lokális gate **nem futtatható** (nincs Dart SDK) — a `tools/round-gate.sh`
ezen a boxon nem mérce. Minden csomag a saját körjelentésében **sorolja fel a
megírt teszt-cellákat és azt, mit BIZONYÍTANAK**, sikeres verifikációt viszont
**tilos állítani** (Ch14 §9/9). Egyetlen mérce a session végén futtatott
`full-gate.yml` + `build-apk.yml`, és a Ch14 végső elfogadási predikátuma
változatlanul a **felhasználó valós gitáros APK-tesztje**.
