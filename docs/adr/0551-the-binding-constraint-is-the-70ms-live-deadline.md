# ADR 0551 — A kötő korlát a 70 ms-os élő határidő; az ADR 0550 főszáma túlzó volt

- **Státusz:** elfogadva (az ADR 0550 D1-ét **felülírja**, D2/D3/D4-ét megerősíti)
- **Dátum:** 2026-09-12
- **Kör:** E18-R28
- **Kapcsolódó:** ADR 0550, ADR 0549, ADR 0512,
  `docs/eval/guitarset-strum-baseline.md`, `docs/LESSONS.md` L665–L666,
  `ml/probe_direction_budget.py`, `ml/guitarset.py`, `ml/experiment_cross_corpus.py`

## Kontextus: a saját előző körömet javítom

Az ADR 0550 D1 azt állította, hogy egy lineáris olvasó **a modell saját bemenetéből**
macro-F1 **0,7723**-at ér el, szemben a CRNN 0,3876-jával, és ebből azt a következtetést
vonta le, hogy *„az információ ott van, a modell nem nyeri ki"*.

**A szám nem a modell bemenetéről szólt.** A `probe_direction_headroom.centred_starts`
minden elemző ablakot a frame-re **centrál**:

```
start = onset − PRE_FRAMES·HOP − N_FFT//2     →  onset − 94 ms
```

a szállított modellt tápláló `experiment_deadline.window_truncated` viszont a frame-nél
**kezdi** az ablakot, és a határidő utáni farkat kinullázza:

```
start = (center − PRE_FRAMES)·HOP             →  onset − 30 ms
seg[onset + 70 ms :] = 0
```

Tehát a próba **64 ms extra felvezetést** kapott, **és** a 70 ms utáni hangot is.

És ez nem akármilyen hiba. Az **ugyanaz az ADR**, a D3-ban, mérte ki, hogy a szigorúan
onset **előtti** hang AUC **0,7128**-cal jelzi az irányt, mert a comping váltakozik — és
kimondta, hogy ez **váltakozás-tipp, nem mérés**, amit nálunk nem szabad beszámítani. A
főszámom tehát **pont azzal a jellel pontozott, amit a szomszédos döntésem megtiltott.**

A modell valódi igazításán, ugyanazon a címkekészleten és osztáson:

```
  szállított log-mel 128, 70 ms levágás (A CRNN BEMENETE)   le 0,7857  fel 0,3913  macro 0,5885
  16 geometriai sáv, 70 ms levágás                         le 0,8817  fel 0,3457  macro 0,6137
  betanított CRNN (Klangio+GuitarSet), 70 ms               le 0,5835  fel 0,4199  macro 0,5017
```

A lineáris padló tehát **0,5885**, nem 0,7723 — és a CRNN **0,087**-tel van alatta, nem
0,39-cel. *A CRNN nem a domináns defekt.*

## A mérés, ami a valódi korlátot megtalálta

`ml/probe_direction_budget.py` — ugyanaz a reprezentáció, ugyanaz a geometria, csak az
onset után megtartott hang hossza mozog. Két frame-szám, hogy a frame-**darabszám** ne
legyen összekeverhető a hang **hosszával**:

```
  frame  megtartott hang      le      fel    macro     AUC
    15    40 ms            0,8746  0,3584  0,6165  0,7479
    15    70 ms (SZÁLLÍTOTT) 0,8817  0,3457  0,6137  0,7484
    15   100 ms            0,8894  0,3506  0,6200  0,7501
    15   150 ms            0,8911  0,3356  0,6133  0,7826
    15   250 ms            0,9186  0,5466  0,7326  0,8369
    28   250 ms            0,9142  0,5217  0,7179  0,8279
    28   minden (368 ms)   0,9129  0,5185  0,7157  0,8228
```

**150 és 250 ms között ugrás van: +0,12 macro, és a fel-F1 megduplázódik (0,3356 →
0,5466).** Több **frame** nem hoz semmit (28 frame rosszabb, mint 15); több **hang** hoz.

## Döntés

### D1 — Az ADR 0550 D1 főszáma felülírva

A szállított bemenet lineáris padlója **0,5885**, és a betanított CRNN **0,5017**. A
„nem nyeri ki, ami a bemenetében van" állítás **0,087-es** résre igaz, nem 0,39-esre. Az
ADR 0550 D1 ennyiben téves, és nem törölve, hanem **láthatóan felülírva** marad — a
hibás szám és a javítása együtt többet mond, mint a javítás egyedül (ugyanaz az elv,
mint az ADR 0549 D3-ban).

### D2 — Az ADR 0550 korpusz-megállapítása VÁLTOZATLANUL áll

Az igazítási hiba a korpusz-kísérletet **nem érinti**: az
`ml/experiment_cross_corpus.py` végig a szállított `window_truncated` geometriát
használja. Mérve, a szállított architektúrán, játékos- és darab-diszjunkt teszten:

```
  kar                      GuitarSet macro   Klangio macro   "fel"-nek mond / valóság
  A Klangio only                0,3552          0,4080        0,76/0,19 · 0,73/0,38
  B Klangio + GuitarSet         0,5017          0,5979        0,64/0,19 · 0,58/0,38
  C GuitarSet only              0,5068          0,3832        0,06/0,19 · 0,00/0,38
```

**B mindkét korpuszon javít** — az *eredeti* doménben is (0,4080 → 0,5979). A
korpusz-diverzitás tehát valódi emelő, és a GuitarSet levezetett címkéi taníthatók
(ADR 0550 D2 megerősítve, most már nem csak lineáris illesztéssel).

