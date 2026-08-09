# E99-R04 (GOV-06) — Valós-audio DSP baseline mérés

> ## ⚠ STÁTUSZ: **DRAFT — NEM INDÍTHATÓ, NINCS A QUEUE-BAN**
>
> Ez a fájl **nem kész kör-brief**, hanem a 2026-08-09-i pre-flight **mért
> megállapításainak** rögzítése, hogy a következő session ne vezesse le újra.
> Hiányzik belőle a `ai-router` blokk, az engedélyezett fájllista, az
> acceptance criteria és a mérce-mátrix. **A `docs/execution/pipeline-queue.tsv`
> szándékosan NEM tartalmaz `E99-R04` sort.**
>
> A kör indítása előtt: a §4 nyitott kérdést el kell dönteni, majd teljes
> briefet kell írni a `docs/execution/08-round-brief.md` sablonra, és
> `tools/brief-lint.py --level strict`-tel zöldre hozni.

- **Típus:** governance-kör, a `HANDOFF.md` §6 „Kötelező sorrend" **4. pontja**
- **Miért ELŐBB, mint az Epic 6:** az Epic 6 harminc köre erre a DSP-re épít
  metrika-, confidence- és insight-réteget. Ha az alap gyenge, azt most olcsó
  megtudni — harminc kör után nem.
- **Előfeltétel:** GOV-05c (`E99-R03`) lezárva.

## 1. Mit kell megmérni

A **szállított** DSP pontossága valódi gitárfelvételeken:

- akkord-pontosság,
- onset precision / recall / F1,
- BPM-hiba.

A `HANDOFF.md` §3 rögzíti a mai állapotot: a termék központi állítására
**egyetlen** mért valós-audio szám létezik (CRNN pengetés-irány 86,7% vs
heurisztika 38,9%, r164 A/B) — akkord-pontosságra valós felvételen **nincs**.

## 2. Ami MÁR MEGVAN (mérve 2026-08-09, `main @ 3bfac3fa`)

### 2.1 Valós, CÍMKÉZETT korpusz — de nincs verziókövetve

`ml/data/klangio/` — **82 `.wav`** telefonos felvétel + **82 `.strums`**
címkefájl + 2 `.csv`. Összesen **423 MB**.

A `.strums` formátum (mérve `recording_1001.strums`):

```
0.4511111111111114	D	C-major
1.6121088435374151	D	C-major
2.9124263038548754	D	C-major
```

`idő(mp) \t irány(D/U) \t akkord` — vagyis **egyszerre ad onset-, irány- és
akkord-ground-truth-ot**. Pontosan az a három dimenzió, amit a kör mérni akar.

> ⚠ **MÉRT KOCKÁZAT: a korpusz NINCS a gitben.** `git ls-files ml/data/klangio/`
> → **0 fájl**. A 423 MB csak ezen a boxon létezik. Következmények, amiket a
> briefnek kezelnie kell:
> 1. **A CI nem tudja futtatni a kiértékelést** — a mérés lokális marad, tehát
>    az eredmény artefaktum (elkötelezett riport), nem CI-kapu.
> 2. A box elvesztésével a korpusz elvész. A brief döntsön: LFS, külön repó,
>    vagy dokumentált, checksummolt külső hivatkozás.
> 3. A HORIZON-szabály miatt a riport akkor bizonyíték, ha a benne szereplő
>    parancs **reprodukálható** — tehát a korpusz elérhetőségét meg kell
>    oldani, nem elhallgatni.

### 2.2 Meglévő kiértékelő szkriptek

- `ml/chords/eval_real_sessions.py` — Lab-mode feltöltésekből dekódol, és egy
  **független librosa CQT-chroma sablon-felismerőt** használ közelítő
  ground-truth-ként. Első valós eredmény (2026-07-14, 7 session / 75 esemény):
  **ML 36% vs DSP 56%** — a synth-tanított modell ROSSZABB a szállított
  DSP-nél valós hangon. A szkript saját fejléce mondja ki, hogy a referencia
  maga is tökéletlen telefonmikrofonos teljes sávú hangon.
- `ml/chords/eval_guitarset.py` — GuitarSet (CC-BY-4.0, ISMIR 2018), valós
  gitár **kézzel ellenőrzött** akkord-annotációval; WCSR / frame majmin
  metrikák.

Mindkettő **Python** és a *modellt* méri. A kör kérdése viszont a **szállított
DSP**, ami **Dart**.

### 2.3 A szállított DSP belépési pontja

`lib/features/analyze/engine/clip_analyzer.dart:35` — `class ClipAnalyzer`.
A providereken keresztül: `analyze_providers.dart:195` —
`Future<void> analyzeImported(List<double> pcm, int sampleRate)`.

A Dart oldal **tud wav-ot dekódolni**: van `wav_decoder`
(`test/features/analyze/wav_decoder_test.dart`).

**Ebből következik a kör legfontosabb tervezési állítása:** a szállított DSP-t
**Dart-oldali offline harness**-szel kell mérni, amely a valódi `ClipAnalyzer`-t
futtatja a 82 felvételen — NEM a Python-oldali újraimplementációval. Egy
Python-reimplementáció azt mérné, amit a Python csinál, nem azt, amit a
felhasználó telefonján futó kód.

## 3. Javasolt alak (a következő session dolgozza ki)

1. Dart offline harness (`tool/eval/` alatt vagy egy `test/`-en kívüli
   futtatható), amely: wav → PCM → `ClipAnalyzer` → esemény-lista.
2. Illesztés a `.strums` ground-truth-hoz: onset-párosítás tűréshatárral
   (a tűréshatár legyen **paraméter**, és a mátrix tartalmazzon alatta /
   rajta / fölötte cellát — `docs/execution/08-round-brief.md` §6 4. pont).
3. Riport: akkord-pontosság, onset P/R/F1, BPM-hiba — felvételenként ÉS
   aggregálva, a `ml/chords/eval_*` meglévő metrika-definícióival
   összevethetően.
4. Az eredmény **elkötelezett riport** (`docs/eval/` alatt), a futtatott
   paranccsal és a korpusz checksumjával — hogy a szám reprodukálható legyen.
5. A riport konklúziója **köti az Epic 6-ot**: ha az alap gyenge, azt az Epic
   6 indítása előtt kell tudni.

## 4. Nyitott kérdés, amit a brief ELŐTT el kell dönteni

**A korpusz verziókövetése** (§2.1). Három út, mind más költséggel:

| Út | Előny | Hátrány |
|---|---|---|
| Git LFS | a CI is futtathatná | 423 MB LFS-kvóta, repó-méret |
| Külön adat-repó / release-asset | a fő repó tiszta marad | külön letöltő lépés, hitelesítés |
| Dokumentált külső hivatkozás + checksum | nulla tárhely | a mérés nem reprodukálható a boxon kívül |

Ez **termék/infrastruktúra-döntés**, nem technikai default — a brief nem
mehet ki nélküle, mert a választás dönti el, hogy a kör eredménye CI-kapu
lehet-e vagy csak lokális artefaktum.

## 5. Amit a kör NEM csinál

- **Nem hangol DSP-t.** Ez mérési kör; a hangolás a mérés UTÁN, külön kör,
  és a `docs/rag/chunks/` frissítésével jár (CLAUDE.md „DSP tuning").
- Nem tanít modellt, nem cserél modellt.
- Nem nyúl a szállított `ClipAnalyzer` viselkedéséhez — ha a harness
  kedvéért kellene változtatni rajta, az önmagában lelet.
