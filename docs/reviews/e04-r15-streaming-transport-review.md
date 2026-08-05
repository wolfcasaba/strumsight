# Review — E04-R15 Backend és Flutter streaming transport

- **Kör:** E04-R15 · **Branch:** `codex/e04-r15-streaming-transport`
- **Implementer motor:** qwen38-max (`qwen/qwen3.8-max`, ADR 0140 override, `codex-round.sh`)
- **Implementációs commit:** `29ea65f` (base `b15165d`)
- **Reviewer:** Claude (Opus 4.8), orchestrátor — read-only, izolált `/tmp/review-e04-r15` klón
- **ADR:** [0142](../adr/0142-ai-tutor-streaming-transport-protocol.md) (orchestrátor pre-flight)
- **Verdikt:** **KÓD APPROVED** (minden lelet zárva), **MERGE HALT (H3)** — a
  build-apk secret-scan egy tilos-zóna fájlon piros (lásd §8–§9).

## 1. Jelzés + handoff

`.codex-round-status`: `status=done`, `head=29ea65f`, `scope_audit=ok`,
`scope_audit_changed=4` (a wrapper a 4 nem-doc fájlt számolta). A záró jelzés az
első futásból kimaradt (token-kifogyás, `status=unknown`) — egy folytató körrel
lett befejezve, ez a NORMÁL út, nem halt. A handoff §10 üres maradt (MINOR, lásd
lentebb).

## 2. Gate-újrafuttatás (saját kéz, `/tmp/review-e04-r15`, `29ea65f`)

`tools/round-gate.sh test/features/ai_tutor/data`:

| Lépés | Eredmény |
|---|---|
| format | zöld |
| analyze | zöld |
| test `test/features/ai_tutor/data` | **zöld** (28/28) |
| architecture | zöld |
| secrets | **PIROS (1)** — pre-existing R14, lásd NOTE-1 |

Backend (venv ruff, `/home/ubuntu/music-theory/backend/.venv/bin/ruff`):

| Lépés | Eredmény |
|---|---|
| `ruff check app/tutor/stream.py tests/tutor/test_tutor_stream.py` | zöld (All checks passed) |
| `ruff format --check app tests` | **PIROS** — 2 fájl (MAJOR-1) |

CI (exact SHA `29ea65f`): Router CI **success**, Backend CI **failure**
(ruff-format, MAJOR-1), Build APK folyamatban.

## 3. Scope-audit

`git diff --stat 18f9273..29ea65f` — **minden fájl az `allowed_paths`-on belül**:
`backend/app/tutor/{stream.py,router.py}`, `backend/tests/tutor/test_tutor_stream.py`,
`lib/features/ai_tutor/data/dto/tutor_stream_dto.dart`,
`lib/features/ai_tutor/data/model_gateway/remote_tutor_model_gateway.dart`,
`test/features/ai_tutor/data/remote_tutor_model_gateway_test.dart`,
`docs/rounds/e04-r15-streaming-transport.md`. `public.dart` nem változott
(a teszt direkt path-importot használ — az additív export nem volt kötelező).
Tilos zóna érintetlen (`main.py`, `service.py`, `provider_gateway.py` nem módosult).
**Scope: TISZTA.**

## 4. Acceptance criteria (§6) — tételes bizonyíték

