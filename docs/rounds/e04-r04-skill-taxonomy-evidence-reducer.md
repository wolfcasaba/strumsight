# E04-R04 — Skill taxonomy, evidence és reducer

- **Státusz:** PREPARED (előre megírva 2026-08-04, kód olvasva: main @ `fbe1e82`)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 4; §35
- **Branch:** `codex/e04-r04-skill-taxonomy-evidence-reducer`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R01 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/domain/models/skill_node.dart",
  "lib/features/ai_tutor/domain/models/skill_evidence.dart",
  "lib/features/ai_tutor/domain/models/skill_estimate.dart",
  "lib/features/ai_tutor/domain/services/skill_evidence_reducer.dart",
  "lib/features/ai_tutor/public.dart",
  "test/features/ai_tutor/domain/skill_taxonomy_test.dart",
  "test/features/ai_tutor/domain/skill_evidence_reducer_test.dart",
  "docs/rounds/e04-r04-skill-taxonomy-evidence-reducer.md",
]
gate_tests = [
  "test/features/ai_tutor/domain",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E04-R01 merge; olvasd újra
> `AGENTS.md`, Chapter 1/5, `HANDOFF.md`. Nincs ÚJ ADR (R01 0131 bővítése).
> `rg`: domain-purity őr; a Practice/Song eredménymodellek **public** felülete
> (`lib/features/{practice,song_trainer}/public.dart`) — a reducer csak a
> később (R05) adaptált, redaktált evidence-t fogyasztja, NEM a source feature
> belső típusait. PREPARED→PLANNING, brief commit az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED — a mért §0.0-t az élesedő pre-flight tölti ki.** Nincs előre kiosztott ADR.

## 1. Cél

Egységes **skill graph** és **készségbizonyíték-modell** létrehozása, amely a
szórt progress-adatot determinisztikus, forrásjelölt skill-becsléssé redukálja.

## 2. Jelenlegi állapot

- Nincs egységes skill graph vagy evidence-modell (SDD §3.2/4).
- A progress-adat több feature-ben, eltérő formában él (Practice/Song/Analyze/
  Progress/Streak) — public barrelen át elérhető, de nem egységes.
- A reducernek **tiszta függvénynek** kell lennie (E02-R10 scorer-precedens:
  belül egész-aritmetika, kifelé normalizált érték; lebegőpont-akkumuláció tilos).

## 3. Scope

**Benne:** `SkillNode` (taxonómia), `SkillEvidence` (forrásjelölt bizonyíték-elem
provenance + scorer/schema version-nel), `SkillEstimate` (redukált becslés +
bizonyosság), `SkillEvidenceReducer` (pure, determinisztikus, stable-order).

**Kívül — TILOS:** context-assembly (R05), UI, cloud, provider-SDK, source feature
belső import.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/models/skill_node.dart` | ÚJ | skill taxonómia |
| `.../domain/models/skill_evidence.dart` | ÚJ | forrásjelölt bizonyíték |
| `.../domain/models/skill_estimate.dart` | ÚJ | redukált becslés |
| `.../domain/services/skill_evidence_reducer.dart` | ÚJ | pure reducer |
| `lib/features/ai_tutor/public.dart` | előző körökből | additív export |
| `test/features/ai_tutor/domain/*` | ÚJ | taxonómia + reducer tesztek |
| `docs/rounds/e04-r04-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, más feature belső contractja, `docs/rag`,
más kör briefje. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. A reducer **pure és determinisztikus** — azonos evidence-halmazra bit-azonos
   becslés, stable tie-break (ADR 0131). **NEM elfogadható:** rendezéstől függő
   vagy lebegőpont-akkumulált eredmény.
2. Minden `SkillEvidence` **provenance + scorer/schema version**-t hordoz — verzió
   nélküli bizonyíték nem kerülhet a becslésbe.
3. Két összehasonlítható evidence-group kell trend-becsléshez (SDD DoD: trend ≥ 2 group).
4. A domain Flutter-/provider-SDK-mentes.

## 6. Acceptance criteria

- [ ] A reducer determinisztikus: shuffle-elt evidence-sorrendre azonos becslés
      (property-teszt seeddel); stable tie-break literálisan tesztelt.
- [ ] Trend csak **≥2** összehasonlítható groupból; 1 groupnál a becslés
      „insufficient" — **mátrix:** 0 / 1 / 2 evidence-group.
- [ ] Verzió nélküli evidence elutasított (fail-loud), nem néma befogadás.
- [ ] Domain purity-őr zöld; **≥90% coverage**.

A reviewer a determinizmust független reference-számítással vagy shuffle-mutációval
pirosra váltja.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/domain
```

Külön processzek, nincs `&&`/pipe/`tail`. CI = orchestrátor.

## 8. Implementációs sorrend

1. RED determinizmus + trend-mátrix + verzió-reject tesztek.
2. Taxonómia + evidence + estimate modellek.
3. Pure reducer.
4. Additív export; gate.

Javasolt commit: `feat(ai-tutor-domain): add skill taxonomy evidence and reducer`.

## 9. Kockázatok

- A reducer csábítható source-feature belső típusra hivatkozni — TILOS; csak a
  R05 adaptált, redaktált evidence a bemenet.
- Lebegőpont-akkumuláció determinizmus-törés — egész/normalizált aritmetika.

**STOP:** source-belső import, nem-determinisztikus becslés vagy mércegyengítés
helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r04-skill-taxonomy-evidence-reducer-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
