# ADR 0569 — A settled asset a TELEPÍTÉSI korpuszon visszaesik: az ADR 0567 D3 csere-javaslata visszavonva

- **Státusz:** elfogadva **mint mérés**; a **D2 korlátja** és a **D4 elfogadási
  kritériuma** az **ADR 0573-ban visszavonva** (a szállított asset Klangio-számai
  *same-player* számok: a splitje felvétel-diszjunkt, nem játékos-diszjunkt, és a 4-es gitáros
  27 felvételéből 22-t tanult). A D1 fold-táblája, a D2 **számai** és a D5 felsorolása áll.
  Szállított viselkedés nem változik.
- **Dátum:** 2026-09-12
- **Kör:** E18-R43
- **Kapcsolódó:** ADR 0567 (amelynek D3-át ez **visszavonja**), ADR 0554 (egy asset mindkét
  szintre — és az ott használt **belső** alapvonal), ADR 0555, ADR 0566, ADR 0568,
  `ml/read_ssml.py`, `ml/probe_asset_swap_klangio.py`, `docs/LESSONS.md` L684

## Kontextus

Az ADR 0567 D4 nyitva hagyta a bekötés utolsó lábát: **a Klangio-oldalt**. Az ok kimondott
volt — a szállított asset Klangion **egyedül** tanult, a settled Klangio **+ GuitarSeten**,
tehát a GuitarSeten mért **+0,186** lehet **csere**, nem nyereség.

Az in-situ változat ebben a környezetben nem elérhető: a Klangio korpusz **nincs a gépen**, a
Dart pipeline pedig audiót fogyaszt, nem gyorsítótárazott ablakot. A **mögötte lévő kérdés**
viszont megválaszolható, mert az `ml/read_ssml.py` (ebben a körben) mindkét `.bin`-t be tudja
tölteni **ugyanabba** a Keras-gráfba — egy műszer, két asset, ugyanazok az ablakok. Ez épp
az, amit az L682 §1 megkövetel.

## Döntés

### D1 — A két asset split-je MÁS, ezért minden Klangio-fold torzít, és a torzítás IRÁNYA a műszer

A szállított asset (`ml/train_live_3c.py`) a **felvételek** random 20%-át tartotta ki
(`split_by_recording`, seed 42). A settled asset (`ml/train_live_3c_settled.py`) a **4-es
gitárost** teljesen. Tehát:

```
  fold                     a settled számára      a szállított számára      torzít
  A  gitáros 4             tiszta held-out        LÁTTA tanításkor          a szállított felé
  B  a szállított evalja    LÁTTA tanításkor       tiszta held-out           a settled felé
  C  A és B                 tiszta                 tiszta ABLAKOK, de        a szállított felé
                                                   látta a gitáros többi
                                                   felvételét
```

**Nincs torzításmentes sejt, és a C NEM az** — ez a kör először pont ebbe a csapdába lépett,
ezért áll itt. A C-ben egyik modell sem *memorizálta* ezeket a mintákat, de a két split
**fajtájában** különbözik: a szállított látta a 4-es gitáros **többi** felvételét, a settled
egyet sem. *„Egyik sem tanult ezeken az ablakokon" nem azonos azzal, hogy „egyformán
ismeretlen".*

Mindhárom fold **ugyanazon a mintán** hasonlítja a két modellt, tehát a fold nehézsége nem
játszik — csak a tanítási kitettség, aminek az **irányát** ismerjük. Ez elég a döntéshez.

### D2 — Mérve: a settled asset Klangion ROSSZABB, és a szoros korlát a B foldról jön

Irány-macro-F1 valódi pengetéseken, mindkét asset a **saját** javasolt kapuján (a szállított
0,85, a settled az ADR 0567 D3 szerinti 0,439); az elnyomott ütés „nincs hívás", nem hibás
hívás — a repó saját `score_direction` konvenciója:

```
  fold                    n     szállított@0,85   settled@0,439    delta
  A  gitáros 4          3721        0,9490            0,5072      −0,4418
  B  a szállított evalja 2013       0,7950            0,7428      −0,0521
  C  egyik sem látta     824        0,8013            0,5359      −0,2653
```

**Olvasd a B-t, és fordítva:** ott a **settled** az előnyben lévő (azokon a felvételeken
tanult), és **mégis veszít**. Ebből következik, hogy a valódi held-out különbség **legalább
0,052** — a 0,2653 (C) és a 0,4418 (A) pedig azt mutatja, hogy a kitettség elvételével a rés
**nő**, nem csökken.

