# Epic 4 (AI Guitar Teacher) — batch előkészítési index

- **Státusz:** PREPARED (batch előre megírva **2026-08-04**, kód olvasva: `main` @ `fbe1e82`)
- **SDD-forrás:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) (Chapter 5, Kör 1–24)
- **Előfeltétel-epic:** Epic 3 (Song Trainer) lezárva — **E03-R22 merge**. A batch
  minden briefje csak ezután élesíthető. Ma (`fbe1e82`) E03-R21 **fut** (a
  pipeline-zár foglalt), E03-R22 **pending**.
- **User-döntés (2026-08-04):** „készítsd elő az Epic 4 fejlesztési köröket, hogy
  aztán az auto-pipeline-ba mehessenek együtt; **nem kell az utolsó körre human
  review**." → a záró **E04-R24** kör NEM kap ADR 0087 §7 szerinti kézi
  epic-záró indítást; a briefje úgy készül, hogy a pre-flight NE tartalmazzon
  eldöntetlen emberi kérdést (lásd §Záró-kör alább).
- **HOLD-döntés (user, 2026-08-04):** az Epic 4 CSAK az Epic 3 teljes befejezése +
  explicit user-go után indul. Ezért a 24 queue-sor `hold` státuszú (NEM `pending`):
  a driver átugorja, így a lánc E03-R22 után **megáll az epic-határon**. Go-kor a
  `hold`→`pending` flip indítja folyamatosan az Epic 4-et (commit `c19b6aa` óta
  élesítve, majd `hold`-ra állítva).

> ⚠ **Ez az index nem futtatható artefaktum.** A körök egyenkénti briefjei az
> `e04-rNN-*.md` fájlok. Minden brief `PREPARED`; az élesedéskor a kötelező
> ⚠ pre-flight méri újra a driftet (merge-elt E03-R21/R22 + a batch korábbi
> körei), és állítja `PLANNING`-re a kör-branchen.

---

## 1. Aktiválási protokoll (élő pipeline miatt kötelező)

`fbe1e82`-kor egy kör **fut** és a pipeline commitol a `main`-re. Ezért ez a
batch **csak új fájlokat** hoz létre (`docs/rounds/e04-*.md`, ez az index) — a
pipeline által birtokolt fájlokat (**`docs/execution/pipeline-queue.tsv`**,
**`HANDOFF.md`**) és a `main` commitot a preparation **nem** érinti, hogy ne
ütközzön a futó driverrel (memória: `concurrent-autonomous-round-driver`).

**Aktiválás (a briefek megírása után, koordinált pillanatban):**

1. Ellenőrizd, hogy a pipeline-zár szabad-e vagy biztonságos ponton van
   (`tools/pipeline-status.sh`), és `git fetch` + `main` gyorstekercs.
2. Fűzd a §5 queue-sorokat a `pipeline-queue.tsv` végére (E03-R22 **után**).
3. `aiTutorEnabled` / `aiTutorCloudEnabled` flag default **OFF** — a rollout az
   E04-R24 runbookjáé, a GA-flip pipeline-on kívüli, külön user/termék döntés.
4. Commit a `main`-re EGY commitban (index + 24 brief + queue-sorok), ha a zár
   szabad; különben várd meg a kör lezárását.

---

## 2. Kör-térkép (24 kör)

