# Onset-detektor A/B — jelentés-alak és Pareto-nézet (E14-R16, ADR 0524)

## Amit ez a kör szállít

Egy futtatható harness (`tool/benchmarks/onset_ab_benchmark.dart` +
`lib/features/live/engine/dsp/onset_detector_variant.dart`), amely **négy**
onset-detektáló függvényt (`current`, `canonicalSuperFlux24`, `complexDomain`,
`spectralFlux`) mér össze **ugyanazon** a bemeneten, **ugyanazzal** a
merge-elt pontozó szerződéssel
(`lib/features/live/domain/evaluation/recognition_metrics.dart`, ADR 0509).
A kör kimenete **mérés + javaslat** — a `superflux_onset_detector.dart` és a
`dsp_config.dart` egyetlen sora sem mozdult (ADR 0524 D1). Ez a dokumentum
NEM tartalmaz mért számot: nincs commitolt audio-korpusz (ADR 0249), a valós
mérés a CLI-nek egy külső korpusz-könyvtár argumentumaként fut le egy
KÉSŐBBI körben.

## A négy variáns

| id | Mit csinál |
|---|---|
| `current` | a SZÁLLÍTOTT `SuperFluxOnsetDetector`, alapértelmezett konstansokkal — nem másolat |
| `canonicalSuperFlux24` | Böck–Widmer SuperFlux a 24 sáv/oktáv log-frekvenciás szűrősoron (nem a szállított 64 mel-sáv) |
| `complexDomain` | komplex-domain ODF: a következő spektrum lineáris predikciója magnitúdóból+fázisból, a flux az eltérés összesített magnitúdója |
| `spectralFlux` | félhullám-egyenirányított magnitúdó-flux, fázis nélkül — a legegyszerűbb baseline ODF |

Mindhárom ÚJ variáns a hangoló-értékeket (`delta`, `lambda`, `minIoiSec`,
`lag`, `window`, `hop`) egy `SuperFluxOnsetDetector` példány PUBLIKUS
mezőiből olvassa (ADR 0524 D2) — nincs újragépelt `12.0`/`1.0` literál. A
csúcs-kiválasztó alakja (medián-ablak, lokális-max megerősítés, min-IOI,
release-hiszterézis) egy dokumentált, KÉZI szinkronban tartott tükör a
szállított fájl privát konstansairól — ez a variáns-fájl kimondott határa,
nem rejtett hiányosság.

## A jelentés alakja — két csatorna (ADR 0524 D4)

### 1. `onset-ab-report.json` + `.md` — determinisztikus

Kizárólag a bemenetből következő értékek: eset- és eseményszámok,
variánsonként a teljes merge-elt metrika-fa (25/50/100 ms tűrés,
precision/recall/F1, `truePositives`/`falsePositives`/`falseNegatives`,
`latencyP50Ms`/`latencyP95Ms`). Ugyanarra a bemenetre kétszer futtatva
**bájtra azonos** — nincs benne `DateTime.now()`, fal-óra, gépnév vagy
bármilyen időzítés-kulcs (`elapsed`, `wallClock`, `cpu`, `durationMicros`,
`timestamp`). Az **algoritmikus késleltetés** (döntés_ideje_ms −
jelentett_onset_ms, ahol a döntés ideje a megerősítő `processFrame`-hívás
keretének VÉGE) IDE tartozik: determinisztikus, a bemenet függvénye, nem a
mérőgép sebességéé.

Egy `RecognitionPrecisionRecallF1` cella `precision`/`recall`/`f1` mezője
`null`, ha az adott esethalmazon nincs annotáció vagy nincs elfogadott
detekció (ADR 0509 D6) — a Markdown-renderer ezt **„not measured"**-ként
írja ki, sosem `0.0000`-ként.

Ide tartozik variánsonként az **ODF-skála diagnosztika** is (`odfScale` —
`fluxMedian`, `fluxP95`, `effectiveThresholdMedian`, ADR 0524 D8): a
variáns `lastFlux` mezőjének mintáján (a szállított detektor publikus
`lastFlux`-ának megfelelője, kiterjesztve a három ÚJ variánsra) számolt
medián/p95 flux-érték, valamint a `delta + lambda * median(flux)` effektív
küszöb esetenkénti értékének mediánja. Mindhárom a bemenet függvénye —
determinisztikus, nem gépfüggő —, és pontosan azt a skála-konfundot teszi
mérhetővé, amit a „Korlátok" szakasz alább kimond.