**C egy csapda, amit a kontroll-kar kapott el.** A macro-ja (0,5068) *megveri* B-t, de a
Klangión **0,00**-t mond felütésnek: összeomlott a „mindig lefelé"-re, és a macro-ja csak
azért magas, mert a teszt 81% lefelé. **Macro-F1 egyedül a rosszabb modellt hozta volna
ki győztesnek** — a „felütésnek mond / valóság" oszlop nélkül ez láthatatlan. Ugyanaz a
prior-illesztés, mint az L664-ben, új helyen. Ezért: **minden irány-eredmény mellett ki
kell írni a jósolt osztály-arányt a valódi mellé.**

### D3 — A kötő korlát a 70 ms-os élő határidő

Mérve: a 70 ms-os levágás **0,12 macro-F1-be és a fel-F1 felébe** kerül. Az irány a
mikrofonon **nem attack-tranziens**, hanem a **lecsengés** jellemzője: melyik húrok
zengenek tovább, és a pengető útja hogyan formálja őket. Ez egyúttal megmagyarázza, amit
az ADR 0550 D4 mért, de nem értett: a nagy időfelbontás **azért** rosszabb, mert nem
sorrend-jel, és a 128 ms-os ablak **azért** nem volt baj.

### D4 — A pontozás nem tartozik a határidő alá; csak a nyíl

Ez a döntés terméki, és a mérésből következik. A **70 ms** azért van, mert az élő
**nyílnak** azonnal meg kell jelennie. A **ritmus-pontozásnak** viszont nincs latencia-
igénye: a `StrumAnalyzer` visszatekinthet. Ugyanakkor a pontozás az, **ahol a hamis
válasz fáj** — az ADR 0549 D2 pont ezt rögzítette: az elnyomott ütés levonás azért, amit
a motor nem hallott, a fantom ütés kredit azért, amit a tanuló nem játszott.

Ezért a javítás alakja **kétszintű irány-döntés**: egy **ideiglenes** válasz 70 ms-nál a
nyílhoz, és egy **letisztult** válasz ~250 ms-nál a pontozáshoz és a visszajelzéshez. A
sín megvan (`StrumDirectionClassifier`, `StrumAnalyzer`), tehát ez bekötési kör, nem
architektúra-átírás. **Ebben a körben nem történik meg**: mérés előbb, változtatás utána.

### D5 — A kapacitás NEM emelő, és az ablakonkénti normalizálás sem

Mérve ugyanazon a poolon (`crnn_capacity` cellák):

- 364k paraméter, globális norm: GuitarSet **0,5017** / Klangio 0,5979 ← a legjobb
- 364k paraméter, ablakonkénti norm: 0,4065 / 0,3927 — **rontott**
- 10k paraméter: **összeomlott** (mindent „fel", le-F1 0,0000)
- 4k paraméter: ugyanaz az összeomlás

A „364 ezer paraméter 106 effektív csoportra, tehát túlilleszkedés" hipotézis tehát
**megbukott**: a modell zsugorítása nem javít, hanem megszünteti. A hangerő-invariancia-
hipotézis szintén: az ablakonkénti normalizálás a CRNN-nek és a lineáris olvasónak is
rontott (0,5885 → 0,5763).

### D6 — Az ADR 0550 D3 megerősítve, és most már bizonyítottan nem elvi aggály

A „szigorúan onset utáni ablakon pontozz" szabály **a saját hibámat fogta meg egy körrel
később**. Nem óvatosságból jó: ha nem lett volna kimondva, a 0,7723-at nem tudtam volna
mihez mérni, és a kör azzal zárult volna, hogy „a CRNN rossz".

## Következmények

- A következő kör a **kétszintű döntést** köti be (D4), és a ~250 ms-os ágra mér
  korpuszközi irány-számot. Ez az, ami a Ch14 §7.2 Alpha kapuhoz (0,80) közelíthet: a
  lineáris padló 250 ms-on **0,7326**, és a korpusz-diverzitás ezen felül jön.
- A szállított eszközön ebben a körben **semmi nem változik**.
- Minden korábbi „0,77" / „0,79" / „0,7861" szám a jelen ADR előtti szövegekben
  **ablak-igazítási hibából** származik; a javítás a mérés-dokumentumban és a RAG chunk
  018-ban is át van vezetve.
- A külső korpuszok **nincsenek verziókövetve** (`ml/data/` gitignorált), tehát ezek
  elkötelezett riportok, nem CI-kapuk.

## Alternatívák, amiket elvetettem

- **A 70 ms-os határidő egyszerű felemelése** mindenhol: a nyíl késne, ami az élő
  visszajelzés lényegét rontja. A kétszintű döntés ugyanazt a nyereséget adja ott, ahol
  a pontosság fontos, és nem fizet ott, ahol a sebesség az.
- **Kisebb modell / erősebb regularizáció** (D5): mérve összeomlik.
- **Ablakonkénti normalizálás** (D5): mérve mindkét olvasónak rontott.
- **Új spektrális reprezentáció** (16 geometriai sáv a 128 log-mel helyett): mérve
  **+0,03** a modell igazításán — valódi, de kicsi, és Dart-oldali tükrözést igényelne
  (`crnn_frontend.dart` paritás). Nem ér annyit, amennyibe kerül, amíg a 0,12-es
  határidő-tétel nyitva van.
- **A `probe_direction_headroom.py` törlése**: megmarad. Az a fájl a hibás
  igazítás rekordja, és a docstringje most megmondja, mire nem használható.
