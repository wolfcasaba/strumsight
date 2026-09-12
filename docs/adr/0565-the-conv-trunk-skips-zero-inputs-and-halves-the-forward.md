# ADR 0565 — A konvolúciós trunk kihagyja a nulla bemeneteket: a forward fele idő alatt fut, bit-azonos kimenettel

- **Státusz:** elfogadva (implementáció + mérés; a súlyok és a kimenet **nem változnak**)
- **Dátum:** 2026-09-12
- **Kör:** E18-R42
- **Kapcsolódó:** ADR 0564 (a költség 45× a fejléc állításának — **számai korrigálva itt**),
  ADR 0474 (benchmark-rekord), `tool/benchmarks/strum_direction_forward_benchmark.dart`,
  `docs/LESSONS.md` L681

## Kontextus

Az ADR 0564 megtalálta a szűk keresztmetszetet: a 16,5 M MAC-ból **11,34 M a három
konvolúció**, és a **már szállító** gyors tier a drága, nem a letisztult. A conv2 és a conv3
**post-ReLU** aktivációkat olvas — tehát lehet bennük nulla, amit **egzaktan** ki lehet hagyni,
ugyanaz a trükk, amit a szállított GRU már alkalmaz („post-ReLU sparsity — skip zero rows").

## Mérés: mennyi a nulla, valódi ablakokon

200 valós GuitarSet-ablakon (`guitarset_live70.npz`), nem szintetikuson — a ritkaság az **adat**
tulajdonsága:

```
  réteg   bemenet nulla-aránya   MAC      kihagyható
  conv1          0,00 %          0,28 M     0,00 M
  conv2         46,08 %          4,42 M     2,04 M
  conv3         71,48 %          6,64 M     4,75 M
  ------------------------------------------------
  trunk                         11,34 M     6,78 M  (59,8 %)
  teljes forward                16,50 M     6,78 M  (41,1 %)
```

## Döntés

### D1 — A bemenet EGYSZER ritkásodik, CSR-szerűen, a kimeneti ciklusokon KÍVÜL

A naiv `if (value == 0) continue` a legbelső ciklusban **hasztalan**: ott a bemeneti érték
minden egyes multiply-addhoz változik, tehát egy teszt egy multiply-addot ment.

A ciklus-alak viszont amortizál. A csomagolt kernel `[tap][o][c]`, tehát **egy bemeneti pozíció
csatorna-vektorát minden kimeneti csatorna újraolvassa**: a ritkásítás `inC` tesztbe kerül
**bemeneti pozíciónként** (h×w db, egy pásztázás), és minden megtalált nulla `outC`
multiply-addot ment. conv3-nál ez **egy teszt 48 művelet helyett**.

**Egzakt, nem közelítés:** a kihagyott tagok `0.0 × véges`, a megmaradók **eredeti
sorrendjüket** tartják, tehát az összeg változatlan. A repó három paritás-fixtúrája
(`crnn_strum_net`, `crnn_live_parity`, `crnn_live_3c_parity`, mind ≤1e-3 a Keras-referenciához)
**zöld**, a `chord_crnn_parity` és a `live_crnn_3class` is.

### D2 — A mért nyereség ~2×, és a konzervatív véget szállítjuk

Interleaved A/B, **ugyanaz a valódi ablak**, ugyanaz a futás-sorozat:

```
  dense  32 250–33 030 us   →   sparse  15 575–16 768 us   →   2,00× (1,93–2,04), n=5
```

```
  terhelés (valódi ablak, host AOT)      dense          sparse
  200 bpm tizenhatod, gyors tier       42,7 %/mag     22,2 %/mag
  200 bpm tizenhatod, letisztult tier   8,5 %/mag      4,4 %/mag
  80 bpm nyolcad, gyors tier            8,5 %/mag      4,4 %/mag
```

### D3 — És egy MÉRT módszertani korlát: ezen a hoston a kód-elhelyezés önmagában ~20%

Két binárist mértem, amik **azonos conv-kódot** tartalmaznak és csak a **timed loopon kívüli
print-ekben** különböznek. Interleaved:

```
  bench3  13 036–13 580 us        final  15 575–16 033 us
```

Reprodukálható, ~20%. Vagyis **az abszolút latencia ezen a hoston nem idézhető 20%-nál
pontosabban**, és egy A/B összevetés **csak a két összevetendő bináris interleaved futtatásával**
érvényes. A két interleaved sorozatom ezért **2,43×-ot** és **2,00×-ot** adott; a szállítható
állítás a **2,00×**, mert egy szállítási döntés nem a legszerencsésebb binárisra épülhet.

### D4 — Ez KORRIGÁLJA az ADR 0564 számait, mert az szintetikus ablakon mért

Az ADR 0564 benchmarkja **szintetikus** ablakot használt. A trunk költsége viszont
**adat-függő**, tehát az a szám **más munkát** mért:

```
                                  szintetikus   valódi
  dense forward median              ~28 ms      ~32,5 ms
  gyors tier 200 bpm tizenhatodon    37,6 %      42,7 %
```

A benchmark mostantól a **paritás-fixtúra valódi, normalizált ablakát** olvassa, és ha a
fixtúra hiányzik, **hangosan** jelzi (`SYNTHETIC — sparsity unrepresentative`), nem csendben
esik vissza.

**Ami az ADR 0564-ből áll:** a „~1 ms per window" állítás téves volt (most ~33×-osan, nem
45×-osan — a 45× a **MAC-arány**, a latencia-arány ennél kisebb), a paraméter-számból becsült
latencia tilos, és a letisztult tier nem a szűk keresztmetszet.

### D5 — A „16,5 M MAC" mostantól DENSE-EKVIVALENS, nem végrehajtott

A benchmark kiírja, hogy a trunk kihagy, tehát a **végrehajtott** MAC kevesebb és adat-függő
(ezen az ablakon ~6,2 M) — és kimondja, hogy a dense-számot **nem szabad** a latenciával
elosztva „átbocsátóképességnek" hívni.

## Következmények

- A `settledTier` költsége most **0,9–4,4%** egy magból (host AOT), a gyors tier **4,4–22,2%**.
- Ha egy jövőbeli kör a trunkot tovább gyorsítaná, a maradék nagy tétel a conv3
  (6,64 M dense, ~2,2 M végrehajtott ezen az ablakon).
- A benchmark `--window-from=` paraméterrel más fixtúrára is állítható, tehát egy
  ritkaság-érzékenységi sorozat ingyen van.

## Amit NEM állítunk

- **Nincs on-device szám.** A 2,00× arány egy x86 host AOT-ján mért; egy telefon
  cache-hierarchiája és branch-prediktora más, és a CSR-gather nem-folytonos kernel-olvasása
  ott más arányt adhat.
- A ritkaság **ezen a korpuszon és ezen a modellen** mért. Egy újratanított modell más
  ReLU-statisztikát adhat, és akkor az arány is más.
- A dense-latencia szintetikus↔valódi különbségét (**28 vs 32,5 ms**) a MAC-számok **nem
  magyarázzák** — megmértem: a szintetikus ablak a GRU-ban **többet** dolgozik (1,90 M vs
  1,15 M), tehát a dense-nek ott **lassabbnak** kellene lennie, nem gyorsabbnak. Ezt **nem
  tudom megmagyarázni**, és ezért nem is adok rá mechanizmust (L681).
