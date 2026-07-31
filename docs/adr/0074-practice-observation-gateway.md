# ADR 0074 — Practice observation gateway és a státusz-vezérelt mikrofon-életciklus

- **Státusz:** Elfogadva (2026-07-31)
- **Kör:** E02-R08 — Observation gateway és audio lifecycle adapter
- **SDD:** `docs/sdd/03-epic-02-practice-engine.md` §13 (observation gateway),
  §12.4 (input latency), §12.5 (pause/resume), §8.2–8.3 (rétegek), „Kör 8"
- **Előzmények:** [ADR 0056](0056-exclusive-microphone-session.md) (exkluzív
  mikrofon-lease), [ADR 0068](0068-practice-domain-model-contracts.md)
  (`PracticeObservation` szerződés), [ADR 0071](0071-legacy-practice-adapters.md)
  (`legacyPracticeChordLabel`), [ADR 0072](0072-practice-target-compiler.md)
  (§1.1 időszabály), [ADR 0073](0073-practice-session-state-machine.md)
  (state machine, `PracticeSessionStatus`)

## Kontextus

Az E02-R07 után megvan a determinisztikus session state machine és az órája.
Ami hiányzik: a **bemenet** — a Live detektor `LiveFrame`-jei nem jutnak el a
Practice V2 domainig, és nincs olyan egység, ami a nyers frame-eket
`PracticeObservation`-né alakítaná.