> **VISSZAVONVA (ADR 0573 D5).** Ez az érvelés a szállított asset fold-B-beli **0,7950**-ét a
> becsületes held-out szintjének vette. Nem az: a `split_by_recording` **felvétel**-diszjunkt,
> de **nem játékos**-diszjunkt — mind a három gitáros mindkét oldalon van —, tehát a 0,7950
> **same-player, új-felvétel** szám. A repó saját r172 LOGO mérése (`ml/model_card.json`,
> ugyanez a live-70 ms konfiguráció) a same-player→új-játékos esést **~15 pontra** árazta, és a
> 4-es gitárost mérte a három közül a **legrosszabbnak** (`test_acc` 0,5289, `n_test`=3721 —
> bitre a fold A). A „legalább 0,052" korlát tehát **nem áll**. A számok a táblában
> reprodukálhatók és érvényesek; amit nem bírnak el, az a belőlük olvasott **rangsor**.

Lebontva, közös kapun, hogy a modell és a kapu szétválhasson:

```
  fold                  asset        kapu     macro     le       fel    megtartás
  C egyik sem látta     szállított   0,850    0,8013   0,8102   0,7923   0,9636
  C egyik sem látta     settled      0,439    0,5359   0,4970   0,5749   0,8240
  C egyik sem látta     settled      0,850    0,5507   0,4985   0,6030   0,8847
```

A settled **mindkét** osztályon rosszabb (nem osztály-eltolódás), **és** kevesebb valódi
pengetést tart meg (0,824 vs 0,964). A hamis onseteken közel egyenlők (elnyomás 0,9516 vs
0,9614 az összes negatívon).

### D3 — Ezért az ADR 0567 D3 csere-javaslata VISSZAVONVA

Az ADR 0567 D3 azt írta: „a szállítható javaslat a csere **és** a kapu visszaállítása
0,439-re". Ez a mérés azt mondja, hogy a csere **korpusz-csere**:

```
  GuitarSet (ismeretlen játékos ÉS darab, IN SITU)   0,3872 → 0,5728   +0,186
  Klangio   (ugyanaz a fold, a settled előnyben)     0,7950 → 0,7428   −0,052  (legalább)
```

És a döntést nem a két szám nagysága hozza meg, hanem az, hogy **melyik korpusz hasonlít a
telepítésre**. A Klangio felvételei `recording_<id>_phone.wav` — a `ml/klangio.py` saját
szavaival **„our deployment condition"**. A GuitarSet mikrofon-tömb stúdióban. Egy
Android-app a **telefon mikrofonját** használja.

**Tehát: az assetet nem cseréljük.** Nem azért, mert a GuitarSet-nyereség nem valódi — az
ADR 0567 in-situ mérése áll —, hanem mert az a nyereség azon a korpuszon van, ami **nem** a
telepítési feltétel, és a veszteség azon, ami **igen**.

### D4 — A szerkezeti hiányosság: egy jelölt assetet sosem hasonlítottunk a SZÁLLÍTOTTHOZ

Az ADR 0554 helyesen állította, hogy a GuitarSet hozzáadása **mindkét** tartalék korpuszt
emelte — de a **saját belső alapvonalához** mérve (GuitarSet 0,4468, Klangio 0,3836,
ugyanaz a szerelvény, ugyanazok a splitek). Ez egy **adat-ablációs** állítás, és igaz.

Amit **soha senki nem mért**: jelölt asset **a szállított assethez**, egy műszerrel, minden
korpuszon. Ezért tudott egy asset tizenegy körön át „jobbnak" látszani úgy, hogy a
telepítési korpuszon rosszabb. (És azért nem volt mérhető, mert a szállított asset súlyai
csak `.bin`-ként léteznek — a tanítási artefaktumai nincsenek meg —, és **nem volt
olvasó**. Most van: `ml/read_ssml.py`.)

**Elfogadási kritérium innentől:** egy jelölt asset akkor szállítható, ha **a szállítottat
minden korpuszon legyőzi vagy hozza**, egy műszerrel mérve, és a fold-torzítás iránya
minden sorra kimondva. Ablációs alapvonalhoz mért javulás **nem** elfogadási kritérium.

