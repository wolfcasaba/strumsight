# E14-R28 — Onset-igazított akkordváltás, chord-latch diagnosztika, shadow-seam (ADR 0545)

- **Kör:** E14-R28 · **Csomag:** PKG-A · **ADR:** 0545
- **Ág:** `claude/laptop-apk-debug-prompt-kys4oa`
- **Környezet:** nincs Dart/Flutter SDK → **lokális gate nem futtatható**.

## 1. Cél

Három, egymásra épülő szállítmány, **egyetlen DSP-küszöb hangolása nélkül**:

1. az akkord-címke váltása a Live úton **pengetés-onsethez igazodik** (a
   meglévő ADR 0518 stabilizátor fölött, dokumentált ablakon belül);
2. a chord-latch (H3 / L2) minden bemenő értéke **mérhetővé** válik egy
   elvárás-mentes, determinisztikus Karplus–Strong riportban;
3. a `RecognitionShadowObserver` **seam** landol (no-op alapértékkel), amire a
   PKG-E a 2. hullámban ráépít.

## 2. Mért állapot (a kör előtt)

- `recognition_stabilizer.dart` (ADR 0518) csak *mi* az új címke kérdésre
  válaszol (`minAgreeFrames`: free 3, guided 5). *Mikor szabad váltani* — nincs.
- `viterbi_chord_decoder.dart` MÁR onset-tudatos (`noteOnset`,
  `_onsetBoostFrames = 2`, `_onsetBonusScale = 0,25` — chunk 016 rec #2,
  round 138), de a premissza a stabilizátor szintjén nem volt kimondva.
- H3: a chord-latch nem húz be Karplus–Strong jelen. Gyanúsított:
  `confidence = winSim*(0,5 + 2·margin)` közel-döntetlennél `≈ 0,5·winSim`,
  a `chordConfRise = 0,54` alatt. **Hipotézis — a fán nem volt felület, amin
  képkockánként kiolvasható lett volna.**
- `recognitionShadowModeEnabled` zászlónak nincs fogyasztója; shadow-plumbing
  nem létezik.

## 3. Scope

**Benne:** az onset-igazítási feltétel a stabilizátorban; a levezetett ablak
és a hozzá tartozó `DspConfig` konstansok (érték-változás nélküli áthelyezés);
`ChordLatchDiagnostics` + dekóder-getterek + a riport-cella; Karplus–Strong
generátor a `test/support/synth.dart`-ban; `RecognitionShadowObserver` seam.

**Kívül:** bármely küszöb ÚJRAHANGOLÁSA (`chordConfRise`, `chordConfRelease`,
`chordReleaseHoldFrames`, `chordNoChordScore`, `chordSelfTransitionBonus`, a
margin-képlet, a tonalness-kapu) — **egyetlen számjegy sem változott**;
shadow-implementáció (PKG-E); UI (PKG-F); zászlók (PKG-D).

## 4. Érintett fájlok

| Fájl | Változás |
|---|---|
| `lib/features/live/engine/recognition_stabilizer.dart` | onset-igazítási feltétel a kiszorításra; `onsetAlignmentWindowSec`; `onsetHeldFrames` |
| `lib/features/live/engine/dsp/dsp_config.dart` | `chordOnsetBoostFrames/BonusScale/Seconds`, `frameEmitSeconds` (értékek változatlanok) |
| `lib/features/live/engine/dsp/viterbi_chord_decoder.dart` | `last*` diagnosztikai getterek; a konstansok a `DspConfig`-ból |
| `lib/features/live/model/live_frame.dart` | **ÚJ mező** `onsetTimeSec` (alapérték −1, opcionális) |
| `lib/features/live/engine/dsp/strum_analyzer.dart` | `lastOnsetSec` — a klasszifikáció ELŐTT bélyegzett onset-idő |
| `lib/features/live/engine/dsp/live_pipeline.dart` | `chordLatchDiagnostics` (kiolvasáskor épül); shadow-hívási pont; `frameEmitSeconds` |
| `lib/features/live/domain/recognition/chord_latch_diagnostics.dart` | **ÚJ** |
| `lib/features/live/engine/recognition_shadow_observer.dart` | **ÚJ** — interfész + no-op + isolate-barát factory typedef |
| `lib/features/live/engine/real_strum_engine.dart` | observer-factory átadása az izolátumnak |
| `lib/features/live/public.dart` | seam + diagnosztika export |
| `test/support/synth.dart` | Karplus–Strong generátorok (determinisztikus LCG) |
| `test/features/live/onset_aligned_chord_transition_test.dart` | **ÚJ** |
| `test/features/live/chord_latch_diagnostics_report_test.dart` | **ÚJ** (elvárás-mentes riport) |
| `test/features/live/recognition_shadow_observer_test.dart` | **ÚJ** |
| `docs/adr/0545-…md`, `docs/rag/chunks/012-…md` | doksi |

