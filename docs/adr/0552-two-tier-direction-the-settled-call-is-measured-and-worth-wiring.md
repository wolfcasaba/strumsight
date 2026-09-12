# ADR 0552 — A kétszintű irány-döntés megérte: a „letisztult" válasz mérve +0,14, és minden irány-szám mellé többségi alapvonal kell

- **Státusz:** elfogadva
- **Dátum:** 2026-09-12
- **Kör:** E18-R29
- **Kapcsolódó:** ADR 0551 (a határidő-lelet, D4 a tervvel), ADR 0550, ADR 0549,
  `docs/eval/guitarset-strum-baseline.md`, `docs/LESSONS.md` L665–L667,
  `ml/experiment_cross_corpus.py`, `ml/probe_direction_budget.py`

## Kontextus

Az ADR 0551 D4 kimondta a tervet — **ideiglenes** irány-válasz 70 ms-nál az élő nyílhoz,
**letisztult** válasz ~250 ms-nál a ritmus-pontozáshoz —, és kimondta azt is, hogy
**nem épül meg**, amíg a nyereség nincs megmérve: a 0,7326 egy **lineáris padló**, nem
ígérvény. Ha a CRNN nem tudja a plusz hangot pontosságra váltani, a vezetékezés semmit nem
ér.

Két dolog mellette szól előre: a szállított 15 frame **már most 238 ms-ot elér** az onset
után (a 70 ms-os levágás ebből 168 ms-ot dob el), és a tensor-alak mindkét esetben
`(15, 128)`. Tehát a letisztult fejhez **nincs új frontend és nincs Dart-paritás munka**,
csak egy második meghívás.

## Előbb a mérce: MINDEN irány-szám mellé többségi alapvonal kell

Ez a kör egy olyan hiányt zár be, ami három kört engedett „javulásról" beszélni anélkül,
hogy bárki megkérdezte volna: **mihez képest.**

```
  többségi alapvonal („mindig lefelé")
    GuitarSet teszt (n=530,  81% lefelé):  le 0,8935  fel 0,0000  macro 0,4468
    Klangio  teszt (n=3721, 62% lefelé):  le 0,7673  fel 0,0000  macro 0,3836

  SZÁLLÍTOTT 3 osztályos CRNN, végponttól végpontig, GuitarSeten:  macro 0,3876
```

**A szállított irány-kimenet a többségi alapvonal ALATT van.** Ez az a szám, amit
mostantól idézni kell, ha valaki megkérdezi, hogy áll az irány-fej.

