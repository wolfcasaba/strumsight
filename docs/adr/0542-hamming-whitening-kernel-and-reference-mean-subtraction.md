# ADR 0542 — Hamming-súlyozott whitening-kernel, és ezzel együtt a referencia átlag-kivonása

**Státusz:** javasolt (2026-09-11, E18-R10 / R11 / R12)

**Hatókör:** `lib/features/live/engine/dsp/nnls_chroma.dart` — a whitening
normalizáló **kernelje** (lapos doboz → normált Hamming) és a szállított
`whiteningMeanCoefficient` (0.0 → 0.20), plus a `live_pipeline.dart` átadása.
Érinti a Live és az Analyze utat is (közös `NnlsChroma`). **Nem** nyúl a
szótárhoz, a dekóderhez, a konfidencia-formulához, a whitening szélességéhez
(±3, ADR 0540) vagy bármely kapuküszöbhöz.

Kapcsolódik:
[ADR 0540](0540-whitening-neighbourhood-span-and-the-quiet-guitar-third.md)
(a szélesség — ennek az **alsó korlátja** részben megszűnt, ld. ott az utólagos
mérést), [ADR 0541](0541-depth-weighted-bass-chroma-register-windows.md)
(mélység-súlyozott basszus-króma), kutatási jegyzetek:
[`hamming-whitening-kernel-2026-09.md`](../research/hamming-whitening-kernel-2026-09.md),
[`soft-floor-rectifier-2026-09.md`](../research/soft-floor-rectifier-2026-09.md),
[`real-audio-hearing-probe-2026-09.md`](../research/real-audio-hearing-probe-2026-09.md),
[`chordino-reference-parameters-2026-09.md`](../research/chordino-reference-parameters-2026-09.md)
§4, `AGENTS.md` §9.

## Kontextus — egy elutasított kör, és ami kiderült belőle

Az E18-R09 a referencia whitening-aritmetikáját (lokális átlag kivonása +
félhullámú egyenirányítás) **tárcsaként** építette be, végigsöpörte, és
**szándékosan 0-n hagyta**. Oka egyetlen, de súlyos: `k ≥ 0.15`-nél a szállított
halk-terc fixture átbillen — egy nyílt E, aminek a terce a csúcs 0.08-án ül,
`Em`-nek olvas. A **dúr↔moll csere a legrosszabb hiba, amit ez az app
elkövethet**, mert az E/Em és A/Am a kezdő tananyag akkordjai: a helyesen játszó
tanulónak azt mondanánk, hogy mollt fogott.

Az a kör két jelöltet nevezett meg, ÉS megnevezett egy okot. Az ok téves volt.

**E18-R11 (lágy padló) — nemleges, és megdöntötte a saját premisszánkat.** Egy
mérőponton közvetlenül kiolvasva a terc binjének súlyát kiderült, hogy **a terc
binje sosem nullázódik**: a saját lokális átlaga FÖLÖTT van, tehát az
egyenirányító hozzá sem ér. A teljes publikált spektrális-padló tartományon a
súlya egy számjegyet sem mozdul. Amit a tercet megöli, az a **kivonás**: a
`k · átlag` egy fix absztolút mennyiség a környezetén belül, tehát egy halk
csúcsot sokkal súlyosabban adóztat, mint egy hangosat — a kontraszt-operátor
pont a kis kontrasztú jellemzőt nyomja el. 8.57 % → 7.09 % → 5.54 % → 3.94 % →
2.30 %, ahogy `k` nő; a döntési határ 7.09 % (`Em`) és 7.83 % (`E`) között.

**Ez tette a kernelt a jól célzott jelöltté**: nem azért, mert „gyengébb", hanem
mert azt változtatja meg, hogy **mi a lokális átlag**.

## A gyökér — mérve, nem sejtve

A referencia (`Chordino.cpp`, `SpecialConvolution`) a futó átlagot és a futó
szórást **normált Hamming-súlyozású** kernelen veszi, nem lapos dobozon. A mi
dobozunk a 3 félhangra lévő szomszédot pont úgy számítja, mint a közvetlen
mellettit — tehát egy hangos csúcs SZÉLÉN a lokális átlagot olyan energia húzza
fel, ami zeneileg máshol van. A halk akkordterc éppen ott él.

A kernel váltása után a halk terc a rács MINDEN `k`-jánál `E` marad, és a
szakadék nem a `k` tengelyen van, hanem a terc szintjén — megkeresve, nem
feltételezve:

