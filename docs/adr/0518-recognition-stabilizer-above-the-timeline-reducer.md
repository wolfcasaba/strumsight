# ADR 0518 — A felismerés-stabilizátor a MÁR MERGE-ELT keret-döntés FÖLÉ kerül: címke-stabilitás, nem második megerősítési kapu

- **Státusz:** Elfogadva
- **Kör:** `E14-R12` (Chapter 14 — Recognition Accuracy & Useful UI Recovery, Kör 12)
- **Dátum:** 2026-09-05
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Kapcsolódó:**
  [ADR 0505](0505-versioned-recognition-frame-contract-and-legacy-adapter.md)
  (a szótár: `RecognitionDecision`, `RecognitionRejectReason`, `ChordPrediction`),
  [ADR 0516](0516-live-chord-decision-wiring.md)
  (a **keret-szintű** akkord-döntés EGYETLEN helye: a `live_pipeline.dart`
  Schmitt-kapuja + tonalness + jel-minőség),
  [ADR 0512](0512-live-direction-abstention-wiring.md)
  (az irány-abstention bekötése — a `latestStrum` ma is csak `confirmed`
  esetén látszik),
  [ADR 0271](0271-recognition-recovery-program.md)
  (`UNKNOWN > CONFIDENTLY WRONG`)

## Kontextus — a pre-flight MÉRT tényei (2026-09-05, `main @ 16b101f7`)

Az előre megírt brief (2026-08-20, `main @ 88e08e65`) óta a fa elmozdult; a
`brief-lint` **S15** lelete emiatt keletkezett. A pre-flight újramérése négy
tényt talált, és mind a négy megváltoztatja a kör tartalmát.

### 1. Az akkord „provisional → confirmed" szótára MÁR MERGE-ELVE VAN

