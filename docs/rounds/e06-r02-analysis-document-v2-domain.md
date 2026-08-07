# E06-R02 — AnalysisDocument V2 domainmodell

- **Státusz:** PREPARED (előre megírva 2026-08-07, kód olvasva: main @ `a6e6f3d`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 2; §7, §9, §10
- **Branch:** `codex/e06-r02-analysis-document-v2-domain`
- **Előfeltétel:** **E06-R01 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/domain/analysis_document.dart",
  "lib/features/audio_analysis/domain/analysis_mode.dart",
  "lib/features/audio_analysis/domain/analysis_input_summary.dart",
  "lib/features/audio_analysis/domain/analysis_provenance.dart",
  "lib/features/audio_analysis/domain/analysis_timeline.dart",
  "lib/features/audio_analysis/domain/analysis_event.dart",
  "lib/features/audio_analysis/domain/analysis_segment.dart",
  "lib/features/audio_analysis/domain/analysis_capability.dart",
  "lib/features/audio_analysis/domain/analysis_metric.dart",
  "lib/features/audio_analysis/domain/analysis_metric_catalog.dart",
  "lib/features/audio_analysis/domain/analysis_hotspot.dart",
  "lib/features/audio_analysis/domain/analysis_insight.dart",
  "lib/features/audio_analysis/domain/analysis_warning.dart",
  "lib/features/audio_analysis/domain/signal_quality_report.dart",
  "lib/features/audio_analysis/public.dart",
  "lib/app/config/feature_flags.dart",
  "test/features/audio_analysis/domain/analysis_document_test.dart",
  "test/features/audio_analysis/domain/analysis_metric_test.dart",
  "test/features/audio_analysis/domain/analysis_capability_test.dart",
  "test/features/audio_analysis/domain/analysis_timeline_test.dart",
  "test/app/feature_flags_test.dart",
  "docs/rounds/e06-r02-analysis-document-v2-domain.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/app",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R01 merge. Olvasd újra
> a `lib/app/config/feature_flags.dart` **mai** flag-listáját (a batch idején
> 20 flag, egy sem audio-analysis) és a `test/app/feature_flags_test.dart`
> tényleges nevét/tartalmát — ha a fájl nem létezik vagy máshogy hívják, a
> flag-őr tesztje **a meglévő fájlba** kerül, a lista pedig a pre-flightban
> javul. ADR 0200/0203/0204/0205 az R01-ből. PREPARED→PLANNING, brief commit
> előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Új ADR nincs — a kör az R01 ADR 0200 (verziózás), 0203 (metric ID
és verzió), 0204 (capability-publikáció) és 0205 (flag-határ) végrehajtása.

## 1. Cél

A verziózott, immutable **V2 domainmodell** létrehozása úgy, hogy a V1
`AnalyzeResult` **egyetlen bájtot sem változik**. Ez a kör kizárólag típusokat
és validációt szállít — nincs benne DSP, nincs I/O, nincs UI.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- **Nincs `lib/features/audio_analysis/`** — a kör greenfield.
- A mai eredménymodell `lib/features/analyze/model/analyze_result.dart` (198
  sor): `TimelineChord{label,startSec,endSec}`, `TimelineStrum{direction,
  timeSec,confidence}`, `MlChordDiagnostics{mlChords,agreement}`,
  `AnalyzeResult{durationSec,bpm,chords,strums,beatsPerBar,diagnostics?}`.
  Lebegőpontos **másodperc** minden időmezőben, `schemaVersion` nincs.
- A validációs primitívek készen állnak: `lib/core/foundation/json_validation.dart`
  (`requireString`, `requireDouble`, `requireEnumByName`, `requireList(maxLength:)`,
  `optionalInt(min:,max:)`), és `AnalyzeResult` már használja őket.
- `AppResult`/`AppFailure` a `lib/core/foundation/`-ben (sealed
  `Success`/`Failure`).
- A `tool/check_architecture.dart` érvényesíti: `lib/features/*/domain/`
  **framework-mentes** (nincs Flutter-import), cross-feature import csak
  `public.dart`-on át, és az allowlist **csak szűkülhet**.
- `lib/app/config/feature_flags.dart`: 20 flag, mind konstruktor-paraméter +
  `forEnvironment` default + `==` + `hashCode` + `toString`. **Egy sem
  audio-analysis.**

## 3. Scope

**Benne:** az SDD §9 tizenhárom domain-típusa (`AnalysisDocument`,
`AnalysisCompletion(Status)`, `AnalysisMode`, `AnalysisInputSummary`,
`AnalysisProvenance`, `AnalysisTimeline`, `AnalysisEvent` sealed hierarchia,
`AnalysisSegment`, `CapabilityReport` + `AnalysisCapability` +
`CapabilityStatus` + `CapabilityUnavailableReason`, `AnalysisMetricResult` +
**sealed** `AnalysisMetricValue`, `AnalysisHotspot`, `AnalysisInsight`,
`AnalysisWarning`, `SignalQualityReport` **típusa** — a számítása az R07-é),
a metric-ID katalógus, a `public.dart` barrel, és **három** új feature flag:
`audioAnalysisV2Enabled`, `analysisBeatGridEnabled`, `analysisPitchEnabled`
(mind default OFF).

**Kívül — TILOS:** JSON codec (R03), pipeline (R04), bármely számítás,
`lib/features/analyze/**` és `lib/features/library/**` érintése, DSP.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/analysis_document.dart` | ÚJ | gyökér aggregátum + `AnalysisCompletion` |
| `.../domain/analysis_mode.dart` | ÚJ | mode + input source (külön mező, §6.1) |
| `.../domain/analysis_input_summary.dart` | ÚJ | privacy-flagelt input-metaadat |
| `.../domain/analysis_provenance.dart` | ÚJ | analyzer/pipeline/stage verziók, hashek |
| `.../domain/analysis_timeline.dart` | ÚJ | timeline aggregátum |
| `.../domain/analysis_event.dart` | ÚJ | sealed event hierarchia |
| `.../domain/analysis_segment.dart` | ÚJ | chord/pitch szegmens típusok |
| `.../domain/analysis_capability.dart` | ÚJ | capability + status + reason + report |
| `.../domain/analysis_metric.dart` | ÚJ | metric result + **sealed** metric value |
| `.../domain/analysis_metric_catalog.dart` | ÚJ | stabil metric ID-k (ADR 0203) |
| `.../domain/analysis_hotspot.dart` | ÚJ | hotspot |
| `.../domain/analysis_insight.dart` | ÚJ | insight + recommended action |
| `.../domain/analysis_warning.dart` | ÚJ | warning típusok |
| `.../domain/signal_quality_report.dart` | ÚJ | quality riport **típus** |
| `.../public.dart` | ÚJ | a feature egyetlen kifelé látszó barrelje |
| `lib/app/config/feature_flags.dart` | meglévő | **additív** 3 flag, default OFF |
| `test/features/audio_analysis/domain/*` | ÚJ | validációs tesztek |
| `test/app/feature_flags_test.dart` | meglévő/ÚJ | flag-default őr |

**Tilos zóna:** `lib/features/analyze/**`, `lib/features/library/**`,
`lib/features/live/**`, `assets/**`, `docs/rag/**`, minden DSP-konstans.
Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Az idő a domainben `Duration`** (vagy egész mikroszekundum/sample index).
   **NEM elfogadható:** `double seconds` mező a domain-típusokban — a
   lebegőpontos másodperc kizárólag a szerializációs és UI-határon él (ADR 0200).
2. **Minden lista immutable snapshot:** a konstruktor `List.unmodifiable`-t
   tárol. **NEM elfogadható:** a hívó által átadott lista referenciájának
   megtartása (a `CompiledPracticeTarget` precedense szerint).
3. **A metrika értéke sealed hierarchia** (`ScalarMetricValue`,
   `PercentageMetricValue`, `DurationMetricValue`, `DistributionMetricValue`,
   `TimeSeriesMetricValue`, `CategoryMetricValue`, `ScoreMetricValue`).
   **NEM elfogadható:** `Object?`/`dynamic` értékmező (SDD §31.9).
4. **Metric ID csak a katalógusból** (ADR 0203): `<namespace>.<name>.v<N>`
   alak, a katalógus konstansaiból. **NEM elfogadható:** string literál a
   metrika létrehozási helyén.
5. **A domain framework-mentes:** nincs `package:flutter`, nincs
   `flutter_riverpod`, nincs `AppLocalizations`. Az insight **`messageKey` +
   `messageArgs`** párt hordoz, nem kész mondatot (SDD §9.10).
6. **Konstruktor-validáció fail-closed:** negatív duration, `[0,1]`-en kívüli
   confidence, duplikált metric ID, `end < start` szegmens,
   `completion == cancelled|failed` **menthető** dokumentumként — mind
   `ArgumentError`/`assert` helyett **kontrollált** hiba a projekt
   konvenciója szerint (a `json_validation.dart` mintája). **NEM elfogadható:**
   érvénytelen érték csendes clampelése.
7. **A flagek additívak és OFF-ok** (ADR 0205): a `forEnvironment` mindhárom új
   flaget `false`-ra állítja **minden** környezetben, dart-define override
   nélkül; az `==`/`hashCode`/`toString` kiegészítése kötelező.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: A validációs hiba kivétel legyen vagy AppResult?
    blocking: true
    resolution_policy: use_default
    default: >-
      konstruktorban dobó `ArgumentError` (a domain invariáns megsértése
      programozói hiba), a HATÁRON (codec, R03) viszont AppResult/typed
      failure — a két réteg nem keveredik.
  - id: OD-02
    question: A `mode` és az `inputSource` egy enum legyen?
    blocking: false
    resolution_policy: use_default
    default: >-
      KÉT külön mező (SDD §6.1 kifejezetten ezt kéri); az importedRecording
      input source, nem intent.
```

## 6. Acceptance criteria

- [ ] **Domain-purity őr:** `dart run tool/check_architecture.dart` zöld, és
      egyetlen új `domain/` fájl sem importál `package:flutter`-t
      (a gate `architecture` lépése méri).
- [ ] **Validációs mátrix — `AnalysisDocument`:** minden sor saját teszt-cella:
      `durationUs` **−1 / 0 / +1**; confidence **−0.0001 / 0.0 / 0.5 / 1.0 /
      1.0001**; duplikált metric ID **0 / 1 / 2** előfordulással; szegmens
      `start > end`, `start == end`, `start < end`.
- [ ] **Confidence-küszöb hármas:** a `[0,1]` tartomány mindkét határa
      **inkluzív**; a mátrixban szerepel a `0.0` és `1.0` (átmegy) ÉS a
      `-1e-9` / `1.0 + 1e-9` (elutasít) cella — `python3 -c` -vel kiszámolt
      értékekkel, nem `0.0001`-es közelítéssel.
- [ ] **Immutabilitás-teszt:** a konstruktornak átadott lista **utólagos
      mutálása** nem látszik a dokumentumon (`document.metrics.length`
      változatlan), és `document.metrics.add(...)` dob.
- [ ] **Metric-value sealed teszt:** `switch` az `AnalysisMetricValue` fölött
      **exhaustive** default ág nélkül fordul (a fordító bizonyítja).
- [ ] **Metric-ID őr:** teszt méri, hogy a katalógus minden ID-je egyedi és
      illeszkedik a `^[a-z_]+\.[a-z0-9_]+\.v[0-9]+$` alakra.
- [ ] **Flag-őr:** `FeatureFlags.forEnvironment` mind a **négy** környezetére
      (dev/lab/staging/production — a mai enum tényleges értékeire) mindhárom
      új flag `false`; és a `toString()` tartalmazza őket.
- [ ] **V1 érintetlen:** `git diff --stat` nem tartalmaz
      `lib/features/analyze/**` vagy `lib/features/library/**` útvonalat, és
      a `test/features/analyze` + `test/features/library` gate zöld.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A konstruktor a kapott listát referenciaként tárolja | immutabilitás-teszt „utólagos mutálás nem látszik" cellája |
| A confidence-ellenőrzés `<`/`>` helyett `<=`/`>=` (a határ kizárva) | a `0.0` és `1.0` **átmegy**-cella |
| A confidence-ellenőrzés hiányzik | a `-1e-9` / `1.0+1e-9` **elutasít**-cella |
| A duration validáció `>= 0` helyett `> 0` | a `durationUs == 0` átmegy-cella |
| A metric value `Object?` marad | a sealed `switch` nem fordul default nélkül → analyze **PIROS** |
| A metric ID string literálként készül | a katalógus-alak őr (`^…v[0-9]+$`) **PIROS** a nem katalógusbeli ID-re |
| A domain importál `package:flutter`-t | `tool/check_architecture.dart` **PIROS** |
| Az új flag `nonProd`-ra `true` | flag-őr production≠nonProd cellája **PIROS** |
| **Valódi-sértés próba (§10):** a duplikált-metric-ID ellenőrzés ideiglenes kiszedése → a duplikált-ID teszt **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/app test/features/analyze test/features/library
```

Külön processzek, nincs `&&`/pipe/`tail`. A két utolsó útvonal a **V1
regressziómentesség** bizonyítéka. Teljes suite + property gate: CI, exact-SHA
dispatch az orchestrátortól.

## 8. Implementációs sorrend

1. RED: a validációs mátrix tesztjei (dokumentum, metrika, capability, timeline).
2. `analysis_metric_catalog.dart` + `analysis_metric.dart` (sealed value).
3. Capability/segment/event/warning típusok.
4. `analysis_provenance.dart`, `analysis_input_summary.dart`, `analysis_timeline.dart`.
5. `analysis_document.dart` + `public.dart`.
6. Feature flagek + flag-őr.
7. Gate.

## 9. Kockázatok

- **A `public.dart` túl sokat exportál** → később a cross-feature határ
  átjáróvá válik. Ellenszer: a barrel **csak** azokat a típusokat exportálja,
  amiket a későbbi körök adapterei ténylegesen igényelnek; a bővítés a
  fogyasztó kör dolga.
- **A domain túl korán rögzít számítási feltevést** (pl. `tonalness` skálája) —
  ezért ez a kör **kizárólag típusokat** szállít, mértékegység-dokumentációval
  a doc-commentben, számítás nélkül.
- **`beatsPerBar` V1-kompatibilitás:** a V2 `Meter` fogalma az R12-é; itt csak
  a mező helye létezik, feltöltés nélkül.

**STOP:** ha a domain valamely mezője csak úgy értelmezhető, hogy egy V1 fájlt
módosítani kell, az **megállás és jelentés**, nem a tilos zóna tágítása.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r02-analysis-document-v2-domain-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
