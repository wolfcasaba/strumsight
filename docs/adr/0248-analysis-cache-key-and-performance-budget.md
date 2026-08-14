# ADR 0248 — Analysis cache-kulcs és performance budget

- **Státusz:** Elfogadva (E06-R28 pre-flight, 2026-08-13)
- **Kör:** E06-R28 — Cache, performance és model lifecycle
- **Előzmény:** a brief 2026-08-07-i batch-tervezéskor ezt a döntést **0210**
  szám alatt vázolta fel; a szám a pre-flightban **0248**-ra frissült
  (`docs/rounds/e06-r28-cache-performance-and-model-lifecycle.md` §0.0 —
  a `tools/round-slots.py reserve-adr` ütközésmentes foglaló adta vissza,
  mert a 0210/0211 placeholder sosem ment át a foglalón és időközben elavult).
- **Kapcsolódó szerződések:** SDD Ch7 §10.4 (input fingerprint), §22.1–22.3
  (isolate runner, modellbetöltés), §22.7 (performance budget), §23.1–23.5
  (cache és újraelemzés); [ADR 0215](0215-analysis-document-versioning.md)
  (schemaVersion/analyzer version), [ADR 0217](0217-analysis-raw-audio-retention.md)
  (nyers audio nem perzisztálható — a fingerprintre is vonatkozik),
  [ADR 0218](0218-analysis-metric-id-and-version-governance.md) (verzió-
  governance precedens), [ADR 0220](0220-audio-analysis-v2-parallel-rollout-boundary.md)
  (V2 flag-határ változatlan), [ADR 0239](0239-analysis-document-storage.md)
  (R21 repository — a mentett dokumentum tartóssági igazsága),
  [ADR 0247](0247-analysis-export-share-and-delete-contract.md) (R27 törlés —
  a `AnalysisCachePort` seam forrása).

## Kontextus

A V2 elemzési pipeline-nak (E06-R02…R27) ma nincs cache-rétege: minden
elemzési futás — akár a modellbájtok betöltése, akár maga a DSP/ML számítás —
nulláról indul. Ugyanez a minta (modellbájtok újratöltése és -parse-olása
minden hívásnál) mérve megvan a V1 Analyze úton is
(`lib/features/analyze/providers/analyze_providers.dart` — ezen kör saját
tiltott zónája, kizárólag motiváló bizonyítékként hivatkozva, lásd a brief
§0.0 pontja 2). Az Epic 6 eddigi körei rétegenként építik fel a V2
infrastruktúrát bekötés nélkül (`audioAnalysisV2Enabled` és minden al-flag
`false` marad) — ez a kör ugyanezt a mintát követi a cache- és
modell-újrahasználati réteggel.

Az R21 ([ADR 0239](0239-analysis-document-storage.md)) adja a tartós
dokumentum-tárolást (fájlrendszeres `AnalysisRepository`), az R22
([ADR 0240](0240-analysis-runner-and-pipeline-boundary.md)) a run-ID-alapú
runnert, az R08 ([ADR 0225](0225-analysis-preprocessing-and-resampling-policy.md))
a preprocessing configot — ez utóbbi az egyik cache-kulcs bemenet. Az R27
([ADR 0247](0247-analysis-export-share-and-delete-contract.md)) már otthagyott
egy explicit, stabil portot a leendő cache-invalidálásnak
(`AnalysisCachePort.invalidate(String documentId)`,
`delete_analysis_use_case.dart:10-12`, alapértelmezett `NoCachePort` no-op),
kifejezetten ennek a körnek szánva.

## Döntés

1. **A cache-kulcs pontosan hat, EGYÜTTESEN kötelező komponensből áll:**
   input fingerprint, analyzer version, model manifest ID-k, DSP config
   hash, target hash, feature flag snapshot (SDD §23.1). Bármelyik komponens
   változása **miss** — közelítő/részleges egyezés nem fogadható el. A
   `AnalysisProvenance` domain modell (`domain/analysis_provenance.dart`) már
   hordozza az `inputFingerprint`/`analyzerVersion`/`dspConfigHash`/
   `modelManifestIds`/`featureFlagSnapshot` mezőket — az `AnalysisCacheKey`
   ezekre épül; a „target hash" az egyetlen, ami ma nincs kész mezőként
   (a `targetVersion` String nem azonos vele).
2. **A fingerprint algoritmusa:** SHA-256 a (mintaszám, sampleRate,
   csatornaszám, preprocessing config verzió) fejlécen **plusz** a minták
   kvantált 16-bit bájtjain. A nyers lebegőpontos érték és a fájlnév/
   elérési út/eszközazonosító **sosem** kerül a hashbe (ADR 0217 — nem
   felhasználóazonosító, nem rekonstruálható nyers audio).
3. **Tárolási hely:** lemezen, az app-support `analysis_cache/`
   alkönyvtárában (az R21 injektált `Directory`-mintájával), plusz egy kis
   memória-LRU réteg a futó folyamatban. A `SharedPreferences` kizárva (nagy
   payload — teljes köztes/végleges `AnalysisDocument`-méretű bejegyzések).
