# E14-R32 — Chord kalibráció, unknown/open-set és selective prediction

- **Státusz:** LESZÁLLÍTVA (mechanizmus) / **PARTIAL** (küszöbök és mérés hiányzik)
- **ADR:** [`0540`](../adr/0540-chord-calibration-open-set-and-selective-prediction.md)
- **Csomag:** PKG-B · **Készült:** 2026-09-09

## 1. Cél

(a) A chord-sáv kapja meg ugyanazt a modellhez kötött kalibrációs
artefaktumot, **root+quality tudatosan**; (b) legyen tiszta függvényes
open-set döntés, amely a `noChord` és az „ismeretlen akkord” állapotot
**szétválasztja**; (c) mindez úgy, hogy alapértelmezésben semmi nem változik.

## 2. Mért kiindulóállapot

- `ChordPrediction.calibratedConfidence` = `null`; a `decision`/`rejectReason`
  konstruktor-kapott.
- A szótár zárt: 25 osztály (`N.C.` + 12 dúr + 12 moll); sus4/add9/7 akkordra
  nincs helyes válasz, a dekóder mégis a legközelebbi maj/min-t nevezi meg.
- A metrika-oldal **már** szétválasztja a kettőt: `chordNoChordF1`
  (`noChord`) vs `chordUnknownFalseAccept` (`unknown`).
- `chord_matcher.dart:99–100` konfidencia-képlete a mai jelzés — ez a kör nem
  nyúlt hozzá.

## 3. Scope

BENNE: `band: "chord"` artefaktum + `perClassMappings` (`"<root>:<quality>"`);
`ChordClassKey` címke-bontás; `decideChordOpenSet` tiszta függvény
`ChordOpenSetPolicy`-vel (alapérték: `disabled()` = identitás); a két
fenntartott értékelési címke konstansként.

KÍVÜL: bármely küszöb értéke; a `chord_matcher.dart` (PKG-A); az UI-szövegek
és ARB-kulcsok (PKG-F/PKG-A); a `ChordPrediction` bekötése (PKG-A, 2. hullám).

## 4. Fájlok

Új:
- `lib/features/live/domain/evaluation/chord_open_set_decision.dart`
- `test/features/live/evaluation/chord_open_set_decision_test.dart`

Bővített (E14-R21-gyel közösen):
- `lib/features/live/domain/evaluation/confidence_calibration_profile.dart`
  (`CalibrationBand.chord`, `perClassMappings`, `ChordClassKey`,
  `recognitionNoChordLabel`, `recognitionUnknownChordLabel`)
- `test/features/live/evaluation/confidence_calibration_profile_test.dart`

## 6. Acceptance

| # | Kritérium | Állapot |
|---|---|---|
| 1 | `noChord` és `unknown` sosem esik egybe | **PINNED-BY-TEST** |
| 2 | Alapértelmezett policy = identitás (nincs új elhallgattatás) | **PINNED-BY-TEST** |
| 3 | Nem támogatott akkord (közel egyforma két jelölt) `unknown`, nem a legközelebbi maj/min | **PINNED-BY-TEST** (mért policy mellett) |
| 4 | A határ az informatívabb oldalé | **PINNED-BY-TEST** |
| 5 | Tartományon kívüli bizonyíték = tipizált hiba, nem néma clamp | **PINNED-BY-TEST** |
| 6 | Chord artefaktum per-osztály leképezése a defaultot csak arra az osztályra írja felül | **PINNED-BY-TEST** |
| 7 | Strum artefaktum per-osztály leképezéssel elutasított | **PINNED-BY-TEST** |
| 8 | `ChordPrediction.calibratedConfidence` marad `null` artefaktum nélkül | **PINNED-BY-TEST** (a resolver szintjén) |
| 9 | Az unknown-padlók értéke, per-class recall, hard-negatív false-accept | **NEEDS-MEASUREMENT** |
| 10 | Reliability-diagram valós chord-adaton | **NEEDS-MEASUREMENT** |

## 7. Verifikáció

Lokális gate nem futtatható; a cellák a §6-ban.

## 10. Handoff

- **PKG-A (2. hullám):** a `ChordPrediction` építésekor a resolver hívása; az
  open-set kimenet leképezése `RecognitionDecision`/`RecognitionRejectReason`
  párra (a `noChord` és az `unknown` **külön** ok legyen).
- **PKG-F:** két külön felhasználói állapot, két külön ARB-kulcs kell
  („Nincs akkord” vs „Ismeretlen akkord”); a domain oldal készen áll.
- **Küszöbök:** csak mért adatból, külön ADR-rel (Ch14 §12/1).
