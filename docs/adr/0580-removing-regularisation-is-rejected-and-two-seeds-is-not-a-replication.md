# ADR 0580 — A regularizáció elvétele ELUTASÍTVA: a 70 ms-os tieren előjelet vált, a csonkítatlanon következetesen költség, és a szórást 3,3×-ra nyitja — plusz a HARMADIK eset, ahol két egyező seed után a harmadik megfordult

- **Státusz:** elfogadva (irányított kísérlet **negatív** eredménnyel; az ADR 0578 D2 egy
  megállapítását **hatókörben szűkíti**; semmi nem kerül felkapcsolásra)
- **Dátum:** 2026-09-13
- **Kör:** E18-R46
- **Kapcsolódó:** ADR 0578 (a hipotézis forrása, és amit ez hatókörben szűkít), ADR 0554 D1 (a
  szórás-érv, amit ez **megerősít**), ADR 0575, `ml/experiment_recipe_ladder.py`,
  `docs/LESSONS.md` L691

## Kontextus

Az ADR 0578 D2 egyetlen **stabil negatív** leletet talált: a regularizáció (dropout 0,25 /
rec 0,15 / l2 1e-4) a telepítési korpuszon **mindhárom seeden költség** volt — az R1 → R2
lépés −0,0217 / −0,0905 / −0,0656, átlag **−0,0592 ± 0,0348**.

Ebből adódott egy **irányított** hipotézis, nem tapogatózás: ha a regularizáció költség, akkor
a settled receptből **elvéve** javulnia kell. Ez az R5 kar (minden úgy, mint az R4, csak
`reg={}`), három seeden.

## Döntés

### D1 — Mérve: a hipotézis NEM áll

```
  R4 → R5 (a regularizáció elvétele)   s42       s1        s2      átlag ± sd     ítélet
  Klangio@70                         +0,0533   +0,0440   −0,0244   +0,0243 ± 0,0424  ELŐJELET VÁLT
  GuitarSet@70                       +0,0246   −0,0630   −0,0696   −0,0360 ± 0,0526  ELŐJELET VÁLT
  Klangio@full                       −0,0186   −0,0141   −0,0243   −0,0190 ± 0,0051  MIND NEGATÍV
  GuitarSet@full                     −0,0007   −0,0547   −0,0759   −0,0438 ± 0,0388  MIND ≤ 0
```

**Két seed igazolta a hipotézist (+0,0533, +0,0440), a harmadik megfordította (−0,0244).** A
70 ms-os tieren tehát **nem megállapított**.

A **csonkítatlan** tieren viszont a legszorosabb delta az egész kísérletsorozatban:
**−0,0190 ± 0,0051** Klangión, mindhárom seeden. Vagyis a regularizáció **elvétele** ott
következetesen **rombol** — és éppen az a tier, amit a két-tier döntés meg akar vásárolni
(ADR 0579).

### D2 — És a regularizáció azt teszi, amit a regularizáció tesz: szűkíti a szórást

```
  seed-szórás, Klangio@70     R0        R4 (reg)    R5 (nincs reg)
                            0,0757      0,0153        0,0509
  szintek (átlag)           0,4708      0,5231        0,5474
```

Az R4 seed-szórása a **3,3×-a** szorosabb az R5-nél ugyanazon a cellán. Tehát az R5 látszólag
magasabb átlaga (0,5474 vs 0,5231) egy **háromszor bizonytalanabb** mérésből jön — pont az a
csere, amit az ADR 0554 D1 szórás-érve leír, és amit az ADR 0578 D5 a 3-osztályú kapuzott
családon replikált.

**Ez az érv az R4 mellett szól, és nem a szintről:** egy recept, aminek a kimenete seedenként
kevésbé ugrál, kevesebb kört visz el annak eldöntésére, hogy mit is mért.

### D3 — Ezért az R5 ELUTASÍTVA, és az R4 marad a jelölt recept

Négy ok, és egyik sem kis számbeli különbségen áll:

1. a 70 ms-os nyereség **nem megállapított** (előjelet vált);
2. a csonkítatlan tieren **következetes veszteség** (−0,0190 ± 0,0051);
3. GuitarSeten mindkét tieren **romlás** (−0,0360 / −0,0438);
4. a seed-szórás Klangión **3,3×** nagyobb.

### D4 — Az ADR 0578 D2 regularizáció-megállapítása HATÓKÖRBEN szűkítve

Az ADR 0578 D2 így hangzott: *„a regularizáció mindhárom seeden KÖLTSÉG a telepítési
korpuszon."* Ez **áll**, de csak abban a kontextusban, amiben mérték: az **R1 → R2** lépés,
azaz **Klangio-only, 70 ms-only** recept, a 70 ms-os cellán.

A **mindkét levágáson tanító** receptben ugyanez a faktor máshogy viselkedik: a 70 ms-on
előjelet vált, a csonkítatlanon pedig **javít** (azaz elvétele rombol). Egy faktor hatása
tehát **nem vihető át** egyik recept-kontextusból a másikba — ugyanaz a hiba-család, mint
amit az L685 a routing-jelre írt fel („egy jel érvényessége a MODELL tulajdonsága").

### D5 — És a HARMADIK eset, ahol két egyező seed után a harmadik megfordult

```
  eset                                          s42       s1        s2        kimenet
  ADR 0575 nettó R0→R4, Klangio               +0,1051   +0,0923   −0,0403   visszavonva
  ADR 0578 R2→R3 (GuitarSet) Klangión         +0,0810   +0,0642   −0,0413   visszavonva
  ADR 0580 R4→R5 (reg elvétele) Klangión      +0,0533   +0,0440   −0,0244   elutasítva
```

Háromszor ugyanaz az alak: **s42 és s1 egyetért, s2 megfordítja.** Ez nem azt jelenti, hogy az
s2 „rossz seed" — azt jelenti, hogy **ebben a kísérlet-családban két egyező seed nem
replikáció**, és a Klangio@70 cella seed-szórása (az R0-n **0,0757**) összemérhető minden
érdekes hatással.

**A szabály innentől: ezen a létrán egyetlen recept-állítás sem kerül ADR-be két seedből. A
`STD_SEEDS` mind a három kötelező, és ha egy delta előjele nem egyezik mindhármon, az
eredmény „nem megállapított", nem „kisebb".**

## Következmények

- Az **R4** (a settled recept, regularizációval) marad a jelölt recept. Az R5 nem indul újra.
- A `ml/recipe_ladder_seed{42,1,2}.json` mostantól mind a hat kart tartalmazza (R0–R5), mert a
  létra **MERGE**-öl és nem klobberol — ezt ebben a körben javítottam, különben egy
  `--arms=R5` futás szétverte volna a három seed ötkaros rekordját.
- A `settledTier` marad **false**.

## Amit NEM állítunk

- **Nem állítjuk, hogy a regularizáció JAVÍT a 70 ms-os tieren** a settled receptben. Azt
  állítjuk, hogy az elvétele ott **nem megállapítottan** javít, máshol pedig **mér**hetően
  rombol.
- **n = 3.** Egy három-elemű szórás maga is zajos; a D5 szabálya épp ezért előjel-egyezést
  kíván, nem t-próbát.
- **Orákulum-ablakok**, nem in situ (az in-situ műszer az ADR 0577).
- **Nem kerestünk más regularizációs erősséget.** A `H.AUG_REG` a-priori érték (r173), nem
  tuningolt; egy köztes erősség mérhető, de ez a kör nem mérte.