### 2. `onset-ab-timing.json` — kimondottan gépfüggő

Variánsonként teljes feldolgozási idő (`totalProcessingMicros`,
`Stopwatch`-mérve) és egy audio-másodpercre jutó mikroszekundum
(`microsPerAudioSecond`), `deviceId` + `buildSha` metaadattal, és egy
kimondó `note` mezővel, hogy ez SOSEM merge-kapu (ADR 0474/0248 — a szám
gépenként és futásonként változik). Ez a fájl nem kerül diffelésre
helyesség szempontjából, és egyetlen kulcsa sem szivárog a determinisztikus
riportba.

### 3. Variánsonkénti manifest (ADR 0524 D5)

`onsetAbManifestJson(id, cases)` egy `schemaVersion: "1.0"` felismerési
manifestet ír, amit `RecognitionEvaluationRunner.runFromJsonString`
visszaolvas — ugyanazokkal az onset-metrikákkal, mint a riport (round-trip,
9. acceptance-pont). A per-alcsoport (player/device/guitar/room) bontást a
MEGLÉVŐ dashboard (`recognition_report_renderer.dart`, ADR 0511) adja ezen a
manifesten keresztül — a benchmark nem épít második csoportosítást.

## A Pareto-nézet olvasata

A négy variáns egy 3 tengelyű térben áll: **pontosság** (a 50 ms-os
`onsetTolerance50Ms.f1`, a felismerési célra elsődleges tűrés), **algoritmikus
késleltetés** (`latencyP50Ms`/`latencyP95Ms`, a determinisztikus riportból) és
**CPU-költség** (`microsPerAudioSecond`, a gépfüggő időzítés-fájlból, csak
tájékoztató jelleggel — sosem hasonlítható össze eltérő gépeken mért
számokkal). Egy variáns akkor „domináns", ha egyszerre nem rosszabb mindhárom
tengelyen, és legalább egyben szigorúan jobb, mint egy másik. A `current` a
viszonyítási alap: bármely másik variánsnak ezt kell felülmúlnia legalább egy
tengelyen ahhoz, hogy egyáltalán érdemes legyen mérlegelni.

**Ezen a körön belül nincs mért Pareto-táblázat** — a cellák szintetikus
jelekkel igazolják a harness helyességét (§6 acceptance-mátrix), nem egy
valós korpuszt pontoznak. A valós mérés parancsa (a `real_audio_dsp_baseline.dart`
alakja szerint):

```bash
dart run tool/benchmarks/onset_ab_benchmark.dart <corpus-directory> [<output-directory>]
```

ahol a `<corpus-directory>` `<stem>.wav` + `<stem>.onsets.json`
(`{"onsets": [seconds, ...]}`) párokat tartalmaz — ez a formátum ÚJ ebben a
körben (nincs a repóban meglévő tiszta onset-annotáció formátum; a
`.strums` fájlok chord-eseményeket hordoznak, nem használhatók közvetlenül).

## Javaslat — a döntés egy KÉSŐBBI kör ADR-je