`RecognitionDecision` — `candidate`, `provisional`, `confirmed`, `uncertain`,
`rejected`, `expired`
(`lib/features/live/domain/recognition/recognition_decision.dart:5-23`). Egy
ÚJ állapot-enum ugyanerre a fogalomra **második, divergens szótár** volna —
pontosan az a hibaosztály, amit az E14-R10 H3-ja mért
([L636](../LESSONS.md#l636)), és amit az ADR 0516 az akkord-oldalon már
egyszer elhárított.

### 2. A keret-szintű akkord-megerősítésnek MÁR VAN egyetlen döntési helye

Az E14-R11 (ADR 0516, squash `ac7df497`) óta a `live_pipeline.dart`
`debugDeriveChordDecision`-je vezeti le a `RecognitionDecision`-t a
`_chordLatched` Schmitt-kapuból (`chordConfRise = 0.54`, inkluzív,
debounce-olt release), a tonalness-kapuzott match-ből és a
`SignalQualityState`-ből (`live_pipeline.dart:313-348`), és a
`_buildFrame()` ugyanezt a bitet használja a `LiveFrame.current`-hez
(`:388-407`). A `live_pipeline.dart` ennek a körnek a **tilos zónájában**
van.

Ha tehát ez a kör „N egybehangzó frame → confirmed" néven egy MÁSODIK
megerősítési kaput írna ugyanarra a kérdésre („megbízható-e ez az akkord"),
két különböző küszöb döntene ugyanarról — ez az L636/L624 hibaosztály.

### 3. A tiszta reducer szerződését a körön KÍVÜL élő teszt pinneli

`reduceChordTimeline` (`chord_timeline_provider.dart:20-66`) mai
szemantikáját a `test/property/chord_timeline_property_test.dart` méri
(randomizált property + 8 fix cella, köztük „A→A with a strum updates the
last card in place", „A→B→A gives 3 distinct cards", cap-trimmelés,
azonos-referencia-visszaadás). Ez a fájl **nincs** a kör
`allowed_paths`-án; a reducer szemantikájának átírása tehát a körön kívüli
mércét vinné pirosra → H3 (az S11/S14 hibaosztály, [L593](../LESSONS.md#l593)).

### 4. A churn valódi forrása a CÍMKE-váltás, nem a jelenlét

A mai lánc: pipeline (jelenlét + megbízhatóság eldöntve) → `LiveFrame.current`
→ `reduceChordTimeline` → **minden címkeváltás új kártya**. Egyetlen
egy-frame-es téves címke (A→B→A) így három kártyát ad. Ez egy MÁS kérdés,
mint amit az ADR 0516 eldönt: nem „van-e itt megbízható akkord", hanem
„elég stabil-e ez a MÁR megbízhatónak ítélt címke ahhoz, hogy előzménnyé
váljon".

## Döntés

### D1 — Nincs új szótár: a stabilizátor a merge-elt `RecognitionDecision`-t adja vissza

A stabilizátor állapota `candidate` (még nincs látott címke) → `provisional`
(fut az egyezés, de a küszöb alatt) → `confirmed` (a küszöbön vagy fölötte).
Új enum, új `bool`-pár vagy saját státusz-string **tilos**: a fogalom már
tipizálva van (ADR 0505 D3).

### D2 — A stabilizátor a keret-döntés FÖLÉ kerül, nem a helyére

A stabilizátor **soha** nem vezet le jelenlétet, hangosságot, tonalness-t,
jel-minőséget vagy konfidencia-küszöböt: bemenete a MÁR eldöntött keret
(`LiveFrame.current != null`, azaz az ADR 0516 kapuját megjárt akkord). Az
egyetlen, ezzel nem átfedő döntése: **hány egymást követő eldöntött kereten
egyezik a CÍMKE**. A két döntés mértékegysége is más (EMA-simított
match-konfidencia vs. egyezési sorozathossz), tehát D2 nem gyengíti és nem
duplikálja az ADR 0516 D3-at.

### D3 — A megerősítés evidencia-számláló, nem időzítő

`agreeFrames >= profile.minAgreeFrames`, **inkluzív** határ. `Future.delayed`,
`Timer`, `DateTime.now()` vagy fal-óra alapú megerősítés tilos — a mérce a
keretek száma, ami audio nélkül, determinisztikusan tesztelhető. A küszöb
tárgya az **elmozdítás** (D11).

### D4 — A profil paraméter, nem kódág

`StabilizerProfile` érték-objektum két konstans példánnyal (`free`,
`guided`), amely UGYANAZT az állapotgépet paraméterezi. Másolt `if (guided)`
ág az állapotgépen belül tilos. Mért választás nincs mögötte, ezért ez
kimondottan **tervezői** paraméter-választás, nem kalibráció:
`free.minAgreeFrames = 3`, `guided.minAgreeFrames = 5`. Indoklás: Guided
módban a felület egy előírt lecke-akkordhoz képest állít valamit, ott egy
téves felvillanás magát az utasítást mondja felül — ez a profil késleltetést
vesz stabilitásért cserébe. ~15 fps-en ez 3 keret ≈ 200 ms, 5 keret ≈ 333 ms.
A profil futásidejű **kapcsolása** (mikor melyik aktív) NEM ennek a körnek a
dolga: a `screens/**` tilos zóna, termelője ma nincs.

### D5 — A tiszta reducer szerződése bit-azonos marad; a bekötés a controllerben van

`reduceChordTimeline` szövege és szemantikája **változatlan**. A stabilizátor
a `ChordTimelineController.build()`-ban, a `liveFrameProvider` és a reducer
KÖZÉ kerül: `LiveFrame? stabilize(LiveFrame)` — a visszaadott keret mehet a
reducerbe, `null` esetén a puffer érintetlen marad. Így a churn megszűnik
(az egy-frame-es téves címke el sem jut a reducerig), miközben a körön kívül
élő property-mérce zöld marad. A `test/property/chord_timeline_property_test.dart`
ezért a kör **saját** kapujába (`gate_tests`, §7) is bekerül: a
„változatlan" állítás így gépi, nem szöveges.

### D6 — Kötelező felépülési út: a stabilizátor nem fagyhat be

Egy tartósan megváltozott akkord **mindig** megerősítődik `minAgreeFrames`
egybehangzó kereten belül, tetszőlegesen hosszú zajos előzmény után is: az
egyezés-számláló eltérésre nullázódik, és az új címke friss sorozatot indít.
Ez az [L165](../LESSONS.md#l165) hibaosztály (küszöb-alapú szűrő felépülési
út nélkül örökre befagy) explicit kizárása, saját őr-cellával.

### D7 — Az esemény immutábilis (a `strumSeq` az identitása)

Ha egy pengetés-eseményt (`LiveFrame.strumSeq`) a stabilizátor egyszer
elfogadott egy iránnyal, ugyanaz a `strumSeq` **soha** nem írhatja felül azt
egy másik iránnyal — az ilyen keret nem jut el a timeline-ig. Új esemény
kizárólag ÚJ `strumSeq`. Ez előre-védő szerződés: a mai pipeline nem termel
ilyen revíziót, tehát a cella kézzel épített keret-sorozattal mér — a
„utólagos korrekció jobb élményt ad" feloldás kifejezetten **nem
elfogadható** (brief §5.1).

### D8 — A mérőszám a kimenet része, nem logsor

A stabilizátor olvasható getterként adja ki a `confirmationLatencyFrames`
(az utolsó megerősített címke ELSŐ észlelésétől a megerősítéséig eltelt
keretek száma — tehát a zaj is beleszámít, nem csak `minAgreeFrames`) és a
`flipRate` (megerősített címkeváltások ÷ feldolgozott keretek, `0..1`)
értékeket, hogy az R09 release gate mérhesse őket.

### D9 — A stabilizátor-provider `autoDispose`

A `live_providers.dart`-ba kerülő provider `autoDispose`, hogy minden Live
látogatás friss állapotgéppel induljon, és semmilyen úton ne pinnelhesse a
`liveFrameProvider`-t (a mikrofon-elengedés mért csapdája, r185 C1 —
`test/features/live/live_mic_release_test.dart`).

### D10 — A UI-oldal nincs benne

`screens/**`, `widgets/**` és a hero-út (`live_screen.dart` →
`SsChordHero`) érintetlen: a `LiveFrame.current` (hero) továbbra is
közvetlenül a pipeline döntését mutatja. A kör kizárólag az **előzmény**
(timeline) stabilitását szállítja. A hero és a timeline így egy keretig
eltérhet — ez tudatos: a hero „most mit hallok", a timeline „mi történt".

### D11 — Cold-start kivétel: a küszöb az ELMOZDÍTÁST kapuzza, nem a legelső észlelést

*(Kiegészítés a kör implementációja során, 2026-09-05 — az ADR ennek a körnek
a MÉG NEM merge-elt saját artefaktuma, a kiegészítés az orchestrátor
hatásköre; ADR 0087 §2.)*

A legelső valaha látott, MÁR eldöntött címkének **nincs mihez képest egyet
nem értenie**: a timeline üres, nincs megállapított alapállapot, tehát nincs
mit elmozdítani. Ezért:

- az első valaha látott eldöntött címke **ránézésre megerősül** (a keret
  átmegy, `chordState = confirmed`), és
- **kizárólag** egy MÁR megerősített címke **elmozdítása** (átállás egy ÚJ,
  ELTÉRŐ címkére) igényli a `profile.minAgreeFrames` egybehangzó keretet.

Ez a kivétel **példányonként pontosan egyszer** tüzel (a `_confirmedLabel`
soha nem áll vissza `null`-ra), és a `chordState` `candidate` állapota
továbbra is a „még egyetlen eldöntött keret sem érkezett" állapot (D1).

**MÉRT indok (a reviewer által függetlenül reprodukálva).** A kivétel nélküli
változat — minden címke, az első is, `minAgreeFrames` keretet kér — a kör
`allowed_paths`-án KÍVÜL eső **három** meglévő cellát visz pirosra, mert azok
egyetlen keretet emittálnak és azonnali timeline-visszajelzést várnak:

```
flutter test test/features/live/live_screen_test.dart test/features/live/live_stage_test.dart
  ✗ live_screen_test.dart: Live renders the current chord + its strum on the timeline hero
  ✗ live_stage_test.dart:  A1 — DSP output reaches the UI unaltered by the migration
  ✗ live_stage_test.dart:  A2 — weak signal … chord held → mic warning
```

(Reprodukció: a `50dcca56` klónjában a `_confirmedLabel == null` ág törlése,
majd a fenti parancs → `+13 -3`.) A listán kívüli teszt átírása H3 volna, a
kivétel viszont a kör saját fájljain belül marad, és a churn-mércét nem
gyengíti: a §7.1 falszifikációs cella `minAgreeFrames = 1`-nél továbbra is
PIROS.

**Ár, kimondva:** a Live megnyitása utáni ELSŐ előzmény-kártya nulla
stabilitás-evidenciával jelenik meg. Ezt a keretet a pipeline saját kapuja
(Schmitt-trigger `chordConfRise = 0.54`, debounce-olt release + tonalness +
jel-minőség, ADR 0516) már megszűrte, tehát nem szűretlen nyers címke — de
egy téves első felismerés egy (és pontosan egy) fölösleges kártyát adhat.

**Gépi mérce (kötelező):** a kivételt saját cella pinneli — kezdeti
`candidate` állapot; az első eldöntött címke ránézésre `confirmed`; a
MÁSODIK, ELTÉRŐ címke viszont a teljes `minAgreeFrames`-t kéri. Szöveges
előírás gépi mérce nélkül ebben a körben nem elfogadható.

## Következmények

**Pozitív.** A timeline-churn a kör után gépileg mérve megszűnik; a
megerősítés determinisztikus, audio nélkül tesztelhető; a mérőszámok
kimenetek, tehát a release gate bekötheti őket; sem új szótár, sem második
megerősítési küszöb nem keletkezik.

**Ár.** Az előzmény-kártya `minAgreeFrames − 1` kerettel (≈133 ms Free,
≈267 ms Guided, 15 fps) később jelenik meg, mint ma. A §10 handoff ezt
számszerűen jelenti.

**Tiltott.** Új döntési enum; a `live_pipeline.dart` küszöbeinek
újraimplementálása vagy megkerülése; időzítő-alapú megerősítés; a
`reduceChordTimeline` szemantikájának átírása; a profil második kódágként
való megvalósítása; egy elfogadott pengetés-esemény irányának felülírása;
UI/layout-változtatás.
