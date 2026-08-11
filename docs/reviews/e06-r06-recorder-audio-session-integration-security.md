# E06-R06 — Biztonsági / privacy review (dedikált)

Brief: `docs/rounds/e06-r06-recorder-audio-session-integration.md`
Diff: `main (2b724d3) ... eab4336` (pre-flight `9f77bd6` + implementáció
`eab4336`), 8 fájl / 733 sor. A review izolált klónban futott
(`/tmp/security-review-e06-r06`, offline `flutter pub get`), a megosztott
munkapéldányt csak olvasásra érintette.
Reviewer: security-reviewer ágens (független, READ-ONLY) · Dátum: 2026-08-11
Kockázat (brief): `high` · `native_gate = false`
Verdikt: ~~CHANGES REQUIRED — 1 BLOCKER (reprodukálva)~~ → **PASS (javító kör
után, `eb9a6e7`)** — 0 CRITICAL/BLOCKER, 0 MAJOR, S2 FIXED, 2 NOTE

## Javító kör után — orchesztrátor újra-ellenőrzése (2026-08-11)

A javító kör `_cancelFromRevocation`-t úgy módosította, hogy `_mic.stop()`
MOSTANTÓL FELTÉTEL NÉLKÜL fut (a run-ID egyezés csak a `_complete(...
cancelled)` run-állapot-mutációt gátolja, magát a mic-leállítást nem) —
pontosan a jelentés „javasolt iránya". A `dispose()` is `try/finally`-re
javult (S2 zárva).

Az orchesztrátor saját, friss izolált klónban (`/tmp/review-e06-r06`)
megismételte a security-reviewer reprodukcióját: a guard-ot visszaállítva az
eredeti, hibás alakra (`if (_activeRunId != runId) return;` a `_mic.stop()`
ELŐTT), az implementer által hozzáadott regressziós teszt
(`background revocation during mic warm-up stops the capture`,
`analysis_recorder_lifecycle_test.dart`) pirosra váltott
(`capture.stopCalls`: várt `>0`, kapott `0`) — a javítás visszaállítása után
zöld. A teljes gate (mind a 8 lépés) saját, független futtatásban zöld. A
scope-audit a végleges HEAD-en (`eb9a6e7`) is tiszta.

S3/S4 (NOTE, előremutató, ugyanaz a gyökérok mint S1 volt) változatlanul
nyitva maradhat — nem blokkoló.

## Összegzés (eredeti, a javító kör ELŐTT)

CRITICAL: 0 · BLOCKER: 1 · MAJOR: 0 · MINOR: 1 · NOTE: 2

## Megállapítások

| ID | Súlyosság | Hely | Lelet |
|---|---|---|---|
| S1 | **BLOCKER** | `analysis_recorder.dart:125-129` (`_cancelFromRevocation`), `_start` (:88-114) és `mic_capture.dart:72-121` kölcsönhatásában | Warm-up-ablak revoke-szivárgás: hot mic háttérben + coordinator szabadnak jelzi magát + második owner konkurens capture-t nyithat. Reprodukálva. |
| S2 | MINOR | `analysis_recorder.dart:217-222` (`dispose`) | `_levels.close()` kimarad, ha `await stop()` dob → a broadcast `StreamController` nem minden útvonalon szabadul fel (AGENTS.md §7 szellemében). |
| S3 | NOTE | `analysis_recorder.dart:184-197`, `:212-214` | Egy `NaN` minta mindkét hysteresis-összehasonlítást hamissá tenné → a clipping-figyelmeztetés csendben sosem kapcsolna be. A mai mikrofonos (int16-normalizált) úton nem elérhető — előremutató jegyzet. |
| S4 | NOTE | `analysis_recorder.dart:131-136` (`_acceptChunk`) | A warm-up alatt (mielőtt `_activeRunId` beállna) érkező chunk stale-ként számolódik el (`droppedStaleChunks`), holott a JELENLEGI run korai audiója — ugyanaz a gyökérok, mint S1, valószínűleg ugyanaz a javítás oldja meg. |

### S1 — BLOCKER — háttérbe kerülés a mic-warmup ALATT hot mic-et hagy és felszabadítja a coordinatort

**Sértett szabály:** `AGENTS.md` §5 — „Mikrofont egyszerre egy owner
birtokolhat", és a háttérbe-kerüléskor a felvétel véget ér elv. A kör saját
§6 lifecycle-mátrix acceptance criteriuma is ezt a viselkedést írja elő és
téveszti el.