```
                   k=0.00  k=0.25  k=0.50  k=0.75  k=1.00
box     terc 0.08     E      Em      Em      Em      Em
box     terc 0.04    Em      Em      Em      Em      Em
hamming terc 0.08      E       E       E       E       E
hamming terc 0.04      E       E       E       E      Em
hamming terc 0.02     Em      Em      Em      Em      Em
```

**A kernel felezi a szükséges tercszintet** — és ezt `k = 0`-nál is teszi. Nem
dúr-irányú elhajlás: a nyílt Em minden tercszinten és minden `k`-n `Em` marad, a
nyílt Am sosem olvas `A`-nak, a valódi `Dsus4`/`A7` változatlan, és a
randomizált property 42/7/123/2026/31337 seedeken nulla párhuzamos-csere hibát
tart.

## Döntés

1. A szállított whitening-kernel **normált Hamming-súlyozás**
   (`defaultWhiteningHammingKernel = true`), a lapos doboz injektálható marad.
2. A szállított átlag-kivonás **`k = 0.20`**
   (`defaultWhiteningMeanCoefficient = 0.20`).
3. A szélek **a bent lévő súlyok összegével normalizálódnak**, nem nulla-
   párnázással: a nulla-párnázás mért csendnek vennék a tengelyen kívüli
   tapokat, és az első/utolsó ±3 félhang többszörösen hangosan jönne ki a
   whiteningből — épp ott, ahol a gitár legmélyebb alaphangja (E2, 0. bin) van.
4. A `whiteningSpectralFloor` **0-n marad** (E18-R11 nemleges eredménye), de a
   tárcsa és a mérőpad a fában maradnak.

## Miért `k = 0.20` — a GROUND TRUTH döntötte el, nem a hangulat

Az E18-R10 a tíz stock loopon mért, amelyekhez **nincs akkord-ground-truth**.
Ezért az E18-R12 a választást a **hét címkézett valódi gitárfelvételre** vitte
(`test/tooling/live_chord_wav_probe_test.dart`), ami az egyetlen valódi
akkord-ground-truth ebben a projektben a repón belül elérhető adaton:

| beállítás | valódi gitár | megerősített keret |
|---|---|---|
| box, k = 0 (eddigi) | **7/7** | 278 |
| hamming, k = 0 | **7/7** | 294 |
| **hamming, k = 0.20** | **7/7** | **296** |
| hamming, k = 0.50 | **7/7** | 297 |
| hamming, k = 0.75 | **7/7** | 295 |

A valódi gitáron tehát a **kernel** hozza a hasznot (278 → 294), a `k` alig. A
`k`-t a nehéz anyag döntötte el, fájlonként:

| | box k=0 | hamming k=0 | **hamming k=0.20** | hamming k=0.50 |
|---|---|---|---|---|
| B-moll hangnemben | 82 % | 84 % | **86 %** | 74 % |
| F-moll hangnemben | néma | **néma** | **93 %** | 88 % |
| `electric-guitar-phrase` | 71 keret | **néma** | megint nevez | megint nevez |

`k = 0` tehát **két fájlt veszít el csendbe** — ez regresszió, nem semleges. A
`k = 0.20` mindkettőt visszahozza, és a B-mollon a legjobb. A `k = 0.50` a
B-mollt 74 %-ra rontja.

## A változás MÉRT költsége

- **Futásidő:** 147 bin × 19 tap, közvetlen konvolúció. Izolált
  mikrobenchmarkon (gazdagép JIT) 21.09 µs/keret a 8.89 helyett (divide-only),
  illetve 16.67 a 4.89 helyett (átlag-kivonós) — ~2.4×, de a keret-büdzsé (egy
  `nnlsHop` = 92 880 µs) **0.023 %-a**.

  **Utólag AOT-on is megmérve (E18-R13).** A `nnls_chroma.dart` Flutter-mentes
  lett (`package:meta` a `package:flutter/foundation` helyett — az csak
  újraexportálja ezt az annotációt), amivel a teljes akkord-lánc
  `dart compile exe`-vel AOT-ra fordítható és a szállított módon mérhető. A
  `tool/bench/whitening_bench.dart` a **publikus `process()`-t** méri, egy teljes
  analízis-keretet — nem teszt-szeamen keresztül a whiteninget, mert egy benchmark
  nem teszt, és az analizátornak igaza van, amikor a `tool/` `@visibleForTesting`
  tagot érint:

  ```
  keret-büdzsé 92 880 µs (egy nnlsHop), 3000 iteráció, AOT, két futás
  box     k=0.20            1174.32 / 1208.54 µs    1.26 % / 1.30 %
  hamming k=0.20 (szállított) 1215.04 / 1216.57 µs  1.31 % / 1.31 %
  ```

  Két dolgot mond. **Egy teljes króma-keret ~1.2 ms AOT-on, a büdzsé ~1.3 %-a** —
  tehát a valós munka két nagyságrenddel nagyobb, mint a kernel különbsége. És a
  **kernel választása ezen a felbontáson nem különíthető el**: a szállított és a
  box közti eltérés (8–40 µs) ugyanabba a sávba esik, mint a box saját
  futás-közti szórása (34 µs). Ez összhangban van az izolált 12 µs-mal: a kernel
  költsége a keret saját munkájának zajszintje alatt van.

  **Ami továbbra sem mérve:** az **ARM** absztolút érték. A JIT→AOT ugrás be van
  zárva (a kettő gyakorlatilag megegyezik), tehát a nyitott kérdés egy
  architektúra-váltás, nem egy fordítási mód.
