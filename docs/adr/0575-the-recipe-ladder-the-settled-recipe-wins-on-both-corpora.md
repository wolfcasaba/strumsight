# ADR 0575 — A recept-létra: a két recept HAT dologban tér el, és egy illesztett splitten a settled recept MINDKÉT korpuszon győz (+0,105 Klangio, +0,345 GuitarSet)

- **Státusz:** elfogadva (mérés; az ADR 0569 **következtetését** megfordítja, a mechanizmus-listáját
  **kizárja**; semmi nem kerül felkapcsolásra)
- **Dátum:** 2026-09-12
- **Kör:** E18-R44
- **Kapcsolódó:** ADR 0573 (miért ez a létra a helyes műszer, és miért nem bíró a szállított
  asset), ADR 0569 (a következtetés, amit ez megfordít), ADR 0554 (a két-levágásos döntés —
  **más modell-családon** mérve), ADR 0549 (a kapu-szabály), ADR 0572,
  `ml/experiment_recipe_ladder.py`, `docs/LESSONS.md` L687, L688

## Kontextus

Az ADR 0569 azt állapította meg, hogy a settled asset a **telepítési** korpuszon visszaesik, és
a mechanizmus-jelölteket így sorolta fel: *„a guitarist-diszjunkt split nehezebb célja, a
GuitarSet-adat domináns hatása, a két korpusz mikrofon-karaktere, vagy a kapacitás"*.

A két tanító scriptet egymás ellen olvasva ez a lista **hiányos**. A `train_live_3c.py` és a
`train_live_3c_settled.py` **hat** dologban tér el:

```
  1. KORPUSZ         csak Klangio              vs  Klangio + GuitarSet
  2. LEVÁGÁS         csak 70 ms                vs  70 ms ÉS csonkítatlan
  3. REGULARIZÁCIÓ   nincs (dropout=0, l2=0)   vs  AUG_REG (dropout .25 / rec .15 / l2 1e-4)
  4. FIT-MENETREND   val_accuracy, 40 ep, bs32 vs  val_loss, 60 ep, bs64
  5. SPLIT           felvételek random 20%-a   vs  4-es gitáros + GuitarSet játékos × darab
  6. VAL-PROTOKOLL   az eval fold EGYBEN a     vs  csoport-szerinti 20% a TRAIN-ből
                     korai-leállás ÉS a
                     kapu-kalibrálás foldja
```

Az arc mindig **(1)-et és (2)-t** nevezte meg a különbségnek. A **(3)** különösen olyan fajta
változás, ami az in-domain pontosságot a generalizációra váltja — **bármelyik** irányban —, és
soha nem volt a listán.

## Döntés

### D1 — A létra: öt kar, mindegyik EGY faktorral tér el az előzőtől, egy splitten

`ml/experiment_recipe_ladder.py`. **Fixen tartva**, hogy ne legyenek rejtett faktorok: a split,
a val-protokoll (csoport-szerinti, a TRAIN-ből), a normalizálási statisztika és az
osztálysúlyok **csak a fit foldból**, a kapu-szabály (class-blind — ADR 0549-é, ami szállít), a
pontozó (`score_direction`, tehát az elnyomott pengetés **nincs hívás**, nem hibás hívás), és a
kiértékelő sejtek.

Az **(5)** és **(6)** ebben a létrában **nem változtatható**: a settled split tartása az, ami
egyáltalán létrehoz egy tiszta Klangio held-out foldot, a szállított protokoll eval foldja
pedig egyszerre a korai-leállás és a kapu-kalibrálás foldja, tehát a reprodukálása a held-out
sejtet **megszüntetné**. Ezek kimondott, nem mért különbségek maradnak.

### D2 — Mérve: a telepítési korpuszon (Klangio @70, a tier, ahol a nyíl és a kapu él)

```
  arm  mi változott                        Klangio@70   delta      GuitarSet@70   delta
  R0   a SZÁLLÍTOTT recept                   0,4354                  0,1623
  R1   + a fit-menetrend                     0,4808   +0,0454        0,1506   −0,0117
  R2   + regularizáció                       0,4591   −0,0217        0,2504   +0,0998
  R3   + GuitarSet                           0,5401   +0,0810        0,5596   +0,3092
  R4   + a második levágás = a SETTLED       0,5405   +0,0004        0,5071   −0,0525
                                    nettó:           +0,1051                 +0,3448
```

És a **csonkítatlan** tier, amit csak az R4 tud törvényesen szolgálni (a saját, arra a
levágásra kalibrált kapuján):