**Gyökérok:** `_start()` az `_activeRunId`-t csak az `await _mic.start(...)`
VISSZATÉRÉSE UTÁN állítja be (104. sor). A `_mic.start()` belsejében
(`mic_capture.dart` `_doStart`) a coordinator lease-t a `capture.start()`
hívás ELŐTT szerzi meg — eközben, ha az app háttérbe kerül, az
`AudioLifecycleGuard` a `coordinator.revokeActive()`-en át meghívja a
lease `onRevoke`-ját, ami itt `_cancelFromRevocation(runId)`:

```dart
Future<void> _cancelFromRevocation(String runId) async {
  if (_activeRunId != runId) return;   // MÉG null a warm-up alatt → korai return
  _complete(runId, RecordingRunStatus.cancelled);
  await _mic.stop();                   // ...ezért SOSEM fut le
}
```

A `_mic.stop()` elmaradása ellenére a `_Lease._revoke()` `finally` ága
(`audio_session_coordinator.dart:119-121`) MINDENKÉPP felszabadítja a
lease-t. Amikor a `capture.start()` végül visszatér, a `MicCapture` nem lát
`_stopRequested`-et, élőnek tartja a capture-t, és `Success`-t ad vissza —
az `AnalysisRecorder` `recording` állapotot jelent, MIKÖZBEN a coordinator
már szabadnak mutatja a sessiont.

**Kettős hatás:** (1) a mikrofon tovább rögzít a háttérben — a user azt
hiszi, nem figyel semmi; (2) `coordinator.activeOwner == null`, tehát egy
MÁSIK owner sikeresen megszerezheti a mikrofont, miközben a V2 recorder
capture-je ténylegesen még él — konkurens mic-tulajdonlás.

**Reprodukálva (izolált klónban, a tesztet a próba után eltávolítva):**
`FakeAudioCapture(startGate:)` nyitva tartott indítási kapuval indított
`start()`, közben `coordinator.revokeActive()` meghívva, majd a kapu
eltolva. Eredmény: `result` `Success<RecordingRun>`, `recorder.isRecording
== true`, `capture.isRunning == true`, `capture.stopCalls == 0`,
`coordinator.activeOwner == null`, egy utólagos `capture.emit([...])`
növelte a mintaszámot, és egy MÁSODIK `MicCapture(owner: live)` `start()`-ja
is sikeres volt. **Kontraszt-teszt:** ugyanez a forgatókönyv egy sima
`MicCapture` ALAPÉRTELMEZETT `onRevoke`-jával (= a saját `stop`-ja, ez a V1
`ClipRecorder` útja) helyesen leállítja a capture-t — ez bizonyítja, hogy a
szivárgás **V2-specifikus regresszió**, nem a `MicCapture` meglévő hibája.

