# E06-R06 — Review

Brief: `docs/rounds/e06-r06-recorder-audio-session-integration.md`
Diff: `git diff origin/main...codex/e06-r06-recorder-audio-session-integration` (8 files, 733 insertions / 8 deletions)
Reviewer: Claude Sonnet 5 (orchestrátor) · Dátum: 2026-08-11
Implementer: Terra (Codex, `gpt-5.6-terra`), 1 forduló (`eab4336`) egy köztes,
scope-on kívüli környezeti akadály (hiányzó generált `lib/l10n/**`, az
orchesztrátor pótolta a munkapéldányban) utáni folytatással — nincs
tartalmi javító kör.
Verdikt: **CHANGES REQUIRED** (1 nyitott MAJOR)

## Összegzés

BLOCKER: 0 · MAJOR: 1 · MINOR: 1 · NOTE: 3

## Módszertan

Független, izolált klónban (`/tmp/review-e06-r06`, közvetlenül a GitHub
originból, NEM a megosztott munkapéldányból) futtatott TELJES gate +
négy valódi-sértés (mutáció) próba a négy leginkább biztonság-/
helyesség-kritikus őrön. A zöld gate-et NEM fogadtam el bemondásra —
mindegyik állítást vagy a forráskód olvasásával, vagy egy ténylegesen
lefuttatott (és utána visszaállított) mutációval igazoltam.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Lease-mátrix (4 cella: szabad/busy/stop-felszabadít/kétszeri-start-egy-capture) | ✅ | `analysis_recorder_test.dart` 4 teszt; (c) cella mutáció-próbával megerősítve (lásd lent) |
| 2 | Lifecycle-mátrix (5 cella: resumed/inactive/paused/hidden/detached) | ✅ | `analysis_recorder_lifecycle_test.dart`, valós `AudioLifecycleGuard`+`AudioSessionCoordinator` ellen driveolva; mutáció-próbával megerősítve |
| 3 | Stale-chunk mátrix (`droppedStaleChunks == 2`) | ✅ | `analysis_recorder_test.dart:112-131`; mutáció-próbával megerősítve |
| 4 | Max-hossz küszöb-hármas (28 799 999 / 28 800 000 / 28 800 001) | ⚠️ **RÉSZLEGES — ld. F1** | statikus aritmetika tesztelve; a viselkedési (futásidejű) csonkolás egy TÚLMÉRETEZETT chunkra NINCS tesztelve — mutáció-próbával megerősített hiány |
| 5 | Hysteresis-mátrix (−0.5/−1.0/−2.0/−3.0/−3.5 dBFS, oda-vissza) | ✅ | `analysis_recorder_test.dart:197-237`; kézzel újraszámolva a 9 elemű elvárt sorozat ellen (lásd lent) — pontosan egyezik |
| 6 | Nincs FFT / O(N) preview | ✅ | kód-olvasás (nincs FFT-import, nincs pipeline-import a recorderben) + `CountingSampleBuffer.readCount` teszt |
| 7 | V1 regressziómentesség | ✅ | saját, független gate-futás `test/features/analyze` lépése zöld; `git diff --stat` nem tartalmaz `lib/features/analyze/**`-t |

## Scope-audit

```
tools/scope-audit.py --repo /tmp/review-e06-r06 \
  --brief docs/rounds/e06-r06-recorder-audio-session-integration.md \
  --base 98220a0158c50e71995ef51ece7b031bcc8f4e35
→ Legacy scope audit OK (98220a0158c5..eab43360face, 8 changed path(s), 0 generated/ignored)
```

Engedélyezett fájlokon kívüli változás: **nincs** — a `git diff --stat` 8
fájlja szó szerint egyezik a brief `allowed_paths` 8 bejegyzésével.

## Megállapítások

### F1 — MAJOR — a max-hossz csonkolás VISELKEDÉSE nincs tesztelve egy túlméretezett chunkra

- **Fájl:** `lib/features/audio_analysis/data/capture/analysis_recorder.dart:149`
  (`final acceptedCount = math.min(remaining, chunk.length);`)
