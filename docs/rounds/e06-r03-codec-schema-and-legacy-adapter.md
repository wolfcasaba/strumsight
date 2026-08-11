# E06-R03 — Codec, schema validation és V1 adapter

- **Státusz:** PLANNING (előre megírva 2026-08-07, kód olvasva: main @ `a6e6f3d`;
  pre-flight revízió 2026-08-11, mért `main` HEAD `172d2621` — ld. §0.0)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 3; §10.5 (ez a kör), §24.6 (R21 kontextus, NEM ennek a körnek a scope-ja)
- **Branch:** `codex/e06-r03-codec-schema-and-legacy-adapter`
- **Előfeltétel:** **E06-R02 merge** (teljesült, `68a24c25`)
- **Brief szerzője:** Claude (batch) · **Pre-flight revízió + [ADR 0221](../adr/0221-legacy-analysis-v2-migration-mapping.md):** Claude Sonnet 5 (orchesztrátor) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/data/analysis_document_codec.dart",
  "lib/features/audio_analysis/data/legacy_analyze_adapter.dart",
  "lib/features/audio_analysis/data/legacy_view_adapter.dart",
  "lib/features/audio_analysis/domain/signal_quality_report.dart",
  "lib/features/audio_analysis/public.dart",
  "test/features/audio_analysis/data/analysis_document_codec_test.dart",
  "test/features/audio_analysis/data/legacy_analyze_adapter_test.dart",
  "test/features/audio_analysis/domain/signal_quality_report_test.dart",
  "test/fixtures/analysis/legacy_session_v1.json",
  "test/fixtures/analysis/legacy_session_pre_bpb.json",
  "test/fixtures/analysis/legacy_session_lab_diag.json",
  "test/property/analysis_codec_property_test.dart",
  "docs/rounds/e06-r03-codec-schema-and-legacy-adapter.md",
  "docs/adr/0221-legacy-analysis-v2-migration-mapping.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/property",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R02 merge. Olvasd újra
> `lib/features/analyze/model/analyze_result.dart` és
> `lib/features/library/model/analyzed_session.dart` **mai** `toJson`/`fromJson`
> alakját (a batch idején: `duration`, `bpm`, `chords`, `strums`, `bpb`,
> opcionális `diag`; a session szinten `id`, `createdAt`, `title`, `result`,
> `customTitle`) — a legacy fixture-öket ebből kell generálni, nem kézzel
> kitalálni. PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED → PLANNING (R1 revízió, 2026-08-11, orchesztrátor pre-flight,
mért `main` HEAD `172d2621`).**

### R1 — ADR-átszámozás (mért, pipeline-prompt §1)

A brief 2026-08-07-i megírásakor az E06-R01 hat ADR-jét még nem foglalták le,
ezért a `0200` (verziózás) és `0203` (metric verzió) placeholder-számokat
idézte. A tényleges `reserve-adr` futás **0215–0220**-at adta (lásd
[ADR 0215](../adr/0215-analysis-document-versioning.md) fejléce és
`HANDOFF.md` E06-R01/R02 close-out banner). Leképezés: `0200→0215`
(dokumentum-verziózás), `0203→0218` (metric ID + verzió). A brief minden
hivatkozása javítva lentebb.

