# E02-R08 — Observation gateway és audio lifecycle adapter

Státusz: PLANNING
SDD: `docs/sdd/03-epic-02-practice-engine.md` §13 (§13.1–13.4), §12.4, §12.5, §8.2–8.3, „Kör 8"
Branch: `mm/e02-r08-observation-gateway`
Brief szerzője: Claude · Implementáció: **MiniMax M3** (a user döntése, 2026-07-31)
ADR: [0074](../adr/0074-practice-observation-gateway.md) — **már meg van írva, NE módosítsd**

---

## 0. Kör-jelzés — ezzel kezdd, mielőtt bármit olvasnál

A munkád első és utolsó lépése a jelzés (`AGENTS.md` §15.2):

```bash
tools/codex-signal.sh start "E02-R08 observation gateway"
# ... a kör vége:
tools/codex-signal.sh done "<egymondatos összefoglaló>"
# scope-ütközés / megválaszolatlan kérdés esetén:
tools/codex-signal.sh stopped "<mi akasztotta meg>"
```

Jelzés nélkül az orchestrátor a futásodat halottnak tekinti.

**A brief §8 a terved — nincs külön task-lista, nincs saját újratervezés.**
Ha a §8 lépései és a valóság ütközik: `stopped`, és írd le az ütközést.

---

## 1. Cél

A Live detektor `LiveFrame`-jei ma nem jutnak el a Practice V2 domainig. Ez a kör
megépíti azt a hidat: a `PracticeObservationGateway` szerződést, a `LiveFrame →
PracticeObservation` adaptert, és — a kör lényege — azt a **`const` táblát, ami a
mikrofon-hallgatást az E02-R07 session-státuszhoz köti**, nem egy widget-mezőhöz.

Miért most: az R07 óta van determinisztikus állapotgép; az R09 controller-kör csak
akkor tudja összekötni az órát, a targetet és a scorert, ha van tipizált,
tesztelhető bemeneti forrás.

Miért fontos a státusz-kötés: a mai legacy úton a hallgatás igazságforrása a
`learn_screen.dart` `_playing` / `_scorer != null` mezője, és mérten **a `_pause()`
nem zárja a frame-subscriptiont** → szünet alatt a mikrofon és a DSP-izolátum
tovább fut. A V2 úton ez szerkezetileg nem tud létrejönni.

---

## 2. Jelenlegi állapot (elolvasott kód alapján)

### 2.1 Ami már megvan

- `lib/features/practice/domain/model/practice_observation.dart` (E02-R03,
  **BEFAGYASZTVA**): sealed `PracticeObservation` (`at`), `StrumObservation`
  (`sequence`, `direction`, `confidence`), `ChordObservation` (`label`,
  `confidence`). Validáció: `at >= 0`, confidence véges és `0..1`, `sequence >= 0`,
  a chord-label kanonikus vagy `null` (`isCanonicalPracticeChordLabel`, 24 elem).
- `lib/features/practice/domain/model/practice_session_state.dart` (E02-R07):
  `PracticeSessionStatus` — **11 érték**: `idle`, `preparing`, `permissionRequired`,
  `ready`, `countIn`, `running`, `paused`, `finishing`, `completed`, `cancelled`,
  `failed`.
- `lib/features/practice/data/adapters/legacy_chord_label.dart` (E02-R05):
  `String? legacyPracticeChordLabel(String?)` — a legacy címkét a 24 elemű
  maj/min szótárra redukálja, értelmezhetetlenre `null`.
- `lib/features/live/public.dart`: exportálja a `engine/strum_engine.dart`-ot és a
  `providers/live_providers.dart`-ot. A `model/live_frame.dart`-ot **NEM**.
- `lib/features/live/model/live_frame.dart`: `LiveFrame` — `current` (`Chord?`),
  `latestStrum` (`Strum?`), `strumSeq` (int, új strumonként nő, default 0),
  `latestStrumTime` (double, az engine saját mintaóráján, `-1` = nincs),
  `engineTimeSec` (double, ugyanazon az órán, `-1` = nincs), `listening` (bool).
  **`confidence` getter = `latestStrum?.confidence ?? 0`, azaz STRUM-confidence.
  A `Chord`-nak NINCS confidence mezője.**
- `lib/core/audio/mic_capture.dart` + `lifecycle/` (ADR 0056): engedély →
  exkluzív lease → capture; `MicrophonePermissionGateway.currentState()/request()`,
  `MicrophonePermissionState.isGranted` / `.failure`.
