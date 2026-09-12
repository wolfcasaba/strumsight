# ADR 0578 — Három seed: a GuitarSet-nyereség áll (+0,377 ± 0,071), a KLANGIO-fele az ADR 0575-nek VISSZAVONVA (előjelet vált), és az ADR 0554 szórás-érve viszont replikál

- **Státusz:** elfogadva (mérés; az **ADR 0575 D2 Klangio-felét és D4-ét visszavonja**, a
  GuitarSet-felét megerősíti, és az ADR 0554 D1 egy érvét **replikálja**; semmi nem kerül
  felkapcsolásra)
- **Dátum:** 2026-09-13
- **Kör:** E18-R45
- **Kapcsolódó:** ADR 0575 (amit ez részben visszavon — a D5 **saját** figyelmeztetése
  alapján), ADR 0554 D1 (a szórás-érv, itt **igazolva**), ADR 0569 (amelynek aggálya ezzel
  **nem igazolódik, de nem is dől meg**), ADR 0573, ADR 0577,
  `ml/experiment_recipe_ladder.py`, `honest_eval.STD_SEEDS`

## Kontextus

Az ADR 0575 D5 **saját** zajpadló-mérése alapján ezt írta elő: *„a következő kör dolga ezeket
a `honest_eval.STD_SEEDS = [42, 1, 2]`-vel megismételni."* Megismételve — mind az öt kar,
mindhárom seed, ugyanaz a split, ugyanaz a műszer.

Az eredmény a **saját előző köröm főállításának felét visszavonja.**

## Döntés

### D1 — A három seed

```
  Klangio@70 (a TELEPÍTÉSI korpusz)        s42     s1      s2      átlag ± sd
  R0  a szállított recept                 0,4354  0,4192  0,5577  0,4708 ± 0,0757
  R1  + fit-menetrend                     0,4808  0,4990  0,5233  0,5010 ± 0,0213
  R2  + regularizáció                     0,4591  0,4085  0,4577  0,4418 ± 0,0288
  R3  + GuitarSet                         0,5401  0,4727  0,4164  0,4764 ± 0,0620
  R4  + 2. levágás (= settled recept)     0,5405  0,5115  0,5174  0,5231 ± 0,0153

  GuitarSet@70                             s42     s1      s2      átlag ± sd
  R0                                      0,1623  0,0971  0,2379  0,1658 ± 0,0705
  R1                                      0,1506  0,2233  0,1537  0,1759 ± 0,0411
  R2                                      0,2504  0,1748  0,1995  0,2082 ± 0,0385
  R3                                      0,5596  0,4314  0,4808  0,4906 ± 0,0647
  R4                                      0,5071  0,5552  0,5645  0,5423 ± 0,0308
```

### D2 — Ami ÁLL: a GuitarSet-oldal, és két lépés

```
  NETTÓ R0 → R4, GuitarSet    +0,3448  +0,4581  +0,3266   átlag +0,3765 ± 0,0713
  R2 → R3 (GuitarSet-adat)    +0,3092  +0,2565  +0,2813   átlag +0,2823 ± 0,0264
  R1 → R2 (regularizáció), Klangión  −0,0217 −0,0905 −0,0656  átlag −0,0592 ± 0,0348
  R3 → R4 (2. levágás), Klangión     +0,0004 +0,0388 +0,1010  átlag +0,0467 ± 0,0508
```

- A settled recept a GuitarSeten **nagy fölénnyel** jobb, és a nyereség az átlagának 5×-e a
  szórásnak. Ez **áll**.
- A GuitarSet-adat hozzáadása a GuitarSetet emeli, szorosan. (Nem meglepő; a korpuszán tanul.)
- A **regularizáció mindhárom seeden KÖLTSÉG** a telepítési korpuszon.
- A **második levágás mindhárom seeden pozitív** Klangión — de az egyik érték +0,0004, tehát
  ez a leggyengébb a négy „azonos előjelű" közül.

### D3 — Ami NEM áll: az ADR 0575 D2 KLANGIO-fele. Visszavonva.

```
  NETTÓ R0 → R4, Klangio      +0,1051  +0,0923  −0,0403   átlag +0,0524 ± 0,0805
```

**A harmadik seeden az előjel megfordul.** A szórás nagyobb, mint az átlag (t ≈ 1,11, n=3);
ez nem „kisebb nyereség", hanem **nem megállapított**.

Az ADR 0575 D2 főállítása így hangzott: *„illesztett splitten a settled recept a szállított
receptet MINDKÉT korpuszon legyőzi — Klangion +0,1051."* A **GuitarSet-fele áll**, a
**Klangio-fele visszavonva.** Egy seedből állítottam, és a következő kettő közül az egyik
megfordította.

Két további lépés is előjelet vált, és ezeket is visszavonom: **R0 → R1** (fit-menetrend)
mindkét korpuszon, és **R2 → R3** Klangión (+0,0810 / +0,0642 / **−0,0413**) — tehát az
ADR 0575 D3 állítása, hogy *„a GuitarSet hozzáadása a Klangiót is emeli, +0,0810"*, szintén
**nem megállapított**.

### D4 — Az ADR 0575 D4 („a regularizáció transzferért fizet in-domain pontossággal") VISSZAVONVA

```
  R1 → R2, GuitarSeten        +0,0997  −0,0485  +0,0458   előjelet VÁLT
  R1 → R2, Klangión           −0,0217  −0,0905  −0,0656   mindhárom NEGATÍV
```

