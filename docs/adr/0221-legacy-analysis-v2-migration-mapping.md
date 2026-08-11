# ADR 0221 — Legacy Analyze/Library → Audio Analysis V2 migrációs leképezés

- **Státusz:** Elfogadva (E06-R03 pre-flight, 2026-08-11)
- **Kör:** E06-R03 — Codec, schema validation és V1 adapter
- **Implementer motor:** Terra — az ADR-t az orchesztrátor (Claude Sonnet 5)
  írta a pre-flightban (ADR 0055).
- **Epic:** [Chapter 7 — Epic 6: Audio Analysis 2.0](../sdd/07-epic-06-audio-analysis-2.md)
  Kör 3; §10.5 (Migráció), §9 (Fő domain modellek)
- **Kontext-ADR-ek:** [0215](0215-analysis-document-versioning.md)
  (dokumentum-verziózás), [0216](0216-analysis-confidence-calibration-and-abstention.md)
  (confidence kalibráció/abstention), [0217](0217-analysis-raw-audio-retention.md)
  (nyers audio retention), [0218](0218-analysis-metric-id-and-version-governance.md)
  (metric ID + verzió kormányzás — ez az ADR annak határát méri és tartja be),
  [0219](0219-analysis-capability-aware-publication.md) (capability-aware
  publikáció), [0220](0220-audio-analysis-v2-parallel-rollout-boundary.md)
  (V1/V2 rollout határ)

## Kontextus

**Mért 2026-08-11-én, `main` HEAD `172d2621` (E06-R02 merge után):**

