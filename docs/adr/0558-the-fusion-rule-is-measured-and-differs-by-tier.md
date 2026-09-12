# ADR 0558 — A fúziós szabály megmérve: a nyereség nagy, a kockázat az inga-sértő ütéseken van, és a biztonságos szabály TIERENKÉNT MÁS

- **Státusz:** elfogadva (mérés; a bekötés ezzel **megkapta a szabályát** a pontozó úton)
- **Dátum:** 2026-09-12
- **Kör:** E18-R34
- **Kapcsolódó:** ADR 0557 (a két csatorna), ADR 0555 (a kapu), ADR 0556 (a nyíl),
  `ml/probe_direction_fusion.py`, `docs/LESSONS.md` L672

## Kontextus

Az ADR 0557 két csatornát mért külön (metrikus tartalék AUC 0,9797, akusztikus 0,7484) és
**kifejezetten nem állított** összevont számot: két AUC nem komponálható. Ez a kör megadja —
és azt a számot is, ami a termék-kérdést valóban eldönti.

A veszély nem az, hogy a fúzió nem segít. Az, hogy **átlagban úgy segít, hogy pont ott
téved, ahol számít.** Az inga-sértő ütés — egy felütés a tizenhatod-offbeaten **kívül** — az
a tanulói hiba, amiért az app létezik, és ezeken a metrikus csatorna **definíció szerint
téved**. Ha a fúzió ott felülírja a helyes akusztikus hívást, az app azt mondja a tanulónak,
hogy azt játszotta, amit játszania *kellett volna*. Egy minden ütésre átlagolt macro-F1 ezt
**nem látja**, mert a sértések a korpusz 4%-a.

Ezért minden szabály **háromszor** van pontozva: összes ütés, inga-követő, inga-sértő.

## Mérés (`ml/probe_direction_fusion.py`, tartalék GuitarSet: ismeretlen játékos ÉS dal)

530 sor, a metrikus csatorna **99,2%-on elérhető**; inga-követő 519, **inga-sértő 11**.

```
  tier     szabály                       macro   le-F1   fel-F1   pont.összes  követő  SÉRTŐ
  70 ms    C  csak akusztikus            0,5262  0,7743  0,2780     0,6377     0,6435  0,3636
  70 ms    A  teljes fúzió  lam=0,99     0,9168  0,9518  0,8817     0,9000     0,9152  0,1818
  70 ms    B  csak döntetlen m<0,30      0,6497  0,8409  0,4585     0,7321     0,7418  0,2727
 238 ms    C  csak akusztikus            0,6061  0,8605  0,3516     0,7585     0,7649  0,4545
 238 ms    A  teljes fúzió  lam=0,99     0,9226  0,9709  0,8743     0,9377     0,9538  0,1818
 238 ms    B  csak döntetlen m<0,30      0,6784  0,8876  0,4693     0,8019     0,8092  0,4545
```

A `lam` a **előírt rácsnak adott bizalom**, egyetlen söpört skalár — nem korpuszból
illesztett tábla (ADR 0557 D3). `lam = 0,5` **azonos** a C szabállyal, tehát az alapvonal a
**ugyanazon görbe egy pontja**, nem külön kódút.

### A fejléc-szám fel van fújva, és ezt a korpusz okozza

A tartalék ütések **98%-a engedelmeskedik az ingának**, tehát egy rácsra bízó szabály nagyrészt
azt a feladatot kapja, hogy **a rácsot jósolja meg a rácsból**. Egy tanuló kevésbé
engedelmeskedik. A várható pontossága **egyenes** az engedelmességben:

```
  pont(c) = c · pont(követő) + (1 − c) · pont(sértő)
```

Minden szabály **egy ponton** metszi a csak-akusztikus alapvonalat. Ez a metszés — **nem a
fejléc** — mondja meg, szállítható-e:

```
  tier     szabály                     megtérülés c*    várható pontosság c =
                                                        0,95    0,80    0,60    0,40
  70 ms    A  teljes fúzió  lam=0,99      0,401        0,8786  0,7685  0,6219  0,4752
  70 ms    B  csak döntetlen m<0,30       0,481        0,7184  0,6480  0,5542  0,4604
 238 ms    A  teljes fúzió  lam=0,99      0,591        0,9152  0,7994  0,6450  0,4906
 238 ms    B  csak döntetlen m<0,30       0,000        0,7915  0,7383  0,6674  0,5964
```

