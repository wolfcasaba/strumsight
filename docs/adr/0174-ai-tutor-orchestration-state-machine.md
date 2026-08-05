# ADR 0174 — AI Tutor orchestration state machine és output-validator

- **Státusz:** Elfogadva (E04-R16 pre-flight, 2026-08-05)
- **Kör:** E04-R16 — Tutor orchestration state machine és output validator
- **Implementer motor:** Codex (`gpt-5.6-terra`, örökölt kézi override, `codex-round.sh`)
- **Epic:** [Chapter 5 — Epic 4: AI Guitar Teacher](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 16; §20; §35
- **Szülő/kontext-ADR-ek:** [0131](0131-ai-tutor-provider-boundary.md) (provider boundary),
  [0132](0132-ai-tutor-privacy-and-consent.md) (privacy/consent, grounding),
  [0137](0137-ai-tutor-readonly-tool-contract.md) (read-only tool contract),
  [0139](0139-ai-tutor-action-proposal-confirmation.md) (action confirm),
  [0141](0141-ai-tutor-prompt-output-schema-injection-boundary.md) (prompt/output-schema),
  [0142](0142-ai-tutor-streaming-transport-protocol.md) (streaming transport)

## Kontextus

Az AI Tutor eddigi körei az egész turn-pipeline **építőelemeit** megépítették,
de a köztük lévő determinisztikus vezérlés hiányzik:

- **R05** redaktált kontextust ad (`TutorContextAssembler.assemble(...)` →
  `TutorContextSnapshot`, sync).
- **R07** trusted-tudás forrás-referenciákat ad
  (`KnowledgeRetriever.retrieve(KnowledgeRetrievalQuery)` → `List<TutorSourceRef>`,
  sync; **üres lista is legális** eredmény).
- **R10** read-only tool-allowlistet + registry-t ad
  (`TutorToolRegistry.schemasForTurn(policy)`, `execute(request)` →
  `Future<AppResult<TutorToolResult>>`).
- **R11** action-javaslat/validátor/megerősítés-szolgáltatást ad
  (`TutorActionValidator.validate(...)`, `ActionConfirmationService.propose/confirm`).
- **R12** verziózott prompt-építést + `TutorOutputSchema.v1`-et ad
  (`TutorPromptBuilder.build(...)` → `Future<TutorPrompt>`).
- **R13/R15** provider-független streaming modellkaput ad
  (`TutorModelGateway.start(request)` → `Future<AppResult<Stream<TutorModelEvent>>>`,
  `cancel()`; terminális `TutorModelDone`/`TutorModelError(code,message)`).

Ezek külön-külön tesztelt, redaktált, allowlistelt egységek, de nincs olyan
**determinisztikus állapotgép**, amely egy tanuló-fordulót (turn) az
`context → retrieval → prompt → gateway → tool → validator` úton végigvezet,
és a hibás/hiányos kimenetet **kontrolláltan** kezeli. UI még nincs (R18), a
valódi cloud sincs (a fake gateway a hajtómű), ezért a réteg most **tisztán,
UI-mentesen** specifikálható és tesztelhető.

A fő kockázatok, amelyeket normatívan rögzíteni kell: (a) **repair-loop
elfajulás** — a modell rossz outputjára korlátlan újrakérés; (b) **cancel utáni
race** — késői stream-event mutálja a lezárt turn state-jét; (c) **hallucinált
tartalom** — a modell nem-alátámasztott claimet vagy nem-allowlistelt actiont
javasol; (d) **párhuzamos turn** egy conversationben.

## Döntés

1. **Determinisztikus, sealed input/effect állapotgép.** A turn-vezérlés a
   Practice-controller precedenst (E02-R13+) tükrözi: sealed `TutorCommand`
   (user-szándék) és sealed `TutorSignal` (környezeti tény, pl. stream-event) egy
   sealed `TutorInput` alatt; **külön** sealed `TutorEffect` fa (egyszeri,
   nem state-en tárolt). A `TutorOrchestrator` a **pure** átmenet-motor
   (`state × input → transition{state, effects, isRejected}`) + a
   pipeline-lépések bekötése; nincs rejtett mutáció. Minden terminal út
   **lezár** — nincs végtelen loop.

2. **Legfeljebb EGY repair-request, majd deterministic fallback.** Ha a
   `TutorOutputValidator` a modell kimenetét érvénytelennek méri, az orchestrator
   **pontosan egyszer** kérhet javított outputot (repair prompt), és ha az is
   érvénytelen, **determinisztikus fallback** választ ad. Korlátlan repair-loop
   **tilos** (ADR 0132 grounding). A repair-cap a state-en számlált, nem
   heurisztikus.

3. **Cancel után a késői event no-op; egy aktív turn / conversation.** Cancel
   hatására az orchestrator meghívja a `gateway.cancel()`-t, és minden ezután
   érkező stream-event **request-id-korreláció** alapján eldobódik (nem mutálja a
   state-et). Egy conversationben egyszerre **egy** aktív turn lehet; a
   párhuzamos küldés (concurrent-send) kontrolláltan elutasított (`isRejected`),
   nem indít második streamet.

4. **A validator claim- ÉS action-schemát is ellenőriz.** A `TutorOutputValidator`
   a `TutorOutputSchema.v1` ellen validál: a nem-alátámasztott (grounding nélküli)
   claim és a nem-allowlistelt/lejárt action **blokkolt** (a hallucinált-metric
   blokk R23-mal együtt teljesedik ki). A validáció **pure** és determinisztikus.

5. **Usage-limit és consent-revoked az orchestration-rétegben modellezett, a
   gateway-réteg érintése nélkül.** Mért hiány (pre-flight): az `ai_tutor`
   rétegben **nincs** usage/rate-limit fogalom, és a `TutorConsent` **nem enum**
   (a revoked = `modelUseGranted == false`). Ezért:
   - **consent-revoked**: az orchestrator a `gateway.start(...)` ELŐTT rövidre
     zár egy terminális *consent-revoked* effektbe, ha a modellhasználat nincs
     engedélyezve;
   - **usage-limit**: a gateway `TutorModelError(code, message)` terminális
     eseményének egy **orchestration-birtokolt kód-konstansát** (az allowed
     orchestration-fájlban élő string, pl. `tutor.usage_limit`) az orchestrator
     külön terminális *usage-limit* útra képezi le. A scripted fake ezt
     `FakeGatewayError(code, message)`-dzsel produkálja. **Új gateway-kód vagy
     -típus NEM kerül a gateway-rétegbe** (tilos zóna); az error-code→terminál
     leképezés az orchestratoré.

## Következmények

- A teljes turn-pipeline UI nélkül, scripted fake-kel, **determinisztikusan**
  tesztelhető (transition-mátrix: happy, retrieval-empty, tool-call, repair
  success, repair failure → fallback, cancel, late-delta no-op, concurrent-send,
  consent-revoked, usage-limit).
- A „nincs végtelen loop / minden terminal path lezár" invariáns **gépi mércét**
  kap: a reviewer a repair-cap eldobásával (mutáció) a gate-et pirosra tudja
  váltani.
- A gateway-, tool-, action-, prompt-rétegek **változatlanok** maradnak; az
  orchestrator csak a meglévő publikus felületüket köti össze.
- A publikus feature-export továbbra is **halasztva** (a `public.dart`
  üres-boundary invariáns tovább él — R18 UI-caller az első valódi fogyasztó);
  lásd a kör-brief §0.0 szűkítését.
