# ADR 0560 — A metrikus csatorna csak olyan rácson működik, amit az APP BIRTOKOL: a pipeline önhorgonyzott ütemével mérve ROSSZABB, mint a „mindig lefelé"

- **Státusz:** elfogadva (negatív mérés; **megállítja** a tervezett bekötést)
- **Dátum:** 2026-09-12
- **Kör:** E18-R37
- **Kapcsolódó:** ADR 0557 (a metrikus csatorna), ADR 0558 (a fúziós szabály), ADR 0559
  (a letisztult tier), `docs/LESSONS.md` L667 (a hiányzó többségi alapvonal), L675,
  `ml/probe_metric_grid_sensitivity.py`

## Kontextus

Az előző kör végén a következő lépést így mondtam ki: „a `TempoTracker` rácsa + a
bar-horgony átadása a `StrumMetricChannel`-nek". Bekötés előtt megnéztem, **mi is az a
rács** — és kiderült, hogy nem rács.

- **`TempoTracker.bpm`**: medián-IOI becslés, EMA-simítva, és **ismételt
  duplázással/felezéssel 60–200-ra hajtogatva** — vagyis az **oktávja kifejezetten
  kétértelmű**, fázist pedig egyáltalán nem ad.
- **`_barStartSec`**: a `_placeInBar` ahhoz az **önkényes ütéshez** horgonyozza, ami épp
  túllépte az előző ütemet (`_barStartSec = event.timeSec`), és kb. ütemenként újraválasztja.

A csatorna állítása az, hogy **a pozíció dönti el az irányt**. Egy fél réssel elhibázott
origó ezért nem elmossa a választ, hanem **megfordítja** — a lehető legrosszabb hiba-alak:
magabiztos és téves.

## Mérés (`ml/probe_metric_grid_sensitivity.py`, tartalék GuitarSet: ismeretlen játékos ÉS dal)

526 ütés, 12 felvétel, felütés-arány 0,1920 — tehát a **„MINDIG LEFELÉ" alapvonal 0,8080**,
és ez az a szám, amit meg kell verni (L667).

```
  rács                                                pontosság   vs annotált
  annotált (ADR 0557: helyes tempó ÉS origó)            0,9848        --

  1  ORIGÓ önkényes ütésből, helyes tempó
     egy horgony/felvétel, seed 0                       0,7300      -0,2548
     egy horgony/felvétel, seed 1                       0,9430      -0,0418
     egy horgony/felvétel, seed 2                       0,8555      -0,1293
     egy horgony/felvétel, seed 3                       0,7833      -0,2015
     egy horgony/felvétel, seed 4                       0,9468      -0,0380
     ütemenként újrahorgonyozva (_placeInBar)           0,8612      -0,1236

  2  TEMPÓ oktávot hibázik, helyes origó
     ×2 (felezett olvasat)                              0,6597      -0,3251
     ÷2 (duplázott olvasat)                             0,7985      -0,1863

  3  a becsületes szabad-játék eset: mindkettő téves
     újrahorgonyozva + tempó ×2                         0,6179      -0,3669
     újrahorgonyozva + tempó ÷2                         0,7662      -0,2186
```

**A „mindig lefelé" 0,8080-hoz mérve:**

- Önhorgonyzott, helyes tempóval: 0,8612 — csak **+0,053**, és seedenként 0,73–0,95 között
  szór: **öt horgonyból három ROSSZABB**, mint a konstans.
- Rossz tempó-oktáv: 0,6597 / 0,7985 — **mindkettő rosszabb** a konstansnál.
- Mindkettő téves: 0,6179 / 0,7662 — **mindkettő rosszabb** a konstansnál.

A szórás oka mechanikus, nem zaj: a horgony-ütés **81,2%-ban lefelé, 18,8%-ban felfelé**
lenne, és egy **felfelé** horgony egy réssel csúsztatja a rácsot, ami szigorú alternáción
**minden hívást átfordít**. Az önhorgonyzott sorok tehát **majdnem tökéletes és majdnem
invertált felvételek keveréke**, nem egyenletesen romlott jel. Egy átlag itt elrejti, hogy
a tanuló fele **fordítva** kapná a visszajelzést.

