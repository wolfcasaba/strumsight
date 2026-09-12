# ADR 0555 — A „nem-pengetés" kapu osztály-feltételes: az osztály-vak szabály a felütéseket hallgattatta el

- **Státusz:** elfogadva (az ADR 0549 kalibrációs **szabályát** váltja, a döntését megtartja)
- **Dátum:** 2026-09-12
- **Kör:** E18-R32
- **Kapcsolódó:** ADR 0549 (az illesztett kapu), ADR 0552/0554 (a kétszintű döntés),
  ADR 0556 (a megjelenítés), `docs/LESSONS.md` L670,
  `ml/train_live_3c_settled.py`, `ml/live_3c_settled_threshold.json`

## Kontextus

Az ADR 0549 a kaput így kalibrálta: az a P(no-strum) kvantilis, ami **a valódi pengetések
95%-át megtartja**. A szabály **nem kérdezi meg, melyik irányú** volt a pengetés.

Mérve, a most tanított kétszintű modellen (ADR 0554), a tartalék korpuszokon:

```
  szint    korpusz     elnyomva: LE     FEL     arány    P(no-strum) medián LE / FEL
   70 ms   Klangio        0,165      0,209     1,27×      0,0051 / 0,0098
   70 ms   GuitarSet      0,138      0,225     1,63×      0,0046 / 0,0241
  238 ms   Klangio        0,114      0,154     1,35×      0,0014 / 0,0038
  238 ms   GuitarSet      0,035      0,098    2,80×      0,0003 / 0,0019
```

**A kapu a felütéseket 1,3–2,8-szor gyakrabban nyomja el** — vagyis a teljes elnyomási
költségvetését aránytalanul arra az osztályra költi, amiben a modell a leggyengébb. És a
két osztály illesztett küszöbe **hétszeresen** tér el:

```
  le   0,041166      fel  0,292900
```

**Terméki következmény, nem elvont aszimmetria.** A `reggae-skank` lecke szinte kizárólag
felütés. Egy azt gyakorló tanuló az ütéseinek **tizedét** a motor csendje miatt veszítené
el — levonásként. Ez pontosan az ADR 0549 D2-ben kimondott hazugság, csak osztály szerint
elfordítva.

## Ez NEM új ötlet, és ez a fontos része

A kutatás (Sonnet 5 agent, 2026-09-12) megnevezte, minek az esete:

