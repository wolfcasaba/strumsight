# E04-R23 — Safety, prompt injection, usage és evaluation gate

- **Státusz:** PREPARED (előre megírva 2026-08-04, kód olvasva: main @ `fbe1e82`)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 23; §35
- **Branch:** `codex/e04-r23-safety-injection-usage-evaluation-gate`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R12, R14, R16 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/domain/services/tutor_safety_policy.dart",
  "lib/features/ai_tutor/domain/services/tutor_claim_validator.dart",
  "backend/app/tutor/safety.py",
  "backend/app/tutor/redaction.py",
  "evaluation/tutor/run_eval.dart",
  "evaluation/tutor/datasets/",
  ".github/workflows/tutor-eval.yml",
  "lib/features/ai_tutor/public.dart",
  "test/features/ai_tutor/domain/tutor_safety_policy_test.dart",
  "test/features/ai_tutor/domain/tutor_claim_validator_test.dart",
  "backend/tests/tutor/test_tutor_safety.py",
  "docs/rounds/e04-r23-safety-injection-usage-evaluation-gate.md",
]
gate_tests = [
  "test/features/ai_tutor/domain",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E04-R12/R14/R16 merge; olvasd újra
> `AGENTS.md`, Chapter 1/5 (**§20 safety/eval**), `backend/README.md`, `HANDOFF.md`.
> Nincs előre kiosztott ADR (R01 **0132**/**0133** bővítése); ha a pre-flight ÚJ
> kötött safety/eval-döntést mér, az orchestrátor a next-free számot osztja akkor.
> **Workflow-kör:** a `.github/workflows/tutor-eval.yml` elfogadása CSAK a kör-branchre
> dispatchelt **zöld** futás az új gate-tel **+ egy bizonyított piros** út (a brief-prep
> workflow-óvintézkedése). PREPARED→PLANNING, brief commit az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED — a mért §0.0-t az élesedő pre-flight tölti ki.** Nincs előre kiosztott ADR.

## 1. Cél

A tutor production-rolloutja ELŐTT kötelező **biztonsági, minőségi és költségkapuk**
— prompt-injection, hallucinált metric, safety-kategóriák, evaluation merge-gate.

## 2. Jelenlegi állapot

- Nincs safety/claim-validator/eval-gate. R12 prompt/injection-fixture + R14 backend
  + R16 output-validator kész — ezek fölé épül a formális kapu.
- A `.github/workflows/` a meglévő CI-készlet; `tutor-eval.yml` új required workflow.

## 3. Scope

**Benne:** safety-kategória + response-policy, claim-validator (measured/trend/
knowledge/inference), prompt-injection + unsupported-capability adversarial dataset,
backend redaction + content-size guard, evaluation CLI + CI workflow (fake/approved
provider), merge-gate schema/action/groundedness/safety metrikára, usage/model-alias audit,
prompt/model-update → kötelező eval-report, content-telemetry csak consenttel.

**Kívül — TILOS:** valódi cloud-provider a CI-ben (fake/approved), UI, source-belső import.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/services/tutor_safety_policy.dart` | ÚJ | safety-kategória + policy |
| `.../domain/services/tutor_claim_validator.dart` | ÚJ | claim-provenance validáció |
| `backend/app/tutor/safety.py` | ÚJ | backend safety |
| `backend/app/tutor/redaction.py` | ÚJ | redaction + size-guard |
| `evaluation/tutor/run_eval.dart` | ÚJ | evaluation CLI |
| `evaluation/tutor/datasets/` | ÚJ | adversarial + capability dataset |
| `.github/workflows/tutor-eval.yml` | ÚJ | eval merge-gate workflow |
| `lib/features/ai_tutor/public.dart` | előző körökből | additív export |
| `test/features/ai_tutor/domain/*`, `backend/tests/tutor/test_tutor_safety.py` | ÚJ | safety/claim tesztek |
| `docs/rounds/e04-r23-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más workflow/fájl, más feature belső contractja, `docs/rag`,
más kör briefje. A `.github/workflows/tutor-eval.yml` csak dispatchelt zöld+piros
bizonyítékkal fogadható. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Prompt-injection nem emel tool-permissiont** (ADR 0133); **hallucinált metric
   blokkolt** (ADR 0132 grounding). **NEM elfogadható:** „figyelmeztetéssel átengedett"
   invented metric.
2. **Production rollout eval-report nélkül tiltott**; prompt/model-update → kötelező report.
3. A CI **fake/approved** providerrel fut (nincs valódi cloud-secret a workflow-ban).
4. Content-telemetry **csak consenttel** (R03/R22).

## 6. Acceptance criteria

- [ ] pain-response; medical-refusal; copyright; credential-request; **prompt-injection**;
      **invented-metric** blokk; camera-claim tiltás; unsafe-action; usage-limit; redaction;
      **evaluation-threshold** (schema/action/groundedness/safety — alatta/rajta/fölötte mátrix,
      géppel számított cellák).
- [ ] A merge-gate a küszöb alatt **piros** — bizonyított piros út a workflow- n; reviewer
      eldobható mutációval (küszöb-lazítás) pirosra váltja.
- [ ] Prompt-injection az adversarial dataseten NEM emel permissiont.

## 7. Kötelező ellenőrzések

Flutter domain:

```bash
tools/round-gate.sh test/features/ai_tutor/domain
```

Backend (külön, `backend/README.md`):

```bash
cd backend && ruff check . && pytest -q backend/tests/tutor/test_tutor_safety.py
```

A `tutor-eval.yml` elfogadása: kör-branchre dispatchelt **zöld** futás + **egy
bizonyított piros** (küszöb alatti) út. Full CI = orchestrátor exact-SHA.

## 8. Implementációs sorrend

1. RED safety/claim/injection/threshold tesztek (Flutter + backend).
2. safety-policy + claim-validator + backend safety/redaction.
3. evaluation CLI + dataset + workflow.
4. Gate-ek + dispatchelt zöld/piros workflow-bizonyíték (orchestrátor).

## 9. Kockázatok

- Workflow-kör kockázat (brief-prep óvintézkedés) — csak dispatchelt zöld+piros bizonyíték.
- Invented-metric átengedés „figyelmeztetéssel" — TILOS, hard blokk.

**STOP:** invented-metric átengedés, injection-permission-emelés vagy küszöb-lazítás
helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r23-safety-injection-usage-evaluation-gate-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
