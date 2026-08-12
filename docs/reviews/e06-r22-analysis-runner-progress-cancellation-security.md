# E06-R22 — Security / adatvédelmi / prompt-injection review

- **Kör:** E06-R22 — Analysis runner, progress UI és cancellation
- **Branch:** `codex/e06-r22-analysis-runner-progress-cancellation`
- **Diff:** `git diff 4ef44008..HEAD` (izolált klón: `/tmp/review-e06-r22`)
- **Reviewer:** Claude (dedikált security-reviewer, READ-ONLY — production kód nem módosult, AGENTS.md §15.1)
- **Dátum:** 2026-08-12
- **Brief kockázat:** `risk = "high"` → kötelező dedikált security review
- **Verdikt:** ~~FAIL~~ → **PASS (javítás után)** — 0 CRITICAL · 0 BLOCKER · **0 OPEN MAJOR** (1 FIXED) · 0 MINOR · 4 NOTE

> **Javítás után (orchesztrátor, 2026-08-12, fix commit `63f39515`):** a
> MAJOR-1 leletet a Terra javító kör #1 zárta — a `_dispose()` immár a
> `_isolate` mezőt atomikusan veszi át és nullázza, majd a killt a
> `_disposed` once-guard ELŐTT futtatja, ezért a spawn-utáni késői
> hozzárendelés is garantáltan killt kap
> (`analysis_isolate_runner.dart:196-207`). A javítást egy ÚJ, VALÓDI
> (nem fake) isolate-ot spawnoló teszt zárja (`analysis_cancellation_test.dart`,
> „cancellation during spawn kills the later-assigned isolate before it
> finishes work"), amely egy injektálható `isolateSpawner` seam-en (`analysis_
> isolate_runner.dart:44-63`) át determinisztikusan a spawn-ablakban cancel-el.
> **Orchesztrátor-oldali független ellenőrzés (kétszer mérve):** (1) a
> security review saját `leak_probe.dart` reprodukcióját újra lefuttattam —
> A (cancel-during-spawn) `finished=true`, B (cancel-after-spawn)
> `finished=false`, C (baseline) `finished=true`, változatlanul a
> hibaminta-leírás szerint; (2) a fixált kódon a fenti ÚJ tesztet valódi-sértés
> próbával futtattam: a `_dispose()` sorrendjét ideiglenesen visszaállítottam a
> javítás ELŐTTI (guard-előbb-mint-kill) alakra → a teszt PIROSRA váltott
> (`Expected: false, Actual: <true>`) → visszaállítva, a teszt újra zöld. A
> NOTE-2 (`analyze()` nem szakítja meg a korábbi futást) is javítva ugyanebben
> a körben (`analysis_controller.dart:70-73`, `unawaited(cancelAnalysis(previousRun))`),
> és a NOTE-3 (nulla-nevezős progress-sáv) is (`analysis_progress_view.dart:27-28`,
> `totalUnits! > 0` feltétel hozzáadva). NOTE-1 és NOTE-4 változatlanul nyitott
> megfigyelés/pozitív-ellenőrzés, nem igényelt kódváltozást.

> **Nincs CRITICAL/BLOCKER lelet:** a kör nem sért nem-tárgyalható adat/adatvédelmi
> termékhatárt (AGENTS.md §5) — nincs titok-szivárgás, consent-megkerülés,
> path-traversal, RCE, rejtett hálózati kérés, és **nyers audio/PCM egyetlen
> határon (isolate, persistálás, log, hibaüzenet) sem lép át**. A `FAIL` oka
> **egy reprodukált MAJOR erőforrás-szivárgás** (cancel-during-spawn isolate
> leak), amely egy **kifejezett kör-acceptance kritériumot** (brief §5.2 /
> §6.1: „a cancel nem hagy szemetet, NEM elfogadható a »majd a GC elviszi«
> isolate-kezelés") megsért, és amelyet a kör saját tesztkészlete **nem fed**
> (false-green). A kör merge-küszöbe (brief §11) „nulla OPEN BLOCKER/MAJOR" —
> ezért a lelet **blokkolja a merge-et**, amíg nyitva van. A teljes V2
> `audio_analysis` réteg **bekötetlen** (`audioAnalysisV2Enabled = false` +
> `analysisV2RunnerProvider` fail-closed `StateError`), így a lelet ma
> production-ban nem elérhető — ezért MAJOR, nem BLOCKER.

---

## 1. Vizsgált diff és módszer

`git diff --stat 4ef44008..HEAD` — a security-releváns `lib/` felület:

| Fájl | Állapot |
|---|---|
| `.../application/analysis_isolate_runner.dart` | ÚJ (198 sor) — isolate spawn/kill, JSON codec-határ |
| `.../application/analysis_controller.dart` | ÚJ (166 sor) — run-ID állapotgép, késői-eredmény szűrő |
| `.../application/analysis_state.dart` | ÚJ (80 sor) — 11-állapotos sealed hierarchia |
| `.../application/analyze_audio_use_case.dart`, `cancel_analysis_use_case.dart`, `save_analysis_use_case.dart` | ÚJ — application-határok |
| `.../application/analysis_providers.dart` | +69 — wiring (runner provider **fail-closed**) |
| `.../presentation/analysis_progress_view.dart` | ÚJ (90 sor) — progress widget |
| `.../public.dart` | +7 export |
| `lib/l10n/app_en.arb`, `app_hu.arb` | +22 additív fázis-szöveg mindkettőben |
| 3 teszt (`test/features/audio_analysis/application|presentation/*`) | ÚJ |

**Reprodukálható alap-tények (mind lefuttatva a klónban):**
- **Bekötöttség:** `analysisV2RunnerProvider` (`analysis_providers.dart:168-173`)
  `StateError`-t dob → `AnalyzeAudioUseCase` production-ban nem konstruálható;
  `audioAnalysisV2Enabled = false` a konstruktor-defaultban ÉS a prod resolve
  ágon (`lib/app/config/feature_flags.dart:32,80`), nincs `fromEnvironment`
  felülírás. **Kettős fail-closed → a réteg teljesen bekötetlen.**
- **Hálózat/titok sweep:** `git diff … lib/ | grep -Ei '(dio|http|https?://|socket|Uri\.|secret|token|password|apikey|signing|Authorization|Bearer)'`
  → **nincs találat** (csak import-sorok és az „audio" szó). Nincs új hálózati
  hívás, nincs hardcodolt kulcs.
- **Log-sink sweep:** `git diff … lib/ | grep '^\+' | grep -Ei '(print|debugPrint|log|developer\.log|stderr|writeAsString|File\()'`
  → **nincs** hozzáadott logolás/fájlírás. A kör semmit nem logol.

---

## 2. Leletek

### MAJOR-1 — Cancel-during-spawn: a `cancel()` nem öli meg az isolate-ot (erőforrás-szivárgás, kör-kritérium sérül)

**Fájl:sor:** `lib/features/audio_analysis/application/analysis_isolate_runner.dart:95`
(`_isolate = await Isolate.spawn(...)`), `:103-106` (a spawn utáni
`if (_cancelled) { await _dispose(); return; }`), `:146-148` (`cancel()`),
`:171-177` (`_dispose()` a `_disposed` once-guarddal).

**Failure scenario (konkrét bemenet → rossz kimenet):** A host elindít egy futást,
majd **még mielőtt az `Isolate.spawn` future feloldódna**, háttérbe kerül vagy
elhagyja a képernyőt — `AnalysisController.appBackgrounded()` / `screenDetached()`
(`analysis_controller.dart:100-103`) → `cancel()` → `cancelAnalysis(run)` →
`run.cancel()`. A `cancel()` szinkron törzse (`_cancelled=true`, majd
`_dispose()`: `_disposed=true`, `_isolate?.kill()`) **lefut, mielőtt a spawn
future feloldódik**, ezért `_isolate` ekkor még `null` → a `kill()` **no-op**, de a
`_disposed` once-guard **elhasználódik**. Amikor a spawn feloldódik, `_isolate`
egy **élő isolate-ot** kap (`:95`), de a rákövetkező `if (_cancelled) → _dispose()`
(`:104`) a `_disposed==true` miatt **azonnal visszatér, kill nélkül**; a `finally`
`_dispose()`-a (`:140`) szintén no-op. **Az isolate soha nem lesz megölve** — a
teljes `operation(documentJson)` (egy jövőbeli valódi DSP-stage = másodpercek
CPU/akku) lefut, jóval a felhasználó cancelje után. A `kill(immediate)`, aminek
meg kellett volna szakítania a munkát, **sosem tüzel**.

**Bizonyíték (reprodukálva, 3/3 determinisztikus):** faithful pure-Dart repro a
valódi életciklussal (`_isolate = await Isolate.spawn` sorrend + `_disposed`
guard + spawn-utáni no-op dispose bitre másolva; valódi `dart:isolate`
spawn/kill). Marker-fájlok mérik az isolate életét a határon át:

```
A cancel-during-spawn : started=true finished=true   (LEAK: az isolate végigfutott, kill nem tüzelt)
B cancel-after-spawn  : started=true finished=false   (kill MŰKÖDIK, ha _isolate már hozzá van rendelve)
C no-cancel baseline  : started=true finished=true    (normál lefutás)
```

Az **A vs. B** kontraszt bizonyítja, hogy a hiba **specifikusan a spawn-ablak**
(nem általános cancel-hiba): amint `_isolate` hozzá van rendelve (B), a kill
megszakítja a munkát. (A repro nem a Flutter-szennyezett import-láncot futtatja —
a valódi runner tranzitíven `package:flutter`-t húz be a `public.dart`-on át —,
de a mérvadó sorok az `analysis_isolate_runner.dart`-ral azonosak.)

**Coverage-rés (false-green):** a `analysis_cancellation_test.dart` cancel-
takarítás tesztje **FAKE** `_CleanupRun`-t használ (`:63-88`), nem a valódi
runnert; az egyetlen **valódi** isolate-teszt (`:41-50`) csak codec round-tripet
mér és **sosem hív `cancel()`-t**; a `analysis_controller_test.dart` végig
`_QueueRunner`/`_FakeRun` fake-eket használ (`:242,251`). Így a valódi runner
spawn-ablakos cancel-útját **egyetlen teszt sem fedi** — a brief §6.1 mérce-
mátrix „A cancel nem szabadítja fel az isolate-ot → `disposed==true` cella PIROS"
sora **csak a fake-en** mér.

**Sértett szabály:** brief **§5.2** („cancel után az isolate felszabadul … NEM
elfogadható a »majd a GC elviszi« isolate-kezelés"), **§6** „Cancel-takarítás" +
**§6.1** mérce-mátrix, **ADR 0240** Döntés 3 és 7 (`cancel()` megöli az
isolate-ot, „kemény, futásonkénti kill"), **AGENTS.md §5.4** (minden kilépési út
felszabadít). **NEM** az öt nem-tárgyalható adat/adatvédelmi határ egyike (nem
nyers audio, nem mic/kamera, nem titok) → **MAJOR**, nem BLOCKER; de a kör §11
merge-küszöbe („nulla OPEN MAJOR") miatt **merge-blokkoló**.

**Javasolt javítás iránya:** a spawn-utáni `_cancelled`-ágon **explicit**
öld meg a frissen hozzárendelt isolate-ot (a kamera-fix „első disposal-check
cleanup" mintája szerint), **vagy** tedd a `_dispose`-t úgy, hogy a
`_isolate` killje akkor is lefusson, ha a guard már beállt (külön
`_isolateKilled` flag), **vagy** ne spawnolj, ha `_cancelled` már igaz, és
kill-on-assign. **Teszt:** exit-mátrix cella, amely **valódi** runnernél
(nem fake) spawn-késleltetést injektál és **a spawn alatt** cancelt — a
`FakeCameraCapture.startGate` mintájának isolate-analógja.

---

### NOTE-1 — A késői-eredmény kapu a runner-példány stabilitására épül (runId reset)

**Fájl:sor:** `analysis_controller.dart:106,126` (`event.runId != _activeRunId`,
`runId != _activeRunId`); `analysis_isolate_runner.dart:50,54`
(`_nextRunNumber`, `'analysis-isolate-${++_nextRunNumber}'`).

**Scenario:** a kapu helyessége azon áll, hogy a runId-k a controller
élettartamán belül egyediek. `_nextRunNumber` **példányonként 0-ra
nullázódik**. Ma a runner cache-elt singleton (`analysisV2RunnerProvider` sima
`Provider`), így egyedi — a kapu **jelenleg zár**. Ha egy jövőbeli wiring a
runner providert `autoDispose`/invalidálhatóvá teszi, egy újra-instanciált
runner megint `analysis-isolate-1`-től indul; egy még futó **elavult** run
késői eredménye ütközhet egy új run id-jével és **átjut** a `!=` kapun →
elavult eredmény felülírja az aktuális state-et (adatintegritás). Az ADR 0240
Döntés 2 / „Elutasított alternatívák" pontosan **ezért** utasította el a
pipeline példány-lokális számlálóját — de a `_nextRunNumber`-nek **ugyanez** a
tulajdonsága. Ma **nem reprodukálható** (bekötetlen + singleton) → előre-mutató.

**Javítás iránya:** a runId egy controller-birtokolt monoton forrásból vagy
UUID-ból; vagy a runner-singleton invariáns explicit dokumentálása/assertje.

---

### NOTE-2 — `analyze()` nem szakítja meg a korábbi, még futó futást

**Fájl:sor:** `analysis_controller.dart:70-86`.

**Scenario:** ha `analyze()`-t egy még aktív futás mellett hívják (előzetes
`cancel()` nélkül), a korábbi `_activeRun`/`_activeRunId` felülíródik **anélkül,
hogy a régi futást megszakítaná** → a régi isolate a saját befejezéséig szivárog
(erőforrás, nem state — a késői-eredmény kapu a régi eredményt elutasítja). A
host-kontraktus az előzetes cancel/await. Előre-mutató robusztusság.

**Javítás iránya:** `unawaited(_activeRun?.cancel())` az `analyze()` elején.

---

### NOTE-3 — Progress-sáv nulla-nevezős osztás (hamis determinista sáv)

**Fájl:sor:** `analysis_progress_view.dart:27-28,43`.

**Scenario:** `unitsAvailable` **csak null-t** ellenőriz; egy `completedUnits:0,
totalUnits:0` (vagy total==0) eseményt kibocsátó stage esetén `0/0=NaN`
(vagy `n/0=Infinity`) kerül a `LinearProgressIndicator(value:)`-be. A Flutter a
painterben clamppel (nincs crash), de **hamis, determinista sávot** rajzol —
gyenge kapcsolódás a #5 határhoz (félrevezető haladás). A brief §6 „nincs
százalék, ha nincs completedUnits" guardja a **total==0** esetet nem fedi.

**Javítás iránya:** `unitsAvailable`-hez kell `totalUnits! > 0` is.

---

### NOTE-4 — (Pozitív / defense-in-depth ellenőrizve) az isolate hibaszöveg a decode-nál eldobódik; a `cause` sosem renderelődik

**Fájl:sor:** `analysis_isolate_runner.dart:192-197` (`request.replyTo.send(
error.toString())`), `:115-124` (`decode(message)` → nem-JSON →
`ValidationFailure(code: 'analysis.document.codec.invalid')`, a nyers string
**eldobva**), `:129,136` (`UnknownFailure(cause: …)`).

**Ellenőrzés:** ha egy jövőbeli valódi `operation` az isolate-on belül dob, a
`error.toString()` visszakerül, de **soha nem logolódik és nem jelenik meg** — a
codec `decode` egy stabil kódú `ValidationFailure`-ré alakítja, a nyers szöveget
elnyelve; egy nem-String üzenet `UnknownFailure.cause`-ba kerül, amit az
`AppFailure.toString()` **kizár** (`core/foundation/app_failure.dart:106-116`:
„deliberately excludes cause, which may contain a URL, a request body or other
sensitive payload"). Tehát a boundary **strukturálisan** véd egy jövőbeli DSP
minta/elérési-út szivárgás ellen. **Fogyasztói caveat:** a `public.dart`
exportálja az `AnalysisError`/`AnalysisInputError` state-eket, amelyek
`AppFailure`-t hordoznak — a jövőbeli host **kizárólag `code` szerint
lokalizáljon**, és soha ne rendereljen `cause`/`stackTrace`-t.

---

## 3. Amit végignéztem és tisztának találtam (üres-jelentés-mint-bizonyíték)

- **Isolate-határ payload — nincs nyers audio.** A határon **kizárólag**
  `AnalysisDocumentCodec().encode(AnalysisDocument)` JSON-je lép át
  (`analysis_isolate_runner.dart:92,98`). A codec `_documentToJson`
  (`analysis_document_codec.dart:39-55`) **nem tartalmaz** minta/PCM mezőt; a
  `PreprocessedAudio` (az egyetlen PCM-hordozó domain-típus,
  `originalSamples`/`canonicalSamples`) **nem része** az `AnalysisDocument`-nek;
  `analysis_input_summary.dart:3` kifejezetten „Privacy-safe … never PCM". →
  **Nyers audio sem isolate-on, sem persistáláson, sem logon nem megy át.**
- **Save-út.** `SaveAnalysisUseCase` (`save_analysis_use_case.dart:10-11`) vékony
  továbbítás az R21 `AnalysisRepository.save`-hez; **nem** épít
  `AnalysisSaveRequest`-et, nem ír független adatot. A retenció
  (`keepOriginal=false`) az R21 kapuja, ez a kör **nem kerüli meg**.
- **Kredit-út.** `PracticeEntry` (`analysis_providers.dart:210-219`) = aggregált
  számok (day/source/seconds/strokes/chord-count), **nincs audio**; a predikátum
  a V1-gyel azonos (`analysis_controller.dart:160-164`).
- **`_ensureFiniteJson`** (`analysis_document_codec.dart:680-708`) NaN/Infinity
  ellen fail-closed **encode-nál ÉS decode-nál** — nincs nem-véges szám-csempészet
  a transzferált/persistált JSON-be.
- **ARB / progress-nézet.** 22 additív, **generikus** fázis-szöveg (en+hu); nincs
  path, stack trace, hibakód vagy PII. A `AnalysisProgressView` **csak**
  lokalizált címet/leírást + cancelt + `Semantics`-et renderel; **`AppFailure`
  objektum a nézetbe nem jut** (a widget nem is kap failure-t).
- **Prompt-injection / AI-provider / tool-calling / KB-retrieval:** **N/A** — a
  körben nincs LLM/provider, nincs eszközhívás, nincs külső-tartalom-mint-utasítás
  felület.
- **Import/kicsomagolás (zip/mxl/midi, path traversal, zip bomb):** **N/A** — a
  kör nem csomagol ki és nem importál archívumot.
- **Ellátási lánc:** nincs új dependency, nincs új asset (a `pubspec` érintetlen).

---

## 4. Verdikt

**FAIL** — 0 CRITICAL · 0 BLOCKER · **1 MAJOR** · 0 MINOR · 4 NOTE.

A MAJOR-1 (cancel-during-spawn isolate leak) **reprodukált**, egy **kifejezett
kör-acceptance kritériumot** (brief §5.2/§6.1, ADR 0240 Döntés 3/7) sért, és a
kör tesztkészlete **nem fedi** (false-green). A kör §11 merge-küszöbe „nulla OPEN
MAJOR" — a lelet **blokkolja a merge-et**, amíg nyitva van. Mivel a teljes V2
réteg bekötetlen (flag `false` + fail-closed runner provider), a lelet ma
production-ban nem elérhető, és nem sért nem-tárgyalható adat/adatvédelmi
határt — ezért **MAJOR**, nem BLOCKER/CRITICAL. Javítás után (a spawn-ablakban
kill-on-assign + valódi-runner exit-mátrix teszt) a kör tiszta.