> **VISSZAVONVA (ADR 0573 D6, LESSONS L688).** A második mondat **áll**. Az első viszont
> **szerkezetileg teljesíthetetlen**, mert egyetlen dönthető sejt sincs:
>
> ```
>   sejt                                 SHIP          jelölt         dönthető?
>   Klangio, BÁRMELY fold                same-player   új-játékos     NEM — SHIP-nek kedvez
>   GuitarSet, Klangio-only jelölt       nem látta     nem látta      IGEN
>   GuitarSet, mindkét korpuszos jelölt  nem látta     TANULTA        NEM — a jelöltnek kedvez
> ```
>
> Minden Klangio-sejt a szállítottnak kedvez (mert a splitje nem ad új-játékos számot), minden
> GuitarSet-sejt a jelöltnek. Egy ilyen kritérium **minden** jelöltet örökre blokkol,
> függetlenül attól, jó-e. A helyére: **(1)** recept-vs-recept **egy** splitten, ahol a
> szállított asset nem bíró, hanem egy sor a táblában a kitettségével (ADR 0575 létrája); és
> **(2)** egy **harmadik korpusz**, amit egyik modell sem látott — ez az egyetlen szerkezeti
> feloldás a SHIP-vs-jelölt kérdésre.

### D5 — Amit ez a kör az ARC többi méréséről mond

A settled asset súlyai (`ml/weights_live_3c_settled.npz`) az, amit **minden** érintett
Python-próba betölt: `probe_direction_fusion.py`, `probe_settled_tier_value.py`,
`probe_gate_window_jitter.py`, `probe_gate_cost_frame.py`. Tehát az alábbiak a **settled**
modellt jellemzik, nem a szállítottat, és ezt ki kell mondani:

- **ADR 0563** (a letisztult tier +0,0551 macrót ér margó 0,30 felett) — a settled modellen,
  GuitarSeten;
- **ADR 0566 D2** reject curve-jei (a FEL precizitás 0,206 → 0,043 kapu nélkül, a macro
  csúcsa 0,439-nél) — a settled modellen;
- **ADR 0557–0562** metrikus csatorna AUC-jai az **akusztikus** oldalon (a 0,7484) — a
  settled modellen. A metrikus csatorna saját 0,9797-e modell-független (ütem-fázis), azt ez
  nem érinti.

Ez **nem** érvényteleníti őket: mindegyik a maga modelljéről igaz állítás. De amíg a
szállított asset marad, a szállított útra vonatkozó előrejelzésük **nem igazolt**, és a
két-tier bekötése előtt az ADR 0563 mérését a **szállított** assetn meg kell ismételni.

## Következmények

- A bekötő kör **nem** indul a jelen assettel. A következő adat/tanító kör célja egy asset,
  ami **mindkét** korpuszon legyőzi a szállítottat.
- A `ml/read_ssml.py` ezt mostantól mérhetővé teszi: bármely `.bin` betölthető Pythonba.
- Az ADR 0567 in-situ mérése és műszere (`STRUM_3C_ASSET`, `STRUM_SPLIT`) **érvényes marad**
  — azt mérte, amit mondott; csak a **következtetése** (szállítsuk) dőlt meg.

## Amit NEM állítunk

- **Nincs in-situ Klangio szám.** Ezek **orákulum**-ablakok, a Python úton az annotált
  onsetre építve — a „melyik modell jobb ezen az audión" kérdésre válaszolnak, nem arra,
  hogy „mit tenne az app". A korpusz nincs a gépen; ha bekerül, a mérés a
  `guitarset_threshold_sweep_test.dart` mintájára megírható.
- **A szállított assetnek NINCS gitáros-diszjunkt Klangio száma**, mert a tanításakor ilyen
  split nem létezett. Ezért a „0,795 vs 0,507" **nem** érvényes modell-összevetés; az
  érvényes összevetések a D2 három **azonos foldos** sora.
- **A visszaesés mechanizmusát nem mértük.** Hogy a guitarist-diszjunkt split nehezebb
  célja, a GuitarSet-adat domináns hatása, a két korpusz mikrofon-karaktere, vagy a
  kapacitás — **nem tudjuk**, és nem adunk rá magyarázatot (L681 szabálya).
- **A GuitarSet-oldali +0,186 nem romlott el.** Két korpusz, két előjel; ez csere, nem hiba.
