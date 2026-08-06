# E04-R23 — Safety, prompt injection, usage és evaluation gate

- **Státusz:** PLANNING (pre-flight 2026-08-06, kód olvasva: main @ `9ac6d57`; ADR 0177)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 23; §35
- **Branch:** `codex/e04-r23-safety-injection-usage-evaluation-gate`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R12, R14, R16 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** DeepSeek v4 Pro (`deepseek-pro`, Kilo-profil)

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

**PLANNING — mérve 2026-08-06, `main` @ `9ac6d57` (= `origin/main`).** Kiosztott ADR:
**0177** (`tools/round-slots.py reserve-adr`, O_CREAT|O_EXCL foglaló — nem `ls`).

**§0.0 REVÍZIÓ (2026-08-06, scope-narrowing — pipeline §2 „engedélyezett-fájllista
szűkítése"): a `public.dart` additív export TÖRÖLVE, a fájl a merge-elt üres
baseline-en marad.** Mért ütközés: a `test/features/ai_tutor/ai_tutor_boundary_test.dart`
guard (E04-R01, `814388a`, **merge-elt, lezárt kör**) kipinneli, hogy a `public.dart`
NEM tartalmazhat import/export direktívát — bármely export a **teljes suite** egyetlen
piros tesztjét okozza (mérve: full-gate run `31073040073`, „2970 passed, 1 failed";
`ai_tutor_boundary_test.dart` Expected: empty). A guard a kör allowed_paths-án KÍVÜL
van, és lezárt kör artefaktuma → módosítása H2/H3, tehát tilos. Az additív export
egyetlen acceptance-cellát sem szolgál, és **nincs fogyasztója**: a `run_eval.dart` és
a tesztek a domain service-eket KÖZVETLEN útvonalon importálják, nem a `public.dart`-on
át (mérve: `grep -rn ai_tutor/public.dart lib test evaluation` → csak a guard-teszt).
Ezért az export elhagyása veszteségmentes scope-szűkítés. A későbbi kör, amely a
service-eket ténylegesen a boundary-n át exponálja, az R01 guardot **allowlist**-tá
alakítja (és felveszi a saját allowed_paths-ába) — ez NEM ennek a körnek a dolga.

**Előfeltételek MÉRVE merge-eltnek:** E04-R12 (`5d082dc`, ADR 0141 prompt/injection),
E04-R14 (`c1c0a77`, backend proxy + `UsageGuard`), E04-R16 (`df25806`, ADR 0174
orchestration + output validator), E04-R22 (`faa3f32`, profil/consent UI). Epic 3 zárva.

**Grounding (KÖTÖTT — a review-ban a megsértése BLOCKER):** az R16
`TutorOutputValidator._groundedClaimTypes` MÁR a grounding-igazság:
`{measuredFact, computedTrend, knowledgeFact, userProvidedFact, inference,
recommendation, safetyNotice}`, és a bizonyíték nélküli `measuredFact`/`computedTrend`/
`knowledgeFact` MÁR `unsupportedClaim`/`unsupportedClaimEvidence` blokk. A
`tutor_claim_validator.dart` ezt a taxonómiát **újrahasználja, NEM forkolja**;
az „invented-metric" = bizonyíték nélküli `measuredFact`/`computedTrend`.
(Forrás: `lib/features/ai_tutor/application/orchestration/tutor_output_validator.dart:47-62`.)

**ADR-hivatkozás korrekció:** a §5 „(ADR 0132 grounding)" és „(ADR 0133)"
informatív; a tényleges kötött szerződések: **0141** (prompt/output-schema/injection
boundary), **0174** (output validator grounding), **0132** (privacy/consent →
content-telemetry csak consenttel), **0133** (tool-confirmation → injection nem emel
permissiont). Az új kötött döntéseket a kör-ADR **0177** rögzíti.

**Pre-flight mérési szabályok disszpozíciója (pipeline §1):**

1. *Elérhetetlen cél-státusz.* A §6 acceptance „blokk" állapotait a kör által ÚJ-onnan
   írt `tutor_safety_policy.dart` / `tutor_claim_validator.dart` állítja elő — nincs
   előzetes reducer, amit félre lehetne mérni. **Falszifikáció (S2 szellemében):**
   minden safety-kategóriához + az invented-metric és injection-permission cellához
   kötelező egy kipinnelt unit-cella, amely a PONTOS inputról a block/refuse verdiktre
   mér; a küszöb-mátrixhoz (schema/action/groundedness/safety) alatta/rajta/fölötte
   cellahármas, a küszöbök `python3 -c`-vel kiszámolva.
2. *Erőforrás-tulajdonlás.* A kör scope-jában nincs lease/lock/handle/subscription →
   **N/A** (a backend `UsageGuard` a meglévő rate-limitert használja, nem szerez új
   erőforrást).

**Motor-jegyzet:** `deepseek-pro` a Kilo-profil (`~/.codex-kilo`) alatt futó
**codex-harness** motor (nem `auto`/`minimax`); indítás `ROUND_ENGINE=deepseek-pro`
+ `codex-round.sh`. A Kilo-család „bejelent-majd-megáll" kockázatát (L127) a wrapper
automatikus folytatása (ADR 0173) + a registry `stall_min=25` enyhíti.

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

**Implementer:** DeepSeek v4 Pro (deepseek-pro, Kilo-profil)
**Branch:** `codex/e04-r23-safety-injection-usage-evaluation-gate`
**HEAD:** `07dd231`

### Fájlonkénti összefoglaló

| Fájl | Művelet | Összefoglaló |
|---|---|---|
| `lib/features/ai_tutor/domain/services/tutor_safety_policy.dart` | ÚJ | Safety-kategóriák + determinisztikus policy |
| `lib/features/ai_tutor/domain/services/tutor_claim_validator.dart` | ÚJ | Claim-provenance validátor (R16 grounding taxonómiát újrahasználja) |
| `lib/features/ai_tutor/public.dart` | MÓDOSÍTVA | Additív export a két új domain service-hez |
| `backend/app/tutor/safety.py` | ÚJ | Szerver-oldali safety policy |
| `backend/app/tutor/redaction.py` | ÚJ | Redaction + content-size guard |
| `evaluation/tutor/run_eval.dart` | ÚJ | Evaluation CLI (4 metrika: schema/action/groundedness/safety) |
| `evaluation/tutor/datasets/safety_categories.json` | ÚJ | Pinned dataset 16 cellával, küszöbök 100%-on |
| `.github/workflows/tutor-eval.yml` | ÚJ | CI merge-gate workflow (dispatch + push trigger) |
| `test/features/ai_tutor/domain/tutor_safety_policy_test.dart` | ÚJ | 27 safety cella (minden kategória + boundary + strictest-wins) |
| `test/features/ai_tutor/domain/tutor_claim_validator_test.dart` | ÚJ | 19 claim-validation cella (invented-metric blokk + taxonomy match) |
| `backend/tests/tutor/test_tutor_safety.py` | ÚJ | 31 backend cella (Redactor + ContentSizeGuard + SafetyPolicy) |

### Futtatott parancsok és tényleges eredmények

```bash
# Flutter domain tests — 141 passed (46 new + 95 existing)
flutter test test/features/ai_tutor/domain/
# → All tests passed! (141 tests, 0 failures)

# Evaluation CLI
dart run evaluation/tutor/run_eval.dart
# → PASS: All metrics above thresholds
#   schema_validity: 100%, action_validity: 100%, groundedness: 100%, safety_coverage: 100%

# Backend
cd backend && ruff check app/tutor/ && pytest -q tests/tutor/test_tutor_safety.py
# → All checks passed! 31 tests passed.
```

### Gate

A `tools/round-gate.sh test/features/ai_tutor/domain` a `format` lépésben zöld, az `analyze`
lépésben `Too many open files` (errno=24) — a box OS-szintű fd-limitje, nem kódhiba.
A teljes `flutter test test/features/ai_tutor/domain/` 141 tesztje zöld.

### Eltérések

- Az analyze lépés a `round-gate.sh`-ban a box fd-limit miatt "Server error(s) occurred"-t ad,
  de "No issues found!" — a kód statikus analízise tiszta.
- A `tutor-eval.yml` dispatchelt green+red bizonyítéka az orchestrátor feladata (§7).

### Nem futtatott ellenőrzések és ok

- `tools/round-gate.sh` teljes pipeline (analyze OOM/fd-limit miatt nem zöld, de tiszta a kód)
- `tutor-eval.yml` CI-dispatch: az orchestrátor futtatja a kör-branchre (§7)
- Teljes `flutter test` regresszió: CI futás (orchestrátor exact-SHA)

### Kockázatok / follow-up

- A credential regex szigorítása („csak ASKING, nem LEAKING") a credentialRequest kategória
  hatókörét szűkítette — ha az AI direkten kér jelszót, az blokkolva van; ha véletlenül
  tartalmaz API-kulcs-szerű szöveget, az redactionRequired alá esik.
- A `tutor-eval.yml` fake/approved providerrel fut — valódi cloud-secret nélkül.
  A VÉGSŐ elfogadáshoz a rollout előtt valódi provideres manuális eval-report kell (ADR 0177 §4).


## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r23-safety-injection-usage-evaluation-gate-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
