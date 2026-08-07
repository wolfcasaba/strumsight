# E06-R06 — Recorder és AudioSessionCoordinator integráció

- **Státusz:** PREPARED (előre megírva 2026-08-07, kód olvasva: main @ `a6e6f3d`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 6; §11.6, §21, §22.5
- **Branch:** `codex/e06-r06-recorder-audio-session-integration`
- **Előfeltétel:** **E06-R05 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/data/capture/analysis_recorder.dart",
  "lib/features/audio_analysis/data/capture/recording_run.dart",
  "lib/features/audio_analysis/domain/recording_level.dart",
  "lib/features/audio_analysis/public.dart",
  "test/features/audio_analysis/data/analysis_recorder_test.dart",
  "test/features/audio_analysis/data/analysis_recorder_lifecycle_test.dart",
  "test/support/fake_audio.dart",
  "docs/rounds/e06-r06-recorder-audio-session-integration.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/core",
  "test/features/analyze",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R05 merge. Olvasd újra
> `lib/features/analyze/engine/clip_recorder.dart` (58 sor),
> `lib/core/audio/lifecycle/audio_session_coordinator.dart` (123 sor, ADR 0056
> exkluzív lease + kontrollált busy failure),
> `lib/core/audio/lifecycle/audio_lifecycle_guard.dart` (`isBackgroundLifecycleState`
> — `paused|hidden|detached`, az `inactive` **NEM**), és
> `test/features/analyze/recorder_hardening_test.dart` +
> `cancel_during_start_test.dart` + `cancel_on_leave_test.dart` **tényleges
> eseteit**. Ezek a tesztek a **mai** viselkedés őrei: átírásuk tilos.
> Ellenőrizd a `test/support/fake_audio.dart` mai API-ját — a bővítés additív.
> PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Új ADR nincs — a kör az ADR 0056 (exkluzív audio lease) meglévő
szerződését **használja**, nem tervezi újra.

## 1. Cél

A V2 felvételi útvonal: run ID-val azonosított felvétel, `AudioCapture`
interfész mögötti forrás, `AudioSessionCoordinator` lease, **maximum
kliphossz**, és olcsó, felvétel közbeni szintjelzés — a mai `ClipRecorder`
**érintése nélkül**.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- `ClipRecorder` (58 sor): `MicCapture`-t kap, in-memory `List<double>` puffer,
  `MicStart{ok, denied, failed}`, `start()` single-flight garanciája a
  `MicCapture.start`-ban él (round 101), `stop()` a puffer **másolatát** adja.
  **Nincs** maximum hossz, **nincs** run ID, **nincs** szintjelzés.
- `AudioSessionCoordinator` (ADR 0056): egy tulajdonos egyszerre; a második
  **kontrollált busy failure**-t kap (`FailureCode.audioSessionBusy`), a
  kritikus szakasz az első `await` **előtt** fut; `onRevoke` a háttérbe
  kerüléskor bontja le a tulajdonos capture-ét.
- `AudioOwner.analyzeRecorder` a mai Analyze lease-neve
  (`analyze_providers.dart` 135: `createMicCapture(ref, AudioOwner.analyzeRecorder)`).
- A mai controller hot-mic védelme: `_screenAttached` + a mic-handshake alatti
  tab-váltás kezelése (`analyze_providers.dart` 140–179), és a
  `stopAndAnalyze` **a stop-flush await ELŐTT** lép ki a `recording` fázisból
  (round 114 R2).
- Meglévő őrtesztek: `recorder_hardening_test.dart`,
  `cancel_during_start_test.dart`, `cancel_on_leave_test.dart`,
  `mic_error_parity_test.dart`.

## 3. Scope

**Benne:** `AnalysisRecorder` (a V2 felvevő) az `AudioCapture` interfész
mögött, `AudioSessionCoordinator` lease-szel; `RecordingRun` (run ID, indítási
idő, sample rate, állapot); **maximum kliphossz** kikényszerítése
(`InputLimits.maxDuration`, R05) automatikus, **nem hibás** lezárással;
olcsó `RecordingLevel` stream (peak + RMS + clipping jelző, hysteresissel);
a `test/support/fake_audio.dart` **additív** bővítése.

**Kívül — TILOS:** a `ClipRecorder` és az `AnalyzeController` módosítása,
a V1 Analyze képernyő, a teljes pipeline futtatása, UI, permission-UX.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../data/capture/analysis_recorder.dart` | ÚJ | V2 felvevő lease-szel |
| `.../data/capture/recording_run.dart` | ÚJ | run ID + felvételi állapot |
| `.../domain/recording_level.dart` | ÚJ | szint/clipping jelzés típusa |
| `.../public.dart` | meglévő | recorder + level export |
| `test/features/audio_analysis/data/*` | ÚJ | recorder + lifecycle tesztek |
| `test/support/fake_audio.dart` | meglévő | **additív** fake capture bővítés |

**Tilos zóna:** `lib/features/analyze/**` (a `ClipRecorder`-t is beleértve),
`lib/core/audio/**` (a coordinator szerződése adott), `lib/features/live/**`.
Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Egyszerre egy mic-tulajdonos** (ADR 0056): a V2 recorder ugyanazon a
   coordinatoron kér lease-t. **NEM elfogadható:** külön, párhuzamos
   coordinator-példány vagy a lease megkerülése „mert a V2 flag mögött van".
2. **A plugin-hiba SOHA nem `granted`:** a permission-hiba és a busy mic
   **külön** failure (a mai `MicStart.denied` vs `failed` szétválasztás
   megőrzése). **NEM elfogadható:** egyetlen „mic error" gyűjtőállapot.
3. **Run ID kötelező:** minden felvétel egyedi ID-t kap; egy régebbi run
   `onChunk` callbackje **nem írhat** az aktuális pufferbe, és ezt **számláló**
   méri (`droppedStaleChunks`). Ez a mérés **eszköze** — nélküle a cella
   mérhetetlen lenne.
4. **Háttérbe kerülés = a felvétel vége** (`isBackgroundLifecycleState`:
   `paused|hidden|detached`; **`inactive` NEM**): az `onRevoke` bontja a
   capture-t, a run `cancelled` lesz, a mic felszabadul. **NEM elfogadható:**
   az `inactive` állapot kezelése háttérként (az a mai viselkedés
   megváltoztatása lenne).
5. **A maximum hossz nem hiba:** a limit elérésekor a felvétel **automatikusan
   lezárul** `maxDurationReached` okkal, és az addig felvett PCM **elemezhető**
   marad. **NEM elfogadható:** a puffer eldobása vagy `Failure` visszaadása.
6. **A szintjelzés olcsó:** a preview kizárólag peak/RMS-t számol a beérkező
   chunkon, **nem** futtat FFT-t és **nem** indítja el a pipeline-t
   (SDD §11.6). **NEM elfogadható:** a teljes signal-quality stage futtatása
   felvétel közben.
7. **A warning nem ugrál:** a clipping/túl-halk jelzés **hysteresissel**
   vált (be- és kikapcsolási küszöb különbözik). **NEM elfogadható:** egyetlen
   küszöb frame-enkénti kiértékelése.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: A V2 recorder saját AudioOwner értéket kapjon?
    blocking: true
    resolution_policy: use_default
    default: >-
      IGEN, ha az `AudioOwner` enum bővítése NEM igényli `lib/core/audio/**`
      módosítását — mivel igényelné, a V2 az `AudioOwner.analyzeRecorder`
      MEGLÉVŐ értékét használja. Így a V1 és V2 kölcsönösen kizárja egymást
      a mikrofonon, ami a kívánt viselkedés (egy mic-tulajdonos).
  - id: OD-02
    question: A level-stream mintavételi gyakorisága?
    blocking: false
    resolution_policy: use_default
    default: >-
      chunkonként egy érték, de a kibocsátás legfeljebb 10 Hz-re throttle-özve,
      a throttle a recorderben (nem az UI-ban) — így a teszt determinisztikus.
```

## 6. Acceptance criteria

- [ ] **Lease-mátrix — négy cella:** (a) szabad session → `start` sikeres;
      (b) a session **más** tulajdonosnál → kontrollált busy failure, a
      recorder **nem** kezd felvenni; (c) `stop` után a lease felszabadul
      (`coordinator.activeOwner == null`); (d) **kétszeri** `start` egyetlen
      capture-t nyit (a fake capture `startCount == 1`).
- [ ] **Lifecycle-mátrix — négy cella:** `resumed` / `inactive` /
      `paused` / `detached` — a felvétel **csak** a `paused` és `detached`
      esetén áll le; az `inactive` **nem** állítja le. (A `hidden` értéket a
      pre-flight ellenőrzi a mai enum ellen, és ha létezik, ötödik cella.)
- [ ] **Stale-chunk mátrix:** run#1 indul, `stop`, run#2 indul, majd run#1
      callbackje két chunkot küld → a run#2 puffere **változatlan**, és
      `droppedStaleChunks == 2`.
- [ ] **Maximum hossz — küszöb hármas** (48 000 Hz, `maxDuration = 10 perc`
      = 28 800 000 minta): **28 799 999** minta → fut tovább;
      **28 800 000** → a felvétel **lezárul** (a határ inkluzív), a puffer
      hossza pontosan 28 800 000; **28 800 001** → a puffer **28 800 000**-re
      vágott, a többlet eldobva, és a run oka `maxDurationReached`.
      A három számot `python3 -c`-vel kiszámolva.
- [ ] **Hysteresis-mátrix:** a clipping jelzés bekapcsol `peak ≥ −1.0 dBFS`-en
      és kikapcsol `peak ≤ −3.0 dBFS`-en; a mátrix cellái a **−0.5 / −1.0 /
      −2.0 / −3.0 / −3.5 dBFS** sorozat, oda-vissza bejárva — a −2.0 dBFS-en
      a jelzés **megmarad**, ha korábban bekapcsolt, és **nem** kapcsol be, ha
      korábban ki volt. (Ez az egyetlen cella, ami a hysteresist a
      küszöbtől megkülönbözteti.)
- [ ] **Nincs FFT a preview-ban:** a level-stream számítása kizárólag
      peak/RMS; teszt méri, hogy a preview `N` chunkra `O(N)` mintát olvas
      (számlálós fake), és hogy a pipeline egyetlen stage-e sem futott.
- [ ] **V1 regressziómentesség:** `test/features/analyze` **átírás nélkül**
      zöld, és `git diff --stat` nem tartalmaz `lib/features/analyze/**`
      útvonalat.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A recorder megkerüli a coordinatort | a lease-mátrix (b) busy-cellája |
| A `stop` nem adja vissza a lease-t | a lease-mátrix (c) `activeOwner == null` cellája |
| Az `inactive` is leállítja a felvételt | a lifecycle-mátrix `inactive` cellája |
| A `paused` nem állítja le | a lifecycle-mátrix `paused` cellája (hot mic) |
| Hiányzik a run ID szűrés | a `droppedStaleChunks == 2` cella |
| A max hossz `>` helyett `>=` (vagy fordítva) | a **pontosan** 28 800 000 mintás cella |
| A max hossz elérésekor a puffer eldobódik | a „puffer hossza pontosan 28 800 000" cella |
| Egyetlen küszöb, nincs hysteresis | a −2.0 dBFS oda-vissza cella |
| A preview FFT-t futtat | az `O(N)` mintaolvasás cella |
| **Valódi-sértés próba (§10):** a lease `release` hívás ideiglenes törlése a `stop`-ból → a (c) cella **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/core test/features/analyze
```

Külön processzek, nincs `&&`/pipe/`tail`.

## 8. Implementációs sorrend

1. `test/support/fake_audio.dart` additív bővítése (számlálós capture,
   vezérelhető lifecycle).
2. RED: lease-, lifecycle-, stale-chunk-, max-hossz- és hysteresis-mátrix.
3. `recording_run.dart` + `recording_level.dart`.
4. `analysis_recorder.dart` (lease, run ID, limit, throttle, hysteresis).
5. Gate; a V1 tesztek **átírás nélküli** zöldjének igazolása.

## 9. Kockázatok

- **A `fake_audio.dart` közös fájl** — más feature tesztjei is használják;
  a bővítés kizárólag **additív**, meglévő szignatúra nem változhat.
  Ha egy meglévő teszt elbukik: **megállás és jelentés**.
- **A lease-megosztás a V1-gyel** azt jelenti, hogy V2 felvétel közben a V1
  Analyze nem indítható — ez **szándékos** (§5.1 OD-01), és a §10-ben
  rögzítendő follow-upként a UI-oldali üzenet (R22).
- **A throttle és a teszt-determinizmus** ütközhet: a throttle
  **mintaszám-alapú** legyen (nem óra-alapú), hogy a teszt ne `Timer`-re
  várjon.

**STOP:** ha a run ID-szűréshez `lib/core/audio/**` módosítás kellene, az
**megállás és jelentés**, nem néma core-változtatás.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r06-recorder-audio-session-integration-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
