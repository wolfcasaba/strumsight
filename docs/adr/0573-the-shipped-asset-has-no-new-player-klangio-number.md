# ADR 0573 — A szállított assetnek NINCS új-játékos Klangio száma, és ezért az ADR 0569 korlátja és elfogadási kritériuma egyaránt elérhetetlen volt

- **Státusz:** elfogadva (mérés + két **korábbi állítás visszavonása**; szállított viselkedés
  nem változik)
- **Dátum:** 2026-09-12
- **Kör:** E18-R44
- **Kapcsolódó:** ADR 0569 (amelynek **D2 korlátját és D4 kritériumát** ez visszavonja),
  ADR 0572 (ami a 0569-re épült — a D1 mérése áll, a belőle olvasott rangsor nem),
  ADR 0550 (kereszt-korpusz transzfer), ADR 0575 (a recept-létra, ami a helyére lép),
  `ml/model_card.json` (r172 LOGO), `docs/rag/chunks/018-strum-ml-pipeline.md`,
  `ml/experiment_recipe_ladder.py`, `docs/LESSONS.md` L687, L688

## Kontextus

Az ADR 0569 D4 elfogadási kritériumot írt fel, és tizenegy kör tanulsága volt benne:

> „Egy jelölt asset akkor szállítható, ha **a szállítottat minden korpuszon legyőzi vagy
> hozza**, egy műszerrel mérve, és a fold-torzítás iránya minden sorra kimondva."

Az ADR 0569 D1 ehhez a fold-torzítás **irányát** végiggondolta. Amit nem tett meg — és amit a
repó **saját mérése** már tartalmazott —, az a torzítás **nagysága** és **fajtája**.

## Döntés

### D1 — Mért tény a splitről: a szállított asset a 4-es gitáros 27 felvételéből 22-t TANULTA

A `klangio.split_by_recording` a **felvételek** 20%-át tartja ki, seed 42. Megszámolva:

```
  gitáros   TRAIN felvétel   EVAL felvétel      TRAIN pengetés   EVAL pengetés
  1              21                6                3426             643
  2              23                5                3431             546
  4              22                5                2897             824
```

**Mind a három gitáros mindkét oldalon van.** Tehát:

- a **fold A** (a 4-es gitáros mind a 3721 pengetése) a szállított asset számára nem csak
  „torzít" — a sorok **78%-a literálisan a tanítókészletében van**;
- a **fold B** (a saját eval foldja, 2013 pengetés) **felvétel**-diszjunkt, de **nem
  játékos**-diszjunkt: mind a három gitáros szerepel a tanításban.

**A szállított assetnek tehát egyetlen új-játékos Klangio száma sincs, és a splitje nem is
tud ilyet előállítani.** Ez nem mérés kérdése: a split szerkezete.

### D2 — A repó ezt MÁR megmérte, ugyanezen a foldon, jóval korábban

`ml/model_card.json`, r172, leave-one-guitarist-out CV, **live-70 ms**, ugyanaz a három
gitáros — és a 4-es fold `n_test` értéke **3721**, azaz bitre ugyanaz a fold A:

```
  kihagyott gitáros    test_acc (2-osztályú iránypontosság)
  1                       0,6508
  2                       0,6387
  4                       0,5289     <- a LEGROSSZABB fold
  átlag                   0,6061 ± 0,0548
```

Összevetési pontként a same-player live-70 ms szám **~0,799** — de ez a **régi**, r172 **előtti**
érték (`restore-best-over-epochs`, in-sample kalibrálva), tehát maga is optimista. A
`docs/rag/chunks/018` a maga szavaival: *„a legrosszabb ismeretlen gitáros közel pénzfeldobás
az up/down-on"*, és *„a ~15 pontos same-player→new-player esés a valódi telepítési rés"* — a
„~15 pont" a chunk összefoglalása a két konfigurációra (batch 0,852 → 0,707 = 14,5 pont);
live-70 ms-on a 0,799 → 0,6061 **~19 pont**.

Tehát: a **settled** split pontosan azt az egy gitárost tartja ki, akit a repó saját mérése a
három közül a **legnehezebbnek** mért — és a szállított asset ugyanezen a foldon azért áll
0,9490-en, mert 22 felvételét tanulta.

**Ez nem új információ volt. Tizenegy kör óta a model cardban állt, és nem néztem meg.**

### D3 — Mérve: a szállított RECEPT a 4-es gitáros nélkül 0,4220, ugyanazon az ütéshalmazon

`ml/experiment_recipe_ladder.py` R0 arm — a szállított recept (Klangio, 70 ms, regularizáció
nélkül, `val_accuracy`/40/bs32), a **settled** splitre átültetve, egy műszer, egy pontozó:

```
  ugyanaz a 3721 pengetés, irány-macro-F1, KÖZÖS kapukon 0,439 / 0,650 / 0,850
  szállított ASSET  (a 4-es gitáros 22/27-ét tanulta)   0,9481 / 0,9484 / 0,9490
  R0  szállított RECEPT (a 4-es gitárost kihagyta)      0,4039 / 0,4132 / 0,4220
```

Kapu-illesztve is **0,527** a rés. Nem kapu-műtermék.

### D4 — De a 0,527 FELSŐ korlát, nem becslés — és ezt a saját kontrollom mondja

Az R0 nem „a szállított asset mínusz a szivárgás". Két dolog is eltér:

1. **A Klangiónak HÁROM gitárosa van.** Egyet kihagyni nem „ugyanaz a recept más splitten",
   hanem a **játékos-diverzitás harmadának** elvétele. A split ezen a korpuszon nem
   független faktor.
