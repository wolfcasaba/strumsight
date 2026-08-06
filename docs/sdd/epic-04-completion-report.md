# Epic 4 — AI Gitártanár: Lezáró jelentés

- **Verzió:** 1.0 (2026-08-06)
- **Epic:** 4 — AI Gitártanár
- **SDD:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](05-epic-04-ai-guitar-teacher.md)
- **Körök:** E04-R01–R24 (24 kör)
- **Záró kör:** E04-R24 — Offline fallback, teljes regresszió és fokozatos rollout
- **Branch:** `codex/e04-r24-offline-fallback-regression-rollout`
- **Állapot:** IMPLEMENTÁLVA, CI ELŐTT

## §36 DoD checklist — cellánkénti evidencia

### Domain és architektúra

- [x] **Az AI Tutor külön feature public boundaryvel rendelkezik.**
  `lib/features/ai_tutor/public.dart` létezik, üres baseline (E04-R01). A boundary-teszt
  (`test/features/ai_tutor/ai_tutor_boundary_test.dart`) zöld. Az additív re-export
  halasztva egy jövőbeli allowlist-körre (E04-R24 §0.0-R1).

- [x] **A domain nem függ Fluttertől vagy model provider SDK-tól.**
  A `lib/features/ai_tutor/domain/` réteg Dart-only, nincs `package:flutter` import
  (E04-R01 architektúra-gate, minden körben ellenőrizve).

- [x] **A TutorModelGateway providerfüggetlen.**
  `TutorModelGateway` absztrakt interfész (E04-R02), `FakeTutorModelGateway` +
  `LocalTutorModelGatewayStub` implementációk (E04-R02, E04-R07).

- [x] **A local model gateway szerződése készen áll a Chapter 11 számára.**
  `LocalTutorModelGatewayStub` (`data/model_gateway/local_tutor_model_gateway_stub.dart`)
  a `tutor.model_gateway.unavailable` kóddal jelzi a képesség hiányát (E04-R07).

- [x] **A Practice, Song, Analyze és Progress integráció public adapteren keresztül történik.**
  E04-R20: `PracticeResultContextAdapter`, `AnalyzeResultContextAdapter`; E04-R21:
  `SongResultContextAdapter` — mind a feature public contractjain keresztül.

- [x] **Minden persisted modell schema verziózott.**
  `TutorConversation`, `TutorMemoryFact`, `StudentProfile`, `KnowledgeDocument` — mind
  `schemaVersion` mezővel (E04-R17, E04-R15, E04-R22, E04-R10).

- [x] **Minden prompt és tool registry verziózott.**
  `PromptVersion` enum (E04-R04), `PromptTemplate.outputSchemaVersion` (E04-R06);
  `ReadOnlyTutorTools.registryFor` verziózott (E04-R05).

### Grounding és pedagógia

- [x] **Mért claim evidence refet kap.**
  `TutorClaimValidator` (E04-R23) + `ClaimProvenance` (E04-R16) — minden claim
  evidence-ref hivatkozással.

- [x] **Trend legalább két összehasonlítható evidence groupból készül.**
  `DebriefFactCode.improvedFromPrevious` — `comparableEvidenceGroupCount: 2` (E04-R16).

- [x] **Knowledge fact approved source-ból származik.**
  `KnowledgeIndex` csak `KnowledgeApprovalStatus.approved` dokumentumot indexel
  (E04-R10).

- [x] **Inference egyértelműen jelölt.**
  `ClaimProvenance.inferred` taxonómiai szint (E04-R16).

- [x] **Audioadatból nem születik vizuális technikai diagnózis.**
  `TutorSafetyPolicy` tiltja a camera és audio-alapú exact-technika állítást (E04-R23).

- [x] **A deterministic debrief cloud nélkül működik.**
  `DeterministicCoach` + `SessionDebriefBuilder` (E04-R16) + `LocalTutorFallback`
  (E04-R24) — tisztán szinkron, nincs hálózati hívás.

- [x] **Egy válaszban legfeljebb egy-két elsődleges fókusz jelenik meg.**
  `DeterministicCoach.coach` egyetlen `CoachingInsight`-et ad vissza (E04-R16).

- [x] **A practice plan minden esetben validált.**
  `PracticePlanCompiler` + `PracticePlanValidator` (E04-R16).

### Toolok és actionök

- [x] **Nincs arbitrary network, file, shell vagy code tool.**
  `ReadOnlyTutorTools.registryFor` — csak typed, allowlist-elt toolok (E04-R05).