- `lib/features/live/engine/real_strum_engine.dart`: `StrumEngine.start()` a
  **`Future<void>`** — a foglalt mikrofont / capture-hibát a `frames` streamre
  teszi `addError`-ral, engedélyhiány esetén egy `LiveFrame.empty`-t ad.
- `test/support/fake_engines.dart`: **`FakeStrumEngine` már létezik** —
  `startCalls`, `stopCalls`, `expectedChordCalls`, `emit(LiveFrame)`,
  `emitError(Object)`. **Ez elég; a fájlt NEM módosíthatod.**
- `tools/round-gate.sh`: a futtatható gate-artefaktum.

### 2.2 A legacy referencia-viselkedés (ezt kell megőrizni)

`lib/features/learn/screens/learn_screen.dart` `_onFrame` (≈163–206):

```dart
if (frame.strumSeq > _lastSeq && frame.latestStrum != null) {
  _lastSeq = frame.strumSeq;
  var at = _elapsedSec;
  final lag = frame.engineTimeSec - frame.latestStrumTime;
  if (frame.engineTimeSec >= 0 && frame.latestStrumTime >= 0 &&
      lag > 0 && lag < 0.5) {
    at -= lag;
  }
  ... _scorer!.registerStrum(frame.latestStrum.direction, at);
}
```

A **kalibrált** input latency NEM itt van levonva, hanem a `LessonScorer`-ben
(`inputLatencySec`). Ez a felosztás a parity-alap része — ne told át.

`_pause()` (≈235–240): csak a `Ticker`-t állítja meg és a `_playing`-et billenti;
`_frameSub` nyitva marad. Ez a chunk 014 pause-rése — **a legacy fájlt ebben a
körben NEM nyúlod meg.**

### 2.3 Ami nincs

Nincs gateway-interfész, nincs Live adapter, nincs fake gateway, nincs
státusz→capture policy, és a `PracticeObservation`-nek nincs egyetlen production
előállítója sem.

---

## 3. Scope

**Benne:**

1. `PracticeObservationGateway` interfész + `PracticeObservationConfig` érték-objektum.
2. `practiceCaptureActiveByStatus` — `const` tábla mind a 11 státuszra + a
   `practiceCaptureActive(status)` pure függvény.
3. `LivePracticeObservationGateway` — a `StrumEngine` frame-jeiből observation.
4. Fake gateway a `test/support/` alatt (az R09/R10 integrációs tesztek bemenete).
5. Négy új hibakód / validációs kód (§5.7).
6. `lib/features/live/public.dart` +1 export.
7. Tesztek + randomizált property-őr.

**Kívül (ebben a körben TILOS):**

- Bármilyen Riverpod provider a gatewayhez (`application/providers.dart` NEM jön létre).
- Bármilyen UI / képernyő / ARB-string.
- A legacy Learn út (`lib/features/learn/**`) bármilyen módosítása — beleértve a
  `_pause()` pause-rését. Az a migrációs kör (E02-R11) dolga, mert
  felhasználó-látható és valódi eszközön kell verifikálni.
- DSP / ML / `lib/core/audio/**` / `lib/features/live/engine/**` módosítás.
- A `ScoringProfile`, a `PracticeObservation`, a `CompiledPracticeTarget` vagy
  bármely befagyasztott domain-modell mezőbővítése.
- A matcher / scorer (E02-R09).
- A kalibrált input latency alkalmazása.
- ADR és RAG-chunk írás — **a 0074 ADR és a chunk 014 már kész, Claude írta.**

---

## 4. Engedélyezett fájlok

Csak az alábbi útvonalak módosíthatók/hozhatók létre. Bármi más → **MEGÁLLÁS**
(`tools/codex-signal.sh stopped`) és jelentés.