1. A brief 2026-08-07-én íródott, amikor `lib/features/audio_analysis/domain/`
   még nem létezett — az SDD Ch7 §9/§10.5 IDEALIZÁLT leírására épített. Az
   E06-R02 (`172d2621`-ig merge-elve) a TÉNYLEGES domain modellt szállította,
   és öt ponton szűkebben zárt, mint amit az SDD/brief feltételezett:
   - [`analysis_metric_catalog.dart:5-20`](../../lib/features/audio_analysis/domain/analysis_metric_catalog.dart) —
     `AnalysisMetricId.known` ZÁRT, NÉGY elemű halmaz (`timing.mean_absolute_error.v1`,
     `rhythm.rush_drag_bias.v1`, `dynamics.strum_consistency.v1`,
     `harmony.chord_coverage.v1`); egyik sem legacy-specifikus.
     `AnalysisMetricResult` konstruktora
     ([`analysis_metric.dart:92`](../../lib/features/audio_analysis/domain/analysis_metric.dart))
     fail-closed dob, ha `id` nincs a katalógusban. Az R02 brief saját 4.
     Kötött döntése
     ([`docs/rounds/e06-r02-analysis-document-v2-domain.md` §5](../rounds/e06-r02-analysis-document-v2-domain.md)):
     „Metric ID csak a katalógusból… NEM elfogadható: string literál a
     metrika létrehozási helyén." Az E06-R03 brief §5 Döntés 3 ugyanakkor egy
     `tempo.legacy_bpm.v1` és egy `harmony.legacy_chord_summary.v1` metrikát
     irányzott elő — egyik sincs a katalógusban, és felvételük egy, az
     `allowed_paths`-on kívüli R02 domain-fájl módosítását igényelné.
   - [`analysis_mode.dart:5-10`](../../lib/features/audio_analysis/domain/analysis_mode.dart) —
     `AnalysisInputSource { microphone, importedFile, practiceSession,
     songSession }`. Nincs `legacyMigration` érték, pedig az SDD §10.5 és a
     brief §5 Döntés 4 kifejezetten ezt írja elő.
   - [`analysis_capability.dart:21-35`](../../lib/features/audio_analysis/domain/analysis_capability.dart) —
     `CapabilityUnavailableReason` 13 értéke között nincs legacy/migrációs ok;
     a brief ezt már előre látta (§5 Döntés 2 zárójele: „ha ilyen ok nincs, a
     legközelebbi meglévő ok + details").
   - [`analysis_document.dart:28-72`](../../lib/features/audio_analysis/domain/analysis_document.dart) —
     `AnalysisDocument`-nek nincs cím-jellegű mezője; a `title`/`customTitle`
     (utóbbi **bool**, ld.
     [`lib/features/library/model/analyzed_session.dart:14-25`](../../lib/features/library/model/analyzed_session.dart)
     — NEM string!) így nem fér el a dokumentumban. Ugyanígy nincs mező a
     Lab-mode `MlChordDiagnostics`-nak sem.
   - [`analysis_timeline.dart`](../../lib/features/audio_analysis/domain/analysis_timeline.dart)/[`analysis_provenance.dart`](../../lib/features/audio_analysis/domain/analysis_provenance.dart) —
     nincs metre/time-signature mező sehol (az SDD Ch14.4 a metre-becslést
     jövőbeli, flag mögötti DSP-képességként kezeli, nem statikus mezőként).
   - [`signal_quality_report.dart:4-39`](../../lib/features/audio_analysis/domain/signal_quality_report.dart) —
     `SignalQualityReport` mind a hét mezője **kötelező és fail-closed
     véges/tartomány-ellenőrzött**; `AnalysisDocument.signalQuality` NEM
     nullable. A V1 `AnalyzeResult`/`AnalyzedSession` egyetlen ehhez köthető
     adatot sem tárol (nincs peak/rms/noise-floor/clipping/silence/tonalness).
2. Mind az öt hiány közös gyökere ugyanaz: **a brief egy még nem létező
   domainre tervezett; az R02 tényleges implementációja egy szűkebb,
   konzervatívabb kezdő katalógust szállított.** A brief saját STOP-klauzulája
   (§9) ezt a helyzetet kifejezetten előre látta a `CapabilityUnavailableReason`
   esetére: „ha a veszteségmentes migrációhoz új `CapabilityUnavailableReason`
   érték kellene, az megállás és jelentés (brief-revízió az R02 fájllistájának
   bevonásáról), nem néma enum-bővítés." Ez az ADR ugyanezt az elvet
   alkalmazza a mért öt esetre, egységesen.
3. A V1 forrásalak újra-mérve
   ([`lib/features/analyze/model/analyze_result.dart:113-198`](../../lib/features/analyze/model/analyze_result.dart),
   [`lib/features/library/model/analyzed_session.dart:8-55`](../../lib/features/library/model/analyzed_session.dart))
   — egyezik a brief §2 leírásával, változatlan.
4. A rögzített capture-formátum: mono, 44100 Hz
   ([`lib/features/live/engine/dsp/dsp_config.dart:8`](../../lib/features/live/engine/dsp/dsp_config.dart),
   [`lib/features/analyze/engine/clip_recorder.dart:16`](../../lib/features/analyze/engine/clip_recorder.dart),
   [`lib/core/audio/capture/audio_capture_factory.dart:13`](../../lib/core/audio/capture/audio_capture_factory.dart)),
   és maga az R02 teszt-konvenció is ezt használja
   ([`test/features/audio_analysis/domain/analysis_document_test.dart`](../../test/features/audio_analysis/domain/analysis_document_test.dart)
   `_input()` helper: `sampleRate: 44100, channelCount: 1`).
5. `AnalysisDocument` konstruktora **nem kényszeríti ki** a `capabilities`
   lista teljességét (mérve: `analysis_document_test.dart` `_document()`
   helpere egyetlen `CapabilityReport`-tal is érvényes dokumentumot épít) —
   de az [ADR 0219](0219-analysis-capability-aware-publication.md) §Döntés
   3/4 „a capability-tengelyek függetlenek, teljes kép" elve a teljes 14-elemű
   lefedést várja el.

## Döntés

1. **A BPM nem metrika, hanem timeline-adat.** A migrált dokumentum a legacy
   BPM-et egyetlen `TempoPoint(time: Duration.zero, bpm: <érték>)`
   bejegyzésként hordozza az `AnalysisTimeline.tempoPoints`-ban — NEM az
   `AnalysisMetricResult`/`AnalysisMetricId` katalóguson keresztül. A migrált
   dokumentum `metrics` listája **üres**. Ez betartja az R02 „metric ID csak a
   katalógusból" szabályát változtatás nélkül, és elkerüli a „legacy BPM
   higher-is-better" félreértést (nincs metrika-szemantika, csak nyers
   adatpont).