| Kör | Cím | Motor | Előre kiosztott ADR | Előfeltétel (Epic 4-en belül) | Brief |
|---|---|---|---|---|---|
| E04-R01 | AI Tutor baseline, ADR-ek, feature flagek | codex | 0131, 0132, 0133, 0134 | — (Epic 3 zárva) | `e04-r01-ai-tutor-baseline-and-boundaries.md` |
| E04-R02 | Conversation és message domain | codex | — | R01 | `e04-r02-conversation-and-message-domain.md` |
| E04-R03 | Student/guitar profile, goals, consent | codex | — | R01 | `e04-r03-student-guitar-profile-goals-consent.md` |
| E04-R04 | Skill taxonomy, evidence, reducer | codex | — | R01 | `e04-r04-skill-taxonomy-evidence-reducer.md` |
| E04-R05 | Context adapterek + TutorContextSnapshot | codex | — | R02, R03, R04 | `e04-r05-context-adapters-and-snapshot.md` |
| E04-R06 | Kurált knowledge schema + első content pack | codex | 0135 | R01 | `e04-r06-knowledge-schema-and-content-pack.md` |
| E04-R07 | Offline knowledge index és retrieval | codex | — | R06 | `e04-r07-offline-knowledge-index-retrieval.md` |
| E04-R08 | Deterministic debrief és coaching fallback | codex | — | R04, R05 | `e04-r08-deterministic-debrief-coaching.md` |
| E04-R09 | PracticePlanDraft, validator, compiler | codex | — | R03, R04 | `e04-r09-practice-plan-draft-validator-compiler.md` |
| E04-R10 | Tutor Tool contract + read-only registry | codex | — | R02, R05 | `e04-r10-tool-contract-and-registry.md` |
| E04-R11 | Action proposal, validáció, confirmation | codex | — | R10 | `e04-r11-action-proposal-and-confirmation.md` |
| E04-R12 | Prompt templatek, output schema, injection boundary | codex | — | R05, R07, R10 | `e04-r12-prompts-output-schema-injection-boundary.md` |
| E04-R13 | TutorModelGateway és scripted fake | codex | — | R02, R12 | `e04-r13-model-gateway-and-fake.md` |
| E04-R14 | Backend tutor proxy, provider registry, usage guard | codex | — | R13 | `e04-r14-backend-tutor-proxy-usage-guard.md` |
| E04-R15 | Backend + Flutter streaming transport | codex | 0136 | R13, R14 | `e04-r15-streaming-transport.md` |
| E04-R16 | Orchestration state machine + output validator | codex | — | R05, R07, R10, R11, R12, R13 | `e04-r16-orchestration-state-machine.md` |
| E04-R17 | Conversation repository, summary, inspectable memory | codex | — | R02 | `e04-r17-conversation-repository-and-memory.md` |
| E04-R18 | Tutor Home, Chat UI, streaming UX | minimax | — | R13, R16, R17 | `e04-r18-tutor-home-chat-ui.md` |
| E04-R19 | Evidence, source, action card UI | minimax | — | R09, R11, R18 | `e04-r19-evidence-source-action-card-ui.md` |
| E04-R20 | Practice és Analyze post-session integráció | codex | — | R08, R16, R18 | `e04-r20-practice-analyze-integration.md` |
| E04-R21 | Song Trainer debrief és range action | codex | — | R10, R20 | `e04-r21-song-trainer-debrief-range-actions.md` |
| E04-R22 | Profile, privacy, data, consent UI | codex | — | R03, R17 | `e04-r22-profile-privacy-data-consent-ui.md` |
| E04-R23 | Safety, prompt injection, usage, evaluation gate | codex | — | R12, R14, R16 | `e04-r23-safety-injection-usage-evaluation-gate.md` |
| E04-R24 | Offline fallback, teljes regresszió, rollout (ZÁRÓ) | codex | — | MIND (R01–R23) | `e04-r24-offline-fallback-regression-rollout.md` |

---

## 3. ADR-kiosztás (PROVIZÓRIKUS — pre-flightban reconcile KÖTELEZŐ)

A `main`-en a legmagasabb ADR ma **0128**. A **0129** és **0130** az élesedéskor
**E03-R21** és **E03-R22** számára fenntartva (a batch NEM használja). Epic 4
ezért **0131**-től oszt:

| ADR | Kör | Tárgy | Fájl (Claude/orchestrátor írja a kör pre-flightjában, NEM implementer-diff) |
|---|---|---|---|
| 0131 | R01 | AI tutor provider boundary | `docs/adr/0131-ai-tutor-provider-boundary.md` |
| 0132 | R01 | AI tutor privacy és consent | `docs/adr/0132-ai-tutor-privacy-and-consent.md` |
| 0133 | R01 | AI tutor tool confirmation | `docs/adr/0133-ai-tutor-tool-confirmation.md` |
| 0134 | R01 | AI tutor memory policy | `docs/adr/0134-ai-tutor-memory-policy.md` |
| 0135 | R06 | Tutor knowledge governance | `docs/adr/0135-tutor-knowledge-governance.md` |
| 0136 | R15 | AI tutor streaming protocol (SSE/választott) | `docs/adr/0136-ai-tutor-streaming-protocol.md` |

