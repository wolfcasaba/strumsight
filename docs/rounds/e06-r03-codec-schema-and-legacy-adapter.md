# E06-R03 — Codec, schema validation és V1 adapter

- **Státusz:** PREPARED (előre megírva 2026-08-07, kód olvasva: main @ `a6e6f3d`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 3; §10.5, §24.6
- **Branch:** `codex/e06-r03-codec-schema-and-legacy-adapter`
- **Előfeltétel:** **E06-R02 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/data/analysis_document_codec.dart",
  "lib/features/audio_analysis/data/legacy_analyze_adapter.dart",
  "lib/features/audio_analysis/data/legacy_view_adapter.dart",
  "lib/features/audio_analysis/public.dart",
  "test/features/audio_analysis/data/analysis_document_codec_test.dart",
  "test/features/audio_analysis/data/legacy_analyze_adapter_test.dart",
  "test/fixtures/analysis/legacy_session_v1.json",
  "test/fixtures/analysis/legacy_session_pre_bpb.json",
  "test/fixtures/analysis/legacy_session_lab_diag.json",
  "test/property/analysis_codec_property_test.dart",
  "docs/rounds/e06-r03-codec-schema-and-legacy-adapter.md",
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

**PREPARED.** Új ADR nincs — az R01 ADR 0200 (verziózás, ismeretlen séma =
kontrollált failure) és 0203 (metric verzió) végrehajtása.

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
| `.../data/legacy_analyze_adapter.dart` | ÚJ | V1 → V2 |
| `.../data/legacy_view_adapter.dart` | ÚJ | V2 → mai UI-alak |
| `.../public.dart` | meglévő | a két adapter exportja |
| `test/features/audio_analysis/data/*` | ÚJ | codec + adapter tesztek |
| `test/fixtures/analysis/*.json` | ÚJ | három legacy fixture |
| `test/property/analysis_codec_property_test.dart` | ÚJ | round-trip + NaN property |
| `docs/rounds/e06-r03-…md` | meglévő | §10 handoff |

**Tilos zóna:** `lib/features/analyze/**`, `lib/features/library/**`,
`lib/core/storage/**`, `assets/**`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Fail-closed a kötelezőre, fail-open az opcionálisra** (ADR 0200):
   ismeretlen `schemaVersion`, ismeretlen **kötelező** enum érték, hiányzó
   kötelező mező → `Failure(AppFailure)`; ismeretlen **extra** JSON-mező →
   figyelmen kívül. **NEM elfogadható:** ismeretlen séma esetén „best effort"
   dekódolás, és **NEM elfogadható** az extra mezőre dobás.
2. **Az adapter semmit nem talál ki** (SDD §10.5): a V1-ből hiányzó V2
   metrikák **`unavailable`** státuszt kapnak
   `CapabilityUnavailableReason.legacyDocument`-tel (ha ilyen ok nincs az R02
   enumjában, a **legközelebbi** meglévő ok + `details` magyarázat — új enum
   érték felvétele az R02 fájljába **scope-sértés**). **NEM elfogadható:**
   BPM-ből származtatott „tempóstabilitás" vagy strum-számból becsült
   „timing" a migrált dokumentumban.
3. **A BPM legacy metrikaként él tovább:** `tempo.legacy_bpm.v1`, `descriptive`
   irányultsággal (ADR 0203). **NEM elfogadható:** a legacy BPM
   `higher is better` jelölése.
4. **Provenance jelöli az eredetet:** `source = legacyMigration`, és megőrzi a
   session `id`-t, `createdAt`-ot, `customTitle`-t. **NEM elfogadható:** új ID
   generálása migrációkor.
5. **A Lab `diag` mező a provenance/diagnostics ágba kerül**, nem a publikus
   metrikák közé.
6. **Determinizmus:** ugyanaz a dokumentum kétszer kódolva **bájtazonos**
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
      a migrált dokumentum metre-je 4/4 és ezt provenance jelöli;
      (c) `legacy_session_lab_diag.json` `diag`-gal → a diagnosztika a
      provenance ágban van, a publikus metrikák közt **nincs** ML-eredmény.
- [ ] **Veszteségmentesség:** mindhárom fixture-re a migrált dokumentum
      chord-szegmensei és strum-eseményei **darabszámra és időre** egyeznek a
      V1 értékekkel (a `Duration` mikroszekundumra kerekítve, dokumentált
      toleranciával: |Δ| ≤ 1 µs), és a `customTitle`/`id`/`createdAt` bitre
      megmarad.
- [ ] **Nincs kitalált mérés:** teszt méri, hogy a migrált dokumentumban a
      timing/dynamics/pitch capabilityk **mind** `unavailable` státuszúak, és
      a `metrics` lista **kizárólag** legacy ID-ket (`tempo.legacy_bpm.v1`,
      `harmony.legacy_chord_summary.v1`) tartalmaz.
- [ ] **Oda-vissza az UI felé:** `LegacyViewAdapter.toAnalyzeResult(migrált)`
      a **kiinduló** `AnalyzeResult`-tal egyező `chords`/`strums`/`bpm`/
      `durationSec`/`beatsPerBar` értékeket ad.
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
| Az adapter a BPM-ből tempóstabilitást számol | a „nincs kitalált mérés" cella (metrics-lista csak legacy ID) |
| Az adapter új session ID-t generál | a `id`/`createdAt` megőrzés cella |
| A `Duration` másodpercként szerializálódik | az 1 µs-os round-trip cella |
| A NaN a `confidence`-en átmegy | a NaN-mátrix cella + property-teszt |
| A `bpb` hiánya 0-ra migrálódik 4 helyett | a `legacy_session_pre_bpb.json` metre-cellája |
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
érték kellene, az **megállás és jelentés** (brief-revízió az R02 fájllistájának
bevonásáról), nem néma enum-bővítés.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r03-codec-schema-and-legacy-adapter-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