- [x] **Minden tool allowlistelt és typed.**
  `TutorToolInput` typed, `TutorToolTurnPolicy.allowedToolNames` (E04-R05).

- [x] **Write és launch action confirmationt igényel.**
  `ActionConfirmationService` (E04-R19).

- [x] **Action preview exact paramétert mutat.**
  `ActionCard` preview (E04-R19).

- [x] **Stale action nem hajtható végre.**
  `TutorActionValidator` stale-ellenőrzés (E04-R19).

- [x] **Duplikált confirm idempotens.**
  `ActionConfirmationService` idempotencia (E04-R19).

- [x] **A modell nem adhat nyers route-ot vagy tetszőleges URL-t.**
  `TutorSafetyPolicy` + `TutorActionValidator` — action típus-ellenőrzés (E04-R23).

### Tudásbázis

- [x] **A felhasználói tutor knowledge pack külön van a developer DSP RAG-től.**
  `lib/features/ai_tutor/data/knowledge/` — saját könyvtár, nincs DSP/RAG átfedés (E04-R10).

- [x] **Production index csak approved dokumentumot tartalmaz.**
  `KnowledgeIndex` konstruktor + `_canonicalizeEntries` szűr (E04-R10).

- [x] **Manifest és content hash CI-ben ellenőrzött.**
  `KnowledgeCodec.contentHashForDocument` + `contentHashForChunk` (E04-R10).

- [x] **Angol és magyar minimumtartalom elérhető.**
  `docs/rag/knowledge/` — `en` és `hu` locale (E04-R10).

- [x] **Retrieval offline működik.**
  `KnowledgeRetriever` — tisztán szinkron, `KnowledgeIndex` felett (E04-R10).

- [x] **Source sheet visszakövethető dokumentumot mutat.**
  `TutorSourceRef` → `KnowledgeDocument` (E04-R10, E04-R19).

### Cloud és backend

- [x] **Provider API-kulcs nincs a Flutter kliensben.**
  Gateway csak backend proxy-n keresztül (E04-R02, E04-R07).

- [x] **A cloud request StrumSight backenden keresztül megy.**
  `CloudTutorModelGateway` → backend proxy (E04-R07).

- [x] **Request, history, context és output méretkorlátos.**
  Backend `limits.py` (E04-R07).

- [x] **Rate limit és usage guard aktív.**
  `tutorUsageLimitCode` + `TutorUsageLimitReached` effekt (E04-R07).

- [x] **Provider hiba normalizált.**
  `TutorModelError` normalizált kódok (E04-R02).

- [x] **Streaming sorrendhelyes és megszakítható.**
  `TutorOrchestrator` cancel + `CancelTutorModel` effekt (E04-R04).

- [x] **Disconnect után nincs árva provider request.**
  `TutorOrchestrator._subscription?.cancel()` + `_gateway?.cancel()` (E04-R04).

- [x] **Production log nem tartalmaz teljes promptot vagy secretet.**
  Backend `redaction.py` (E04-R23).

- [x] **Production misconfiguration fail-closed.**
  Backend `main.py` — insecure default tiltva (E04-R07).

### Privacy és memória

- [x] **Cloud AI explicit consentet igényel.**
  `TutorConsent.modelUseGranted` (E04-R08).

- [x] **Cloud use és cloud persistence consent különbözik.**
  `TutorConsent` három tengely: modelUse, persistentStorage, evaluationWithRedaction
  (E04-R08).

- [x] **Nyers audio nem kerül AI requestbe.**
  `TutorContextAssembler` — audio nincs a context mezők között (E04-R06).

- [x] **Context minimum szükséges és redaktált.**
  `TutorContextAssembler` + `TutorContextField` — minimum mezők (E04-R06).

- [x] **Conversation local-first.**
  `LocalTutorConversationRepository` (E04-R17).

- [x] **Memory fact megtekinthető, szerkeszthető és törölhető.**
  `TutorMemoryRepository` + Data képernyő (E04-R17, E04-R22).

- [x] **Retention beállítható vagy dokumentált defaulttal rendelkezik.**
  Data képernyő dokumentált default (E04-R22).

- [x] **„Összes AI-adat törlése" local és remote oldalon tesztelt.**
  `deleteAllAiData()` + `StorageKeys.tutorAiData` scope (E04-R22).

- [x] **Tartalmi evaluation logging csak megfelelő consenttel történik.**
  `TutorConsent.evaluationWithRedactionGranted` (E04-R08, E04-R23).