**Reconciliation-szabály (minden brief ⚠ pre-flightjában):** indítás előtt
`ls docs/adr/ | sort | tail` a valós next-free számhoz; ha E03-R21/R22 vagy a
batch korábbi köre másképp fogyasztott, **told el az egész blokkot** és javítsd
a brief §5-ét. A többi kör architekturális döntése a R01 négy alapozó ADR-jét
bővíti a saját §5-ében; ha a pre-flight ÚJ, kötött döntést mér, az orchestrátor
a következő szabad számot osztja ki akkor.

---

## 4. Motor-besorolás (ADR 0069 mért szabály)

A `pipeline-queue.tsv` mért szabálya: `risk=normal` → minimax; `risk=high` ÉS
UI/ARB > domain+app+data → minimax; egyébként → codex (ítélet-/invariáns-kritikus).
Epic 4 túlnyomó része domain/application/data/backend, security- vagy
invariáns-kritikus (grounding, tool-allowlist, action-confirmation, redaction,
prompt-injection, streaming edge-case-ek) → **codex**. Kizárólag a két
UI-dominált kör — **R18** (Home/Chat) és **R19** (evidence/action card) — megy
**minimax**-ra. (Operatív megjegyzés: a 2026-08-04 motorváltás minden nyitott
E03 kört Terrára tett; ha ez a posture Epic 4-nél is él, a `codex` sorok
változatlanul Terrán futnak — a queue engine-oszlopa mérvadó indításkor.)

---

## 5. Queue-sorok (a `pipeline-queue.tsv` VÉGÉN, E03-R22 után)

> **Élesítve `hold` státusszal** (a driver az `\tpending$` sorokat választja, a
> `hold`-ot átugorja). Go-kor: `sed -i -E 's/^(E04-R[0-9]+\t.*\t)hold$/\1pending/'`.
> Alább a rows referenciaként `pending`-gyel — a valós fájlban `hold`.

```tsv
# Epic 4 (AI Guitar Teacher) — batch előkészítve 2026-08-04 (docs/rounds/epic-04-batch-index.md).
# Előfeltétel: E03-R22 (Epic 3 zárás) merge. Motor: ADR 0069 mért szabály (R18/R19 minimax, többi codex).
# ZÁRÓ-KÖR WAIVER (user-döntés 2026-08-04): az E04-R24 NEM kap ADR 0087 §7 kézi
# epic-záró indítást — a briefje pre-decidálja a rollout/flag/ADR kérdéseket, így
# a pre-flightnak nincs eldöntetlen emberi kérdése; auto fut, az automata Claude
# független review (ADR 0055) és az exact-SHA CI változatlanul kötelező.
E04-R01	docs/rounds/e04-r01-ai-tutor-baseline-and-boundaries.md	codex	nincs	pending
E04-R02	docs/rounds/e04-r02-conversation-and-message-domain.md	codex	nincs	pending
E04-R03	docs/rounds/e04-r03-student-guitar-profile-goals-consent.md	codex	nincs	pending
E04-R04	docs/rounds/e04-r04-skill-taxonomy-evidence-reducer.md	codex	nincs	pending
E04-R05	docs/rounds/e04-r05-context-adapters-and-snapshot.md	codex	nincs	pending
E04-R06	docs/rounds/e04-r06-knowledge-schema-and-content-pack.md	codex	nincs	pending
E04-R07	docs/rounds/e04-r07-offline-knowledge-index-retrieval.md	codex	nincs	pending
E04-R08	docs/rounds/e04-r08-deterministic-debrief-coaching.md	codex	nincs	pending
E04-R09	docs/rounds/e04-r09-practice-plan-draft-validator-compiler.md	codex	nincs	pending
E04-R10	docs/rounds/e04-r10-tool-contract-and-registry.md	codex	nincs	pending
E04-R11	docs/rounds/e04-r11-action-proposal-and-confirmation.md	codex	nincs	pending
E04-R12	docs/rounds/e04-r12-prompts-output-schema-injection-boundary.md	codex	nincs	pending
E04-R13	docs/rounds/e04-r13-model-gateway-and-fake.md	codex	nincs	pending
E04-R14	docs/rounds/e04-r14-backend-tutor-proxy-usage-guard.md	codex	nincs	pending
E04-R15	docs/rounds/e04-r15-streaming-transport.md	codex	nincs	pending
E04-R16	docs/rounds/e04-r16-orchestration-state-machine.md	codex	nincs	pending
E04-R17	docs/rounds/e04-r17-conversation-repository-and-memory.md	codex	nincs	pending
E04-R18	docs/rounds/e04-r18-tutor-home-chat-ui.md	minimax	nincs	pending
E04-R19	docs/rounds/e04-r19-evidence-source-action-card-ui.md	minimax	nincs	pending
E04-R20	docs/rounds/e04-r20-practice-analyze-integration.md	codex	nincs	pending
E04-R21	docs/rounds/e04-r21-song-trainer-debrief-range-actions.md	codex	nincs	pending
E04-R22	docs/rounds/e04-r22-profile-privacy-data-consent-ui.md	codex	nincs	pending
E04-R23	docs/rounds/e04-r23-safety-injection-usage-evaluation-gate.md	codex	nincs	pending
E04-R24	docs/rounds/e04-r24-offline-fallback-regression-rollout.md	codex	nincs	pending
```

