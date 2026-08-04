# E04-R15 — Backend és Flutter streaming transport

- **Státusz:** PREPARED (előre megírva 2026-08-04, kód olvasva: main @ `fbe1e82`)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 15; §35
- **Branch:** `codex/e04-r15-streaming-transport`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R13 + E04-R14 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

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
> **ADR-reconcile:** a batch **0136**-ot oszt (ai-tutor-streaming-protocol); ha
> az előző körök eltolták, javítsd. `rg`: az R13 gateway-event + R14 router mai
> alakja. **Backend + Flutter kör:** mindkét gate fut. PREPARED→PLANNING,
> brief commit az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED — a mért §0.0-t az élesedő pre-flight tölti ki.** Előre kiosztott ADR:
**0136** (streaming-protocol) — **orchestrátor** írja a pre-flightban, NEM
implementer-diff, NEM TOML `allowed_paths`.

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
| `docs/adr/0136-ai-tutor-streaming-protocol.md` | ÚJ (pre-flight, **orchestrátor**) | protokoll döntés |

**Tilos zóna:** minden más fájl, más feature belső contractja, `docs/rag`,
más kör briefje. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **ADR 0136:** a streaming-protokoll (SSE/választott) rögzített; a sequence
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

1. Pre-flight ADR 0136 (protokoll-döntés).
2. RED gap/duplicate/retry/orphan tesztek (backend + Flutter).
3. backend stream.py + cleanup; remote gateway + DTO parser.
4. Mindkét gate.

## 9. Kockázatok

- Árva provider-request disconnectkor (költség + biztonság) — cleanup kötelező.
- Retry-duplikáció: a user-message idempotens kulccsal megy (analóg R11 clientActionId).

**STOP:** néma gap-elnyelés, árva request vagy retry-duplikáció helyett dokumentált
brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r15-streaming-transport-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
