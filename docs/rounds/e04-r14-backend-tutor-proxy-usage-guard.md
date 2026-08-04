# E04-R14 — Backend tutor proxy, provider registry és usage guard

- **Státusz:** PREPARED (előre megírva 2026-08-04, kód olvasva: main @ `fbe1e82`)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 14; §35
- **Branch:** `codex/e04-r14-backend-tutor-proxy-usage-guard`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R13 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/tutor/__init__.py",
  "backend/app/tutor/router.py",
  "backend/app/tutor/schemas.py",
  "backend/app/tutor/service.py",
  "backend/app/tutor/provider_gateway.py",
  "backend/app/tutor/provider_registry.py",
  "backend/app/tutor/usage.py",
  "backend/app/config.py",
  "backend/app/main.py",
  "backend/tests/tutor/__init__.py",
  "backend/tests/tutor/test_tutor_proxy.py",
  "backend/tests/tutor/test_tutor_usage.py",
  "docs/rounds/e04-r14-backend-tutor-proxy-usage-guard.md",
]
gate_tests = []
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E04-R13 merge; olvasd újra
> `AGENTS.md`, Chapter 1/5, `backend/README.md`, `HANDOFF.md`. Nincs ÚJ ADR
> (R01 **0131** provider-boundary bővítése). `rg`: a `backend/app/config.py`,
> `deps.py`, `ratelimit.py`, `security.py`, `main.py` mai alakja + a
> `backend/tests/conftest.py`. **Backend-kör:** a gate a backend suite
> (`ruff` + `pytest` + alembic) — a Flutter round-gate itt nem elég.
> PREPARED→PLANNING, brief commit az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED — a mért §0.0-t az élesedő pre-flight tölti ki.** Nincs előre kiosztott ADR.

## 1. Cél

Biztonságos FastAPI cloud model-proxy — a provider-részletek (secret, model-id) a
**szerveren maradnak**, a kliens csak a StrumSight backenddel beszél.

## 2. Jelenlegi állapot

- A backend (`backend/app/`) auth + settings-sync + rate-limit + hardening alappal
  létezik (`config.py`, `deps.py`, `ratelimit.py`, `security.py`, `main.py`,
  `routers/`); **tutor-modul nincs**.
- A fail-closed release/boot minta (ADR 0060/0061/0062) a precedens: prod-secret
  hiányában boot-fail.

## 3. Scope

**Benne:** `backend/app/tutor/` modul flag mögött, capability + non-streaming turn
endpoint v1, allowlistelt request/response Pydantic schema, config-alapú provider
registry, request/history/context/output limit, usage + rate-limit guard, redaktált
log + provider-hiba, fake-provider adapter, prod-secret-hiány → fail-closed boot.

**Kívül — TILOS:** streaming (R15), Flutter-oldal (R15 gateway), tetszőleges kliens-oldali
model-id választás, provider-secret kliensbe.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `backend/app/tutor/__init__.py` | ÚJ | modul |
| `backend/app/tutor/router.py` | ÚJ | capability + turn endpoint |
| `backend/app/tutor/schemas.py` | ÚJ | allowlistelt Pydantic schema |
| `backend/app/tutor/service.py` | ÚJ | turn-orchestration |
| `backend/app/tutor/provider_gateway.py` | ÚJ | provider-absztrakció |
| `backend/app/tutor/provider_registry.py` | ÚJ | config-alapú registry |
| `backend/app/tutor/usage.py` | ÚJ | usage + rate-limit guard |
| `backend/app/config.py`, `main.py` | meglévő | flag + router-mount + fail-closed boot (additív) |
| `backend/tests/tutor/*` | ÚJ | proxy + usage + fake-provider tesztek |
| `docs/rounds/e04-r14-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más backend/Flutter fájl, más kör briefje, `docs/rag`.
Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **A provider-secret a szerveren marad**; a Flutter kliens csak a StrumSight
   backendhez beszél (ADR 0131). **NEM elfogadható:** provider-kulcs vagy nyers
   provider-válasz a kliens felé.
2. A kliens **nem választhat tetszőleges model-id-t** — a registry config-vezérelt.
3. **Prod-secret hiányában fail-closed boot** (ADR 0060/0061 minta).
4. A log/provider-hiba **redaktált** (nincs teljes prompt/secret a logban).

## 6. Acceptance criteria

- [ ] feature-flag off ⇒ nincs tutor endpoint; schema-reject; **request-size /
      history / context / output limit mátrix** (alatta/rajta/fölötte); provider-selection
      config szerint; secret-guard; **rate-limit + usage-limit** (küszöb alatt/rajta/fölött).
- [ ] provider-timeout → normalizált hiba; error-mapping; **no prompt log** teszt.
- [ ] fake-providerrel a contract zöld; **prod misconfig blokkolja a bootot** —
      reviewer eldobható mutációval (secret-guard kikapcsolása) pirosra váltja.

## 7. Kötelező ellenőrzések

Backend-kör — a mérce a backend suite (lásd `backend/README.md`):

```bash
cd backend && ruff check . && pytest -q
```

A `ruff` és a `pytest` **külön** hívásként fut (nincs `&&`-lánc a promptban; a fenti
sor a backend saját dokumentált gate-je). A Flutter round-gate itt nem alkalmazandó.
Full backend + Flutter suite + APK CI = orchestrátor exact-SHA dispatch.

## 8. Implementációs sorrend

1. RED schema-reject + limit-mátrix + secret-guard + fail-closed tesztek.
2. schemas + registry + service + provider_gateway + usage.
3. router + config/main mount, flag mögött.
4. fake-provider adapter; backend gate.

## 9. Kockázatok

- Prod-secret fail-closed vs. dev-mock — a boot-logika ne engedjen prodban secret nélkül.
- A settings-sync silent-no-op csapda (round 17) analógja: a usage-guard hibáját ne
  nyelje el try/except — propagálja normalizáltan.

**STOP:** kliens-oldali secret/model-id, néma usage-hiba vagy fail-closed gyengítés
helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r14-backend-tutor-proxy-usage-guard-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
