# ADR 0507 — Live signal-quality: a matematika a NYILVÁNOS barrelen át újrahasznosított, az állapot hiszterézissel vált, az `unknown` valódi állapot

- **Státusz:** elfogadva
- **Dátum:** 2026-09-04
- **Kör:** `E14-R05` (Chapter 14 — Recognition Accuracy & Useful UI Recovery, Kör 5)
- **Kapcsolódó:** [`0224`](0224-signal-quality-stage-measurement-boundary.md)
  (a batch signal-quality stage mérési és publikációs határa; §3: a már
  merge-elt `SignalQualityReport` nem változik; §4: a stage hangforrást és
  játékminőséget NEM osztályoz),
  [`0505`](0505-versioned-recognition-frame-contract-and-legacy-adapter.md)
  (a `SignalQualitySnapshot` szerződése, amit ez a kör TÖLT MEG),
  [`0271`](0271-recognition-recovery-program.md) §1
  (`UNKNOWN > CONFIDENTLY WRONG`),
  [`0234`](0234-dynamics-evidence-and-gating-boundary.md)
  (a minőségi jelzés kapuz, nem magyaráz),
  [`0002`](0002-feature-first-clean-architecture.md) +
  [`0176`](0176-cross-feature-public-barrel-recognition.md)
  (cross-feature import KIZÁRÓLAG `public.dart` barrelen át)
- **Előzmény:** `docs/LESSONS.md` L05/L09 (a gate artefaktum, nem parancssor),
  L619 (fail-open séma-validátor), L624–L626 (E14-R04: a szerződés-kör a saját
  fogyasztójában nem használta a szótárát)

## Kontextus

Az `E14-R04` leszállította a `SignalQualitySnapshot` **alakját** — hét `null`
metrika + `SignalQualityState.unknown` default
(`lib/features/live/domain/recognition/signal_quality_snapshot.dart`) —, de
üresen. Ez a kör tölti meg.

**Mért állapot a `main @ f963af1f` fán:**

1. **A Live úton egyetlen minőségi jel van, és az egy skálázott RMS:**
   `final level = (_strums.lastRms * 8).clamp(0.0, 1.0).toDouble();`
   (`lib/features/live/engine/dsp/live_pipeline.dart:277`), amit a frame
   `inputLevel`-ként visz ki (`:288`). Klipping, zajszint, SNR, csend-arány,
   beszéd-jelleg: **nincs**.
2. **A batch oldalon KÉSZ a matematika:**
   `lib/features/audio_analysis/engine/quality/signal_quality_math.dart` (208
   sor) — `peakDbfs`, `rmsDbfs`, `clippedSampleRatio`, `isSilentFrame`,
   `silentRatio`, `activeRegionRatio`, `noiseFloorDbfs`,
   `noiseFloorDbfsForFrames`, `tonalness`; a küszöbök a
   `QualityThresholds.standard` (`signal-quality-v1`) alatt élnek, forrásuk a
   `docs/rag/chunks/019-signal-quality-metrics.md`.
3. **A `SignalQualitySnapshot` hét mezője 1:1 megfelel ennek a felületnek** —
   új DSP-matek tehát nem kell, és nem is szabad.
4. **A `live/` feature ma NULLA `audio_analysis` hivatkozást tartalmaz**
   (`grep -rn "audio_analysis" lib/features/live/` → 0 találat).

### A mért architekturális szűk keresztmetszet

A `tool/check_architecture.dart` `crossFeatureImportsMustUsePublicApi` szabálya
szerint a cross-feature import KIZÁRÓLAG a cél-feature `public.dart` barreljét
célozhatja (`tool/check_architecture.dart:366-392`). A szabályt a
`test/core/architecture_dependency_test.dart` pinneli, és a
`tools/round-gate.sh:232` `architecture` lépése futtatja
(`dart run tool/check_architecture.dart`).

