# E04-R08 — Deterministic debrief és coaching fallback

- **Státusz:** PLANNING (pre-flight mérve 2026-08-05, main @ `20da3e2`; lásd §0.0)
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

**Pre-flight mérve 2026-08-05, `main` @ `20da3e2` (E04-R07 merge után). Nincs előre kiosztott ADR.**

**D1 — Nincs ÚJ ADR.** A legmagasabb ADR-szám `0136` (mérve: `ls docs/adr/`).
E kör **realizáció**, nem új normatív döntés: az ADR 0132 (grounding: minden
insight evidence-ref-et hordoz) + ADR 0084 (a legacy `PracticeCoach`/
`PracticeInsight` parity-referencia) + SDD §14 (Deterministic coach és debrief)
+ SDD §21 (Claim grounding) realizálása. A R03/R04/R05 precedens szerint
realizációs körre nem osztunk új ADR-számot (szám-infláció elkerülése).

**D2 — REVÍZIÓ: engedélyezett-lista szűkítés, `public.dart` eltávolítva.** A
`test/features/ai_tutor/ai_tutor_boundary_test.dart` **nulla import/export
invariánst** őriz (`public.dart` jelenlegi tartalma csak `library;` + doc-comment,
mérve). Bármely export onnan pirosra váltaná a lezárt E04-R01 boundary-tesztet;
egyetlen acceptance sem igényel külső elérhetőséget (a §6 kritériumok mind
determinisztikus kimenetre / groundingre / parityre vonatkoznak). A debrief
**belső marad** (`domain/models/` + `application/debrief/`); a hívó/export a
R12/R16 prompt-kör dolga (R02–R07 precedens).

**D3 — §1.1(1) Elérhetetlen cél-státusz (mért input→státusz).** Az acceptance
forgatókönyvei (late bias / wrong direction / low chord / first session /
improvement / non-comparable / low evidence) mind előállíthatók: a legacy
`PracticeCoach` (`lib/features/practice/domain/service/practice_coach.dart`) a
mért prioritás-mátrix (noSignal → lowCompletion → biasLate/Early → directionError
→ chordError → chordPairProblem → tempoTooHigh → positiveReinforcement →
nextDifficulty; küszöbök: completion<0.5, dir<0.6, chord<0.6, rhythm<0.7 &
bpm≥120, reinforcement≥0.85, bias ≥8 paired & ≥70% share). A parity-fixture
`practice_coach_bias_late_v1` **létezik és teljes**
(`docs/baseline/epic-04-ai-tutor-start.md` §Rögzített deterministic coaching
fixture-snapshot: input → `code: practice.insight.bias_late`). Nincs parity-STOP.

**D4 — §1.2 Erőforrás-tulajdonlás: N/A.** A kör tiszta domain/application; nincs
lease/lock/handle/subscription. `grep -rn "\.acquire(" lib/features/ai_tutor` —
nincs találat az érintett rétegen; a mic-lease változatlanul a `MicCapture`-nél.

**D5 — Modellek/kontraktusok (SDD §14.2/§14.3/§21 mérve).** `DebriefFact`:
`code, value, provenance, confidence, priority` (SDD §14.2). `CoachingInsight`:
stabil code, title loc-key, explanation loc-key, **evidence refs**, priority,
suggested action template, uncertainty, conflicting-evidence flag (SDD §14.3).
Grounding: minden mért állítás ≥1 session evidence-ref, computedTrend ≥2
összehasonlítható evidence group (SDD §21.3). Bemenetek adottak: R04
`SkillEvidence`/`SkillEstimate`, R05 `TutorContextSnapshot` (mérve, léteznek).

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
| ~~`lib/features/ai_tutor/public.dart`~~ | **§0.0 REVÍZIÓ — eltávolítva** | boundary-invariáns: bármely export RED-re vált; e körnek nincs hívója (R12/R16 fogyasztja) |
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

### Megvalósítás

- `DebriefFact` és `CoachingInsight` immutable, evidence-refet validáló belső
  modellek; a computed trend legalább két összehasonlítható evidence groupot
  követel.
- `SessionDebriefBuilder` csak redaktált primitív session inputból készít stabil
  prioritású fact-listát. Lefedi a late bias, wrong direction, low chord,
  section consistency, stable tempo, first evidence, improvement és
  non-comparable eseteket; Practice feature import nincs.
- `DeterministicCoach` egyetlen elsődleges insightot választ prioritás + stabil
  code tie-break alapján, és kizárólag localization keyt, action template-et és
  evidence refeket ad tovább. A legacy late-bias fixture `practice.insight.bias_late`
  kódját megtartja.
- Az angol és magyar ARB-katalógus additív debrief/uncertainty/action kulcsokat
  kapott. Vizuális vagy kamerás diagnózis nincs.

### Tesztek és ellenőrzések

- RED: az új forrás-contract hiányát jelző tesztek pirosak voltak; a viselkedési
  RED után a builder/coach `UnimplementedError`-ral vártan pirosra vált.
- `flutter test test/features/ai_tutor/application/session_debrief_builder_test.dart test/features/ai_tutor/application/deterministic_coach_test.dart`
  — 15 teszt zöld. Lefedi a parity fixture-t, a 7/8/9 paired-evidence mátrixot,
  first/improvement/non-comparable eseteket, hu+en ARB-lookupot, grounding
  mutációt, stabil rendezést és a tiltott vizuális claim-szavakat.
- `flutter gen-l10n` — sikeres, generált output gitignore-olt.
- `tools/round-gate.sh test/features/ai_tutor/application` — zöld: format
  változás nélkül, analyze `No issues found`, application suite `+35` teszt.
  A kimenet tokenkorlátja után külön ismételt `dart run tool/check_architecture.dart`:
  `Architecture dependencies OK (12 allowlisted deviation(s)).`

### Nem futtatott ellenőrzések

- Teljes Flutter suite, randomizált property gate és release APK CI nem futott:
  ezek az orchestrátor exact-SHA CI-feladatai.

### Eltérés vagy nyitott kockázat

- Nincs scope-eltérés; új ADR, public export, cloud hívás és source-feature
  belső import nem került a diffbe.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r08-deterministic-debrief-coaching-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
