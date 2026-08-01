# ADR 0082 — Free Practice és Rhythm-only: ne állítsunk többet, mint amit mérünk

**Státusz:** elfogadva (E02-R16 pre-flight, 2026-08-01).
Épít az [ADR 0071](0071-practice-chord-label-mapping.md) (veszteséges maj/min
címke-leképezés), [ADR 0072](0072-practice-time-layer.md) (`CompiledPracticeTarget`
időréteg), [ADR 0076](0076-practice-scoring.md) (`PracticeVerdict`, metrika-modell),
[ADR 0078](0078-practice-hub-and-setup.md)/[ADR 0079](0079-state-driven-practice-session-shell.md)
(Practice V2 session-héj) és [ADR 0081](0081-chord-change-measurement.md) (medián-alapú,
csak-mért összegzés) döntéseire.
Kör: [`docs/rounds/e02-r16-rhythm-only-and-free-practice.md`](../rounds/e02-r16-rhythm-only-and-free-practice.md).

## Kontextus

Két mód közös elve: **ne állítsunk többet, mint amit mérünk** (SDD §15). A
Free Practice cél nélküli, **pontozatlan** session; a Rhythm-only célakkord
nélküli ritmusgyakorlás. Mindkettőnél a legnagyobb kockázat a **hamis
pontszám** — egy 0%, egy „—", egy pass/fail, ami valójában „nincs adat".

A döntéseket mért kód rögzíti (`main` @ `ce8fbce`, pre-flight mérés
2026-08-01):

1. **`ScoringProfile.freePracticeOpen`** (`scoring_profile.dart:126`) **üres**
   súlyokkal, `completionThresholdPercent = 0`, `overallThresholdPercent = 0`.
   Az R10 aggregátor (`practice_score_aggregator.dart:76-81`) üres/csupa-nulla
   súlynál `availableWeightTotal == 0` → az `overall` **`MetricNotApplicable`**
   (nem 0, nem null). Ez a mért út, amelyre az A2 acceptance épül.
2. **`PracticeMode.freePractice => const {}`** és
   **`PracticeMode.rhythmOnly => const {PracticeScoreDimension.rhythm}`**
   (`practice_mode.dart:31-32`) — a mérendő dimenziók halmaza.
3. **A metrika-modell** (`practice_metrics.dart`): `MetricAvailable(value)`,
   `MetricNotApplicable()`, `MetricInsufficientData(reasonCode)`. A reason-code
   konstansok (`PracticeMetricReasonCode`, `practice_metrics.dart:211`):
   `noSignal`, `noApplicableTargets`, `chordUnstable`, `insufficientSamples`.
4. **`PracticeAttemptOutcome`** (`practice_attempt_result.dart:10`):
   `passed`, `failed`, `incomplete`, **`notScored`** — az utóbbi a Free
   Practice kimenete.
5. **Aktív idő:** `PracticeSessionState.playingElapsed`
   (`practice_session_state.dart:110`) — a count-in (`countInElapsed`) és a
   pause (`pausedElapsed`) **külön** akkumulátor.
6. **Detektált BPM:** `LiveFrame.bpm` (`live_frame.dart:38`) — a Free Practice
   összegző bemenete (gatewayen keresztül, R08).
7. **Streak-jogosultsági predikátum nincs** (`grep -rn "eligib" lib/` csak
   matcher-kommentre és az onset-detektorra illeszkedik, nincs streak-predikátum)
   — ezt a kör építi fel, tisztán a domainben, **hívó nélkül**.

## Döntés (NEM tárgyalható — a kör kötött szabályai)

1. **Free Practice alatt NINCS** miss, pass/fail, overall accuracy, combo,
   „jól/rosszul játszottál" állítás. A modellben az `overall`
   **`MetricNotApplicable`** (nem 0, nem null-ként ábrázolt hiány), a
   `PracticeAttemptResult.outcome` **`notScored`**, a verdict-lista **üres**,
   `totalTargets == 0`. Ez a modellben helyes — nem a UI rejti el, mert az R18
   result és az R19 progress ebből olvas.