Nem csere. A regularizáció a telepítési korpuszon **következetesen költség**, a GuitarSeten
pedig **zaj**. Az ADR 0575 D4 egyetlen seed két cellájából olvasott ki egy Pareto-cserét, ami
nincs ott.

### D5 — De az ADR 0554 D1 SZÓRÁS-érve replikál, és ez az egyetlen érv, ami nem a szinttől függ

Az ADR 0554 D1 első érve nem a szintről szólt, hanem arról, hogy a határidő-augmentáció
**regularizál, és ezt a szórás mutatja**. Három seeden, a **3-osztályú, kapuzott** családon
(az ADR 0554 2-osztályú, kapu nélküli karokon mérte — ADR 0575 D6):

```
  seed-szórás                 R0       R1       R2       R3       R4
  Klangio@70               0,0757   0,0213   0,0288   0,0620   0,0153   <- R4 a legszorosabb
  GuitarSet@70             0,0705   0,0411   0,0385   0,0647   0,0308   <- R4 a legszorosabb
```

**A mindkét levágáson tanított kar mindkét korpuszon a legkisebb seed-szórású** — a
szállított recept (R0) szórásának **ötödé** Klangión, **felé**nél kevesebb GuitarSeten. Ez az
ADR 0554 érvének az a fele, ami **átvisz** a szállító modell-családra, és ami nem dőlt meg a
szintekkel együtt. Egy olyan recept, aminek a kimenete seedenként kevésbé ugrál, **önmagában**
értékes: az ADR 0575 D5 zajpadlója pontosan ezért volt akkora probléma.

### D6 — Mit jelent ez az arc állására

Az ADR 0569 azt állította, a settled recept a telepítési korpuszon **visszaesik**. Az
ADR 0573 megmutatta, hogy ezt egy same-player számhoz mérte — **az a visszavonás áll.** Az
ADR 0575 a helyére azt tette, hogy **nyer** — és most ez sem áll.

A becsületes állapot: **a telepítési korpuszon nem tudjuk, melyik recept jobb.** Se nem
„visszaesik", se nem „nyer". Három seed, öt kar, és a nettó előjele nem stabil.

Ami a lezárásához kell, nem több seed ugyanazon a műszeren: **a telepítési korpuszt most in
situ is mérjük** (ADR 0577), ami végponttól végpontig méri, amit az app tesz — onset
detektálás, streamelt ablak, kapu, margó —, nem orákulum-ablakon. Egy recept ottani
összevetéséhez a jelölt súlyait `.bin`-be kell exportálni, és a söprést `STRUM_3C_ASSET`-tel
ráfuttatni. Ez a következő kör tétele, és **nem** egy újabb seed-kör.

### D7 — A fegyelem, ami ezt elkapta, a saját előző köröm figyelmeztetése volt

Az ADR 0575 D5 megmérte a zajpadlót (~0,048 két script között, egy seeden), felsorolta, mely
lépések **nem feloldhatók** egy seedből, és előírta a STD_SEEDS-ismétlést. A lista akkor így
szólt: a fit-menetrend, a regularizáció és a 2. levágás. **Kettőből kettő eltalálva** — a
fit-menetrend és (GuitarSeten) a regularizáció valóban megfordult —, de a lista **hiányos**
volt: a **nettó** is megfordult, és azt akkor „megbízhatónak" minősítettem, mert 0,105 jóval
a 0,048-as padló fölött volt.

*Egy egy-seedes zajpadló a LÉPÉSEKRE ad korlátot, nem a NETTÓRA: a nettó négy lépés összege,
és ha a lépések külön-külön seed-érzékenyek, az összegük szórása nem kisebb, hanem nagyobb
lehet.* Ezt a hibát a padló számából nem lehetett kiolvasni — csak a seedekből.

## Következmények

- Az ADR 0575 helyben annotálva: a D2 Klangio-fele, a D3 Klangio-lépése és a D4 visszavonva;
  a D2 GuitarSet-fele, a D6 (ADR 0554-gyel nincs ellentmondás) és a D7 (a `pool_tier` lelet)
  **áll**.
- A `ml/recipe_ladder_seed{42,1,2}.json` mindhárom futás teljes provenance-rekordja a fán.
- A `settledTier` marad **false**. Asset nem cserélve, szállított konstans nem mozdítva.

## Amit NEM állítunk

- **Nem állítjuk, hogy a settled recept ROSSZABB Klangión.** Azt állítjuk, hogy **nem
  megállapított**. A D6 pont ezt a különbséget tartja.
- **n = 3.** Egy három-elemű szórás maga is nagyon zajos; a „± sd" itt tájékoztató, nem
  konfidencia-intervallum. Több seed szűkítené, de a D6 szerint nem az a helyes következő
  lépés.
- **Orákulum-ablakok.** Ez a létra a gyorsítótárazott ablakokon fut, nem in situ (ADR 0577 az
  in-situ műszer).
- **A GuitarSet-oldali fölény nem szállítási állítás.** A GuitarSet nem a telepítési
  feltétel (ADR 0569 D3), és a GuitarSet-sejt a GuitarSeten tanító karok felé torzít
  (ADR 0573 D6).
- **A D5 szórás-érve nem szint-állítás.** Azt mondja, hogy az R4 kimenete stabilabb, nem hogy
  jobb.
