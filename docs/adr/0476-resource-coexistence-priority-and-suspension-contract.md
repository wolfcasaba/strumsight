# ADR 0476 — Erőforrás-együttélés: rendezett prioritás, felfüggesztés-nem-elvétel, és a döntő saját eredménytípusa

- **Státusz:** elfogadva
- **Dátum:** 2026-08-29
- **Kör:** `E12-R15` (Chapter 12, Kör 15)
- **Kapcsolódó:** [`0056`](0056-exclusive-microphone-session.md) (kizárólagos
  mikrofon-session: BUSY hiba, NEM lopás), [`0184`](0184-vision-camera-capture-stack.md)
  (vision camera capture stack; a lifecycle-elengedés a route-leave és a
  háttérbe váltás útján), [`0196`](0196-vision-device-tier-performance-and-thermal-contract.md)
  (device-tier és termál degradációs létra), [`0472`](0472-e2e-flow-harness-runs-in-the-flutter-test-host.md)
  (az e2e folyam-harness a `flutter test` hostban fut)

## Kontextus

A fán MA két, egymástól **teljesen független** kizárólagos erőforrás-koordinátor
él, és egyik sem tud a másikról. A pre-flight mérése (2026-08-29,
`main @ c207f91a`):

- `lib/core/audio/lifecycle/audio_session_coordinator.dart:34-55` — egy lease,
  `AudioOwner` ∈ {`live`, `tuner`, `analyzeRecorder`, `latencyCalibration`,
  `diagnostics`}; a második kérő `Failure(AudioFailure(code:
  FailureCode.audioSessionBusy))`-t kap (`app_failure.dart:39` →
  `'audio.session_busy'`);
- `lib/core/camera/camera_session_coordinator.dart:35-71` — ugyanaz a minta,
  `CameraOwner` ∈ {`visionSetup`, `visionPractice`, `songVision`, `labCapture`};
  a második kérő `FailureCode.cameraSessionBusy` (`camera_failure.dart:27`);
