# ADR 0177 — AI Tutor safety, claim-provenance és evaluation merge-gate

- **Státusz:** Elfogadva (E04-R23 pre-flight, 2026-08-06)
- **Kör:** E04-R23 — Safety, prompt injection, usage és evaluation gate
- **Implementer motor:** DeepSeek v4 Pro (`deepseek/deepseek-v4-pro`, Kilo-profil,
  `codex-round.sh`, engine-registry `deepseek-pro`)
- **Epic:** [Chapter 5 — Epic 4: AI Guitar Teacher](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 23; §35
- **Szülő/kontext-ADR-ek:** [0131](0131-ai-tutor-provider-boundary.md) (provider boundary),
  [0132](0132-ai-tutor-privacy-and-consent.md) (privacy/consent),
  [0133](0133-ai-tutor-tool-confirmation.md) (tool-confirmation),
  [0141](0141-ai-tutor-prompt-output-schema-injection-boundary.md) (prompt/output-schema/injection boundary),
  [0174](0174-ai-tutor-orchestration-state-machine.md) (orchestration state machine + output validator)

## Kontextus

Az AI Tutor turn-pipeline építőelemei megvannak (R05 kontextus, R07 tudás,
R10 tool-allowlist, R11 action-confirm, R12 prompt/output-schema + injection
boundary, R14 backend proxy + usage guard, R16 orchestration + output validator),
de a **production-rollout előtti formális biztonsági, minőségi és költségkapuk**
hiányoznak: nincs safety-kategória szerinti response-policy, nincs claim-provenance
validátor a domain-rétegben, nincs adversarial prompt-injection/capability dataset,
nincs backend redaction/size-guard, és nincs olyan evaluation merge-gate, amely a
küszöb alatt **pirosra** vált és blokkolja a merge-et.

**Mért baseline (2026-08-06, `main` @ `9ac6d57`):**

- Az R16 `TutorOutputValidator` (`lib/features/ai_tutor/application/orchestration/tutor_output_validator.dart`)
  MÁR definiálja a grounding-taxonómiát: `_groundedClaimTypes = {measuredFact,
  computedTrend, knowledgeFact, userProvidedFact, inference, recommendation,
  safetyNotice}`, és MÁR blokkolja (`TutorOutputValidationIssue.unsupportedClaim`
  / `unsupportedClaimEvidence`) azt a `measuredFact`/`computedTrend`/`knowledgeFact`
  claimet, amelynek nincs trusted `evidenceRefs`-e. **A „hallucinált metric" tehát
  nem új fogalom** — a `measuredFact`/`computedTrend` bizonyíték nélkül = invented
  metric, amit R16 már elutasít.
- A backend usage/quota kapu MÁR létezik: `backend/app/tutor/usage.py`
  (`UsageGuard`, `RateLimitExceeded`, `UsageLimitExceeded`, hiba **nem nyelt el** —
  429-re propagál).
- A `evaluation/` top-level könyvtár még NEM létezik (új, allowed_paths-on belül).

## Döntés

1. **Claim-provenance a domain-rétegben (`tutor_claim_validator.dart`):** a validátor
   az R16 grounding-taxonómiát **újrahasználja**, NEM forkolja. `measuredFact` és
   `computedTrend` claim csak trusted forrás-referenciával (`TutorSourceRef.chunkId`)
   fogadható el; referencia nélkül **hard blokk** — „figyelmeztetéssel átengedett"
   invented metric TILOS. A domain-validátor a policy-eldöntés tiszta, immutable
   magja; az application-réteg (R16) fölötte marad.

2. **Safety-kategória + response-policy (`tutor_safety_policy.dart`):** determinisztikus,
   tiszta leképezés inputról safety-verdiktre. Kötelező kategóriák hard-block/refuse
   verdikttel: pain-response, medical-refusal, copyright, credential-request,
   prompt-injection, invented-metric, camera-claim (unsupported capability),
   unsafe-action, usage-limit, redaction-required. **Prompt-injection SOHA nem emel
   tool-permissiont** (0141/0133 határ); a policy a legszigorúbb egyező verdiktet adja.

3. **Backend safety + redaction (`safety.py`, `redaction.py`):** szerver-oldali
   redaction + content-size guard; a tartalom-telemetria **csak explicit consenttel**
   (0132) kerül továbbításra/naplózásra.

4. **Evaluation merge-gate (`evaluation/tutor/run_eval.dart` + `tutor-eval.yml`):**
   a CI **fake/approved** providerrel fut — **valódi cloud-secret a workflow-ban TILOS**.
   A gate négy metrikát mér küszöbbel: schema-validity, action-validity, groundedness,
   safety-coverage. Bármelyik metrika a küszöb ALATT → a workflow **piros** → merge
   blokkolt. A gate elfogadása CSAK a kör-branchre dispatchelt **zöld** futás ÉS egy
   **bizonyított piros** (küszöb-lazító mutációval kiváltott) út együtt.

5. **Rollout-előfeltétel:** production rollout eval-report nélkül tiltott; prompt-
   vagy model-update → **kötelező** friss eval-report.

## Következmények

- A tutor production-rollout kapuja mostantól gépi és megkerülhetetlen: küszöb
  alatti minőség/safety → piros CI → nincs merge.
- A claim-validátor és az R16 output-validátor **egyetlen** grounding-igazságot
  használ; a divergens taxonómia bevezetése a review-ban BLOCKER.
- A `tutor-eval.yml` új **required** workflow; a merge-kapu exact-SHA (ADR 0086 §2).
- A CI-ben nincs valódi provider-hívás → a gate determinisztikus és olcsó, de a
  VÉGSŐ elfogadás továbbra is a valódi-provider manuális eval-report a rollout előtt.
