# E14-R12 — Provisional → confirmed stabilizátor állapotgép

- **Státusz:** PRE-FLIGHT KÉSZ — **mért alap: `main @ 16b101f7`**
  (újramérve 2026-09-05; az előre megírt változat 2026-08-20-i alapja
  elavult, a feloldás a §0.0)
- **Típus:** Chapter 14, Kör 12 (truthfulness hotfix blokk)
- **Kör-azonosító:** `E14-R12`
- **Branch:** `sonnet-impl/e14-r12-recognition-stabilizer`
- **Előfeltétel:** `E14-R04` merge-elve (döntési állapotok). Az `E14-R08`
  ajánlott a flip-rate méréshez, de nem blokkoló: a kör fixture-ön is mér.
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** `0518` — **a Claude írta meg a pre-flightban**, a `docs/adr/` a TILOS
  zónában van. (Az előre kiosztott `0364` elavult; a foglaló
  `tools/round-slots.py reserve-adr` `0518`-at adott.)

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/live/engine/recognition_stabilizer.dart",
  "lib/features/live/providers/chord_timeline_provider.dart",
  "lib/features/live/providers/live_providers.dart",
  "lib/features/live/public.dart",
  "test/features/live/recognition_stabilizer_test.dart",
  "test/features/live/chord_timeline_churn_test.dart",
  "docs/rounds/e14-r12-recognition-stabilizer.md",
]
gate_tests = [
  "test/features/live/recognition_stabilizer_test.dart",
  "test/features/live/chord_timeline_churn_test.dart",
  "test/property/chord_timeline_property_test.dart",
]
native_gate = false
```

> A `test/property/chord_timeline_property_test.dart` a `gate_tests`-ben van,
> de **NINCS** az `allowed_paths`-on: futtatnod kell, módosítanod tilos. Ez a
> D5 gépi mércéje (§0.0 4. pont).

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Pre-flight revízió (2026-09-05, orchestrátor) — a brief-lint S12 + S15 feloldása

A brief 2026-08-20-án, egy azóta elavult alapra készült. A `brief-lint` **S15**
lelete (a mért alap elmozdult) és **S12** lelete (a §7 parancs nem tükrözte a
`gate_tests`-et) a pre-flight teendője volt. Az újramérés (`main @ 16b101f7`)
öt tényt talált; a kör tartalma emiatt PONTOSODIK — a scope nem tágul.

**Visszakeresés (ADR 0312):** `knowledge-rag --corpus lessons,halts,adr` és
`--corpus lessons,halts` — releváns előzmény: [L636](../LESSONS.md#l636)
(előre megírt brief mért alapja elmozdul → ÚJ kapu egy MÁR merge-elt döntésre
= H3), [L357](../LESSONS.md#l357) (az előre megírt brief `allowed_paths`-a nem
követi az azóta elfogadott ADR-t), [L165](../LESSONS.md#l165) (küszöb-alapú
szűrő felépülési út nélkül **örökre befagy** egy valós, tartós változáson),
[L593](../LESSONS.md#l593) (a `gate_tests`-ből kimaradó kipinnelt teszt zölden
hagyja a célzott kaput, miközben a kör pirosra viszi).

**1) A „provisional → confirmed" szótár MÁR MERGE-ELVE VAN.** A §5 nem hozhat
új enumot: `RecognitionDecision` (`candidate`/`provisional`/`confirmed`/
`uncertain`/`rejected`/`expired`) él a fában
(`lib/features/live/domain/recognition/recognition_decision.dart:5-23`).

**2) A KERET-szintű akkord-megerősítésnek MÁR van egyetlen döntési helye.** Az
E14-R11 (ADR 0516, squash `ac7df497`) óta a `live_pipeline.dart`
`debugDeriveChordDecision`-je dönt (Schmitt-kapu `chordConfRise = 0.54`
inkluzív + tonalness + `SignalQualityState`, `live_pipeline.dart:313-348`), és
a `_buildFrame()` ugyanezt a bitet adja a `LiveFrame.current`-nek (`:388-407`).
A `live_pipeline.dart` **tilos zóna**. Ezért a kör állapotgépe **nem** második
megerősítési kapu ugyanarra a kérdésre: a kör egyetlen döntési helye a
**CÍMKE-stabilitás** a MÁR eldöntött kereteken (ADR 0518 D2). Ez a §2/§5.2
átfogalmazásának oka.

**3) A `LiveFrame` már hordozza a döntést.** `chordDecision` /
`chordRejectReason` additív mezők (`model/live_frame.dart:72-80`) — a
stabilizátor ezeket OLVASHATJA, de nem írhatja felül és nem vezetheti le újra
(a `model/` amúgy is tilos zóna).

**4) A tiszta reducer szemantikáját a körön KÍVÜL élő teszt pinneli.** A
`test/property/chord_timeline_property_test.dart` (randomizált property + 8 fix
cella: „A→A with a strum updates the last card in place", „A→B→A gives 3
distinct cards", cap-trim, azonos-referencia) NINCS az `allowed_paths`-on. Ezért
a bekötés helye a **`ChordTimelineController.build()`**, a `liveFrameProvider`
és a VÁLTOZATLAN `reduceChordTimeline` közé (ADR 0518 D5) — a reducer
átírása H3 volna. A property-teszt a kör `gate_tests`-ébe került (L593).

**5) S12 — a §7 parancs most tükrözi a `gate_tests` listát** (mindhárom
útvonal, külön argumentumként).

**Ami változatlanul igaz a 2026-08-20-i briefből:** nincs
`recognition_stabilizer.dart` a fában; a `ChordTimelineController` ma
közvetlenül a `liveFrameProvider`-ből hajtogat, stabilizáló réteg nélkül; a
Free/Guided profil sehol nem létezik.

## 1. Cél

A felület **előzménye** (timeline) csak stabil, megerősített akkord-váltást
mutasson: egy MÁR eldöntött keret címkéje csak N egymást követő egyező kereten
válik `confirmed`-dé, a megerősített címkéből pedig csak ugyanilyen erős
ellenevidencia mozdít ki. A pengetés-esemény immutábilis. A kör méri a
megerősítési késleltetést és a flip-rate-et.

### 1.1 Visszakeresett előzmény (ADR 0312)

- **Chapter 14 §4.1–4.2 (mért audit):** a jelenlegi UI minden labelváltást
  kártyává emel — a felismerési zajból „timeline churn" lesz.
- **E14-R10 (ADR 0512):** ugyanaz az elv a strum-oldalon (egy eseményre egy
  végleges irány); ez a kör az akkord-oldali párja.
- **E14-R11 (ADR 0516):** a keret-szintű akkord-döntés bekötése — ez a kör NEM
  ismétli meg, hanem föléépül (L636, L624).
- **L165:** küszöb-alapú szűrő felépülési út nélkül befagy → ADR 0518 D6 +
  §6.6 cella.

## 2. Jelenlegi állapot — mért tények (`main @ 16b101f7`, 2026-09-05)

- `lib/features/live/providers/chord_timeline_provider.dart` — a
  `ChordTimelineController` a `liveFrameProvider`-ből hajtogatja a történetet
  a tiszta `reduceChordTimeline`-nal („newest last, capped ring buffer");
  **nincs stabilizáló réteg**. A reducer 3. szabálya minden címkeváltásra új
  kártyát ad (`:50-65`) — ez a churn forrása.
- `lib/features/live/engine/` — nincs `recognition_stabilizer.dart`; ez a kör
  hozza létre.
- `lib/features/live/engine/dsp/live_pipeline.dart` (**tilos zóna**) — a
  keret-szintű `RecognitionDecision` EGYETLEN levezetési helye (ADR 0516).
- `lib/features/live/model/live_frame.dart` (**tilos zóna**) — `current`,
  `latestStrum`, `strumSeq`, `latestStrumTime`, `engineTimeSec`,
  `chordDecision`, `chordRejectReason`; a `copyWith` **nem tud** nullable
  mezőt törölni (`:85-110`) — ezért a stabilizátor keretet ENGED ÁT vagy
  ELDOB, nem ír át.
- `test/property/chord_timeline_property_test.dart` (**tilos zóna**) — a mai
  reducer-szemantika kipinnelt mércéje; futtatandó, nem módosítandó.
- A Free és Guided mód külön profilja ma sehol nem létezik.

## 3. Scope

**Benne:** `RecognitionStabilizer` (Free/Guided profil paraméterként),
címke-stabilitás `provisional → confirmed` a MÁR eldöntött kereteken,
immutábilis pengetés-esemény (`strumSeq`-identitás), `confirmationLatency` /
`flipRate` mérőszám a kimeneten, a timeline bekötése a controllerben, additív
export.

**Nincs benne:** UI-layout (R13), DSP/ML konstans, a `live_pipeline.dart`
bármely küszöbe, a `reduceChordTimeline` szemantikája, új modell, hálózat, a
profil futásidejű kapcsolása.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `lib/features/live/engine/recognition_stabilizer.dart` | az állapotgép + a profilok |
| `lib/features/live/providers/chord_timeline_provider.dart` | a bekötés a controllerben (a reducer VÁLTOZATLAN) |
| `lib/features/live/providers/live_providers.dart` | `autoDispose` stabilizátor-provider |
| `lib/features/live/public.dart` | additív export |
| `test/features/live/recognition_stabilizer_test.dart` | állapotgép-mátrix |
| `test/features/live/chord_timeline_churn_test.dart` | churn-mérés + provider-bekötés |
| `docs/rounds/e14-r12-recognition-stabilizer.md` | §10 handoff |

**Tilos zóna:** minden más — kiemelten `lib/features/live/engine/dsp/**`
(benne a `live_pipeline.dart`), `lib/features/live/engine/ml/**`,
`lib/features/live/model/**`, `lib/features/live/domain/**`,
`lib/features/live/screens/**`, `lib/features/live/widgets/**`,
`test/property/**`, `assets/**`, `ml/**`, `docs/adr/**`,
`docs/rag/chunks/**`, `.github/workflows/**`, `tools/round-gate.sh`.

## 5. Kötött architekturális döntések (ADR 0518)

### 5.1 Az esemény immutábilis

Egy elfogadott pengetés-esemény (`LiveFrame.strumSeq` az identitása) iránya
soha nem változik: ugyanaz a `strumSeq` másik iránnyal nem juthat a
timeline-ig. **NEM elfogadható**: „utólagos korrekció jobb élményt ad".
(ADR 0518 D7.)

### 5.2 A megerősítés evidencia-alapú, nem időzítő

A `confirmed` átmenet feltétele `agreeFrames >= profile.minAgreeFrames`
(**inkluzív**) — nem `Future.delayed`, `Timer` vagy `DateTime.now()`.
(ADR 0518 D3.)

### 5.3 A profil paraméter, nem elágazás

`StabilizerProfile` érték-objektum (`free`, `guided`) paraméterezi UGYANAZT az
állapotgépet. `free.minAgreeFrames = 3`, `guided.minAgreeFrames = 5` —
tervezői választás, nem kalibráció (ADR 0518 D4). Másolt kódág tilos.

### 5.4 Tartott akkord nem generál új kártyát

Változatlan `confirmed` címke ismételt megjelenése nem hoz létre új
timeline-elemet, és **egy-frame-es idegen címke sem** (ez a churn maga).

### 5.5 A mérőszám a kimenet része

A stabilizátor getterként adja ki a `confirmationLatencyFrames`-t (az utolsó
megerősített címke ELSŐ észlelésétől a megerősítésig eltelt keretek száma — a
zaj is beleszámít) és a `flipRate`-et (megerősített címkeváltás ÷ feldolgozott
keret, `0..1`), hogy az R09 release gate mérhesse — nem logsor. (ADR 0518 D8.)

### 5.6 Nincs második szótár és nincs második megerősítési kapu

Az állapot a merge-elt `RecognitionDecision` (`candidate` → `provisional` →
`confirmed`). A stabilizátor **nem** vezet le jelenlétet, konfidenciát,
tonalness-t vagy jel-minőséget: bemenete a MÁR eldöntött keret
(`LiveFrame.current != null`). (ADR 0518 D1/D2.)

### 5.7 A reducer szerződése változatlan; a bekötés a controllerben van

`reduceChordTimeline` szövege és szemantikája bit-azonos marad. A
`ChordTimelineController.build()` a keretet előbb a stabilizátorba adja:
`LiveFrame? stabilize(LiveFrame frame)` — visszaadott keret → reducer,
`null` → a puffer érintetlen. (ADR 0518 D5.)

### 5.8 A provider `autoDispose`, a UI változatlan

A stabilizátor-provider `autoDispose` (r185 C1 mikrofon-csapda). A hero-út
(`live_screen.dart` → `SsChordHero`) és minden widget érintetlen: a kör az
ELŐZMÉNYT stabilizálja. (ADR 0518 D9/D10.)

## 6. Acceptance criteria

Mindegyik cella a `free` profillal (`minAgreeFrames = 3`) mér, hacsak a pont
mást nem mond. A bemenet kézzel épített `LiveFrame`-sorozat (nincs audio).

1. **Megerősítési küszöb hármas cellája** (`N = 3`, a határ **inkluzív**): a
   küszöb **alatt** (2 egybehangzó eldöntött keret) → `provisional`, pontosan
   **rajta** (3) → `confirmed`, a küszöb **fölött** (4) → `confirmed`.
2. `confirmed` állapotból **gyenge** ellenevidencia (1 keret idegen címkével)
   nem vált ki átmenetet — a megerősített címke marad; **erős** (3 egymást
   követő keret ugyanazzal az idegen címkével) igen. A teszt **mindkét**
   irányt méri.
3. **Churn:**
   - **3a** 10 kereten át tartott azonos akkord **pontosan egy**
     timeline-kártyát ad;
   - **3b** két tartott A-szakasz közé ékelt **egy** keretnyi B címke
     **NEM** hoz létre kártyát (a puffer végig 1 kártya, `A`).
4. Egy MÁR elfogadott pengetés-eseményre (ugyanaz a `strumSeq`) érkező
   ellentétes irány-javaslat nem írja felül az elfogadott irányt; ÚJ
   `strumSeq` viszont új eseményt ad.
5. A `free` és a `guided` profil UGYANAZON a bemeneten mérhetően eltérő
   `(confirmationLatencyFrames, flipRate)` párt ad, és **mindkét** érték a
   kimenet része (getter, nem log).
6. **Felépülési út (L165):** tetszőlegesen hosszú, váltakozó címkéjű zajos
   előzmény UTÁN is, 3 egymást követő B keret megerősíti B-t — az állapotgép
   nem fagy be.
7. **A reducer szerződése változatlan:** a
   `test/property/chord_timeline_property_test.dart` (a kör kapujában fut,
   módosítani tilos) **zöld** marad.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A küszöb exkluzív (`> N`) | 1. pont **3 → confirmed** cellája |
| Időzítő-alapú megerősítés (`Future.delayed`/`DateTime.now()`) | 2. pont (a keret-számláló nélkül a gyenge/erős megkülönböztetés eltűnik) + 1. pont |
| A stabilizátor minden eldöntött keretet átenged (`N = 1`) | 3b (a B-blip kártyát ad) |
| A timeline minden frame-re kártyát ad (bekötés kimarad) | 3a **és** 3b |
| Az elfogadott esemény felülírható | 4. pont |
| A profil nem paraméter, hanem másolt kódág / azonos küszöb | 5. pont (a két profil azonos párt ad) |
| A számláló nem nullázódik eltérésre (befagy) | 6. pont |
| A `reduceChordTimeline` szemantikáját írja át | 7. pont (a property-teszt) |
| Új állapot-enum a merge-elt `RecognitionDecision` helyett | a fordítás/`analyze` + az 1–2. pont típusa (a getter `RecognitionDecision`-t ad) |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/live/recognition_stabilizer_test.dart test/features/live/chord_timeline_churn_test.dart test/property/chord_timeline_property_test.dart test/features/live
```

Külön processzben futó `format` → `analyze` → célzott tesztek → `architecture`
(AGENTS.md §12). `&&` láncolás tilos (L05/L09). CI-dispatch/PR/merge
Claude-oldal.

### 7.1 Falszifikációs cella

A §10-ben dokumentáld: a `free` profil `minAgreeFrames` értékét ideiglenesen
**1**-re állítva a 6.3b cella **PIROS** (a B-blip kártyát ad), visszaállítva
**ZÖLD**. A kimenetet (a piros cella nevével és az assert szövegével együtt)
másold be.

## 8. Implementációs sorrend

1. `RecognitionStabilizer` + `StabilizerProfile` + mátrix-teszt (1., 2., 6.
   pont) — profilok paraméterként.
2. Mérőszámok kivezetése (5. pont).
3. Immutábilis esemény (4. pont).
4. Timeline bekötése a controllerben + churn-teszt (3a/3b) + a property-teszt
   futtatása (7. pont).

## 9. Kockázatok

- **Késleltetés-növekedés:** az előzmény-kártya `minAgreeFrames − 1` kerettel
  (≈133 ms Free, ≈267 ms Guided, ~15 fps) később jelenik meg. A §10-ben
  számszerűen jelenteni kell (a release gate küszöbe a R09-é).
- **Kettős igazság:** a timeline nem olvashat a stabilizátor MELLETT nyers
  keretet — egyetlen forrás. A hero (`LiveFrame.current`) tudatosan a
  pipeline döntését mutatja (ADR 0518 D10), ez nem „második igazság", hanem
  „most" vs. „előzmény".
- **Befagyás:** L165 — a 6. pont cellája őrzi.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
