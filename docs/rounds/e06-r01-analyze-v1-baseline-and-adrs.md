# E06-R01 — Analyze V1 baseline, mérés és ADR-ek

- **Státusz:** PREPARED (előre megírva 2026-08-07, kód olvasva: main @ `a6e6f3d`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 1; §3, §10, §19, §28, §30
- **Branch:** `codex/e06-r01-analyze-v1-baseline-and-adrs`
- **Előfeltétel:** **Epic 5 lezárva (E05-R30 merge)** + a user APK-ellenőrzése
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "docs/baseline/epic-06-audio-analysis-start.md",
  "docs/manual-testing/analysis-eval-matrix.md",
  "docs/adr/0200-analysis-document-versioning.md",
  "docs/adr/0201-analysis-confidence-calibration-and-abstention.md",
  "docs/adr/0202-analysis-raw-audio-retention.md",
  "docs/adr/0203-analysis-metric-id-and-version-governance.md",
  "docs/adr/0204-analysis-capability-aware-publication.md",
  "docs/adr/0205-audio-analysis-v2-parallel-rollout-boundary.md",
  "tool/audio_analysis_baseline.dart",
  "docs/rounds/e06-r01-analyze-v1-baseline-and-adrs.md",
]
gate_tests = [
  "test/features/analyze",
  "test/features/library",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main`; `ls docs/adr | sort | tail`
> a valós next-free számhoz — a **0185–0199** blokk az Epic 5 hátralévő körei
> (E05-R12/R17/R21 renumberelése) és a governance-munka számára **fenntartott**,
> az Epic 6 **0200-tól** oszt; ütközéskor a teljes 0200–0211 blokkot told el, és
> javítsd az `epic-06-batch-index.md` §3-at. Olvasd újra a `lib/features/analyze/`
> 12 fájlját és a `test/features/analyze` 14 tesztjét — a baseline MÉRT tény,
> nem másolat ebből a briefből. PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Előre kiosztott ADR-ek: **0200–0205** (hat darab; az SDD Kör 1
hármat nevez meg, a batch további hármat oszt ki, mert az Epic 6 három
keresztmetsző szabálya — metric-verziózás, capability-publikáció, V1/V2
párhuzamos rollout — enélkül körönként újratárgyalódna).

## 1. Cél

A **mai** Analyze funkció pontos, reprodukálható technikai baseline-jának
rögzítése **egyetlen sor alkalmazáskód-változtatás nélkül**, plusz az Epic 6
hat kötött architekturális döntése ADR-ként. Ez a kör a mérce, amihez a
későbbi 29 kör paritása mérődik.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- `lib/features/analyze/` = **12 fájl, 1 866 sor**: `engine/`
  (`chroma_denoise` 88, `clip_analyzer` 241, `clip_recorder` 58, `hpss` 226,
  `ml_chord_decoder` 250, `wav_decoder` 2 = deprecated re-export a
  `core/audio/codec/wav_decoder.dart`-ra), `model/analyze_result.dart` 198,
  `providers/analyze_providers.dart` 256, `screens/analyze_screen.dart` 432,
  `widgets/` (`analyze_skeleton` 127, `timeline_view` 170), `public.dart` 18.
- `AnalyzeResult` mezői: `durationSec`, `bpm`, `chords`, `strums`,
  `beatsPerBar` (default 4), `diagnostics?`. **Nincs** `schemaVersion`,
  provenance, per-metrika confidence vagy availability.
- `AnalyzePhase` = `{idle, recording, analyzing, done, micDenied, micError}` —
  **nincs** `cancelled`, `degraded`, progress vagy run ID.
- `computeClipAnalysis(pcm, sr, labMode)` egyetlen `compute()` hop; a
  `ClipAnalyzer` két passzt futtat (strum/tempo a `LivePipeline`-on,
  chord batch NNLS→Viterbi), `_bpmFromStrums` medián intervallum
  `.clamp(30, 300)`.
- `ClipRecorder` in-memory `List<double>` puffer, **nincs maximum hossz**.
- Library: `AnalyzedSession{id, createdAt, title, result, customTitle}` →
  `KeyValueLibraryRepository` → `JsonCollectionStore` **egyetlen kulcson**
  (`ss.library.sessions`, legacy `library_sessions`), cap 100.
- `tool/check_architecture.dart` 10–21. sora **12 engedélyezett** cross-feature
  importot sorol az `analyze → live/engine/{dsp,ml}` irányban.
- Tesztek: `test/features/analyze` 14 fájl, `test/features/library` 4 fájl,
  `test/property` 17 fájl (köztük `dsp_property_test`, `superflux_property_test`,
  `chord_timeline_property_test`, `crnn_ab_property_test`).
- **Nincs** `lib/features/audio_analysis/`, nincs `docs/baseline/epic-06-*`,
  nincs analysis feature flag a `lib/app/config/feature_flags.dart`-ban
  (a 20 meglévő flag közt egy sem audio-analysis).

## 3. Scope

**Benne:** `docs/baseline/epic-06-audio-analysis-start.md` (állapotgép,
`AnalyzeResult`/`AnalyzedSession` séma, recorder-lifecycle, WAV-támogatás,
ClipAnalyzer passzok, CRNN-fallback, Lab diagnostics, Library persistence,
Progress/Streak integráció, érintett tesztek, cross-feature dependency map);
`tool/audio_analysis_baseline.dart` (futtatható mérőszkript **legalább három**
szintetizált fixture-re: elemzési idő, event count, chord timeline, BPM,
model-load overhead); a hat ADR; `docs/manual-testing/analysis-eval-matrix.md`
váza PENDING sorokkal.

**Kívül — TILOS:** bármilyen `lib/` változtatás, teszt módosítása, DSP-konstans,
modell-asset, új feature flag, `test/` alatti új fájl.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `docs/baseline/epic-06-audio-analysis-start.md` | ÚJ | a mért V1 baseline |
| `docs/manual-testing/analysis-eval-matrix.md` | ÚJ | a valós-audio evidencia PENDING sorai |
| `docs/adr/0200-…` … `docs/adr/0205-…` | ÚJ | a hat kötött döntés |
| `tool/audio_analysis_baseline.dart` | ÚJ | futtatható mérés (a számok forrása) |
| `docs/rounds/e06-r01-…md` | meglévő | §10 handoff |

**Tilos zóna:** `lib/**`, `test/**`, `assets/**`, `docs/rag/**`,
`.github/**`, `tool/ci/**`, `tools/round-gate.sh`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **ADR 0200 — Analysis document versioning.** A V2 dokumentum kötelező
   `schemaVersion` egészt hordoz, a `Duration` szerializáció **mikroszekundum
   egész**; ismeretlen `schemaVersion` **kontrollált failure**, nem best-effort
   olvasás. **NEM elfogadható:** „lebegőpontos másodperc a domainben" vagy
   verzió nélküli JSON.
2. **ADR 0201 — Confidence, kalibráció, abstention.** Nyers softmax/cosine
   score **nem publikálható probabilityként**; minden metrika confidence-e
   kalibrációs verzióval azonosított, és a rendszernek joga abstainelni.
   **NEM elfogadható:** „a modell 0.87-et adott, tehát 87 % valószínűség".
3. **ADR 0202 — Raw audio retention.** Alapértelmezés `keepOriginal = false`;
   nyers audio nem kerül logba, crash-reportba, Tutor-kontextusba, exportba.
   **NEM elfogadható:** „ideiglenesen elmentjük, majd egy későbbi kör törli".
4. **ADR 0203 — Metric ID + version governance.** Minden metrika stabil,
   névtérrel ellátott ID-t és önálló verziót kap
   (`timing.mean_absolute_error.v1`); két session csak **azonos ID + kompatibilis
   verzió** mellett hasonlítható. **NEM elfogadható:** magic string a
   számítás helyén.
5. **ADR 0204 — Capability-aware publikáció.** Metrika csak
   `available`/jelölt `degraded` capability + küszöb feletti confidence +
   megengedő input-quality mellett jelenhet meg értékként; egyébként
   **magyarázott `unavailable`** (`CapabilityUnavailableReason`).
   **NEM elfogadható:** „0-t vagy N/A-t írunk ki és kész".
6. **ADR 0205 — V1/V2 párhuzamos rollout határa.** A V1 Analyze **az egész
   Epic alatt a shipping út marad**; a V2 minden képessége
   `audioAnalysisV2Enabled` (+ al-flagek) mögött, **default OFF minden
   környezetben, dart-define override nélkül** (a `songTrainerV2Enabled`
   precedense). Meglévő Analyze/Library teszt **nem írható át a zöldért** —
   elbukó meglévő teszt = **megállás és jelentés**.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: A baseline-mérés valós eszközön vagy szintetizált fixture-ön fusson?
    blocking: true
    resolution_policy: use_default
    default: >-
      szintetizált fixture (test/support/synth.dart mintájára a tool-szkriptben
      újraépítve) — ezen a boxon nincs Android SDK és nincs valós felvétel;
      a valós eszközös számok a docs/manual-testing/analysis-eval-matrix.md
      PENDING sorai, NEM merge-kapu.
  - id: OD-02
    question: A peak memória mérhető-e itt?
    blocking: false
    resolution_policy: use_default
    default: >-
      ha a `dart:developer`/`ProcessInfo` nem ad megbízható számot a gate
      környezetében, a baseline "NEM MÉRT (ok: …)" sort ír, nem becsült számot.
```

## 6. Acceptance criteria

- [ ] **Nulla `lib/` és `test/` diff:** `git diff --stat` egyetlen `lib/` vagy
      `test/` útvonalat sem tartalmaz.
- [ ] A baseline dokumentum **minden** állítása mellett fájlnév (és ahol
      értelmes, sorszám) áll; a §2-ben felsorolt 12 forrásfájl és 18 tesztfájl
      mind szerepel.
- [ ] `tool/audio_analysis_baseline.dart` **kétszer futtatva bájtazonos
      timeline/BPM/event-count kimenetet ad** (determinizmus), és a futtatott
      kimenet szó szerint bemásolva a baseline dokumentum „Mért értékek"
      táblájába — nem kerekítve, nem kézzel írva.
- [ ] A mérés **legalább három** fixture-re fut: (a) csend, (b) ismert BPM-ű
      pengetés-sorozat, (c) négy akkordból álló progresszió — mindegyikhez
      elemzési idő, event count, chord-szegmensszám, BPM, model-load overhead.
- [ ] Mind a hat ADR tartalmazza: **Döntés · Kontextus · Következmény ·
      Elutasított alternatívák · A visszavonás feltétele**.
- [ ] Az ADR 0205 kimondja a flag-nevet, a default OFF-ot **minden**
      környezetben, és azt, hogy dart-define override **nincs**.
- [ ] `docs/manual-testing/analysis-eval-matrix.md` minden PENDING sora
      megnevezi a **felelőst** és a **mérendő számot** (nem „ellenőrizni kell").
- [ ] `tools/brief-lint.py --brief docs/rounds/e06-r01-… --level strict` → 0 lelet.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

Docs-only kör: a falszifikáció a **reviewer eldobható próbája**.

| Hibás/hiányos szállítás | Melyik cella válik bizonyíthatatlanná (reviewer-próba) |
|---|---|
| A baseline számai kézzel írtak, nem a szkript kimenetéből | a reviewer újrafuttatja `tool/audio_analysis_baseline.dart`-ot → eltérő szám → **PIROS** |
| A szkript nem determinisztikus (pl. `DateTime.now()` a seedben) | kétszeri futtatás eltérő event countot ad → **PIROS** |
| Az ADR 0205-ből kimarad a „default OFF minden környezetben" mondat | a rollout-acceptance cella bizonyíthatatlan: az E06-R02+ körök flag-defaultja szabadon értelmezhető |
| Az ADR 0203-ból kimarad a verzió-kompatibilitási szabály | az E06-R25 összehasonlítási acceptance-e elveszti a hivatkozási alapját |
| A dependency map nem sorolja fel mind a 12 allowlist-bejegyzést | a `tool/check_architecture.dart` 10–21. sorával összevetve hiányos → **PIROS** |
| Bármelyik `lib/`/`test/` fájl módosul | a „nulla alkalmazáskód-változás" cella **PIROS** (`git diff --stat`) |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/analyze test/features/library
```

Külön processzek, nincs `&&`/pipe/`tail`. A gate itt **regressziómentességet**
bizonyít (a kör nem nyúl a kódhoz); a teljes suite + property gate CI-oldali,
exact-SHA dispatch az orchestrátortól.

## 8. Implementációs sorrend

1. `tool/audio_analysis_baseline.dart` (szintetizált fixture-ök + mérés).
2. Kétszeri futtatás, determinizmus-ellenőrzés, a kimenet mentése.
3. `docs/baseline/epic-06-audio-analysis-start.md` a mért számokkal.
4. ADR 0200–0205.
5. `docs/manual-testing/analysis-eval-matrix.md` PENDING váza.
6. Gate.

## 9. Kockázatok

- **A szkript véletlenül behúzza a `flutter` runtime-ot** (`rootBundle`) —
  a modellsúlyok a `rootBundle`-ból jönnek, ami main-isolate-only és
  `dart run` alatt nem elérhető. Feloldás: a model-load overheadet a szkript
  a **fájlméret + parse idő** mérésével adja meg (`ml/` asset közvetlen
  olvasásából), és ezt a baseline explicit megjegyzi.
- **A `compute()` isolate-hop ideje gépfüggő** — az abszolút szám nem mérce,
  csak baseline; a dokumentum írja ki a futtató gép leírását.
- **ADR-szám ütközés** párhuzamos governance-körrel — a pre-flight `ls`-e a
  kapu, a `tools/tests/test_adr_numbering.py` a gépi őr.

**STOP:** ha a baseline-mérés csak `lib/` módosítással lenne elvégezhető,
az **megállás és jelentés** (dokumentált brief-revízió), nem néma
kódmódosítás.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r01-analyze-v1-baseline-and-adrs-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
