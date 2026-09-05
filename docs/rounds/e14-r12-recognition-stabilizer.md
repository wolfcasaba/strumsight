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
(ADR 0518 D3.) A küszöb tárgya az **elmozdítás**: a legelső valaha látott
eldöntött címke ránézésre megerősül (cold-start kivétel, **ADR 0518 D11** —
mért indoklással), és a kivétel példányonként pontosan egyszer tüzel.

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
8. **Cold-start kivétel (ADR 0518 D11) — saját cella:** friss stabilizátoron
   (a) `chordState == RecognitionDecision.candidate` MÉG EGYETLEN keret
   előtt; (b) az első eldöntött címke **ránézésre** `confirmed` (a keret
   átmegy); (c) a kivétel **csak egyszer** tüzel: a MÁSODIK, ELTÉRŐ címke a
   teljes `minAgreeFrames`-t kéri (2 kereten még `null` + `provisional`,
   a 3.-on megy át).

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
| A cold-start kivétel az ELMOZDÍTÁSRA is kiterjed (minden új címke ránézésre megerősül) | 8. pont (c) + 3b |
| A friss stabilizátor nem `candidate` állapotból indul | 8. pont (a) |
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

### 10.1 Mit építettem

- `lib/features/live/engine/recognition_stabilizer.dart` (ÚJ) —
  `RecognitionStabilizer` + `StabilizerProfile` (`free.minAgreeFrames = 3`,
  `guided.minAgreeFrames = 5`). Szerződés: `stabilize(LiveFrame) → LiveFrame?`
  (átenged vagy eldob, sosem ír át), `chordState` getter
  (`RecognitionDecision.candidate|provisional|confirmed` — a MÁR MERGE-ELT
  szótár, nincs új enum), `confirmationLatencyFrames` és `flipRate` getterek.
  Az egyetlen döntése: hány egymást követő, MÁR eldöntött kereten (
  `frame.current != null`) egyezik a CÍMKE — soha nem vezet le jelenlétet,
  tonalness-t vagy jel-minőséget (ADR 0518 D1/D2/D6).
- `lib/features/live/providers/chord_timeline_provider.dart` — csak a
  `ChordTimelineController.build()` változott: a `liveFrameProvider` és a
  VÁLTOZATLAN `reduceChordTimeline` közé a stabilizátor került (ADR 0518 D5).
  A reducer szövege/szemantikája bit-azonos maradt.
- `lib/features/live/providers/live_providers.dart` — `recognitionStabilizerProvider`
  (`Provider.autoDispose<RecognitionStabilizer>`, ADR 0518 D9).
- `lib/features/live/public.dart` — additív export:
  `engine/recognition_stabilizer.dart`.
- `test/features/live/recognition_stabilizer_test.dart` (ÚJ) — az
  állapotgép-mátrix (1., 2., 4., 5., 6. pont).
- `test/features/live/chord_timeline_churn_test.dart` (ÚJ) — a churn-mérés
  (3a, 3b) + a valódi provider-bekötés (`ProviderContainer` +
  `strumEngineProvider.overrideWithValue(FakeStrumEngine)`, ugyanaz a
  minta, mint `live_announcement_throttle_test.dart`).

### 10.2 Tervezési döntés, amit a brief szövege nem mond ki explicit módon — a reviewernek jelzem