- **Az osztály-vak szabály tankönyvi Chow (1970)** („On optimum recognition error and
  reject tradeoff", *IEEE Trans. IT* 16(1):41–46). A küszöb-formulában —
  `t = (C_r − C_c)/(C_e − C_c)` — **nincs osztály-index**, mert minden hibát és minden
  elutasítást egyenlő költségűnek vesz. A mért 1,3–2,8-szoros eltérés tehát nem hiba a
  kalibrációban, hanem **ennek a feltevésnek a dokumentált bukási módja**.
- **A javítás neve Mondrian / címke-feltételes konformális predikció** (Vovk, Lindsay,
  Nouretdinov, Gammerman 2003, *Mondrian Confidence Machine*; Vovk, Gammerman, Shafer
  2005, *Algorithmic Learning in a Random World*): osztályonként saját kvantilis, és ezzel
  **egzakt véges mintás, eloszlásfüggetlen osztályonkénti garancia**.
- **És elérhető nálunk:** Barber, Candès, Ramdas, Tibshirani (2021, *The Limits of
  Distribution-Free Conditional Predictive Inference*) szerint az egzakt feltételes
  lefedés **folytonos** feltételre lehetetlen, **véges partícióra viszont egzaktul
  elérhető** — a három osztályunk véges partíció.
- **A mért dominancia publikált tétel:** Fumera, Roli, Giacinto (2000, *Reject Option with
  Multiple Thresholds*) bizonyítja, hogy az osztályonkénti elutasítási küszöbök
  **Pareto-dominálják** az egy-küszöbű Chow-t, épp mert az osztályonkénti becslési hiba
  aszimmetrikus.

Vagyis amit „jó ötletnek" éreztem, az egy **2000-es tétel és egy 2003-as keretrendszer**.

## Döntés

### D1 — A szállított kapu az osztályonkénti kvantilisek MAXIMUMA

```
  class_blind        (ADR 0549)   0,124528   megtart 0,950   elutasít 0,974
  class_conditional  (szállított) 0,292900   megtart 0,971   elutasít 0,960
```

A maximum azért, mert így **minden osztály eléri legalább a célt** (a könnyebb osztály
többet kap, innen a 0,971 a 0,95 cél helyett). A döntő, hogy a küszöböt a **nehezebb
osztály** állítja be — itt a felütés.

Tartalék teljesítmény, mind a négy cellában:

```
  kapu               szint    korpusz     macro   fel-F1  fel-pont. fel-recall  elnyomva-fel
  class_blind         70 ms   Klangio    0,4922  0,5137   0,4343    0,6285      0,209
  class_conditional   70 ms   Klangio    0,5055  0,5357   0,4371    0,6918      0,137
  class_blind         70 ms   GuitarSet  0,5117  0,2600   0,2653    0,2549      0,225
  class_conditional   70 ms   GuitarSet  0,5262  0,2780   0,2562    0,3039      0,127
  class_blind        238 ms   Klangio    0,6267  0,5754   0,5516    0,6014      0,154
  class_conditional  238 ms   Klangio    0,6363  0,5899   0,5472    0,6399      0,110
  class_blind        238 ms   GuitarSet  0,6000  0,3409   0,4054    0,2941      0,098
  class_conditional  238 ms   GuitarSet  0,6061  0,3516   0,4000    0,3137      0,078
```

Ára **1,4 pont** hamis-onset elutasítás (0,974 → 0,960).

### D2 — A MEGTARTOTT halmaz pontosságát külön ellenőriztük, mert az irodalom ezt előírja

Jones, Sanyal és mások (NeurIPS 2020, *Selective Classification Can Magnify Disparities
Across Groups*) és Cresswell és mások (ICLR 2025, *Conformal Prediction Sets Can Cause
Disparate Impact*) ugyanazt mondja: **a megtartás kiegyenlítése nem egyenlíti ki a
megtartott halmaz hibaarányát**, és a hátrányos osztályt akár **rontani** is tudja — a
költség átkerül egy másik tengelyre.

Megmérve: a felütés megtartott **pontossága** −0,005…+0,003 (gyakorlatilag mozdulatlan),
a **recall** +0,020…+0,063. A visszaütés tehát **nem történik meg**, de **kicsiben
látható** — a nyereség a recallon van, és 4–7-szerese a pontosság-veszteségnek.

Ezért a `train_live_3c_settled.py` **mindkét** kapun, **osztályonkénti megtartott
pontossággal és recall-lal** riportál. Egy olyan mérés, ami csak a megtartási arányt
nézi, ezt a cserét nem látná.

### D3 — A szállított asset NEM változik ebben a körben

Az új súlyok `assets/ml/strum_crnn_live_3c_settled.bin`-ben vannak, a paritás-fixtúra
`test/fixtures/crnn_live_3c_settled_parity.json`-ban. A
`strum_crnn_live_3c.bin` **érintetlen**. Az átállítás a bekötő kör dolga, AGENTS.md §9
alatt — és a D4 nyitott tétele előbb döntésre vár.

### D4 — NYITVA: a megtartási kvantilis eleve rossz keret, ha a költségek nem egyeznek

Ugyanaz a kutatás egy **mélyebb** hibát is megnevezett, amit ez az ADR **nem** javít. Ha a
hamis csend (`C_FS`) és a hamis pozitív (`C_FP`) költsége különbözik, akkor a klasszikus,
vitán felüli válasz az, hogy a küszöböt **költség-arányból** vezetjük le, nem megtartási
kvantilisből (Chow saját általánosítása; Tortorella; Pietraszek 2005, *Optimizing
Abstaining Classifiers Using ROC Analysis*; Charoenphakdee és mások 2021, *Classification
with Rejection Based on Cost-Sensitive Classification*).

**Az ADR 0549 D2 mindkét költséget megnevezte prózában** — „az elnyomott ütés levonás, a
fantom ütés kredit" —, **aztán mégis kvantilist választott.** A kvantilis egy
*lefedés-cél*, ami vak arra, melyik hibát kerüljük.

Ez valódi keret-váltás: meg kell mondani a `C_FS / C_FP` arányt (terméki döntés, nem
mérési), és a riportolást érdemes **precision/recall reject curve**-re váltani
(Fischer & Wollstadt 2023), ami pont kiegyensúlyozatlan osztályokra készült. **Külön kör**
— nem csempészem ebbe, mert akkor nem lehetne megmondani, melyik változás mozdította
melyik számot.

**Egy fenntartás ugyanebből az irodalomból:** Jones és mások szerint az osztályonkénti
küszöb lehet, hogy egy **kalibrációs** probléma tünetét kezeli. Egy jövőbeli kör
mérhetné, hogy osztályonkénti Platt/izotonikus kalibráció a P(no-strum)-on jobb-e, mint a
küszöb szétválasztása.

## Következmények

- A `reggae-skank`-szerű, felütés-domináns anyagon a motor csendje mérve **kevesebb**
  ütést vesz el (GuitarSeten 0,098 → 0,078 a letisztult szinten, 0,225 → 0,127 a gyors
  szinten).
- Az ADR 0549 `fittedNoStrumThreshold` / `noStrumThreshold` párja **érintetlen**, mert a
  szállított asset nem változik; a bekötő kör fogja összevezetni őket.
- **A modell felütés-képessége továbbra is a szűk keresztmetszet**, és ezt a kapu nem
  javítja: a GuitarSeten a megtartott felütések pontossága **0,40**, a recall **0,31**.
  Vagyis az ismeretlen játékosok felütéseinek kb. **harmadát** találja meg. Ez az ADR 0553
  adat-diagnózisa, változatlanul.

## Alternatívák, amiket elvetettem

- **Osztály-vak kapu megtartása** (D1): mérve mind a négy cellában rosszabb.
- **Szintenkénti (70/238 ms) kapu**: mérve **nem** segít — a közös kapu 4-ből 3 cellában
  jobb vagy egyenlő volt, tehát a „két skalár ingyen van" ötlet megbukott.
- **Csak a felütés-kvantilis, a maximum nélkül**: ebben a mérésben a kettő **azonos**
  (a felütésnek van a nehezebb farka), de a maximum a **robusztus** megfogalmazás — egy
  jövőbeli modellnél a lefelé osztály is lehet a nehezebb.
- **A költség-arány bevezetése itt** (D4): valódi javítás, de összekeverné a két változást.