```
  sejt                  R3 (csak 70 ms-on tanult)      R4 (mindkettőn)
  Klangio @full         0,4231  [KERESZT-TIER]         0,6112
  GuitarSet @full       0,5674  [KERESZT-TIER]         0,5745
```

**Tehát: egy illesztett splitten a settled recept a szállított receptet MINDKÉT korpuszon
legyőzi** — Klangion +0,1051, GuitarSeten +0,3448 —, **és a második levágás a 70 ms-os tieren
nem kerül semmibe** (+0,0004), miközben a 238 ms-os tiert **megvásárolja** (0,4231 → 0,6112).

### D3 — Ez megfordítja az ADR 0569 következtetését, és kizárja a mechanizmus-listáját

Az ADR 0569 fő állítása — *„a settled asset a telepítési korpuszon visszaesik"* — a **szállított
asset same-player számához** mérve állt elő (ADR 0573). Illesztett splitten **nincs
visszaesés**: a settled recept nyer.

És a mechanizmus-lista két tagja **mérve kizárva**:

- **„a GuitarSet-adat domináns hatása"** — a GuitarSet hozzáadása a **Klangiót** is emeli,
  **+0,0810**-nel (R2 → R3). A kereszt-korpusz adat nem elvesz a telepítési korpusztól, hanem ad.
- **„a guitarist-diszjunkt split nehezebb célja"** — igaz, de nem a settled recept ellen szól:
  minden kar ezen a splitten van, tehát a nehézség **kiesik** a létra deltáiból.

A mikrofon-karakter és a kapacitás **nincs mérve**, és nem is állítunk róluk semmit (L681).

### D4 — A REGULARIZÁCIÓ nem ingyen van, és a cserét ki kell írni

Az R1 → R2 lépés a Klangión **−0,0217**, a GuitarSeten **+0,0998**. Vagyis a regularizáció a
kereszt-korpusz transzferért fizet in-domain pontossággal — **pont az a csere, amit az
ADR 0550 a direction-defekt diagnózisának nevezett**. Ez nem volt a 0569 listáján, és most
mérve van, előjellel és mindkét oldallal.

### D5 — A ZAJPADLÓ, mérve — és ez korlátozza, mit olvashatok ki a saját létrámból

Az R4 **ugyanaz a recept, ugyanaz a split, ugyanaz a seed (42)**, mint amivel a settled
**asset** készült. Mégsem ugyanaz a szám: R4 Klangio@70 **0,5405**, az asset saját
class-blind jelentése **0,4923**.

Végigmértem, hogy a kapu magyarázza-e. **Nem:** a settled asseten a kapu 0,1245-ről egészen a
**kapu nélküliig** emelve is csak +0,030-at ad (0,4923 → 0,5219):

```
  settled asset, 4-es gitáros (n=3721)    macro@70   macro@full
  0,1245 (a szállított class_blind)        0,4923      0,6268
  0,2929 (a class_conditional)             0,5055      0,6363
  0,8500                                   0,5141      0,6484
  nincs kapu                               0,5219      0,6568
```

Tehát a 0,048 nagyobb része **futás-közi szórás két script között** ugyanazon a seeden (más
sor-sorrend → más batch-összetétel a `shuffle=True` alatt). **Ez egy mért zajpadló**, és
megmondja, mit NEM olvashatok ki egy seedből:

- **Megbízható** (a szóráson túl): a GuitarSet hozzáadása (+0,0810), a nettó R0 → R4
  (+0,1051 / +0,3448), és a csonkítatlan tier megvásárlása (0,4231 → 0,6112).
- **NEM feloldható egy seeden**: a fit-menetrend (+0,0454), a regularizáció (−0,0217 Klangión),
  és a második levágás 70 ms-os hatása (+0,0004). A D4 GuitarSet-oldala (+0,0998) a határon van.

A következő kör dolga ezeket a `honest_eval.STD_SEEDS = [42, 1, 2]`-vel megismételni.

### D6 — Az ADR 0554 D1-gyel NINCS ellentmondás, mert más modell-családon mérte

Az ADR 0554 azt állította, hogy a mindkét levágáson tanított kar a 70 ms-os tieren **legyőzi**
a saját specialistáját (GuitarSet 0,5934 vs 0,4690; Klangio 0,5828 vs 0,4879). Az én R3 → R4
lépésem 70 ms-on **döntetlen** Klangión (+0,0004) és kicsit **veszít** GuitarSeten (−0,0525).