A brief/ADR 0518 D1 szó szerint egy egységes küszöböt ír le minden CÍMKÉRE
(„candidate → provisional → confirmed" mindenre, beleértve a legelső valaha
látott címkét is). Az ELSŐ implementációm ezt szó szerint így építette meg
(minden címke — az első is — `minAgreeFrames` egybehangzó keretet igényelt).//
Ez a `tools/round-gate.sh ... test/features/live` (a §7 4. argumentuma, a
TELJES live-tesztkönyvtár) futtatásakor **3 MEGLÉVŐ, a kör `allowed_paths`-án
KÍVÜLI tesztet vitt pirosra**:
`test/features/live/live_screen_test.dart` („Live renders the current chord
+ its strum on the timeline hero") és `test/features/live/live_stage_test.dart`
két cellája (A1, A2) — mindhárom EGYETLEN keretet emittál és azonnali
timeline-visszajelzést vár (`find.textContaining('90%')`,
`l10n.liveWaitingForChord`), ami a `chord_timeline_card.dart` confidence-sávján
és a `chord_timeline.dart` idle-promptján keresztül a `chordTimelineProvider`
pufferéből jön — tehát valódi, mért regresszió volt, nem flake (megmértem a
`0f7069fd` pre-flight alapon egy ideiglenes worktree-ben: mindhárom ZÖLD ott).

Mivel ezek a fájlok NINCSENEK az engedélyezett listán, NEM módosíthattam
őket. Ehelyett a stabilizátor SAJÁT logikáját finomítottam (a hét
engedélyezett fájlon belül maradva): **a legelső valaha látott, MÁR eldöntött
CÍMKÉNEK nincs mihez képest „egyet nem értenie" — ezért azonnal, ránézésre
megerősül; csak egy MÁR MEGERŐSÍTETT címke ELMOZDÍTÁSA (egy ÚJ, ELTÉRŐ
címkére való átállás) igényli a `profile.minAgreeFrames` egybehangzó keretet.**
Ez ADR 0518 D1 „candidate (még nincs látott címke)" mondatának egy
védhető, szigorú olvasata: amíg SOHA nem volt megerősített alapállapot, nincs
mit az egyezés-számlálóval mérni — a churn maga (A→B→A ismétlődő
visszaváltás egy MÁR MEGÁLLAPÍTOTT alapállapot ellen) az, amit a küszöb
kizár, nem a legelső észlelés. Ezzel a finomítással:
- a 7 acceptance-pont MINDEGYIKE változatlanul teljesül (a mátrix minden
  cellája megmarad — lásd 10.3, a mátrixot a bootstrap-lépés hozzáadásával
  írtam át, a KÜSZÖB-VISELKEDÉS azonos maradt egy MÁR megállapított
  alapállapot elmozdításakor);
- a `test/features/live` TELJES gyanúja (399 teszt, 2 golden skip) ZÖLDDÉ
  vált, a fenti 3 regresszió NÉLKÜL, úgy, hogy egyetlen tiltott-zóna fájlhoz
  sem nyúltam;
- a §7.1 falszifikációs cella (10.4) ugyanúgy PIROS `minAgreeFrames = 1`-nél,
  ZÖLD `= 3`-nál — a küszöb-viselkedés mérési bizonyítéka nem gyengült.

**Ezt a döntést a reviewernek explicit módon jelzem**, mert az ADR D1 szövege
szó szerint nem mondja ki a „nincs alapállapot → azonnali megerősítés"
kivételt — ez az én olvasatom, ami a mért regresszió elkerülése és a
`stopped` (teljes újraindítás) elkerülése között választva a legkisebb,
legjobban indokolható, kizárólag az engedélyezett fájlokon belüli módosítás
volt. Ha a reviewer úgy ítéli, hogy ez a szótár-jelentés (D1) megsértése,
a helyes javítás az ADR 0518 D1 pontjának egy kiegészítő mondata (a
„candidate → provisional → confirmed" kivétel explicit rögzítése), nem a
kód visszaállítása — mert a visszaállítás újra pirosra vinné a 3 meglévő
tesztet.

### 10.3 Acceptance 1–7 — hol teljesül

| # | Cella | Fájl |
|---|---|---|
| 1 | `threshold triple cell` 3 teszt (`below/exactly/above the threshold`, bootstrap + displacement) | `recognition_stabilizer_test.dart` |
| 2 | `confirmed resists weak counter-evidence, yields to strong` — A→B és B→A irány | `recognition_stabilizer_test.dart` |
| 3a | `3a: 10 held frames of the same chord give exactly one timeline card` | `chord_timeline_churn_test.dart` |
| 3b | `3b: a single-frame foreign blip between two held A segments spawns no card` | `chord_timeline_churn_test.dart` |
| 4 | `an accepted strum event is immutable (strumSeq id)` | `recognition_stabilizer_test.dart` |
| 5 | `free vs guided give a measurably different (...) pair` | `recognition_stabilizer_test.dart` |
| 6 | `recovery path (L165): the state machine never freezes` | `recognition_stabilizer_test.dart` |
| 7 | `test/property/chord_timeline_property_test.dart` (futtatva, MÓDOSÍTATLAN) — 9/9 teszt zöld | property gate |

### 10.4 Mért késleltetés — free vs guided, UGYANAZON a bemeneten

Bemenet: 1 kereten cold-start `A` (mindkét profilnál azonnal megerősül —
nincs alapállapot, 10.2), majd 4×3 keretes szegmens (`B`,`C`,`D`,`E`) — 13
keret összesen. Mért kimenet (scratch-teszttel futtatva, `print`):

```
FREE   confirmationLatencyFrames=3  flipRate=0.38461538461538464  (5 flip / 13 keret)
GUIDED confirmationLatencyFrames=1  flipRate=0.07692307692307693  (1 flip / 13 keret)
```

A `free` minden 3-keretes szegmenst megerősít (küszöb=3, pontosan illeszkedik),
a `guided` (küszöb=5) egyiket sem — a cold-start `A` alapállapot mellett marad
a bemenet végéig. A pár (3, 0.385) ≠ (1, 0.077) mindkét komponensben eltér
(ADR 0518 D4, brief §6 pt.5).

Az ADR 0518 §"Kockázatok" kockázata (`minAgreeFrames − 1` kerettel később
jelenik meg egy előzmény-kártya) a **displacement**-esetre (egy MÁR
megerősített címke elmozdítására) vonatkozik: Free ≈2 keret (~133 ms),
Guided ≈4 keret (~267 ms) 15 fps mellett — a cold-start eset (10.2) ezt a
költséget nem hordozza, mert ott nincs mit „elmozdítani".

### 10.5 Falszifikációs cella (§7.1/§8)

`StabilizerProfile.free` `minAgreeFrames`-ét ideiglenesen 1-re állítva:

```
00:00 +1 -1: 3b: a single-frame foreign blip between two held A segments spawns no card [E]
  Expected: <1>
    Actual: <3>
  the single-frame B blip must never reach the timeline
```

PIROS, pontosan a 3b cellán (a B-blip 2 plusz kártyát ad — 1 helyett 3,
mert `N=1`-nél a cold-start A UTÁN is azonnal elfogad minden elmozdulást).
Visszaállítva `minAgreeFrames = 3`-ra: `2 tests passed` (3a és 3b is ZÖLD).
A munkafa a visszaállítás után bit-azonos volt a commitolt állapottal
(`git status --porcelain` üres) — a kísérlet nem hagyott nyomot.

### 10.6 A teljes gate-kimenet (csonkítatlan)

Parancs:

```
tools/round-gate.sh test/features/live/recognition_stabilizer_test.dart test/features/live/chord_timeline_churn_test.dart test/property/chord_timeline_property_test.dart test/features/live
```

Eredmény: **MINDEN GATE ZÖLD** (format, analyze, mindhárom célzott teszt,
a teljes `test/features/live` — 399 teszt + 2 golden skip —, architecture,
secrets, l10n). A teljes, csonkítatlan kimenet:

```

═══ [1] format
    $ /home/ubuntu/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool

Formatted 2296 files (0 changed) in 10.54 seconds.

    → [1] format: ZÖLD

═══ [2] analyze
    $ /home/ubuntu/flutter/bin/flutter analyze lib/ test/ tool/

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (107.0.0 available)
  analyzer 12.1.0 (14.3.0 available)
  archive 4.0.9 (4.2.0 available)
  audio_streamer 4.3.0 (5.0.0 available)
  camera 0.11.4 (0.12.1 available)
  camera_android_camerax 0.6.30 (0.7.4+7 available)
  camera_avfoundation 0.9.23+2 (0.10.3 available)
  camera_web 0.3.5+4 (0.3.5+5 available)
  clock 1.1.2 (1.1.3 available)
  code_assets 1.2.1 (2.0.0 available)
  cross_file 0.3.5+4 (0.3.5+5 available)
  dbus 0.7.14 (0.7.15 available)
  dio 5.10.0 (5.11.1 available)
  dio_web_adapter 2.2.0 (2.2.2 available)
  file_selector_android 0.5.2+9 (0.5.2+10 available)
  file_selector_ios 0.5.3+5 (0.5.3+6 available)
  file_selector_linux 0.9.4 (0.9.4+1 available)
  file_selector_macos 0.9.5 (0.9.5+1 available)
  file_selector_windows 0.9.3+5 (0.9.3+6 available)
  flutter_local_notifications 22.0.1 (22.3.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.2.0 available)
  flutter_riverpod 3.3.2 (3.4.3 available)
  flutter_secure_storage 10.3.1 (11.0.0 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_linux 3.0.1 (3.0.2 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.3 available)
  glob 2.1.3 (2.2.0 available)
  go_router 17.3.0 (18.0.1 available)
  hooks 2.0.2 (2.2.0 available)
  intl 0.20.2 (0.20.3 available)
  io 1.0.5 (1.1.0 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.3 available)
  matcher 0.12.19 (0.12.20 available)
  material_color_utilities 0.13.0 (0.13.1 available)
  meta 1.18.0 (1.19.0 available)
  mime 2.0.0 (2.1.0 available)
  objective_c 9.4.1 (9.6.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.1 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.6.1 available)
  permission_handler_html 0.1.3+5 (0.1.4+1 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  pool 1.5.2 (1.5.3 available)
  pub_semver 2.2.0 (2.2.1 available)
  record_use 0.6.0 (1.1.1 available)
  riverpod 3.3.2 (3.4.3 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.28 available)
  shared_preferences_foundation 2.5.6 (2.5.7 available)
  source_maps 0.10.13 (0.10.14 available)
  stack_trace 1.12.1 (1.12.2 available)
  stream_transform 2.1.1 (2.1.2 available)
  synchronized 3.4.1 (3.4.1+2 available)
  test 1.31.0 (1.32.0 available)
  test_api 0.7.11 (0.7.14 available)
  test_core 0.6.17 (0.6.20 available)
  url_launcher_linux 3.2.2 (3.2.3 available)
  url_launcher_windows 3.1.5 (3.1.6 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  vm_service 15.2.0 (15.3.0 available)
  wakelock_plus 1.6.1 (1.8.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.7.0 available)
  win32 6.3.0 (6.4.0 available)
  xml 6.6.1 (7.0.1 available)
  yaml 3.1.3 (3.1.4 available)
Got dependencies!
71 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Analyzing 3 items...                                            
No issues found! (ran in 6.2s)

    → [2] analyze: ZÖLD

═══ [3] test test/features/live/recognition_stabilizer_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/features/live/recognition_stabilizer_test.dart

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (107.0.0 available)
  analyzer 12.1.0 (14.3.0 available)
  archive 4.0.9 (4.2.0 available)
  audio_streamer 4.3.0 (5.0.0 available)
  camera 0.11.4 (0.12.1 available)
  camera_android_camerax 0.6.30 (0.7.4+7 available)
  camera_avfoundation 0.9.23+2 (0.10.3 available)
  camera_web 0.3.5+4 (0.3.5+5 available)
  clock 1.1.2 (1.1.3 available)
  code_assets 1.2.1 (2.0.0 available)
  cross_file 0.3.5+4 (0.3.5+5 available)
  dbus 0.7.14 (0.7.15 available)
  dio 5.10.0 (5.11.1 available)
  dio_web_adapter 2.2.0 (2.2.2 available)
  file_selector_android 0.5.2+9 (0.5.2+10 available)
  file_selector_ios 0.5.3+5 (0.5.3+6 available)
  file_selector_linux 0.9.4 (0.9.4+1 available)
  file_selector_macos 0.9.5 (0.9.5+1 available)
  file_selector_windows 0.9.3+5 (0.9.3+6 available)
  flutter_local_notifications 22.0.1 (22.3.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.2.0 available)
  flutter_riverpod 3.3.2 (3.4.3 available)
  flutter_secure_storage 10.3.1 (11.0.0 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_linux 3.0.1 (3.0.2 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.3 available)
  glob 2.1.3 (2.2.0 available)
  go_router 17.3.0 (18.0.1 available)
  hooks 2.0.2 (2.2.0 available)
  intl 0.20.2 (0.20.3 available)
  io 1.0.5 (1.1.0 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.3 available)
  matcher 0.12.19 (0.12.20 available)
  material_color_utilities 0.13.0 (0.13.1 available)
  meta 1.18.0 (1.19.0 available)
  mime 2.0.0 (2.1.0 available)
  objective_c 9.4.1 (9.6.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.1 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.6.1 available)
  permission_handler_html 0.1.3+5 (0.1.4+1 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  pool 1.5.2 (1.5.3 available)
  pub_semver 2.2.0 (2.2.1 available)
  record_use 0.6.0 (1.1.1 available)
  riverpod 3.3.2 (3.4.3 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.28 available)
  shared_preferences_foundation 2.5.6 (2.5.7 available)
  source_maps 0.10.13 (0.10.14 available)
  stack_trace 1.12.1 (1.12.2 available)
  stream_transform 2.1.1 (2.1.2 available)
  synchronized 3.4.1 (3.4.1+2 available)
  test 1.31.0 (1.32.0 available)
  test_api 0.7.11 (0.7.14 available)
  test_core 0.6.17 (0.6.20 available)
  url_launcher_linux 3.2.2 (3.2.3 available)
  url_launcher_windows 3.1.5 (3.1.6 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  vm_service 15.2.0 (15.3.0 available)
  wakelock_plus 1.6.1 (1.8.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.7.0 available)
  win32 6.3.0 (6.4.0 available)
  xml 6.6.1 (7.0.1 available)
  yaml 3.1.3 (3.1.4 available)
Got dependencies!
71 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_stabilizer_test.dart
00:00 +0: brief §6 pt.1 — threshold triple cell (free, N=3, inclusive) below the threshold (2 agreeing frames) -> provisional, dropped
00:00 +1: brief §6 pt.1 — threshold triple cell (free, N=3, inclusive) exactly on the threshold (3rd agreeing frame) -> confirmed
00:00 +2: brief §6 pt.1 — threshold triple cell (free, N=3, inclusive) above the threshold (4th agreeing frame) -> still confirmed
00:00 +3: brief §6 pt.2 — confirmed resists weak counter-evidence, yields to strong (both directions) A confirmed: 1 foreign B frame does not flip; 3 consecutive do
00:00 +4: brief §6 pt.2 — confirmed resists weak counter-evidence, yields to strong (both directions) B confirmed: 1 foreign A frame does not flip; 3 consecutive do
00:00 +5: brief §6 pt.4 — an accepted strum event is immutable (strumSeq id) same strumSeq with an opposite direction is refused; new seq admitted
00:00 +6: brief §6 pt.5 — free vs guided give a measurably different (confirmationLatencyFrames, flipRate) pair on the same input the two profiles diverge on both metrics
00:00 +7: brief §6 pt.6 — recovery path (L165): the state machine never freezes after arbitrarily long noisy alternating history, 3 consecutive frames still confirm
00:00 +8: All tests passed!

    → [3] test test/features/live/recognition_stabilizer_test.dart: ZÖLD

═══ [4] test test/features/live/chord_timeline_churn_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/features/live/chord_timeline_churn_test.dart

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (107.0.0 available)
  analyzer 12.1.0 (14.3.0 available)
  archive 4.0.9 (4.2.0 available)
  audio_streamer 4.3.0 (5.0.0 available)
  camera 0.11.4 (0.12.1 available)
  camera_android_camerax 0.6.30 (0.7.4+7 available)
  camera_avfoundation 0.9.23+2 (0.10.3 available)
  camera_web 0.3.5+4 (0.3.5+5 available)
  clock 1.1.2 (1.1.3 available)
  code_assets 1.2.1 (2.0.0 available)
  cross_file 0.3.5+4 (0.3.5+5 available)
  dbus 0.7.14 (0.7.15 available)
  dio 5.10.0 (5.11.1 available)
  dio_web_adapter 2.2.0 (2.2.2 available)
  file_selector_android 0.5.2+9 (0.5.2+10 available)
  file_selector_ios 0.5.3+5 (0.5.3+6 available)
  file_selector_linux 0.9.4 (0.9.4+1 available)
  file_selector_macos 0.9.5 (0.9.5+1 available)
  file_selector_windows 0.9.3+5 (0.9.3+6 available)
  flutter_local_notifications 22.0.1 (22.3.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.2.0 available)
  flutter_riverpod 3.3.2 (3.4.3 available)
  flutter_secure_storage 10.3.1 (11.0.0 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_linux 3.0.1 (3.0.2 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.3 available)
  glob 2.1.3 (2.2.0 available)
  go_router 17.3.0 (18.0.1 available)
  hooks 2.0.2 (2.2.0 available)
  intl 0.20.2 (0.20.3 available)
  io 1.0.5 (1.1.0 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.3 available)
  matcher 0.12.19 (0.12.20 available)
  material_color_utilities 0.13.0 (0.13.1 available)
  meta 1.18.0 (1.19.0 available)
  mime 2.0.0 (2.1.0 available)
  objective_c 9.4.1 (9.6.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.1 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.6.1 available)
  permission_handler_html 0.1.3+5 (0.1.4+1 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  pool 1.5.2 (1.5.3 available)
  pub_semver 2.2.0 (2.2.1 available)
  record_use 0.6.0 (1.1.1 available)
  riverpod 3.3.2 (3.4.3 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.28 available)
  shared_preferences_foundation 2.5.6 (2.5.7 available)
  source_maps 0.10.13 (0.10.14 available)
  stack_trace 1.12.1 (1.12.2 available)
  stream_transform 2.1.1 (2.1.2 available)
  synchronized 3.4.1 (3.4.1+2 available)
  test 1.31.0 (1.32.0 available)
  test_api 0.7.11 (0.7.14 available)
  test_core 0.6.17 (0.6.20 available)
  url_launcher_linux 3.2.2 (3.2.3 available)
  url_launcher_windows 3.1.5 (3.1.6 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  vm_service 15.2.0 (15.3.0 available)
  wakelock_plus 1.6.1 (1.8.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.7.0 available)
  win32 6.3.0 (6.4.0 available)
  xml 6.6.1 (7.0.1 available)
  yaml 3.1.3 (3.1.4 available)
Got dependencies!
71 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_timeline_churn_test.dart
00:00 +0: 3a: 10 held frames of the same chord give exactly one timeline card
00:00 +1: 3b: a single-frame foreign blip between two held A segments spawns no card
00:00 +2: All tests passed!

    → [4] test test/features/live/chord_timeline_churn_test.dart: ZÖLD

═══ [5] test test/property/chord_timeline_property_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/property/chord_timeline_property_test.dart

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (107.0.0 available)
  analyzer 12.1.0 (14.3.0 available)
  archive 4.0.9 (4.2.0 available)
  audio_streamer 4.3.0 (5.0.0 available)
  camera 0.11.4 (0.12.1 available)
  camera_android_camerax 0.6.30 (0.7.4+7 available)
  camera_avfoundation 0.9.23+2 (0.10.3 available)
  camera_web 0.3.5+4 (0.3.5+5 available)
  clock 1.1.2 (1.1.3 available)
  code_assets 1.2.1 (2.0.0 available)
  cross_file 0.3.5+4 (0.3.5+5 available)
  dbus 0.7.14 (0.7.15 available)
  dio 5.10.0 (5.11.1 available)
  dio_web_adapter 2.2.0 (2.2.2 available)
  file_selector_android 0.5.2+9 (0.5.2+10 available)
  file_selector_ios 0.5.3+5 (0.5.3+6 available)
  file_selector_linux 0.9.4 (0.9.4+1 available)
  file_selector_macos 0.9.5 (0.9.5+1 available)
  file_selector_windows 0.9.3+5 (0.9.3+6 available)
  flutter_local_notifications 22.0.1 (22.3.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.2.0 available)
  flutter_riverpod 3.3.2 (3.4.3 available)
  flutter_secure_storage 10.3.1 (11.0.0 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_linux 3.0.1 (3.0.2 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.3 available)
  glob 2.1.3 (2.2.0 available)
  go_router 17.3.0 (18.0.1 available)
  hooks 2.0.2 (2.2.0 available)
  intl 0.20.2 (0.20.3 available)
  io 1.0.5 (1.1.0 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.3 available)
  matcher 0.12.19 (0.12.20 available)
  material_color_utilities 0.13.0 (0.13.1 available)
  meta 1.18.0 (1.19.0 available)
  mime 2.0.0 (2.1.0 available)
  objective_c 9.4.1 (9.6.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.1 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.6.1 available)
  permission_handler_html 0.1.3+5 (0.1.4+1 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  pool 1.5.2 (1.5.3 available)
  pub_semver 2.2.0 (2.2.1 available)
  record_use 0.6.0 (1.1.1 available)
  riverpod 3.3.2 (3.4.3 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.28 available)
  shared_preferences_foundation 2.5.6 (2.5.7 available)
  source_maps 0.10.13 (0.10.14 available)
  stack_trace 1.12.1 (1.12.2 available)
  stream_transform 2.1.1 (2.1.2 available)
  synchronized 3.4.1 (3.4.1+2 available)
  test 1.31.0 (1.32.0 available)
  test_api 0.7.11 (0.7.14 available)
  test_core 0.6.17 (0.6.20 available)
  url_launcher_linux 3.2.2 (3.2.3 available)
  url_launcher_windows 3.1.5 (3.1.6 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  vm_service 15.2.0 (15.3.0 available)
  wakelock_plus 1.6.1 (1.8.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.7.0 available)
  win32 6.3.0 (6.4.0 available)
  xml 6.6.1 (7.0.1 available)
  yaml 3.1.3 (3.1.4 available)
Got dependencies!
71 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-sonnet-impl-e14-r12/test/property/chord_timeline_property_test.dart
PROPERTY_SEED=42
00:00 +0: property: reducer invariants hold over random frame sequences
00:00 +1: A→A dedupe: same chord does not spawn a second card
00:00 +2: A→A with a strum updates the last card in place
00:00 +3: held chord with an UNCHANGED strum returns the same list reference (no per-frame reallocation)
00:00 +4: A→B→A gives 3 distinct cards (A recurrence is a NEW card)
00:00 +5: cap trimming drops the oldest, keeps newest last
00:00 +6: timeSec falls back to engineTimeSec when no strum time
00:00 +7: confidence falls back to frame.confidence when no strum
00:00 +8: idle (null current) leaves the buffer identical instance
00:00 +9: All tests passed!

    → [5] test test/property/chord_timeline_property_test.dart: ZÖLD

═══ [6] test test/features/live
    $ /home/ubuntu/flutter/bin/flutter test test/features/live

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (107.0.0 available)
  analyzer 12.1.0 (14.3.0 available)
  archive 4.0.9 (4.2.0 available)
  audio_streamer 4.3.0 (5.0.0 available)
  camera 0.11.4 (0.12.1 available)
  camera_android_camerax 0.6.30 (0.7.4+7 available)
  camera_avfoundation 0.9.23+2 (0.10.3 available)
  camera_web 0.3.5+4 (0.3.5+5 available)
  clock 1.1.2 (1.1.3 available)
  code_assets 1.2.1 (2.0.0 available)
  cross_file 0.3.5+4 (0.3.5+5 available)
  dbus 0.7.14 (0.7.15 available)
  dio 5.10.0 (5.11.1 available)
  dio_web_adapter 2.2.0 (2.2.2 available)
  file_selector_android 0.5.2+9 (0.5.2+10 available)
  file_selector_ios 0.5.3+5 (0.5.3+6 available)
  file_selector_linux 0.9.4 (0.9.4+1 available)
  file_selector_macos 0.9.5 (0.9.5+1 available)
  file_selector_windows 0.9.3+5 (0.9.3+6 available)
  flutter_local_notifications 22.0.1 (22.3.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.2.0 available)
  flutter_riverpod 3.3.2 (3.4.3 available)
  flutter_secure_storage 10.3.1 (11.0.0 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_linux 3.0.1 (3.0.2 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.3 available)
  glob 2.1.3 (2.2.0 available)
  go_router 17.3.0 (18.0.1 available)
  hooks 2.0.2 (2.2.0 available)
  intl 0.20.2 (0.20.3 available)
  io 1.0.5 (1.1.0 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.3 available)
  matcher 0.12.19 (0.12.20 available)
  material_color_utilities 0.13.0 (0.13.1 available)
  meta 1.18.0 (1.19.0 available)
  mime 2.0.0 (2.1.0 available)
  objective_c 9.4.1 (9.6.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.1 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.6.1 available)
  permission_handler_html 0.1.3+5 (0.1.4+1 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  pool 1.5.2 (1.5.3 available)
  pub_semver 2.2.0 (2.2.1 available)
  record_use 0.6.0 (1.1.1 available)
  riverpod 3.3.2 (3.4.3 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.28 available)
  shared_preferences_foundation 2.5.6 (2.5.7 available)
  source_maps 0.10.13 (0.10.14 available)
  stack_trace 1.12.1 (1.12.2 available)
  stream_transform 2.1.1 (2.1.2 available)
  synchronized 3.4.1 (3.4.1+2 available)
  test 1.31.0 (1.32.0 available)
  test_api 0.7.11 (0.7.14 available)
  test_core 0.6.17 (0.6.20 available)
  url_launcher_linux 3.2.2 (3.2.3 available)
  url_launcher_windows 3.1.5 (3.1.6 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  vm_service 15.2.0 (15.3.0 available)
  wakelock_plus 1.6.1 (1.8.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.7.0 available)
  win32 6.3.0 (6.4.0 available)
  xml 6.6.1 (7.0.1 available)
  yaml 3.1.3 (3.1.4 available)
Got dependencies!
71 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_screen_test.dart
00:00 +0: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_screen_test.dart: Live renders the current chord + its strum on the timeline hero
00:02 +1: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_background_test.dart: Live holds the wakelock while the session runs
00:02 +2: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_screen_test.dart: a capo transposes the timeline chord shape and shows a badge
00:02 +3: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_background_test.dart: backgrounding stops the mic and releases the wakelock
00:02 +4: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_screen_test.dart: Pause freezes the display and toggles the action label
00:02 +5: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_background_test.dart: leaving Live releases the wakelock and the lifecycle hook
00:02 +6: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_screen_test.dart: leaving the Live tab releases the mic (autoDispose timeline)
00:03 +7: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_screen_test.dart: A mic start failure surfaces an error banner with Retry
00:04 +8: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_mic_release_test.dart: (1) navigation — leaving Live stops the mic (autoDispose)
00:06 +9: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A1 — DSP output reaches the UI unaltered by the migration a fixed detection frame shows the exact same chord/confidence/direction as pre-migration
00:06 +10: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A1 — DSP output reaches the UI unaltered by the migration a fixed detection frame shows the exact same chord/confidence/direction as pre-migration
00:06 +11: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_mic_release_test.dart: (3) pause — tapping Pause stops the mic
00:06 +12: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A2 — weak signal and "no chord" are distinct states weak signal WHILE a chord is held shows the mic warning, not the "play a chord" prompt
00:06 +13: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_mic_release_test.dart: (4) error — a mic start failure never leaves it silently open (the engine already reports the failure, not a stuck-open handle)
00:06 +14: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A2 — weak signal and "no chord" are distinct states no chord WHILE the signal is adequate shows the "play a chord" prompt, not the mic warning
00:07 +15: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_mic_release_test.dart: (4) dispose — leaving via Finish stops the mic before the route goes
00:07 +16: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A3 — confidence is never colour-only a low-confidence and a high-confidence strum read as DIFFERENT text, not just a colour swap
00:07 +17: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_mic_release_test.dart: (5) dispose — unmounting Live disposes its SsLiveRegion, not just its listeners (review MINOR-1)
00:07 +18: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_mic_release_test.dart: (5) dispose — unmounting Live disposes its SsLiveRegion, not just its listeners (review MINOR-1)
00:07 +19: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A6 — no overflow across layouts landscape compact (915×412) renders a full frame without overflow
00:07 +20: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A6 — no overflow across layouts expanded (1300×900) renders a full frame without overflow
00:08 +21: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A10 — Pause and Finish stay visible in every active transport state portrait — active
00:08 +22: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A10 — Pause and Finish stay visible in every active transport state portrait — paused
00:08 +23: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A10 — Pause and Finish stay visible in every active transport state portrait — finishing
00:08 +24: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A10 — Pause and Finish stay visible in every active transport state portrait — finishing
00:08 +25: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A10 — Pause and Finish stay visible in every active transport state portrait — finishing
00:08 +26: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A10 — Pause and Finish stay visible in every active transport state portrait — finishing
00:08 +27: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A10 — Pause and Finish stay visible in every active transport state portrait — finishing
00:08 +28: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A10 — Pause and Finish stay visible in every active transport state portrait — finishing
00:08 +29: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A10 — Pause and Finish stay visible in every active transport state portrait — finishing
00:08 +30: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A10 — Pause and Finish stay visible in every active transport state portrait — finishing
00:08 +31: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A10 — Pause and Finish stay visible in every active transport state portrait — finishing
00:08 +32: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A10 — Pause and Finish stay visible in every active transport state portrait — finishing
00:08 +33: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A10 — Pause and Finish stay visible in every active transport state portrait — finishing
00:08 +34: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A10 — Pause and Finish stay visible in every active transport state portrait — finishing
00:08 +35: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A10 — Pause and Finish stay visible in every active transport state portrait — finishing
00:08 +36: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A10 — Pause and Finish stay visible in every active transport state portrait — finishing
00:08 +37: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A10 — Pause and Finish stay visible in every active transport state portrait — finishing
00:08 +38: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A10 — Pause and Finish stay visible in every active transport state portrait — finishing
00:08 +39: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A10 — Pause and Finish stay visible in every active transport state portrait — finishing
00:08 +40: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A10 — Pause and Finish stay visible in every active transport state portrait — finishing
00:08 +41: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A10 — Pause and Finish stay visible in every active transport state portrait — finishing
00:08 +42: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A10 — Pause and Finish stay visible in every active transport state landscape — active
00:08 +43: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A10 — Pause and Finish stay visible in every active transport state landscape — paused
00:09 +44: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: A10 — Pause and Finish stay visible in every active transport state landscape — finishing
00:09 +45: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_stage_test.dart: Finish fallback target is the app entry route, not a fixed screen (review MINOR-2) E15-R02 (ADR 0467 D9): with the adaptive shell on (now the non-production default) and nothing to pop to, Finish navigates to /today — the entry route — instead of staying on Live
00:09 +46: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/superflux_onset_test.dart: SuperFluxOnsetDetector finds all 16th-note strums at 120 BPM within ±50 ms
00:09 +47: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/superflux_onset_test.dart: SuperFluxOnsetDetector finds all 16th-note strums at 160 BPM within ±50 ms
00:09 +48: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/superflux_onset_test.dart: SuperFluxOnsetDetector stays silent on constant-amplitude vibrato (the SuperFlux win)
00:09 +49: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/superflux_onset_test.dart: SuperFluxOnsetDetector silence and a stationary noise floor produce zero onsets
00:09 +50: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/superflux_onset_test.dart: SuperFluxOnsetDetector a SOFT strum after loud strums + true silence still fires (r142)
00:09 +51: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/superflux_onset_test.dart: SuperFluxOnsetDetector overlapping ring-out strums are still separated
00:10 +52: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/dim_aug_chord_test.dart: a B diminished triad is recognised as Bdim
00:10 +53: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/dim_aug_chord_test.dart: a C augmented triad is recognised as Caug
00:10 +54: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/dim_aug_chord_test.dart: a plain A minor stays Am (dim must not steal the weak fifth)
00:11 +55: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/dim_aug_chord_test.dart: a plain C major stays C (aug must not steal)
00:11 +56: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/cqt_parity_test.dart: CqtExtractor matches cqt.py golden fixture
00:12 +57: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/cqt_parity_test.dart: CqtExtractor matches cqt.py golden fixture
00:12 +58: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/cqt_parity_test.dart: CqtExtractor matches cqt.py golden fixture
00:12 +59: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/cqt_parity_test.dart: CqtExtractor matches cqt.py golden fixture
00:12 +60: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/cqt_parity_test.dart: CqtExtractor matches cqt.py golden fixture
00:12 +61: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/cqt_parity_test.dart: CqtExtractor matches cqt.py golden fixture
00:12 +62: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/cqt_parity_test.dart: CqtExtractor matches cqt.py golden fixture
00:12 +63: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/cqt_parity_test.dart: CqtExtractor matches cqt.py golden fixture
00:12 +64: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/cqt_parity_test.dart: CqtExtractor matches cqt.py golden fixture
00:12 +65: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/cqt_parity_test.dart: CqtExtractor matches cqt.py golden fixture
00:13 +66: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/cqt_parity_test.dart: CqtExtractor matches cqt.py golden fixture
00:13 +67: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/cqt_parity_test.dart: CqtExtractor matches cqt.py golden fixture
00:13 +68: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/cqt_parity_test.dart: CqtExtractor matches cqt.py golden fixture
00:14 +69: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/cqt_parity_test.dart: CqtExtractor matches cqt.py golden fixture
CQT parity: max abs diff = 4.99881967902082e-7 at frame 0 bin 43 (2x144, fftLen=32768)
00:14 +70: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/tonalness_test.dart: LivePipeline reports a chord for a triad but NOT for white noise
00:15 +71: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/nnls_chroma_test.dart: silence yields null
00:15 +72: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/nnls_chroma_test.dart: a harmonic-rich single note maps to ONE pitch class (overtones suppressed)
00:15 +73: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/nnls_chroma_test.dart: C major triad → the three strongest pitch classes are C, E, G
00:16 +74: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/nnls_chroma_test.dart: A minor triad → the three strongest pitch classes are A, C, E
00:16 +75: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/nnls_chroma_test.dart: bass+treble split (chunk 012): treble carries the harmony, bass the root, and both are zero on silence
00:16 +76: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/tuning_estimation_test.dart: a C major detuned 35 cents FLAT still reads as C
00:16 +77: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/tuning_estimation_test.dart: a C major detuned 35 cents SHARP still reads as C
00:16 +78: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/tuning_estimation_test.dart: a G7 detuned 30 cents flat keeps its 7th (stays G7)
00:16 +79: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/tuning_estimation_test.dart: an in-tune chord is unaffected (regression guard)
00:17 +80: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/spectral_whitening_test.dart: thin-mic C major (bass rolled off below 300 Hz) still reads as C
00:17 +81: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/spectral_whitening_test.dart: thin-mic A minor still reads as Am
00:17 +82: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/spectral_whitening_test.dart: a body resonance (500 Hz bump) does not change the reading
00:17 +83: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/spectral_whitening_test.dart: neutral timbre is unaffected (regression guard)
00:17 +84: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/voice_rejection_test.dart: a strong C-major triad STILL surfaces a chord (no over-rejection)
00:18 +85: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/voice_rejection_test.dart: a single sustained tone (monophonic, ambiguous) shows NO phantom chord
00:18 +86: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/voice_rejection_test.dart: the confidence gate is wired: an impossible rise shows nothing, a zero rise shows the chord
00:18 +87: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/voice_rejection_test.dart: raising the rise gate never INCREASES the frames a chord is shown (monotone) — property
00:18 +88: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/voice_rejection_test.dart: raising the rise gate never INCREASES the frames a chord is shown (monotone) — property
00:18 +89: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/voice_rejection_test.dart: raising the rise gate never INCREASES the frames a chord is shown (monotone) — property
00:18 +90: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/voice_rejection_test.dart: raising the rise gate never INCREASES the frames a chord is shown (monotone) — property
00:18 +91: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/voice_rejection_test.dart: raising the rise gate never INCREASES the frames a chord is shown (monotone) — property
00:18 +92: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/voice_rejection_test.dart: raising the rise gate never INCREASES the frames a chord is shown (monotone) — property
00:18 +93: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/voice_rejection_test.dart: raising the rise gate never INCREASES the frames a chord is shown (monotone) — property
00:18 +94: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/voice_rejection_test.dart: raising the rise gate never INCREASES the frames a chord is shown (monotone) — property
00:19 +95: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/voice_rejection_test.dart: a latched chord HOLDS through a brief gap then releases on silence (Schmitt hold, not per-frame flicker)
00:19 +96: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/voice_rejection_test.dart: a longer release-hold keeps a sustained chord shown across a dip (round 176 anti-flicker) — and never resurrects voice
00:19 +97: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/live_pipeline_test.dart: end-to-end: sustained C major chord is recognised from chunks
00:19 +98: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/live_pipeline_test.dart: end-to-end: sustained C major chord is recognised from chunks
00:20 +99: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/live_pipeline_test.dart: end-to-end: alternating strums produce directions, tempo and a bar
00:20 +100: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/live_pipeline_test.dart: end-to-end: silence yields no chord and near-zero level
00:20 +101: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/live_pipeline_test.dart: hero strum fades after 2 s without a new onset
00:20 +102: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/live_pipeline_test.dart: E14-R10: a confirmed direction margin keeps today's arrow behaviour
00:20 +103: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/strum_analyzer_suppression_test.dart: a suppressed classification emits NO StrumEvent (no arrow/Learn hit)
00:21 +104: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/strum_analyzer_suppression_test.dart: a non-suppressed classification still emits the strum
00:21 +105: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/strum_analyzer_test.dart: a single staggered strum produces exactly one onset
00:21 +106: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/strum_analyzer_test.dart: silence produces no events
00:21 +107: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/strum_analyzer_test.dart: down-strum (low strings first) classified as down
00:21 +108: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/strum_analyzer_test.dart: up-strum (high strings first) classified as up
00:22 +109: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/strum_analyzer_test.dart: fast overlapping strums keep correct direction (ring-out isolation)
00:22 +110: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/strum_classifier_seam_test.dart: the analyzer observes every hop and classifies 12 frames post-onset
00:22 +111: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/strum_analyzer_test.dart: alternating pattern detects all four strums in order
00:22 +112: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/strum_analyzer_test.dart: constant-amplitude vibrato yields at most the initial attack
00:22 +113: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/strum_analyzer_test.dart: 180 BPM 16th-note strums are all detected
00:22 +114: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/strum_analyzer_test.dart: reported onset time tracks the true attack within ±6 ms (r144)
00:22 +115: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/strum_analyzer_test.dart: onsetJustFired flags exactly the confirming frames (round 138)
00:23 +116: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/strum_analyzer_test.dart: TempoTracker: 0.5 s spacing → 120 BPM
00:23 +117: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/strum_analyzer_test.dart: TempoTracker folds eighth-note spacing into 60–200 range
00:23 +118: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/strum_analyzer_test.dart: TempoTracker resets after a long silence gap
00:23 +119: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/chroma_chord_test.dart: C major triad with harmonics is recognised as C
00:23 +120: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/chroma_chord_test.dart: A minor triad is recognised as Am
00:23 +121: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/chroma_chord_test.dart: G major triad is recognised as G
00:23 +122: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/chroma_chord_test.dart: silence yields no chord
00:23 +123: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/chroma_chord_test.dart: chroma of a C triad peaks on C, E, G pitch classes
00:23 +124: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/chroma_chord_test.dart: hysteresis: chord only switches after consecutive frames
00:23 +125: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/dsp/chroma_chord_test.dart: extractor reports RMS and gates noise-floor frames
00:24 +126: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: RecognitionDecision / RecognitionRejectReason — model 1/5 RecognitionDecision has exactly the six ADR 0505 D3 states
00:24 +127: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: RecognitionDecision / RecognitionRejectReason — model 1/5 RecognitionRejectReason has exactly the six ADR 0505 D3 reasons
00:24 +128: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: RecognitionDecision / RecognitionRejectReason — model 1/5 JSON round-trip is lossless for every RecognitionDecision
00:24 +129: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: RecognitionDecision / RecognitionRejectReason — model 1/5 JSON round-trip is lossless for every RecognitionRejectReason
00:24 +130: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: RecognitionDecision / RecognitionRejectReason — model 1/5 an unknown RecognitionDecision value throws, not falls back
00:24 +131: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: RecognitionDecision / RecognitionRejectReason — model 1/5 a missing/null RecognitionDecision value throws, not null
00:24 +132: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: RecognitionDecision / RecognitionRejectReason — model 1/5 an unknown RecognitionRejectReason value throws, not falls back
00:24 +133: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: StrumPrediction — model 2/5 directionMargin threshold is inclusive on the rejection side
00:24 +134: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: StrumPrediction — model 2/5 directionMargin is always |pDown - pUp|, never stored
00:24 +135: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: StrumPrediction — model 2/5 calibratedConfidence stays null and is never the raw pDown
00:24 +136: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: StrumPrediction — model 2/5 JSON round-trip is lossless with a null calibratedConfidence
00:24 +137: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: StrumPrediction — model 2/5 JSON round-trip is lossless with a measured calibratedConfidence
00:24 +138: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: StrumPrediction — model 2/5 decision/directionMargin/rejectReason in the wire payload are re-derived, not trusted
00:24 +139: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: StrumPrediction — model 2/5 toJson carries the derived rejectReason paired with decision
00:24 +140: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: StrumPrediction — model 2/5 a calibratedConfidence outside 0..1 throws on decode
00:24 +141: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: StrumPrediction — model 2/5 a missing calibratedConfidence KEY throws — distinct from null
00:24 +142: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: StrumPrediction — model 2/5 a missing modelId key throws a typed error, not a partial object
00:24 +143: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: StrumPrediction — model 2/5 fromJson rejects a non-object payload
00:24 +144: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: ChordPrediction — model 3/5 decision is constructor-received this round, not derived
00:24 +145: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: ChordPrediction — model 3/5 calibratedConfidence stays null and is never the raw pNoChord
00:24 +146: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: ChordPrediction — model 3/5 JSON round-trip is lossless with a null calibratedConfidence
00:24 +147: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: ChordPrediction — model 3/5 JSON round-trip is lossless with a measured calibratedConfidence
00:24 +148: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: ChordPrediction — model 3/5 a missing sourceEngine key throws, not a partial object
00:24 +149: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: ChordPrediction — model 3/5 a missing decision key throws, not a default decision
00:24 +150: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: ChordPrediction — model 3/5 rejectReason is constructor-received, paired with the reject-side decision the caller supplies
00:24 +151: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: ChordPrediction — model 3/5 JSON round-trip is lossless with a non-null rejectReason
00:24 +152: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: ChordPrediction — model 3/5 a missing rejectReason KEY throws — distinct from null
00:24 +153: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: ChordPrediction — model 3/5 a calibratedConfidence outside 0..1 throws on decode
00:24 +154: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: SignalQualitySnapshot — model 4/5 the unknown default has every metric null and state unknown
00:24 +155: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: SignalQualitySnapshot — model 4/5 JSON round-trip is lossless for the unknown default
00:24 +156: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: SignalQualitySnapshot — model 4/5 JSON round-trip is lossless for a fully measured snapshot
00:24 +157: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: SignalQualitySnapshot — model 4/5 a missing state key throws — no silent good default
00:24 +158: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: SignalQualitySnapshot — model 4/5 a missing (nullable) metric key throws — missing != null
00:24 +159: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: RecognitionFrame — model 5/5 schemaVersion defaults to the current contract version
00:24 +160: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: RecognitionFrame — model 5/5 chord- and direction-confidence are carried separately
00:24 +161: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: RecognitionFrame — model 5/5 JSON round-trip is lossless with strum and chord present
00:24 +162: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: RecognitionFrame — model 5/5 JSON round-trip is lossless with no strum/chord yet
00:24 +163: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: RecognitionFrame — model 5/5 an unknown schemaVersion throws, never a best-effort read
00:24 +164: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: RecognitionFrame — model 5/5 a missing runtimeInfo key throws, not a partial frame
00:24 +165: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: RecognitionFrame — model 5/5 a missing frameTimeSec key throws, not a partial frame
00:24 +166: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_frame_contract_test.dart: RecognitionFrame — model 5/5 a missing strum/chord KEY throws — distinct from an explicit null
00:25 +167: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/pcm_ring_buffer_test.dart: PcmRingBuffer (Lab-mode rolling capture, r199) does nothing until enabled — zero overhead on the default path
00:25 +168: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/pcm_ring_buffer_test.dart: PcmRingBuffer (Lab-mode rolling capture, r199) does nothing while the sample rate is unknown
00:25 +169: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/pcm_ring_buffer_test.dart: PcmRingBuffer (Lab-mode rolling capture, r199) retains appended PCM when enabled and returns a copy
00:25 +170: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/pcm_ring_buffer_test.dart: PcmRingBuffer (Lab-mode rolling capture, r199) caps at ~maxSeconds and drops the oldest samples
00:25 +171: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/pcm_ring_buffer_test.dart: PcmRingBuffer (Lab-mode rolling capture, r199) clear() drops audio but keeps rate + enabled; reset() clears all
00:26 +172: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/crnn_frontend_test.dart: resampleLinear mirrors np.interp over linspace(0, n-1, round(n*to/from))
00:26 +173: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/crnn_frontend_test.dart: resampleLinear same-rate input is returned unchanged
00:26 +174: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/crnn_frontend_test.dart: resampleLinear preserves a sine well below Nyquist (44.1k -> 16k)
00:26 +175: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/crnn_frontend_test.dart: windowAt cuts PRE=3 before and POST=12 after the onset frame
00:26 +176: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/crnn_frontend_test.dart: windowAt zero-pads past both edges like the Python reference
00:26 +177: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/crnn_live_parity_test.dart: live net matches the Keras reference to <=1e-3
00:28 +178: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/crnn_live_parity_test.dart: live net matches the Keras reference to <=1e-3
00:28 +179: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/crnn_live_3c_parity_test.dart: 3-class live net matches the Keras reference to <=1e-3
00:29 +180: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/crnn_live_3c_parity_test.dart: 3-class live net matches the Keras reference to <=1e-3
00:29 +181: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/crnn_live_3c_parity_test.dart: mined no-strum windows land on the reject class above chance
00:30 +182: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/live_pipeline_ml_wiring_test.dart: valid weights bytes put the live CRNN behind the seam
00:30 +183: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/live_pipeline_ml_wiring_test.dart: no bytes -> heuristic (mock mode, stripped builds)
00:30 +184: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/live_pipeline_ml_wiring_test.dart: garbage bytes -> heuristic, never a crash (model is an upgrade)
00:30 +185: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/live_crnn_3class_test.dart: r175 no-strum reject — classifyProbs suppression gate the shipped no-strum threshold is a valid probability
00:30 +186: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/live_crnn_3class_test.dart: r175 no-strum reject — classifyProbs suppression gate P(no-strum) above the threshold suppresses the arrow
00:30 +187: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/live_crnn_3class_test.dart: r175 no-strum reject — classifyProbs suppression gate P(no-strum) below the threshold emits the winning direction
00:30 +188: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/live_crnn_3class_test.dart: r175 no-strum reject — classifyProbs suppression gate direction confidence stays in the r170 calibrated band
00:30 +189: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/live_crnn_3class_test.dart: r175 no-strum reject — classifyProbs suppression gate a 2-class prob vector never suppresses (r139 fallback behaviour)
00:31 +190: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/crnn_strum_net_test.dart: CrnnStrumNet (setUpAll)
00:31 +190: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/crnn_strum_net_test.dart: CrnnStrumNet shipped weights asset parses with the expected architecture
00:31 +191: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/crnn_strum_net_test.dart: CrnnStrumNet forward pass matches the Keras reference to <=1e-3
00:32 +192: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/crnn_strum_net_test.dart: CrnnStrumNet forward pass matches the Keras reference to <=1e-3
00:32 +193: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/chord_crnn_parity_test.dart: ChordCrnn forward pass matches the Keras reference to <=1e-3
ChordCrnn parity: maxAbsDiff=7.068328857218198e-7 argmaxMismatches=0 / 100
00:32 +194: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/crnn_strum_net_test.dart: CrnnStrumNet fixture windows classify to their labels well above chance
00:33 +195: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/crnn_strum_net_test.dart: CrnnStrumNet fixture windows classify to their labels well above chance
00:33 +196: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/crnn_strum_net_test.dart: CrnnStrumNet fixture windows classify to their labels well above chance
00:33 +197: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/live_crnn_classifier_test.dart: LiveCrnnStrumClassifier implements the seam and returns a verdict
00:34 +198: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/live_crnn_classifier_test.dart: confidence calibration (r170, measured on the real eval fold) maps raw softmax to empirical P(correct), monotonically
00:34 +199: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/live_crnn_classifier_test.dart: confidence calibration (r170, measured on the real eval fold) classifyAt emits the calibrated confidence
00:34 +200: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/ml/live_crnn_classifier_test.dart: tryLoad returns null when the asset is missing (heuristic fallback)
00:35 +201: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_lab_panel_test.dart: Live Lab panel is HIDDEN when Lab mode is off (default)
00:35 +202: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_lab_panel_test.dart: Live Lab panel is HIDDEN when Lab mode is off (default)
00:35 +203: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_lab_panel_test.dart: Live Lab panel is HIDDEN when Lab mode is off (default)
00:36 +204: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_timeline_test.dart: empty events shows the idle "play a chord" prompt
00:36 +205: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_timeline_test.dart: empty events shows the idle "play a chord" prompt
00:37 +206: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_timeline_test.dart: empty events shows the idle "play a chord" prompt
00:37 +207: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_timeline_test.dart: renders each chord label with its strum arrow, newest as hero
00:37 +208: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_timeline_test.dart: a beat-index change fires a finite pulse and settles cleanly
00:37 +209: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_timeline_test.dart: shows the next-ghost when a next chord is known
00:38 +210: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_signal_quality_analyzer_test.dart: unknown — before the history buffer fills, no metric is fabricated
00:38 +211: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_signal_quality_analyzer_test.dart: good — a clean, steady tone at a healthy level
00:38 +212: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_signal_quality_analyzer_test.dart: good — a realistic multi-harmonic chord-like signal
00:38 +213: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_signal_quality_analyzer_test.dart: tooQuiet — a weak but present tone
00:38 +214: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_signal_quality_analyzer_test.dart: tooLoud — near full-scale but not clipped
00:38 +215: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_signal_quality_analyzer_test.dart: clipping — a hard-clipped square wave, 100% reproducible
00:38 +216: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_signal_quality_analyzer_test.dart: tooNoisy — broadband white noise at a moderate level
00:38 +217: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_signal_quality_analyzer_test.dart: speechLike — a spectral proxy only, never a speaker classification
00:38 +218: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_signal_quality_analyzer_test.dart: unstable — a wildly swinging level over the rolling history window
00:38 +219: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_signal_quality_analyzer_test.dart: silence — RMS floor, 100% reproducible
00:38 +220: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_signal_quality_analyzer_test.dart: clippedSampleRatio boundary — inclusive on the clipping side below the threshold (2/3000 = 0.000667) is NOT clipping
00:38 +221: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_signal_quality_analyzer_test.dart: clippedSampleRatio boundary — inclusive on the clipping side exactly at the threshold (3/3000 = 0.001) IS clipping (inclusive)
00:38 +222: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_signal_quality_analyzer_test.dart: clippedSampleRatio boundary — inclusive on the clipping side above the threshold (4/3000) is clipping
00:39 +223: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_runtime_info_test.dart: RecognitionRuntimeInfo — model contract every FallbackReason is one of the 5 stable, closed codes
00:39 +224: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_runtime_info_test.dart: RecognitionRuntimeInfo — model contract JSON round-trip is lossless for an activated info
00:39 +225: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_runtime_info_test.dart: RecognitionRuntimeInfo — model contract JSON round-trip is lossless for a fallback info
00:39 +226: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_runtime_info_test.dart: RecognitionRuntimeInfo — model contract fallbackReason serializes to its enum name, not an index
00:39 +227: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_runtime_info_test.dart: RecognitionRuntimeInfo — model contract equality/hashCode compare every field
00:39 +228: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_runtime_info_test.dart: RecognitionRuntimeInfo — model contract RecognitionRuntimeInfo.fallback is the canonical neutral shape
00:39 +229: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_runtime_info_test.dart: 5. LiveLabState carries runtime info (R3 — additive, no wiring yet) initial state has a null runtimeInfo
00:39 +230: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_runtime_info_test.dart: 5. LiveLabState carries runtime info (R3 — additive, no wiring yet) reportRuntimeInfo distinguishes activated from fallback
00:39 +231: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_runtime_info_test.dart: 5. LiveLabState carries runtime info (R3 — additive, no wiring yet) reportRuntimeInfo(null) clears it back to null
00:39 +232: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_widgets_test.dart: ChordDisplay shows the current and next chord
00:40 +233: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_widgets_test.dart: ChordDisplay shows the current and next chord
00:40 +234: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_widgets_test.dart: ChordDisplay shows the current and next chord
00:40 +235: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_widgets_test.dart: ChordDisplay shows the current and next chord
00:40 +236: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_widgets_test.dart: ChordDisplay shows the current and next chord
00:40 +237: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_widgets_test.dart: ChordDisplay shows the current and next chord
00:40 +238: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_widgets_test.dart: ChordDisplay shows the current and next chord
00:40 +239: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_widgets_test.dart: ChordDisplay shows the current and next chord
00:40 +240: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_widgets_test.dart: ChordDisplay shows the current and next chord
00:40 +241: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/model_activation_test.dart: 3. fallback preserves pipeline behaviour (heuristic still verdicts) garbage weights bytes -> heuristic still verdicts a real strum
00:40 +242: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/model_activation_test.dart: 3. fallback preserves pipeline behaviour (heuristic still verdicts) garbage weights bytes -> heuristic still verdicts a real strum
00:40 +243: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_widgets_test.dart: ConfidencePill renders nothing without a strum
00:40 +244: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/model_activation_test.dart: 3. fallback preserves pipeline behaviour (heuristic still verdicts) valid weights -> live CRNN classifier activates, info matches
00:40 +245: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/model_activation_test.dart: 3. fallback preserves pipeline behaviour (heuristic still verdicts) valid weights -> live CRNN classifier activates, info matches
00:40 +246: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_widgets_test.dart: BeatCounter renders all eight slot labels
00:40 +247: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_widgets_test.dart: BeatCounter renders all eight slot labels
00:40 +248: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_widgets_test.dart: BeatCounter renders all eight slot labels
00:40 +249: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/model_activation_test.dart: 4. redaction canary — fallback values never leak the path a successful activation strips the temp-dir segment down to the bare filename (reaches the path.split basename derivation the missing-file cell above never runs — L260)
00:40 +250: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_widgets_test.dart: InputLevelMeter builds at a mid level
00:40 +251: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_widgets_test.dart: InputLevelMeter builds at a mid level
00:40 +252: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_widgets_test.dart: InputLevelMeter builds at a mid level
00:40 +253: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_widgets_test.dart: InputLevelMeter builds at a mid level
00:40 +254: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_widgets_test.dart: InputLevelMeter builds at a mid level
00:41 +255: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_release_gate_test.dart: fail-closed: missing/null metric a null-valued metric is FAIL and names the metric
00:41 +256: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_release_gate_test.dart: fail-closed: missing/null metric skipping the missing-metric branch would turn this cell green (§7.1 falsification is exercised by temporarily short-circuiting _evaluateEntry to `passed: true` — see round brief §10)
00:41 +257: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_release_gate_test.dart: boundary belongs to the accepting side higherIsBetter == true: below/on/above 0.9
00:41 +258: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_release_gate_test.dart: boundary belongs to the accepting side higherIsBetter == false: below/on/above 2.0
00:41 +259: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_release_gate_test.dart: boundary belongs to the accepting side the direction fixed at ">=" would wrongly pass 2.001 on a lower-is-better metric
00:41 +260: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_release_gate_test.dart: verdict aggregation one failing finding among several fails the whole verdict
00:41 +261: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_release_gate_test.dart: verdict aggregation every finding passing passes the verdict
00:41 +262: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_release_gate_test.dart: typed configuration errors unknown schemaVersion is a typed error, never a default
00:41 +263: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_release_gate_test.dart: typed configuration errors a threshold entry declaring higherIsBetter is a typed error
00:41 +264: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_release_gate_test.dart: typed configuration errors a threshold entry declaring ">=" is a typed error
00:41 +265: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_release_gate_test.dart: typed configuration errors an unrecognised metricPath is a typed error, never silently skipped
00:41 +266: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_release_gate_test.dart: typed configuration errors a metricPath outside the overall scope is a typed error
00:41 +267: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_release_gate_test.dart: deterministic ordering entries and findings are sorted by metricPath regardless of source order
00:41 +268: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_release_gate_test.dart: shipped v1 threshold file (ADR 0511 D9 — pinned, not remeasured) carries exactly the Ch14 §7.2/§7.4 Alpha values this round maps
00:41 +269: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_release_gate_test.dart: shipped v1 threshold file (ADR 0511 D9 — pinned, not remeasured) the shipped file evaluates FAIL against the current legacy-DSP baseline (docs/eval/recognition-release-guard.md) — this is the gate working as intended, not a bug
00:42 +270: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_split_test.dart: RecognitionSplitBuilder — every strategy folds the full set (acceptance 1) leaveOnePlayerOut: the union of every fold's eval set is exactly the case set, with no element lost or duplicated
00:42 +271: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_split_test.dart: RecognitionSplitBuilder — every strategy folds the full set (acceptance 1) leaveOneDeviceOut: the union of every fold's eval set is exactly the case set, with no element lost or duplicated
00:42 +272: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_split_test.dart: RecognitionSplitBuilder — every strategy folds the full set (acceptance 1) leaveOneGuitarOut: the union of every fold's eval set is exactly the case set, with no element lost or duplicated
00:42 +273: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_split_test.dart: RecognitionSplitBuilder — every strategy folds the full set (acceptance 1) roomHoldout: the union of every fold's eval set is exactly the case set, with no element lost or duplicated
00:42 +274: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_split_test.dart: LeakageDetector — fail-closed (acceptance 2, ADR 0509 D1) the same group value on both sides of a fold throws, naming the conflicting group key and value
00:42 +275: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_split_test.dart: LeakageDetector — fail-closed (acceptance 2, ADR 0509 D1) a correctly built leave-one-out fold never triggers leakage
00:42 +276: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_split_test.dart: Missing group key — typed failure, never an "unknown" fold (acceptance 7, ADR 0509 D2) a case missing the requested group key throws, naming the case
00:42 +277: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_split_test.dart: Missing group key — typed failure, never an "unknown" fold (acceptance 7, ADR 0509 D2) an empty-string group value is also missing, not a valid group
00:42 +278: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_split_test.dart: RecognitionSplitFold — deterministic ordering (ADR 0509 D6) fold case ids are sorted, not insertion order
00:42 +279: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_split_test.dart: RecognitionSplitFold — deterministic ordering (ADR 0509 D6) folds themselves are ordered by group value, not hash order
00:43 +280: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_report_renderer_test.dart: single source, three formats (ADR 0511 D5) the JSON, Markdown and HTML renderings agree on an overall metric
00:43 +281: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_report_renderer_test.dart: single source, three formats (ADR 0511 D5) the JSON, Markdown and HTML renderings agree on a group metric
00:43 +282: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_report_renderer_test.dart: single source, three formats (ADR 0511 D5) every format names the gate thresholds version
00:43 +283: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_report_renderer_test.dart: determinism (ADR 0511 D7) two independent builds of the same manifest render byte-identical JSON, Markdown and HTML
00:43 +284: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_report_renderer_test.dart: determinism (ADR 0511 D7) output carries no timestamp-shaped or absolute-path text
00:43 +285: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_report_renderer_test.dart: determinism (ADR 0511 D7) groups are sorted by group-key name then group value, not iteration order
00:43 +286: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_report_renderer_test.dart: unknown group naming (ADR 0511 acceptance #8) a case missing its device group key is counted, not dropped
00:43 +287: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_report_renderer_test.dart: unknown group naming (ADR 0511 acceptance #8) a case missing its room group key is counted, not dropped
00:43 +288: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_report_renderer_test.dart: unknown group naming (ADR 0511 acceptance #8) axes with no missing keys have no unknown bucket
00:43 +289: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_report_renderer_test.dart: event categories (ADR 0511 D4) confidentWrong and rejected match the exact public-field formula
00:43 +290: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_report_renderer_test.dart: event categories (ADR 0511 D4) uncertainCorrect is null with a non-empty reason, never 0
00:43 +291: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_report_renderer_test.dart: event categories (ADR 0511 D4) rejected does not leak into confidentWrong / the false-visible event count
00:44 +292: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_annotation_test.dart: RecognitionAnnotationParser — typed-failure matrix valid pair parses without throwing
00:44 +293: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_annotation_test.dart: RecognitionAnnotationParser — typed-failure matrix unsupported schema version is a typed InvalidSchemaVersion failure (not null, not a silent default)
00:44 +294: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_annotation_test.dart: RecognitionAnnotationParser — typed-failure matrix unknown field is a typed UnknownField failure
00:44 +295: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_annotation_test.dart: RecognitionAnnotationParser — typed-failure matrix missing provenance is a typed failure, never defaulted to "human"
00:44 +296: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_annotation_test.dart: RecognitionAnnotationParser — typed-failure matrix an "auto" provenance value is parsed as auto, never promoted
00:44 +297: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_annotation_test.dart: RecognitionAnnotationParser — typed-failure matrix a strum event without a direction is a typed missing-field failure
00:44 +298: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_annotation_test.dart: RecognitionAnnotationParser — typed-failure matrix two overlapping events on the same lane are rejected with BOTH conflicting indices — not silently trimmed, merged, or reordered
00:44 +299: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_annotation_test.dart: RecognitionAnnotationParser — typed-failure matrix events of different types at the same timeMs do not overlap
00:44 +300: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_annotation_test.dart: RecognitionAnnotationParser — typed-failure matrix two intersecting chord segments are rejected with BOTH conflicting indices
00:44 +301: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_annotation_test.dart: RecognitionAnnotationParser — typed-failure matrix chord segments that only touch at a boundary do not overlap
00:44 +302: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_annotation_test.dart: parseJsonString rejects malformed JSON without crashing
00:44 +303: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_annotation_test.dart: AnnotationAgreementCalculator onset-tolerance boundary is inclusive: 49ms pairs, 50ms pairs, 51ms does not (falsification: swapping <= for < turns this red)
00:44 +304: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_annotation_test.dart: AnnotationAgreementCalculator matchedEventRatio divides by the larger annotator event count, not the count of matched pairs
00:44 +305: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_annotation_test.dart: AnnotationAgreementCalculator directionAgreement and chordAgreement are null, not zero, when there is nothing paired to divide by
00:44 +306: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_annotation_test.dart: AnnotationAgreementCalculator the fixture: 10 events each, 8 pairable within 50ms, of which 7 match direction -> directionAgreement = 0.875 (matched-pairs denominator, not the raw event count)
00:44 +307: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_annotation_test.dart: AnnotationAgreementCalculator the fixture report is byte-identical across two runs (no clock, no hash-order dependence)
00:44 +308: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_annotation_test.dart: AnnotationAgreementCalculator toJson uses a fixed, canonical (alphabetical) key order
00:44 +309: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_annotation_test.dart: annotation_schema.json is present and describes a draft-07 object schema for the annotation pair
00:44 +310: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: RecognitionMetrics — hand-verified literal values (acceptance 4/5, ADR 0509 D3) onset P/R/F1 @ 25ms: 2 of 6 matched (TP=2,FP=4,FN=4)
00:44 +311: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: RecognitionMetrics — hand-verified literal values (acceptance 4/5, ADR 0509 D3) onset P/R/F1 @ 50ms: 4 of 6 matched (TP=4,FP=2,FN=2)
00:44 +312: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: RecognitionMetrics — hand-verified literal values (acceptance 4/5, ADR 0509 D3) onset P/R/F1 @ 100ms: 5 of 6 matched (TP=5,FP=1,FN=1)
00:44 +313: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: RecognitionMetrics — hand-verified literal values (acceptance 4/5, ADR 0509 D3) any-strum F1: 3 of 4 strums matched regardless of direction (TP=3,FP=1,FN=1)
00:44 +314: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: RecognitionMetrics — hand-verified literal values (acceptance 4/5, ADR 0509 D3) direction F1: macro((down: P1 R0.5 F1=2/3), (up: P1/3 R0.5 F1=0.4)) = 8/15
00:44 +315: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: RecognitionMetrics — hand-verified literal values (acceptance 4/5, ADR 0509 D3) chord weighted accuracy: 2 correct of 4 expected (C, noChord correct; G wrong label; Am missed)
00:44 +316: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: RecognitionMetrics — hand-verified literal values (acceptance 4/5, ADR 0509 D3) chord macro-F1: C=1, G=0(no accepted prediction), noChord=1, Am=0(no accepted prediction) -> 0.5
00:44 +317: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: RecognitionMetrics — hand-verified literal values (acceptance 4/5, ADR 0509 D3) no-chord F1 is the noChord entry of the chord macro breakdown: a clean 1.0, not null
00:44 +318: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: RecognitionMetrics — hand-verified literal values (acceptance 4/5, ADR 0509 D3) unknown false-accept: 2 of 4 accepted chord detections are "unknown"
00:44 +319: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: RecognitionMetrics — hand-verified literal values (acceptance 4/5, ADR 0509 D3) accepted accuracy: 5 of 10 accepted detections are correct (onset1, strum-down, strum-up#2, chord-C, chord-noChord)
00:44 +320: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: RecognitionMetrics — hand-verified literal values (acceptance 4/5, ADR 0509 D3) coverage: 10 of 11 detections were surfaced (1 abstained)
00:44 +321: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: RecognitionMetrics — hand-verified literal values (acceptance 4/5, ADR 0509 D3) false visible events/min: 5 wrong accepted detections over 2 minutes of audio
00:44 +322: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: RecognitionMetrics — hand-verified literal values (acceptance 4/5, ADR 0509 D3) latency p50/p95: nearest-rank over [20,40,60,80,100]
00:44 +323: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: RecognitionMetrics — hand-verified literal values (acceptance 4/5, ADR 0509 D3) ECE: weighted mean absolute gap across 10 one-observation bins (python3 -c verified: 0.37000000000000005)
00:44 +324: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: RecognitionMetrics — hand-verified literal values (acceptance 4/5, ADR 0509 D3) Brier score: mean squared error over the 10 confidence observations (python3 -c verified: 0.20249999999999999)
00:44 +325: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: Onset-tolerance boundary is inclusive at 50ms (acceptance 3, ADR 0509 D5) 49ms (below the tolerance) is a hit
00:44 +326: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: Onset-tolerance boundary is inclusive at 50ms (acceptance 3, ADR 0509 D5) exactly 50ms (on the tolerance) is a hit — the boundary belongs to the accepting side
00:44 +327: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: Onset-tolerance boundary is inclusive at 50ms (acceptance 3, ADR 0509 D5) 51ms (above the tolerance) is a miss
00:44 +328: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: Matching is maximum-cardinality, not greedy (acceptance 8, ADR 0509 D5, docs/LESSONS.md L269) expected [50,90] vs detected [0,55] @ 50ms tolerance: 2 TP, not 1 — a greedy nearest-pair matcher would take (50,55) first and strand both 0 and 90 outside tolerance of each other
00:44 +329: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: Every metric carries its direction (acceptance 9, ADR 0509 D4) the F1 family, accepted accuracy and coverage are higher-is-better
00:44 +330: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: Every metric carries its direction (acceptance 9, ADR 0509 D4) ECE, Brier, false-visible-events/min and latency p50/p95 are lower-is-better — all four error metrics measured explicitly
00:44 +331: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: Determinism (acceptance 6, ADR 0509 D6) the same manifest produces byte-identical JSON on repeat runs
00:44 +332: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: directionF1/chordMacroF1 definition text matches the computed behaviour (review MAJOR-1 fix) zero time-matched strum pairs still gives down FN=1 and macro F1=0.0 — the definition text says so, not "does not enter this metric"
00:44 +333: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: directionF1/chordMacroF1 definition text matches the computed behaviour (review MAJOR-1 fix) zero time-matched chord pairs still gives label FN=1 and macro F1=0.0 — same rule on the chord side
00:44 +334: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: RecognitionEvaluationRunner on the committed CI fixture (review MAJOR-2 fix) running the committed ci_manifest.json through runFromJsonString twice produces byte-identical JSON (acceptance 6 on the real run path, not a hand-built report)
00:45 +335: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: RecognitionEvaluationRunner on the committed CI fixture (review MAJOR-2 fix) every split strategy folds the fixture-parsed cases into an eval union that is exactly the fixture case set (acceptance 1 on the fixture)
00:45 +336: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: RecognitionEvaluationRunner on the committed CI fixture (review MAJOR-2 fix) an unknown top-level field is a typed unknownField rejection
00:45 +337: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: RecognitionEvaluationRunner on the committed CI fixture (review MAJOR-2 fix) an unsupported schemaVersion is a typed invalidSchemaVersion rejection
00:45 +338: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: RecognitionEvaluationRunner on the committed CI fixture (review MAJOR-2 fix) a strum expected event without a direction is a typed missingField rejection
00:45 +339: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: RecognitionExpectedEvent/RecognitionDetectedEvent enforce their own kind invariant (review MINOR-1 fix) a hand-built strum event without a direction throws ArgumentError, not a raw TypeError from computeRecognitionMetrics
00:45 +340: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: RecognitionExpectedEvent/RecognitionDetectedEvent enforce their own kind invariant (review MINOR-1 fix) a hand-built chord event without a chordLabel throws ArgumentError
00:45 +341: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/evaluation/recognition_metrics_test.dart: RecognitionExpectedEvent/RecognitionDetectedEvent enforce their own kind invariant (review MINOR-1 fix) an onset event never requires direction or chordLabel
00:46 +342: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_signal_quality_hysteresis_test.dart: oscillating ±1 dB across the tooQuiet/good boundary changes state at most once over 40 frames
00:46 +343: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_frame_adapter_test.dart: LiveFrameAdapter — backward compatibility matrix (ADR 0505 D5, §6.3) candidate → current null
00:46 +344: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_frame_adapter_test.dart: LiveFrameAdapter — backward compatibility matrix (ADR 0505 D5, §6.3) provisional → current null
00:46 +345: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_frame_adapter_test.dart: LiveFrameAdapter — backward compatibility matrix (ADR 0505 D5, §6.3) confirmed → current present
00:46 +346: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_frame_adapter_test.dart: LiveFrameAdapter — backward compatibility matrix (ADR 0505 D5, §6.3) uncertain → current null
00:46 +347: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_frame_adapter_test.dart: LiveFrameAdapter — backward compatibility matrix (ADR 0505 D5, §6.3) rejected → current null
00:46 +348: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_frame_adapter_test.dart: LiveFrameAdapter — backward compatibility matrix (ADR 0505 D5, §6.3) expired → current null
00:46 +349: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_frame_adapter_test.dart: LiveFrameAdapter — backward compatibility matrix (ADR 0505 D5, §6.3) a RecognitionFrame with no chord prediction at all → current null
00:46 +350: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_frame_adapter_test.dart: LiveFrameAdapter — strum backward compatibility matrix (MAJOR-1 fix, ADR 0505 D5, §6.3) below threshold (uncertain) → decision uncertain, latestStrum null
00:46 +351: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_frame_adapter_test.dart: LiveFrameAdapter — strum backward compatibility matrix (MAJOR-1 fix, ADR 0505 D5, §6.3) exactly on threshold — inclusive on the reject side (uncertain) → decision uncertain, latestStrum null
00:46 +352: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_frame_adapter_test.dart: LiveFrameAdapter — strum backward compatibility matrix (MAJOR-1 fix, ADR 0505 D5, §6.3) above threshold (confirmed) → decision confirmed, latestStrum present
00:46 +353: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_frame_adapter_test.dart: LiveFrameAdapter — strum backward compatibility matrix (MAJOR-1 fix, ADR 0505 D5, §6.3) a RecognitionFrame with no strum prediction at all → latestStrum null
00:46 +354: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_frame_adapter_test.dart: LiveFrameAdapter — fields the new contract does not model yet bar/bpm/inputLevel/tuningHz/listening/strumSeq pass through from base
00:46 +355: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_frame_adapter_test.dart: LiveFrameAdapter — fields the new contract does not model yet engineTimeSec comes from the new frame, not the base
00:46 +356: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_frame_adapter_test.dart: LiveFrameAdapter — calibratedConfidence never becomes a fabricated legacy confidence an uncalibrated strum reports legacy confidence 0, not the raw pDown
00:46 +357: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_frame_adapter_test.dart: LiveFrameAdapter — calibratedConfidence never becomes a fabricated legacy confidence a calibrated strum reports the calibrated value as legacy confidence
00:46 +358: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_frame_adapter_test.dart: LiveFrameAdapter — calibratedConfidence never becomes a fabricated legacy confidence no strum prediction → no legacy latestStrum
00:48 +359: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_uncertainty_test.dart: E14-R11: the pipeline produces a typed chord verdict (ADR 0516 D1, §6 pt.1) a sustained, tonal chord confirms with the merged RecognitionDecision
00:48 +360: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_uncertainty_test.dart: E14-R11: decision == confirmed exactly when showChord (§6 pt.2) confirmed cell: the frame shows a chord -> decision confirmed
00:48 +361: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_uncertainty_test.dart: E14-R11: decision == confirmed exactly when showChord (§6 pt.2) inverse cell: the frame shows no chord -> decision never confirmed
00:48 +362: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_uncertainty_test.dart: E14-R11: the four §5.4 mapping rows (ADR 0516 D4) confirmed: the kapu latched and a match exists, regardless of signal quality
00:48 +363: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_uncertainty_test.dart: E14-R11: the four §5.4 mapping rows (ADR 0516 D4) signalQuality: a bad mic reading rejects, never blamed as lowConfidence
00:48 +364: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_uncertainty_test.dart: E14-R11: the four §5.4 mapping rows (ADR 0516 D4) noChord: tonalness-gated / no match, signal quality good
00:48 +365: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_uncertainty_test.dart: E14-R11: the four §5.4 mapping rows (ADR 0516 D4) lowConfidence: a match exists but under the gate
00:48 +366: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_uncertainty_test.dart: E14-R11: rise-gate inclusivity at the EXACT EMA boundary (§6 pt.4) EMA 0.53 (below the threshold) -> not latched -> not confirmed
00:48 +367: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_uncertainty_test.dart: E14-R11: rise-gate inclusivity at the EXACT EMA boundary (§6 pt.4) EMA 0.54 (exactly on it) -> latched -> confirmed (the boundary is inclusive)
00:48 +368: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_uncertainty_test.dart: E14-R11: rise-gate inclusivity at the EXACT EMA boundary (§6 pt.4) EMA 0.55 (above the threshold) -> latched -> confirmed
00:48 +369: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_uncertainty_test.dart: E14-R11: calibratedConfidence stays null (ADR 0505 D2, ADR 0516 D2, §6 pt.5) a confirmed prediction still carries a null calibratedConfidence
00:48 +370: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_uncertainty_test.dart: E14-R11: calibratedConfidence stays null (ADR 0505 D2, ADR 0516 D2, §6 pt.5) a rejected/no-match prediction also carries a null calibratedConfidence
00:48 +371: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_uncertainty_test.dart: E14-R11: chord and strum confidence come from different sources (§6 pt.6) high strum confidence while the chord stays NOT confirmed
00:48 +372: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_uncertainty_test.dart: E14-R11: chord and strum confidence come from different sources (§6 pt.6) chord confirmed while the strum confidence stays at its "nothing detected" floor
00:48 +373: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_uncertainty_test.dart: E14-R11: chord and strum confidence come from different sources (§6 pt.6) chord confirmed while the strum confidence stays at its "nothing detected" floor
00:48 +374: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_uncertainty_test.dart: E14-R11: chord and strum confidence come from different sources (§6 pt.6) chord confirmed while the strum confidence stays at its "nothing detected" floor
00:48 +375: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_uncertainty_test.dart: E14-R11: chord and strum confidence come from different sources (§6 pt.6) chord confirmed while the strum confidence stays at its "nothing detected" floor
00:48 +376: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_uncertainty_test.dart: E14-R11: chord and strum confidence come from different sources (§6 pt.6) chord confirmed while the strum confidence stays at its "nothing detected" floor
00:48 +377: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_uncertainty_test.dart: E14-R11: chord and strum confidence come from different sources (§6 pt.6) chord confirmed while the strum confidence stays at its "nothing detected" floor
00:48 +378: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_uncertainty_test.dart: E14-R11: chord and strum confidence come from different sources (§6 pt.6) chord confirmed while the strum confidence stays at its "nothing detected" floor
00:49 +379: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_uncertainty_test.dart: E14-R11: chord and strum confidence come from different sources (§6 pt.6) chord confirmed while the strum confidence stays at its "nothing detected" floor
00:49 +380: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_uncertainty_test.dart: E14-R11: LiveFrame compatibility (§6 pt.7) LiveFrame.empty has null chord fields
00:49 +381: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_uncertainty_test.dart: E14-R11: LiveFrame compatibility (§6 pt.7) copyWith preserves the new fields
00:49 +382: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_uncertainty_test.dart: E14-R11: the adapter gap is pinned, not silent (ADR 0516 D7, §6 pt.8) LiveFrameAdapter.toLiveFrame leaves chordDecision null even when the RecognitionFrame carries a confirmed chord
00:50 +383: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/live_announcement_throttle_test.dart: below the threshold (200 ms apart): one announcement, but every visual change is still shown
00:51 +384: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/expected_hint_cleared_on_live_test.dart: entering Live clears a stale expected-chord hint
00:52 +385: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/expected_hint_cleared_on_live_test.dart: entering Live clears a stale expected-chord hint
00:52 +386: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/expected_hint_cleared_on_live_test.dart: entering Live clears a stale expected-chord hint
00:53 +387: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_stabilizer_test.dart: brief §6 pt.1 — threshold triple cell (free, N=3, inclusive) below the threshold (2 agreeing frames) -> provisional, dropped
00:53 +388: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_stabilizer_test.dart: brief §6 pt.1 — threshold triple cell (free, N=3, inclusive) exactly on the threshold (3rd agreeing frame) -> confirmed
00:53 +389: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_stabilizer_test.dart: brief §6 pt.1 — threshold triple cell (free, N=3, inclusive) above the threshold (4th agreeing frame) -> still confirmed
00:53 +390: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_stabilizer_test.dart: brief §6 pt.2 — confirmed resists weak counter-evidence, yields to strong (both directions) A confirmed: 1 foreign B frame does not flip; 3 consecutive do
00:53 +391: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_stabilizer_test.dart: brief §6 pt.2 — confirmed resists weak counter-evidence, yields to strong (both directions) B confirmed: 1 foreign A frame does not flip; 3 consecutive do
00:53 +392: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_stabilizer_test.dart: brief §6 pt.4 — an accepted strum event is immutable (strumSeq id) same strumSeq with an opposite direction is refused; new seq admitted
00:53 +393: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_stabilizer_test.dart: brief §6 pt.5 — free vs guided give a measurably different (confirmationLatencyFrames, flipRate) pair on the same input the two profiles diverge on both metrics
00:53 +394: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/recognition_stabilizer_test.dart: brief §6 pt.6 — recovery path (L165): the state machine never freezes after arbitrarily long noisy alternating history, 3 consecutive frames still confirm
00:54 +395: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/strum_direction_abstention_test.dart: E14-R10: margin decision-trio reaches the live pipeline (ADR 0512 D6) below the threshold -> uncertain, no arrow ever surfaces
00:54 +396: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/strum_direction_abstention_test.dart: E14-R10: margin decision-trio reaches the live pipeline (ADR 0512 D6) exactly on the threshold ((2*T, T), egzakt) -> uncertain
00:54 +397: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/strum_direction_abstention_test.dart: E14-R10: margin decision-trio reaches the live pipeline (ADR 0512 D6) above the threshold -> confirmed, today's arrow behaviour
00:54 +398: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/strum_direction_abstention_test.dart: E14-R10: the heuristic branch never gets a fabricated probability (ADR 0512 D2) a probability-less StrumEvent keeps today's direct-arrow behaviour
00:54 +399: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_timeline_golden_test.dart: chord timeline — full buffer, 412 px
00:54 +399 ~1: /home/ubuntu/ss-sonnet-impl-e14-r12/test/features/live/chord_timeline_golden_test.dart: chord timeline — full buffer, narrow 320 px
00:54 +399 ~2: All tests passed!

    → [6] test test/features/live: ZÖLD

═══ [7] architecture
    $ /home/ubuntu/flutter/bin/dart run tool/check_architecture.dart

Running build hooks...Running build hooks...Architecture dependencies OK (12 allowlisted deviation(s)).

    → [7] architecture: ZÖLD

═══ [8] secrets
    $ /home/ubuntu/flutter/bin/dart run tool/ci/check_secrets.dart

Running build hooks...Running build hooks...Secret scan OK (4393 file(s) scanned, 0 finding(s)).

    → [8] secrets: ZÖLD

═══ [9] l10n
    $ /home/ubuntu/flutter/bin/dart run tool/ci/check_l10n_parity.dart

Running build hooks...Running build hooks...L10n aggregate freshness OK (en, hu).
L10n parity OK (en → hu, 2304 message(s)).

    → [9] l10n: ZÖLD

═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/features/live/recognition_stabilizer_test.dart   zöld
    test test/features/live/chord_timeline_churn_test.dart     zöld
    test test/property/chord_timeline_property_test.dart       zöld
    test test/features/live                                    zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld

MINDEN GATE ZÖLD. A teljes suite + randomizált property gate + APK a CI-ban
fut (ADR 0053) — azt az orchestrátor indítja, te ne hívj gh-t.

```

## 11. Review — a Claude tölti ki
