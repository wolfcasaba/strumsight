# ADR 0561 — A rács forrása a `RhythmGrid`, és az elolvasása KÉT hibát talált a metrikus csatornában

- **Státusz:** elfogadva (javítás; a szállított viselkedés **nem változik**, a csatorna
  továbbra sincs bekötve)
- **Dátum:** 2026-09-12
- **Kör:** E18-R38
- **Kapcsolódó:** ADR 0557 (a metrikus csatorna), ADR 0560 (a rácsnak az app birtokában
  kell lennie), `lib/features/curriculum/domain/rhythm_grid.dart`,
  `docs/research/strumming-direction-pedagogy-2026-09.md`, `docs/LESSONS.md` L676

## Kontextus

Az ADR 0560 kimondta: a csatorna csak olyan rácson admisszibilis, aminek a fázisát **az app
birtokolja**. Ennek a rácsnak a keresése közben elolvastam a `RhythmGrid`-et — és kiderült,
hogy a repó **már tartalmazza** mindazt, amit a metrikus csatornához kitaláltam, jobban:

- **`RhythmGrid.pendulumDirection`** — az inga-deriváció, ugyanazokra a pedagógiai
  forrásokra hivatkozva, amikre az ADR 0557 épül;
- **`beatsPerBar`, `subdivision`** (negyed/nyolcad), és **authored** rács azoknak a
  mintáknak, amik legitimen **elhagyják** az ingát (a tanított 3/4 oom-pah);
- **`StrokeSound.ghost`** — egy rés, ahol a kéz **utazik, de nem üt**;
- **`onsetUs({bar, slotIndex, bpm})`** — **ismert fázisú absztrakt időrács** a gyakorlat
  kezdetétől. Pontosan az, amit az ADR 0560 megkíván.

## Döntés

### D1 — A `RhythmGrid` az inga EGYETLEN hatósága; a csatorna nem derivál újra

A `StrumMetricChannel` készen kapott irányú `MetricSlot`-okat vesz át, hogy ne legyen
**második implementáció** ugyanarra a szabályra, ami elsodródhat az elsőtől. A
`features/live/engine/dsp` **nem importálja** a curriculumot (a könyvtár minden más fájlja is
függőségmentes); a leképezést a `StrumMetricChannel.crossings` nevű gyár végzi primitívekből,
amit a konfigurációs hely hív a `RhythmGrid`-del.

### D2 — HIBA 1: egy ghost-rés HORDOZ irányt; a „nincs véleménye" téves volt

A csatorna első verziója a minta `null` rését „nincs véleménye"-ként kezelte. Ez
**pedagógiailag téves**, és a repó saját dokumentációja mondja ki: a pengető kéz **inga, és
nem áll meg**, tehát egy csendben hagyott kereszteződésen **valódi kéz-utazás** történik,
valódi iránnyal — csak nincs mit hallani. Ha a tanuló **mégis** odaüt, az ingának **van**
jóslata az irányára.

Ezért a `MetricSlot` **két** dolgot hordoz: `direction` (mindig ismert) és `expected` (kér-e
a minta hangot ott). A `MetricCall.expectedHere == false` tehát nem kétely az irányban, hanem
**minta-sértés** — az ütem utáni áttekintés leletе (ADR 0556 D4).

### D3 — HIBA 2: egy NEGYED rácsot KERESZTEZŐDÉS-felbontáson kell olvasni, különben minden off-beat ütés átfordul

Egy negyed rács **négy** lefelé ütést jelöl. A kéz mégis **felfelé** jön vissza közöttük — a
`RhythmGrid.handCrossings` pontosan ezért létezik, és a dokumentációja ki is mondja a
különbséget: *„amit KÉRNEK (a rések) versus amit a kéz TESZ"*. A metrikus csatorna arról
szól, **amit a kéz tesz**.

Rés-felbontáson olvasva egy két ütem közti ütés a legközelebbi negyedre esne, és **„lefelé"**
lenne a válasz, miközben a kéz **felfelé** tart — **magabiztos inverzió** pontosan azokon az
off-beat ütéseken, amiket egy tanuló akkor ad hozzá, amikor kezdi kitölteni a mintát.

A `StrumMetricChannel.crossings` ezért a negyed rácsot **nyolc kereszteződésre** tágítja, a
visszautakat ghost-ként. Teszt pinnel mindkét felét: hogy a tágítás egyezik a
`RhythmGrid.handCrossings`-szel, és hogy a **nem tágított** olvasat ugyanazon az ütésen
**„lefelé"**-t ad — a számokban kiírva, mi ellen védünk.

### D4 — Az AUTHORED rács iránya érvényben marad

A tanított 3/4 oom-pah (basszus **le** az egyesen, könnyű akkordok **fel** a kettőn-hármon)
`followsPendulum == false`, és a csatorna **nem javítja ki**. Egy modell, ami ezt hibásnak
mondaná, **hamisat tanítana egy mintáról, amit valódi tanárok tanítanak**. Teszt pinnel.

## Következmények

- A **mérés nem változik.** A GuitarSet implikált mintája szigorú tizenhatod-alternáció,
  **ghost-kereszteződés nélkül**, tehát a `slot_call` válasza sosem függött a ghost-szemantikától;
  a 0,9797 és a fúziós táblák érvényben maradnak.
- A **paritás-fixtúra újragenerálva** (180 eset), és most `expectedHere`-t is hordoz, plusz a
  kitágított negyed rácsot és a 3/4-es authored oom-pah-t.
- A bekötés következő lépése konkretizálódott: a `RhythmGrid.onsetUs` adja a bar-horgonyt, a
  `crossings` gyár a mintát.

## Amit NEM állítunk

- **A negyed-inverziót nem mértük korpuszon** — geometriai tény, tesztben kiírva. Hogy a
  gyakorlatban hány ütést érint, az a tanuló mintájától függ.
- A csatorna **továbbra sincs bekötve**, és szabad játékban az ADR 0560 szerint nem is lesz.
