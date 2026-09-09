# Release-kapu fokozatok és kontrollált rollout (E14-R24 / E14-R33)

- **ADR:** [0537](../adr/0537-gate-stages-and-clamped-rollout.md) (strum),
  [0541](../adr/0541-chord-gate-rows-and-rollout.md) (chord)
- **Fájl:** [`evaluation/recognition/recognition_release_gate.json`](../../evaluation/recognition/recognition_release_gate.json)
  (`thresholdsVersion: ch14-alpha-v1`, `schemaVersion: "1"` — változatlan)
- **Kód:** `…/domain/evaluation/recognition_release_gate.dart` (stage/band/enabled),
  `…/domain/evaluation/rollout_licence.dart` (clamp)

## 1. A kapu-sor három új, OPCIONÁLIS mezője

| Mező | Alap | Jelentés |
|---|---|---|
| `stage` | `alpha` | `alpha` = Ch14 §7.2/§7.4 minimum, `beta` = §7.3/§7.5 cél |
| `band` | `shared` | `strum` \| `chord` \| `shared` — melyik modell rolloutját fogja |
| `enabled` | `true` | `false` = **informatív** sor |

Az alapértékek miatt egy E14-R24 előtti kapu-fájl **jelentése bitre azonos**
marad. A `passed` verdikt csak az **engedélyezett** sorokra épül.

## 2. Mi az „informatív” sor

Egy `enabled: false` sor **kiértékelődik és megjelenik a riportban**, de:

- **nem bukik meg** tőle a verdikt (nem blokkolja a mai Alpha munkát), és
- **nem is engedélyez semmit**: az a fokozat, amelynek a sorai le vannak
  tiltva, **elérhetetlen** (`RolloutClampReason.gateRowDisabled`).

Ez az aszimmetria a lényeg: a Beta célok láthatóak és verziózottak, de sem
kapuként, sem teljesítettként nem viselkednek. A riport ezért `INFO (above
target)` / `INFO (below target)` státusszal rendereli őket, sosem sima
`FAIL`-lel.

## 3. A mai sorok

**Alpha (10 sor, mind engedélyezve, változatlan érték)** — §7.2/§7.4:
onset F1@50 ms 0,82 · direction macro-F1 0,80 · accepted accuracy 0,90 ·
coverage 0,70 · false visible event ≤ 2/perc · latency p50 ≤ 180 ms ·
p95 ≤ 280 ms · chord weighted accuracy 0,80 · chord macro-F1 0,70 ·
N.C./unknown F1 0,88.

**Beta (12 sor, MIND letiltva, informatív)** — §7.3/§7.5:
onset F1 ≥ 0,87 · Down F1 ≥ 0,88 · Up F1 ≥ 0,84 · accepted accuracy ≥ 0,93 ·
coverage ≥ 0,80 · false visible ARROW ≤ 1/perc · p95 ≤ 250 ms ·
chord weighted accuracy ≥ 0,86 · chord macro-F1 ≥ 0,78 · N.C./unknown F1 ≥ 0,92 ·
leggyengébb támogatott chord recall ≥ 0,65 · false CONFIDENT chord ≤ 1/perc.

Három új, **származtatott** metrika-út lett nevezhető (új mérés nélkül, a
meglévő per-label blokkokból): `directionF1.perLabel.down.f1`,
`directionF1.perLabel.up.f1`, `chordMacroF1.weakestSupportedRecall` (ez
utóbbi kihagyja a fenntartott `noChord`/`unknown` címkéket és a nulla
supportú osztályokat).

## 4. Ami NEM ábrázolható ma (és ezért nincs a fájlban)

| Ch14 sor | Miért nincs |
|---|---|
| Event finalization flip ≤ 1% (§7.3) | a metrika-készletben nincs „flip” fogalom (ADR 0509) |
| Confirmed chord accepted accuracy (§7.4 0,88 / §7.5 0,92) | nincs `confirmed`-re szűkített accepted-accuracy metrika |
| Chord transition p50 ≤ 350 ms (§7.4), p95 ≤ 500 ms (§7.5) | a latency-metrika a verdikt-latency, nem a chord-váltás ideje |

Egy nem létező `metricPath` a kapuban **tipizált hiba**, nem néma átugrás —
ezért ezek a sorok inkább hiányoznak, mint hogy hamis útvonalat kapjanak. Új
metrika = új mérési kör a `recognition_metrics.dart`-ban (PKG-B), utána egy
`enabled: false` Beta sor.

Ugyanígy **nem** került be a §7.4 két Alpha sora (leggyengébb chord recall
≥ 0,55, false confident chord ≤ 2/perc): ezek most már ábrázolhatók
(`chordMacroF1.weakestSupportedRecall`, `falseVisibleChordEventsPerMinute`),
de hozzáadásuk **megváltoztatná az élő Alpha kaput**, amit ez a kör
szándékosan érintetlenül hagy. Ez a legközelebbi chord-mérési kör első
teendője.

## 5. Rollout-clamp

A **létra PKG-D tulajdona**
(`lib/app/config/recognition_rollout_stage.dart`, ADR 0542):

```
off → shadow → alpha → beta → ga
```

`clampRolloutStage(band:, stageName:, verdict:)`
(`…/domain/evaluation/rollout_licence.dart`) a **kért** fokozatot a kapu
által engedélyezettre vágja:

- `shadow` ⇐ **pontosság nem engedélyezi és nem is tiltja** — sosem
  felhasználó-látható, ezért a shadow-főkapcsoló őrzi
  (`recognitionShadowModeEnabled` / `recognitionChordShadowModeEnabled`,
  ADR 0542 D2), nem a metrika;
- `alpha` ⇐ minden alpha sor (band + shared) engedélyezve ÉS átment;
- `beta` és `ga` ⇐ ugyanez a beta sorokra is (ez a PKG-D-oldali
  `RecognitionRolloutStage.requiresBetaThresholds` gépi tükre);
- ismeretlen fokozatnév ⇒ `off` (`unrecognisedStageName`), sosem a
  legközelebbi ismert fokozat;
- a clamp **csak csökkenthet**; a döntés megnevezi a korlátozó
  `metricPath`-okat.

A `ga` a kapu felől ugyanazt kéri, mint a `beta`; az emberi jóváhagyás
(R40 field study, rollback-gyakorlat, `docs/release/ch14-recognition-rollout.md`)
**process-lépés, amit ez a kiértékelő nem képes és nem is akar ábrázolni**.

**Zászló-tulajdon:** a `strumModelRolloutStage` és a `chordModelRolloutStage`
mező a `FeatureFlags`-ben él (PKG-D); az evaluation réteg csak **névként**
hivatkozik rájuk (`recognitionRolloutFlagNames`) és a fokozatot a
`LicensedRolloutStage` névtükrén keresztül kapja meg — importálni nem
importálja, hogy Flutter- és app-független maradjon. A tükröt teszt pinneli
(érték-lista + `requiresBetaThresholds`).

## 6. A mai valóság

A legacy DSP baseline (chord accuracy 0,671, onset F1 0,674, direction 0,807)
**megbukik** az Alpha kapun — ez a kapu helyes működése, nem hiba. Ebből
következik, hogy a mai effektív rollout-fokozat mindkét sávon legfeljebb
**`shadow`** (a `FeatureFlags` alapértéke `off`, tehát ma `off`), és a Beta
letiltott sorai miatt `beta` akkor sem érhető el, ha az Alpha egyszer zöldre
fordul.
