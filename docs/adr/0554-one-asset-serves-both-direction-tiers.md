# ADR 0554 — Egy asset szolgálja mindkét irány-szintet; és az ADR 0552 „+0,1429"-e két változást kevert össze

- **Státusz:** elfogadva (az ADR 0552 D1 **nyereség-számát** javítja, a döntését megerősíti)
- **Dátum:** 2026-09-12
- **Kör:** E18-R31
- **Kapcsolódó:** ADR 0552 (a kétszintű döntés), ADR 0553, ADR 0551, ADR 0549,
  `docs/eval/guitarset-strum-baseline.md`, `docs/LESSONS.md` L664–L669,
  `ml/experiment_deadline_augmentation.py`

## Kontextus

Az ADR 0552 kimondta a kétszintű irány-döntést — **ideiglenes** válasz a 70 ms-os élő
határidőnél a nyílhoz, **letisztult** válasz ~238 ms-nál a ritmus-pontozáshoz —, és azt
írta, hogy ez „nulla architektúra-költség", mert a szállított 15 frame már 238 ms-ot elér
és a tensor `(15, 128)` marad.

**Ez a bemenetre igaz, a súlyokra nem.** A két szint két **különböző levágáson tanított**
modell volt, vagyis naivan két asset, két `tryLoad`, két paritás-fixtúra, és a Dart-oldalon
hívási helyenkénti modellválasztás. Van viszont egy harmadik lehetőség: **egy** modell,
ami **mindkét** levágáson tanul (minden söprés kétszer, 70 ms-os és teljes ablakkal), és
megtanulja azt használni, ami éppen ott van.

Ezt a kör megméri, mert a két-asset változat megépítése és ennek **utólagos** felfedezése a
drága sorrend.

## A mérés

`ml/experiment_deadline_augmentation.py` — három kar, mindegyik **mindkét** határidőn
pontozva, mindkét tartalék korpuszon, a repó saját `honest_eval.STD_SEEDS = [42, 1, 2]`
magjaival (mean ± sd). Egy mag nem tud összeomlást rossz inicializálástól megkülönböztetni,
és a döntő leletek **itt épp összeomlások**.

```
  GuitarSet (új játékos ÉS új darab)   alapvonal 0,4468
    kar              70 ms-on pontozva            238 ms-on pontozva
    A @70 ms    0,4690 ±0,0603 (fel 0,3554, felmond 0,59/0,19)  0,4269 ±0,0063 (fel 0,2680, 0,53/0,19)
    B @238 ms   0,5865 ±0,0358 (fel 0,3372, felmond 0,21/0,19)  0,6954 ±0,0362 (fel 0,5164, 0,21/0,19)
    C @MINDKETTŐ 0,5934 ±0,0127 (fel 0,3896, felmond 0,31/0,19)  0,6659 ±0,0172 (fel 0,4608, 0,19/0,19)

  Klangio (új játékos, ugyanaz a rig)  alapvonal 0,3836
    A @70 ms    0,4879 ±0,0854 (fel 0,4907, felmond 0,62/0,38)  0,5205 ±0,0248 (fel 0,4012, 0,37/0,38)
    B @238 ms   0,4795 ±0,0924 (fel 0,1912, felmond 0,08/0,38)  0,6593 ±0,0193 (fel 0,6194, 0,50/0,38)
    C @MINDKETTŐ 0,5828 ±0,0385 (fel 0,5599, felmond 0,56/0,38)  0,6675 ±0,0195 (fel 0,6086, 0,44/0,38)
```

## Döntés

### D1 — EGY asset szolgálja mindkét szintet: a „mindkét levágáson tanítva" fej

Három érv, és egyik sem kis számbeli különbségen áll:

1. **C nyeri a 70 ms-os szintet, a saját specialistáját is megverve.** GuitarSet 0,5934 vs
   A 0,4690; Klangio 0,5828 vs A 0,4879. Nem kompromisszum: a határidő-augmentáció
   **regularizál**, és ezt a **szórás** is mutatja — C ±0,0127 / ±0,0385, A ±0,0603 /
   ±0,0854.
2. **A 238 ms-os szinten B és C döntetlen.** GuitarSet 0,6954 vs 0,6659 a ±0,036-os
   szóráson belül; Klangión C a jobb (0,6675 vs 0,6593). Nincs mérhető veszteség a
   specialistához képest.
3. **C sehol nem omlik össze**, miközben **mindkét specialista összeomlik a másik szinten**
   (D2).

Következmény: **egy** súlykészlet, **egy** `.bin`, **egy** paritás-fixtúra, **egy**
`tryLoad`, és a Dart-oldalon a két szint két **hívási idő**, nem két modell.

### D2 — A két szint NEM lehet „ugyanaz a mai modell, két időben hívva"

Mindkét kereszt-cella összeomlik, és három magon **stabilan**:

- **A letisztult fej a nyílnál:** B @ 70 ms a Klangión **0,08**-at mond felütésnek a valódi
  0,38 mellett (fel-F1 0,1912). Gyakorlatilag megszűnik felütést jelezni — **pont a nyíl
  helyén**.
- **A mai fej a pontozásnál:** A @ 238 ms a GuitarSeten **0,4269 ± 0,0063**, vagyis a
  **többségi alapvonal (0,4468) ALATT**, és a szórás parányi — ez nem ingadozás, hanem
  tulajdonság. A mai modell a plusz hangtól **rosszabb** lesz, mert sosem tanulta meg
  használni.

### D3 — Ezért ASSET ELŐBB, SÍN UTÁNA

Eredetileg a Dart-sínt akartam előbb megépíteni. **Mérve nem szabad:** a mai assettel a
„letisztult" hívás a többségi alapvonal alatt van, tehát a sín bekötése a
**ritmus-pontozást rontaná el** — épp azon az úton, ahol a hamis válasz levonás vagy hamis
kredit (ADR 0549 D2). Egy sín, aminek a mögötte lévő modellje rosszabb, **nem semleges
infrastruktúra, hanem regresszió**.

A sorrend tehát: (1) a C konfigurációval tanított **3 osztályos** asset + kapu-kalibráció +
export + paritás-fixtúra (AGENTS.md §9); (2) utána a Dart-sín.

### D4 — Az ADR 0552 „+0,1429"-e KÉT változást kevert össze; a valódi szint-nyereség +0,07–0,08

Az ADR 0552 a nyereséget így számolta: A @ 70 ms (0,5017) → B @ 238 ms (0,6446). Ez
**egyszerre** változtatta a *szintet* és a *tanítást*, tehát nem a szint nyereségét mérte.

Ugyanazon a súlykészleten — azon, amit D1 szerint szállítanánk — a szint-váltás:

```
  GuitarSet:  C @70 ms 0,5934  →  C @238 ms 0,6659   =  +0,0725
  Klangio:    C @70 ms 0,5828  →  C @238 ms 0,6675   =  +0,0847
```

**+0,07–0,08, nem +0,14.** A kétszintű döntés továbbra is megéri (a szórás ±0,017–0,020,
tehát a nyereség azon kívül van), de a korábbi szám **nem az volt, aminek látszott**.

### D5 — Az ADR 0552 egy-magos számai MINDKÉT irányban tévedtek

Az a kör `seed 42`-n futott. Három maggal:

```
  A @70 ms, GuitarSet:   0,5017 (egy mag)  →  0,4690 ± 0,0603   (optimista volt)
  B @238 ms, GuitarSet:  0,6446 (egy mag)  →  0,6954 ± 0,0362   (pesszimista volt)
```

Tehát nem „egy mag optimista" a hiba alakja, hanem hogy **egy mag nem mérés**. A repónak
**volt** erre konvenciója (`honest_eval.STD_SEEDS`), és nem használtam. Az ADR 0552
táblázata ettől nem lesz érvénytelen — a döntése (a 238 ms-os szint jobb) a három magon
erősebb lett —, de a **számai** a jelen ADR-ből olvasandók.

## Következmények

- A következő kör a **C konfigurációval** tanít 3 osztályosan: GuitarSet negatívok bányászása
  az új geometrián (`negatives.negative_times` korpusz-agnosztikus), a no-strum kapu
  **újrakalibrálása** az ADR 0549 receptjével, `.bin` export, paritás-fixtúra.
- A Dart-sín terve áll, és három csapdához kell teszt: a revízió **nem kreálhat** ütést
  (`_strumSeq` változatlan), **nem írhatja át egy újabb** ütés irányát (200 bpm tizenhatodon
  ~75 ms-ra vannak az ütések, a letisztulás ~240 ms → **akár három ütés van levegőben**), és
  az **elnyomott onset nem éled újra** (nincs esemény, amit revideálni lehetne; az
  újraélesztés késve kreálna ütést).
- A `crnn_frontend` **nem változik**: a gyűrűje 1 s, és a `windowAt(onsetFrame, currentFrame)`
  a még meg nem érkezett részt magától nullázza — a letisztult híváshoz csak **később kell
  hívni**.
- A külső korpuszok **nincsenek verziókövetve** (`ml/data/`, `ml/*.npz` gitignorált).

## Alternatívák, amiket elvetettem

- **Két specializált asset** (D1): a 238 ms-os szinten nincs mérhető nyereség a C-hez
  képest, a 70 ms-oson pedig C **jobb** — tehát a dupla asset, dupla fixtúra és a
  hívás-helyenkénti modellválasztás **fizetés nyereség nélkül**.
- **Ugyanaz a mai modell, két időben hívva** (D2): mérve összeomlik mindkét kereszt-cellában.
- **A sín előbb** (D3): a mai assettel a pontozást rontaná.
- **Egy mag** (D5): mérve mindkét irányban téved.