A mai (legacy) Learn út ezt a `learn_screen.dart` `State`-jében teszi:
`_frameSub ??= ref.listenManual(liveFrameProvider, _onFrame)` a `_play()`-ben,
és a `_onFrame` a `_scorer != null` mezőre néz. **A `_pause()` nem zárja a
subscriptiont** — a `docs/rag/chunks/014-play-along-learn.md` állítása
(„subscribes … only while playing, closed on pause/dispose") mérten valótlan:
szünet alatt a mikrofon nyitva marad, az `autoDispose` nem old el, a DSP-izolátum
fut tovább. Ez az Epic 2 „pause-rése" (HANDOFF §6.4 follow-up).

A gyökér ok nem egy elfelejtett `close()` hívás, hanem az, hogy a **hallgatás
igazságforrása egy widget-mező** (`_playing` / `_scorer != null`) volt. Egy
widget-mező nem auditálható, nem tesztelhető widget-teszt nélkül, és nincs
kikényszerítve, hogy minden állapotváltásnál karbantartsák.

## Döntés

### 1. A hallgatás igazságforrása a `PracticeSessionStatus`, nem widget-flag

Új, tiszta (Flutter-mentes, óra-mentes) policy:
`lib/features/practice/application/practice_observation_activation.dart`.

```dart
const Map<PracticeSessionStatus, bool> practiceCaptureActiveByStatus = { … };
bool practiceCaptureActive(PracticeSessionStatus status);
```

A tábla **mind a 11 státuszra** kiterjed, és a kulcshalmaza gépi teszttel egyezik
a `PracticeSessionStatus.values`-szal — új státusz hozzáadása pirosra vált, nem
csendes `false`-ra esik vissza (ugyanaz a minta, mint az R07 `allowedTransitions`).

Kötött értékek:

| Státusz | capture | Miért |
|---|---|---|
| `countIn` | **be** | bemelegítés: a mikrofon és a DSP-izolátum a count-in alatt áll fel, hogy az első ütés ne vesszen el |
| `running` | **be** | ez az egyetlen státusz, ahol a megfigyelés pontozási értékű |
| `paused` | **ki** | **ez a chunk 014 pause-résének lezárása**: a szünet elengedi a mikrofont (§12.5 „mikrofon policy alapján felszabadítható") |
| `idle`, `preparing`, `permissionRequired`, `ready`, `finishing`, `completed`, `cancelled`, `failed` | ki | nincs pontozott bemenet |

A `finishing` szándékosan **ki**: a legacy `_finish()` is azonnal `finalize()`-ol,
tehát a ring-out alatti késői ütés ma sem pontozódik. A `totalDuration`
tartalmazza a ring-outot, így a ring-out még `running` alatt zajlik — parity-veszteség
nincs.

A gateway maga **nem ismeri** a state machine-t: a policy az `application/` rétegben
pure függvény, a `data/` adaptert a controller (E02-R09) start/stop hívásokkal vezérli.
Ez tartja a §8.3 „az audio gateway ne ismerje a presentation réteget" szabályt, és
azt is, hogy a domain ne függjön az adaptertől.

### 2. A gateway-szerződés a SDD §13.1 + `dispose()`

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

A `dispose()` a §13.1-hez képest kiegészítés (a „Kör 8" feladatlistája explicit
`dispose` tesztet ír elő); minden más szó szerint a §13.1.

### 3. Az idő: a gateway CSAK az engine-óra de-jittert alkalmazza

A §12.4 képlete:

```text
playedAt = observedAt − calibratedInputLatency − frameDeliveryLag
```

A gateway ebből **kizárólag** a `frameDeliveryLag = engineTimeSec − latestStrumTime`
tagot vonja le. A `calibratedInputLatency` (user-kalibrált konstans,
`inputLatencyProvider`) a **matcher/controller** dolga marad (E02-R09).

Miért így: pontosan ez a legacy felosztás — a `learn_screen.dart` `_onFrame`-je
de-jitterez, a `LessonScorer` pedig `inputLatencySec`-kel korrigál. A parity-mérce
(ADR 0067) ezen a felosztáson lett befagyasztva; ha a gateway is levonná a
kalibrált latenciát, az duplán számítana, vagy a matcher szerződését kellene
megváltoztatni. Így a `PracticeObservation` (befagyasztott, E02-R03) sem kap új
metaadat-mezőt.

Sanity guard, §12.4 szó szerint:

- hiányzó engine-óra (`engineTimeSec < 0` vagy `latestStrumTime < 0`) → lag = 0;
- negatív lag → 0;
- `config.maxFrameDeliveryLag`-nál (alapérték 500 ms) nagyobb lag → **figyelmen
  kívül hagyva (lag = 0) és logolva**.

A lag µs-ban, **egyszeri** kerekítéssel áll elő (ADR 0072 §1.1 fegyelme).

### 4. `at` monoton, `sequence` sűrű és a starttal újraindul

```text
at = max(lastEmittedAt, max(Duration.zero, timelineNow() − lag))
```

A monoton-clamp nem kozmetika: a de-jitter visszafelé mozgat, tehát két frame
között az `at` csökkenhetne — a §10.6 „observation idő monotonic" invariánsa
ezt tiltja.

A `StrumObservation.sequence` a **gateway saját, sűrű számlálója** (0, 1, 2, …),
ami minden `start()`-nál nullázódik — ez a §12.5 „új observation sequence
baseline szükséges" követelménye. Az engine `strumSeq`-je **kizárólag**
duplikátum-szűrésre szolgál (`frame.strumSeq > lastSeenSeq`), nem kerül át az
observationbe. Eldobott (küszöb alatti) strum **nem** fogyaszt sorszámot.

### 5. Confidence-küszöbök a gateway configjában, nem a `ScoringProfile`-ban

A §13.4 a küszöböket a scoring profile részeként képzeli el. Ettől **tudatosan
eltérünk**: a `ScoringProfile` az E02-R04/R05 óta befagyasztott parity-alap
(`legacyLearnParity` `const`), és egy mezőbővítés a parity-golden újragenerálását
kockáztatná. A küszöbök ezért a `PracticeObservationConfig`-ban élnek
(`strumMinConfidence` 0.55, `chordMinConfidence` 0.60, `chordStableDuration`
180 ms, `maxFrameDeliveryLag` 500 ms — a §13.4 kezdőértékei). A profil→config
leképezés az E02-R09 controller-kör feladata. A §13.4 valódi követelménye — „ne
a UI-ban legyen hardcode-olva" — teljesül.

A küszöb-határ **inkluzív**: `confidence >= min` átmegy.

### 6. A `LiveFrame` nem hordoz chord-confidence-t — ezt kimondjuk, nem elfedjük

A `LiveFrame.confidence` a **strum** confidence-e (`latestStrum?.confidence`); a
`Chord` modellnek nincs confidence mezője. A Live adapter ezért a
`ChordObservation.confidence`-t `1.0`-ra állítja, aminek a jelentése **„nem
mért"**, nem „biztos". Következmény: a `chordMinConfidence` küszöb ma a Live
úton nem szűr. Ez doc-commentben ÉS teszttel rögzített tény, nem hallgatólagos
viselkedés.

Follow-up (E02-R09/R11): a chord-confidence felvitele a `LiveFrame`-be a DSP
oldaláról — külön kör, mert a `LiveFrame` az Analyze úton is közös.

### 7. Hibaleképezés: engedély elöl, mikrofon-hiba a streamen

- **Engedély:** a `start()` elsőként az injektált `MicrophonePermissionGateway`-t
  kérdezi (`currentState()` → ha nem granted, `request()`); megtagadás esetén
  tipizált `Failure(PermissionFailure)` — ez az, amit az R07 reducer
  `PermissionDenied` signalja vár.
- **Foglalt mikrofon / capture-hiba:** a `RealStrumEngine.start()` `Future<void>`-ot
  ad, a hibát a `frames` streamre teszi. A gateway ezért az upstream stream-hibát
  leképezi és **az `observations` streamre továbbítja hibaeseményként**, majd
  belsőleg leáll (elengedi a mikrofont), de újraindítható marad. `AppFailure`
  típusú upstream hiba változatlanul megy át (pl. `audio.session_busy`); minden
  más `AudioFailure(code: FailureCode.practiceObservationStreamFailed)`-be
  csomagolódik.
- **Ismert korlát + follow-up:** így a „foglalt mikrofon" nem tud a `start()`
  szinkron `Failure`-je lenni. A tiszta megoldás a `StrumEngine.start()`
  `AppResult`-osítása, ami a Live/Analyze utat is érinti → külön kör.

### 8. Logolás: soha nem a nyers stream

A §23 „Logban nem jelenhet meg teljes nyers observation stream" szabály miatt a
gateway **observationönként nem logol**. Logol: capture start/stop, engedély-megtagadás,
leképezett stream-hiba, és a tartományon kívüli lag — utóbbi legfeljebb
**másodpercenként egyszer** (rate limit), a `timelineNow()`-ra mérve.

### 9. Cross-feature import a `live/public.dart`-on át

A `data/live_practice_observation_gateway.dart` a Live feature-t **kizárólag**
a `lib/features/live/public.dart` barrelen keresztül éri el. Ehhez a barrel
egyetlen új exportot kap: `model/live_frame.dart` (a `StrumEngine` már ki volt
exportálva). Az architektúra-allowlist **nem bővül** — ugyanaz a minta, mint az
E02-R05 `songs/public.dart`-ja.

### 10. Nincs hívó, nincs provider

A kör **nem** vezet be Riverpod providert és nem köt be UI-t. A gateway-t az
E02-R09 controller-kör építi és vezérli. A három practice-flag OFF marad, a
legacy Learn út (`learn_screen.dart`, `lesson_scorer.dart`, `liveFrameProvider`)
**egy sorral sem változik** → a production viselkedés bitre azonos.

Ebből következik, hogy a legacy pause-rés **ebben a körben nem záródik le a
legacy képernyőn** — ott a szünet alatti mikrofon-tartás felhasználó-látható
viselkedés (resume-kor nincs bemelegedési késés), amit valódi eszközön kell
verifikálni. A legacy út a V2 migrációval (E02-R11) áll át; addig a chunk 014
a **mai igazságot** írja le.

## Következmények

**Jó:**

- a „hallgat-e a mikrofon" kérdésre egyetlen, `const` táblával auditálható válasz van;
- a pause-rés a V2 úton szerkezetileg nem tud létrejönni;
- a domain nem lát nyers `LiveFrame`-et (§ elfogadási feltétel);
- az Epic 1 mikrofon-lease és engedély-szabályai változatlanul érvényesek;
- nincs DSP-módosítás.

**Ár:**

- két helyen él időlogika (gateway: de-jitter, matcher: kalibrált latencia) —
  szándékos, a legacy felosztás megőrzése miatt, doc-commentben rögzítve;
- a `chordMinConfidence` ma inert a Live úton;
- a „foglalt mikrofon" aszinkron hiba marad.

## Alternatívák, amiket elvetettünk

1. **A gateway kérdezi le a session state-et (pl. injektált `PracticeSessionState
   Function()`).** Elvetve: a `data/` réteg így a state machine-tól függene, és a
   start/stop kétszeres igazságforrást kapna. A pure policy + explicit start/stop
   ugyanazt adja, kevesebb csatolással.
2. **Háromállapotú capture (`off` / `warmUp` / `observing`), ahol a count-in alatt
   nyitva a mikrofon, de nincs emisszió.** Elvetve: a §13.1 interfészt bővítené,
   és a count-in alatti observationök úgyis a count-in tartományba esnek, ahol a
   matchernek nincs nyitott targetje — a szűrés a matcher dolga, nem a gatewayé.
3. **A kalibrált input latency levonása a gatewayben.** Elvetve: duplán számítana
   a matcher R09-es szerződésével, és eltérne a befagyasztott legacy felosztástól.
4. **Új `AudioOwner.practice` enum-érték.** Elvetve: a V2 ugyanazt a
   `StrumEngine`-t vezérli, amit a Learn ma — új owner nélkül a lease-szabályok
   változatlanok, és a core enum nem mozdul.