| Útvonal | Miért |
|---|---|
| `lib/features/practice/application/practice_observation_gateway.dart` | ÚJ — §5.1 interfész + §5.2 config |
| `lib/features/practice/application/practice_observation_activation.dart` | ÚJ — §5.3 státusz→capture tábla |
| `lib/features/practice/data/live_practice_observation_gateway.dart` | ÚJ — §5.4–5.8 Live adapter |
| `lib/features/practice/domain/model/practice_validation.dart` | §5.7 — HÁROM új kód a lista végére + `allCodes` |
| `lib/core/foundation/app_failure.dart` | §5.7 — KETTŐ új kód, kizárólag a `// --- practice ---` szekcióba |
| `lib/features/live/public.dart` | §5.9 — EGYETLEN új export sor |
| `test/support/fake_practice_observation_gateway.dart` | ÚJ — a fake gateway |
| `test/features/practice/application/practice_observation_gateway_test.dart` | ÚJ — config-validáció + fake-szerződés |
| `test/features/practice/application/practice_observation_activation_test.dart` | ÚJ — a 11 soros tábla |
| `test/features/practice/data/live_practice_observation_gateway_test.dart` | ÚJ — az adapter mátrixai |
| `test/features/practice/domain/practice_validation_test.dart` | az új kódok felvétele a meglévő állításokba |
| `test/property/practice_observation_property_test.dart` | ÚJ — randomizált őr |
| `docs/rounds/e02-r08-observation-gateway.md` | **kizárólag a §10 handoff szekció** |

**Tilos zóna** (a felsoroltakon kívül minden, kiemelten):
`lib/features/learn/**` · `lib/features/live/**` a `public.dart` EGY sora kivételével ·
`lib/core/audio/**` · `lib/features/practice/domain/model/practice_observation.dart` ·
`lib/features/practice/domain/model/scoring_profile.dart` ·
`lib/features/practice/application/practice_session_*.dart` ·
`test/support/fake_engines.dart` · `docs/adr/**` · `docs/rag/**` · `HANDOFF.md` ·
`tool/check_architecture.dart` (az allowlist NEM bővülhet).

> **ÚJ fájl létrehozása is scope-sértés, ha nincs a listán — akkor is, ha „csak
> teszt".** Mért eset: E02-R07 javító kör, 456 soros új tesztfájl az explicit
> tiltás ellenére (`docs/reviews/e02-r07-review.md` §7.3).

---

## 5. Kötött architekturális döntések

Ezeket a kör NEM tervezheti újra. Mind az [ADR 0074](../adr/0074-practice-observation-gateway.md)-ben
van indokolva — olvasd el, mielőtt kódot írsz.

### 5.1 Az interfész — SDD §13.1 szó szerint + `dispose()`

`lib/features/practice/application/practice_observation_gateway.dart`:

```dart
abstract interface class PracticeObservationGateway {
  Stream<PracticeObservation> get observations;
  Future<AppResult<void>> start({required PracticeObservationConfig config});
  void setExpectedChord(String? chord);
  Future<AppResult<void>> stop();
  Future<void> dispose();
}
```

Se több metódus, se kevesebb.

### 5.2 `PracticeObservationConfig`

Ugyanabban a fájlban, `@immutable`, `const` konstruktorral, érték-egyenlőséggel
(`==` + `hashCode`), a projekt mintája szerint:

```dart
const PracticeObservationConfig({
  this.strumMinConfidence = 0.55,
  this.chordMinConfidence = 0.60,
  this.chordStableDuration = const Duration(milliseconds: 180),
  this.maxFrameDeliveryLag = const Duration(milliseconds: 500),
});
```

Az értékek a SDD §13.4 kezdőértékei. `List<PracticeValidationFailure> validate()`
a §5.7 kódjaival. A küszöbök **nem** a `ScoringProfile`-ban élnek (ADR 0074 §5).

### 5.3 A státusz→capture tábla

`lib/features/practice/application/practice_observation_activation.dart` —
Flutter-mentes, óra-mentes, csak a `practice_session_state.dart`-ot importálja:

```dart
const Map<PracticeSessionStatus, bool> practiceCaptureActiveByStatus = {
  PracticeSessionStatus.idle: false,
  PracticeSessionStatus.preparing: false,
  PracticeSessionStatus.permissionRequired: false,
  PracticeSessionStatus.ready: false,
  PracticeSessionStatus.countIn: true,
  PracticeSessionStatus.running: true,
  PracticeSessionStatus.paused: false,
  PracticeSessionStatus.finishing: false,
  PracticeSessionStatus.completed: false,
  PracticeSessionStatus.cancelled: false,
  PracticeSessionStatus.failed: false,
};

bool practiceCaptureActive(PracticeSessionStatus status) => …;
```

