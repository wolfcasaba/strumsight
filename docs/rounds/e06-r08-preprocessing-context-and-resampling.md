# E06-R08 — Preprocessing context és resampling policy

- **Státusz:** PREPARED (előre megírva 2026-08-07, kód olvasva: main @ `a6e6f3d`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 8; §12.1–12.4
- **Branch:** `codex/e06-r08-preprocessing-context-and-resampling`
- **Előfeltétel:** **E06-R05, E06-R07 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/domain/preprocessed_audio.dart",
  "lib/features/audio_analysis/engine/preprocessing/preprocessing_stage.dart",
  "lib/features/audio_analysis/engine/preprocessing/mono_downmix.dart",
  "lib/features/audio_analysis/engine/preprocessing/preprocessing_config.dart",
  "lib/features/audio_analysis/public.dart",
  "lib/app/config/feature_flags.dart",
  "test/features/audio_analysis/engine/preprocessing_stage_test.dart",
  "test/features/audio_analysis/domain/preprocessed_audio_test.dart",
  "test/property/analysis_preprocessing_property_test.dart",
  "docs/adr/0206-analysis-preprocessing-and-resampling-policy.md",
  "docs/rounds/e06-r08-preprocessing-context-and-resampling.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/property",
  "test/app",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R05/R07 merge.
> **ADR 0206** előre kiosztva; ütközéskor a 0200–0211 blokk tolása. Olvasd újra
> a `lib/core/audio/codec/wav_decoder.dart` **mai** csatorna-átlagolását (a
> downmix ma ott történik, dekódoláskor) és az R05 adapterét — a kör NEM
> duplikálhatja a downmixet, hanem **verziózott policy** mögé helyezi.
> Ellenőrizd a `DspConfig.nnlsWindow`/`nnlsHop` mai értékét: a
> sample-to-time mapping tesztje ezekre hivatkozik. PREPARED→PLANNING.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Előre kiosztott ADR: **0206** (preprocessing + resampling policy).

## 1. Cél

Az **eredeti** és a feature-extractionre előkészített audio biztonságos
szétválasztása, verziózott preprocessing-konfigurációval — hogy a dinamikai
metrikák sose egy normalizált másolatból számoljanak, és a sample↔idő leképezés
reprodukálható legyen.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- **Nincs preprocessing réteg.** A mai út: WAV-dekóder (ott történik a
  stereo→mono **átlagolás**, `wav_decoder.dart`) vagy mikrofon → nyers
  `List<double>` → `ClipAnalyzer.analyze(pcm, sampleRate)`.
- **Nincs resampling sehol:** a `LivePipeline` és a `NnlsChroma` a kapott
  `sampleRate`-tel dolgozik (`clip_analyzer.dart` 115, 158). A chord-pass
  ablak/hop a `DspConfig.nnlsWindow`/`nnlsHop` **mintában** kifejezett
  konstansa, tehát a szegmenshatárok időben **sample rate-függők**
  (`centers.add((start + win / 2) / sampleRate)`, 173. sor).
- **Nincs normalizáció** és **nincs DC-offset eltávolítás** a shipping úton.
- A HPSS (`hpss.dart`, 226 sor) és a chroma denoise (`chroma_denoise.dart`,
  88 sor) létezik, de a `ClipAnalyzer` alapértelmezésben **nem** használja a
  HPSS-t, a denoise pedig `chromaMedianWindow = 1` (= kikapcsolva) default
  mellett fut.
- Az R05 megőrzi a csatornaszámot metaadatként (OD-02), az R07 riportot ad.

## 3. Scope

**Benne:** `PreprocessedAudio` (original metadata + canonical samples +
sample↔idő mapping + normalization gain + config/verzió); `PreprocessingStage`
(R04-stage); verziózott `MonoDownmix` policy; `PreprocessingConfig`
(verzió + kapcsolók); **ADR 0206** a resampling-döntéssel; **egy** új feature
flag: `analysisPreprocessingExperimentalEnabled` (DC-offset + normalizáció
mögé, default OFF).

**Kívül — TILOS:** resampler **implementálása** (az ADR 0206 dönt: a V1
natív sample rate-en marad), HPSS/chroma-denoise bekapcsolása vagy
paraméterezése, `DspConfig`, `lib/features/analyze/**`, `lib/features/live/**`.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/preprocessed_audio.dart` | ÚJ | eredeti + kanonikus reprezentáció |
| `.../engine/preprocessing/preprocessing_config.dart` | ÚJ | verziózott konfiguráció |
| `.../engine/preprocessing/mono_downmix.dart` | ÚJ | verziózott downmix policy |
| `.../engine/preprocessing/preprocessing_stage.dart` | ÚJ | R04-stage |
| `.../public.dart` | meglévő | `PreprocessedAudio` export |
| `lib/app/config/feature_flags.dart` | meglévő | **additív** 1 flag, default OFF |
| `test/features/audio_analysis/**`, `test/property/**` | ÚJ | paritás + property |
| `docs/adr/0206-…md` | ÚJ | resampling/preprocessing döntés |

**Tilos zóna:** `lib/features/live/**`, `lib/features/analyze/**`,
`lib/core/audio/codec/**`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **ADR 0206 — a V1 NEM resampol.** Minden stage a bemenet **natív** sample
   rate-jén fut; a `PreprocessedAudio` a mapping-et **explicit** hordozza
   (`sampleIndexToDuration`, `durationToSampleIndex`). Indok: a mai
   `ClipAnalyzer`/`NnlsChroma` mintában kifejezett ablakai miatt bármely
   resampling **azonnali paritásvesztés**, mérés és evaluation nélkül.
   Az ADR kimondja a **visszavonás feltételét** (mikor vezethető be resampler:
   fixture-paritás több sample rate-re + anti-alias fixture + evaluation).
   **NEM elfogadható:** „ideiglenes" nearest-neighbor resampling (SDD §12.3
   tiltja), és **NEM elfogadható** a mapping implicit `index / sampleRate`
   szórása a hívási helyekre.
2. **A dinamika az EREDETI amplitúdóarányokat kapja** (SDD §12.4): a
   `PreprocessedAudio` **két** mintasorozatot tart — `originalSamples`
   (érintetlen) és `canonicalSamples` (feature-extractionre előkészített);
   a normalization gain **szám**, amivel az eredeti visszaállítható.
   **NEM elfogadható:** egyetlen, normalizált puffer + „majd visszaosztjuk".
3. **A normalizáció és a DC-offset eltávolítás flag mögött, default OFF**,
   és **paritás-teszttel** védve: bekapcsolva sem változhat az onset-idők és a
   chord-szegmenshatárok dokumentált toleranciáján kívül.
   **NEM elfogadható:** a flag alapértelmezett bekapcsolása „mert jobb".
4. **A downmix verziózott és determinisztikus:** `v1` = a **mai** viselkedés
   (csatorna-átlag), a fázis-kioltás kockázata a doc-commentben rögzítve;
   a downmix **után** clipping-ellenőrzés fut (SDD §12.1).
   **NEM elfogadható:** „jobb csatorna kiválasztása" a v1-ben.
5. **A preprocessing bemenetet nem mutál:** az `AnalysisInput` PCM-je bitre
   változatlan marad. **NEM elfogadható:** in-place módosítás.
6. **A konfiguráció verziója a provenance-be kerül**, és a cache-kulcs
   bemenete lesz (R28).

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: A canonicalSamples memóriaduplázása elfogadható?
    blocking: true
    resolution_policy: use_default
    default: >-
      IGEN a V1-ben: ha a config minden transzformációt kikapcsol (a default),
      a canonicalSamples ugyanaz a REFERENCIA, mint az originalSamples —
      nulla másolat. Másolat csak akkor keletkezik, ha ténylegesen történt
      transzformáció. Ezt teszt méri (`identical(...)`).
  - id: OD-02
    question: A `Float32List` vagy `Float64List` legyen a kanonikus típus?
    blocking: true
    resolution_policy: use_default
    default: >-
      marad a MAI `List<double>` / `Float64List` út (a `ClipAnalyzer`
      `Float64List.fromList`-et használ) — típusváltás előtt az SDD §22.2
      paritás- és teljesítménymérést ír elő, ami az E06-R28 dolga.
```

## 6. Acceptance criteria

- [ ] **Nulla-másolat cella:** default konfigurációval
      `identical(pre.canonicalSamples, pre.originalSamples)` **igaz**; bármely
      transzformáció bekapcsolásakor **hamis**, és az `originalSamples` bitre
      egyezik a bemenettel.
- [ ] **Sample↔idő mapping mátrix:** 44 100 Hz és 48 000 Hz mellett a
      `sampleIndexToDuration(i)` és `durationToSampleIndex(d)` **oda-vissza**
      egyezik a `0`, `1`, `sampleRate−1`, `sampleRate`, `sampleRate+1` és a
      `length−1` indexekre; a kerekítés iránya dokumentált (lefelé), és a
      mikroszekundum-értékek `python3 -c`-vel kiszámolva
      (pl. 44 100 Hz-en az 1. minta = **22 µs**, a 44 100. = **1 000 000 µs**).
- [ ] **Downmix-mátrix:** mono bemenet → változatlan; stereo azonos
      csatornákkal → azonos amplitúdó; stereo **ellenfázisú** csatornákkal →
      a downmix ~0, és a `PreprocessedAudio` **warningot** hordoz a
      fázis-kioltásról; stereo, ahol az átlag |x| > 1 → clipping-jelzés.
- [ ] **Bemenet-immutabilitás:** a stage futása után a bemeneti PCM lista
      **bitre változatlan** (elemenkénti összehasonlítás).
- [ ] **Dinamika-megőrzés:** normalizáció **bekapcsolva** is a dinamikai út az
      `originalSamples`-t látja — teszt méri, hogy két, egymáshoz képest 6 dB
      különbségű strum arányát a normalizáció **nem** változtatja meg
      (a mért arány |Δ| < 0.001).
- [ ] **Paritás-küszöb hármas a flag-re:** a DC-offset eltávolítás
      bekapcsolásakor az onset-idők eltérése a dokumentált toleranciához
      (`5 ms`) képest: **4.9 ms** → zöld, **5.0 ms** → zöld (a határ
      **inkluzív**), **5.1 ms** → **PIROS**. A fixture-t úgy kell építeni,
      hogy mindhárom cella előálljon (szintetikus DC-eltolással hangolva).
- [ ] **Flag-őr:** `analysisPreprocessingExperimentalEnabled` minden
      környezetben `false`.
- [ ] **ADR 0206** tartalmazza: a döntést (nincs resampling a V1-ben), a
      kontextust (mintában kifejezett ablakok), az elutasított alternatívákat
      (44.1→22.05 kHz kanonikus rate; polyphase resampler), és a
      **visszavonás számszerű feltételét**.
- [ ] **V1 érintetlen:** `git diff --stat` nem tartalmaz
      `lib/features/live/**` vagy `lib/features/analyze/**` útvonalat.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A canonical mindig másolat (akkor is, ha nincs transzformáció) | a nulla-másolat `identical` cella |
| A mapping `round` helyett `ceil`/`floor` inkonzisztensen | a mapping-mátrix `sampleRate+1` és `length−1` cellája |
| A normalizáció az `originalSamples`-t is átírja | a bemenet-immutabilitás + dinamika-megőrzés cella |
| A dinamikai út a canonicalt kapja | a 6 dB-es arány cella (|Δ| < 0.001) |
| A fázis-kioltás nem ad warningot | a downmix-mátrix ellenfázisú cellája |
| A paritás-tolerancia utólag tágul 5 ms fölé | a **5.1 ms → PIROS** cella (a tolerancia a briefben rögzített) |
| A stage resampol | a mapping-mátrix + a V1 chord-paritás (`test/features/analyze/batch_chord_timeline_test.dart`) |
| A flag `nonProd`-ra `true` | a flag-őr cella |
| **Valódi-sértés próba (§10):** a bemeneti PCM ideiglenes in-place módosítása a stage-ben → a bemenet-immutabilitás cella **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/property test/app test/features/analyze
```

Külön processzek, nincs `&&`/pipe/`tail`.

## 8. Implementációs sorrend

1. ADR 0206 (a resampling-döntés és a visszavonás feltétele).
2. RED: nulla-másolat, mapping-, downmix-, immutabilitás- és paritás-mátrix.
3. `preprocessing_config.dart` + `mono_downmix.dart`.
4. `preprocessed_audio.dart` (két reprezentáció + mapping).
5. `preprocessing_stage.dart` + flag.
6. Property-teszt; gate.

## 9. Kockázatok

- **A „nincs resampling" döntés később drága lehet** (különböző eszközök
  eltérő natív rate-je) — ezért az ADR 0206 a **visszavonás feltételét**
  számszerűen rögzíti, és a `docs/manual-testing/analysis-eval-matrix.md`
  kap egy PENDING sort a valós eszközös sample rate-ek felmérésére.
- **A kétpufferes modell memóriája** hosszú klipen duplázódhat — a §5.1 OD-01
  nulla-másolat szabálya ezt a default úton kizárja; a mért memóriakép az
  E06-R28 dolga.
- **A paritás-tolerancia „elcsúszása"**: a brief rögzíti az 5 ms-ot, a
  tágítása **brief-revízió**, nem implementer-döntés.

**STOP:** ha a mapping csak `DspConfig` módosításával lenne konzisztens, az
**megállás és jelentés** — DSP-konstans ebben a körben nem változhat.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r08-preprocessing-context-and-resampling-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