- **`lib/core/resources/` nem létezik**;
- a lease-t MA három hely szerzi meg, és mindhárom KÖZVETLENÜL a koordinátortól:
  `lib/core/audio/mic_capture.dart:82` (mikrofon),
  `lib/features/vision/application/vision_session_controller.dart:157` és
  `lib/features/vision/application/vision_setup_controller.dart:163` (kamera).
  Ez a mérés a TÉNYLEGES hívási láncról szól, nem a réteg-diagramról
  ([L100](../LESSONS.md#l100), [L19](../LESSONS.md#l19));
- **low-memory jelzés a fán nincs**: `grep -rni
  'memorypressure|didHaveMemoryPressure|lowMemory|low_memory' lib/ test/` → **0
  találat**. A `WidgetsBindingObserver.didHaveMemoryPressure` sehol nincs
  bekötve;
- helyi AI-futtató nincs: az Epic 10 (Offline AI) sávja `hold`-on áll, a
  `LocalAiResourceCoordinator` (SDD Ch10 §10.2) MA nem létezik.

Két fogyasztó ma tehát csak akkor találkozik, ha ugyanazt az egy erőforrást
kéri — és akkor a válasz BUSY. Amire nincs kimondott szerződés: mi történik,
amikor **különböző** erőforrások fogyasztói versengenek a gép véges
kapacitásáért (élő hang + kamerás visszajelzés + háttérben futó AI), és mi
történik memória-nyomás alatt. Enélkül minden későbbi bekötés a saját ad-hoc
sorrendjét hozná, és a mért hibaosztály (néma elvétel, elveszett részmunka)
körönként újratermelődne.

## Döntés

### D1 — A prioritás RENDEZETT és teljes; a sorrend kód, nem konvenció

`ResourcePriority` egy rendezett enum, magasabbtól alacsonyabb felé:

1. `liveAudio` — élő tanulási hang (a felhasználó éppen játszik);
2. `cameraFeedback` — kamera-alapú visszajelzés;
3. `backgroundAi` — háttérben futó helyi AI.

A rendezés **összehasonlítható** (`outranks`), és a rendezés a deklarációs
sorrend. Két fogyasztó prioritása lehet egyenlő; ilyenkor egyik sem előzi a
másikat, és az arbiter az `already_active` ágra megy — a döntetlen NEM
felfüggesztés.

### D2 — Az arbiter NEM vesz el kiadott lease-t (ADR 0056 nem gyengül)

Az arbiter a MEGLÉVŐ két koordinátor **fölé** ül: a kérések SORRENDJÉT és az
alacsonyabb prioritású fogyasztó felfüggesztését szabályozza. Amit **soha nem
tesz**: nem hívja a koordinátorok `revokeActive()`-ját, és nem hívja egy másik
fogyasztó `release()`-ét azért, hogy egy magasabb prioritásút kiszolgáljon.

**Indok (mért, nem elvi):** a lease elvétele pontosan azt a néma no-op osztályt
állítaná elő, amit az ADR 0056 kizár — a mikrofonját vesztett képernyő UI-ja
továbbra is „hallgatlak"-ot mutatna, miközben a streamje halott. A kizárólagos
erőforrás birtoklása marad a koordinátoré; a második kérő továbbra is a
koordinátor BUSY hibáját kapja, nem az arbiter felülbírálását.

**Nem elfogadható gyengítés:** „preempt" mód bevezetése a Live-élmény javítására.

### D3 — A felfüggesztés MEGŐRZŐ művelet: `pause` ≠ `cancel`

A `ResourceConsumer` szerződése három műveletet ír elő —
`acquire`, `release`, `pauseForHigherPriority` —, és a felfüggesztett fogyasztó
`resume`-mal folytatható. `pauseForHigherPriority` után a fogyasztó
**folytatható állapotban** marad: a félbehagyott munka nem tűnik el, és a
fogyasztó maga tudja, hogy fel van függesztve (`isSuspended`).

A `cancel` (a részmunka eldobása) NEM a felfüggesztés implementációja. Egy
`pause`-t `cancel`-lel megvalósító fogyasztó a szerződést sérti, és ezt gépi
cella méri (`resource_arbiter_test.dart`, A5).

**Nem elfogadható gyengítés:** `cancel` hívása `pause` helyett, mert „egyszerűbb".

### D4 — A memória-nyomás a legalacsonyabb prioritásútól felfelé szabadít fel

Memória-nyomás jelzésekor az arbiter a **legalacsonyabb** prioritású AKTÍV
fogyasztót állítja le először, és felfelé halad. A legmagasabb prioritású aktív
fogyasztó (jellemzően a `liveAudio`) az utolsó, akihez hozzányúl.

**A jelzés az arbiter SAJÁT API-ja, nem platform-csatorna.** Mérve: a fán ma
nincs semmilyen low-memory forrás (lásd a Kontextus utolsó pontját), és a
platform-csatorna bekötése az arbiter fölötti réteg (app/lifecycle observer)
dolga. Ez a kör tehát a **döntést** rögzíti, nem a jelzés forrását; a bekötés
későbbi kör feladata, és ezt a szerződés-dokumentum kimondja.

### D5 — Az arbiter eredménye SAJÁT, `lib/core/resources`-lokális típus

Az arbiter döntése egy `lib/core/resources/**` alatt definiált, zárt
eredménytípus explicit indok-értékkel (megadva / elutasítva / a magasabb
prioritású miatt felfüggesztve). **Új `FailureCode` konstans nem születik**, és
az arbiter nem talál ki új hiba-sztringet.

**Indok (mért):** a `FailureCode` egyetlen forrása
`lib/core/foundation/app_failure.dart` (`FailureCode` abstract final class,
a doc-comment kimondja: „Never change an existing string — add a new one
instead"), és ez a fájl NINCS a kör engedélyezett listáján. Egy resources-lokális
sztring-konstans két helyre osztaná a kódszótárat — a kizárólagos erőforrások
BUSY-kódja (`audio.session_busy`, `camera.session_busy`) a koordinátoroké marad
és VÁLTOZATLAN, az arbiter döntése pedig nem hiba, hanem ütemezési eredmény.

### D6 — A helyi AI ebben a körben ABSZTRAKT fogyasztó marad

Az arbiter a `ResourceConsumer` szerződéssel dolgozik; a valódi helyi AI-futtató
bekötése az Epic 10 Kör 12 (`e10-r12-local-ai-resource-coordinator.md`) dolga. A
kör tesztjei fake fogyasztókkal mérnek.

**Indok:** az Epic 10 sávja `hold`-on áll, a `LocalAiResourceCoordinator`
felülete (SDD Ch10 §10.2: mikrofon-owner, kamera-owner, Analyze-állapot, termál,
battery saver, low-memory, modell-állapot, foreground/background) **még nem
végleges**. Az előre-implementálás két, egymásra író szerződést hozna létre.

**Nem elfogadható gyengítés:** az Epic 10 tervezett API-jának előre-implementálása.

### D7 — Az arbiter a `lib/core/` importszabály alá esik

`lib/core/resources/**` nem importálhat `lib/features/**`-ot
(`tool/check_architecture.dart:332-339`, `coreMustNotImportFeatures`). Az
arbiter tehát a fogyasztókat **szerződésen keresztül** ismeri, nem a vision
controllerek típusain keresztül.

## Következmények

- A két meglévő koordinátor viselkedése **változatlan**: a `test/core/audio/
  audio_session_coordinator_test.dart` és a `test/core/camera/
  camera_session_coordinator_test.dart` a kör gate-jében szerepel, és
  módosítás nélkül zöld kell legyen (A6).
- Az arbiter MA **egyetlen production hívóval sem rendelkezik** — ez szándékos:
  a bekötés (`lib/features/**`, `mic_capture.dart`) a kör tilos zónája, és
  külön kör dolga. A kör terméke a szerződés + a gépi mércéje, nem a bekötés.
- Mivel nincs bekötés, az „arbiteren keresztüli kamera-elengedés" nem mérhető a
  valódi app-fán; a mérés a VALÓDI `CameraSessionCoordinator` állapotán történik
  (`activeOwner == null`, `lease.isActive == false`), nem mockolt
  platform-csatornán ([L453](../LESSONS.md#l453)).
- A `didHaveMemoryPressure` bekötése, a termál-létra (ADR 0196) és a battery
  saver összekötése az arbiterrel későbbi körök feladata.