A `practiceCaptureActive` a **táblából** olvas (hiányzó kulcsra fail-fast, ne
csendes `false`). A doc-comment mondja ki: az egyetlen jogos hívó az E02-R09
controller, és a hallgatás igazságforrása ez a tábla, soha nem widget-mező.

**A gateway maga nem ismeri a `PracticeSessionStatus`-t** — a
`live_practice_observation_gateway.dart` NEM importálhatja a
`practice_session_state.dart`-ot.

### 5.4 A Live adapter konstrukciója

```dart
LivePracticeObservationGateway({
  required StrumEngine engine,
  required MicrophonePermissionGateway permissions,
  required Duration Function() timelineNow,
  required AppLogger logger,
})
```

- `timelineNow` a session-idővonal aktuális pozíciója (R09: `state.timelinePosition`).
  A gateway **nem** példányosít `Stopwatch`-ot és nem hív `DateTime.now()`-t.
- `observations` **broadcast** stream, a konstruktorban jön létre, és csak a
  `dispose()` zárja — start/stop ciklusokon át él, hogy a fogyasztónak ne kelljen
  újra feliratkoznia.

### 5.5 Az idő — a legacy képlet szó szerint

Minden emittált observationre:

```text
lagSec  = engineTimeSec − latestStrumTime
lagAlkalmazandó ⟺ engineTimeSec >= 0 ÉS latestStrumTime >= 0
                   ÉS lagSec > 0 ÉS lagSec < maxFrameDeliveryLag
lag     = alkalmazandó ? Duration(microseconds: (lagSec * 1e6).round()) : Duration.zero
raw     = timelineNow() − lag
at      = max(lastEmittedAt, max(Duration.zero, raw))
```

- **Szigorú `<`** a felső határon — ez a legacy predikátum (`lag < 0.5`). A SDD
  §12.4 „0.5-nél nagyobb" szövegétől pontosan a `lag == 500 ms` pontban tér el;
  **a parity nyer**, és ezt doc-commentben rögzítsd (ADR 0074 §3).
- Egyszeri kerekítés µs-ra (ADR 0072 §1.1).
- Ha a lag **>= `maxFrameDeliveryLag`**: lag = 0 **és** `logger.warning` — de
  legfeljebb másodpercenként egyszer, a `timelineNow()`-ra mérve (§5.8).
- A **kalibrált** input latency NEM itt jön le (R09).
- `lastEmittedAt` a `start()`-nál `Duration.zero`-ra áll vissza.

### 5.6 Mit emittál

**Strum.** `frame.strumSeq > lastSeenSeq && frame.latestStrum != null` esetén:

1. `lastSeenSeq = frame.strumSeq` (a dedup-alap **akkor is** frissül, ha a
   confidence miatt eldobjuk — különben ugyanaz a strum később újra bejönne);
2. ha `confidence` nem véges → eldobás (nincs observation, nincs log);
3. ha `confidence < config.strumMinConfidence` → eldobás (a küszöb **inkluzív**:
   `>=` átmegy);
4. különben `StrumObservation(at: …, sequence: nextSequence++, direction:
   frame.latestStrum.direction, confidence: …)`.

