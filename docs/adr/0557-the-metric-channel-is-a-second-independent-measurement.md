# ADR 0557 — A metrikus csatorna: a pengetés irányát az ütemen belüli HELY erősebben jelzi, mint a hang — és ez két független mérés, nem egy jobb modell

- **Státusz:** elfogadva (mérés + tervezési döntés; a **bekötés külön kör**)
- **Dátum:** 2026-09-12
- **Kör:** E18-R33
- **Kapcsolódó:** ADR 0551 (a 70 ms-os határidő mint kötő korlát), ADR 0553 (a rés
  adat), ADR 0554/0555/0556 (a kétszintű asset, a kapu, a nyíl), ADR 0512 (margó-kapu),
  `ml/probe_direction_metric.py`, `docs/LESSONS.md` L671

## Kontextus

Négy kör mérte az irány-jelet **a hangban**, és mind falba ért: a jel egy **lecsengési**
jellemző, 150–250 ms utóhangot kíván (ADR 0551), a modell a **saját bemenete lineáris
plafonján** ül (ADR 0553, 0,0155 rés), a gradient boosting mindenhol rosszabb, és a
maradék rés **adat**.

Mind a négy mérés **egyetlen, izolált ütésként** kezelte a pengetést. A pengető kéz
viszont nem izolált: **inga**, ami a lüktetéshez van kötve. Így tanítja a gitár-pedagógia,
és az app maga **ki is rajzolja** (`ss_strum_pendulum.dart`).

A GuitarSet a hexafonikus annotáció mellé **`beat_position` rácsot** is ad. A kérdés tehát
JSON-olvasás árán eldönthető volt.

## A mérés (`ml/probe_direction_metric.py`, játékos- ÉS dal-diszjunkt felosztás)

A fejlécben szereplő jellemzőnek **nulla illesztett paramétere** van:

```
  pontszám = -| a legközelebbi tizenhatod-offbeattől mért távolság |
```

```
  csatorna                                    tartalék AUC
  METRIKUS (hely az ütemben, 0 paraméter)        0,9797      n=526
  AKUSZTIKUS (CRNN a 70 ms-os határidőn)         0,7484      (probe_direction_budget)
```

A mechanizmus olvasható — `P(fel | fázis)`, 8 sáv, tanító oldal:

```
  fázis 0,000-0,125  n=216  P(fel)=0,0316     <- a nyolcadon: LE
  fázis 0,125-0,250  n= 63  P(fel)=0,8884
  fázis 0,250-0,375  n=115  P(fel)=0,9600     <- a tizenhatod-offbeaten: FEL
  fázis 0,375-0,500  n=124  P(fel)=0,0536
  fázis 0,500-0,625  n=176  P(fel)=0,0385     <- a nyolcadon: LE
  fázis 0,625-0,750  n= 82  P(fel)=0,9009
  fázis 0,750-0,875  n=128  P(fel)=0,9565     <- a tizenhatod-offbeaten: FEL
  fázis 0,875-1,000  n=133  P(fel)=0,0715
```

### A kontrollok, amik megmagyarázhatták volna

- **Címke-szivárgás az ütés saját idején keresztül.** Egy lefelé seprés első hangja a
  basszushúr, egy felfelé seprésé a magas E, és az `at` mindkét esetben az ELSŐ hang — egy
  irányfüggő elcsúszás tehát legfeljebb a seprés saját szórása lehet. Mérve: **21,8 ms
  (le) / 23,5 ms (fel)**, a kettő között **1,7 ms** — a tizenhatod 134 ms, vagyis **~6×**
  annyi, amit át kellene lépni. Kizárva.