---

## 6. Záró-kör (E04-R24) — human-review waiver kivitelezése

A user waivere úgy tartható, hogy a záró kör pre-flightja NE kérjen emberi
döntést. Ezért az **E04-R24 briefje előre eldönti**:

- **Rollout-létra:** internal → Lab → opt-in beta → limited production → GA;
  minden flag default **OFF**; a **GA-flip pipeline-on kívüli**, külön user/termék
  döntés (a runbook rögzíti) → a pre-flightban nincs nyitott kérdés.
- **Flag-politika:** `aiTutorEnabled` + `aiTutorCloudEnabled` marad OFF a merge-kor;
  a kör csak a rollout/rollback runbookot és a completion reportot zárja.
- **Nincs új architekturális ADR** a záró körben (regressziós/rollout kör).
- **Ami VÁLTOZATLAN a waiver mellett is:** az automata Claude független review
  (ADR 0055), az exact-SHA zöld CI (full suite + property + APK), és a HORIZON
  valós-eszközös elfogadás — ez utóbbi a merge UTÁNI termék-elfogadás, nem
  pipeline-kapu. A „human review" waiver kizárólag az ADR 0087 §7 **kézi
  epic-záró indítást** ejti.

---

## 7. Globális pre-flight emlékeztetők (minden Epic 4 brief örökli)

- **Greenfield feature:** ma nincs `lib/features/ai_tutor/` — a legtöbb kör
  „Jelenlegi állapot"-ja = a feature/típus HIÁNYA + a fogyasztott public API-k
  (`lib/features/<f>/public.dart`: analyze, practice, progress, song_trainer,
  songs, streak, settings, learn, library, live).
- **Flag helye:** `lib/app/config/feature_flags.dart` (`accountEnabled`,
  `diagnosticsEnabled`, `migratedLearnEnabled`, `practiceDetailedHistoryEnabled`);
  Epic 4 additívan ad `aiTutorEnabled` + `aiTutorCloudEnabled` mezőt, default OFF.
- **Storage:** `lib/core/storage/storage_keys.dart` `ss.` névtér + verziózott
  envelope + karantén (Chapter 2 szabály); tutor kulcsok ide.
- **Backend:** `backend/app/` (`routers/`, `schemas.py`, `config.py`, `deps.py`,
  `ratelimit.py`, `security.py`, `main.py`), `backend/tests/`; Epic 4 új
  `backend/app/tutor/` modul flag mögött, prod secret hiányában fail-closed boot.
- **Domain purity:** a `lib/features/*/domain/` framework-/Riverpod-/provider-SDK-
  mentes, gépi őr alatt (`tool/check_architecture.dart`); tutor domain sem
  importálhat Fluttert vagy model-provider SDK-t.
- **DSP-tilalom (AGENTS.md §9):** a `docs/rag` fejlesztői DSP-anyag; a user-célú
  tutor knowledge pack (R06) KÜLÖN, nem másolható a `docs/rag`-ből.
- **Gate:** `tools/round-gate.sh <érintett test-útvonalak>` — egyetlen lokális
  záró gate, külön processz format/analyze/test/architecture, nincs `&&`/pipe;
  full suite + property + APK CI = orchestrátor exact-SHA dispatch.
