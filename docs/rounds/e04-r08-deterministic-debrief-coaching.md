# E04-R08 — Deterministic debrief és coaching fallback

- **Státusz:** PREPARED (előre megírva 2026-08-04, kód olvasva: main @ `fbe1e82`)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 8; §35
- **Branch:** `codex/e04-r08-deterministic-debrief-coaching`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R04 + E04-R05 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/domain/models/debrief_fact.dart",
  "lib/features/ai_tutor/domain/models/coaching_insight.dart",
  "lib/features/ai_tutor/application/debrief/session_debrief_builder.dart",
  "lib/features/ai_tutor/application/debrief/deterministic_coach.dart",
  "lib/features/ai_tutor/public.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/ai_tutor/application/session_debrief_builder_test.dart",
  "test/features/ai_tutor/application/deterministic_coach_test.dart",
  "docs/rounds/e04-r08-deterministic-debrief-coaching.md",
]
gate_tests = [
  "test/features/ai_tutor/application",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E04-R04/R05 merge; olvasd újra
> `AGENTS.md`, Chapter 1/5, `HANDOFF.md`. Nincs ÚJ ADR. `rg`: az R05
> `TutorContextSnapshot` + R04 evidence-modell mai alakja; a legacy Practice
> `PracticeCoach`→`PracticeInsight` (ADR 0084) mint parity-referencia; az ARB
> generált output gitignore-olt → `flutter gen-l10n` a gate előtt (L48/HEAL
> E03-R14 tanulság). PREPARED→PLANNING, brief commit az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED — a mért §0.0-t az élesedő pre-flight tölti ki.** Nincs előre kiosztott ADR.

## 1. Cél

Cloud modell **nélkül** is megbízható, lokalizált, **bizonyíték-alapú**
session-visszajelzés — a legacy determinisztikus coaching parity megtartásával.

## 2. Jelenlegi állapot

- A tutor determinisztikus debriefje nincs; a legacy `PracticeCoach`→`PracticeInsight`
  (ADR 0084) a parity-referencia (a R01 baseline fixture-t rögzített róla).
- R05 után van redaktált `TutorContextSnapshot`, R04 után evidence/skill-becslés —
  ezek a bemenetek.

## 3. Scope

**Benne:** `DebriefFact` (timing bias/direction/chord/consistency/stable-tempo),
`CoachingInsight` (evidence-ref-fel), `SessionDebriefBuilder` (result → fact-lista),
`DeterministicCoach` (priority policy: **egy** elsődleges insight; localization-key
alapú determinisztikus output; low-evidence → uncertainty text; previous-comparable-
session összehasonlítás; action template).

**Kívül — TILOS:** cloud/model-hívás, vizuális kéz/ujj-diagnózis, UI (R19/R20),
source-feature belső import.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/models/debrief_fact.dart` | ÚJ | mért fact-modell |
| `.../domain/models/coaching_insight.dart` | ÚJ | insight + evidence-ref |
| `.../application/debrief/session_debrief_builder.dart` | ÚJ | result→fact |
| `.../application/debrief/deterministic_coach.dart` | ÚJ | priority + localized output |
| `lib/features/ai_tutor/public.dart` | előző körökből | additív export |
| `lib/l10n/app_en.arb`, `app_hu.arb` | meglévő | insight lokalizációs kulcsok (additív) |
| `test/features/ai_tutor/application/*` | ÚJ | fact/priority/parity tesztek |
| `docs/rounds/e04-r08-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, más feature belső contractja, `docs/rag`,
más kör briefje. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. A debrief **cloud nélkül** teljes; minden insight **evidence-ref**-et hordoz —
   bizonyíték nélküli állítás TILOS (ADR 0132 grounding).
2. Egy válaszban **legfeljebb egy-két** elsődleges fókusz (SDD §17.3 priority).
3. **Nincs vizuális technikai diagnózis** audio-adatból (SDD DoD; a CV Epic dolga).
4. A legacy determinisztikus feedback **parity** megőrzött (R01 fixture ellen mérve).

## 6. Acceptance criteria

- [ ] Forgatókönyvek: late bias / wrong direction / low chord accuracy / first session /
      improvement / non-comparable session / low evidence — mind determinisztikus,
      lokalizált (hu+en) outputot ad.
- [ ] **Low evidence → uncertainty text**, NEM 0%/hamis állítás; a küszöb alatt/rajta/
      fölött mátrix.
- [ ] **No unsupported claim:** minden insighthoz evidence-ref; camera/vizuális claim
      soha. Reviewer eldobható mutációval (evidence-ref elhagyása) pirosra váltja.
- [ ] **Legacy parity:** a R01 coaching fixture-snapshot ellen a determinisztikus
      output egyezik (a dokumentált értelmezési tartományon belül).

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/application
```

Külön processzek, nincs `&&`/pipe/`tail`. ARB-változásnál `flutter gen-l10n` a gate
előtt. CI = orchestrátor exact-SHA dispatch.

## 8. Implementációs sorrend

1. RED priority + evidence-ref + parity + uncertainty tesztek.
2. Fact + insight modellek.
3. Builder + deterministic coach + ARB kulcsok.
4. `flutter gen-l10n`; gate.

Javasolt commit: `feat(ai-tutor-coach): add grounded deterministic session debrief`.

## 9. Kockázatok

- Parity-csapda: a legacy coach viselkedését pontosan a R01 fixture rögzíti — ha az
  hiányos, `stopped`, nem találgatás.
- ARB gen-l10n gitignore-csapda (HEAL E03-R14) — gen a gate előtt.

**STOP:** unsupported claim, vizuális diagnózis vagy parity-gyengítés helyett
dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r08-deterministic-debrief-coaching-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