## Döntés

### D1 — A pontozó (letisztult) úton a szállítható szabály a DÖNTETLEN-TÖRŐ, mert `c* = 0,000`

238 ms-nál a „csak döntetlen, m < 0,30" szabály **semmilyen engedelmességi szinten nem
veszít** a csak-akusztikushoz képest, és közben **+0,0723 macro**-t (0,6061 → 0,6784) és
+0,0434 pontosságot hoz. Ez Pareto-javítás a mért tartományban, nem csere.

Ez egybeesik az **ADR 0557 D4-gyel** — „a metrikus csatorna a tartózkodás lécét mozdíthatja,
de a hívást soha nem fordítja át". **Őszintén: ez egybeesés, nem levezetés.** A D4-et
*mérés előtt* etikai korlátként mondtam ki; a mérés véletlenül egyetért. Ha nem egyezett
volna, a D4 **akkor is kötne**, és ezt ki kellett volna mondanom.

### D2 — A nyíl (gyors) úton a teljes fúzió megtérülése 0,401 — ígéretes, de NEM szállítható vakon

70 ms-nál a teljes fúzió a nyíl pontosságát **0,6377 → 0,9000**-re, a macrót
**0,5262 → 0,9168**-ra viszi, és **0,401 engedelmesség felett** jobb a csak-akusztikusnál —
amit egy küszködő kezdő is bőven meghalad.

**De ez 11 ütésen áll.** Minden „sértő" pontosság **1/11 többszöröse**, a 0,3636 → 0,1818
különbség **két ütés**. A megtérülési pontok ezt a bizonytalanságot öröklik. Ezek tehát
**érveléshez használható korlátok, nem szállítható munkapontok**.

### D3 — És a „biztonságosnak" tervezett szabályom a gyors úton ROSSZABB volt

A B szabály (csak döntetlenre) a *tervezési* intuícióm volt a biztonságos változatra.
70 ms-nál a megtérülése **0,481**, a teljes fúzió **0,401** — vagyis a „konzervatív"
szabály ott **hamarabb** veszít, ahol a legtöbb a tét. Az intuíció a tier, amin a legtöbb
múlt, **fordítva szólt**. Rögzítve: L672.

### D4 — A blokkoló mérés megnevezve

A sértő részhalmazt ez a korpusz **nem tudja megmérni**, mert **nem tartalmazza a
hibaosztályt** (ADR 0557 D5). Ez nem ok a döntés elhagyására, hanem ok a **korlátozására**:
a D1 szabálya szállítható most, a D2-é **a tanulói adat után**.

## Következmények

- A **bekötő kör megkapta a szabályát** a pontozó úton (D1) — mért, Pareto-biztos, és
  egybeesik a már kimondott etikai korláttal.
- A nyíl fúziója **funkció-kapu mögé** tartozik, amíg a D2 megtérülése nincs tanulói
  adaton megmérve.
- A `TempoTracker` rácsát **tizenhatodra** kell finomítani (ma nyolcad), és a fázist
  folytonosan megtartani — a metrikus csatorna 99,2%-os elérhetősége ezen áll.
- Metronóm nélküli szabad játékban a metrikus csatorna **nem elérhető**; a rendszer a C
  szabályra esik vissza. Nincs néma romlás, mert az elérhetőség explicit állapot.

## Amit NEM állítunk

- A 0,9168 / 0,9226 macro **nem** generalizációs becslés tanulóra: a korpusz 98%-os
  inga-engedelmessége fújja fel. A megtérülési görbe a becslés, és az **11 ütésen** áll.
- A lineáris engedelmesség-modell feltételezi, hogy **a tanuló sértései úgy néznek ki, mint
  a GuitarSet sértései**. Egy kezdő sértése valószínűleg **másfajta** (egész minta
  elcsúszása, nem egy-egy kósza ütés), tehát még a lineáris modell is **ismeretlen
  pontosságú**.
- A `lam` nem kalibrált valószínűség, hanem söpört bizalom-skalár. Kalibrálni a lecke
  jelöléséből és a mért időzítési szórásból lehetne — külön kör.