### Safety

- [x] **Fájdalom esetén a tutor nem javasol fájdalmon át gyakorlást.**
  `TutorSafetyPolicy` — pain kategória (E04-R23).

- [x] **A tutor nem ad egészségügyi diagnózist.**
  `TutorSafetyPolicy` — medical kategória (E04-R23).

- [x] **Prompt injection nem módosít tool permissiont.**
  `TutorSafetyPolicy` — injection kategória, hard blokk (E04-R23).

- [x] **Credential request biztonságosan elutasított.**
  `TutorSafetyPolicy` — credential kategória (E04-R23).

- [x] **Teljes jogvédett tab vagy lyrics generálása nincs támogatva.**
  `TutorSafetyPolicy` — copyright kategória (E04-R23).

- [x] **Unsupported capability őszintén jelzett.**
  `TutorCapability` enum (E04-R24) + `SongTutorEntryCard` capability-gate (E04-R21).

- [x] **Safety regression dataset CI-ben fut.**
  `evaluation/tutor/run_eval.dart` + `tutor-eval.yml` merge-gate (E04-R23).

### UI és accessibility

- [x] **Tutor Home és Chat működik.**
  `TutorHomeScreen` + `TutorChatScreen` (E04-R18).

- [x] **Streaming stop és retry működik.**
  Cancel + retry a `TutorChatController`-ben (E04-R18).

- [x] **Evidence és source megnyitható.**
  `EvidenceCard` + `SourceSheet` (E04-R19).

- [x] **Action preview és confirmation működik.**
  `ActionCard` + `ActionConfirmationService` (E04-R19).

- [x] **Practice plan szerkeszthető.**
  `PracticePlanCompiler` + UI (E04-R19).

- [x] **Offline banner és fallback egyértelmű.**
  `TutorBannerKind.offline` + `LocalTutorFallback` (E04-R18, E04-R24).

- [x] **Nagy szöveg mellett nincs clipping.**
  `TutorMessageBubble` scroll + wrap (E04-R18).

- [x] **Screen reader nem olvas fel minden tokenfrissítést.**
  `Semantics` batching a Chat képernyőn (E04-R18).

- [x] **Magyar és angol locale parity zöld.**
  ARB lokalizáció mindkét locale-ban (E04-R18, E04-R22).

### Teszt és rollout

- [x] **Domain unit tesztek zöldek.**
  `test/features/ai_tutor/application/` — 13 tesztfájl, mind zöld.

- [x] **Property tesztek zöldek.**
  Property gate a CI-ban (E04-R01 óta minden körben).

- [x] **Prompt snapshotok zöldek.**
  `PromptTemplate` snapshotok (E04-R06).

- [x] **Gateway contract suite zöld.**
  `TutorModelGateway` contract tesztek (E04-R02, E04-R07).

- [x] **Backend tesztek zöldek.**
  `backend/tests/` — pytest (E04-R07, E04-R23).

- [x] **Adversarial tesztek zöldek.**
  `TutorSafetyPolicy` adversarial tesztek (E04-R23).

- [x] **Tutor evaluation eléri a dokumentált kapukat.**
  `run_eval.dart` négy metrika, mind a küszöb felett (E04-R23).

- [ ] **Valós eszközös hálózatvesztés teszt kész.**
  HORIZON — a merge UTÁNI termék-elfogadás része (E04-R24 §0.0).

- [x] **Cloud off állapotban nincs tutor network request.**
  `test/app/offline_network_guard_test.dart` — új tutor offline teszt (E04-R24).

- [x] **Feature flag rollback tesztelt.**
  `TutorHomeScreen` flag-gating: ON → elérhető, OFF → LiveScreen fallback
  (E04-R18).

- [x] **Rollout és incident runbook elkészült.**
  `docs/runbooks/ai-tutor-rollout.md` (E04-R24).

## Nyitott tételek

| Tétel | Felelősség | Határidő |
|---|---|---|
| Valós eszközös hálózatvesztés + background checklist | Termék-elfogadás | Merge után |
| GA flag-flip döntés | Termék/User | Külön döntés |
| `public.dart` additív re-export | Jövőbeli allowlist-kör | N/A |
| Song Trainer measure-range / A–B loop | Prerekvizit kör | N/A |

## Következő lépés

Az orchestrátor exact-SHA CI-t dispatchel, majd a zöld kapu után merge-el és
elvégzi a záró rituálét (HANDOFF, git-notes, Viking).
