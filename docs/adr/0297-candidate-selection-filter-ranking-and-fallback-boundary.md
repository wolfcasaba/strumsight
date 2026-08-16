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
A difficulty, soft preference, mérhetőség és recent-overuse policy-faktorok
csak azonos vagy policy szerint közeli relevancián belül rendeznek. Diversity
és az injektált seedből számolt exploration ezért nem tehet kevésbé releváns
elemet az első helyre. A teljes tie-break stabil lexical candidate identity.

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

Az E07-R13 A1–A8 unit-cellái, különösen a hard-filter valódi-sértés próbája,
az offline/fallback kizárás, a relevance-et nem felülíró diversity, és azonos
seedre stabil decision bizonyítják a boundary-t.