| Kritérium | Bizonyíték | Verdikt |
|---|---|---|
| normal ordered stream | `test_normal_stream_emits_ordered_frames`: started→…→complete, seq `range(n)`, egyetlen terminális | ✅ |
| disconnect → **nincs árva provider-request** | `test_disconnect_cancels_provider_task`: `_hang_until_cancelled` (sleep 3600), disconnect a started után, `assert turn_task.cancelled()`; a `finally: turn_task.cancel()` eltávolítása PIROS | ✅ (mutáció-öléssel) |
| cancel | gateway `cancel()` → transport.cancelActiveStream + `_finish` (subscription cancel + controller close) | ✅ |
| duplicate frame idempotens | DTO `parse`: `seq==next-1 && payload==last` → `TutorFrameDropped` | ✅ |
| **sequence gap** → transport-failure | DTO: `seq!=next` (nem dup) → `TutorFrameRejected(sequenceGap)`; gateway → `TutorModelError(transport_sequence_gap)` | ✅ |
| malformed JSON | DTO: nem-JSON / nem-objektum / hiányzó-rossz mező / ismeretlen type → `malformed` | ✅ |
| timeout | `test_provider_timeout_maps_to_failure_frame`: [started, failure(provider_timeout)] | ✅ |
| **retry** nem duplikál | `test_retry_does_not_duplicate_user_message`: 2 hívás, azonos message-lista, pontosan 1 user-message; a backend stateless (nem perzisztál), az idempotencia inherens (ADR 0142 D9) | ✅ |
| backend cleanup | `tutor_stream_frames` `finally` minden úton cancelli a taskot | ✅ |
| **large frame reject** (mátrix) | DTO `utf8.encode(payload).length > maxFrameBytes` → `frameTooLarge` a decode ELŐTT; backend `encode_sse_frame` sosem bocsát ki limit fölötti frame-et, a delta-chunkolás garantálja a méretet | ✅ |
| gap-detektálás kikapcsolás → PIROS | a DTO seq-guard eltávolítása a gap/dup teszteket pirosra váltja | ✅ |

## 5. Architektúra + termékhatárok (AGENTS.md §5/§6)

- **Auth:** `/tutor/stream` `current_user: CurrentUser` paraméterrel védett
  (stream.py:206), a `turn`-nel azonosan; `test_stream_requires_authentication`
  401/403-at vár. ✅ (a security-review NOTE-1 kielégítve.)
- **Secret/prompt-leak:** a failure-frame `message` FIX, provider-semleges string
  (sosem `str(exc)`); a logging csak metaadat (user_id, request_id, sequence),
  a prompt/reply sosem logolódik (stream.py:214–220). ✅ (NOTE-2 kielégítve.)
- **Lifecycle:** a StreamController + StreamSubscription minden terminális/hiba/
  cancel úton felszabadul (`_finish` idempotens). ✅
- **Domain-függetlenség:** a DTO/gateway nem hoz be UI/provider-SDK típust; a
  `TutorStreamTransport` absztrakció mögé rejti a wire-t. ✅

## 6. Leletek

| Kód | Súly | Fájl:sor | Lelet | Javaslat |
|---|---|---|---|---|
| MAJOR-1 | MAJOR | `backend/app/tutor/stream.py`, `backend/tests/tutor/test_tutor_stream.py` | A `ruff format --check` PIROS (kézi sortördelés a ruff stílusától eltér) → **Backend CI failure**. `ruff check` (lint) zöld, viselkedésváltozás NINCS. | Javító kör: `ruff format` a két fájlon (venv ruff), commit. |
| NOTE-1 | NOTE | `backend/tests/tutor/test_tutor_proxy.py:596,611,627,631` | A `check_secrets` PIROS egy **R14-es** teszt-fixture fake kulcsain. **Pre-existing** (c1c0a77/R14 merge-elt), NEM ez a kör diffje, a fájl a tilos zónában, a CI merge-kapu (build-apk + router-ci) NEM futtatja a secrets-scant. R14 pontosan ebben az állapotban merge-elt. | Nem blokkolja R15-öt. Önjavító kör (ADR 0112) tegye a fájl tetejére: `// strumsight:allow-secret-file teszt-fixture`. |
| MINOR-1 | MINOR | `docs/rounds/e04-r15-streaming-transport.md` §10 | Az „Implementation handoff" szekció üres maradt. | Follow-up: a záró rituálékban röviden kitölthető; nem hizlalja a diffet érdemben, de nem blokkol. |

## 7. Merge-döntés

MAJOR-1 nyitva → **merge TILOS**. Javító kör #1 (qwen38-max) dispatch-elve a
MAJOR-1 leletlistával. A javítás után: Backend CI újra, exact-SHA zöld kapu
(build-apk + backend-ci + router-ci), majd frissített verdikt.

