# ADR 0081 — Akkordváltás-mérés: csak mért állítás, előjeles felismerési késés, medián-összegzés

**Státusz:** elfogadva (E02-R15 pre-flight, 2026-08-01).
Épít az [ADR 0071](0071-practice-chord-label-mapping.md) (veszteséges,
sharp-spelled 24-elemű maj/min címke-leképezés), [ADR 0072](0072-practice-time-layer.md)
(`CompiledPracticeTarget`/`ExpectedChordSegment` időréteg),
[ADR 0076](0076-practice-scoring.md) (`PracticeVerdict` + `ChordOutcome`) és
[ADR 0078](0078-practice-hub-and-setup.md)/[ADR 0079](0079-state-driven-practice-session-shell.md)
(Practice V2 session-héj) döntéseire.
Kör: [`docs/rounds/e02-r15-chord-change-mode.md`](../rounds/e02-r15-chord-change-mode.md).

## Kontextus

A Chord Change mód a termék egyik legkonkrétabb ígérete: két (vagy több)
akkord váltogatása, és a **váltás mérhető minősítése** — akkordpáronkénti
statisztikával, amiből a felhasználó megtudja, melyik váltás a leglassabb.

A tétje nem a tartalom (a `BuiltinPracticeCatalog` már tartalmaz G↔D
(`builtin.gToDChanges.v1`) és Em↔C (`builtin.emToCChanges.v1`)
akkordváltás-gyakorlatokat, `PracticeMode.chordChanges`, `main` @ `02b5499`),
hanem **mit állítunk a mérésből**. A detektor akkord-*címkét* lát, nem
ujjrakást — a fizikai valóságot (szólnak-e a húrok, tiszta-e a fogás) nem méri.
Ezért ennek a körnek a legfontosabb szabálya: **csak azt állítjuk, amit tényleg
mérünk** (SDD §15).

A döntéseket mért kód rögzíti (`main` @ `02b5499`):

1. **`ChordObservation(at, label, confidence)`** — a `label` **nullable**
   (`null` = explicit „nincs akkord"), a címke kanonikus (sharp-spelled) és a
   detektor 24-elemű maj/min szótárára korlátozott
   (`isCanonicalPracticeChordLabel`, `practice_observation.dart:61`).
2. **A veszteséges leképezés** (`legacyPracticeChordLabel`, ADR 0071 §2) miatt
   bizonyos akkordok (pl. `Em7 → Em`) nem különböztethetők meg — ez a mérés
   eleve durvább, és ezt jelölni kell, nem elhallgatni.
3. **A `PracticeVerdict`** (`practice_verdict.dart:60`) hordozza a
   `targetAt`, `expectedChord`, `observedChord`, `chordOutcome` mezőket; a
   `ChordOutcome` enum (ma öt tag: `correct`, `wrong`, `insufficientData`,
   `notApplicable`, `noDetection` — a `noDetection` R10/ADR 0076 óta) a
   **cél-eseményenkénti** ítélet, NEM a párra vetített váltás-kimenet.
4. **A stabilitási küszöb** alapértéke **180 ms**
   (`PracticeObservationConfig.chordStableDuration`,
   `_defaultChordStableDuration`), és a chord-scorer ablaka
   `[targetAt − 120 ms, targetAt + 420 ms]` (`practice_chord_scorer.dart:9-11`).
5. **Nincs chord-pair statisztika** sehol (`grep -rn "chordPair\|chord_pair"
   lib/` → 0 találat) — ez a kör építi fel, tisztán a domainben.

## Döntés (NEM tárgyalható — a kör kötött szabályai)

1. **Csak mért állítás.** A modell és a UI szóhasználata: „**felismert és
   stabil akkord**". A `clean chord`, „tiszta fogás", „minden húr szól" típusú
   állítás **tilos** — nincs mögötte mérés (SDD §15).

2. **A váltás definíciója.** Egy akkordpár-váltás a compiled targetben az a
   pont, ahol az elvárt akkord `A`-ról `B`-re vált. A **felismerési késés**
   (`recognizedChangeDelay`) az elvárt váltás pillanatától az **első olyan**
   `ChordObservation`-ig eltelt idő, amelynek címkéje `B` **és** amely eléri a
   stabilitási küszöböt. Ha ilyen nincs az ablakban → a váltás **nem** kap
   késés-értéket (nem nulla, nem „végtelen": **hiányzó**).

3. **Az összesítés medián, nem átlag.** A páronkénti késés reprezentánsa a
   **medián** (outlier-tűrés), és a medián **csak akkor** számolható, ha a
   párnak legalább **három** mért váltása van; egyébként
   `MetricInsufficientData`. Páros elemszámnál a medián a két középső átlaga.

4. **Öt megkülönböztetett kimenet váltásonként:** `correct` · `wrongChord` ·
   `noDetection` · `unstable` · `insufficientSignal`. Ezek **nem** vonhatók
   össze; a UI mindegyiket másképp mutatja. Ez a váltás-kimenet enum a Chord
   Change analyzer **saját** típusa, elkülönítve a cél-eseményenkénti
   `ChordOutcome`-tól (§Kontextus 3).

5. **Determinizmus.** Az elemző pure: azonos bemenetre azonos kimenet; nincs
   benne óra, random vagy IO. A rendezés (pl. „leglassabb pár") **stabil**:
   holtversenynél az akkordpár kanonikus (címke szerinti lexikografikus)
   sorrendje dönt — soha nem a `Map` iterációs sorrendje.

6. **A statisztika bemenete a verdict + a megfigyelés-lista**, nem a nyers
   frame-folyam. A domain nem lát detektort.

7. **A veszteséges címke-leképezés látszik.** Ha a definíció olyan akkordot
   kér, amit a detektor szótára nem tud megkülönböztetni (ADR 0071 §2), azt a
   modell **explicit jelöléssel** adja tovább — a UI ne állítson pontos
   akkord-ítéletet ott, ahol a mérés eleve durvább.

8. **Nincs no-strum vak folt.** Ha a váltás körül **egyetlen** strum sem volt,
   a váltás `insufficientSignal` — nem `wrongChord` és nem `correct`.

## Következmények

- **Előny:** a felhasználó valós, előjeles (korai/kései) váltási késést lát
  párra bontva, és a hiányzó/kevés bizonyítékot a rendszer nem hazudja
  nullának. A pure, determinisztikus elemző CI-n és lokálisan azonosan
  viselkedik.
- **Ár:** a medián három-váltásos küszöbe miatt a rövid session-ök egy része
  `MetricInsufficientData`-t mutat — ez szándékos: kevés bizonyítékból nem
  állítunk statisztikát.
- **Határ:** a páronkénti Result-bontás (Kör 18) és a coaching-mondatok (Kör 18)
  ezen a modellen épülnek majd; ez a kör csak az adatszerkezetet és a
  mód-nézetet adja.
- **Kockázat:** a hamis állítás (§1) a legdrágább hiba; a review kötelező eleme
  a szöveg-audit mindkét ARB-ben.
