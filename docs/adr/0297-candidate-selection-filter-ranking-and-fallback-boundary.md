# ADR 0297 — A jelöltválasztás hard-szűrésből, másodlagos diversityből és azonos-skill fallbackből áll

**Státusz:** elfogadva (2026-08-16). Az Epic 7 jelöltválasztási döntése.
Forrás: [`docs/sdd/08-epic-07-ai-practice-generator.md`](../sdd/08-epic-07-ai-practice-generator.md) Ch8 Kör 13.
Épít: [ADR 0255](0255-deterministic-first-practice-planning.md),
[ADR 0258](0258-hard-and-soft-planning-constraints.md),
[ADR 0262](0262-catalog-snapshot-revisions-and-capability-truth.md),
[ADR 0264](0264-explainable-priority-and-versioned-policy.md).

## Kontextus

Az R12 `SkillPriority` output skill-szintű, az R08 catalog pedig csak
végrehajtható `ExerciseCandidate` elemeket hordoz. A választónak úgy kell a
skill-prioritást konkrét gyakorlattá alakítania, hogy a hard korlát nem válhat
pontszámmá, a repetíció ne uralja a tervet, és minden elutasítás magyarázható
maradjon.

## Döntés

### 1. A selector inputja catalog snapshot és typed végrehajthatósági truth

A selector kizárólag `PracticeCatalogSnapshot` candidate-jeiből választ. A
futáskori hard truth identity-alapú halmazokból érkezik (hard avoid és a
szükséges offline/device/asset/tuning megerősítések); nem olvassa vagy
értelmezi a `LearnerConstraint.value` szabad szövegét. Hiányzó megerősítés
fail-closed kizárás.

`contentLocked` nem selector-input: az R08 adapter ezt már a snapshotba kerülés
előtt kizárja, warningként megőrizve. A selector tehát sem elsődlegesen, sem
fallbackként nem tud locked tartalmat visszahozni.

### 2. Hard filter megelőzi a score-t

Hard-avoided, végrehajthatatlan vagy a cél-skillt nem tartalmazó candidate a
rangsorolás előtt elutasított `CandidateDecision` rekordot kap. Nincs olyan
pontszám vagy exploration eredmény, amely egy ilyen elemet visszaengedhet.

### 3. Rangsor: relevance első, diversity és exploration csak másodlagos

A selector a matching skill prioritását használja elsődleges relevanciának.
A candidate-szintű soft ranking inputok (`difficultyAffinity`,
`preferenceAffinity`, `measurabilityScore` a
`CandidateRankingProfile`-ban, a `CandidateRuntimeContext.rankingProfiles`
map által szállítva) és a `recentOverusePenalty` a selector kompozit score-ját
adják:

```
compositeScore = priority.score
                + difficultyWeight   * difficultyAffinity
                + preferenceWeight   * preferenceAffinity
                + measurabilityWeight * measurabilityScore
                - recentOverusePenalty (ha a jelölt recentlyUsed)
```

A három soft-súly (`CandidatePolicy.difficultyWeight`,
`preferenceWeight`, `measurabilityWeight`) tipizált, validált policy-mező,
alapértelmezetten `0` — ez garantálja, hogy a default policy a korábbi
lexikális viselkedést reprodukálja. A score/relevance contract a
`SelectedCandidate.factors` listán kötelezően megjelenik: minden nem nulla
kontribúciójú tényező külön `CandidateFactor` rekord (kind + normalized
+ contribution), és a lista összege == `compositeScore`. A `weight=0` /
érték≠0 pár NEM jelenik meg a factor-listán — a policy a gate.

A diversity ablak (`diversityWindow`) a top bucket határa: a top
`compositeScore`-tól számított abszolút eltérés legfeljebb `diversityWindow`
értékű lehet. Az `explorationWeight` a bucketön belüli determinisztikus
seed-permutáció kapcsolója. `0` ⇒ szigorú lexikális rendezés, a seed soha
nem befolyásolja a nyertest. Pozitív érték ⇒ a seed egy determinisztikus
FNV-stílusú hash-szel permutálja a bucket elemeit, lexikális tie-breakkel,
de a permutáció eredménye SOHA nem lépheti át a `diversityWindow` által
meghatározott bucket határt. Ezért a diversity/exploration nem tehet
kevésbé releváns elemet az első helyre. A teljes tie-break stabil lexical
candidate identity. A selector nem használ `Random`-ot, `DateTime.now()`-t,
vagy a `LearnerConstraint.value` szabad szövegét.

### 4. A fallback ugyanazt a skillt szolgálja

Ha az első jelölt kiesik, a fallback csak ugyanahhoz a cél-skillhez illeszkedő,
hard-filteren átment candidate lehet. Más skillre váltás a következő
tervezési kör felelőssége, nem egy néma selector-fallback.

### 5. A döntés diagnosztizálható és provenance-os

A `CandidateDecision` immutable, policy-versiont, seed-provenance-ot,
rendezett kiválasztott/fallback referenciát és a teljes, okkal együtt rendezett
rejected-listát hordozza. A magyarázat a tényleges filter/ranking eredmény,
nem utólag generált szöveg.

## Következmények

- Locked/catalog-kizárt tartalom visszahozása strukturálisan lehetetlen;
  offline vagy más végrehajthatósági bizonytalanság fail-closed.
- A selector domain-pure és clock/random-mentes marad; a seed caller-input.
- A time allocation és weekly scheduling továbbra is R14/R15 feladata.

## Mérce

Az E07-R13 unit-cellái bizonyítják a boundary-t:

- **A1–A2** — hard filter uncrossable, `locked`/`offline-unconfirmed` nem
  választható, fallbackként sem. A §10.5 valódi-sértés próba (hard-kizárás
  nagy negatív pontszámra cserélve) az A1 cellát pirosra váltja.
- **A3** — distinct candidate-szintű soft ranking faktorok (`difficulty`,
  `preference`, `measurability`) distinct composite score-t és distinct
  bucket-határt produkálnak; a seed a top bucketon belül sem tud kevésbé
  releváns jelöltet előre vinni. A `diversityWindow`-en kívüli jelölt a
  permutációval sem kerülhet a kiválasztott helyére.
- **A4** — `explorationWeight=0` ⇒ szigorú lexikális rendezés, a seed nem
  befolyásolja a nyertest. `explorationWeight>0` azonos seed-del ⇒ azonos
  decision; eltérő seed-del a bucketön belül determinisztikusan permutál.
- **A5** — a döntés felsorolja az elutasítottakat, okkal és detail-lel.
- **A6** — a fallback ugyanazt a skillt célozza és átment a hard filteren.
- **A7** — a recent-overuse penalty megjelenik a kompozit score-on és a
  factor-listán.
- **A8** — a fallback identity seed-független (canonical ranked listából
  jön), a tie-break stabil lexical.
- **Per-factor observability** — minden soft faktor (`difficulty`,
  `preference`, `measurability`) saját unit-cellával bizonyítja, hogy a
  factor contribution = `weight * value`, és a faktor megjelenik a
  `SelectedCandidate.factors` listán a megfelelő `kind`/`normalizedValue`/
  `contribution` értékekkel.