1. **Futtasd a harnesst egy valódi, annotált korpuszon** (a Klangio-készlet
   onset-only kivonata, vagy egy új, kifejezetten erre annotált részhalmaz)
   és töltsd ki a Pareto-táblázatot mért számokkal — az `odfScale`
   diagnosztikával együtt (mert az F1-oszlop önmagában, skála-illesztés
   nélkül nem értelmezhető, lásd „Korlátok").
2. **Skála-illesztés ELŐBB, mint bármilyen retune-javaslat** (ADR 0524 D8):
   a `canonicalSuperFlux24`/`complexDomain`/`spectralFlux` mai
   `onsetTolerance50Ms.f1`-értéke nem hasonlítható össze a `current`-tel,
   amíg mindegyik a saját flux-skálájára illesztett küszöböt nem kap. Ez egy
   KÜLÖN kör, KÜLÖN ADR-je (a jelöltet a mért `odfScale.effectiveThresholdMedian`
   variánsonkénti szórása jelöli ki) — ebből a körből semmilyen
   `dsp_config.dart`/`superflux_onset_detector.dart` retune-javaslat NEM
   következik.
3. A `complexDomain` és a `spectralFlux` elsődlegesen REFERENCIA-pontok, de
   csak a skála-illesztés UTÁN: a mai, egyetlen abszolút `delta`-val mért
   F1-különbség (lásd a „Korlátok" táblázatát) a küszöb–skála
   illesztetlenségét méri, nem az ODF minőségét, ezért belőle sem az, hogy
   „a `spectralFlux` jobb", sem az, hogy „rosszabb", NEM olvasható ki.
4. A gépfüggő időzítés-fájlt eszközmátrixon (`docs/testing/device-matrix.yaml`
   mintájára) érdemes megismételni, mielőtt bármilyen CPU-alapú állítás
   bekerül egy ADR-be — egyetlen fejlesztői gépen mért `microsPerAudioSecond`
   nem general­izálható (ADR 0474 D2).

## Korlátok

- A `_floor`, `_medianFrames`, `_postFrames`, `_releaseFrames`, `_peakDecay`,
  `_peakRatio` a variáns-fájlban egy KÉZI, nem gépi szinkronú tükör a
  szállított detektor privát konstansairól — ha azokat egy jövőbeli kör
  retune-olja, ezt a tükröt kézzel kell frissíteni.
- A `canonicalSuperFlux24` saját 24 sáv/oktáv szűrősort épít az STFT fölé —
  a `CqtExtractor` erre NEM használható (`hop = 2048` @ 22,05 kHz ≈ 93 ms,
  onset-felbontásnak nagyságrendekkel durva, ADR 0524 Következmények).
- **A keresztvariáns pontosság-összevetés MA NEM érvényes (ADR 0524 D8).**
  Mind a négy variáns UGYANAZT az abszolút `delta`-t kapja (ADR 0524 D2 — a
  `current` LOG-domain flux-ára hangolt `12.0`/`1.0`), de a `delta` a
  szállított út **log-power** flux-egységeiben értelmezett konstans; a
  `spectralFlux`/`complexDomain` **lineáris magnitúdóban** számol, a
  `canonicalSuperFlux24` pedig ~200 sávon összegez a szállított 64 helyett.
  Ugyanaz az abszolút küszöb tehát mindegyiknél MÁS szigorúságot jelent, és
  a detektálás-szám a bemenet erősítésétől is függ — mérve, ugyanazon a
  szintetikus 4-strum mintán (`strumPattern(lowFirstPerStrum: [true, false,
  true, false], gapSeconds: 0.4)`):

  | variáns | detektálás (4 valódi strum) | ugyanaz −20 dB-en (0,1× jel) |
  |---|---|---|
  | `current` | 4 | 4 (változatlan) |
  | `canonicalSuperFlux24` | 7 | 14 |
  | `complexDomain` | 10 | 5 |
  | `spectralFlux` | 15 | 3 |

  Emiatt egy valós korpuszon mért F1-sor NEM azt méri, hogy „melyik
  flux-definíció teljesít jobban a meglévő hangolás mellett" — ez a korábbi,
  NEM validált értelmezés (GOV-06b/`L173` osztály) volt, és ezzel a
  szöveggel visszavonva. Amit mér: a küszöb–skála illesztetlenséget. A
  harness ezért írja ki variánsonként az `odfScale` diagnosztikát
  (flux-medián, flux-p95, effektív küszöb-medián — fent, „A jelentés alakja"
  1. pont) és pinneli gépi cellával a gain-függést
  (`test/tooling/onset_ab_benchmark_test.dart` 11. pont: 0,1× bemeneten a
  `current` detektálás-száma változatlan, legalább egy ÚJ variánsé
  megváltozik). A keresztvariáns pontosság-összevetés a
  **skála-illesztett küszöb** megszületéséig NEM érvényes; a skála-illesztés
  KÉSŐBBI kör, KÜLÖN ADR (ADR 0524 D8).
