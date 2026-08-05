# ADR 0142 — AI Tutor streaming transport protokoll

- **Státusz:** Elfogadva (E04-R15 pre-flight, 2026-08-05)
- **Kör:** E04-R15 — Backend és Flutter streaming transport
- **Implementer motor:** qwen38-max (`qwen/qwen3.8-max`, Kilo/Codex-harness, `codex-round.sh`, ADR 0140 aktív override)
- **Epic:** [Chapter 5 — Epic 4: AI Guitar Teacher](../sdd/05-epic-04-ai-guitar-teacher.md) §20, §35
- **Kontext-ADR-ek:** [0131](0131-ai-tutor-provider-boundary.md) (provider-boundary),
  R13 gateway-event-hierarchia (`tutor_model_event.dart`), R14 backend proxy (`backend/app/tutor/`)

> **Számozási megjegyzés (pre-flight, mért):** a batch-brief eredetileg a
> **0136** számot osztotta ki (`ai-tutor-streaming-protocol`), de az azóta
> merge-elt körök a 0136-ot `tutor-knowledge-retrieval`-re foglalták le
> (`docs/adr/0136-tutor-knowledge-retrieval.md`), és a legmagasabb kiosztott
> szám a merge-elt `main`-en 0141. A brief pre-flight klauzulája ezt explicit
> előírja: „a batch 0136-ot oszt … ha az előző körök eltolták, **javítsd**".
> Ezért ez a streaming-protokoll ADR a következő szabad számot, a **0142**-t
> kapja. Merge-elt ADR-t nem módosítunk (nincs H1).

## Kontextus

R14 után a backend `/tutor/turn` végpontja **nem-streaming**: a
`TutorService.turn()` egyetlen `TutorTurnResponse(reply=...)`-t ad vissza, a
`ProviderGateway.complete()` pedig egyetlen `str`-t. A kliens oldalon az R13
`TutorModelGateway` interfész **stream-alapú** (`Future<AppResult<Stream<
TutorModelEvent>>> start(...)`), és az R13 esemény-hierarchia
(`TutorModelDelta`/`TutorModelToolCall`/`TutorModelDone`/`TutorModelError`,
mind monoton `sequence`-szel) a normalizált kliens-event forrása — de ma csak a
`FakeTutorModelGateway` tölti. Hiányzik a valódi transport a backend és a
kliens között.