---

## 8. Javító körök + security-review

### Security-review (független ágens, `29ea65f` valódi kód ellen)

Verdikt: **nincs BLOCKER, nincs MAJOR** biztonsági szempontból. NOTE-1 (auth),
NOTE-2 (nincs secret/prompt-leak a failure-frame-ben), NOTE-3 (orphan-cancel
valóban tesztelt, hang-until-cancelled coroutine + `assert turn_task.cancelled()`)
mind **MEGERŐSÍTVE** a valódi kód ellen. Size-limit mindkét irányban, minden
transport-deviáció kontrollált `transport_*` failure. **Egy új MINOR:** log-forging
a `request_id`-n (kontrollkarakter → hamis log-sor; csak log-integritás, nincs
titok/prompt-szivárgás).

### Javító kör #1 — `c5a1564` (MAJOR-1 zárás)

`ruff format` a `stream.py` + `test_tutor_stream.py`-on. Reviewer-mérés (venv
ruff): `ruff check` zöld, `ruff format --check` zöld. Scope: 2 fájl, `scope_audit=ok`.

### Javító kör #2 — `0f894fe` (MINOR log-forging zárás)

`TutorStreamRequest`-hez `field_validator` a `request_id`+`conversation_id`
kontrollkarakter-tiltásához (C0 + 0x7F → 422) + `test_control_chars_in_identifiers_rejected`
teszt. Scope: 2 fájl. Reviewer-mérés (venv, `0f894fe`): `ruff check` zöld,
`ruff format --check` zöld (33 fájl), `pytest` a teljes backend suite-on
**113 passed**, ebből `test_tutor_stream.py` 15 zöld.

**Leletzárás:** MAJOR-1 ✅ (c5a1564), MINOR-1 (log-forging) ✅ (0f894fe),
MINOR-2 (§10 handoff üres) → follow-up (nem blokkol). A kód-oldal APPROVED.

## 9. Merge-blokkoló — build-apk secret-scan (HALT H3)

**Mért blokkoló (nem a kör hibája):** a `build-apk.yml` „Run Flutter quality
gates" lépése a `tools/round-gate.sh`-t futtatja, amelynek **`secrets` lépése**
(`dart run tool/ci/check_secrets.dart`) **PIROS** — 4 találat a
`backend/tests/tutor/test_tutor_proxy.py`-ban (`secret_key="real-prod-secret-key-..."`
teszt-fixture fake kulcsok, sorok 596/611/627/631). Bizonyíték: a `29ea65f`
build-apk run kizárólag ezen bukott (`Secret scan failed (1687 file(s) scanned,
4 finding(s))` → exit 1; a format/analyze/test/architecture ELŐTTE zöld volt).

- A fájlt **R14** vezette be (`c1c0a77`, PR #142); a scanner a GOV-03 (`c4de748`,
  ADR 0138) — mindkettő már `main`-en. R15 **NEM érinti** ezt a fájlt.
- A javítás (`# strumsight:allow-secret-file <indok>` a fájl tetejére, mert a
  fixture szándékosan fake) **kívül esik R15 `allowed_paths`-án** → tilos zóna.
- Ezért a zöld kapu (build-apk) **nem hozható zöldre** e körön belül; a
  resolution egy tilos-zóna fájl szerkesztését kívánná → **HALT H3** (§2). A
  javítás az önjavító session dolga (ADR 0112, tágabb infra-jog).

**A HALT nem a kód minőségéről szól** — a kód kész, zöld és biztonságos. A
blokkoló egy pre-existing R14 secret-scan false-positive, amely a build-apk
kaput (és minden R14 utáni kört) pirosan tartja, amíg egy önjavító session a
`test_tutor_proxy.py`-ba nem teszi az allow-secret-file jelölést.

**Feloldás után:** re-dispatch build-apk a branchre, exact-SHA zöld kapu, majd
squash-merge (a kód-oldal már APPROVED).