- **Két állítás billent, egyik sem képesség-regresszió.** A „szállított kernel a
  lapos doboz" tautológia volt; most a Hamminget állítja, a NEVESÍTETT
  konstansból, és a doboz uniformitása külön cellában marad mérve. Az ADR 0540
  ±2-es gyök-erózió **kontrollja** elvesztette a kontrasztját, mert a Hamming a
  jelenséget megszünteti — ezért a kontroll a DOBOZ kernelre van kötve, ahol a
  jelenség létezik, és egy új cella rögzíti a megszűnést. A kontrollt nem
  lazítottuk fel azért, hogy zöld legyen.

## Amit ez a kör NEM bizonyít — nyíltan

- **A `sus4`/`aug` túlreprezentáltság NEM javult** (43.6 % → 43.1 %, ez zaj). Ez
  volt a kampány eredeti hajtóereje, és **nyitva marad**. A `k ≤ 0.15`-nél
  látszó ~9 pontos javulás **műtermék**: a `sus4`-ben gazdag
  `electric-guitar-phrase` ott elnémul, és az átlagból esik ki.
- A tíz loopnak nincs akkord-ground-truth-ja, tehát a `named` és a hangnem-arány
  **viselkedési jelzés, nem pontosság**. A hét címkézett gitárfelvétel az egyetlen
  pontossági szám, és ott 7/7 ↔ 7/7 (a javulás a keretszámban van).
- A B-moll 86 %-a 44/51 keret — kis minta, és az arány részben úgy nőtt, hogy
  **kevesebb** hangnemen kívüli keretet nevezett meg.
- A valódi-gitár A/B (ADR 0539 D4 / E18-R05) és a 82 felvételes korpusz-baseline
  **továbbra is nyitott**; a halk-terc eredmények szintetikus hangzatok
  referencia-szinteken.
- A **span × kernel** kölcsönhatás: mindvégig ±3. Az ADR 0540 utólagos mérése
  jelzi, hogy a kernel mozgatja a span optimumát; ezt nem söpörtük végig.

## Amit a kör FELTÁRT, de nem okozott

A `real_audio_hearing_probe_test.dart` a `whiteningMeanCoefficient`-et
`override ?? 0.0`-val adta át, miközben a kommentje azt ígérte, hogy „unset
esetén a szállított értéket használja". Amíg a szállított érték 0 volt, ez
láthatatlan; a tárcsa elmozdulásával minden jövőbeli kör **csendben mást mért
volna, mint amit szállítunk**. Ezért lett `defaultWhiteningMeanCoefficient` és
`defaultWhiteningSpectralFloor` **nevesített konstans**, és a próba ezekre esik
vissza. Ugyanez a hibaosztály ütött meg engem is a kör közben: a `NnlsChroma`
default-jának átírása semmit nem tett, mert a `LivePipeline` explicit továbbadja
a paramétert — az első „eredményem" kétszer a szállított viselkedést mérte.

**Őrtesztek:** `test/features/live/dsp/spectral_whitening_test.dart` (a kernel
súlyai, a halk terc mindkét kernelen), `register_windows_test.dart` (a
kontroll a dobozra kötve + a megszűnés), `test/property/dsp_property_test.dart`
(a kernel 1-re normál és a lapos spektrumot laposan hagyja; random maj/min
hármasok a teljes referencia-kivonásnál), `test/tooling/whitening_mean_coefficient_sweep_test.dart`
(mindkét kernel × öt `k`, egy közös mérőpadról — az E18-R10 és R11 táblája
számjegyre reprodukálódik belőle).
