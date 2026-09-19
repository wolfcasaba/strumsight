# ADR 0545 — Nincs váltás-időzítés pontszám: a motor késése nem kivonható

- **Státusz:** elfogadva (NEMLEGES döntés)
- **Dátum:** 2026-09-12
- **Kör:** E18-R16
- **Kapcsolódó:** ADR 0544 (az akkord-pillér), `docs/LESSONS.md` L657,
  `docs/superpowers/specs/2026-09-11-gamified-curriculum-design.md` §2

## Kontextus

Az ADR 0544 kimondta, hogy az akkord-osztályozás a taktust méri, és **nem** azt,
hogy a váltás a taktusvonalra esett-e. A következő kör kézenfekvő tárgya ez a
pontszám volt: „a váltásod N ms-mal késett". A `mission.emToAm` tanítása épp ez, a
felhasználói érték világos, és a kód oldala egyszerű — a taktusvonal és az első
megerősítés közti idő.

Egy dolgot azonban nem tudtunk: **mennyi ebből a motor sajátja.** Egy akkord-döntésnek
— ellentétben egy pengetéssel — nincs mért valódi onsetje, amihez vissza lehetne
korrigálni; a pengetés-út épp ezért hordoz kalibrációt (`strum_latency_provider`).
Egy kalibráció nélkül közölt szám a tanuló késése ÉS a dekóder konfirmálási
latenciája összege lenne, a tanuló nevén — pontosan az a hamis állítás, amit a
design §2 tilt („ne a játékost hibáztasd a jelért").

## A mérés

`test/features/live/chord_change_latency_test.dart`. A stimulus a szállított
`ChordShapes` ujjrendekből fizikailag modellezett (Karplus-Strong), a váltás
pillanata **konstrukcióból ismert**, és az előző akkord nem vágódik el — egy valódi
játékos előző alakzata sem áll meg hirtelen.

```
Em -> Am: a váltást 508 ms alatt követte
Am -> D : 1344 ms
D  -> G : 159 ms
G  -> C : 438 ms

FOLLOW LATENCY: median 508 ms, range 159-1344 ms (4/4 váltás követve)
CONSISTENCY:    mean 612 ms, legnagyobb eltérés 731 ms
ÁTFEDÉS:        az előző alakzat a váltás után 90-368 ms-mal szűnik meg
                megerősített lenni
```

A kurzus 70 bpm-jén egy ütés **857 ms**. A motor saját késése tehát átlagosan
**~0,7 ütés**, és **~0,85 ütésnyit szór** — tiszta modellezett audión, pillanatnyi,
tökéletesen lefogott váltásokkal. Egy valódi kezdő keze ennél lassabban és
egyenetlenebbül érkezik meg.

## Döntés

### D1 — Az app NEM pontozza a váltás időzítését

Egy **szisztematikus** késés kivonható: pontosan ezt teszi a pengetés-kalibráció a
készülék latenciájával, és a `LatencyCalibrator` `isStable` mezője az, ami megtagadja
a mentést, ha a futás nem elég egyenletes. Egy **731 ms-ot szóró** késés nem
kivonható: amit a tanulónak mutatnánk, az túlnyomórészt dekóder-zaj lenne az ő nevén.

A következtetés nem „pontatlan", hanem **lehetetlen**. Mediánt közölni egy ennyire
szóró mennyiségről pontosságot állítana ott, ahol nincs.

A `chord_grading.dart` doksija ezért a mérést és a következtetést hordozza, nem egy
„későbbre hagyva" jegyzetet: aki legközelebb ránéz, a számot látja, nem a hiányt.

### D2 — A mérés IGAZOLJA a taktust mint egységet

Az ADR 0544 D1 érv volt („egy akkord tartott, a dekódernek több képkocka kell").
Most mérés: a legrosszabb eset a 3,43 s-os taktus **39 %-a**, és az előző alakzat a
váltás után 90–368 ms-mal szűnik meg megerősített lenni. A taktus-szintű crediting
tehát kényelmes, miközben a pengetés-szintű a dekódert mérte volna.

### D3 — Új, MÉRT korlát: `minimumChordBarUs` = 2,0 s

≈1,5× a mért legrosszabb eset (1344 ms). A `RhythmAssignment` konstruktora
kényszeríti ki: egy akkord-pontozó gyakorlat, aminek a taktusa ennél rövidebb, nem
hozható létre. A szállított rungok kényelmesen felette vannak (3,43 s 70 bpm-en,
3,0 s 80-on), tehát ma semmit nem szorít — azért létezik, hogy egy jövőbeli
gyorsabb tempó vagy rövidebb metrum **hangosan** bukjon el a létrehozásnál, ahelyett
hogy a taktus lejárna, mielőtt a motor követte volna a váltást, és a taktus az
ELŐZŐ akkordként osztályozódna. Az a hiba az „idejében váltottál, mégis rosszat
játszottál" állítást adná.

## Mi nyitná ezt újra

Nem a kívánság, hanem egy mérés. Ha a dekóder konfirmálási késése
szisztematikussá válik — például a felismerés-stabilizátor ablakának vagy
hiszterézisének megváltoztatásával —, a szórás újramérhető, és ha elég kicsi, a
kivonás ugyanúgy elvégezhető, ahogy a pengetés-útnál. Addig a válasz az, hogy ezt
nem mérjük, és ezt ki is mondjuk.

## Következmények

- Egy harmadik Karplus-Strong példány helyett `test/support/modelled_guitar.dart` a
  közös definíció; a modellezett akkord-felismerés mérése most ezt használja, és a
  táblája **digitre** reprodukálódott (34/43, 36/43, 30/43…). Ez egyben megmutatta,
  hogy a korábbi „confirmed" képkocka-számolás nem mért mást: a `current` csak
  megerősítés után publikálódik.
- A design §2 „amit nem mérünk, azt kimondja" szabálya most egy **funkció** szintjén
  is alkalmazva van, nem csak egy kijelzett számon: a hiányzó váltás-időzítés nem
  elfelejtett TODO, hanem dokumentált, mért elutasítás.