`lib/features/audio_analysis/public.dart` **exportálja** a
`engine/quality/quality_thresholds.dart` (`:100`) és a
`engine/quality/signal_quality_stage.dart` (`:101`) fájlt, a
**`signal_quality_math.dart`-ot azonban NEM**.

Mindkét lehetséges útvonal izolált munkapéldányban reprodukálva
(`/home/ubuntu/ss-sonnet-impl-e14-r05`, `dart run tool/check_architecture.dart`):

| Útvonal | Mért eredmény |
|---|---|
| mély import (`…/engine/quality/signal_quality_math.dart`) | **architecture PIROS** — `Unexpected violation(s) … [cross-feature imports must target public.dart]`, exit 1 |
| barrel-import (`…/audio_analysis/public.dart`) | architecture ZÖLD, de **analyze PIROS**: `error • Undefined name 'SignalQualityMath'` |

A `SignalQualityStage` (ami EXPORTÁLT) nem helyettesíti a primitíveket: `async`,
`ValidatedPcmAnalysisInput` + `AnalysisStageContext` bemenetet vár, és MINDEN
hívásán feltétel nélkül lefuttatja a `tonalness` per-frame Hann+radix-2 FFT-jét
és a `noiseFloorDbfs`-t
(`lib/features/audio_analysis/engine/quality/signal_quality_stage.dart:59-110`).
A Live forró úton, blokkonként hívva ez pontosan az a hibás implementáció,
amit a kör-brief mérce-mátrixának 6. sora pirosra visz.

## Döntés

**D1 — A matematika ÚJRAHASZNOSÍTOTT, és a nyilvános barrelen át érhető el.**
A Live elemző a meglévő `SignalQualityMath` primitíveket hívja, a
`package:strumsight/features/audio_analysis/public.dart` barrelen keresztül. Az
elérhetővé tétel **egyetlen additív export-sor** a barrelben
(`export 'engine/quality/signal_quality_math.dart';`, a `:100` sor mellé). A
`signal_quality_math.dart`, a `QualityThresholds`, a `SignalQualityReport` és a
`signal_quality_stage.dart` **bájtra változatlan** (ADR 0224 §3).

**NEM elfogadható gyengítés:** saját RMS/dBFS/klipping-implementáció a `live/`
fában „a forró úthoz gyorsabb kell" indoklással; és NEM elfogadható az
`architectureAllowlist` bővítése sem — az allowlist a saját dokumentációja
szerint (`tool/check_architecture.dart:8-10`) CSAK szűkülhet.

**D2 — A `SignalQualityStage` nem a Live út újrahasznosítási útvonala.** A
stage a batch (Analyze) szerződése marad. A Live elemző a primitíveket hívja,
nem a stage-et.

**D3 — Külön, verziózott `LiveQualityThresholds`.** A Live ablakhossza és
frissítési üteme más, mint a batch-é, ezért a KÜSZÖBÖK külön, verziózott
osztályban élnek (`live_quality_thresholds.dart`), de a KÉPLETEK közösek (D1).
A batch `QualityThresholds.standard` értékei nem módosulnak, és a Live
küszöbök eltéréseinek indoklása a `docs/rag/chunks/live-signal-quality.md`
chunkba kerül, ugyanabban a commitban (CLAUDE.md HORIZON-szabály).

**D4 — Hiszterézis, nem simítás és nem küszöb-tágítás.** Az állapot csak
`enterFrames` egymást követő megerősítés után vált, és csak `exitFrames` után
enged vissza. A villogás elleni védelem KIZÁRÓLAG ez a két paraméter lehet; a
küszöbök tágítása tiltott gyengítés.

**D5 — Az `unknown` valódi állapot.** Kevés adat (indulás, még nem telt puffer)
esetén `unknown` jár, nem `good`. A `good` csak megerősítés után áll be
(ADR 0271 §1).

**D6 — A snapshot nem hazudik nullát.** Ahol nincs mérés, a mező `null` marad —
a `0.0` mint „nincs adat" tiltott (a `SignalQualitySnapshot` minden metrikája
`double?`).