**Elérhetőségi megjegyzés (őszintén jelezve, a súlyosságot NEM csökkenti):**
az `AnalysisRecorder`-t ez a kör még NEM köti be sehova (nincs production
hívó) — egy mai APK-ból ez a séma önmagában nem váltható ki. Élesbe akkor
kerül, amint E06-R22 bedrótozza a recordert a megosztott
coordinator/lifecycle-guard alá (a brief §5.1/§9 explicit terve). Mivel a
hiba ennek a körnek a SAJÁT, kimondott céljában (lease/lifecycle
korrektség) van, és a kör kifejezetten `risk = high`, `AGENTS.md` §15.1
szerint („CRITICAL vagy BLOCKER lelet → merge tilos") ez merge-blokkoló,
nem elhalasztható follow-up.

**Javasolt irány (nem kész patch):** a mic-leállítás ne legyen a run-ID
egyezéshez kötve — egy revoke mindig azonnali leállítást jelent,
függetlenül attól, hogy `_activeRunId` már be van-e állítva; csak a
RUN-ÁLLAPOT mutációját kösse a `runId` egyezés. Ez tükrözi, ahogy a
`MicCapture` alapértelmezett (nem felülírt) revoke-ja már ma helyesen,
feltétel nélkül állítja le a warm-up alatti capture-t.

### S2 — MINOR — `dispose()` kihagyhatja a level-stream lezárását

`Future<void> dispose() async { ...; await stop(); await _levels.close(); }`
— ha `stop()` (ami `_mic.stop()`-ot hív, ami `capture.stop()`-ot) dobna, a
`_levels.close()` sosem fut. Alacsony hatás (broadcast controller, nem
platform-handle), és ma nem elérhető (a fake-ek sosem dobnak stop-on).
**Irány:** `try { await stop(); } finally { await _levels.close(); }`.

### S3 — NOTE — NaN minta csendben elnyomná a clipping-jelzést

Előremutató, a mai mikrofonos úton nem elérhető (int16-normalizált PCM
sosem NaN) — relevánssá válik, ha egy jövőbeli float/WAV-forrás valaha a
recorderbe kötne.

### S4 — NOTE — warm-up alatti chunk stale-ként számolva

Ugyanaz a gyökérok, mint S1; adatvesztés/számlálás-pontosság, nem
biztonsági határ; valószínűleg az S1 javítása egyben ezt is megoldja.

## Ellenőrzött és tiszta (bizonyítékkal)

- **Nyers audio kiszivárgás / logolás / lemez / hálózat:** az új fájlok
  grep-elve (`logger|print(|debugPrint|File(|Directory|Dio|http|socket|Uri.|
  writeAs|openWrite|SharedPreferences|SecureStore`) — az egyetlen találat az
  `au`**`dio`** substring a `mic_capture.dart` import-útvonalban
  (kis-nagybetű-független `dio`). Nincs logger-hívás, nincs `print`, nincs
  fájl-I/O, nincs hálózat egyetlen új fájlban sem. A felvett PCM kizárólag
  a memóriabeli `List<double> _samples`-ben él (csak-olvasható
  `UnmodifiableListView`-n át kiadva); a `levels` stream kizárólag
  aggregált peak/RMS/clipping skalárokat visz, sosem nyers mintát.
- **Mic-lease útvonal:** az `AnalysisRecorder` nem tart saját coordinatort
  vagy capture-t — a megosztott `MicCapture`-t komponálja. Nincs második
  coordinator, nincs közvetlen capture. Az EGYETLEN egy-tulajdonos-sértés az
  S1 útján található.
- **Max-hossz korlát (erőforrás-kimerülés):** a puffer sosem lépheti túl a
  korlátot; a pontos határ, a fölé-eset és a run-befejezés utáni eldobás
  mind ellenőrizve (kód-olvasással + a kör saját, F1 javító körben bővített
  tesztjeivel).
- **Stale-chunk run-ID izoláció:** valódi-sértés próbával megerősítve (a
  guard szűkítése a review saját próbájában és a kör §6.1 próbájában is
  pirosra fordította a megfelelő tesztet).
- **Lifecycle (normál út):** az 5 cellás mátrix helyes; `inactive` helyesen
  NEM állít le. Kizárólag a warm-up ablak (S1) kezeletlen.
- **Prompt injection (§5.1):** a diff NEM dolgoz fel külső/importált
  tartalmat — nincs fájlimport, hálózati válasz, MusicXML/MIDI/tab/
  tudásbázis/provider-szöveg. A bemenetek `List<double>` PCM (numerikus),
  `AppLifecycleState` enumok és konstruktor-paraméterek. **Nem
  releváns — ellenőrizve, nem feltételezve.**
- **Secretek:** nincs token/kulcs/hitelesítő adat az új kódban vagy a
  fixture-ökben.
- **`public.dart` barrel:** additív export, a recorder továbbra is
  injektált `MicCapture`-t igényel — nem tud csendben megkerülni egy
  megosztott coordinatort.

## Teszt-bizonyíték (a tiszta klónban)

- `flutter test test/features/audio_analysis/data/analysis_recorder_test.dart
  test/features/audio_analysis/data/analysis_recorder_lifecycle_test.dart` →
  `+15 All tests passed` (egyezik az implementer állításával).
- Reprodukció + kontraszt-teszt → `+2 All tests passed` (a hibás állítások
  megálltak; a V1-alapértelmezett út biztonságos).
- Mutáció-próba (stale-chunk guard szűkítése) → a várt cella pirosra
  váltott, visszaállítás után zöld, munkafa tiszta.

## Merge-döntés

`AGENTS.md` §15.1: „CRITICAL vagy BLOCKER lelet → merge tilos." **Nyitott
BLOCKER (S1) → merge jelenleg TILOS.** Javító kör ugyanazzal a motorral
(Terra), utána ez a jelentés frissítendő PASS-ra a javító commit sha-jával,
az orchesztrátor saját reprodukciós próbájával megerősítve.