- **Probléma:** a brief §6 „Maximum hossz" cellája és a §6.1 mérce-mátrix
  („A max hossz elérésekor a puffer eldobódik → a »puffer hossza pontosan
  28 800 000« cella") kifejezetten megköveteli, hogy egy a határt átlépő
  ELADÁS (egyetlen, a fennmaradó kapacitásnál nagyobb chunk) a chunk-on
  BELÜL vágódjon le, a többlet eldobva. A meglévő „stays active below the
  limit, completes at it, and drops excess" teszt (`analysis_recorder_test.dart:142-168`)
  ezt NEM ezt a kódutat gyakorolja: mindig 1-mintás chunkokat küld, a
  határ pontosan egy chunk VÉGÉN esik (a chunk mérete sosem haladja meg a
  fennmaradó kapacitást), a „drops excess" állítás valójában a
  **run-befejezés UTÁNI, más őrön (`_activeRunId != runId`) átmenő**
  eldobást méri, nem a `math.min` csonkolást.
- **Mérve (valódi-sértés próba, izolált klónban, visszaállítva):**
  `acceptedCount = math.min(remaining, chunk.length)` ideiglenesen
  `acceptedCount = chunk.length`-re cserélve (a csonkolás teljes
  eltávolítása) — a **teljes célzott tesztfájl 10/10 teszt ZÖLD marad**.
  Egyetlen teszt sem veszi észre, hogy egy túlméretezett chunk immár a
  teljes hosszában bekerülne a pufferbe, átlépve a dokumentált limitet.
- **Hatás:** ha egy jövőbeli refaktor (akár egy másik cellára optimalizálva)
  véletlenül eltávolítja vagy elrontja ezt a `math.min` hívást, a gate
  ZÖLD maradna, miközben a felvétel korlátlanul nőhetne egy elég nagy
  egyetlen chunk esetén — ez pontosan az a memória-korlátlanság, amit a
  brief §5.5 „A maximum hossz nem hiba… NEM elfogadható: a puffer
  eldobása" pontja (és vele szimmetrikusan a felső korlát) ki akar zárni.
  Élő hibát a mai kódban NEM találtam (a `math.min` logika kézi
  végigolvasva helyes tetszőleges túllépésre, nem csak ±1 mintára), ez
  tisztán regresszió-védelmi hiány.
- **Kötelező javítás:** egy új teszteset `analysis_recorder_test.dart`-ban,
  amely a meglévő kis-mintaszámú mintát (`maximumDuration: Duration(seconds: 2)`,
  `sampleRate: 1` → limit 2 minta) egyetlen, a limitnél NAGYOBB chunkkal
  hívja (pl. `capture.emit(const [0.1, 0.2, 0.3])` egy induló, üres
  pufferre) és `expect(recorder.samples, const [0.1, 0.2])` +
  `expect(recorder.currentRun!.status, RecordingRunStatus.maxDurationReached)`-et
  vár — ez a chunk-on BELÜLI csonkolást önmagában, a
  run-befejezés-utáni-eldobástól elkülönítve bizonyítja.
- **Ellenőrzés:** az új teszt a fenti mutációra (a `math.min` eltávolítására)
  pirosra váltson; jelenlegi állapotban (a `math.min` megtartva) zöld legyen.
- **Státusz:** OPEN

### F2 — MINOR — a level-preview csak az ÉPPEN kibocsátó chunkot méri, nem a throttle-ablakban felhalmozott összeset

- **Fájl:** `lib/features/audio_analysis/data/capture/analysis_recorder.dart:151-171`
- **Probléma:** `emitLevel` throttle-ablakonként csak a chunk-ok EGYIKÉT
  (azt, amelyik átlépi a `levelInterval`-t) vizsgálja peak/RMS
  szempontjából; a köztes, nem-kibocsátó chunkok mintái bekerülnek
  `_samples`-be, de peak/RMS-ük SOSEM kerül kiszámításra (a `peak =
  math.max(...)` / `squareSum += ...` sorok csak `if (emitLevel)` ágban
  futnak). Egy rövid, hangos (akár clipping-szintű) tranziens, amely
  TELJES egészében egy köztes, nem-kibocsátó chunkba esik, nem jelenik
  meg a live preview-n (bár a végleges, teljes `samples` pufferben — és
  így egy KÉSŐBBI kör pipeline-alapú signal-quality mérésében — igen).
- **Hatás:** kizárólag a §11.6 „olcsó" LIVE preview pontosságát érinti;
  adatvesztés vagy biztonsági kockázat nincs (a nyers PCM a teljes hosszában
  megmarad). Az OD-02 (`blocking: false`) kifejezetten latitude-ot adott a
  throttle pontos szemantikájára.
- **Javasolt irány (nem kötelező ebben a körben — a fix a
  `_acceptChunk` állapotgépének (futó peak/squareSum/mintaszám a throttle-
  ablakon át) érdemi bővítését igényelné, ami meghaladja a MINOR „nem
  hizlalja a diffet" küszöbét):** kövesd nyitva follow-upként — natural
  otthona a Kör 7 „Signal quality stage" (SDD 07-epic-06 „Kör 7"), amely
  amúgy is a preview és a végleges minőségmérés közös primitíváit tervezi.
- **Státusz:** OPEN (follow-up, nem blokkol)

### N1 — NOTE — SDD „Kör 6" vs. a brief §3 hatókör-eltérése helyesen dokumentálva

`docs/sdd/07-epic-06-audio-analysis-2.md` „Kör 6" korai vázlata („régi
Analyze screen működik adapteren keresztül") tágabb kört ír le, mint a
tényleges, később finomított brief §3/§4. Az implementer a §10 handoffban
explicit rögzítette, hogy a brief elsőbbségével (AGENTS.md §2) a V1 Analyze
érintetlen maradt — ez a helyes döntés, nem lelet, csak megerősítés.

### N2 — NOTE — a permission-vs-busy failure szétválasztás megőrzött, de áttervezett módon

A brief §5 2. pontja a mai `MicStart.denied`/`failed` szétválasztás
MEGŐRZÉSÉT írja elő; az `AnalysisRecorder` nem replikálja a `MicStart` enumot,
hanem a `MicCapture`/`AudioSessionCoordinator` már ma is DISZTINKT
`AppFailure` altípusait (`PermissionFailure` vs. `AudioFailure(code:
audioSessionBusy)`) engedi át változatlanul `AppResult<RecordingRun>`-ként.
Ez a szétválasztást TARTALMILAG megőrzi (a `keeps denied permission distinct
from a capture failure` teszt kifejezetten a típuskülönbséget méri), csak nem
egy `MicStart`-szerű zárt enumban — ésszerű, a duplikációt elkerülő döntés,
nem lelet.

### N3 — NOTE — a `RecordingRunStatus` szándékosan NEM a §21 `AudioAnalysisState`

A `recording_run.dart` négyértékű, lokális `RecordingRunStatus` enumja
(`recording/completed/cancelled/maxDurationReached`) helyesen NEM a SDD §21.1
jövőbeli, pipeline-szintű 11-értékű `AudioAnalysisState` gépe — a §10 handoff
ezt explicit is rögzíti. Ez a jövőbeli E06-R22 (analysis-runner
progress/cancellation) dolga; itt a helyes, szűk hatókörű választás.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (implementer) | Ellenőrizve (reviewer, saját izolált klón) |
|---|---|---|
| format | zöld | ✅ zöld |
| analyze | zöld | ✅ zöld |
| test test/features/audio_analysis | zöld (15 célzott teszt) | ✅ zöld |
| test test/core | zöld | ✅ zöld |
| test test/features/analyze | zöld | ✅ zöld |
| architecture | zöld | ✅ zöld (12 allowlisted deviation — változatlan, a diff nem érinti az allowlistet) |
| secrets | (nem külön jelentve) | ✅ zöld (2187 fájl, 0 lelet) |
| l10n | (nem külön jelentve) | ✅ zöld |
| `scope_audit` | `ok` (implementer jelzésfájl) | ✅ `ok` (saját `tools/scope-audit.py` futás) |

Négy valódi-sértés próba (mind izolált `/tmp/review-e06-r06` klónban, mind
visszaállítva a próba után):

1. `math.min(remaining, chunk.length)` → `chunk.length` (csonkolás
   eltávolítása) — **10/10 teszt ZÖLD maradt** → **F1 nyitott lelet**.
2. `stop()`-ból a `await _mic.stop();` hívás eltávolítva — a „releases the
   lease after stop" teszt PIROSRA váltott (`Actual: AudioOwner.analyzeRecorder`
   maradt aktív tulajdonos) → őr megerősítve.
3. `_acceptChunk` guard `_activeRunId != runId || run == null` →
   csak `run == null`-ra szűkítve — a stale-chunk teszt PIROSRA váltott
   (`sampleCount` várt `0`, kapott `2`) → őr megerősítve.
4. `_mic.start(...)` hívásból az `onRevoke: () => _cancelFromRevocation(runId)`
   eltávolítva — mind a három lifecycle-teszt (`paused`/`hidden`/`detached`)
   PIROSRA váltott (`isRecording` várt `false`, kapott `true` — „zombi"
   felvételi állapot) → őr megerősítve.

## Merge-döntés

ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge.
**Itt egy nyitott MAJOR (F1) van** → **merge jelenleg TILOS.** A lánc normál
útja (user-döntés 2026-07-31): javító kör ugyanazzal a motorral (Terra),
egyetlen célzott teszt hozzáadásával; a review ezután frissítendő
APPROVED-ra a javító commit sha-jával, F2 pedig OPEN follow-upként
átkerül a záró RTM/HANDOFF bejegyzésbe.
