# E06-R29 — Evaluation harness és confidence calibration

- **Státusz:** PLANNING (pre-flight revízió: 2026-08-13, `origin/main` @ `6ce59b5e`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 29; §19.3, §29.6–29.8
- **Branch:** `codex/e06-r29-evaluation-harness-and-calibration`
- **Előfeltétel:** **E06-R19, E06-R28 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** sonnet-impl

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "evaluation/analysis/manifest_schema.json",
  "evaluation/analysis/README.md",
  "evaluation/analysis/fixtures/ci_manifest.json",
  "lib/features/audio_analysis/domain/evaluation/ground_truth.dart",
  "lib/features/audio_analysis/domain/evaluation/evaluation_report.dart",
  "lib/features/audio_analysis/data/evaluation/evaluation_manifest_parser.dart",
  "lib/features/audio_analysis/data/evaluation/evaluation_runner.dart",
  "lib/features/audio_analysis/data/evaluation/calibration_fitter.dart",
  "lib/features/audio_analysis/engine/confidence/calibration_table.dart",
  "lib/features/audio_analysis/public.dart",
  "tool/audio_analysis_evaluate.dart",
  "test/features/audio_analysis/data/evaluation_manifest_parser_test.dart",
  "test/features/audio_analysis/data/evaluation_runner_test.dart",
  "test/features/audio_analysis/domain/evaluation_report_test.dart",
  "test/tooling/analysis_evaluation_regression_test.dart",
  "docs/adr/0249-analysis-evaluation-dataset-governance.md",
  "docs/baseline/epic-06-analysis-evaluation.md",
  "docs/manual-testing/analysis-eval-matrix.md",
  "docs/rounds/e06-r29-evaluation-harness-and-calibration.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/tooling",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R19/R28 merge.
> **ADR 0249** pre-flightban foglalva. Nézd meg az `evaluation/` könyvtár **mai**
> tartalmát és konvencióit (a repo gyökerében létezik) — az `analysis/`
> alkönyvtár **abba illeszkedik**, nem új mintát vezet be. **H-GATEGUARD:**
> a `.github/workflows/**` és a `tool/ci/**` a **mérce**, amit egy önmagát
> mérő session nem írhat át (ADR 0112/0138,
> `.claude/hooks/protect_factory_files.py`) — ezért a CI-oldali regressziós
> kapu **teszt-oldali** megfelelője készül el itt, és a tényleges CI-lépés
> **ember által engedélyezett governance-körre (`GOV-xx`)** marad.
> PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PLANNING — 2026-08-13, `origin/main` @ `6ce59b5e`.**

1. A batchben kiosztott **0211** nem volt foglalt ADR-szám. A kötelező,
   ütközésmentes `tools/round-slots.py reserve-adr --round E06-R29` a
   **0249** számot adta; a kör kizárólag ezt a számot és a
   `0249-analysis-evaluation-dataset-governance.md` fájlt használja.
2. `find evaluation -maxdepth 3 -type f` ma csak az `evaluation/tutor/`
   struktúrát mutatja; `evaluation/analysis/` még nincs. Ezért az új
   analysis-manifest a meglévő gyökérszintű `evaluation/` konvencióhoz
   illeszkedik, nem feltételez létező analysis-adatot.
3. A tényleges confidence-hívási lánc mért: `CapabilityResolver` alapértelmezett
   `const CalibrationTable.identityV1()` példányt birtokol, és
   `_resolveCapability()` a `CalibrationTable.calibrate()` metódusát hívja.
   A jelenlegi tábla kizárólag `identity.v1`; nincs V2 pipeline-wiring vagy
   repo-beli, címkézett valós-audio dataset. Következmény: a szintetikus
   fixture **nem** igazolhat valódi modellkalibrációt, így nem emelhet
   kalibráció-verziót és nem cserélheti le az identity-táblát önkényes görbére.
   A 300/30 minimum alatt az őszinte, kötelező kimenet `identity.v1` és
   `insufficient calibration data`.
4. A `docs/manual-testing/analysis-eval-matrix.md` létezik és minden valós
   eszközös/audio-evidencia sora ma `PENDING`. A szintetikus esetek által
   ténylegesen mért sorok csak akkor zárhatók le; a valós felvételt igénylő
   sorok PENDING-ek maradnak felelőssel.

Ez a revízió a pre-flight mérését rögzíti; nem bővíti a listát és nem módosít
korábban merge-elt ADR-t.

## 1. Cél

A metrikák pontosságának **mérhető, reprodukálható** evaluation-rendszere:
ground-truth séma, futtatható harness, riportformátum és regressziós küszöbök,
valamint a confidence-kalibráció adatküszöbös, őszinte döntése. A jelen kör
szintetikus fixture-e nem helyettesít címkézett valós felvételt: elégtelen adat
esetén kifejezetten az `identity.v1` marad a kimenet.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- Létezik `evaluation/` könyvtár a repo gyökerében (Epic 2–5 anyagaival), és
  léteznek paritás-fixture-ök (`test/fixtures/*_parity.json`).
- Az Epic 6 eddigi körei **kalibrálatlan** küszöbökkel dolgoznak: az R19
  `CalibrationTable`-je **identity.v1**, az R07/R12/R13/R15/R16/R17/R18
  küszöbei „ideiglenes az R29-ig" jelöléssel élnek.
- A `docs/manual-testing/analysis-eval-matrix.md` (R01 óta) gyűjti a
  PENDING sorokat.
- **Nincs** ground-truth séma, **nincs** evaluation runner, **nincs**
  regressziós küszöb.
- Ezen a boxon **nincs valós felvétel** és nincs Android SDK — a nagy,
  valós-audio eval **manuálisan** futtatható, a CI-ban csak a kis fixture-készlet.

## 3. Scope

**Benne:** `evaluation/analysis/` (manifest-séma, README a licenc- és
adatvédelmi szabályokkal, **kis** CI-fixture-manifest); `GroundTruth` és
`EvaluationReport` domain-típusok; `EvaluationManifestParser`;
`EvaluationRunner` (onset precision/recall/F1, timestamp MAE, chord
frame/segment accuracy, strum direction accuracy, BPM error, beat alignment,
pitch cents error, confidence-kalibráció, szelet-lebontás);
`CalibrationFitter` (megbízhatósági diagram + ECE + küszöbválasztás);
a `CalibrationTable` csak elegendő, címkézett adat esetén cserélhető
verziózott, monoton táblára — a CI-fixture esetén kötelezően `identity.v1`
marad;
`tool/audio_analysis_evaluate.dart`; **teszt-oldali** regressziós kapu;
**ADR 0249**; baseline dokumentum a **futtatott** eredménnyel.

**Kívül — TILOS:** `.github/workflows/**` és `tool/ci/**` bármely
módosítása (H-GATEGUARD); valós felvételek repóba töltése; DSP-paraméter
retune (az eval **javasol**, a retune külön kör); modell-tanítás.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `evaluation/analysis/manifest_schema.json` | ÚJ | ground-truth séma |
| `evaluation/analysis/README.md` | ÚJ | licenc + adatvédelem + futtatás |
| `evaluation/analysis/fixtures/ci_manifest.json` | ÚJ | **kis**, szintetikus CI-készlet |
| `.../domain/evaluation/ground_truth.dart` | ÚJ | annotáció-modell |
| `.../domain/evaluation/evaluation_report.dart` | ÚJ | riport-modell |
| `.../data/evaluation/evaluation_manifest_parser.dart` | ÚJ | parser |
| `.../data/evaluation/evaluation_runner.dart` | ÚJ | metrika-riport |
| `.../data/evaluation/calibration_fitter.dart` | ÚJ | kalibráció |
| `.../engine/confidence/calibration_table.dart` | meglévő | identity → **valódi** tábla |
| `.../public.dart` | meglévő | export |
| `tool/audio_analysis_evaluate.dart` | ÚJ | futtatható harness |
| `test/tooling/analysis_evaluation_regression_test.dart` | ÚJ | teszt-oldali kapu |
| `docs/adr/0249-…md`, `docs/baseline/epic-06-analysis-evaluation.md` | ÚJ | döntés + mért eredmény |
| `docs/manual-testing/analysis-eval-matrix.md` | meglévő | PENDING sorok lezárása/frissítése |

**Tilos zóna:** `.github/**`, `tool/ci/**`, `tools/round-gate.sh`,
`lib/features/live/**`, `lib/features/analyze/**`, `assets/ml/**`,
`lib/features/audio_analysis/engine/metrics/**`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **H-GATEGUARD:** a CI-oldali regressziós lépés **nem** része ennek a
   körnek. A kör a **teszt-oldali** megfelelőt szállítja
   (`test/tooling/analysis_evaluation_regression_test.dart`), a completion
   report pedig **nevesíti** a hátralévő CI-munkát → ember által
   engedélyezett `GOV-xx` kör. Ez **tudatos határ, nem hiány**.
   **NEM elfogadható:** workflow-fájl szerkesztése.
2. **A dataset nem kerül a repóba:** az `evaluation/analysis/` **manifestet**
   és **szintetikus** CI-fixture-t tartalmaz; a valós felvételek külső,
   licencelt tárban élnek, és a README rögzíti a licencet, a hozzáférést és
   az adatvédelmi szabályt. **NEM elfogadható:** valós felvétel commitolása.
3. **Determinisztikus riport:** ugyanaz a manifest + ugyanaz a kód **bájtazonos**
   riportot ad. **NEM elfogadható:** időbélyeg vagy véletlen sorrend a
   riportban.
4. **A kalibráció verziózott, és nem rejti el az identitást:** ha az
   adatmennyiség nem elég a megbízható kalibrációhoz, a tábla **marad**
   `identity.v1`, és a riport ezt **kimondja**. **NEM elfogadható:**
   3 mintából illesztett „kalibráció".
5. **Az eval nem hangol DSP-t:** a riport **javaslatot** ad; a paraméter-
   változtatás külön, mért kör (AGENTS.md §9, a chunkkal együtt).
6. **A regressziós küszöb a baseline-hoz mér:** a teszt-oldali kapu a
   `docs/baseline/epic-06-analysis-evaluation.md`-ben rögzített
   számokhoz hasonlít, dokumentált toleranciával; a küszöb **gyengítése**
   H-GATEGUARD-döntés (ember).
7. **Nincs privát útvonal-szivárgás:** a riport nem tartalmaz abszolút
   fájlútvonalat vagy felhasználónevet.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: Mit tartalmazzon a CI-fixture-készlet?
    blocking: true
    resolution_policy: use_default
    default: >-
      KIZÁRÓLAG szintetikusan generált klipek (a tool szkript állítja elő
      futásidőben, a manifest a generálási paramétereket írja le) —
      így nincs bináris audio a repóban, és a készlet reprodukálható.
      Legalább 12 eset: csend, ismert BPM (60/120), 3/4 és 4/4, két- és
      négyakkordos progresszió, ring-out, clippelt, halk, zajos,
      monofonikus skála, hangváltás.
  - id: OD-02
    question: Mennyi adat kell a kalibrációhoz?
    blocking: true
    resolution_policy: use_default
    default: >-
      binonként legalább 30 megfigyelés ÉS összesen legalább 300 —
      ez alatt a tábla marad identity.v1, és a riport "insufficient
      calibration data" jelölést kap. A szintetikus CI-készlet ezt
      VÁRHATÓAN nem éri el: ez a helyes, őszinte kimenet.
  - id: OD-03
    question: Milyen regressziós tolerancia?
    blocking: true
    resolution_policy: use_default
    default: >-
      onset F1 és chord accuracy: a baseline-tól legfeljebb 2 százalékpont
      ROMLÁS; timestamp MAE és BPM error: legfeljebb 10 % ROMLÁS.
      A javulás sosem bukik. A számok az ADR 0249-ben.
```

## 6. Acceptance criteria

- [ ] **Manifest-parser mátrix — hat cella:** érvényes manifest; hiányzó
      annotáció; ismeretlen mező; érvénytelen időrend (annotáció vége <
      kezdete); duplikált eset-ID; hibás séma-verzió — mind **typed failure**,
      a hívó nem kap crash-t.
- [ ] **Determinisztikus riport:** ugyanaz a manifest kétszer futtatva
      **bájtazonos** riport-JSON-t ad (időbélyeg nélkül).
- [ ] **Metrika-teljesség:** a riport tartalmazza mind a kilenc SDD-metrikát
      (onset P/R/F1, timestamp MAE, chord frame accuracy, chord segment
      accuracy, strum direction accuracy, BPM error, beat alignment,
      pitch cents error, confidence-kalibráció), és **szelet-lebontást**
      (legalább: tempó-sáv, jelminőség-fokozat, mód).
- [ ] **Ismert-válaszú cellák:** legalább **négy** eset, ahol a helyes
      eredmény kézzel levezethető és `python3 -c`-vel ellenőrzött:
      (a) tökéletes detektálás → F1 = **1.0**; (b) minden esemény hiányzik →
      recall = **0.0**, precision **nem értelmezett** (a riport ezt
      `null`-ként jelöli, nem 0-ként); (c) fele hiányzik, semmi extra →
      precision **1.0**, recall **0.5**, F1 **0.666…**; (d) 10 detektált,
      5 helyes, 6 elvárt → precision **0.5**, recall **0.8333…**,
      F1 **0.625**.
- [ ] **Kalibráció-küszöb hármas** (binonként 30): **29 / 30 / 31**
      megfigyelés a legszűkebb binben — a **30**-nál még illeszt (inkluzív),
      a 29-nél `identity.v1` marad, és a riport ezt **kimondja**.
      Az összes-megfigyelés küszöbre (300) külön hármas:
      **299 / 300 / 301**.
- [ ] **ECE számítás:** egy kézzel konstruált, ismert megbízhatósági
      eloszlásra az Expected Calibration Error értéke `python3 -c`-vel
      kiszámolt konkrét szám (|Δ| ≤ 1e−9).
- [ ] **Regressziós kapu:** a teszt-oldali kapu (a) a baseline-nal egyező
      riportra **zöld**; (b) 2.1 százalékpontos onset-F1 romlásra **piros**;
      (c) 1.9 százalékpontos romlásra **zöld**; (d) 11 %-os BPM-error
      romlásra **piros**. Négy cella.
- [ ] **Nincs privát útvonal:** a riport JSON-jában egyetlen abszolút
      útvonal (`/home/`, `C:\`) sem szerepel — property-jellegű teszt.
- [ ] **Nincs bináris audio a repóban:** `git diff --stat` egyetlen
      `.wav`/`.mp3`/`.m4a` fájlt sem tartalmaz.
- [ ] **Baseline dokumentum:** a `docs/baseline/epic-06-analysis-evaluation.md`
      a **futtatott** `tool/audio_analysis_evaluate.dart` kimenetét
      tartalmazza, nem kézzel írt számokat.
- [ ] **ADR 0249** rögzíti: a dataset licenc- és adatvédelmi szabályát, a
      CI vs manuális eval szétválasztását, a regressziós küszöböket, a
      kalibrációs minimumokat, és hogy a küszöb **gyengítése** emberi döntés.
- [ ] **Eval-mátrix frissítés:** a korábbi körök PENDING sorai közül azok,
      amiket a szintetikus készlet **le tud** fedni, lezárva; a többi
      **megmarad** PENDING-ként, felelőssel.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Precision 0-ként jelölve, ha nincs detektálás | a (b) „precision `null`" cella |
| Az F1 képlete hibás | a (c) 0.666… és a (d) 0.625 cella |
| A riport időbélyeget tartalmaz | a bájtazonos determinizmus cella |
| A kalibráció kevés adatból illeszt | a **pontosan 29** binre `identity.v1` cella |
| A kalibrációs küszöb exkluzív | a **pontosan 30** illeszt-cella |
| Az ECE képlet súlyozatlan | a kézzel számolt ECE cella |
| A regressziós tolerancia rossz irányba tűr | a (b) 2.1 pp **piros** és (c) 1.9 pp **zöld** cellapár |
| A javulás is buktat | a (c) cella |
| Abszolút útvonal a riportban | a „nincs privát útvonal" cella |
| Bináris audio kerül a repóba | a `git diff --stat` cella |
| Workflow-fájl módosul | a `protect_factory_files.py` hook blokkolja; a §4 tilos zóna |
| **Valódi-sértés próba (§10):** a baseline onset-F1 értékének ideiglenes 3 pp-os rontása → a regressziós kapu **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/tooling
```

Külön processzek, nincs `&&`/pipe/`tail`. A **nagy**, valós-audio eval
manuálisan futtatható (`tool/audio_analysis_evaluate.dart --manifest <külső>`);
az eredménye a device/eval-mátrix PENDING sorait zárja, **nem** merge-kapu.

## 8. Implementációs sorrend

1. ADR 0249 + `evaluation/analysis/README.md` (licenc, adatvédelem, futtatás).
2. `manifest_schema.json` + `ci_manifest.json` (szintetikus generálási
   paraméterekkel).
3. RED: parser-mátrix + a négy ismert-válaszú metrika-cella.
4. `ground_truth.dart` + `evaluation_report.dart` + parser.
5. `evaluation_runner.dart` (kilenc metrika + szeletek).
6. `calibration_fitter.dart` (ECE, minimumok) + `calibration_table.dart` frissítés.
7. `tool/audio_analysis_evaluate.dart` + a **futtatott** baseline dokumentum.
8. Teszt-oldali regressziós kapu (négy cella); eval-mátrix; gate.

## 9. Kockázatok

- **A szintetikus készlet nem helyettesíti a valós audiot** — az ADR 0249
  ezt kimondja, és a valós eval a mátrix PENDING sora marad; a kalibráció
  várhatóan `identity.v1` marad, és ez a **helyes**, őszinte kimenet.
- **A CI-oldali kapu hiánya** tudatos H-GATEGUARD-határ; a completion
  reportnak (R30) **nevesítenie kell** a `GOV-xx` kört.
- **A `calibration_table.dart` az R19 fájlja** — a módosítása itt engedélyezett
  (a fájllistán szerepel), de kizárólag a tábla **tartalmának/verziójának**
  cseréjére; a szerződés (monotonitás, `[0,1]`) nem változhat, és az R19
  tesztjeinek zölden kell maradniuk.

**STOP:** workflow-szerkesztés, valós audio commitolása, DSP-retune vagy
kevés adatból illesztett „kalibráció" helyett `stopped` + brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r29-evaluation-harness-and-calibration-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