### R2 — a brief SDD-alapú feltételezése eltér az R02 TÉNYLEGES domainjétől
— **új ADR 0221** (mért, pipeline-prompt §1: „amit nem találsz meg a
kódban, §0.0 revízióval old fel")

A brief 2026-08-07-én íródott, amikor `lib/features/audio_analysis/domain/`
még nem létezett — az SDD Ch7 §9/§10.5 idealizált leírására épített. Az
E06-R02 (mai nap, `172d2621`-ig merge-elve) a TÉNYLEGES domain modellt
szállította, és öt ponton szűkebben zárt, mint amit ez a brief (§5 Döntés
2-4, §6 acceptance) feltételezett — grep-elve:

1. `AnalysisMetricId.known` **zárt, négyelemű** halmaz
   (`analysis_metric_catalog.dart:5-20`), egyik sem legacy-specifikus;
   `AnalysisMetricResult` fail-closed dob rá nem katalogizált ID-re
   (`analysis_metric.dart:92`). A `tempo.legacy_bpm.v1`/
   `harmony.legacy_chord_summary.v1` egyike sincs benne.
2. `AnalysisInputSource` (`analysis_mode.dart:5-10`) nem hordoz
   `legacyMigration` értéket.
3. `AnalysisDocument`-nek nincs cím-jellegű mezője; a V1 `customTitle`
   valójában **bool** (`analyzed_session.dart:14-25`, nem string!), a
   ténylegesen megőrzendő adat a `title` (String) + `customTitle` (bool)
   pár.
4. Nincs metre/time-signature mező sehol a V2 domainben (a `bpb` megőrzését
   előíró (b) acceptance-cella eredeti szövege ezt hallgatólagosan
   feltételezte).
5. `SignalQualityReport` mind a hét mezője kötelező, fail-closed
   véges/tartomány-ellenőrzött, és `AnalysisDocument.signalQuality` nem
   nullable (`signal_quality_report.dart:4-39`) — a V1 egyetlen idevágó
   adatot sem tárol.

A teljes mérés, indoklás és a választott leképezés **[ADR
0221](../adr/0221-legacy-analysis-v2-migration-mapping.md)**-ben — ez az új
ADR, amit ez a pre-flight írt (a kör-tábla „Előre kiosztott ADR: nincs — te
írod meg" mezője szerint), a brief §9 STOP-klauzulájának („ha új
`CapabilityUnavailableReason` érték kellene: megállás és jelentés,
brief-revízió az R02 fájllistájának bevonásáról, nem néma enum-bővítés")
elvét alkalmazza mind az öt mért esetre. Rövid összefoglaló (a teljes
indoklás az ADR-ben):

- **BPM → `AnalysisTimeline.tempoPoints`** egyetlen `TempoPoint(time:
  Duration.zero, bpm: …)` bejegyzése, NEM metrika; migrált dokumentumon
  `metrics: []`.
- **Chord/strum → a meglévő `chordSegments`/`events` (StrumEvent)**,
  változatlanul (ez már eddig is így volt tervezve).
- **`source = AnalysisInputSource.importedFile`** (legközelebbi meglévő
  érték) + **`sampleRate = 44100`, `channelCount = 1`** (mért, historikusan
  rögzített capture-formátum, ugyanaz, mint az R02 saját teszt-konvenciója)
  + **`fingerprint`** determinisztikus, session-ID-ből származtatott,
  dokumentáltan NEM audio-tartalom hash.
- **`mode = AnalysisMode.freePlay`** minden migrált dokumentumra.
- **A migráció ténye + a legacy `beatsPerBar` egy `AnalysisWarning(kind:
  migration, …, messageArgs: {'beatsPerBar': …})`-on él** — a
  `LegacyViewAdapter` ebből olvassa vissza a kör-trip mezőt (nem-migrált
  dokumentumon a warning hiányozhat → `beatsPerBar` alapérték 4).
- **`title`/`customTitle`/Lab `diag`**: a `LegacyAnalyzeAdapter` egy
  adapter-lokális kísérő típusban adja vissza az `AnalysisDocument` MELLETT,
  nem abban.
- **`CapabilityUnavailableReason.modelUnavailable`** a kijelölt „legközelebbi
  meglévő ok" minden migrációból eredő `unavailable` capabilityre.
- **A `capabilities` lista mind a 14 értéket lefedi**: `chordTimeline`,
  `strumDirection`, `onsetTimeline` → `available`; a többi 11 →
  `unavailable`/`modelUnavailable`.
- **`SignalQualityReport` additív bővítés: `measured` bool, default
  `true`** — az EGYETLEN R02 domain-fájl módosítás ebben a körben
  (`signal_quality_report.dart` + új teszt, mindkettő felvéve az
  `allowed_paths`-ra fent), mert a V1 adatban semmi nem táplálhatja a hét
  kötelező mezőt, és egy néma találgatás (pl. `silentRatio: 1.0`) ellentmondana
  a dokumentum saját, nem-üres chord/strum-adatának. Migrált dokumentumon
  `measured: false` + kísérő `AnalysisWarning(kind: migration, …)`.

§5 (Kötött architekturális döntések) és §6 (Acceptance criteria) lentebb a
fenti leképezés szerint frissítve; a §6.1 mérce-mátrix egy sora szintúgy. A
codec (`AnalysisDocumentCodec.encode/decode`, schemaVersion-mátrix,
NaN-mátrix, bájtazonos encode) ettől a revíziótól **érintetlen** — kizárólag
`AnalysisDocument`-et (de)szerializál, aminek a mezőkészlete nem változott.

### R3 — §2 „Jelenlegi állapot" újra mérve

A V1 forrásalak (`lib/features/analyze/model/analyze_result.dart:113-198`,
`lib/features/library/model/analyzed_session.dart:8-55`) újra grep-elve
**egyezik** a brief eredeti §2 leírásával — nincs további revízió.

## 1. Cél

A V2 dokumentum **determinisztikus, verziózott szerializációja**, és a mai
`AnalyzeResult` → V2 **veszteségmentes** adaptere, hogy a Library minden
meglévő mentett sessionje V2-ként is olvasható legyen — **kitalált mérés
nélkül**.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- A mai szerializáció **kulcsai** (`analyze_result.dart` 168–197. sor):
  `duration`, `bpm`, `chords[{label,start,end}]`, `strums[{dir,time,conf}]`,
  `bpb` (round 118 óta, korábbi rekordokra `optionalInt` default 4),
  opcionális `diag{mlChords,agreement}` (csak Lab módban).
  `AnalyzedSession.toJson`: `id`, `createdAt` (ISO-8601), `title`, `result`,
  `customTitle`.
- Bounds: `maxTimelineChords = 5000`, `maxTimelineStrums = 20000` —
  a `requireList(maxLength:)` ezekkel véd.
- `AnalyzeResult.fromJson` **dob** (`JsonRecordException`) hiányzó `label`,
  ismeretlen `dir`, negatív `duration` esetén; a `JsonCollectionStore` egyetlen
  hibás rekordot **kihagy**, a többit betölti (`analyzed_session.dart` 46–54).
- **Nincs** `schemaVersion` sehol a mentett analízisben.
- `test/fixtures/` ma: `audio/`, `practice/`, `song_trainer/`, `vision/`,
  `*_parity.json` — **nincs** `analysis/` alkönyvtár.
- A V2 domain az R02-ből: `Duration` alapú idő, sealed metric value, katalógus.

## 3. Scope

**Benne:** `AnalysisDocumentCodec` (`encode`/`decode`, explicit
`schemaVersion`, ismeretlen kötelező enum → **kontrollált failure**, ismeretlen
**opcionális** mező → figyelmen kívül hagyás backward-compatible módon);
`LegacyAnalyzeAdapter` (V1 `AnalyzeResult` + `AnalyzedSession` → V2
`AnalysisDocument`); `LegacyViewAdapter` (V2 → a mai `AnalyzeResult` alak,
hogy a jelenlegi UI változtatás nélkül tudjon V2 dokumentumot renderelni);
három legacy JSON fixture; property-teszt a round-tripre.

**Kívül — TILOS:** repository/persistence (R21), a mai Library **tényleges**
migrációja (R21), pipeline (R04), bármely számítás, `lib/features/analyze/**`
és `lib/features/library/**` módosítása.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../data/analysis_document_codec.dart` | ÚJ | verziózott JSON codec |
| `.../data/legacy_analyze_adapter.dart` | ÚJ | V1 → V2 (+ adapter-lokális kísérő típus title/customTitle/diag-hoz, ld. §0.0 R2) |
| `.../data/legacy_view_adapter.dart` | ÚJ | V2 → mai UI-alak |
| `.../domain/signal_quality_report.dart` | **meglévő (R02) — additív bővítés** | `measured` bool, default `true` (ADR 0221 Döntés 9). EGYETLEN R02 domain-fájl, amit ez a kör érint. |
| `.../public.dart` | meglévő | a két adapter exportja |
| `test/features/audio_analysis/data/*` | ÚJ | codec + adapter tesztek |
| `test/features/audio_analysis/domain/signal_quality_report_test.dart` | ÚJ | a `measured` flag tesztje |
| `test/fixtures/analysis/*.json` | ÚJ | három legacy fixture |
| `test/property/analysis_codec_property_test.dart` | ÚJ | round-trip + NaN property |
| `docs/rounds/e06-r03-…md` | meglévő | §10 handoff |
| `docs/adr/0221-legacy-analysis-v2-migration-mapping.md` | ÚJ (pre-flight) | a §0.0 R2 leképezés indoklása |

**Tilos zóna:** `lib/features/analyze/**`, `lib/features/library/**`,
`lib/core/storage/**`, `assets/**`, és `lib/features/audio_analysis/domain/**`
**a `signal_quality_report.dart` kivételével** (az is csak additívan — ld.
ADR 0221 Döntés 9 és "NEM elfogadható"). Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Fail-closed a kötelezőre, fail-open az opcionálisra** (ADR 0215):
   ismeretlen `schemaVersion`, ismeretlen **kötelező** enum érték, hiányzó
   kötelező mező → `Failure(AppFailure)`; ismeretlen **extra** JSON-mező →
   figyelmen kívül. **NEM elfogadható:** ismeretlen séma esetén „best effort"
   dekódolás, és **NEM elfogadható** az extra mezőre dobás.
2. **Az adapter semmit nem talál ki** (SDD §10.5, ADR 0221 Döntés 7-8): a
   V1-ből hiányzó V2 capabilityk (`signalQuality`, `beatGrid`, `tempoCurve`,
   `timingAccuracy`, `dynamicConsistency`, `monophonicPitch`, `intonation`,
   `noteStability`, `transitionSmoothness`, `targetAlignment`,
   `sectionComparison`) **`unavailable`** státuszt kapnak
   `CapabilityUnavailableReason.modelUnavailable`-lel (ez a kijelölt
   „legközelebbi meglévő ok" — nincs `legacyDocument` az R02 enumjában, új
   enum érték felvétele **scope-sértés** lenne), `details`-ben
   `{'legacyMigration': 'true'}`-szerű jelöléssel. `chordTimeline`,
   `strumDirection`, `onsetTimeline` → **`available`** (a 3. pont adatai
   teljesek, veszteségmentesek — ld. ADR 0221 Döntés 2/8). **NEM
   elfogadható:** BPM-ből származtatott „tempóstabilitás" vagy strum-számból
   becsült „timing" a migrált dokumentumban.
3. **A BPM legacy timeline-adatként él tovább, NEM metrikaként** (ADR 0221
   Döntés 1, felülírja az eredeti `tempo.legacy_bpm.v1` tervet — az R02
   metrika-katalógus zárt, négyelemű, egyik ID sem legacy-specifikus, és az
   R02 saját 4. kötött döntése tiltja a katalóguson kívüli string ID-t):
   egyetlen `TempoPoint(time: Duration.zero, bpm: …)` az
   `AnalysisTimeline.tempoPoints`-ban; a migrált dokumentum `metrics` listája
   **üres**. **NEM elfogadható:** bármilyen `AnalysisMetricResult` a migrált
   dokumentumban (a négy meglévő katalógus-ID egyike sem alkalmazható
   kitalálás nélkül legacy adatra); a legacy BPM `higher is better` jelölése.
4. **Provenance/warning jelöli az eredetet** (ADR 0221 Döntés 3/5, felülírja
   az eredeti „`source = legacyMigration`" tervet — nincs ilyen enumérték):
   `AnalysisInputSummary.source = AnalysisInputSource.importedFile`
   (legközelebbi meglévő érték), `sampleRate = 44100`, `channelCount = 1`
   (mért capture-formátum), determinisztikus, NEM audio-tartalom
   `fingerprint`; egy dedikált `AnalysisWarning(kind: migration, …,
   messageArgs: {'beatsPerBar': …})` jelzi a migráció tényét és hordozza a
   legacy metrét (nincs metre-mező a V2 domainben); `mode =
   AnalysisMode.freePlay`. A dokumentum megőrzi a session `id`-t
   (`AnalysisDocument.id`) és `createdAt`-ot közvetlenül; a `title` (String)
   + `customTitle` (**bool**, nem string — mérve `analyzed_session.dart:14-25`)
   az `AnalysisDocument` MELLETT, egy adapter-lokális kísérő típusban tér
   vissza (nincs V2 mező rájuk). **NEM elfogadható:** új ID generálása
   migrációkor.
5. **A Lab `diag` mező NEM az `AnalysisDocument` része** (ADR 0221 Döntés 6,
   felülírja az eredeti „provenance/diagnostics ágba kerül" tervet — az
   `AnalysisProvenance` zárt, fix mezőkészlet, nincs szabad bag): ugyanabban
   az adapter-lokális kísérő típusban tér vissza, mint a `title`/
   `customTitle`. A publikus metrikák közt (`AnalysisDocument.metrics`)
   **nincs** ML-eredmény.
6. **`SignalQualityReport` additív `measured` bool, default `true`** (ADR
   0221 Döntés 9): migrált dokumentumon `measured: false` +
   `AnalysisDocument.signalQuality` egy érvényes (de nem valós méréshez
   köthető, dokumentáltan placeholder) `SignalQualityReport` + kísérő
   `AnalysisWarning(kind: migration, …)`. **NEM elfogadható:** `measured`
   jelzés nélküli fabrikált numerikus érték.
7. **Determinizmus:** ugyanaz a dokumentum kétszer kódolva **bájtazonos**
   JSON-t ad (kulcsrendezés rögzített). **NEM elfogadható:** `Map` iterációs
   sorrendre hagyatkozás.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: A codec dobjon, vagy AppResult-ot adjon?
    blocking: true
    resolution_policy: use_default
    default: >-
      `AppResult<AnalysisDocument>` a decode-on (a határ typed failure-t ad,
      R02 §5.1 OD-01), az encode nem hibázhat (a domain már validált).
  - id: OD-02
    question: Mi legyen a V2 schemaVersion kezdőértéke?
    blocking: false
    resolution_policy: use_default
    default: 1 — és a codec elutasít minden 1-nél nagyobb és 1-nél kisebb értéket.
```

## 6. Acceptance criteria

- [ ] **Round-trip:** `decode(encode(doc)) == doc` **minden** mezőre, beleértve
      az üres listákat, a `null` opcionálisokat és a `Duration` mikroszekundum
      pontosságát (1 µs-os érték is túléli).
- [ ] **Bájtazonos encode:** ugyanazt a dokumentumot kétszer kódolva a két
      string **azonos** (`identical` string-összehasonlítás nem elég —
      `==` a teljes JSON-szövegre).
- [ ] **`schemaVersion` mátrix:** `0` / `1` / `2` / hiányzó / nem-szám — a `1`
      az egyetlen elfogadott, a többi négy `Failure`, mindegyik saját cella.
- [ ] **Ismeretlen enum mátrix:** ismeretlen **kötelező** enum (pl.
      `completion`) → `Failure`; ismeretlen **extra** top-level mező
      (`"futureField": 1`) → **Success**, a mező elhagyva. Mindkettő saját cella.
- [ ] **NaN/Infinity mátrix:** `NaN`, `+Infinity`, `-Infinity` bemenet a
      `confidence` és a `value` mezőn → mind a hat cella `Failure`; és a
      property-teszt méri, hogy **kimenetbe soha nem jut** nem véges szám.
- [ ] **Legacy fixture mátrix — három fájl:** (a) `legacy_session_v1.json`
      teljes mai alak; (b) `legacy_session_pre_bpb.json` `bpb` **nélkül** →
      a migrált dokumentum `AnalysisWarning(kind: migration)`
      `messageArgs['beatsPerBar']` értéke `'4'`; (c) `legacy_session_lab_diag.json`
      `diag`-gal → a Lab-diagnosztika az adapter-lokális kísérő típusban van
      (ADR 0221 Döntés 6), a publikus `AnalysisDocument.metrics`/`.timeline`
      közt **nincs** ML-eredmény.
- [ ] **Veszteségmentesség:** mindhárom fixture-re a migrált dokumentum
      chord-szegmensei és strum-eseményei **darabszámra és időre** egyeznek a
      V1 értékekkel (a `Duration` mikroszekundumra kerekítve, dokumentált
      toleranciával: |Δ| ≤ 1 µs), a `tempoPoints[0].bpm` egyezik a V1
      `bpm`-mel, és a `title`/`customTitle`/`id`/`createdAt` bitre megmarad
      (az adapter-lokális kísérő típuson, ill. `AnalysisDocument.id`/
      `.createdAt`-on).
- [ ] **Nincs kitalált mérés:** teszt méri, hogy a migrált dokumentumban a
      `signalQuality`/`beatGrid`/`tempoCurve`/`timingAccuracy`/
      `dynamicConsistency`/`monophonicPitch`/`intonation`/`noteStability`/
      `transitionSmoothness`/`targetAlignment`/`sectionComparison`
      capabilityk **mind** `unavailable` (reason `modelUnavailable`)
      státuszúak, `chordTimeline`/`strumDirection`/`onsetTimeline` `available`,
      és a `metrics` lista **üres** (ADR 0221 Döntés 1/7/8).
- [ ] **Oda-vissza az UI felé:** `LegacyViewAdapter.toAnalyzeResult(migrált)`
      a **kiinduló** `AnalyzeResult`-tal egyező `chords`/`strums`/`bpm`
      (`tempoPoints[0].bpm`-ből)/`durationSec`/`beatsPerBar`
      (`AnalysisWarning(kind: migration)` `messageArgs['beatsPerBar']`-ból,
      hiányzó warning esetén alapérték 4) értékeket ad.
- [ ] **`SignalQualityReport.measured`:** migrált dokumentumon `false` +
      legalább egy `AnalysisWarning(kind: migration)`; egy nem-migrált,
      kézzel épített `SignalQualityReport` (implementer teszt) `measured`
      alapértéke `true` marad módosítás nélkül (R02 teszt-suite zöld marad).
- [ ] **V1 érintetlen:** `git diff --stat` nem tartalmaz
      `lib/features/analyze/**` vagy `lib/features/library/**` útvonalat.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A decode ismeretlen `schemaVersion`-t is elfogad | a `schemaVersion = 2` **Failure**-cella |
| A decode extra mezőre dob | az `"futureField"` **Success**-cella |
| Az encode `Map` iterációs sorrendre hagyatkozik | a bájtazonos-encode cella |
| Az adapter a BPM-ből tempóstabilitást számol, vagy bármit betesz a `metrics` listába | a „nincs kitalált mérés" cella (`metrics` üres) |
| Az adapter `analysis_metric_catalog.dart`-on kívüli/nem katalogizált metrika-ID-t próbál létrehozni | `AnalysisMetricResult` konstruktor `ArgumentError` (fail-closed, nem elkapható csendben) |
| `SignalQualityReport measured: false` jelzés nélkül, kísérő warning nélkül | a `SignalQualityReport.measured` cella |
| Az adapter új session ID-t generál | a `id`/`createdAt` megőrzés cella |
| A `Duration` másodpercként szerializálódik | az 1 µs-os round-trip cella |
| A NaN a `confidence`-en átmegy | a NaN-mátrix cella + property-teszt |
| A `bpb` hiánya 0-ra migrálódik 4 helyett | a `legacy_session_pre_bpb.json` `messageArgs['beatsPerBar']` cellája |
| **Valódi-sértés próba (§10):** a `schemaVersion`-ellenőrzés ideiglenes kikommentelése → a `schemaVersion = 2` teszt **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/property test/features/analyze test/features/library
```

Külön processzek, nincs `&&`/pipe/`tail`. A property-teszt a
`PROPERTY_SEED` konvenciót követi (hiányzó env → 42).

## 8. Implementációs sorrend

1. A három legacy fixture generálása a **mai** `toJson`-ból (nem kézzel).
2. RED: schemaVersion-, enum-, NaN- és fixture-mátrix.
3. `AnalysisDocumentCodec` (rendezett kulcsok, typed failure).
4. `LegacyAnalyzeAdapter` + `LegacyViewAdapter`.
5. Property-teszt (round-trip, NaN-mentesség).
6. Gate.

## 9. Kockázatok

- **A fixture kézzel írása** csendes eltérést hoz a valós mentett alakhoz
  képest → a §8.1 kimondja: a fixture a mai `toJson` kimenete.
- **A `Duration` kerekítés** másodperc→mikroszekundum átváltáskor
  ±1 µs-os eltérést okozhat; ezt a brief toleranciaként rögzíti, és a teszt
  erre mér — **nem** a tolerancia utólagos tágításával.
- **A `public.dart` bővítése** a cross-feature határ; csak a két adapter és a
  codec kerülhet ki, a belső JSON-helperek nem.

**STOP:** ha a veszteségmentes migrációhoz új `CapabilityUnavailableReason`
érték (vagy bármely további, itt fel nem sorolt R02 domain-mező) kellene, az
**megállás és jelentés** (`tools/codex-signal.sh stopped`), nem néma
enum-bővítés vagy néma `allowed_paths`-on kívüli fájlírás. Ezt a klauzulát a
pre-flight már egyszer alkalmazta öt mért esetre — ld. §0.0 R2 és [ADR
0221](../adr/0221-legacy-analysis-v2-migration-mapping.md) —, az ott
rögzített leképezés a KÖTELEZŐ út, nem csak egy javaslat. Ha az implementálás
közben egy HATODIK, itt nem szereplő R02-hiányt találsz, ugyanez a protokoll:
jelezz, ne told át a scope-ot magadtól.

## 10. Implementation handoff — az implementer tölti ki

**Implementer: Terra (Codex, `gpt-5.6-terra`), 1 forduló (0 automatikus
folytatás), javító kör nélkül.** Session `019ff095-a56a-7671-9b05-2f89b86877c3`.
Két commit: `c3aae562` (codec + migrációs tesztek indítása), `a103724e`
(V1/V2 adapterek befejezése). A branch HEAD-je a merge előtt: `a103724e`.

- `AnalysisDocumentCodec` — fail-closed `schemaVersion`, rögzített kulcssorrendű
  `Map`-literál minden JSON-objektumhoz (determinisztikus encode), `_ensureFiniteJson`
  encode előtt (NaN/Infinity sosem jut kimenetbe).
- `LegacyAnalyzeAdapter.adapt(AnalyzedSession)` → `LegacyAnalysisMigration
  {document, title, customTitle, diagnostics?}` — pontosan az ADR 0221 Döntés
  1-9 szerint: `tempoPoints` a BPM-nek, `chordSegments`/`StrumEvent` a
  chord/strum adatnak (`ChordSegment.confidence` fixen 1), egyetlen
  `AnalysisWarning(kind: migration)` a metrének (`messageArgs['beatsPerBar']`)
  és a migráció tényének, `capabilities` mind a 14 értékre (3 `available`, 11
  `unavailable`/`modelUnavailable`), `SignalQualityReport(measured: false)`
  nulla-placeholder mezőkkel, `metrics: []`, `mode: freePlay`, `source:
  importedFile`, `fingerprint: 'legacy-session:<id>'`.
- `LegacyViewAdapter.toAnalyzeResult(AnalysisDocument)` — visszaolvassa a
  `tempoPoints.first.bpm`-et (üres lista → 0), a `chordSegments`/`StrumEvent`-eket,
  és a `beatsPerBar`-t a migration-warningből (hiányzó/érvénytelen → 4).
- `signal_quality_report.dart` — kizárólag additív: egy új, opcionális
  `measured` bool paraméter, default `true`; egyetlen meglévő sor sem
  törölve/módosítva a mezőkön kívül.
- Három legacy fixture (`test/fixtures/analysis/*.json`) a mai
  `AnalyzeResult`/`AnalyzedSession` alak szerint.
- Futtatott parancsok, TÉNYLEGES kimenettel: `tools/round-gate.sh
  test/features/audio_analysis test/property test/features/analyze
  test/features/library` — mind a 9 lépés zöld (`format`, `analyze`, négy
  `test <útvonal>`, `architecture`, `secrets`, `l10n`).
- Eltérés a brief-től: nincs.
- Nem futtatott ellenőrzés: CI (a teljes suite + property + a Router CI) —
  az orchesztrátor dolga a review-val párhuzamosan.
- Scope-audit: `ok`, a diff mind a 12 módosított fájl a §4 engedélyezett
  listáján belül (függetlenül újra mérve: `git diff --name-status
  59aa9424..a103724e`, nulla eltérés).

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r03-codec-schema-and-legacy-adapter-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
