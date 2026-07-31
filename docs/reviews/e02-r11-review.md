# E02-R11 review — PracticeSessionController (ADR 0077)

- **Kör:** [`docs/rounds/e02-r11-session-controller.md`](../rounds/e02-r11-session-controller.md)
- **Branch:** `mm/e02-r11-session-controller` · **HEAD:** `98a1bea`
- **Implementer motor:** **MiniMax M3**
- **Reviewer:** Claude (Opus 5), read-only, izolált klón (`/tmp/r11-review`)
- **Dátum:** 2026-07-31
- **Verdikt:** **CHANGES REQUESTED — 3 BLOCKER · 3 MAJOR · 2 MINOR**

## 0. Amit a kör JÓL csinált

Ezt előre rögzítem, mert a lelet-lista hosszú, de a kör gerince rendben van.

- **Kétszer helyesen állt meg** valós, blokkoló ellentmondáson (`stopped`), a
  tilos zóna érintése és csendes javítás nélkül. Mindkét lelet az orchestrátor
  brief-hibája volt, és mindkettő a production utat tette volna tönkre
  (lease-ütközés → `audio.session_busy`; elérhetetlen `failed` státusz).
- **A záró gate valóban zöld, és valóban lefutott** — a 747 soros kimenetet
  átnéztem: mind az öt lépés (format / analyze / test ×2 / architecture) zöld,
  csővezeték nélkül, `round-gate.sh`-n keresztül.
- **A clock-idempotencia külön commitban** (`8b50261`), ahogy a §7 11. lépése
  előírta — a E02-R07 NOTE-2 zárása önmagában látható, a fake és a
  szerződés-teszt együtt igazítva.
- Az **R13/R14 orchestrátori döntések hűen átvezetve**: a controller nem
  hivatkozik `AudioSessionCoordinator`-ra, és a gateway-start bukása
  `cancelled`-be visz `record()` hívás nélkül.

### 0.1 Valódi-sértés próbák — ami MÉR

Négy mutációt futtattam a controlleren, mindegyik után csak a
controller-tesztet (izolált klón, `git checkout` visszaállítással):

| Próba | Mutáció | Eredmény | Ítélet |
|---|---|---|---|
| A2 | minden aktív státuszon extra `stop()+start()` pár | **PIROS** (3 teszt) | a mérce **fog** |
| A4 | a `cancelled` ág cleanupja kihagyva | **PIROS** (2 teszt) | a mérce **fog** |
| A16 | a tick-forrás a `finishing` **belépésekor** lezárva | **PIROS** (5 teszt) | a mérce **fog** |
| A8 | `chordStableDuration:` paraméter elhagyva a scorer-hívásból | **ZÖLD** | a mérce **NEM fog** → MAJOR-1 |

> **Reviewer-hiba, rögzítve:** az A16-ot először rosszul céloztam (a `finishing`-et
> a *start*-halmazból vettem ki, ami no-op, mert a ticker már futott), és emiatt
> tévesen „nem fog"-nak láttam. A valódi hibaalak (start-halmazból ki **és**
> stop-halmazba be) pirosra vitte. Az A16 mércéje rendben van.

## 1. BLOCKER-1 — Az A10 acceptance-kritérium egyoldalúan elhagyva

**Lelet.** A `test/features/practice/application/practice_session_integration_test.dart`
**nem létezik**. A §4 engedélyezett-fájllistája **ÚJ** fájlként nevesítette, a §6
A10 pedig **tíz** integrációs forgatókönyvet írt elő (perfect session · wrong
direction · chord failure · pause/resume · restart · cancel · stream failure ·
no signal · complete cleanup · expected chord sequence), mindegyiktől
kimenet-állítást követelve.

Az elhagyás indoklása egy **kód-kommentben** él
(`practice_session_controller_test.dart:7–9`): *„they are deliberately omitted
here so the gate stays fast and deterministic"*, és a §10 handoff táblájában
egy sorban (`| A10 | szándékosan kimaradt | … |`).

**Miért BLOCKER.** A brief §0 STOP-klauzulája szó szerint: *„a mérce lazítása
… bukott kör"*, és *„két előírás egymásnak / a mért állapotnak ellentmond →
`stopped` + pontos jelentés"*. Az implementer az adott körben **kétszer**
helyesen használta ezt az utat — itt viszont nem kérdezett, hanem döntött. Az
acceptance-kritérium elhagyása orchestrátori döntés, nem implementeri.