## Döntés

### D1 — A pipeline NEM adhatja át a `TempoTracker` bpm-jét és a `_barStartSec`-et

Ez a tervezett következő lépés volt, és **elvetem**. Egy gyártott rács mérve **rosszabb,
mint nem adni csatornát** — és közben magabiztos. Az ADR 0557 D4 tiltása („a metrikus
csatorna egyedül soha nem dönt") nem ment meg ettől: a fúzió a gyors tieren a rácsra
támaszkodna, és a rács lenne rossz.

### D2 — A csatorna csak olyan rácson admisszibilis, amit az APP BIRTOKOL

Egyetlen legitim origó-forrás van: **a metronóm / lecke saját időrácsa**, amit az app maga
állít elő, tehát a fázisa **definíció szerint ismert**. Ez a `features/curriculum` és a
`features/learn` rétegben él (`metronome_pulse.dart`, a count-in és az ütem-számlálás), és
**ma nem jut el a DSP pipeline-ig**. A bekötés tehát **réteg-átívelő** munka: a rácsot
kívülről kell beadni, nem a jelből megbecsülni.

### D3 — Szabad játékban a csatorna NEM ELÉRHETŐ, és ez már így is van megépítve

A `StrumMetricChannel` `bpm <= 0`-ra `MetricCall.unavailable`-t ad, és ez a három állapot
közül az egyik **elsőrangú** állapot, nem hibajelzés (ADR 0557, E18-R35). A pipeline tehát
szabad játékban **ne adjon tempót** a csatornának. Tiszta képesség-határ: a rendszer a
csak-akusztikus útra esik vissza, amit az ADR 0558 C szabálya leír.

### D4 — És egy új kockázat, amit ez a kör talált: a metronóm-klikk ÖNMAGÁT hitelesítené

A repó már megmérte (`metronome_click_pollution_test.dart`): **16 klikkből 15 jelentett
ütés** lesz, minden szinten 0,1 erősítésig. A klikk **pontosan az ütemre** esik — vagyis
pontosan oda, ahová a rács lefelé ütést vár. A metrikus csatorna tehát a klikket
**magabiztos lefelé ütésként bélyegezné le**, és a fúzió a fantom ütést **még
magabiztosabbá** tenné.

A meglévő mérséklés a helyes: a pontozás alatt a pulzus **haptikus**, nem hallható
(`CurriculumPulse.haptic`). Ez a kölcsönhatás innentől **dokumentált kényszer**: a metrikus
csatornát **nem** szabad engedélyezni hallható klikk mellett, mert a két mechanizmus
egymás hibáját erősíti.

## Következmények

- A bekötés sorrendje megváltozik: **(1)** a curriculum rácsának átadása a DSP-ig (réteg-
  átívelő, a rács **ismert fázisú**), **(2)** a D1 fúzió a pontozó úton, **(3)** a nyíl
  funkció-kapu mögött. A „TempoTracker-rács" lépés **törölve**.
- A `StrumMetricChannel` **nem változik** — a három állapota pont ezt az esetet modellezte.
- A Learn/practice út lesz az első, ahol a csatorna él; a szabad Live **marad
  csak-akusztikus**, és ezt ki kell írni a termék-dokumentációba is, nem csak ide.

## Amit NEM állítunk

- **Nem azt mértük, hogy egy beat-tracker nem tudna elég jó rácsot adni.** Azt mértük, hogy
  **a jelenlegi `TempoTracker` és `_placeInBar`** nem. Egy valódi beat-tracker (ismert fázis,
  oktáv-eldöntés) külön kérdés és külön mérés.
- A 0,8080-as „mindig lefelé" alapvonal **ennek a korpusznak** az osztályaránya; egy
  felütés-domináns anyagon (reggae-skank) a konstans alapvonal más, és a csatorna értéke is.
- A klikk-kölcsönhatás **nem mérve** a metrikus csatornával — a 15/16 onset-szám a repó
  korábbi mérése. Hogy a fúzió pontosan mennyit ront egy hallható klikken, az külön mérés.
