# ADR 0540 — Chord-kalibráció, nyílt halmazú („ismeretlen akkord”) döntés és selective prediction

**Státusz:** elfogadva (2026-09-09) · **Kör:** E14-R32 · **Párja:** ADR 0536 (strum-sáv) · **Kapcsolódik:** ADR 0505 D2, ADR 0509 (`chordUnknownFalseAccept`), ADR 0516/0535 (chord-döntés és okok)

## Kontextus (mért)

- `ChordPrediction.calibratedConfidence` **`null`**, a `decision` és a
  `rejectReason` konstruktor-kapott (ADR 0505: kalibráció nélküli
  származtatás tiltott).
- A szállított szótár **zárt**: `assets/ml/model_manifest.json`
  `output_classes` = `N.C.` + 12 dúr + 12 moll (25 osztály). Egy sus4/add9/7
  akkordra **nincs helyes válasz** — a dekóder ma mégis a legközelebbi
  maj/min-t nevezi meg.
- A metrika-készlet már ma **két külön** metrikával méri a két állapotot:
  `chordNoChordF1` (a `noChord` címkére) és `chordUnknownFalseAccept` (az
  `unknown` címkére) — a szemantikai szétválasztás tehát a mérés oldalán már
  létezik, a döntés oldalán nem.
- `chord_matcher.dart:99–100`: `margin = (best − second)/best`,
  `confidence = best·(0,5 + 2·margin)` — ez a mai bizonytalanság-jelzés, és
  ez a kör **nem nyúl hozzá**.

## Döntés

### D1 — `noChord` és `unknown` KÜLÖN válasz, sosem esnek egybe

`ChordOpenSetOutcome`: `noChord` (nem szól semmi) · `unknownChord` (szól
valami, de a modellnek nincs rá osztálya) · `supportedChord`. A két
fenntartott értékelési címke konstansként is rögzített
(`recognitionNoChordLabel = 'noChord'`,
`recognitionUnknownChordLabel = 'unknown'`), és teszt pinneli, hogy
különbözőek. A `ChordClassKey.tryParseLabel` mindkettőt visszautasítja: ezek
nem akkordosztályok.

### D2 — A döntés tiszta függvény a megnevezett bizonyítékon

`decideChordOpenSet({evidence, policy})` a `winSim` és a `margin` felett
dönt, kiértékelési sorrendje szerződés: N.C.-padló → unknown-hasonlóság →
unknown-margin → supported. A határ a **informatívabb** oldalé (szigorú
`<`), összhangban az ADR 0511 D3 konvenciójával. Motor-állapotot nem olvas,
tehát audió nélkül teljesen tesztelhető.

### D3 — Egyetlen küszöb sem születik itt

`ChordOpenSetPolicy` minden mezője kötelező bemenet. A **szállított**
alapérték `ChordOpenSetPolicy.disabled()`: minden padló 0, tehát a függvény
sem `noChord`-ot, sem `unknown`-t nem tud kiadni — bekötve **bitre a mai
viselkedés**. Van `noChordOnly(similarityFloor:)` is, amely a hívó meglévő
N.C.-padlóját viszi tovább, unknown nélkül. Új küszöb csak mért adatból, külön
ADR-rel (Ch14 §12/1).

### D4 — A kalibrációs artefaktum ugyanaz a formátum, `band: "chord"`

Az ADR 0536 D1–D6 változatlanul érvényes; a chord-sáv annyival bővül, hogy az
artefaktum **root+quality tudatos**: `perClassMappings` kulcsa
`"<root>:<quality>"` (pl. `A:min`), és per-osztály leképezés csak a default
leképezés MELLETT, nem helyette. Egy strum-artefaktum, amely per-osztály
leképezést hoz, elutasított. A `ChordPrediction.calibratedConfidence`
bekötési pontja ugyanaz a `ConfidenceCalibrationResolver`; a fán ma nincs
chord-artefaktum, tehát az érték marad `null`.

### D5 — Selective prediction: közös mechanizmus, sávonként külön policy

A `selective_prediction.dart` sávfüggetlen; a chord-sáv ugyanazt a
risk–coverage görbét és coverage-maximalizáló szelektort használja. A
`0,88`-as confirmed accepted accuracy (Ch14 §7.4) ezen a görbén olvasható ki
— **ha** lesz korpusz.

### D6 — A UI-szöveg NEM ebben a körben születik

Az „Ismeretlen akkord” és a „Nincs akkord” **két külön** felhasználói
állapot, két külön ARB-kulccsal; a szövegek és a banner PKG-F/PKG-A
hatásköre. Ez a kör a domain-döntést és a két címke szétválasztását
szállítja, hogy a UI-nak legyen mit megjelenítenie.

## Ami MÉRVE van és ami NINCS

**Mérve:** a három kimenet szétválása, a határok viselkedése, a disabled
policy identitás-volta, az artefaktum per-osztály feloldása, a
`noChord`/`unknown` címkék különbözősége.

**NINCS mérve (NEEDS-MEASUREMENT):** az unknown-padlók értéke; a
per-osztály minimum recall; a hard-negatív false-accept ráta; bármely
chord-ECE. Mindhez a §7.1 korpusz és a `chord-train.yml` mérés kell
(`docs/eval/chord-corpus-plan.md`,
`docs/eval/calibration-and-selective-prediction.md`).
