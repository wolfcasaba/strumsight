# E04-R15 — Backend és Flutter streaming transport

- **Státusz:** PLANNING (pre-flight 2026-08-05, kód mérve: main @ `b15165d`, E04-R13+R14 merge után)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 15; §35
- **Branch:** `codex/e04-r15-streaming-transport`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R13 + E04-R14 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** qwen38-max (`qwen/qwen3.8-max`, ADR 0140 aktív override, `codex-round.sh`)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/tutor/stream.py",
  "backend/app/tutor/router.py",
  "lib/features/ai_tutor/data/model_gateway/remote_tutor_model_gateway.dart",
  "lib/features/ai_tutor/data/dto/tutor_stream_dto.dart",
  "lib/features/ai_tutor/public.dart",
  "backend/tests/tutor/test_tutor_stream.py",
  "test/features/ai_tutor/data/remote_tutor_model_gateway_test.dart",
  "docs/rounds/e04-r15-streaming-transport.md",
]
gate_tests = [
  "test/features/ai_tutor/data",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E04-R13/R14 merge; olvasd újra
> `AGENTS.md`, Chapter 1/5 (**§20 streaming**), `backend/README.md`, `HANDOFF.md`.
> **ADR-reconcile:** a batch **0136**-ot osztott, de az foglalt (tutor-knowledge-
> retrieval) → a pre-flight a **0142**-t osztja (ld. §0.0). `rg`: az R13 gateway-event + R14 router mai
> alakja. **Backend + Flutter kör:** mindkét gate fut. PREPARED→PLANNING,
> brief commit az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**Mért pre-flight (2026-08-05, `main` @ `b15165d`, E04-R13+R14 merge után).**

**ADR-szám — mérve, JAVÍTVA.** A batch a **0136**-ot osztotta ki, de az azóta
merge-elt körök `0136`-ot `tutor-knowledge-retrieval`-re foglalták le
(`docs/adr/0136-tutor-knowledge-retrieval.md`); a legmagasabb kiosztott szám a
`main`-en **0141**. A brief pre-flight klauzulája ezt előírta („ha az előző
körök eltolták, javítsd"), ezért a streaming-protokoll ADR a következő szabad
számot kapja: **[ADR 0142](../adr/0142-ai-tutor-streaming-transport-protocol.md)**
(orchestrátor írta a pre-flightban). Merge-elt ADR nem módosul (nincs H1).

**Mért baseline (grep-elt kontraktusok):**

- **R13 kliens-event (`lib/features/ai_tutor/data/model_gateway/`):** a
  `TutorModelGateway` interfész `Future<AppResult<Stream<TutorModelEvent>>>
  start(TutorModelRequest)` + `void cancel()` + `Future<AppResult<void>>
  health()`. A `TutorModelEvent` **sealed**, `sequence`-szel; leszármazottak:
  `TutorModelDelta{delta}`, `TutorModelToolCall{toolCallId,name,arguments}`,
  `TutorModelDone`, `TutorModelError{code,message}`. **Nincs `started`/`usage`
  variáns** → a wire `started`/`usage` frame kontroll, nem surfacelt event
  (ADR 0142 D6). A gateway a duplikált terminálist már eldobja.
  `TutorModelRequest{requestId,sequence,conversationId,message}` a retry-
  idempotencia kulcsa (ADR 0142 D9).
- **R14 backend (`backend/app/tutor/`):** a `/tutor` router már
  `include_router`-elt a `main.py`-ban (`if settings.tutor_enabled`); a
  streaming-route **additívan** a meglévő `router.py` `APIRouter`-ére szerelődik
  — **`main.py` NEM kell** (és nincs is az `allowed_paths`-ban). A
  `ProviderGateway.complete()` egyetlen `str`-t ad; a `service.py` és a
  `provider_gateway.py` **kívül a scope-on** → a `stream.py` a nem-streaming
  válaszból **szintetizálja** a rendezett frame-sorozatot, és maga birtokolja a
  provider-coroutine-t az `asyncio.Task` cancellationhöz (ADR 0142 D7, D10). A
  méret-korlát az R14 `TutorLimits` (413) + frame-size-limit.

**§1 mérési szabályok (pipeline-prompt):**

1. *Elérhetetlen cél-státusz:* az acceptance „transport-failure" állapotát a
   **kliens-parser** produkálja gap/out-of-order/malformed/frame-too-large
   inputra (`TutorModelError(code: "transport_*")`, ADR 0142 D4/D6/D8). Ma egyetlen
   `TutorModelError`-t a `fake_tutor_model_gateway.dart:180` konstruál — az R15
   remote gateway/DTO ÚJ termelője ennek az útnak. Az állapot **elérhető**.
2. *Erőforrás-tulajdonlás:* `grep -rn "\.acquire(\|lease\|subscribe"
   backend/app/tutor lib/features/ai_tutor` → **üres**. Nincs long-lived
   erőforrás; a „provider-request" egy `await`-elt coroutine, tulajdonosa a
   **`stream.py` végpont** (ADR 0142 D7). A disconnect-cleanup = task-cancel a
   végponton, nem service-módosítás.

## 1. Cél

**Sorrendhelyes, megszakítható, újrapróbálható** tutor streaming a backend és a
Flutter kliens között, kontrollált transport-hibákkal.

## 2. Jelenlegi állapot

- R14 után van non-streaming turn endpoint; **streaming nincs**.
- R13 gateway-event-hierarchia a kliens-oldali normalizált event forrása; a remote
  gateway ezt tölti a stream-frame-ekből.

## 3. Scope

**Benne:** ADR-ben rögzített protokoll (SSE vagy választott), monoton event-sequence,
started/delta/usage/tool-call/complete/failure frame, disconnect-cleanup + provider-
cancellation, Flutter stream-parser, duplicate-frame idempotens, gap/out-of-order →
kontrollált transport-failure, retry nem duplikál user-message-et, body+frame size-limit,
background-policy dokumentált.

**Kívül — TILOS:** UI (R18), orchestration (R16), tetszőleges provider-frame kliensbe.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `backend/app/tutor/stream.py` | ÚJ | streaming endpoint + cleanup |
| `backend/app/tutor/router.py` | R14-ből | stream-route mount (additív) |
| `.../data/model_gateway/remote_tutor_model_gateway.dart` | ÚJ | remote gateway |
| `.../data/dto/tutor_stream_dto.dart` | ÚJ | frame-parser DTO |
| `lib/features/ai_tutor/public.dart` | előző körökből | additív export |
| `backend/tests/tutor/test_tutor_stream.py` | ÚJ | stream edge-case tesztek |
| `test/features/ai_tutor/data/remote_tutor_model_gateway_test.dart` | ÚJ | parser tesztek |
| `docs/rounds/e04-r15-*.md` | meglévő | §10 handoff |
| `docs/adr/0142-ai-tutor-streaming-transport-protocol.md` | ÚJ (pre-flight, **orchestrátor** — 0136 foglalt, ld. §0.0) | protokoll döntés |

**Tilos zóna:** minden más fájl, más feature belső contractja, `docs/rag`,
más kör briefje. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **ADR 0142:** a streaming-protokoll **SSE** (rögzített); a sequence
   **monoton**; gap/out-of-order → **kontrollált transport-failure** (nem néma átugrás).
   **NEM elfogadható:** hiányzó frame csendes elnyelése.
2. Duplicate-frame **idempotens**; **retry nem duplikál** user-message-et.
3. Disconnect után **nincs árva provider-request** (cleanup + cancellation).
4. Body + frame **size-limit**; a kliens normalizált eventet kap (R13).

## 6. Acceptance criteria

- [ ] normal stream; disconnect; cancel; duplicate frame; **sequence gap** →
      transport-failure; malformed JSON; timeout; **retry** nem duplikál; backend cleanup;
      **large frame reject** (size-limit alatt/rajta/fölött mátrix).
- [ ] disconnect után **nincs árva provider-request** — teszt; reviewer eldobható
      mutációval (gap-detektálás kikapcsolása) pirosra váltja.

## 7. Kötelező ellenőrzések

Flutter oldal:

```bash
tools/round-gate.sh test/features/ai_tutor/data
```

Backend oldal (külön, `backend/README.md`):

```bash
cd backend && ruff check . && pytest -q backend/tests/tutor/test_tutor_stream.py
```

Nincs `&&`-lánc a promptban a Flutter gate-en belül. Full CI = orchestrátor exact-SHA.

## 8. Implementációs sorrend

1. Pre-flight ADR 0142 (protokoll-döntés) — **kész** (orchestrátor).
2. RED gap/duplicate/retry/orphan tesztek (backend + Flutter).
3. backend stream.py + cleanup; remote gateway + DTO parser.
4. Mindkét gate.

## 9. Kockázatok

- Árva provider-request disconnectkor (költség + biztonság) — cleanup kötelező.
- Retry-duplikáció: a user-message idempotens kulccsal megy (analóg R11 clientActionId).

**STOP:** néma gap-elnyelés, árva request vagy retry-duplikáció helyett dokumentált
brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

**Motor:** qwen38-max (explicit engine-override). Continuation session: az első
futás a backend + tesztek megírása után token-limit miatt jelzés nélkül leállt;
ez a session a hiányzó Flutter-implementációt készítette el és commitolt.

### Fájlonkénti összefoglaló

| Fájl | Változás |
|---|---|
| `lib/features/ai_tutor/data/dto/tutor_stream_dto.dart` | ÚJ — `TutorTransportErrorCode` (5 wire-kód: `transport_sequence_gap` / `transport_malformed` / `transport_frame_too_large` / `transport_truncated` / `transport_stream_error`, ADR 0142 D4/D6/D8); `TutorStreamFrame` sealed hierarchia (started/delta/tool_call/usage/complete/failure, közös monoton `seq`); `TutorFrameOutcome` sealed (accepted/rejected/dropped); `TutorStreamFrameParser` — szigorú monoton seq (gap/out-of-order → `sequenceGap` reject és a parser lezárul), pontosan egyező szomszéd-duplikátum → idempotens drop, terminális frame vagy rejection után minden további frame drop; nem-JSON / nem-object / ismeretlen type / hiányzó vagy rossz típusú mező → `malformed`; `maxFrameBytes` felett → `frameTooLarge`; `defaultTutorFrameBytesLimit = 8192` (a backend `MAX_FRAME_BYTES` tükre); `TutorStreamTransport` interfész (`openTurnStream` / `cancelActiveStream` / `health`). |
| `lib/features/ai_tutor/data/model_gateway/remote_tutor_model_gateway.dart` | ÚJ — `RemoteTutorModelGateway implements TutorModelGateway`, `{required transport, maxFrameBytes = default}`. `start()`: busy-check → `UnknownFailure('tutor.model_gateway.busy')`; transport-open failure átmegy változatlanul; sikeres open után friss parserrel normalizál az R13 hierarchiára (`delta`→`TutorModelDelta`, `tool_call`→`TutorModelToolCall`, `complete`→`TutorModelDone`, `failure`→`TutorModelError` a szerver kódjával/üzenetével; `started`/`usage` kontroll-frame, nem surfacelt). Rejected frame / nyers stream-hiba / terminális frame nélküli lezárás → terminális `TutorModelError(code: transport_*)`. `cancel()` transport-cancel + stream-zárás (újrahívás no-op), `health()` delegál, `isRunning` publikus. |
| `test/features/ai_tutor/data/remote_tutor_model_gateway_test.dart` | Előző session írta (28 teszt, 14 parser + 14 gateway). EGY javítás e sessionben: a „frame size matrix" frame-jei `seq: 1` → `seq: 0` (ld. Eltérések). |
| `backend/app/tutor/stream.py` | Előző session munkája (ÚJ, 227 sor) — SSE frame-szintézis, `MAX_FRAME_BYTES = 8192`, task-cancel cleanup. Most commitolva, tartalmához nem nyúltam. |
| `backend/app/tutor/router.py` | Előző session +7 sora — stream-router mount (additív, alul import a circular import elkerülésére). Diff review-zva: rendben. |
| `backend/tests/tutor/test_tutor_stream.py` | Előző session munkája (ÚJ, 388 sor). Most commitolva. |
| `lib/features/ai_tutor/public.dart` | NEM változott — a boundary jelenleg üres (`library;`), R13/R14 sem exportált gateway-contractot, cross-feature fogyasztó még nincs; a teszt közvetlen path-importot használ. Az üresen hagyás konzisztens a korábbi körökkel. |

### Futtatott parancsok és tényleges eredmények

- `flutter test test/features/ai_tutor/data/remote_tutor_model_gateway_test.dart`
  → **28/28 zöld** (EXIT=0).
- `tools/round-gate.sh test/features/ai_tutor/data` →
  format **ZÖLD** (970 fájl, a 3 módosított `dart format`-tálva) ·
  analyze **ZÖLD** (No issues found) ·
  test `test/features/ai_tutor/data` **ZÖLD** (97 teszt, EXIT=0) ·
  architecture **ZÖLD** (12 allowlisted deviation — meglévő) ·
  secrets **PIROS**: 4 találat — `backend/tests/tutor/test_tutor_proxy.py:596,611,627,631`
  („credential assigned a long literal"). Ezek az **R14 merge-ben (c1c0a77)
  commitolt fake `Settings(...)` boot-fixture sorai**, nem e kör diffjéből
  származnak, és a fájl az engedélyezett listán kívül esik → follow-up F1.

### Eltérések

1. **Méretmátrix-teszt `seq` javítása.** A teszt friss parseren várt
   elfogadni `seq: 1`-es delta frame-et, miközben a „rejects a gap in the very
   first frame" teszt ugyanezt `sequenceGap`-re utasítja, és az ADR 0142
   monoton-szabálya is ezt követeli — a két elvárás egymásnak ellentmondott.
   A mátrix célja tisztán a mérethatár (alatta/rajta/felette), ezért a
   frame-ek `seq`-ja `0`-ra javítva (1 számjegy, a méret-matek változatlan);
   ezután 28/28 zöld. A tesztfájl az engedélyezett listán van.
2. `public.dart` nem bővült exporttal (indoklás a táblázatban).

### Nem futtatott ellenőrzések és okuk

- `cd backend && ruff check . && pytest -q tests/tutor/test_tutor_stream.py` —
  a boxon nincs `ruff`/`pytest`/`python` (csak csupasz `python3`), backend venv
  nincs, **telepítés tiltott**. A backend-oldal bizonyítása a CI-é (F2).
- Teljes `flutter test` suite, property gate, APK build — orchestrátor/CI
  feladat (§12, ADR 0052/0053).

### Follow-up (scope-on kívül)

- **F1:** `backend/tests/tutor/test_tutor_proxy.py` 4 fake-fixture sorára
  `# strumsight:allow-secret <indok>` marker kell, különben a round-gate
  secrets-lépése minden jövőbeli futásban piros marad. A fájl az E04-R15
  engedélyezett listáján kívül esik, ezért nem módosult.
- **F2:** backend ruff/pytest futtatása CI-ben (boxon nincs Python-környezet).

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r15-streaming-transport-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
