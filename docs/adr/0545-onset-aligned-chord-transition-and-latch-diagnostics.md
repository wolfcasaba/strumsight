# ADR 0545 — Onset-igazított akkordváltás a stabilizátor fölött, a chord-latch diagnosztikai kivezetése és a shadow-seam

**Státusz:** elfogadva (2026-09-09) · **Kör:** E14-R28 · **Kiegészíti:** ADR 0518 (stabilizátor), ADR 0516 (akkord-verdikt) · **Előkészíti:** E14-R23 (PKG-E, shadow-mód)

## Kontextus (mért)

- `lib/features/live/engine/recognition_stabilizer.dart` (ADR 0518) EGYETLEN
  kérdésre válaszol: *mi* az új címke — `profile.minAgreeFrames` (free 3,
  guided 5) egyetértő képkocka. Arra, hogy *mikor* SZABAD egyáltalán akkordot
  váltani, nincs válasza: két hasonló fogásforma közti lassú elsodródás egy
  kitartott akkord közepén is megerősíthet új címkét, pengetés nélkül.
- A dekóder MÁR ismeri a helyes premisszát (chunk 016 rec #2, round 138):
  `ViterbiChordDecoder.noteOnset()` a pengetés után `_onsetBoostFrames = 2`
  akkordképkockán át `_onsetBonusScale = 0,25`-tel skálázza a self-bonust —
  „a chord a pengetésen vált, közte stabil". Ez a premissza a stabilizátor
  szintjén nem volt kimondva.
- H3 / L2 (HANDOFF, nem javítva): a chord-latch nem húz be Karplus–Strong
  szintetikus jelen. Névvel nevezett gyanúsítottak: `chord_matcher.dart:99–100`
  (`margin = (best−second)/best`, `confidence = best*(0,5 + 2·margin)`) —
  közel egyforma két legjobb sablonnál `margin ≈ 0` → `conf ≈ 0,5·best`, ami a
  `chordConfRise = 0,54` alatt marad. **Ez hipotézis, nem mérés**: a fán nem
  volt olyan felület, amin a `winSim`, `margin`, `rawConf`, EMA és az N.C.-padló
  képkockánként kiolvasható lett volna.
- `recognitionShadowModeEnabled` zászlónak **nincs fogyasztója** a `lib/**`-ben;
  shadow-plumbing nem létezik.

## Döntés

### D1 — A stabilizátor marad EGY osztály; nem születik második állapotgép

Nem vezetünk be `FreeChordProfile`/`GuidedChordProfile` párhuzamos
provisional/confirmed gépet. Az ADR 0518 gép már pontosan ezt a két állapotot
kezeli (`provisional` a küszöb alatt, `confirmed` fölötte). Egy második gép
ugyanarra a kérdésre két igazságforrást adna — ez a hibaosztály, amit a
Ch14 §12 tilt.

### D2 — EGYETLEN új feltétel a KISZORÍTÁSRA: onset-igazítás

Egy már megerősített címkét kiszorítani szándékozó kihívó — miután
`minAgreeFrames` egyetértést gyűjtött — **csak onset-igazított képkockán**
erősödhet meg. Egy képkocka onset-igazított, ha az alábbiak BÁRMELYIKE igaz
(ebben a sorrendben):

1. **Nincs óra.** `engineTimeSec < 0` vagy `onsetTimeSec < 0` — a termelő
   nem vezet mintaórát vagy nem detektál onsetet (mockok, kézzel épített
   képkockák, a `LiveFrameAdapter` határ), tehát **egyáltalán nincs
   onset-evidencia**. A kapu nem ítélhet és nem is fagyaszthat: a viselkedés a
   tiszta ADR 0518 egyetértés. Ugyanaz a konvenció, amit
   `LiveFrame.strumExpired` használ.
2. **A pengetésen.** A legfrissebb onset legfeljebb
   `StabilizerProfile.onsetAlignmentWindowSec` régi (és nem a jövőben van).
3. **Elavult onset.** A legfrissebb onset `LiveFrame.strumHoldSec` (2 s)
   régebbi — ekkor a termelő maga is **eldobta** a pengetést a képkockáról,
   tehát az onset-evidencia lejárt. A kapu kinyit: egy elmulasztott onset
   késleltetésbe kerülhet, **tartósan rossz akkordba nem**.

A 2. és 3. eset között (valódi, de túl régi onset) a kiszorítás vár. **Ez az
egyetlen viselkedés, amit a kapu hozzáad.**

**Új `LiveFrame.onsetTimeSec` mező (alapérték −1), NEM a `latestStrumTime`.**
Utóbbi csak akkor lép előre, ha a strum IRÁNYA is megerősödött
(`_isDirectionConfirmed`), tehát egy olyan onset, amin az irány-modell
tartózkodott, nem nyitná ki a kaput — pedig az is pengetés. Az új mezőt a
`StrumAnalyzer.lastOnsetSec` táplálja, amit a detektor **a klasszifikáció
ELŐTT** bélyegez (ugyanazzal az attack-eltolással, mint a `StrumEvent.timeSec`).
Minden más termelő (mock, adapter) −1-en hagyja → 1. eset.

A már megerősített címke ÚJRAÁLLÍTÁSA (ADR 0518 D6), a hidegindítás
(D11) és a strum-immutabilitás (D7) **érintetlen** — a kapu a VÁLTOZÁSRÓL szól,
nem a jelenlétről.

### D3 — Az ablak LEVEZETETT, nem hangolt

```dart
double get onsetAlignmentWindowSec =>
    DspConfig.chordOnsetBoostSeconds + minAgreeFrames * DspConfig.frameEmitSeconds;
```

Két, a fán MÁR MEGLÉVŐ konstans összege:

| Tag | Forrás | Érték |
|---|---|---|
| `chordOnsetBoostSeconds` | `2 × nnlsHop (4096) / defaultSampleRate (44 100)` — a dekóder onset-boost ablaka (chunk 016 rec #2, round 138) | ≈ 0,1858 s |
| `minAgreeFrames × frameEmitSeconds` | ADR 0518 D3 küszöb × a `LivePipeline` kibocsátási ütem (a korábbi csupasz `0.066` literál) | free 0,198 s / guided 0,330 s |

Free: **0,384 s**. Guided: **0,516 s**. A guided nem azért hosszabb, mert
külön hangoltuk, hanem mert az egyetértési küszöbe magasabb — ha a második tag
hiányozna, az ablak azelőtt zárulna be, hogy a kiszorítás egyáltalán
megerősödhetne.

`chordOnsetBoostFrames` / `chordOnsetBonusScale` **átkerül** a dekóder privát
konstansaiból a `DspConfig`-ba (értékük változatlan), hogy a stabilizátor
UGYANAZOKBÓL a számokból vezethesse le az ablakot, ne egy másodikat találjon
ki. **Új küszöb nem született ebben a körben.**

`RecognitionStabilizer.onsetHeldFrames` diagnosztikai számláló: hány képkocka
volt már egyetértésben, de még nem igazítva. Ez az a szám, amiből a Ch14 kapu
kért **transition-latency** valós bemeneten MÉRHETŐ — nem állítjuk, mérhetővé
tesszük.

### D4 — Küszöbhangolás NINCS ebben a körben

`chordConfRise`, `chordConfRelease`, `chordReleaseHoldFrames`,
`chordNoChordScore`, `chordSelfTransitionBonus`, a margin-képlet és a
tonalness-kapu **egyetlen számjegye sem változik**. A H3 hipotézist a kör
MÉRHETŐVÉ teszi (D5), nem „javítja".

### D5 — A chord-latch diagnosztikai kivezetése: `ChordLatchDiagnostics`

Új, csak olvasható értéktípus
(`domain/recognition/chord_latch_diagnostics.dart`) képkockánként:
`tonalness`, `tonalGatePassed`, `winnerLabel`, `winnerIsNoChord`, `winSim`,
`secondSim`, `margin`, `rawConfidence`, `noChordScore`,
`winSimOverNoChordFloor`, `chordConfEma`, `chordConfRise`,
`chordConfRelease`, `emaOverRise`, `belowReleaseFrames`, `chordLatched`,
`expectedTieBreakApplied`, `mode`. Plusz `csvHeader` / `toCsvRow()`, hogy a
felhasználó laptopos futása táblázatba illeszthető legyen.

A rekord **kiolvasáskor épül** a képkocka-út által amúgy is tárolt skalárokból
(`LivePipeline.chordLatchDiagnostics`), tehát a valós idejű hurok **egyetlen
allokációval sem** fizet érte, és semmi a döntési úton nem olvassa vissza.

A dekóder oldalán ehhez `lastWinSim` / `lastSecondSim` / `lastMargin` /
`lastRawConfidence` / `lastWinnerLabel` / `lastWinnerIsNoChord` /
`lastExpectedTieBreakApplied` / `noChordScore` getterek születnek — csak a
streaming `process()` írja őket, a batch utak nem.

A mérőcella (`test/features/live/chord_latch_diagnostics_report_test.dart`)
**szándékosan elvárás-mentes**: egyetlen assert sem hasonlít mért DSP-értéket
küszöbhöz. Egy „a latch behúz" assert vagy a mai hibás viselkedést kódolná be,
vagy vak hangolásra kényszerítene. Csak strukturális ellenőrzések vannak
(lefutott-e, végesek-e a számok, determinisztikus-e), plusz a kinyomtatott
tábla. A `test/support/synth.dart` ehhez kapott determinisztikus
Karplus–Strong generátort (`karplusStrongNote/Chord/StrumPattern`, saját LCG,
`dart:math`'s `Random` nélkül) — a harmonikus-összeg referencia ugyanabban a
riportban fut, hogy a két bemenet oszloponként diffelhető legyen.

### D6 — `RecognitionShadowObserver` seam: kimeneti csap, alapból no-op

```dart
abstract interface class RecognitionShadowObserver {
  void onRecognitionFrame({
    required RecognitionMode mode,
    required LiveFrame frame,
    required ChordPrediction? chord,
    required StrumPrediction? strum,
  });
}
```

Egyetlen hívási pont: `LivePipeline.addChunk`, kibocsátott képkockánként
pontosan egyszer, a MÁR ELKÉSZÜLT képkockával. `void` visszatérés → a
megfigyelő semmit nem tud megváltoztatni; a pipeline soha nem olvas vissza
tőle. Alapértelmezés `NoopRecognitionShadowObserver` (null-objektum), ezért a
seam nélküli és a seam-es termelési út **bit-azonos** (teszttel rögzítve).

Nincs `try`/`catch` a hívás körül: egy elnyelt shadow-hiba pont az a néma
no-op, amit az AGENTS.md tilt — egy hibás megfigyelőnek hangosan kell buknia.

Az izolátum-határ miatt `RealStrumEngine` nem példányt, hanem
`RecognitionShadowObserverFactory`-t (top-level/statikus függvényhivatkozás,
küldhető) kap, és a megfigyelő a DSP izolátumon BELÜL jön létre. Closure
átadása `Isolate.spawn`-nál hangosan bukik — ez a szándék.

Implementációt ez a kör **nem** ír hozzá (PKG-E, 2. hullám).

## Mit mér ez, és mit nem

| Állítás | Státusz |
|---|---|
| Az ablak levezetett, nem hangolt | **TESZTTEL RÖGZÍTVE** (`onset_aligned_chord_transition_test.dart`) |
| Egy nem igazított kiszorítás vár, egy igazított azonnal megerősít | **TESZTTEL RÖGZÍTVE** |
| A kapu sosem fagyasztja be a címkét (elavult onset, óra nélküli képkocka) | **TESZTTEL RÖGZÍTVE** |
| A meglévő ADR 0518 mátrix változatlan | **TESZTTEL RÖGZÍTVE** (a régi cellák óra nélküliek → 1. eset) |
| A seam nélkül/vele bit-azonos kimenet | **TESZTTEL RÖGZÍTVE** (`recognition_shadow_observer_test.dart`) |
| A latch-diagnosztika determinisztikus és teljes | **TESZTTEL RÖGZÍTVE** |
| **A latch VALÓBAN behúz-e KS akkordon, és melyik tag a hibás** | **NEM MÉRT — a riport pont ezért létezik; a felhasználó laptopos futása méri** |
| transition-latency és false-flip SZÁMOK (Ch14 kapu) | **NEM MÉRT** — valós korpusz + eszköz kell |
| Az onset-kapu valós hangon javít-e | **NEM MÉRT** — APK-teszt kell |
