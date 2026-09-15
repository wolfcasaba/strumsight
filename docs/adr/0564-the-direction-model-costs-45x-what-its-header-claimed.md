# ADR 0564 — Az irány-modell 45×-ét költi annak, amit a saját fejléce állított: 28 ms ütésenként, nem ~1 ms

- **Státusz:** elfogadva (mérés + egy szállított forrásban álló téves állítás javítása)
- **Dátum:** 2026-09-12
- **Kör:** E18-R41
- **Kapcsolódó:** ADR 0474 (benchmark-rekord, a négy `kind`), ADR 0563 (a letisztult tier
  relatív költsége), ADR 0559 D3 (a „~29 ms JIT" próza),
  `tool/benchmarks/strum_direction_forward_benchmark.dart`, `docs/LESSONS.md` L680

## Kontextus

Az ADR 0563 megmérte a letisztult tier **hasznát** (+0,0551 irány-macro-F1) és a **relatív**
költségét (+20% forward), az **absztrakt** költséget viszont prózában hagyta: „~29 ms egy
JIT-es teszt-harnesszen, ami nem on-device szám". Ez **felső korlát adatpontnak maszkírozva**
— pontosan az a keveredés, ami ellen az ADR 0474 a négy `kind`-ot (`measured` / `upperBound` /
`derivedContract` / `target`) bevezette. A számnak a benchmark-rekordban a helye, a `kind`-jával
kimondva.

És volt egy **ellentmondás** is. A `crnn_strum_net.dart` fejléce azt állította: *„a net ~350k
params / **~1 ms per window**"*. A JIT-harnesz ~29 ms-ot mért — **29-szerest**. Egyiknek nem
volt igaza a **szállított** út költségéről.

## Mérés (`tool/benchmarks/strum_direction_forward_benchmark.dart`, `ci_host`)

Tiszta Dart, szándékosan Flutter-import nélkül, hogy **kétféleképpen** futhasson:

```bash
flutter test --reporter expanded tool/benchmarks/strum_direction_forward_benchmark.dart   # JIT
dart compile exe tool/benchmarks/strum_direction_forward_benchmark.dart -o bench && ./bench  # AOT
```

```
  forward latencia   JIT  median 25,8 ms          AOT  median 27-29 ms (p95 33 ms)
```

**Az AOT nem gyorsabb.** Tehát a JIT-szám sosem volt az a pesszimista korlát, aminek
kezeltem — a ~28 ms a **valódi** host-költség.

### És a magyarázat: a paraméter-szám nem a munka

```
  conv1  15×128×16 kimenet × 9          =  0,28 M MAC   (utána maxpool W/2)
  conv2  15×64×32  kimenet × 9×16       =  4,42 M
  conv3  15×32×48  kimenet × 9×32       =  6,64 M
  GRU    15 lépés × (768 + 128) × 384   =  5,16 M
  dense  128 × 3                        =  0,00 M
                                          --------
                                          16,5 M MAC
```

**363 891 paraméter ellen 16,5 M MAC — 45×.** Egy konvolúciós kernel **minden térbeli
pozíción** alkalmazódik, a GRU mátrixai **mind a 15 időlépésen**; a paraméter és a munka nem
ugyanaz a szám. A mért 16,5 M MAC / 28 ms ≈ **0,6 GMAC/s**, ami **szokásos** skalár
Dart-sebesség — tehát **nem az implementáció lassú**, hanem a munka 45×-e annak, amit a
fejléc sugallt. A „~1 ms" becslés a paraméter-számból jött.

### A terhelés lineáris az ütés-sűrűségben

```
  200 bpm tizenhatod (stressz)   13,3 ütés/s
     gyors tier (minden ütés)     376 ms/s  = 37,6 % egy magból
     letisztult tier (19,8%)       74 ms/s  =  7,4 %
  80 bpm nyolcad (kezdő)          2,7 ütés/s
     gyors tier                    75 ms/s  =  7,5 %
     letisztult tier               15 ms/s  =  1,5 %
```

## Döntés

### D1 — A szállított forrásban álló téves állítás javítva, a javítás módjával együtt

A `crnn_strum_net.dart` fejléce mostantól a **mért** számot hordozza, a MAC-táblát, és
kimondja, hogy **a korábbi állítás 45×-esen téves volt, és miért** (paraméterből becsült
latencia). Nem töröltem a hibát: egy javítás, ami elrejti, mi volt ott, a következő olvasót
nem védi meg ugyanattól a becsléstől.

### D2 — A szám a benchmark-rekordba megy, `kind` kimondva

Négy `measured` rekord `ci_host`-on: median és p95 latencia, plusz a levezetett
másodpercenkénti terhelés a két tierre. **Egyik sem állít telefon-`deviceId`-t** — az ADR 0474
D2 zárt eszköz-szótára szerint egy kitalált eszköz **parse-hiba**, és ez itt pont a kívánt
viselkedés. Az on-device szám **nincs megmérve**, és ezért **nincs is rekordja**: a séma
értéket kíván, tehát egy „PENDING cél" nem rekord, hanem dokumentum-sor.

### D3 — A letisztult tier NEM a szűk keresztmetszet; a már SZÁLLÍTÓ gyors tier az

A letisztult tier hozzájárulása **7,4%** egy magból a stressz-esetben, **1,5%** kezdő
tempónál. A **gyors tier** — ami **ma szállít** — **37,6%**, illetve 7,5%. A kérdés tehát,
amivel ez a kör indult („megengedhetjük-e a második forwardot"), **a rossz kérdés volt**: az
inkrementum kicsi, az alap nagy.

### D4 — Ez nyitja az egyetlen valódi teljesítmény-kérdést, és NEM válaszolja meg

37,6% egy magból **x86 asztali gépen**, AOT. Egy telefon skalár Dart-ban tipikusan lassabb.
Hogy a **szállított** gyors út elfér-e az élő büdzsében a stressz-tempón, az **on-device mérés**
— ez a kör ezt **nem** tudja megadni, és nem is állít róla semmit. Amit megad: a kérdés innentől
**mérhető**, a benchmark futtatható, és a rekord-séma megakadályozza, hogy egy host-szám
telefon-számként olvasódjon.

## Következmények

- A `settledTier` felkapcsolásának költség-indoka **megvan** (1,5–7,4% egy magból, host-AOT),
  de a döntés a **gyors** tier on-device számán is múlik, nem csak a sajátján.
- A benchmark `--json=` kimenete a meglévő `tool/compare_benchmarks.py` komparátorba illik,
  tehát a regresszió-figyelés ingyen jön.
- Ha az on-device szám szorít, a nyereség nem a tier lekapcsolásában van, hanem a **trunk**
  költségében: 16,5 M MAC-ból 11,3 M a három konvolúció. Ez külön kör és külön ADR.

## Amit NEM állítunk

- **Nincs on-device szám**, és ezért nincs állítás arról, hogy a szállított út elfér-e.
- A 16,5 M MAC a réteg-alakokból **levezetett** érték, nem számlálóval mért — az alakok
  viszont az assetből és a `forward` kódjából jönnek, és a belőlük adódó 0,6 GMAC/s
  **egyezik** a mért latenciával, ami a levezetés ellenőrzése.
- A két tempó-sor **választott** reprezentáns, nem eloszlás: egy valódi menet ütés-sűrűsége
  ennél változóbb.