A repó máshol használja ezt a fegyelmet (a GOV-06 akkord-pontosságot „67,069% a 18,832%-os
többségi alapvonal fölött" formában írta le); az irány-mérésekből kimaradt.

És ugyanez a vizsgálat egy **metrika-csapdát** is kinyitott. Egy orákulum, ami semmit nem
tud az ütésről, csak azt, **melyik felvételből** jött, és a take-ek felütés-aránya szerint
rangsorol, **AUC 0,7386**-ot ér el. Tehát:

> **Ezen a korpuszon a 0,74 alatti AUC semmilyen irány-diszkriminációt nem bizonyít.**
> A macro-F1 az olvasandó metrika.

Ez visszamenőleg érvénytelenít néhány AUC-ot az ADR 0551-ben (a szállított log-mel 0,6523
és a 16 sávos 0,7484 is a nulla-információs szint körül vagy alatta van); a **macro-F1**
számok ott érvényesek.

**Mellékhatásként megbukott a saját mechanizmus-magyarázatom.** Az ADR 0550 D3 az onset
előtti jelet (AUC 0,7128) „váltakozás-tippnek" nevezte. Az egymást követő ütések a
GuitarSeten **61,4%-ban ugyanolyan irányúak** (Klangión 45,4%) — nincs erős váltakozás. A
valódi mechanizmus rosszabb: **128 ms terem, gitár és akkord azonosítja a take-et**, és a
take osztály-aránya elvégzi a többit. A D3 döntése (ne számítsuk be az onset előtti
kontextust) **változatlan, és jobban megalapozott, mint amikor meghoztam.** A `D DU UDU`-ra
hivatkozó érvem viszont pontatlan volt: az 60%-ban váltakozik, vagyis **többet**, mint a
korpusz; a valódi érv az, hogy a kontextus-prior **a korpusz repertoárjára** jellemző.

## A mérés

`ml/experiment_cross_corpus.py` — három tanítókészlet × két határidő, mindegyik cella
**mindkét** tartalék korpuszon. A két határidő-blokk között **csak a levágás** változik:
ugyanaz a `(15, 128)` tensor, ugyanaz a háló, ugyanaz a mag, ugyanaz a csoport szerinti
korai leállítás.

```
  GuitarSet teszt (új játékos ÉS új darab, n=530)      alapvonal 0,4468
    kar                    határidő      le      fel    macro   "fel"-nek mond/valóság
    A csak Klangio          70 ms     0,3856  0,3248  0,3552        0,76/0,19
    A csak Klangio         238 ms     0,3352  0,3477  0,3415        0,82/0,19
    B Klangio+GuitarSet     70 ms     0,5835  0,4199  0,5017        0,64/0,19
    B Klangio+GuitarSet    238 ms     0,8284  0,4609  0,6446        0,29/0,19
    C csak GuitarSet        70 ms     0,8772  0,1364  0,5068        0,06/0,19
    C csak GuitarSet       238 ms     0,8625  0,4402  0,6514        0,20/0,19

  Klangio teszt (új játékos, ugyanaz a rig, n=3721)    alapvonal 0,3836
    A csak Klangio          70 ms     0,3426  0,4734  0,4080        0,73/0,38
    A csak Klangio         238 ms     0,6442  0,5984  0,6213        0,56/0,38
    B Klangio+GuitarSet     70 ms     0,6169  0,5788  0,5979        0,58/0,38
    B Klangio+GuitarSet    238 ms     0,6488  0,6154  0,6321        0,58/0,38
    C csak GuitarSet        70 ms     0,7649  0,0014  0,3832        0,00/0,38
    C csak GuitarSet       238 ms     0,7496  0,3554  0,5525        0,18/0,38
```

## Döntés

### D1 — A kétszintű döntés megépül; a nyereség mérve +0,1429

`B @ 238 ms` a választott konfiguráció: GuitarSet **0,6446**, Klangio **0,6321** —
mindkettő jóval a saját többségi alapvonala fölött (0,4468 / 0,3836), és kalibrált
(„fel"-nek mond 0,29 a valódi 0,19 mellett, illetve 0,58 a 0,38 mellett).

A határidő-emelés önmagában hozza a különbséget a B karon: GuitarSet **0,5017 → 0,6446**
(+0,1429), Klangio 0,5979 → 0,6321 (+0,0342). Architektúra-költség **nulla**.

Kiindulópont: a szállított út **0,3876**, a többségi alapvonal **alatt**. A cél tehát nem
egy csiszolás, hanem az, hogy az irány-kimenet **egyáltalán többet mondjon a találgatásnál**.

### D2 — A két emelő NEM helyettesíti egymást, és ezt külön ki kell mondani

- **Plusz hang egyedül** (A kar): a saját doménben nagyot hoz — Klangio 0,4080 →
  **0,6213** (+0,2133) —, de a korpuszon **átvinni nem tud**: GuitarSet 0,3552 → 0,3415,
  vagyis **semmi**, és mindkettő a 0,4468-as alapvonal **alatt**.
- **Második korpusz egyedül** (B @ 70 ms): átvisz (+0,1465 a GuitarSeten), de a
  hang-költségvetést asztalon hagyja.
- **Együtt**: 0,6446 / 0,6321.

Ebből következik a szabály: *a „több hang" javítja a modellt azon, amit már ismer; a
„több korpusz" teszi átvihetővé.* Aki csak az egyiket építi meg, a mérés szerint az egyik
felét kapja — és ha csak a határidőt emeli, idegen felvételen **nullát**.

### D3 — A „csak GuitarSet" kar NEM nyer, pedig a GuitarSeten a legjobb

`C @ 238 ms` a GuitarSeten 0,6514, hajszálnyival B felett (0,6446). De a Klangión
**0,5525** B 0,6321-ével szemben, és 70 ms-nál teljesen összeomlik („fel"-nek mond **0,00**,
fel-F1 0,0014 — a többségi osztályra esett). A választás tehát B, és a kontroll-kar
pontosan azt tette, amiért bekerült: megmutatta, hogy a Klangio **nem holt súly**.

Itt is áll, amit az ADR 0551 D2 rögzített: **macro-F1 egyedül C-t hozta volna ki
győztesnek** 70 ms-nál. A „fel"-nek mond / valóság oszlop nélkül ez láthatatlan.

### D4 — Az Alpha kapu továbbra sem teljesül, és ezt nem kerekítjük fel

Ch14 §7.2: irány macro-F1 ≥ **0,80**. A választott konfiguráció **0,6446**. A lineáris
padló 238 ms-on 0,7326, tehát a CRNN **0,088**-cal van alatta — **ugyanannyival, mint
70 ms-nál** (0,5017 vs 0,5885). Ez önmagában informatív: a CRNN a plusz hangot
**ugyanolyan hatékonysággal** váltja pontosságra, vagyis a nyereség valódi képesség, nem
műtermék — de a maradék rés is ugyanott van.

## Következmények

- **Bekötő kör kell** (nem ez): a `StrumDirectionClassifier` / `StrumAnalyzer` sínen egy
  második, késleltetett osztályozás; a nyíl az ideiglenes választ kapja, a
  **ritmus-pontozás** a letisztultat. A pontozás az, ahol a hamis válasz fáj (ADR 0549 D2:
  az elnyomott ütés levonás, a fantom ütés kredit) — és épp ott nincs latencia-igény.
- A bekötő kör **AGENTS.md §9** alá esik (fixtúra + property + paritás + valós-audio
  mérés), és a szállított 3 osztályos asset újratanítását igényli a választott
  konfigurációval (a jelenlegi kísérletek **2 osztályosak**: a no-strum fej külön
  képesség, saját kalibrált kapuval — ADR 0549 —, és a kettőt összekeverve nem lehetne
  megmondani, melyik változás mozdította melyik számot).
- A külső korpuszok **nincsenek verziókövetve** (`ml/data/`, `ml/*.npz` gitignorált; a
  GuitarSetet helyben olvassuk, nem kopírozzuk), tehát ezek elkötelezett riportok, nem
  CI-kapuk.

## Alternatívák, amiket elvetettem

- **A nyíl késleltetése 250 ms-ra**: az élő visszajelzés lényegét rontja. A kétszintű
  döntés ugyanezt a nyereséget adja ott, ahol a pontosság fontos.
- **Csak a határidő emelése, a korpusz nélkül** (A @ 238 ms): mérve **nullát** hoz idegen
  felvételen, és a többségi alapvonal alatt marad.
- **Csak a korpusz, a határidő nélkül** (B @ 70 ms): a mérhető nyereség fele.
- **A C kar szállítása**, mert a GuitarSeten hajszállal jobb: a Klangión 0,08-cal rosszabb,
  és 70 ms-nál összeomlik. Egy korpuszra választani pontosan az a hiba, amit az ADR 0549
  és az ADR 0550 is leírt.
- **28 frame-es geometria** a 238 ms eléréséhez: nem kell — a 15 frame már eléri —, és
  mérve rosszabb is (ADR 0551).
