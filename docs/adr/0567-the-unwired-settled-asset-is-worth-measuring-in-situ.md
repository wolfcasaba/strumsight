# ADR 0567 — A bekötetlen settled asset a SZÁLLÍTÓ úton +0,186 irány-macro-F1-et ér ismeretlen játékoson és dallamon

- **Státusz:** elfogadva (**csak mérés**; az asset ebben a körben **nem** kerül bekötésre)
- **Dátum:** 2026-09-12
- **Kör:** E18-R43
- **Kapcsolódó:** ADR 0554 (egy asset szolgálja mindkét szintet), ADR 0555 D3 (szándékosan
  bekötetlen), ADR 0566 (a kapu költség-kerete — ugyanebből a körből), ADR 0549 (a kapu
  0,85-re állítása), ADR 0553 (az adat-diagnózis), `docs/LESSONS.md` L682 §1,
  `test/tooling/guitarset_threshold_sweep_test.dart`

## Kontextus

Az ADR 0555 D3 szándékosan bekötetlenül hagyta a `strum_crnn_live_3c_settled.bin`-t, és
kimondta, hogy az átállítás egy **későbbi kör** dolga az AGENTS.md §9 alatt. Annak a körnek
kell egy szám, ami eddig nem létezett: **mit tesz ez az asset a produkciós úton** — nem
Pythonban, orákulum-ablakokon, hanem a szállított Dart pipeline-ban, detektált onseteken.

## Hogyan majdnem elrontottam ezt a mérést — kétszer

Ez nem anekdota, hanem az ADR két döntésének (D5, D6) az indoklása.

**Először**: elosztottam a Python-oldali megtartást (0,944) a söprés megtartásával (0,633),
„30 pontos résnek" neveztem, és órákig kerestem a **mechanizmusát** — ablak-központozás,
populáció, újraminta-vétel, fixtúra-határ. Mindet megmértem, mind kiesett. Amit nem
kérdeztem meg: **melyik modellen** készült a két szám. Minden `ml/probe_*.py` a
`weights_live_3c_settled.npz`-t tölti be, a söprés pedig a **szállított**
`strum_crnn_live_3c.bin`-t futtatja. **A hányados semmiről szólt.**

**Másodszor**: a söprést ráállítottam a settled assetre — és mind a **72** fájlon mértem.
A settled modell viszont az ADR 0554 szerint **GuitarSeten is tanult** (players 00–02 × 8
dallam), tehát a 72 fájlos szám **kontaminált**: a modell memóriáját jelenti be
képességként. A kontaminált tábla **+0,284** irány-macro-F1-et mutatott; a held-out szelet
**+0,186**-ot. A kontamináció a nyereséget **felével felnagyította**.

## Döntés

### D1 — Mérve: ugyanaz az út, ugyanaz a 12 held-out fájl, ugyanaz a kapu

`STRUM_SPLIT=heldout` (players 03–05 × a 4 **nem tanított** dallam), 1772 SuperFlux onset,
a szállított 0,850-es kapu, `margin on` — vagyis **pontosan** amit a produkció tesz:

```
  asset                       kept  onsetP  onsetF1  pengetés-recall  le-F1   fel-F1  macro
  strum_crnn_live_3c           804   0,908   0,6518       0,758       0,5736  0,2007  0,3872
  strum_crnn_live_3c_settled  1258   0,836   0,7810       0,919       0,7978  0,3478  0,5728
  ----------------------------------------------------------------------------------------
  változás                          −0,072  +0,1292      +0,161      +0,2242 +0,1471 +0,1856
```

**Az egyetlen oszlop, ami romlik, az onset-precizitás (−0,072).** Minden más — detektálás,
megtartás, mindkét irány, a macro — érdemben javul, és a **fel** osztály F1-je, ami az ADR
0553 óta a szűk keresztmetszet, **0,2007 → 0,3478** (+73% relatíve).

### D2 — A lefedési szakadék gyakorlatilag eltűnik

Az ADR 0566 D1 szakadéka (`coverage < 0,5` → **nulla bizonyíték**, tehát nincs haladás) a
megtartásból számolt egzakt binomiális. Ugyanezen a held-out szeleten:

```
  asset        p(hallva)   4 slot   8 slot   16 slot
  szállított     0,758     0,0464   0,0238   0,0059
  settled        0,919     0,0020   0,0002   0,0000
```

A hibátlanul eljátszott 8-slotos kísérletek **2,4%-a → 0,02%-a** ad nulla bizonyítékot.
Ez **ugyanaz a szám**, amit az ADR 0566 D1 a keret-korrekció magjául használ — vagyis az
asset-csere nem *megkerüli* a kapu-kérdést, hanem **elveszi a tárgyát**: egy 0,92-es
megtartás mellett a szakadék nem működő költség többé.

### D3 — Az ár precizitásban van, és egy kapu-szigorítás visszavesz belőle