4. **Kilakoltatási politika:** LRU, cap **20 bejegyzés VAGY 50 MiB
   (52 428 800 bájt), amelyik előbb teljesül**, mindkettő néven nevezett
   konstans. A „legrégebben használt" (utolsó hozzáférés), nem a
   „legrégebben írt" bejegyzés tűnik el.
5. **A sérült cache-bejegyzés miss, sosem hiba:** dekódolási/ellenőrzési
   hibánál a bejegyzés eldobódik, a hívó normálisan újraszámol — a cache
   soha nem propagál kivételt a hívó felé.
6. **A cache és a mentett dokumentum élettartama független.** A cache
   ürítése (LRU kilakoltatás vagy explicit purge) **nem** érinti az R21
   `AnalysisRepository`-ban mentett dokumentumokat — a repository marad az
   egyetlen tartóssági igazságforrás; a cache pusztán derived/reprodukálható
   gyorsítótár.
7. **Egyidejű azonos kérés — single-flight:** a második (és minden további)
   egyidejű, azonos kulcsú kérő ugyanarra a folyamatban lévő `Future`-re
   csatlakozik, nem indít második futást; a pipeline hívásszámlálója ezt
   mérhetővé teszi.
8. **`ModelByteCache`:** a modell-bundle-t futásonként **egyszer** olvassa
   (`rootBundle`/asset-forrás), és a parse-olt modellt (nem a nyers bájtokat)
   használja újra a stage-ek között — akkor is, ha több stage kéri ugyanazt a
   modellt. Ma nincs konkrét V2 stage-lista éles összeállítva
   (`analysisV2RunnerProvider` throw-ol, `application/analysis_providers.dart:168-173`
   — „A future pipeline-composition round must override it"), ezért ez a
   viselkedés a `ModelByteCache` saját, szimulált többszörös-hívó tesztjével
   bizonyított, nem éles bekötéssel.
9. **Opcionális, nem gate-elt integrációs pont:** az R27 `AnalysisCachePort`
   (`delete_analysis_use_case.dart:10-12`) számára egy valódi adapter az
   `application/analysis_providers.dart` wiring fájlban megírható (a portot
   NEM módosítva) — ez természetes kiterjesztés, de nem önálló acceptance
   criterion; a §6 lista ettől függetlenül kimerítő.
10. **A `TransferableTypedData`/`Float32List` átállás csak JAVASOLT, ebben a
    körben NEM végrehajtott** (SDD §22.2). Feltétel a jövőbeli bevezetéshez:
    mért paritás (bitre egzakt vagy dokumentált tolerancia) ÉS mért
    teljesítménynyereség, mindkettő a `tool/audio_analysis_benchmark.dart`
    futtatásával, dokumentálva a bevezető kör ADR-jében. Visszavonási
    feltétel: ha egy jövőbeli mérés paritás-drift-et vagy nem mérhető
    nyereséget mutat, az átállás visszavonható ÚJ ADR nélkül, e döntés
    egyszerű visszaállításaként.
11. **Nincs wall-clock merge-kapu.** A benchmark számai a
    `docs/baseline/epic-06-analysis-performance.md` dokumentumba és az
    eval-mátrix PENDING soraiba kerülnek; a gate kizárólag funkcionális
    cellákat mér — `Stopwatch`/`lessThan` mintájú assert unit-tesztben nem
    elfogadható (flaky ezen a gépen).

## Következmények

**E06-R30 (2026-08-13):** a döntés változatlan; performance device budget evidence EVAL-07/27/32/33 PENDING.

- A cache teljes egészében on-device és offline; hálózati hívást nem végez.
- `audioAnalysisV2Enabled` és minden al-flag változatlanul `false` — ez a kör
  infrastruktúra, a production elemzési útvonalakba bekötetlen.
- Egy jövőbeli pipeline-kompozíciós kör feladata a `ModelByteCache`/
  `AnalysisCache` éles V2 runnerbe kötése, és opcionálisan a valódi
  `AnalysisCachePort` adapter bekötése a törlési útvonalba.
- A teljesítményszámok a baseline dokumentumba és az eval-mátrixba kerülnek,
  nem ebbe az ADR-be — a szám gépfüggő, nem merge-kapu.

## Elutasított alternatívák

- **Kulcs csak a fingerprintre:** inkompatibilis eredményt adna vissza egy
  analyzer-/modell-/DSP-config-verzióváltás után — pontosan az a hiba, amit a
  hat-komponensű kulcs kizár.
- **`SharedPreferences`-alapú tárolás:** nem alkalmas nagy payloadra (teljes
  `AnalysisDocument`-méretű bejegyzések).
- **FIFO kilakoltatás LRU helyett:** nem felel meg a „legrégebben használt,
  nem legrégebben írt" követelménynek (§6 AC külön cellája méri a
  közben-olvasott legrégebbi bejegyzés túlélését).
- **Wall-clock assert a unit-tesztben:** ezen a mérőgépen (ARM Oracle,
  változó terhelés) flaky — a `docs/LESSONS.md` több korábbi bejegyzése is
  ezt a mintát azonosítja kerülendőként.
