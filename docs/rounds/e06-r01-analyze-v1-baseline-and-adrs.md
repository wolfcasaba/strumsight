# E06-R01 — Analyze V1 baseline, mérés és ADR-ek

- **Státusz:** PLANNING (előre megírva 2026-08-07, kód olvasva: main @ `a6e6f3d`;
  R1+R2 pre-flight revízió 2026-08-11, ADR-ek megírva és commitolva — ld. §0.0)
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
  "docs/adr/0215-analysis-document-versioning.md",
  "docs/adr/0216-analysis-confidence-calibration-and-abstention.md",
  "docs/adr/0217-analysis-raw-audio-retention.md",
  "docs/adr/0218-analysis-metric-id-and-version-governance.md",
  "docs/adr/0219-analysis-capability-aware-publication.md",
  "docs/adr/0220-audio-analysis-v2-parallel-rollout-boundary.md",
  "tool/audio_analysis_baseline.dart",
  "docs/rounds/e06-r01-analyze-v1-baseline-and-adrs.md",
]
gate_tests = [
  "test/features/analyze",
  "test/features/library",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main`; a valós next-free ADR-számot
> **a `tools/round-slots.py reserve-adr` foglalótól kérd, ne `ls docs/adr | tail`-lel**
> (pipeline-prompt §1.0.1) — ez a kör pontosan ezt tette, és a hat szám
> **0215–0220**-ra módosult, lásd a §0.0 R1 revízióját. Olvasd újra a
> `lib/features/analyze/` **14** fájlját és a `test/features/analyze` **15**
> tesztjét — a baseline MÉRT tény, nem másolat ebből a briefből.
> PREPARED→PLANNING, brief commit megtörtént (R1/R2 revízió).

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED → PLANNING (R1+R2 revízió, 2026-08-11, orchesztrátor pre-flight).**
Előre kiosztott ADR-ek eredetileg: **0200–0205** (hat darab; az SDD Kör 1
hármat nevez meg, a batch további hármat oszt ki, mert az Epic 6 három
keresztmetsző szabálya — metric-verziózás, capability-publikáció, V1/V2
párhuzamos rollout — enélkül körönként újratárgyalódna).

### R1 — ADR-átszámozás: 0200–0205 → 0215–0220 (mért, pipeline-prompt §1.0.1)

A brief fejléce 2026-08-07-én, a legmagasabb akkori `docs/adr/` sorszámból
extrapolálva írta elő a 0200–0205 tartományt. A pipeline-prompt §1.0.1
szabálya szerint a foglalótól kell kérni a valós számot, nem a brief
fejlécét követni — ez a mintázat ötödször-hatodszor mért ismétlődés
(`docs/LESSONS.md` L194: „a pipeline-prompt saját táblája a helyes válasz,
ne a brief fejléce"). Mérve: `git fetch origin --prune` +
`git log --all --diff-filter=A --name-only -- docs/adr` a legmagasabb
ADR-t **0214**-ként adta — három közbeeső governance-kör (GOV-06b `0212`,
GOV-05b-1 `0213`, GOV-05b-2 `0214`, mind 2026-08-09, a brief írása UTÁN)
konzumálta a 0200–0211 sáv fölötti számokat, anélkül hogy magát a
0200–0211 tartományt ténylegesen lefoglalta volna (a `reserve_adr` a
`docs/adr/` + minden branch + az in-flight markerek max()+1 értékét adja,
nem a queue-fájl pre-allokációját olvassa). `tools/round-slots.py
reserve-adr --round E06-R01` hatszor futtatva (atomi `O_CREAT|O_EXCL`
marker, `.pipeline/inflight/adr/0215`…`0220`) **0215, 0216, 0217, 0218,
0219, 0220**-at adta.

Leképezés: `0200→0215` (versioning), `0201→0216` (confidence/calibration/
abstention), `0202→0217` (raw audio retention), `0203→0218` (metric ID +
version governance), `0204→0219` (capability-aware publication),
`0205→0220` (V1/V2 párhuzamos rollout határa) — a brief minden hivatkozása
lent javítva, az `ai-router` `allowed_paths` a valós fájlneveket sorolja.
Mind a hat ADR-t az orchesztrátor írta meg és commitolta a pre-flightban
(ADR 0055, outer pipeline-prompt §0 „te írod meg a pre-flightban" sora) —
az implementer szerepe ezekre **olvasás** (referencia a §1 „Kötelező
olvasmány"-ban), nem módosítás.

**Nem ennek a körnek a scope-ja, de mért követelmény:** a queue többi Epic 6
sorának pre-allokált ADR-száma (E06-R08 `0206`, E06-R11 `0207`, E06-R18
`0208`, E06-R21 `0209`, E06-R28 `0210`, E06-R29 `0211`) ugyanígy elavult, és
az `epic-06-batch-index.md` §3 hivatkozásai is avulnak. Ezt a sort NEM
javítom itt — a `docs/execution/pipeline-queue.tsv` szerkesztése az outer
pipeline-prompt §4 szerint kifejezetten tilos ennek a sessionnek
(„azt a driver vezeti"), és az `epic-06-batch-index.md` nincs az
`allowed_paths`-on (tilos zóna, H3 kockázat egy önkényes bővítésnél). Az
érintett jövőbeli körök saját pre-flightja ugyanezt a mérést fogja
elvégezni, ugyanazzal a `reserve-adr` mechanizmussal.

### R2 — Fájl/sor-szám drift a §2 „Jelenlegi állapot"-ban (mért, pipeline-prompt §1 1. szabálya)

A brief 2026-08-07-i (`a6e6f3d`) méréséhez képest a `main` **drift-elt**: az
E05-R27 kör (`7e430190`, 2026-08-08, „AI Tutor and Analysis vision evidence
adapters") két ÚJ fájlt adott az `lib/features/analyze/` alá
(`model/analysis_vision_reference.dart` 21 sor,
`providers/analysis_vision_adapter.dart` 81 sor), plusz egy megfelelő
tesztfájlt (`test/features/analyze/analysis_vision_adapter_test.dart` 111
sor) és három, ettől a körtől független vision-property tesztet
(`test/property/{clock_mapping,hand_track,homography}_property_test.dart`,
Epic 5 eredetűek). Mérve `HEAD`-en (2026-08-11,
`git diff --stat a6e6f3d HEAD -- lib/features/analyze/
test/features/analyze/ test/property/` + `wc -l`/`find`): **14 fájl, 2 168
sor** az `analyze` alatt (nem 12/1 866); **15** tesztfájl a
`test/features/analyze` alatt (nem 14); **20** fájl a `test/property` alatt
(nem 17). A §2 és a §6 acceptance-cella lent javítva ennek megfelelően.
Minden EGYÉB §2-állítás (mezőnevek, enum-értékek, sorszámok a meglévő 12
fájlon) grep-elve **egyezik** — nincs további revízió. `tool/check_architecture.dart`
10–21. sora (a 12 engedélyezett cross-feature import az analyze→live
irányban) **VÁLTOZATLAN maradt** — csak maga a fájl nőtt (146 sorral, új
vision-architektúra-szabályokkal), a sorszám-tartomány nem tolódott.

## 1. Cél

A **mai** Analyze funkció pontos, reprodukálható technikai baseline-jának
rögzítése **egyetlen sor alkalmazáskód-változtatás nélkül**, plusz az Epic 6
hat kötött architekturális döntése ADR-ként. Ez a kör a mérce, amihez a
későbbi 29 kör paritása mérődik.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- `lib/features/analyze/` = **14 fájl, 2 168 sor** (mérve HEAD-en,
  2026-08-11 — R2 revízió; a 2026-08-07-i `a6e6f3d` mérés 12 fájl/1 866 sor
  volt, az E05-R27 kör két fájlt adott hozzá azóta, ld. §0.0): `engine/`
  (`chroma_denoise` 88, `clip_analyzer` 241, `clip_recorder` 58, `hpss` 226,
  `ml_chord_decoder` 250, `wav_decoder` 2 = deprecated re-export a
  `core/audio/codec/wav_decoder.dart`-ra), `model/` (`analyze_result.dart`
  198, `analysis_vision_reference.dart` 21 — ÚJ, E05-R27), `providers/`
  (`analyze_providers.dart` 256, `analysis_vision_adapter.dart` 81 — ÚJ,
  E05-R27), `screens/analyze_screen.dart` 432, `widgets/`
  (`analyze_skeleton` 127, `timeline_view` 170), `public.dart` 18.
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
- Tesztek: `test/features/analyze` **15** fájl (a 15. ÚJ, E05-R27:
  `analysis_vision_adapter_test.dart`), `test/features/library` 4 fájl,
  `test/property` **20** fájl (17 + 3 Epic 5-eredetű: `clock_mapping_property_test`,
  `hand_track_property_test`, `homography_property_test`; köztük az
  `analyze`-hoz kötődő `dsp_property_test`, `superflux_property_test`,
  `chord_timeline_property_test`, `crnn_ab_property_test` változatlan).
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
| `docs/adr/0215-…` … `docs/adr/0220-…` | ÚJ | a hat kötött döntés (R1 revízió — eredetileg 0200–0205, ld. §0.0) |
| `tool/audio_analysis_baseline.dart` | ÚJ | futtatható mérés (a számok forrása) |
| `docs/rounds/e06-r01-…md` | meglévő | §10 handoff |

**Tilos zóna:** `lib/**`, `test/**`, `assets/**`, `docs/rag/**`,
`.github/**`, `tool/ci/**`, `tools/round-gate.sh`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **ADR 0215 — Analysis document versioning.** A V2 dokumentum kötelező
   `schemaVersion` egészt hordoz, a `Duration` szerializáció **mikroszekundum
   egész**; ismeretlen `schemaVersion` **kontrollált failure**, nem best-effort
   olvasás. **NEM elfogadható:** „lebegőpontos másodperc a domainben" vagy
   verzió nélküli JSON.
2. **ADR 0216 — Confidence, kalibráció, abstention.** Nyers softmax/cosine
   score **nem publikálható probabilityként**; minden metrika confidence-e
   kalibrációs verzióval azonosított, és a rendszernek joga abstainelni.
   **NEM elfogadható:** „a modell 0.87-et adott, tehát 87 % valószínűség".
3. **ADR 0217 — Raw audio retention.** Alapértelmezés `keepOriginal = false`;
   nyers audio nem kerül logba, crash-reportba, Tutor-kontextusba, exportba.
   **NEM elfogadható:** „ideiglenesen elmentjük, majd egy későbbi kör törli".
4. **ADR 0218 — Metric ID + version governance.** Minden metrika stabil,
   névtérrel ellátott ID-t és önálló verziót kap
   (`timing.mean_absolute_error.v1`); két session csak **azonos ID + kompatibilis
   verzió** mellett hasonlítható. **NEM elfogadható:** magic string a
   számítás helyén.
5. **ADR 0219 — Capability-aware publikáció.** Metrika csak
   `available`/jelölt `degraded` capability + küszöb feletti confidence +
   megengedő input-quality mellett jelenhet meg értékként; egyébként
   **magyarázott `unavailable`** (`CapabilityUnavailableReason`).
   **NEM elfogadható:** „0-t vagy N/A-t írunk ki és kész".
6. **ADR 0220 — V1/V2 párhuzamos rollout határa.** A V1 Analyze **az egész
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
      értelmes, sorszám) áll; a §2-ben felsorolt **14 forrásfájl és 19
      tesztfájl** (R2 revízió — eredetileg 12/18, ld. §0.0) mind szerepel.
- [ ] `tool/audio_analysis_baseline.dart` **kétszer futtatva bájtazonos
      timeline/BPM/event-count kimenetet ad** (determinizmus), és a futtatott
      kimenet szó szerint bemásolva a baseline dokumentum „Mért értékek"
      táblájába — nem kerekítve, nem kézzel írva.
- [ ] A mérés **legalább három** fixture-re fut: (a) csend, (b) ismert BPM-ű
      pengetés-sorozat, (c) négy akkordból álló progresszió — mindegyikhez
      elemzési idő, event count, chord-szegmensszám, BPM, model-load overhead.
- [ ] Mind a hat ADR tartalmazza: **Döntés · Kontextus · Következmény ·
      Elutasított alternatívák · A visszavonás feltétele**.
- [ ] Az ADR 0220 kimondja a flag-nevet, a default OFF-ot **minden**
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
| Az ADR 0220-ból kimarad a „default OFF minden környezetben" mondat | a rollout-acceptance cella bizonyíthatatlan: az E06-R02+ körök flag-defaultja szabadon értelmezhető |
| Az ADR 0218-ból kimarad a verzió-kompatibilitási szabály | az E06-R25 összehasonlítási acceptance-e elveszti a hivatkozási alapját |
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
4. ADR 0215–0220 (referencia — az orchesztrátor már megírta a pre-flightban, ld. §0.0).
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

- **Módosított fájlok:**
  - `tool/audio_analysis_baseline.dart` — Flutter-test runneren futó, óra és
    seed nélküli V1-harness; 2 s csendet, 120 BPM-es strum-sorozatot és
    C–G–Am–F progressziót mér. A modell-overhead közvetlen asset read+parse,
    nem `rootBundle`; egy futáson belül kétszer ellenőrzi a determinisztikus
    timeline/BPM/event-count bájtokat.
  - `docs/baseline/epic-06-audio-analysis-start.md` — forráshelyekkel jelölt
    V1 állapot, 14/2168 Analyze production inventory, 15 Analyze + 4 Library
    + 20 property teszt inventory, 12 elemű cross-feature map és két tényleges
    mérési kimenet.
  - `docs/manual-testing/analysis-eval-matrix.md` — minden sor PENDING, és
    mindegyik felelőst, reprodukálható bemenetet és mérendő számot ad.
- **Acceptance evidence:**
  1. `git diff --cached --stat` tényleges kimenete: baseline 71, eval-mátrix
     29, brief 49, tool 253 sor; 4 fájl, 401 insertion, 1 deletion — nincs `lib/**` vagy `test/**` útvonal.
  2. A baseline minden V1-állítást `fájl:sor` hivatkozással, a 14 production
     és 19 Analyze/Library tesztfájlt név szerint tartalmazza.
  3. A determinisztikus kimenet SHA-256-a mindkét külső futásban
     `071925bcc69f53579dddbeb505375ef897760c84efd1f7255db90f4465f1d7b6`;
     a harness saját `orderedEquals` ellenőrzése `tool/audio_analysis_baseline.dart:24-42`.
  4. Mindhárom kötelező fixture futott; a mért idő, event count, chord
     szegmens, BPM és model byte a baseline táblában szó szerint szerepel.
  5. ADR 0215–0220 olvasva és változatlanul hagyva; mind a hatban jelen van
     Döntés, Kontextus, Következmény, Elutasított alternatívák és A
     visszavonás feltétele.
  6. ADR 0220 kimondja az `audioAnalysisV2Enabled` default OFF-ot minden
     környezetben és a dart-define override hiányát.
  7. Az eval-mátrix minden PENDING sora felelőst és metrikát nevez meg.
  8. `tools/brief-lint.py --brief docs/rounds/e06-r01-analyze-v1-baseline-and-adrs.md --level strict` → `# Brief-lint (strict) — nincs lelet`.
- **Két tényleges baseline-futtatás** (`flutter test --reporter expanded tool/audio_analysis_baseline.dart`):
  - A: model 1456371 byte / 42439 µs; silence 186344 µs, 0 BPM, 0 strum,
    0 chord; strums 476446 µs, 120.1853197674418 BPM, 5 strum, 1 `Em`
    chord; progression 295281 µs, 74.89809782608695 BPM, 3 strum, 4
    chord (`C`, `G`, `Am`, `F`); SHA-256 a fenti.
  - B: model 1456371 byte / 45812 µs; silence 189598 µs, 0 BPM, 0 strum,
    0 chord; strums 504544 µs, 120.1853197674418 BPM, 5 strum, 1 `Em`
    chord; progression 312222 µs, 74.89809782608695 BPM, 3 strum, 4
    chord (`C`, `G`, `Am`, `F`); SHA-256 a fenti.
- **Gate:** első futás az új harness két analyze-lintje miatt állt meg
  (`dangling_library_doc_comments`, `avoid_print`); a `library;` direktíva
  és `stdout.writeln` javítása után a teljes gate újrafuttatva:
  `format`, `analyze`, `test test/features/analyze`,
  `test test/features/library`, `architecture`, `secrets` és `l10n` mind
  **zöld**; a gate `MINDEN GATE ZÖLD` kilépéssel zárult.
- **Eltérés / követés:** peak memória NEM MÉRT, mert nincs reprodukálható
  processz-peak forrás; a valós eszközös memória- és pontosságmérés az
  `analysis-eval-matrix.md` PENDING sorai szerint következik. A kör nem
  módosít alkalmazáskódot, tesztet, DSP-konstanst vagy modell-assetet.

## 11. Review — a Claude tölti ki

Link: `docs/reviews/e06-r01-analyze-v1-baseline-and-adrs-review.md`

Verdikt: **APPROVED** (2026-08-11, egy forduló, javító kör nélkül). 0
BLOCKER/MAJOR/MINOR, 3 NOTE (forward-looking). Dedikált security-review
(risk=high) **PASS**, 0 CRITICAL/BLOCKER/MAJOR/MINOR, 2 NOTE. Reviewer
SAJÁT, izolált `/tmp` klónban HARMADIK, független futtatással bitre egyező
determinizmus-SHA-256-ot mért, és a teljes 9-lépéses gate-et is
függetlenül újrafuttatta (mind zöld).