A settled modell ugyanazon a kapun **több fantomot** enged át (a held-out szeleten
74 → 206), mert összességében ritkábban mond „nem-pengetést". De a **teljes görbéje**
dominál, nem csak egy pontja:

```
  asset / kapu                      onsetP  pengetés-recall  macro
  szállított @ 0,850 (ma)            0,908       0,758       0,3872
  szállított @ 0,439 (legjobb pont.) 0,925       0,722       0,3753
  settled    @ 0,850                 0,836       0,919       0,5728
  settled    @ 0,439                 0,864       0,875       0,5771
```

**A szállítható javaslat tehát nem „cseréld az assetet", hanem „cseréld az assetet ÉS
állítsd a kaput vissza az illesztett 0,439-re":** a precizitás 0,908 → 0,864 (−0,044, nem
−0,072), a megtartás 0,758 → 0,875 (+0,117), a macro 0,3872 → 0,5771 (**+0,190**) — vagyis
a szigorítás itt **nem** kerül irányba, sőt a legjobb macro épp ott van.

*Figyelem a csere-arány eszközre:* az ADR 0566 „hány pengetés egy fantomért" mutatója **egy
modell kapu-görbéjén** való elmozdulásra való. Egy **modell-cserére** nem érvényes, mert a
modell-csere olyat is mozdít (irány-F1), amit egy kapu **soha** nem tud — itt +0,19 macrót.
A két dolgot összevetni ugyanaz a hiba lenne, mint amit a „Hogyan majdnem elrontottam"
szakasz első fele leír.

### D4 — Az asset NEM kerül bekötésre ebben a körben

Az AGENTS.md §9 egy DSP-változáshoz **négyet** kér: fixtúra + property + paritás +
valódi-audió mérés. Ebből ez a kör a **valódi-audió mérést** adja, és a paritás-fixtúra
(`crnn_live_3c_settled_parity.json`) az ADR 0555 D3 szerint már létezik. Hiányzik a
bekötéshez tartozó fixtúra/property munka és a Klangio-oldal in-situ ellenőrzése. Egy
asset-csere, ami a szállított nyíl- és pontozó-utat érinti, nem csempészhető egy
mérési körbe — és nem is kell: az asset nincs a `pubspec.yaml`-ban (az assetek fájlonként
deklaráltak), tehát ma nem is kerül az APK-ba.

### D5 — A mérőeszköz mostantól kiírja, MIT mért: assetet és szeletet

`STRUM_3C_ASSET` (default: a **szállított** asset) és `STRUM_SPLIT=heldout`, és a tábla
fejléce **mindkettőt** kiírja. Ez nem kényelmi funkció, hanem a fenti két tévedés
szerkezeti javítása: egy tábla, ami nem mondja meg, melyik modellt és melyik szeletet
mérte, **összevethetőnek látszik** egy másik táblával, amivel nem az.

### D6 — Ami GuitarSeten tanult, azt GuitarSeten csak a held-out szeleten mérjük

A `STRUM_SPLIT=heldout` **kötelező** minden olyan asset mérésénél, ami GuitarSeten tanult.
A szállított assetre az osztatlan futás is becsületes (nem tanult itt) — de épp ezért a
**kettő összevetése** csak ugyanazon a szeleten érvényes, és az ADR-ben csak a held-out
tábla szerepel.

## Következmények

- A bekötő körnek megvan a **valódi-audió** száma, a szállító úton, tiszta szeleten.
- Az ADR 0566 D5 2. pontja (miért nem mozdul most kapu-konstans) **ezzel indokolt**: a kapu
  újrakalibrálása a ma szállított assetn kétszer elvégzett és egyszer sem érvényes munka.
- A Chapter 14 §7.2 Alpha kapu (irány-macro **0,80**) innen **0,5728/0,5771** — még nincs
  meg, de a 0,3872-ről nézve a rés **felére** csökkent.

## Amit NEM állítunk

- **Nincs on-device szám és nincs felhasználói adat.** 12 GuitarSet-fájl, host futás.
- **A fel-F1 továbbra is gyenge** (0,3478): az ADR 0553 adat-diagnózisa **változatlanul
  áll**, a settled asset nem pótolja a hiányzó felütés-adatot, csak kevesebbet veszít.
- **A Klangio-oldalt in situ nem mértük újra.** A settled asset ott is tanult; az ADR 0555
  tábláján a Python-számok megvannak, a produkciós út nem.
- **Az `audio → ablak` szakaszt nincs fixtúra, ami a Python-építőhöz pinelné.** Ebben a
  körben **egyezett** (a settled assetn a Python orákulum-megtartás 0,944/0,963/0,976 vs a
  produkciós 0,941/0,954/0,971 ugyanazokon a söpréseken), tehát ez lappangó fedési hiány,
  nem aktuális hiba — de a fenti mérés ezt **mellékesen** mutatta meg, nem célzottan.
- **A +0,186 egy held-out szelet 12 fájlján, 530 tiszta söprésen** mért érték; a
  szórásáról nincs becslés (egyetlen szelet, nem cross-validáció).
