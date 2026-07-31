# ADR 0075 — Determinisztikus egy-az-egyhez event matcher a practice motorban

- **Státusz:** Elfogadva (2026-07-31)
- **Kör:** E02-R09 (SDD `docs/sdd/03-epic-02-practice-engine.md`, „Kör 9")
- **Kapcsolódó:** [ADR 0072](0072-practice-target-compiler.md) (compiled target),
  [ADR 0073](0073-practice-session-clock.md) (session clock + state machine),
  [ADR 0074](0074-practice-observation-gateway.md) (observation gateway)

## Kontextus

A `CompiledPracticeTarget` (R06) determinisztikus idővonalat ad, az observation
gateway (R08) `PracticeObservation`-öket szállít. Hiányzik a kettőt összekötő
lépés: **melyik megfigyelés melyik célesemény**. Ma ezt a döntést a legacy
`LessonScorer` (`lib/features/learn/lesson_scorer.dart`) hozza meg, összegyúrva
a pontozással, a comboval, az akkord-értékeléssel és a UI-állapottal — egy
343 soros, mutábilis osztályban, ami `double` másodperceken dolgozik.

A legacy párosítás viselkedése **felhasználó-látható**: ez dönti el, mi számít
találatnak, mi eltévesztett iránynak és mi kimaradásnak. Ezt a viselkedést a V2
úton **bitre meg kell őrizni**, különben a migráció csendben átértékeli a
felhasználók eddigi teljesítményét.

Két további kényszer:

1. **Skálázás.** A legacy minden pengetésnél végigpásztázza az ÖSSZES eseményt
   (`for (final t in _events)`). Egy 16 bar × 8 esemény leckénél ez elfér, de a
   dal-hosszú és loopolt targetnél már nem — az SDD elfogadási feltétele
   kifejezetten kimondja: „nagy targetnél cursor-alapú vagy indexelt működés;
   nincs full list scan minden frame-en".
2. **Kompozíció.** A Kör 10 három külön scorert (timing, direction, chord) épít
   erre. A párosításnak ezért **önmagában** használhatónak és pontozás-mentesnek
   kell lennie.

## Döntés

Bevezetünk egy **pure, determinisztikus, egy-az-egyhez** event matchert:
`lib/features/practice/domain/service/practice_event_matcher.dart`.

### 1. Felelősségi határ

A matcher **kizárólag párosít és lezár**. Előállítja céleseményenként azt, hogy
mi párosult hozzá, mikor, és mekkora **előjeles időeltéréssel**. **Nem** ad
`TimingGrade`-et, **nem** számol pontot, combót és akkord-helyességet — azok a
Kör 10 scorereié. Az `ExtraStrumPolicy`-t **nem alkalmazza**: az extra
pengetéseket megszámolja (információ), de sosem büntet.

`ChordObservation` **nincs a hatókörben** — az akkord-idővonal értékelése a Kör
10 chord scoreréé. A matcher bemenete a `StrumObservation`.

### 2. Megőrzött legacy szemantika (a párosítás igazsága)

A `ScoringProfile.legacyLearnParity` mellett a matcher a `LessonScorer`
párosításával **mikroszekundumra egyező** eredményt ad:

| # | Szabály | Legacy forrás |
|---|---|---|
| P1 | A megfigyelés ideje `played = at − inputLatency`; minden összehasonlítás ezen megy | `registerStrum`, `advance` |
| P2 | Jogosult célesemény: nyitott, és `\|target.time − played\| ≤ matchWindow` | `d <= windowSec` |
| P3 | A jogosultak közül a **legkisebb abszolút eltérésű** nyer | `d < bestDelta` |
| P4 | Egyenlő eltérésnél a **korábbi** célesemény nyer (azonos időnél a kisebb index) | szigorú `<` növekvő sorrendű listán |
| P5 | A párosított célesemény **akkor is elfogy**, ha az irány rossz | `best.matched = true` az irány-ág ELŐTT |
| P6 | Jogosult célesemény nélküli pengetés: **állapotot nem változtat**, extraként számolódik | `return null` |
| P7 | Egy célesemény akkor lesz kimaradás, ha `target.time + matchWindow < played` — **szigorú `<`** | `advance` |
| P8 | Lezárt célesemény soha nem nyílik újra, és kétszer nem párosul | `if (t.matched) continue` |
| P9 | Lezáráskor minden még nyitott kötelező célesemény kimaradás | `finalize()` |

**A P2 és a P7 operátora szándékosan különbözik.** Pontosan
`played = target.time + matchWindow` esetén a célesemény **még nyitott ÉS még
jogosult** — az utolsó mikroszekundumban párosítható. Egy „egységesítsük a két
predikátumot" refaktor ezt a cellát csendben elveszi.

### 3. Új viselkedés a legacyn túl

- **Opcionális célesemény** (`CompiledTargetEvent.optional`): párosítható, de
  ha nyitva marad, **nem kimaradás** — külön feloldásként zárul. A legacynak
  nincs megfelelője, ezért nem is sérthet paritást.
- **Sorrend-tolerancia.** A lezáró óra monoton: visszafelé léptetés nincs
  hatással. Az időben visszafelé érkező megfigyelés nem okoz hibát és nem nyit
  újra célt — ha már minden szóba jövő cél lezárt, extraként számolódik.
  **Sorrendben érkező bemenetre a viselkedés bitre a legacy.**

### 4. Skálázás és memória

- A matcher **kurzoralapú**: a nyitott célesemények egy növekvő indexű ablakban
  élnek, a kurzor alatti célok mind lezártak. Mivel a compiled event-lista idő
  szerint rendezett, ez **egyenértékű** a teljes pásztázással, csak nem lineáris
  a target-hosszban.
- A matcher **nem tárol megfigyeléseket**: az állapota `O(célesemény)`, nem
  `O(megfigyelés)`.
- Mindkettő **mért**, nem ígért: a matcher `@visibleForTesting` számlálót ad a
  megvizsgált célesemények számáról és a megtartott rekordokról. Egy full-scan
  implementáció és egy megfigyelés-halmozó implementáció is pirosra fut.

## Következmények

**Pozitív:** a párosítás igazsága egyetlen, tesztelhető, pontozás-mentes helyre
kerül; a Kör 10 három scorere ugyanarra a párosításra épülhet; a legacy
viselkedés paritás-teszttel őrzött, nem emlékezetből átírt.

**Negatív / ár:** a legacy `LessonScorer` egy ideig párhuzamosan él a matcherrel
(két igazságforrás a migrációs kör lezárásáig, E02-R11); a `@visibleForTesting`
számlálók a production API-n ülnek, cserébe a skálázási előírás mérhető.

**Nem érinti:** a DSP-t, a legacy Learn utat, a UI-t. Hívó ebben a körben nincs,
a practice flagek OFF-ban maradnak, a production viselkedés változatlan.