**D7 — Csak audióminőség, semmi más.** Az elemző nem azonosít hangszert,
személyt, hangulatot vagy játéktudást (ADR 0224 §4 határa). A `speechLike`
kizárólag **spektrális** jelzés; ha a fixture nem tudja megbízhatóan
elkülöníteni, `unknown` jár, nem téves osztályozás. Nyers audio nem kerül
logba, hálózatra vagy perzisztens tárolóba (ADR 0224 §1).

**D8 — A meglévő `inputLevel` szerződés érintetlen.** A frame `inputLevel`
mezője ugyanaz a skálázott RMS marad, amíg egy későbbi kör le nem váltja.

**D9 — A `tonalness` FFT nem futhat minden blokkra.** A forró úton a
tonalness-frissítés ritkított (minden N-edik blokk); az `N` értéke és
indoklása a chunkban él.

## Módosítás (ADR 0112 önjavító kör, 2026-09-04)

A D1 útvonala **megnyílt, de nem ebben a körben**: a
`export 'engine/quality/signal_quality_math.dart';` sor az önjavító kör
PR-jével ([#571](https://github.com/wolfcasaba/strumsight/pull/571), squash
`62e0dce6`) landolt a `main`-en, a kör indulása ELŐTT. Ezért az alábbi
„Következmények" első pontja **már nem érvényes**: a kör `allowed_paths`-a
VÁLTOZATLAN marad, és az `audio_analysis` fához a kör NEM nyúl — csak a
barrelt importálja. A többi döntés (D1 képlet-újrahasznosítás, D2–D9)
érintetlen. Mérés: `docs/LESSONS.md` L629; őr:
`test/core/architecture_dependency_test.dart` — „audio analysis quality
primitives stay barrel-reachable (E14-R05)".

## Következmények

- A D1 miatt a kör `allowed_paths`-ának tartalmaznia KELL a
  `lib/features/audio_analysis/public.dart` fájlt. Az `E14-R05` briefje ezt
  **nem** tartalmazza — a kör pre-flightja emiatt `H3`-mal megállt
  (2026-09-04); a lista bővítése az orchestrátor hatáskörén kívül esik
  (ADR 0087 §2: csak SZŰKÍTÉS). A feloldás egy sor a barrelben + egy sor a
  brief listájában.
- Az additív export a batch oldal viselkedését nem változtatja: a
  `SignalQualityMath` privát konstruktorú, kizárólag statikus metódusokat
  hordozó `final class`, tehát az export nem nyit új mutálható felületet.
- A D2 miatt a Live út nem függ az `AnalysisStage` gépezetétől, így az
  `analysis_input`/`analysis_context` szerződések nem szivárognak a valós idejű
  útra.

## Alternatívák, amiket elvetettünk

1. **`architectureAllowlist` bejegyzés a `tool/check_architecture.dart`-ban** —
   elvetve: az allowlist csak szűkülhet (a fájl saját szabálya), és a `tool/`
   a gate infrastruktúrája (ADR 0087 §4: a mérce nem módosulhat attól, akit mér).
2. **Beágyazott `lib/features/audio_analysis/engine/quality/public.dart`
   barrel** (az ADR 0176 által engedett minta) — működne, de egy második,
   redundáns belépési pontot nyitna ugyanahhoz a feature-höz; a meglévő
   feature-root barrel egy sorral bővítve egyszerűbb és kevesebb felületet ad.
3. **A matematika átköltöztetése `lib/core/`-ba** — helyes végállapot lehet,
   de több feature szerződését mozdítja, tehát saját kört és ADR-t érdemel,
   nem ennek a körnek a mellékhatását.
4. **Saját, „gyors" Live-implementáció a primitívekből** — elvetve: két
   forrásból származó, egymástól elcsúszó dBFS-definíció pontosan az a
   hibaosztály, amit az ADR 0224 §3 kizárt.