A cél sorrendhelyes, megszakítható, újrapróbálható streaming **kontrollált**
transport-hibákkal — a néma frame-elnyelés tilos (SDD §20, §35 „message
sorrend stable sequence alapján").

**Mért scope-korlát (E04-R15 `allowed_paths`, pre-flight):** a kör NEM nyúlhat
a `backend/app/main.py`-hoz, a `backend/app/tutor/service.py`-hoz és a
`backend/app/tutor/provider_gateway.py`-hoz. A `/tutor` router már
`include_router`-elt a `main.py`-ban, ezért az új streaming-útvonal **additívan**
a meglévő `backend/app/tutor/router.py` `APIRouter` objektumára szerelődik — új
mount nem kell. Mivel a provider-gateway és a service kívül esik a scope-on, a
streaming-végpont a meglévő nem-streaming válaszból **szintetizálja** a
rendezett frame-sorozatot, és maga birtokolja a provider-coroutine
életciklusát (lásd Döntés 7). A `grep -rn "\.acquire(\|lease\|subscribe"
backend/app/tutor lib/features/ai_tutor` üres — ma egyetlen réteg sem szerez
long-lived erőforrást; a „provider-request" egy `await`-elt coroutine,
tulajdonosa a végpont.

## Döntés

1. **Transport — SSE.** Új `POST /tutor/stream` végpont a meglévő
   authentikált `/tutor` routeren; a válasz `text/event-stream` (SSE). POST,
   mert a `TutorTurnRequest` törzsét viszi (azonos alak, mint `/tutor/turn`),
   a válasz streamelt. Az SSE-t választjuk (nem WebSocket): egyirányú
   szerver→kliens folyam, a meglévő HTTP-auth és a Dio-kliens elég.

2. **Frame-boríték.** Minden SSE `data:` sor egy JSON objektum:
   `{"type": <frame>, "seq": <int>, ...}`. A `seq` **0-tól** monoton, frame-enként
   **+1**, MINDEN frame-típusra közösen (nem típusonként külön számláló).

3. **Frame-típusok:** `started` (kontroll, `seq=0`), `delta`
   (`{"text": <str>}`), `tool_call` (`{"tool_call_id","name","arguments"}`),
   `usage` (kontroll, `{"tokens": <int>}`), `complete` (terminális siker),
   `failure` (terminális hiba, `{"code","message"}`). Pontosan **egy**
   terminális frame (`complete` vagy `failure`) zárja a streamet.

4. **Monoton sequence — kontrollált transport-failure.** A szerver szigorúan
   növekvő `seq`-et bocsát ki. A kliens-parser ellenőrzi:
   `expected == last + 1`. **Gap vagy out-of-order** (`seq > last+1` vagy
   `seq < last` nem-duplikátumként) → a kliens **kontrollált** transport-hibát
   emel: `TutorModelError(code: "transport_sequence_gap", ...)`, és lezárja a
   streamet. **Néma átugrás tilos** (a reviewer eldobható mutációja — a
   gap-detektálás kikapcsolása — a tesztet pirosra váltja).

5. **Duplicate-frame idempotens.** Ha a beérkező `seq` ≤ az utolsó feldolgozott
   (és a payload egyezik) → a kliens **eldobja** (idempotens), nem hibázik. A
   duplikált terminális frame kezelését az R13 gateway már biztosítja (a
   további terminálisokat csendben eldobja).

6. **Normalizált kliens-event (R13-leképezés).** `delta` →
   `TutorModelDelta`, `tool_call` → `TutorModelToolCall`, `complete` →
   `TutorModelDone`, `failure` → `TutorModelError`. A `started` és a `usage`
   **kontroll-frame**, NEM jelenik meg `TutorModelEvent`-ként (az R13
   hierarchiában nincs started/usage variáns; a usage felszínre hozása későbbi
   kör dolga). A `malformed JSON` frame → kontrollált transport-failure
   (`TutorModelError(code: "transport_malformed")`), nem crash.

7. **Disconnect-cleanup + provider-cancellation.** A streaming-végpont a
   provider-hívást `asyncio.Task`-ként birtokolja. Kliens-disconnectkor
   (`Request.is_disconnected()` / lezárt kapcsolat) a végpont
   **cancelli** a taskot és bevárja a cleanupot → **nincs árva
   provider-request**. Ez a kör mérhető acceptance-e (a reviewer eldobható
   mutációja — a cancel elhagyása — a tesztet pirosra váltja).

8. **Size-limit.** A kérés-törzs az R14 `TutorLimits`-t használja
   (413 túlméretre). A **frame-méret** felső korláttal: a szerver soha nem
   bocsát ki a korlát fölötti frame-et, a kliens a korlát fölötti bejövő
   frame-et transport-failure-ként utasítja el (`transport_frame_too_large`).
   Mátrix: korlát alatt / rajta / fölötte.

9. **Retry nem duplikál user-message-et.** Az újrapróbálás a **request-szintű
   azonosítóval** idempotens (`TutorModelRequest.requestId` + a beszélgetés
   monoton `sequence`-e, analóg R11 `clientActionId`). Egy adott
   `requestId`/`sequence` retry-ja friss streamet indít, de a beszélgetéshez a
   user-message-et **nem** fűzi hozzá másodszor.

10. **Szintetizált frame-sorozat (R14 kompatibilitás).** Mivel a
    provider-gateway és a service kívül esik a scope-on, a streaming-végpont a
    meglévő nem-streaming válaszból állítja elő a rendezett sorozatot
    (`started` → egy vagy több `delta` → `usage` → `complete`), és maga
    birtokolja a task-életciklust a cancellationhöz. A **valódi token-szintű
    provider-streaming** későbbi (provider-adapter) körre halasztva.

11. **Background-policy (dokumentált).** Háttérbe kerülő / lecsatlakozó kliens
    esetén a stream megszakad; a szerver cancelli a taskot; R15-ben **nincs**
    szerver-oldali pufferelés vagy resume/replay reconnect után. A retry friss
    streamet indít ugyanarra a `requestId`-ra, a user-message duplikálása
    nélkül. A UI-jelzés és a streaming feature-flag (`aiTutorStreamingEnabled`,
    SDD §35) az R18 dolga — ebben a körben kívül.

## Következmények

- **Pozitív:** provider-független, sorrendhelyes, megszakítható transport;
  minden hiba kontrollált eventté normalizálódik; a scope szűk marad (nem nyúl
  a service-hez/provider-gatewayhez/main.py-hoz).
- **Negatív / halasztott:** nincs valódi token-szintű provider-streaming
  (szintetizált frame-ek); nincs resume/replay reconnect után; a usage-frame
  nem jelenik meg kliens-eventként. Ezek külön körökre halasztva, dokumentálva.
- **Teszt-kötelezettség:** backend `test_tutor_stream.py` (normal / disconnect
  → orphan-cancel / duplicate / gap → transport-failure / malformed / timeout /
  retry-no-dup / size-limit mátrix) és Flutter
  `remote_tutor_model_gateway_test.dart` (parser: gap / duplicate / malformed /
  frame-too-large → transport-failure; happy-path R13-leképezés).

## Alternatívák

- **WebSocket:** kétirányú, de a tutor-turn egyirányú szerver→kliens folyam;
  fölösleges komplexitás és külön auth-kézfogás. Elvetve.
- **Chunked JSON (NDJSON) SSE helyett:** működne, de az SSE keretezés
  (`event:`/`data:`) szabványos a böngésző/Dio oldalon és a jövőbeli
  reconnect-`Last-Event-ID` mezőt ingyen adja. SSE-t választjuk.
- **Provider-gateway streaminggé alakítása most:** kívül a scope-on
  (`provider_gateway.py`/`service.py` nincs az `allowed_paths`-ban); külön
  provider-adapter körre halasztva.
