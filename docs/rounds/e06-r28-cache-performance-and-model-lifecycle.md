# E06-R28 — Cache, performance és model lifecycle

- **Státusz:** PREPARED (előre megírva 2026-08-07, kód olvasva: main @ `a6e6f3d`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 28; §10.4, §22.2–22.7, §23.1–23.5
- **Branch:** `codex/e06-r28-cache-performance-and-model-lifecycle`
- **Előfeltétel:** **E06-R21, E06-R22 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/domain/cache/analysis_cache_key.dart",
  "lib/features/audio_analysis/data/cache/audio_fingerprint.dart",
  "lib/features/audio_analysis/data/cache/analysis_cache.dart",
  "lib/features/audio_analysis/data/cache/model_byte_cache.dart",
  "lib/features/audio_analysis/application/analysis_providers.dart",
  "lib/features/audio_analysis/public.dart",
  "lib/core/storage/storage_keys.dart",
  "tool/audio_analysis_benchmark.dart",
  "test/features/audio_analysis/data/analysis_cache_test.dart",
  "test/features/audio_analysis/data/audio_fingerprint_test.dart",
  "test/features/audio_analysis/domain/analysis_cache_key_test.dart",
  "test/property/analysis_cache_property_test.dart",
  "docs/adr/0248-analysis-cache-key-and-performance-budget.md",
  "docs/baseline/epic-06-analysis-performance.md",
  "docs/manual-testing/analysis-eval-matrix.md",
  "docs/rounds/e06-r28-cache-performance-and-model-lifecycle.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/property",
  "test/core",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R21/R22 merge.
> **ADR 0248** (lásd §0.0 — a batch-tervezéskori 0210 elavult). Olvasd újra
> az R01 `tool/audio_analysis_baseline.dart` mérőszkriptjét és a
> `docs/baseline/epic-06-audio-analysis-start.md` **mért** V1 számait — az
> R28 benchmarkja ezzel **összevethető** kell legyen (azonos fixture-ök).
> Olvasd újra az R21 repository- és az R27 törlés-szerződését (a cache
> invalidálása a törlés része). PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Eredetileg előre kiosztott ADR: 0210 (cache-kulcs + performance
budget) — **elavult, lásd alább.**

**Pre-flight revízió (Claude, 2026-08-13, E06-R28 pre-flight):**

1. **ADR-szám: 0210 → 0248.** A brief 2026-08-07-i batch-tervezéskor kapta a
   „0210" placeholdert, de a `tools/round-slots.py reserve-adr --round
   E06-R28` (a KÖTELEZŐ, ütközésmentes foglaló, §1.0.1) most **0248**-at adott
   vissza. Mérve: `docs/adr/0210-*.md` nem létezik, és a
   `.pipeline/inflight/adr/` foglalási naplóban SINCS `0210` vagy `0211`
   marker — a highest ténylegesen foglalt/committolt szám 2026-08-13 20:06-kor
   **0247** (`docs/adr/0247-analysis-export-share-and-delete-contract.md`,
   E06-R27). A 0210/0211 placeholderek a batch-tervezés idején (mielőtt a
   köztes E06-R08…R27 + más epicek kb. 35 ADR-t elhasználtak) sosem mentek át
   a foglalón — árva, sosem-foglalt számok. Ez a kör **0248**-cal megy; minden
   korábbi „ADR 0210" hivatkozás e fájlban lecserélve. (E06-R29 brief-je is
   „0211"-et hordoz — az az ő pre-flightjának dolga, ezt a fájlt nem érinti.)
2. **§2 pontosítás — a modell-újratöltés idézete a V1 fájl, NEM módosítandó.**
   A „`analyze_providers.dart` 83–101" hivatkozás a `_crnnWeights`/
   `_chordWeights`/`computeClipAnalysis`-ra ténylegesen a **V1**
   `lib/features/analyze/providers/analyze_providers.dart` fájlra mutat (mérve:
   `_crnnWeights` 83. sor, `_chordWeights` 94. sor, `computeClipAnalysis` 108.
   sor a jelen HEAD-en) — ez a fájl a jelen kör §3 **TILOS zónájában** van
   (`lib/features/analyze/**`) és NINCS az `allowed_paths`-on. A hivatkozás
   kizárólag **motiváló bizonyíték** (ugyanez a minta — modellbájtok
   stage/futásonkénti újratöltése — várható a V2 oldalon is, ha egy jövőbeli
   kör konkrét stage-eket köt be), NEM egy módosítandó hely: ezt a köröt a V1
   fájl érintése nélkül kell elvégezni. A §6 „Modell-betöltés" AC
   („bundle-olvasás hívásszáma 1… akkor is, ha három stage kéri") a
   **ÚJ, önálló `ModelByteCache`** saját tesztjével bizonyítandó (szimulált
   stage-hívók), NEM éles V1- vagy V2-runner-bekötéssel — a V2 runner ma sincs
   konkrét stage-listával összeállítva (`analysisV2RunnerProvider` továbbra is
   `throw StateError(...)`, `analysis_providers.dart:168-173`), ennek a
   körnek nem feladata ezt megváltoztatni.
3. **§9 kockázat pontosítása — a mért `AnalysisCachePort` szerződés.** Az R27
   már otthagyott egy explicit, stabil portot pontosan erre a célra:
   `lib/features/audio_analysis/application/delete_analysis_use_case.dart:10-12`
   — `abstract interface class AnalysisCachePort { Future<void>
   invalidate(String documentId); }`, alapértelmezett `NoCachePort` no-op-pal
   (ugyanott, 32–38. sor), és a fájl saját doc-commentje szó szerint: „No
   production implementation exists yet — the E06-R28 cache round wires a
   real port here without touching this use case's contract (ADR 0247
   §Döntés 4)." A `delete_analysis_use_case.dart` fájl **NINCS** ezen kör
   `allowed_paths`-án — az interfészt tilos módosítani (a brief §9 eredeti
   figyelmeztetése ezt helyesen tiltja). Egy valódi portadapter megírása
   (pl. az `AnalysisCache`-t becsomagolva) a `application/analysis_providers.dart`
   wiring fájlban **elvégezhető és természetes**, mert az allowed_paths-on
   van és „wiring" a szerepe — de ez **NEM önálló, külön gate-elt AC**: a §6
   lista és a §6.1 falszifikációs mátrix változatlan, kimerítő és nem bővül
   vele. (`DeleteAnalysisUseCase` maga sincs Riverpod-providerbe kötve ma —
   mérve: nulla `DeleteAnalysisUseCase(`/`deleteAnalysisUseCaseProvider`
   találat a wiring fájlokban a saját osztálydefinícióján kívül — így egy
   teljes éles bekötés ennek a körnek amúgy sem lenne elvégezhető feladat.)

## 1. Cél

A V2 elemzés költségének kontrollálása: **reprodukálható** cache-kulcs,
LRU-korlát, modellbájt-újrahasznosítás, és **dokumentált** teljesítmény-
baseline — optimalizálás **kizárólag** mérés alapján.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- **Nincs cache** sehol: minden `computeClipAnalysis` hívás újraszámol.
- A modellsúlyok betöltése: `_crnnWeights()` és `_chordWeights()`
  `rootBundle.load(...)` **minden** elemzésnél újra
  (`analyze_providers.dart` 83–101); a parse (`CrnnStrumNet.parse`,
  `ChordCrnn.parse`) az isolate-ban, **minden** futásnál újra
  (`runClipAnalysis` 45–52, 60–63).
- **Nincs** input fingerprint, **nincs** teljesítmény-baseline dokumentum
  az Epic 6-ra (az R01 hozta a V1 baseline-t).
- Az R21 adja a dokumentum-tárolást, az R22 a runnert, az R08 a
  preprocessing-konfigurációt (a cache-kulcs egyik bemenete).

## 3. Scope

**Benne:** `AudioFingerprint` (nem személyazonosító, nyers audiot nem
rekonstruáló hash); `AnalysisCacheKey` (input fingerprint + analyzer version +
model manifest ID-k + DSP config hash + target hash + feature flag snapshot);
`AnalysisCache` (hit/miss diagnosztika, LRU cap, invalidáció, korrupció-
kezelés); `ModelByteCache` (a modellbájtok **egyszeri** betöltése és a
parse-olt modell újrahasználata futásonként); `tool/audio_analysis_benchmark.dart`;
`docs/baseline/epic-06-analysis-performance.md`; **ADR 0248**.

**Kívül — TILOS:** `TransferableTypedData`/`Float32List` **átállás**
(mérés nélkül tilos, SDD §22.2 — ez a kör csak **megméri** és ADR-ben
javasol), chunked analysis, DSP-paraméter, `lib/features/analyze/**`.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/cache/analysis_cache_key.dart` | ÚJ | kulcs-szerkezet |
| `.../data/cache/audio_fingerprint.dart` | ÚJ | input hash |
| `.../data/cache/analysis_cache.dart` | ÚJ | LRU cache |
| `.../data/cache/model_byte_cache.dart` | ÚJ | modell újrahasználat |
| `.../application/analysis_providers.dart` | meglévő | wiring |
| `.../public.dart` | meglévő | export |
| `lib/core/storage/storage_keys.dart` | meglévő | **additív** cache-kulcs |
| `tool/audio_analysis_benchmark.dart` | ÚJ | mérőszkript |
| `docs/baseline/epic-06-analysis-performance.md` | ÚJ | mért baseline |
| `docs/adr/0248-…md` | ÚJ | cache + budget döntés |
| `docs/manual-testing/analysis-eval-matrix.md` | meglévő | PENDING sorok |
| `test/**` | ÚJ | cache + fingerprint + property |

**Tilos zóna:** `lib/features/analyze/**`, `lib/features/live/**`,
`assets/ml/**`, `tool/ci/**`, `.github/**`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **A cache-kulcs MINDEN hat bemenetet tartalmazza** (SDD §23.1): input
   fingerprint, analyzer version, model manifest ID-k, DSP config hash,
   target hash, feature flag snapshot. **NEM elfogadható:** csak a
   fingerprintre kulcsolás — az inkompatibilis eredményt adna vissza egy
   verzióváltás után.
2. **A fingerprint nem azonosítja a felhasználót és nem rekonstruálható**
   (SDD §10.4): a hash a **normalizált mintákból** és a formátum-metaadatból
   készül, nem a fájlnévből, nem eszközazonosítóból.
   **NEM elfogadható:** a fájlnév vagy elérési út a hash bemenetében.
3. **A cache soha nem ad inkompatibilis eredményt:** bármely kulcs-komponens
   változása **miss**. **NEM elfogadható:** „közel egyező" kulcs elfogadása.
4. **A sérült cache-bejegyzés miss, nem hiba:** eldobódik, a futás normálisan
   újraszámol.
5. **A mentett session nem cache:** a cache ürítése a **mentett**
   dokumentumokat **nem** érinti (SDD §23.5).
6. **Optimalizálás csak benchmarkkal** (SDD §22.7 / Kör 28 §8): bármely
   típusváltás vagy másolat-csökkentés **előtt** és **után** mérés kell.
   Ez a kör **nem** végez ilyen átállást — az ADR 0248 rögzíti a
   **javaslatot** és a **feltételt**.
7. **A teljesítmény-küszöb NEM merge-kapu ezen a boxon:** a benchmark
   számai a baseline dokumentumba és az eval-mátrix PENDING soraiba kerülnek;
   a gate a **funkcionális** cellákat méri. **NEM elfogadható:** wall-clock
   assert a unit-tesztben (flaky).
8. **A modellbájtok betöltése egyszer:** a `ModelByteCache` futásonként
   **egyszer** olvassa a bundle-t, és a parse-olt modellt újrahasználja a
   stage-ek között. **NEM elfogadható:** stage-enkénti újraparse.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: Hol éljen a cache?
    blocking: true
    resolution_policy: use_default
    default: >-
      lemezen, az app-support `analysis_cache/` alkönyvtárában (az R21
      injektált Directory mintájával), plusz egy KIS memória-LRU a futó
      folyamatban. A SharedPreferences NEM alkalmas (nagy payload).
  - id: OD-02
    question: Mekkora a cache cap?
    blocking: true
    resolution_policy: use_default
    default: >-
      20 bejegyzés VAGY 50 MiB, amelyik előbb teljesül; LRU (utolsó
      hozzáférés szerint). Mindkettő néven nevezett konstans.
  - id: OD-03
    question: Mi a fingerprint algoritmusa?
    blocking: true
    resolution_policy: use_default
    default: >-
      SHA-256 a (mintaszám, sampleRate, csatornaszám, preprocessing config
      verzió) fejlécen + a minták kvantált (16-bit) bájtjain; a nyers
      lebegőpontos értékek NEM kerülnek a hashbe (platformfüggő lenne).
  - id: OD-04
    question: Egyidejű azonos kérés?
    blocking: true
    resolution_policy: use_default
    default: >-
      single-flight: a második kérő ugyanarra a Future-re csatlakozik,
      NEM indít második futást; ezt hívásszámláló méri.
```

## 6. Acceptance criteria

- [ ] **Kulcs-mátrix — hét cella:** azonos minden → **hit**; és külön-külön
      megváltoztatva az input fingerprintet / analyzer verziót / model
      manifest ID-t / DSP config hasht / target hasht / flag snapshotot →
      **mind a hat miss**. Egyetlen komponens sem hagyható ki.
- [ ] **Fingerprint-tulajdonságok:** azonos PCM → azonos hash (100 futásra);
      **egyetlen minta** megváltoztatása → **eltérő** hash; eltérő fájlnév,
      **azonos** tartalom → **azonos** hash (ez méri, hogy a név nincs benne);
      a hash **nem** tartalmaz visszafejthető audiot (a hash hossza fix
      64 hex karakter, függetlenül a klip hosszától).
- [ ] **Cap-küszöb hármas (darab):** **19 / 20 / 21** bejegyzés — a **20**-nál
      még nincs kilakoltatás (inkluzív), a 21-nél a **legrégebben használt**
      tűnik el (nem a legrégebben írt — külön cella, ahol a legrégebbi
      bejegyzést közben olvassuk).
- [ ] **Cap-küszöb hármas (méret):** a bejegyzések összmérete
      **50 MiB − 1 bájt / pontosan 50 MiB / 50 MiB + 1 bájt**
      (= **52 428 799 / 52 428 800 / 52 428 801**, `python3 -c`-vel) — a
      pontosan 50 MiB még belefér.
- [ ] **Sérült bejegyzés:** a cache fájl szemétre cserélése → a lekérés
      **miss** (nem dob), a bejegyzés eltűnik, és a futás újraszámol.
- [ ] **Mentett session védettsége:** cache ürítése után az R21 repository
      `list()` és `getById()` **változatlan** eredményt ad.
- [ ] **Single-flight:** két, egyidejű azonos kérés → a pipeline
      **egyszer** fut (hívásszámláló `== 1`), és **mindkét** hívó ugyanazt az
      eredményt kapja.
- [ ] **Modell-betöltés:** egy futásban a bundle-olvasás hívásszáma
      **1**, és a parse hívásszáma **1** modellenként — akkor is, ha három
      stage kéri.
- [ ] **Benchmark-artefaktum:** `tool/audio_analysis_benchmark.dart`
      lefut, és a `docs/baseline/epic-06-analysis-performance.md`
      **a futtatott kimenetet** tartalmazza (nem kézzel írt számokat) az
      R01-gyel **azonos** fixture-ökre: wall-clock, real-time factor,
      stage-időtartamok, modell-betöltés, cache hit/miss, cancel-latencia.
      Kétszeri futtatás determinisztikus event/chord/BPM kimenetet ad.
- [ ] **Nincs wall-clock assert a tesztben:** forrásolvasó teszt méri, hogy az
      új tesztfájlokban nincs időmérésre épülő `expect` (`Stopwatch` +
      `lessThan` minta).
- [ ] **Eval-mátrix:** a valós eszközös teljesítmény (30 s-os klip
      középkategóriás Androidon, peak memória, thermal) **PENDING** sorként,
      felelőssel és mérendő számmal.
- [ ] **ADR 0248** rögzíti: a kulcs hat komponensét, a cap-értékeket, a
      **javasolt** (de itt el nem végzett) `Float32List`/`TransferableTypedData`
      átállás **feltételét** (paritás + mért nyereség), és a visszavonás
      feltételét.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A kulcs csak a fingerprintet tartalmazza | a kulcs-mátrix hat miss-cellája közül mind |
| Az analyzer verzió kimarad a kulcsból | a kulcs-mátrix „analyzer version" miss-cellája |
| A fájlnév a hash bemenete | az „eltérő név, azonos tartalom → azonos hash" cella |
| A hash hossza a kliptől függ | a fix 64 hex karakter cella |
| A cap exkluzív | a **pontosan 20** nincs-kilakoltatás cella |
| Az LRU valójában FIFO | a „legrégebbit közben olvassuk" cella |
| A méret-cap exkluzív | a **pontosan 52 428 800 bájt** cella |
| A sérült bejegyzés kivételt dob | a sérült-bejegyzés miss-cella |
| A cache ürítése törli a mentett sessiont | a mentett-session védettség cella |
| Két egyidejű kérés két futást indít | a single-flight hívásszám `== 1` cella |
| Stage-enkénti modell-parse | a parse hívásszám `== 1` cella |
| Wall-clock assert kerül a tesztbe | a forrásolvasó cella |
| **Valódi-sértés próba (§10):** az analyzer-verzió komponens ideiglenes kivétele a kulcsból → a megfelelő miss-cella **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/property test/core
```

Külön processzek, nincs `&&`/pipe/`tail`. A benchmark **nem** a gate része —
külön futtatott artefaktum, aminek a kimenete a baseline dokumentumba kerül.

## 8. Implementációs sorrend

1. ADR 0248 (kulcs, cap, budget, átállási feltétel — a pre-flight már megírta,
   §0.0; az implementer csak akkor módosítja, ha implementáció közben mért
   eltérés indokolja, dokumentált módon).
2. RED: kulcs-, fingerprint-, cap- és single-flight mátrix.
3. `audio_fingerprint.dart` + `analysis_cache_key.dart`.
4. `analysis_cache.dart` (LRU, korrupció, invalidáció).
5. `model_byte_cache.dart` (egyszeri betöltés + parse).
6. `tool/audio_analysis_benchmark.dart` + a baseline dokumentum a **futtatott**
   kimenettel.
7. Eval-mátrix PENDING sorok; gate.

## 9. Kockázatok

- **A benchmark számai gépfüggők** — a baseline dokumentum rögzíti a futtató
  környezetet, és a számok **nem** merge-kapuk (§5.7).
- **A cache és az R27 törlése összefügg** — ha az R27 use case-e már
  hivatkozik a cache invalidálására, az interfészt **nem** szabad
  megváltoztatni; ha eltér, az **megállás és jelentés**.
- **A modell-cache isolate-határon** él: a bájtok a main isolate-on
  olvasódnak, a parse az isolate-ban — a §10-ben rögzíteni kell, hol
  történik a tényleges újrahasználat, és hogy az isolate-onkénti parse
  hányszor fut.

**STOP:** típusátállás mérés nélkül, DSP-paraméter érintése vagy wall-clock
gate bevezetése helyett `stopped` + brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r28-cache-performance-and-model-lifecycle-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