2. **A Free Practice összegző csak tényeket ad:** pengetésszám, le/fel eloszlás
   (darabszám **és** arány), akkord-idővonal (címke + időtartam), detektált
   BPM-minták, tempó-stabilitás, aktív jel időtartama. Semmilyen pontszám,
   pontosság vagy ítélet.

3. **Tempó-stabilitás = MAD-jellegű, medián-alapú.** A szomszédos pengetések
   közti intervallumok **mediántól** vett abszolút eltéréseinek mediánja
   (outlier-tűrő), és **csak** akkor számolható, ha legalább **négy** pengetés
   van (három intervallum); egyébként `MetricInsufficientData`. Az átlag+szórás
   szándékosan elvetve: egyetlen szünet nem jelent instabil tempót.

4. **Rhythm-only dimenziók.** A chord-dimenzió `MetricNotApplicable`; az irány
   **opcionális** — ha a definíció eseményei nem hordoznak irányt, a
   direction-dimenzió is `MetricNotApplicable`, **nem** 0. Nulla megfigyelésnél
   a mérhető dimenziók `MetricInsufficientData`.

5. **Az extra pengetés Rhythm-onlyban informatív.** `ExtraStrumPolicy.ignore`
   mellett az extra pengetés **számlálódik és megjelenik**, de **nem** von le
   pontot és **nem** jelenik meg hibaként (SDD §22.4: kezdőt ne büntessünk).

6. **Aktív idő = `playingElapsed`.** Sem a count-in, sem a pause, sem a setup
   nem számít bele — se a Free Practice összegzőbe, se a jogosultságba.

7. **Streak-jogosultság (SDD §20.5), pure predikátum, hívó nélkül:**

   ```text
   eligible = activeDuration >= 20 s
           || resolvedRequiredTargets >= 4
           || freePracticeStrums >= 8
   ```

   Mindhárom feltétel **`>=`** (VAGY-kapcsolat). A predikátum ebben a körben
   **nincs bekötve** sehová (a bekötés a Kör 19), de teljes mátrix-fedéssel
   tesztelt. A `>` / `>=` felcserélése bármelyik küszöbön hiba.

8. **Nincs kitalált adat.** Ha egy mérőszám nem számolható (nincs elég minta),
   a modell `MetricInsufficientData`-t ad (megfelelő reason-code-dal), és a UI
   **nem** mutat helyette nullát vagy kötőjelet pontszám-szerű formában.

9. **Determinizmus.** Az összegző és a predikátum pure: azonos bemenetre azonos
   kimenet; nincs benne óra, random vagy IO. A domain nem lát detektort — a
   bemenet a megfigyelés-lista + a session-állapot.

## Következmények

- **Előny:** a felhasználó valós tényeket lát (pengetésszám, le/fel arány,
  tempó-stabilitás, akkord-idővonal) hamis pontszám nélkül; a hiányzó
  bizonyítékot a rendszer nem hazudja nullának. A pure, determinisztikus
  összegző és predikátum CI-n és lokálisan azonosan viselkedik.
- **Ár:** egy üres Free Practice összegzés csúnya lehet („nem hallottunk
  pengetést"), de a hamis 0% rosszabb — ez szándékos.
- **Határ:** a streak-jogosultság **bekötése** a Kör 19; a Result-képernyő a
  Kör 18. Ez a kör csak a pure modellt, összegzőt, predikátumot és a két
  mód-nézetet adja.
- **Kockázat:** a hamis állítás a legdrágább hiba; a review kötelező eleme a
  **szöveg-audit mindkét ARB-ben** (nincs „accuracy/%/pass/score") és egy
  **valódi-sértés próba** az A2-re (ideiglenes `MetricAvailable(0)` overall a
  free-practice úton → pirosnak kell lennie).
