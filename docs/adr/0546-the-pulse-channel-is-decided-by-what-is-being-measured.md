# ADR 0546 — A metronóm csatornáját az dönti el, MIT mérünk abban a pillanatban

- **Státusz:** elfogadva
- **Dátum:** 2026-09-12
- **Kör:** E18-R17
- **Kapcsolódó:** ADR 0544 (akkord-pillér), ADR 0545 (a nemleges váltás-időzítés),
  `docs/LESSONS.md` L658, RAG chunk 014 (a metronóm),
  `docs/superpowers/specs/2026-09-11-gamified-curriculum-design.md` §2, §3

## Kontextus

A négy ritmus-mód közül három `needsMetronome: true`-t deklarál, az app szállít
metronómot (`lib/features/learn/audio/metronome.dart`, tiszta Dartban szintetizált
klikk, saját némítás-preferenciával), a `pubspec.yaml` sora szó szerint „metronome
click" — a tananyag ritmus-képernyője mégis **néma**: a tanuló egy animációból tartja
a tempót, miközben pengetni próbál. Deklarált igény, semmi mögötte; ugyanaz a
hibaosztály, mint a dal-rung pontszám-ígérete (ADR 0544 D5).

A bekötés egysoros csatlakozásnak látszik. Nem az, mert a klikk **ugyanabba a
szobába szól, amit a mikrofon pontoz.**

## A mérés

`test/features/live/metronome_click_pollution_test.dart`. A stimulus a **szállított**
klikk — `Metronome.buildClickWav`, ugyanaz a tiszta függvény, amit az app lejátszik —,
modellezett gitárra keverve, több szinten.

**Két előre megnevezett kockázat volt, és a mérés a MÁSIKAT igazolta.**

### 1. Kromapollúció — megjósoltam, és a mérés megdöntötte

A klikk 1000 Hz-es szinusz, és 1000 Hz ≈ **B5** (987,77 Hz). A B az **E-moll**
(E-G-B) ÉS a **G** (G-B-D) akkord hangja — a kurzus első és negyedik akkordja. Az
akcentus 1600 Hz ≈ G6 (1568), a G pedig az Em, G és C hangja. Tehát a klikk nem
ártalmatlanul a zenén kívül szól: épp azokra a hangmagasságokra esik, amiket a
dekóder mérlegel.

Mérve: az akkord **azonossága egyetlen szinten sem változott** (Em → Em, G → G,
Am → Am), a megerősített képkockák száma legfeljebb 1-gyel mozdult ~200-ból, és a
**csak klikkek egyáltalán nem neveznek akkordot** — teljes skálán sem, 0 megerősített
képkockával. A hipotézis elfogadható volt és **téves**.

### 2. Hamis onsetek — nem jósoltam meg eléggé súlyosnak, és ez a döntő

```
csak klikkek, gain 0.10: 15 jelentett pengetés
csak klikkek, gain 0.30: 15 jelentett pengetés
csak klikkek, gain 1.00: 15 jelentett pengetés
```

**16 klikkből 15 pengetés**, gitár nélkül, minden tesztelt szinten. És a klikk
pontosan az ütésre esik — pontosan oda, ahol a rács pengetést vár. Tehát egy tanuló,
aki **semmit nem játszik**, egy teli, tökéletesen időzített körrel lenne kreditálva.

## Döntés

### D1 — A csatornát a fázis dönti el, nem egy beállítás

`curriculumPulseFor({phase, isDownbeat, muted})`, tiszta függvény
(`metronome_pulse.dart`):

| Fázis | Csatorna | Miért |
|---|---|---|
| **beszámolás** | hallható klikk, az 1. ütésen akcentussal | Itt semmi nincs pontozva (`countsTowardAttempt` minden bar 1 előtti pengetést eldob), és minden metronóm-módszer ide teszi a pulzust: előbb legyen ütés, aztán legyen mit rá játszani. |
| **pontozott kör** | haptikus pulzus, NÉMA | Érezhető, és a mikrofon nem hallja. A hallható klikk kreditálva lenne pengetésként pont azon az ütésen, amit jelöl. |
| **kalibráció** | SEMMI | Két ok, és külön-külön is elég: a kalibrátor a `latestStrumTime`-ból regisztrál koppintást, és a fenti mérés szerint a klikk épp ilyet termel — egy hallható pulzus tehát **a saját metronómjára kalibrálná a készüléket**. És bármilyen pulzus mást ad követni, mint az inga, miközben pont az inga az, amihez kalibrálunk. |

A kalibráció **felülírja** a beszámolást: egy kalibrációs futás is beszámol, és egy
klikk ott koppintásként regisztrálódna.

### D2 — A döntés tiszta funkció, nem widget-logika

Azért, mert a legnagyobb súlyú eset — a kalibráció alatti csend — az, amit egy
widget-teszt a legnehezebben ér el, és az, aminek a hibája a legcsendesebben rontaná
el a kalibrációt. A `metronome_pulse_test.dart` kimerítően állítja a táblát: minden
fázis × akcentus × némítás.

### D3 — Egy kapcsoló mindkét csatornára

A meglévő `metronomeMutedProvider` **mindkettőt** elhallgattatja. Aki kikapcsolja a
metronómot, nem akar pulzust; egy második preferencia egy olyan csatornára, amit nem
tud összehasonlítani, olyan beállítás lenne, amire senki nem tud válaszolni.

### D4 — A tanulónak megmondjuk, miért hallgat el

Az első pontozott taktusban egy sor: *„A klikk elhallgat, amíg hallgatlak — hogy ne a
te pengetésednek vegyem."* Enélkül a tanuló azt hiszi, elromlott a metronóm. Csak
akkor jelenik meg, ha **volt** mi elhallgasson: egy némított metronómnak nincs mit
megmagyaráznia.

## Következmények

- A tananyag a `learn/public.dart`-on át importál (`crossFeatureImportsMustUsePublicApi`),
  tehát fájlt nem kellett mozgatni; a némítás-preferencia exportja odakerült, mert
  aki le tudja játszani a klikket, annak a tanuló választását is tudnia kell
  tisztelni.
- A haptikus pulzus a pontozott körben azt is jelenti, hogy a ritmus-pillér
  **fejhallgató nélkül is** használható anélkül, hogy a pontszám sérülne — ez nem egy
  ellenőrizhetetlen feltételezés (a „használj fejhallgatót" utasítás az lenne),
  hanem egy szerkezeti tulajdonság.
- A `listenAndRepeat` mód (a négy közül a másik nem használt) ugyanerre a kérdésre
  épül, és most már van rá mért válasz: az app **nem** játszhat hangot, amíg pontoz.
  Az a rung tehát csak úgy működhet, ha a demonstráció és a visszajátszás időben
  elkülönül — ami egyébként a mód deklarált alakja (`demonstratesFirst: true`).