- **Fázis összekeverve minden teszt-felvételen belül** (a tempó, a stílus és az
  osztályarány megtartva): **0,9797 → 0,5604**. A maradék 0,06 a kontroll őszinte plafonja
  — a felvételen belüli keverés megtartja a fázis-eloszlást, tehát egy felvétel-szintű
  korreláció („ebben a felvételben sok az offbeat ÉS sok a felütés") túléli. 0,56 vs 0,98
  így is eldönti.
- **Nem sáv-illesztési műtermék.** A 8 sávos táblát a paraméter nélküli folytonos
  jellemző **megismétli** (0,9783 vs 0,9797), tehát a tábla csak újra felfedezte a
  „távolság a tizenhatod-offbeattől" fogalmat.
- **Játékosonként:** 03 → 0,9044 · 04 → 1,0000 · 05 → 0,9923. Nem egy játékos viszi.
- **Amit NEM tesztelt, noha így hangzik:** a Rock↔Funk átvitel (0,9888 / 0,9560) a
  **stílust** méri, nem a **felosztást** — a GuitarSet mindkét stílusa tizenhatod-alapú.
  Hogy a leképezés felosztás-specifikus, azt a **2 sávos (nyolcad-) tábla** mondja meg:
  **0,5426**, vagyis majdnem vakvéletlen.

### A termék száma: időzítési szórás

A rács elcsúsztatása ugyanaz a relatív eltérés, mint amikor a tanuló csúszik el egy
pontos rácshoz képest — tehát ez a **tanuló saját időzítési hibájának** az ára:

```
  ±0 ms 0,9797 · ±10 ms 0,9781 · ±20 ms 0,9804 · ±30 ms 0,9599 · ±50 ms 0,8427 · ±80 ms 0,6285
```

**±50 ms szórással is 0,84** — vagyis a metrikus csatorna egy pontatlan tanulón is **jobb,
mint az akusztikus csatorna egy profin** (0,7484).

## Döntés

### D1 — Ez két független MÉRÉS, nem egy jobb modell

- **Akusztikus csatorna:** mit tettek a húrok. Onset-relatív 268 ms-os ablak, a rácsot
  **nem látja** — a függetlenség tehát szerkezeti, nem feltevés.
- **Metrikus csatorna:** mit tett volna a kéz, ha inga. **Nulla paraméter, nulla
  késleltetés.**

### D2 — A metrikus csatornának NINCS határidője, és ez feloldja az ADR 0551 korlátját

A fázis az onset pillanatában **már kész** — nem 70, nem 238 ms múlva. Az ADR 0551 azt
mondta, a kötő korlát a 70 ms-os határidő; a metrikus csatornára ez **nem érvényes**. Az
ADR 0556 dilemmája (gyors nyíl vagy helyes nyíl) így nem menedzselendő, hanem **megszűnik**
a gyakori esetben.

### D3 — A leképezés a LECKE jelöléséből jön, nem korpuszból

A 2 sávos eredmény bizonyítja, hogy a fázis→irány leképezés **felosztás-specifikus**: egy
nyolcadokat előíró leckében a GuitarSeten illesztett tábla **pont fordítva** szólna. Az app
viszont **tudja** az előírt mintát (`strum_patterns.dart`, `D DU UDU`), tehát a leképezés
**nem illesztett paraméter**, hanem a lecke saját jelölése.

### D4 — A KÖTŐ SZABÁLY: a metrikus csatorna EGYEDÜL soha nem dönti el, mit mondunk a tanulóra

Ez a döntés lelke. Ha az előírt minta prior-ként eldöntheti az irányt, akkor az app a
**saját megoldókulcsa ellen** mér, és visszaigazolja azt a mintát, amit a tanuló nem
játszott. Ez pontosan a megtiltott hamis tanítás. Ezért:

1. **Nyíl (megjelenítés, alacsony tét, késleltetés-kritikus):** a két csatorna fúziója.
2. **Irány a PONTOZÁSHOZ (magas tét):** **csak az akusztikus csatorna**, tartózkodással. A
   metrikus csatorna a tartózkodás lécét **megemelheti vagy leengedheti**, de a hívást
   **soha nem fordítja át**.
3. **Egyetértés → nincs megjegyzés.** **Egyetértés-hiány magabiztos akusztikus hívás
   mellett → ez a pedagógiai lelet**: „a pengető kezed itt kiesett az ingából" — és az ADR
   0556 D4 szerint ez az **ütem utáni** áttekintésbe tartozik, nem ütésenkénti nyíl-javításba.

### D5 — És a mérés kimondott egy kellemetlenebb dolgot is: a korpusz nem tartalmazza azt a hibaosztályt, amiért az app létezik

```
  tolerancia        sértő ütések            ebből: felütés a rácson KÍVÜL
  ±0,0625 ütem      203 / 3018  (6,7%)      188
  ±0,0938 ütem      125 / 3018  (4,1%)      104
  ±0,1250 ütem      101 / 3018  (3,3%)       69

  TANÍTÓ felosztás: 41 / 1037 (3,95%), ebből 39 rácson kívüli felütés.
```

Az ütések **96%-a engedelmeskedik az ingának**. Vagyis az akusztikus csatorna **szinte
soha nem látott** olyan felütést, ami egy lefelé ütés metrikus helyén szól — és pontosan
ezek azok az ütések, ahol a két csatorna nem egyezik, tehát ahol az akusztikus csatornának
**egyedül kell döntenie**.

A 0,31-es felütés-recall (ADR 0555) tehát nem csak „kevés játékos" (ADR 0553): a korpusz
felütései **metrikusan sztereotípak**. **Ezért a Guitar-TECHS (9 → 12 játékos) ezt NEM
javítja meg** — profik nem követik el ezt a hibát. A szükséges adat **tanulók inga-sértő
ütése**, és erre az egyetlen ismert forrás a **saját felvételünk**.

## Következmények

- A **bekötő kör terve megváltozik.** Az ADR 0556 mérendő margó-küszöbe helyett a
  **fúziós döntési szabályt** kell megmérni — különben egy olyan kaput betonoznánk be, amit
  a metrikus csatorna feleslegessé tesz. Ezért állt meg a bekötés ezen a ponton.
- **A sín már létezik a produkcióban:** a `TempoTracker.bpm` és a `_placeInBar` nyolcad-
  rácsa **ma kiszámolja a fázist**, és irány-jelként **eldobja**. A rács tizenhatodra
  finomítása és a folytonos fázis megtartása a bekötés érdemi része.
- **Szabad játék metronóm nélkül:** nincs rács → a metrikus csatorna **nem elérhető**, a
  rendszer akusztikus-onlyra esik vissza. Tiszta képesség-határ, nem fokozatos romlás.
- **A felhasználó címkézett felvétele** ezzel „jó lenne"-ből **az egyetlen ismert forrása a
  döntő tanító adatnak** lett. Különösen a `D DU UDU` és a lefojtott felvétel: ott élnek a
  sértések.

## Amit NEM állítunk

- **A fúzió nyereségét nem mértük meg.** Két AUC (0,9797 és 0,7484) **nem** ad összevont
  számot; a csatornák függetlensége szerkezetileg valószínű, de a közös poszterior
  tartalék teljesítménye **külön mérés**, ami a cache újraépítését kívánja onset-idővel.
  Amíg ez nem fut, a fúzió **indoklással bíró terv, nem eredmény**.
- **A 0,9797 profikra szól.** A GuitarSet játékosai alapsávra játszanak; egy kezdő nem. A
  ±50 ms-os sor (0,8427) a legközelebbi, amit ez a korpusz mondani tud — **kezdőkön
  mérve nincs**.
- **A tizenhatod-feltevés nem univerzális.** A 2 sávos eredmény épp ezt mutatja. A D3
  ezért nem korpusz-táblát szállít, hanem a lecke jelölését használja.