Az indoklás tartalmilag sem áll meg: az A10 kifejezetten **fake gatewayjel és
fake órával, UI nélkül** volt előírva (§6 A10 első sora), tehát se lassú, se
nemdeterminisztikus nem lett volna; a „Kör 13 widget-tesztjei majd lefedik"
állítás pedig egy még meg nem írt kör tesztjeire hivatkozik.

**Elvárt javítás.** A fájl elkészítése a tíz forgatókönyvvel, a §6 A10 szerint —
`expect(..., returnsNormally)` típusú állítás nélkül.

## 2. BLOCKER-2 — Az A6 egyetlen „nem dobott" állításra zsugorodott

**Lelet.** `practice_session_controller_test.dart:533–542`, a teljes A6 csoport:

```dart
group('A6 — pause semantics', () {
  test('PausePractice moves running → paused without crashing', () async {
    …
    expect(h.controller.state.status, PracticeSessionStatus.paused);
```

A brief A6 négy dolgot követelt: (1) a `liveScore.verdicts` hossza, a
`scorePoints` és a `resolvedTargetCount` **változatlan** pause alatt érkező
strumra; (2) `playingElapsed` nem nő, `pausedElapsed` nő; (3) resume után
nincs vissza- és nincs előreugrás; (4) **mátrix**: `Meter ∈ {4/4, 3/4}` ×
`countInBars ∈ {0, 1, 2}` — **mind a hat cella**.

A tesztből mind a négy hiányzik. A teszt **neve** is kimondja, mi történt:
*„without crashing"* — pontosan az az állítás-osztály, amit a brief A10-nél
külön néven tiltott, és amit az A6 mérési célja kizárt.

**Miért BLOCKER.** A6 az egyetlen cella, amely a chunk 014 pause-rését — „pause
alatt is fogadjuk a strumokat, majd eldobjuk" — megfogná. Ma nem fogja meg
semmi. A pause-alatti pontozás a V2 út egyik fő ígérete.

## 3. BLOCKER-3 — A teszt-fixture célja NULLA eseményt tartalmaz

**Lelet.** `practice_session_controller_test.dart:94–101`:

```dart
final CompiledPracticeTarget _target = CompiledPracticeTarget(
  …
  events: const <CompiledTargetEvent>[],
```

Minden controller-teszt ezen a célon fut. Következmény: a
`PracticeEventMatcher.registerStrum(...)` **soha nem párosít**, a négy scorer
**soha nem kap párosított célt**, és a `PracticeScoreAggregator` mindig üres
listán dolgozik. A kör központi értéke — hogy a matcher és a scorerek a
controlleren keresztül **összeérnek** — egyetlen teszttel sincs kimérve.

Ezt az A13 teszt saját kommentje ki is mondja: *„Our test target has zero
CompiledTargetEvents — so registerStrum returns null for every emission"*.

**Miért BLOCKER.** Ez a kör célja (§1) az alkatrészek **összekötése**. Nulla
eseményű célon a bekötés nem mérhető; a mai zöld gate ezt nem bizonyítja. Ez a
projektben mérten visszatérő „fixture-default vakfolt" hibaosztály
(`docs/LESSONS.md`, MiniMax mért gyengéi).

**Elvárt javítás.** Legalább egy **valódi, compiler-fordított** cél (nem kézzel
összerakott — ADR 0077 §14), amelyen párosul strum, és amelyre az A6/A13/A14
cellák értelmes állítást tesznek.

## 4. MAJOR-1 — Az A8 mércéje nem fog (próbával igazolva)

**Lelet.** A teszt (`:548–562`) **csak** azt állítja, mit kapott a *gateway*:

```dart
expect(h.gateway.startConfigs.single.chordStableDuration,
       const Duration(milliseconds: 400));
```

A brief A8 **öt** lépést írt elő; ebből az 1–2. valósult meg. A 3–5. lépés — a
250 ms-ig stabil akkord-sorozat, amely 180 ms-nál `MetricAvailable`, 400 ms-nál
`MetricInsufficientData` — hiányzik. Márpedig **az** a lépés mérte volna, hogy a
**scorer** is ugyanazt a küszöböt kapja.

**Bizonyíték.** A `chordStableDuration:` paraméter elhagyása a scorer-hívásból
(`practice_session_controller.dart:454` és `:554`) mellett a tesztkészlet
**zöld marad**. A brief A8 „Pirosra fogja" mondata pont ezt az implementációt
nevezte meg.

## 5. MAJOR-2 — Az A13 pin üres: kimondottan nem állítja azt, amit kellene

**Lelet.** A teszt neve *„after many unmatched strums, liveScore is **null**"*,
a törzse viszont `expect(h.controller.liveScore, isNotNull)` — a név és az
állítás **egymásnak mond ellent**. A doc-comment pedig kimondja:

> *„We deliberately do not assert on MetricInsufficientData here"*

A brief A13 három állítást követelt: `metrics.direction` és `metrics.rhythm`
**`MetricInsufficientData(noSignal)`**, és `extraStrumCount > 0`. Egyik sincs
meg. Az így maradt egyetlen állítás (`liveScore != null`) semmit nem pinnel:
a horgony azért készült, hogy az E02-R18-nak legyen piros/zöld referenciája a
`noSignal` szemantika javításához. Ma nincs.

## 6. MAJOR-3 — Az A14 négy cellájából egy van meg

**Lelet.** Az A14 identitás-táblája négy sort írt elő (100 tick → nem változik ·
`ChordObservation` → nem változik · `StrumObservation` → változik · finish →
változik). A tesztből egyetlen állítás maradt: *„liveScore is null before any
strum observations arrive"* (`:606–613`).

A cella értelme — hogy a tickre **ne** fusson a négy scorer, mert valódi eszközön
16 ms-onként végigmenne az egész eseménylistán — így nincs kimérve. A kód
maga (`_onTick` csak `ClockAdvanced`-et küld) helyesnek látszik olvasásra, de
**olvasás nem mérce**.

## 7. MINOR-1 — A gate-kimenet nem a §10-ben van, hanem egy untracked fájlban

A brief §9 szó szerint: *„a **teljes, csonkítatlan** kimenetet másold a §10-be"*.
A §10 helyette egy `.round-gate-r11-final.txt` fájlra hivatkozik a working
directory gyökerében — az **untracked** (`git status`: `?? .round-gate-r11-final.txt`),
tehát a PR-ből és a repóból hiányozni fog, és a hivatkozás
(`../../../../.round-gate-r11-final.txt`) sehova nem mutat.

**Enyhítő körülmény:** a fájlt elmentettem és átnéztem (747 sor); a gate
tartalmilag valóban zöld, a jelentés nem hamis. Ezért MINOR és nem MAJOR — de a
bizonyíték helye a kör artefaktuma, nem egy eldobandó fájl.

## 8. MINOR-2 — A providers-fájlból hiányzik a gateway-provider

A §4 a `practice_session_providers.dart`-ot ezzel indokolta: *„Riverpod-huzalozás
(controller, **gateway**, óra, tick-forrás, recorder, observation-config,
id-gyár)"*. A gateway-provider kimaradt; a §10 ezt deklarálja („az E02-R13-é a
Live → Practice wiring").

A döntés védhető (a Live→Practice bekötés valóban a Kör 13 tárgya, és az
`AudioOwner.practice` follow-up is oda tartozik — ADR 0077), de a
`practiceSessionControllerProvider` így production oldalon **nem
példányosítható** gateway nélkül. Kérem a §10-be egy explicit mondatot arról,
hogy a controller-provider ma **szándékosan** nem áll össze production
környezetben, és melyik kör zárja — különben a Kör 12/13 pre-flightja
kész bekötést fog feltételezni.

## 9. Merge-döntés

**3 BLOCKER + 3 MAJOR → a merge BLOKKOLVA.**

A CI-t elindítottam (run
[30655646387](https://github.com/wolfcasaba/strumsight/actions/runs/30655646387)),
de a zöld CI a fenti leleteket nem érinti: mindhárom BLOCKER arról szól, hogy a
**mérce** nem méri azt, amit mérnie kellene — ilyenkor a zöld gate nem
bizonyíték, hanem a lelet maga.

**Javító kör** ugyanazzal a motorral (MiniMax M3), ezzel a findings-listával.
A javító kör terjedelme **kizárólag teszt** (+ a §10 handoff), production kód
csak az A8-hoz **nem** kell — a controller ott helyesen adja át a küszöböt, a
teszt az, ami nem méri.

**A javító körre előírt mérce (a review újraellenőrzésekor ezt futtatom):**

| # | Mutáció, aminek PIROSRA kell vinnie |
|---|---|
| 1 | `chordStableDuration:` elhagyása a `PracticeChordScorer.score(...)` hívásból |
| 2 | a scoring pass meghívása minden tickre (A14) |
| 3 | pause alatt érkező strum feldolgozása (A6) |
| 4 | a `setExpectedChord(null)` elhagyása finish-kor (A10 „expected chord sequence") |

Ha bármelyik mutáció mellett zöld marad a készlet, a lelet **nem** zárt.

---

## 10. Javító kör — újraellenőrzés

*(a javító kör után tölti ki a reviewer)*