2. És van egy sejt, ami **mindkettőnek egyformán ismeretlen** — a GuitarSet, amit egyik sem
   látott. Ott:

```
  GuitarSet @70, irány-macro-F1, közös kapukon
  szállított ASSET   0,3147 / 0,3244 / 0,3340
  R0                 0,1257 / 0,1347 / 0,1386
```

**Az R0 ezen a tiszta sejten is gyengébb, 0,195-tel.** Tehát az R0 önmagában is gyengébb
futás, és a 0,527-ből nem tudom szétválasztani a memorizálást a futás gyengeségétől.

Amit viszont a D2 ad: egy **független**, más korszakban, más scripttel, 2-osztályú modellel
készült mérés **ugyanezen a 3721 pengetésen**, ami szintén **0,5289** (iránypontosság) — azaz
közel pénzfeldobás. Két független tanítás, egyik sem látta a 4-es gitárost, mindkettő a
mélyben. **A szint tehát a foldé és a kitettségé, nem az R0 futásáé.**

### D5 — Ezért az ADR 0569 D2 korlátja VISSZAVONVA

Az ADR 0569 D2 így érvelt: a fold B-n a **settled** az előnyben lévő (azokon a felvételeken
tanult), és mégis veszít, tehát *„a valódi held-out különbség legalább 0,052"*.

Ez az érvelés a szállított asset fold-B-beli **0,7950**-ét a becsületes held-out szintjének
vette. A D1 szerint az **same-player** szint, amit a D2 szerint a repó ~15 ponttal az
új-játékos szint fölé árazott. **A korlát tehát nem áll** — nem azért, mert a 0,7950 hamis
(valódi, reprodukálható szám), hanem mert nem az, amivel összevetették.

### D6 — És az ADR 0569 D4 kritériuma SZERKEZETILEG teljesíthetetlen

Soroljuk fel az összes elérhető sejtet egy „mindkét korpuszon tanító jelölt" és a szállított
asset között:

```
  sejt                             SHIP            jelölt            tiszta?
  Klangio, bármely fold            same-player     új-játékos        NEM — SHIP-nek kedvez
  GuitarSet, Klangio-only jelölt   nem látta       nem látta         IGEN
  GuitarSet, mindkét korpuszos     nem látta       TANULTA           NEM — a jelöltnek kedvez
```

**Nincs olyan sejt, ahol egy mindkét korpuszon tanító jelölt tisztán összevethető a
szállítottal.** A „legyőzni a szállítottat minden korpuszon" tehát nem elfogadási kritérium,
hanem **feloldhatatlan feltétel**: minden Klangio-sejt a szállítottnak kedvez, minden
GuitarSet-sejt a jelöltnek. Egy ilyen kritérium **minden** jelöltet örökre blokkol, és nem
azért, mert a jelöltek rosszak.

Ez az ADR 0569 D4 szándékát nem érvényteleníti — *„ablációs alapvonalhoz mért javulás nem
elfogadási kritérium"* **áll** (L684). Csak a helyére írt kritérium volt mérhetetlen.

### D7 — A helyére két dolog lép

1. **Recept-vs-recept EGY splitten**, egy műszerrel: ez az ADR 0575 létrája, és **ma
   elérhető**. A szállított asset ebben nem bíró, hanem egy sor a táblában, a kitettségével
   kiírva.
2. **Egy HARMADIK korpusz, amit egyik sem látott** — ez az egyetlen szerkezeti feloldás a
   SHIP-vs-jelölt kérdésre. Ma ez a HANDOFF listáján a **felhasználó címkézett felvétele** és
   a **Guitar-TECHS** ingesztálás. Ettől a körtől kezdve ez nem „jó lenne", hanem a
   szállítási döntés **szerkezeti előfeltétele**.

## Következmények

- Az ADR 0572 **D1 mérése** (szállított asset, fold B, 0,7950 → 0,5495/0,5578 csonkítatlan
  ablakon) **áll** — az **soron belüli** összevetés, ugyanaz a modell, ugyanazok az ablakok.
  Amit az ADR 0572 a **D2 rangsorából** olvasott (melyik asset „jobb" Klangión), az az
  ADR 0575-re vár.
- Az ADR 0569 D5 felsorolása (mely próbák a settled modellt jellemzik) **áll**.
- A `ml/experiment_recipe_ladder.py` minden sorra kiírja, melyik korpuszt és melyik
  truncationt mérte, és a `shipped` sort a kitettségével együtt.

## Amit NEM állítunk

- **Nem állítjuk, hogy a szállított asset rossz.** Azt állítjuk, hogy a Klangio-számai
  **same-player** számok, és hogy új-játékos számot a splitje nem tud adni. Ez a szállítást
  nem kérdőjelezi meg — a 0549–0555 kör a GuitarSeten **in situ** is megmérte.
- **Nem tudjuk szétválasztani** a 0,527-ben a memorizálást a futás gyengeségétől (D4).
- **A D2 metrikája MÁS**: 2-osztályú iránypontosság (`test_acc`), nem 3-osztályú kapuzott
  macro-F1. A 0,5289 és a 0,4220 **nem** ugyanaz a szám, és nem is vetjük össze — a D2 a
  **szint nagyságrendjét** és a fold sorrendjét hitelesíti, nem az értéket.
- **Nincs új in-situ mérés** ebben a körben; a söprés-eszköz nem futott.
- **Egy seed.** Az R0 seed 42. A D2 független korroborációja miatt a szint nem seed-kérdés,
  de az R0 pontos értéke az.