## 5. Kötött döntések

ADR 0545 D1–D6. Kiemelten: **egy** stabilizátor-osztály marad (D1); az ablak
**levezetett** (D3); **nincs küszöbhangolás** (D4); a riport **nem assertál
küszöböt** (D5); a seam alapból **no-op** és bit-azonos (D6).

## 6. Acceptance criteria

| # | Kritérium | Státusz |
|---|---|---|
| 1 | Akkordváltás csak onset után, dokumentált ablakon belül | **PINNED-BY-TEST** — `onset_aligned_chord_transition_test.dart`: nem igazított kiszorítás vár; igazított azonnal megerősít |
| 2 | Az ablak levezetett (nem új küszöb) | **PINNED-BY-TEST** — free `= boost + 3×emit`, guided `= boost + 5×emit`, `boost == 2×4096/44100` |
| 3 | Az ablakhatár inkluzív; egy ms-mal túl már vár | **PINNED-BY-TEST** |
| 4 | A kapu sosem fagyaszt be címkét | **PINNED-BY-TEST** — elavult onset (>2 s) kinyit; óra nélküli képkocka az ADR 0518 útra esik |
| 5 | Az ADR 0518 mátrix változatlan | **PINNED-BY-TEST** — a meglévő cellák óra nélküliek, érintetlenül maradtak |
| 6 | Kitartott akkord nem villog / provisional sosem renderelődik confirmedként | **RÉSZBEN PINNED** — a `provisional` → `null` visszatérés ADR 0518 óta él és tesztelt; új property-cella **nem** született (a `test/property/` `chord_*`/`dsp_*` bővítése a 2. hullámra marad) |
| 7 | A latch minden bemenő értéke képkockánként kiolvasható | **PINNED-BY-TEST** — `chord_latch_diagnostics_report_test.dart` (teljesség + determinizmus + végesség) |
| 8 | **A latch behúz-e KS akkordon; melyik tag a hibás** | **NEEDS-MEASUREMENT** — a riport pont ezt teszi mérhetővé; a felhasználó laptopos futása adja a számokat |
| 9 | transition-latency és false-flip SZÁMOK (Ch14 kapu) | **NEEDS-MEASUREMENT** — valós korpusz + eszköz |
| 10 | Shadow-seam nélkül/vele bit-azonos kimenet | **PINNED-BY-TEST** — `recognition_shadow_observer_test.dart` |

## 7. Verifikáció

Lokálisan nem futtatható. CI: `full-gate.yml` + `build-apk.yml`.
Érintett útvonalak: `test/features/live/`, `test/features/live/dsp/`,
`test/support/`.

**A H3 mérés menete a felhasználó gépén:**

```
flutter test test/features/live/chord_latch_diagnostics_report_test.dart
```

A kimenet CSV-fejléces táblák sorozata (KS 4 pengetés · KS kitartott · a
harmonikus-összeg referencia ugyanarra a fogásformára), plusz `summary:`
sorok. A `closestApproachToRise` negatív értéke mondja meg, **mennyivel**
maradt a latch a `chordConfRise` alatt, a `maxWinSim` / `maxMargin` /
`maxRawConf` hármas pedig azt, hogy a hiba a **padlónál** (`winSimOverNC`),
a **marginnál** vagy az **EMA-nál** van.

## 8. Kockázatok

- **Késleltetés elmulasztott onsetnél:** ha az onset-detektor nem tüzel, a
  címkeváltás a 2 s-os elavulási horizontig várhat. Enyhítés: a 3. eset
  (elavult onset) kinyitja a kaput; `onsetHeldFrames` méri a tényleges
  költséget. Ha valós hangon soknak bizonyul, az ablak **mérés után**
  hosszabbítható.
- A stabilizátor mostantól importálja a `dsp_config.dart`-ot (feature-en
  belüli import, a barrel nem exportál DSP-t).

## 10. Handoff

- **PKG-E (2. hullám):** a seam kész — `RecognitionShadowObserver` +
  `NoopRecognitionShadowObserver` + `RecognitionShadowObserverFactory` a
  `features/live/public.dart`-ból. A `RealStrumEngine` **top-level/statikus**
  függvényhivatkozást vár (izolátum-küldhetőség); closure hangosan bukik.
  `live_pipeline.dart` PKG-A tulajdon marad — a bővítés a seamen át megy.
- **PKG-B:** `ChordLatchDiagnostics` a barrelből elérhető, ha a kiértékelő
  riport per-frame latch-adatot akar.
- **Felhasználó:** a H3 mérést a fenti parancs adja; a számok birtokában
  nyílik meg a `chordConfRise` / margin-képlet kérdése — előbb nem.