2. **A chord/strum adat a meglévő timeline-szerkezeteken él**, ahogy az R02
   már biztosítja: `AnalysisTimeline.chordSegments`
   (`ChordSegment{start,end,confidence,label}`, `confidence` fixen **1.0** —
   a V1 nem tárolt per-szegmens confidence-t, az 1.0 „elfogadott történeti
   tény, nem fokozott becslés" jelentésű, dokumentálva) és
   `AnalysisTimeline.events` mint `StrumEvent` lista (`confidence` közvetlenül
   a V1 `conf` mezőből, `direction` 1:1 leképezés `down↔down, up↔up`, a V2
   `unknown` sosem fordul elő migrációból). A `StrumEvent`-ek időbélyegei
   önmagukban kielégítik az `onsetTimeline` capabilityt — nincs szükség
   külön, duplikált `OnsetEvent` listára.
3. **`AnalysisInputSummary.source = AnalysisInputSource.importedFile`**
   (legközelebbi meglévő érték — a V1 nem tárolja, hogy egy klip mikrofonról
   vagy fájlból származott, tehát bármely konkrét eredet-állítás kitalálás
   lenne; az „importedFile" a legkevésbé félrevezető, mert a migráció maga is
   egy előzőleg létező rekord „importja"). **`sampleRate = 44100`,
   `channelCount = 1`** — mért, historikusan rögzített capture-formátum
   (Kontextus 4. pont), nem becslés. **`fingerprint`** determinisztikus, NEM
   audio-tartalom hash — a legacy session ID-ból származtatott, dokumentáltan
   placeholder string (pl. `'legacy-session:<id>'`), mert a nyers audio nincs
   megőrizve (ADR 0217 default) és visszamenőleg nem hash-elhető.
4. **`AnalysisMode.freePlay`** minden migrált dokumentumra — a V1 Analyze
   funkciónak sosem volt practice-target vagy song-reference összevetése,
   tisztán szabad-játék elemzés volt.
5. **A migráció ténye és a legacy metre egy dedikált `AnalysisWarning`-on
   él**, nem provenance-mezőn (nincs ilyen mező): `AnalysisWarning(kind:
   AnalysisWarningKind.migration, severity: AnalysisWarningSeverity.info,
   messageKey: <stabil kulcs>, messageArgs: {'beatsPerBar': '<V1 bpb>'})`. Az
   `AnalysisWarningKind.migration` érték már létezik az R02 katalógusban
   kifejezetten erre a célra. A `LegacyViewAdapter` ebből az egy warningból
   olvassa vissza a `beatsPerBar`-t a kör-trip acceptance-hez — nincs másik
   hely, ahova a metre kerülhetne (Kontextus 1. pont, ötödik franciabekezdés).
   Nem-migrált (natív V2) dokumentumon a warning hiányozhat — a
   `LegacyViewAdapter` ilyenkor `beatsPerBar = 4` alapértékre esik vissza.
6. **A `title`/`customTitle` és — ha jelen van — a Lab-mode
   `MlChordDiagnostics` NEM kerül az `AnalysisDocument`-be**: egyik R02
   mezőben sincs helye (nincs cím-mező; az `AnalysisProvenance` zárt, fix
   mezőkészlet, nincs szabad „details" bag). A `LegacyAnalyzeAdapter`
   (`AnalyzedSession` bemenet esetén) egy adapter-lokális, a
   `legacy_analyze_adapter.dart` fájlban definiált kis kísérő típusban adja
   vissza mindhármat az `AnalysisDocument` MELLETT, nem abban.
   `AnalysisDocument.id`/`.createdAt` közvetlenül hordozza a session
   `id`/`createdAt` mezőit (ezeknek van V2 helyük). A Lab `diag` round-trip
   fidelitása NEM acceptance-kritérium (csak a „nincs a publikus metrikák
   közt" elhelyezés az).
7. **`CapabilityUnavailableReason.modelUnavailable`** a kijelölt „legközelebbi
   meglévő ok" minden migrációból eredő `unavailable` capabilityre (a brief
   §5 Döntés 2 által előre engedélyezett minta), `details`-ben
   `{'legacyMigration': 'true'}`-szerű jelöléssel, hogy megkülönböztethető
   legyen egy valódi futásidejű modell-betöltési hibától.
8. **A `capabilities` lista mind a 14 `AnalysisCapability` értéket lefedi**
   migrált dokumentumon (Kontextus 5. pont — a konstruktor nem kényszeríti
   ki, de az ADR 0219 elve elvárja). `chordTimeline`, `strumDirection`,
   `onsetTimeline` → `available` (a 2. pont adatai teljesek és
   veszteségmentesek). `signalQuality`, `beatGrid`, `tempoCurve`,
   `timingAccuracy`, `dynamicConsistency`, `monophonicPitch`, `intonation`,
   `noteStability`, `transitionSmoothness`, `targetAlignment`,
   `sectionComparison` → `unavailable`, reason `modelUnavailable` (7. pont).
9. **`SignalQualityReport` additív bővítése: `measured` bool, default
   `true`.** Ez az EGYETLEN R02 domain-fájl módosítás, amit ez a kör végez, és
   kizárólag a brief STOP-klauzulájának (§9) a `CapabilityUnavailableReason`-re
   írt elvét alkalmazza, kiterjesztve erre a mért, analóg esetre: a V1
   adatban **semmi** nem táplálhatja a hét kötelező, fail-closed
   véges/tartomány-ellenőrzött mezőt (peak/rms/noise-floor/clipping/silence/
   tonalness/overall), és bármely konkrét szám kitalált mérés lenne (a brief
   kifejezett tilalma) — egy néma, találgatott dBFS-érték ráadásul
   **ellentmondásba** kerülne a dokumentum saját chord/strum-adatával (pl.
   `silentRatio: 1.0` egy nem-üres chord-timeline mellett). A módosítás
   **kizárólag additív** (új, opcionális, `true` default paraméter — egyetlen
   meglévő hívási hely sem változik, az R02 teszt-suite módosítás nélkül zöld
   marad) — nem redesign, nem előlegezi meg az R07 (a tényleges DSP-alapú
   jelminőség-számítás) döntéseit. Migrált dokumentumon `measured: false` és
   egy kísérő `AnalysisWarning(kind: migration, …)` jelzi explicit módon a
   hiányt (ADR 0219 „soha nem csendes 0/N/A" elve).

## NEM elfogadható

- Bármilyen `AnalysisMetricResult` legacy adatból, ami NEM a meglévő négy
  katalógus-ID egyikét használja (R02 §5 Döntés 4 megsértése).
- `SignalQualityReport` fabrikált numerikus értékekkel **`measured` jelzés
  nélkül** — ez az ADR 0219 „soha nem csendes 0/N/A" elvét sértené egy
  required, non-nullable mezőn keresztül.
- Bármely új `CapabilityUnavailableReason`/`AnalysisInputSource` érték
  felvétele ebben a körben (a brief STOP-klauzulája és ez az ADR is a
  „legközelebbi meglévő érték" mintát írja elő, nem bővítést).
- A `signal_quality_report.dart`/`analysis_metric_catalog.dart`/
  `analysis_mode.dart`/`analysis_capability.dart` bármely NEM additív
  módosítása, vagy bármely meglévő R02-teszt viselkedésének megváltoztatása.

## Következmények

- Az E06-R03 `allowed_paths`-a **egyetlen** R02 domain-fájllal bővül
  (`signal_quality_report.dart` + a hozzá tartozó ÚJ teszt) — minden más
  legacy adat a meglévő timeline/warning szerkezeteken él, nincs más
  R02-fájl érintve.
- A `LegacyViewAdapter` (V2→V1 visszaút) a `tempoPoints[0].bpm`-ből és az
  `AnalysisWarning(kind: migration)` `messageArgs['beatsPerBar']`-jából
  állítja vissza a kör-trip mezőket — ez a kettő az egyetlen hely, ahonnan ez
  olvasható.
- Egy jövőbeli kör (R07, jelminőség-számítás; R21, tényleges
  Library-migráció), ha ÚJ metrika-ID-t, `AnalysisInputSource`-t vagy
  `CapabilityUnavailableReason`-t vezetne be, ezt saját, dedikált ADR-ként
  teheti — ez az ADR nem zárja le a katalógusokat, csak ennek a körnek a
  mértékét rögzíti.

## Elutasított alternatívák

- **Ad-hoc string literál metrika-ID a katalógus bővítése nélkül.** Elvetve:
  az `AnalysisMetricResult` konstruktora fail-closed dob rá — nem is
  fordulna.
- **A `analysis_metric_catalog.dart` bővítése két legacy ID-vel.** Elvetve:
  az R02 saját 4. kötött döntése kifejezetten a katalógus-only mintát írja
  elő minden jövőbeli, VALÓDI V2-natív metrikára; egy migrációs-only ID
  felvétele szennyezné ezt a governance-katalógust olyan bejegyzéssel, ami
  sosem lesz „valódi" V2 mérés (ADR 0218 hatóköre kívül esik ezen).
- **Fabrikált, „semleges" `SignalQualityReport`-számok (`measured` flag
  nélkül).** Elvetve: bármely dBFS-skálájú szám implicit, konkrét (és a
  chord/strum-adattal potenciálisan ellentmondó) állítás — egy 0 dBFS peak
  pl. TELJES KIVEZÉRLÉST állítana egy sosem mért klipre.
- **HALT és emberi döntésre várás.** Elvetve: a brief STOP-klauzulája
  kifejezetten a „brief-revízió, dokumentálva" utat írja elő erre a
  hibaosztályra, az orchesztrátor autonómiája (ADR 0087 §2, 1. és 2. pont: a
  kör-brief és az ADR, amit a pre-flightban ő ír) lefedi — egyik feloldás sem
  érint már merge-elt ADR-t, lezárt kört, vagy a brief §4 "Tilos zóna"
  felsorolásában szereplő tiltott utat; a `signal_quality_report.dart`
  érintése a brief saját STOP-klauzulájának explicit, előre jóváhagyott
  mechanizmusa.

## A visszavonás feltétele

Felülvizsgálandó, ha egy jövőbeli kör (különösen R07 vagy R21) mért indokkal
mutatja, hogy a `measured` flag, a migration-warning-alapú metre-tárolás, vagy
a `modelUnavailable` legacy-jelölés gyakorlati akadályt jelent — ekkor a
felülvizsgálat egy dedikált, explicit ADR dolga, nem egy építő-kör csendes
eltérése.