A `sequence` a **gateway saját, sűrű számlálója**, `start()`-onként 0-ról
(SDD §12.5 „új observation sequence baseline"). Eldobott strum **nem** fogyaszt
sorszámot. Az engine `strumSeq`-je soha nem kerül át az observationbe.

**Chord.** Minden feldolgozott frame-en: `label = legacyPracticeChordLabel(
frame.current?.label)` (a `null` és az értelmezhetetlen egyaránt `null` →
„nincs akkord"). `ChordObservation` akkor emittálódik, ha:

- a `label` eltér az utoljára emittálttól (change-point), **VAGY**
- `timelineNow() − utolsóChordEmisszióIdeje >= config.chordStableDuration`
  (stabilitási újramintavétel).

`confidence: 1.0` — jelentése **„nem mért"**, mert a `LiveFrame` nem hordoz
chord-confidence-t (ADR 0074 §6). Ezt a doc-comment mondja ki, és teszt rögzíti.
Következmény: a `chordMinConfidence` ma a Live úton nem szűr — ezt **nem
elrejteni** kell, hanem kimondani.

**Semmi mást.** A gateway nem emittál duplikált frame-re (ugyanaz a `strumSeq` +
változatlan label → 0 observation), és `start()` előtt / `stop()` után egyet sem.

### 5.7 Új kódok

`lib/features/practice/domain/model/practice_validation.dart` — a lista **végére**,
és fel kell venni az `allCodes` halmazba is (meglévő kódot átnevezni/átsorolni tilos):

```dart
static const String observationConfigConfidenceOutOfRange =
    'observationConfig.confidence.outOfRange';
static const String observationConfigStableDurationNonPositive =
    'observationConfig.stableDuration.nonPositive';
static const String observationConfigMaxLagNonPositive =
    'observationConfig.maxLag.nonPositive';
```

`lib/core/foundation/app_failure.dart` — kizárólag a `// --- practice ---` szekcióba:

```dart
static const String practiceObservationStreamFailed =
    'practice.observation_stream_failed';
static const String practiceObservationGatewayDisposed =
    'practice.observation_gateway_disposed';
```

### 5.8 Életciklus és hibaleképezés

**`start(config:)`:**

1. ha `dispose()`-olt → `Failure(code: practiceObservationGatewayDisposed)`;
2. ha már fut → **no-op `Success`** (az engine `start()`-ja nem hívódik újra);
3. `config.validate()` nem üres → `Failure(ConfigurationFailure(code:
   FailureCode.configurationInvalid, cause: <a `List<PracticeValidationFailure>`>))`
   — az `AppFailure`-nek nincs `message` mezője, a részletek a `cause`-ban utaznak;
4. engedély: `permissions.currentState()`; ha nem granted → `permissions.request()`;
   ha úgy sem → `Failure(state.failure!)` — és az engine `start()`-ja **nem** hívódik;
5. feliratkozás az `engine.frames`-re, majd `await engine.start()`;
6. számlálók nullázása (`sequence`, `lastSeenSeq`, `lastEmittedAt`, chord-baseline);
7. a legutoljára beállított expected chord újra-érvényesítése az engine felé;
8. `Success(null)`.

**`stop()`:** idempotens `Success`; sorrend: subscription lezárása →
`engine.setExpectedChord(null)` → `await engine.stop()`. Kétszeri hívásra az
engine `stop()`-ja **egyszer** fut.

**`dispose()`:** `stop()` + az `observations` stream lezárása. Utána minden
`start()`/`stop()` `Failure(practiceObservationGatewayDisposed)`, a
`setExpectedChord` no-op.

**Stream-hiba:** ha az `engine.frames` hibát ad,

- `AppFailure` típusú hiba **változatlanul** kerül az `observations` stream
  hibaeseményére (így a `audio.session_busy` kód átmegy);
- minden más `AudioFailure(code: FailureCode.practiceObservationStreamFailed,
  cause: <az eredeti>)`-be csomagolva;
- utána a gateway belsőleg leáll (mikrofon elengedve), de **újraindítható**, és
  az `observations` stream NEM záródik be.

**Logolás:** observationönként SOHA. Logolható: capture start/stop,
engedély-megtagadás, leképezett stream-hiba, tartományon kívüli lag
(másodpercenként legfeljebb egyszer).

### 5.9 Cross-feature import

A `data/live_practice_observation_gateway.dart` a Live feature-t **kizárólag**
`package:strumsight/features/live/public.dart`-on át éri el (relatív úton:
`../../live/public.dart`). Ehhez a `public.dart` egyetlen sort kap:

```dart
/// The frame the Practice observation gateway adapts (E02-R08).
export 'model/live_frame.dart';
```

Ha a `LiveFrame` használatához a `model/beat_slot.dart` exportja is kell,
felveheted — **minden más export felvétele STOP.** Az
`architectureAllowlist` NEM bővülhet; ha a `tool/check_architecture.dart` piros,
az azt jelenti, hogy rossz úton importálsz.

### 5.10 Nincs hívó

A kör nem hoz létre providert, nem köt be UI-t, nem módosít legacy fájlt.
A `grep -rn 'LivePracticeObservationGateway\|practiceCaptureActiveByStatus\|PracticeObservationGateway' lib/`
találatai kizárólag `lib/features/practice/` alattiak lehetnek.

---

## 6. Acceptance criteria

Minden pont **mért** állítás. Ahol mátrix szerepel, a mátrix MINDEN cellája
külön eset (a fixture-default kiválaszthat olyan pontot, ahol a hibás és a helyes
implementáció megkülönböztethetetlen — E02-R07 mért tanulsága, `docs/LESSONS.md` L10).

### 6.1 Aktivációs tábla

- [ ] A teszt végigmegy a `PracticeSessionStatus.values` **mind a 11** elemén, és
      státuszonként literálisan állítja a várt `bool`-t.
- [ ] Külön állítás: `practiceCaptureActiveByStatus.keys.toSet()` **egyenlő**
      `PracticeSessionStatus.values.toSet()`-tel (új státusz ⇒ piros).
- [ ] Külön, megnevezett teszt: `paused → false`, kommentben a chunk 014 pause-résre
      hivatkozva.
- [ ] **NEM elfogadható gyengítés:** a `const Map` elhagyása és
      `status == running || status == countIn` kifejezéssel helyettesítése; a
      kulcshalmaz-egyezés tesztjének elhagyása; olyan teszt, ami csak a `running`
      sort méri.

### 6.2 Lag-guard mátrix (§5.5)

- [ ] `timelineNow ∈ {0 s, 10 s}` × `(engineTimeSec, latestStrumTime) ∈`
      `{(-1,-1), (-1, 0.5), (1.0, -1), (1.0, 1.0), (1.0, 0.90), (1.0, 1.10),
      (1.0, 0.50), (1.0, 0.5001)}` — minden cellára a várt `at` **literálisan**
      kiszámolva a tesztben, nem az implementáció képletével.
- [ ] A `(1.0, 0.50)` cella (lag pontosan 500 ms) elvárt eredménye: **a lag NEM
      kerül levonásra** (szigorú `<`, legacy-parity), és a logger pontosan egy
      warning-ot kap.
- [ ] A `(1.0, 1.10)` cella (negatív lag) elvárt eredménye: lag = 0, **nincs** log.
- [ ] **NEM elfogadható gyengítés:** csak a „normál" (0 < lag < 0.5) esetet mérni;
      a határpontot (`== maxFrameDeliveryLag`) kihagyni.

### 6.3 Confidence-határ

- [ ] `strumMinConfidence = 0.55` mellett a `confidence ∈ {0.0, 0.5499, 0.55,
      0.5501, 1.0}` mátrix: emisszió pontosan `>= 0.55` esetén.
- [ ] Nem véges confidence (`double.nan`, `double.infinity`) → nincs observation,
      nincs dobott kivétel.
- [ ] Egy eldobott (küszöb alatti) strum után **ugyanaz a `strumSeq`** újra
      beküldve továbbra sem ad observationt (a dedup-alap frissült).
- [ ] **NEM elfogadható gyengítés:** csak 0.0 és 1.0 pontokon mérni.

### 6.4 Monotonitás és sűrű sorszám

- [ ] Olyan eset, ahol **változatlan `timelineNow()` mellett** egy nagy lagú frame
      után egy lag nélküli frame érkezik → a második observation `at`-ja **nem
      kisebb** az elsőnél (clamp).
- [ ] Olyan eset, ahol a `strumSeq` 5-ről 9-re ugrik (elveszett frame-ek) → az
      observationök `sequence`-e **0, 1** (nem 5, 9).
- [ ] Két küszöb feletti strum között egy küszöb alatti → a sorszámok **0, 1**
      (az eldobott nem fogyaszt sorszámot).
- [ ] `start()` → 3 strum → `stop()` → `start()` → 1 strum: az utolsó observation
      `sequence`-e **0**, `at`-ja nincs a régi `lastEmittedAt`-hoz clampelve.
- [ ] **NEM elfogadható gyengítés:** a monotonitást csak monoton növekvő
      `timelineNow()`-val „bizonyítani"; a `sequence`-t a `frame.strumSeq`-ből venni.

### 6.5 Chord-mintavétel

- [ ] Ugyanaz a label 10 egymást követő frame-en, a `chordStableDuration`-nél
      rövidebb idő alatt → **pontosan 1** `ChordObservation`.
- [ ] Label-váltás (`C` → `G`) → új observation.
- [ ] Akkordból „nincs akkord" (`frame.current == null`) → `label: null`
      observation (ez is change-point).
- [ ] Nem kanonikus label a detektorból (`Em7`, `G/B`, `H`) →
      `legacyPracticeChordLabel` szerinti eredmény (`Em`, `G`, `null`), és az
      emittált observation `validate()`-je **üres** (mind a 24+null halmazban van).
- [ ] Változatlan label, de eltelt `chordStableDuration` → újramintavétel.
- [ ] Teszt rögzíti, hogy a Live úton a `confidence` **mindig 1.0**, és hogy ez
      „nem mért"-et jelent (a `chordMinConfidence` emelése 0.99-re **sem** szűr ki
      chordot) — a viselkedés kimondva, nem elrejtve.

### 6.6 Életciklus

- [ ] `start` ×2 → mindkettő `Success`, `engine.startCalls == 1`.
- [ ] `stop` ×2 → mindkettő `Success`, `engine.stopCalls == 1`.
- [ ] `dispose()` után `start()`/`stop()` → `Failure`, kód
      `practice.observation_gateway_disposed`; az `observations` stream lezárva.
- [ ] `setExpectedChord('G')` → `engine.expectedChordCalls` utolsó eleme `'G'`;
      `stop()` után az utolsó elem `null`.
- [ ] `setExpectedChord('G')` a `start()` **előtt** → a sikeres `start()` után az
      engine újra megkapja a `'G'`-t.

### 6.7 Hibaleképezés

- [ ] Megtagadott engedély → `start()` `Failure(PermissionFailure)`, és
      `engine.startCalls == 0`.
- [ ] Csak `request()` után granted → `engine.startCalls == 1`.
- [ ] Érvénytelen config (pl. `strumMinConfidence: 1.5`) → `Failure`, kód
      `configuration.invalid`, a `cause` tartalmazza a
      `observationConfig.confidence.outOfRange` kódot; `engine.startCalls == 0`.
- [ ] `engine.emitError(AudioFailure(code: FailureCode.audioSessionBusy, …))` →
      az `observations` stream **hibaeseménye** ugyanaz az `AppFailure`
      (`audio.session_busy`), `engine.stopCalls == 1`, a stream **nem zárul be**,
      és egy újabb `start()` sikerül.
- [ ] `engine.emitError(StateError('boom'))` → `AudioFailure` a
      `practice.observation_stream_failed` kóddal.
- [ ] A hiba után beküldött frame **nem** ad observationt.

### 6.8 Log-fegyelem

- [ ] 200 érvényes, observationt eredményező frame feldolgozása után a logger
      **egyetlen** bejegyzést sem kapott a start/stop páron felül.
- [ ] Tíz, tartományon kívüli lagú frame ugyanabban a másodpercben → **1** warning.

### 6.9 Property-őr (`test/property/practice_observation_property_test.dart`)

`PROPERTY_SEED` env (hiányzik → 42), a `practice_session_property_test.dart`
mintája szerint. Randomizált frame-sorozatokon **100%-ban** kell teljesülnie:

- [ ] az emittált `at` értékek nem csökkennek;
- [ ] a `StrumObservation.sequence`-ek pontosan `0..n-1`, hézag nélkül;
- [ ] minden emittált observation `validate()`-je üres;
- [ ] `start()` nélkül / `stop()` után nulla observation;
- [ ] `at >= Duration.zero` minden esetben.
- [ ] **Valódi-sértés próba (kötelező, futtatva jelentendő):** a monoton clamp
      (`max(lastEmittedAt, …)`) szándékos eltávolítása után a property gate
      **pirosra vált** — a §10 handoffban a tényleges kimenettel. Ha zöld marad,
      a property vacuous, és a kör nincs kész.

### 6.10 Semlegesség

- [ ] `git diff --stat` a §4 listán kívül **nulla** fájlt mutat.
- [ ] `grep -rn 'LivePracticeObservationGateway\|practiceCaptureActiveByStatus\|PracticeObservationGateway' lib/`
      csak `lib/features/practice/` alatti találatot ad.
- [ ] `lib/features/learn/**` és `lib/features/live/engine/**` diffje **üres**;
      a `lib/features/live/public.dart` diffje legfeljebb 2 export sor + doc.
- [ ] `tool/check_architecture.dart` zöld, az `architectureAllowlist` változatlan.

---

## 7. Kötelező ellenőrzések

**Egyetlen parancs — szó szerint ez, csővezeték és `tail` NÉLKÜL:**

```bash
tools/round-gate.sh test/features/practice/ test/property/practice_observation_property_test.dart
```

A script a `format` → `analyze` → `test …` → `architecture` lépéseket külön
processzként, csonkítatlan kimenettel futtatja, és az első piros lépésnél megáll.

> **Tilos** a kimenetet `| tail`, `| head`, `| grep`, `> /dev/null` vagy bármilyen
> csővezeték mögé tenni. A csővezeték elrejti a kilépési kódot, így a „minden gate
> zöld" jelentés bizonyíthatatlan. Mért eset: E02-R07, három tiltott `| tail`
> futás (`docs/LESSONS.md` L09).

A teljes suite + randomizált property gate + APK a CI-ban fut
([ADR 0053](../adr/0053-ci-full-test-suite.md)) — azt az **orchestrátor** indítja.
**Te `gh`-t nem hívsz.**

---

## 8. Implementációs sorrend

1. **Kódok** (§5.7): `practice_validation.dart` három kódja + `allCodes`;
   `app_failure.dart` két kódja. `practice_validation_test.dart` frissítése.
2. **Interfész + config** (§5.1–5.2): `practice_observation_gateway.dart`,
   `validate()`-tel és érték-egyenlőséggel. Teszt: `..._gateway_test.dart`
   config-validációs része.
3. **Aktivációs tábla** (§5.3): `practice_observation_activation.dart` +
   `..._activation_test.dart` (§6.1 mind a négy pontja).
4. **`live/public.dart`** (§5.9): a `LiveFrame` export.
5. **Fake gateway**: `test/support/fake_practice_observation_gateway.dart` —
   vezérelhető `Stream`, rögzített `start`/`stop`/`setExpectedChord` hívások,
   injektálható `AppResult` a `start()`-ra. A `..._gateway_test.dart` méri, hogy
   a fake a §5.1 szerződést tartja (start/stop idempotencia, dispose).
6. **Live adapter váza** (§5.4, §5.8): konstrukció, életciklus, hibaleképezés.
   Teszt: §6.6 + §6.7.
7. **Frame → observation** (§5.5–5.6): idő, strum, chord. Teszt: §6.2–6.5.
8. **Log-fegyelem** (§5.8 vége). Teszt: §6.8. A tesztfájl saját, lokális
   `AppLogger`-implementációt használjon (ne hozz létre új support-fájlt).
9. **Property-őr** (§6.9), a valódi-sértés próbával együtt.
10. **Gate** (§7), majd a §10 handoff kitöltése és `tools/codex-signal.sh done`.

---

## 9. Kockázatok

- **A `LiveFrame`-nek nincs chord-confidence-e.** A kísértés az, hogy a
  `frame.confidence`-t (ami a STRUM confidence-e) használd chordhoz. Ne tedd:
  `1.0` = „nem mért", ahogy §5.6 előírja.
- **A `strumSeq` és az observation `sequence` összekeverése.** Két külön fogalom
  (§5.6); a §6.4 mátrixa pont ezt méri.
- **A lag felső határa.** A SDD szövege és a legacy kód a `== 500 ms` pontban
  eltér; a parity nyer (§5.5), és ezt doc-commentben rögzíted.
- **Az architektúra-őr.** A Live feature-t csak a `public.dart`-on át szabad
  elérni; közvetlen `../../live/model/live_frame.dart` import pirosra váltja a
  `check_architecture.dart`-ot.
- **Túlnyúlás a legacy pause-résre.** Csábító a `learn_screen.dart` `_pause()`-át
  „menet közben megjavítani". TILOS (§3): felhasználó-látható, eszközös
  verifikációt igényel, és a migrációs kör (E02-R11) hatásköre.
- **Doc-comment mint bemondás.** Csak olyan állítást írj a kódba, amit teszt
  bizonyít (`const`, „idempotens", „monoton"). Mért eset: E02-R04 valótlan `const`
  doc-comment.

---

## 10. Implementation handoff — a MiniMax M3 tölti ki

- Fájlonkénti összefoglaló.
- Futtatott parancsok + **TÉNYLEGES** kimenet (a `tools/round-gate.sh` teljes
  gate-összegzése, csonkítatlanul).
- A §6.9 valódi-sértés próba tényleges kimenete (piros property gate).
- Eltérések a tervtől és okuk.
- Nem futtatott ellenőrzések és okuk.
- Follow-up issue-k.

> **Minden viselkedési állításhoz add meg a tesztet, ami bizonyítja.** Állítás
> teszt nélkül = bemondás (E02-R07 handoff, `docs/LESSONS.md` L11).

## 11. Review — a Claude tölti ki

Link: `docs/reviews/e02-r08-review.md`