Ez **nem** cáfolat. Az `experiment_deadline_augmentation.py` arm A/B/C **`n_classes=2`**, azaz
**nincs no-strum fej és nincs kapu** (`predicted = ...argmax(axis=1)`); a táblája „0,59/0,19"
oszlopa `called_up`/`truth_up`, nem elnyomás. Az én karjaim 3-osztályúak, kapuval, és az
elnyomott pengetés hibának számít. **Két különböző mennyiség** — összevetni őket pont az
[[L682]]-hiba lenne.

Amit tehát ez a kör hozzáad: az ADR 0554 központi tervezési döntését (egy asset, mindkét
levágás) most **a szállító modell-családon** — 3 osztály, reject fej, kapu — is megmértük, és
ott a 70 ms-os tieren **döntetlen**, nem győzelem. A döntés **áll** (a 238 ms-os tier ingyen
jön), csak az érv gyengébb: a határidő-augmentáció itt nem *regularizál*, hanem **nem kerül
semmibe**.

### D7 — Egy kódlelet mellékesen: a `tier` tömböt kiszámolja, megindokolja, és soha nem használja

A `train_live_3c_settled.py` felépíti a `pool_tier` tömböt, és odaír egy indoklást:

> *„a no-strum GATE egy Dart-oldali skalár, nem az asset része, tehát **tierenként ingyen
> kalibrálható** — és a P(no-strum)-nak semmi oka egyformán oszlani 70 ms és 238 ms audió
> mellett. Egy asset (ADR 0554) nem jelent egy küszöböt."*

Aztán a 157. sorban átveszi (`X, y, groups, tier, tests = ...`) és **többé nem hivatkozik rá**:
a `class_blind` kapu a **két levágás val sorain összevontan** számolódik. Ugyanaz a család, mint
az ADR 0568 „fixtúra, amit senki nem olvas", és mint az L685 „egy sötét konstans is állít
valamit": **egy változó, amit kiszámolnak, megindokolnak, és nem fogyasztanak el.**

A D5 szerint a **költsége kicsi és korlátos** (legfeljebb ~0,03, és a monoton kapu-görbe
szerint az „optimum" a kapu nélküli eset, ami az ADR 0549 fantom-cseréjét nyitja újra, nem egy
ingyen nyereséget). Tehát **helyességi** javítás, nem kar.

### D8 — Amit ez a kör ELDÖNT, és amit NEM

**Eldönti a RECEPT kérdést:** illesztett splitten, egy műszerrel, a settled recept jobb
mindkét korpuszon, és a második levágás nem kerül semmibe.

**NEM dönti el a SZÁLLÍTÁSI kérdést.** Az ADR 0573 D6 szerint a szállított asset és egy
mindkét korpuszon tanító jelölt között **nincs dönthető sejt**. A létra a *receptekről* szól,
nem arról, hogy a meglévő `strum_crnn_live_3c_settled.bin` kiváltsa-e a szállítottat. Ahhoz egy
**harmadik korpusz** kell, amit egyik sem látott.

## Következmények

- Az ADR 0569 által nyitott „egy asset, ami mindkét korpuszon legyőzi a szállítottat" kör
  **specifikációja megváltozik**: nem új asset kell, hanem a **meglévő** asset tisztességes
  összevetése egy harmadik korpuszon — plusz a D5 seed-ismétlés.
- A `settledTier` marad **false**. Semmi nem kerül felkapcsolásra.
- A `ml/experiment_recipe_ladder.py` bármely további karral bővíthető (az R5 — a settled recept
  regularizáció **nélkül** — már definiálva van benne, mérve nincs).

## Amit NEM állítunk

- **Egy seed.** Lásd D5: a lépés-delták fele a zajpadló alatt van.
- **Orákulum-ablakok**, nem in situ. A Dart söprés nem futott ebben a körben.
- **Az R0 nem „a szállított asset mínusz a szivárgás"** (ADR 0573 D4): a Klangiónak három
  gitárosa van, egyet kihagyni a játékos-diverzitás harmadát veszi el, és az R0 a tiszta
  GuitarSet-sejten is gyengébb a szállítottnál.
- **A `full` sejtek 70 ms-on tanított karoknál KERESZT-TIER** cellák, nem összevetések.
- **A mikrofon-karaktert és a kapacitást** nem mértük (D3).
- **A GuitarSet-sejt a R3/R4 felé torzít** (ott tanultak), a szállított asset felé nem — ezért
  a 0,5596 / 0,5071 **nem** olvasható a szállított 0,3340 ellenében (ADR 0573 D6).
