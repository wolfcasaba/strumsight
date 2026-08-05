# E04-R14 — Backend tutor proxy, provider registry és usage guard

- **Státusz:** PLANNING (pre-flight 2026-08-05, kód mérve: main @ `7de9361`, E04-R13 merge után)
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
  "backend/tests/tutor/conftest.py",
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

**Pre-flight mérve 2026-08-05** (orchestrátor: Claude Opus 4.8; implementer motor:
`qwen-plus` = `qwen/qwen3.7-plus`, codex-harness, ADR 0140). Baseline: `main` @
`7de9361` (E04-R13 MERGED). E04-R13 előfeltétel **teljesül** (PR #141, squash
`b9d2950`).

**Módosítás (ADR 0112 önjavító kör, 2026-08-05, H6).** A `qwen-plus`
implementer kétszer lépett ki záró jelzés nélkül (a modul kész volt, ~5
teszt-fixture/wiring javítás maradt hátra — részletek: `.pipeline/HALTED`).
Motorváltás `qwen-coder-plus`-ra (apply_patch nem támogatott, shell-fallback
szerkesztés) zárta le a kört. A befejezéshez egy megosztott
`backend/tests/tutor/conftest.py` fixture-fájl kellett (a `test_tutor_usage.py`
a `test_tutor_proxy.py`-ban definiált `tutor_client`/`tutor_auth_headers`-t
cross-file nem látta) — ez a fájl az `allowed_paths`-ba fel lett véve. Nem
viselkedés-módosítás, tisztán teszt-infrastruktúra.

**ADR-döntés — NINCS új ADR.** A kör az [ADR 0131](../adr/0131-ai-tutor-provider-boundary.md)
`Döntés` §-ában már rögzített szerveroldali proxy-t **implementálja**, nem
módosít normát: 0131 kimondja, hogy „a cloud-oldal a StrumSight backenden (R14)
keresztül fut", és hogy „a provider kiválasztása, kvótája és hibakezelése
backend-oldali, konfigurációval cserélhető döntés". Ez a kör pontosan ezt hozza
létre. Precedens: E04-R13 szintén 0131 hatálya alatt, új ADR nélkül zárt.

**Mért backend-baseline (a brief állításai a kód ellen ellenőrizve):**

1. **Fail-closed boot mechanizmus — létezik és MÉRT.** `backend/app/main.py`
   `_guard_prod(settings)` (a `create_app` hívja, `main.py:97`) `env == "prod"`
   esetén `RuntimeError`-t dob, ha a secret a dev-default (`main.py:40-44`,
   round 120 / ADR 0060–0062 minta). A tutor prod-secret-guard ezt a fv-t
   **additívan** bővíti (a `main.py` az engedélyezett listán). A reviewer
   eldobható mutációja (guard-ág törlése) így méréssel pirosra vált.
   Az acceptance „prod misconfig blokkolja a bootot" INPUT-ja tehát:
   `create_app(Settings(env="prod", tutor_enabled=True, <hiányzó provider-secret>))`
   → `RuntimeError` — nem átmenettábla-él, hanem tényleges kódút.
2. **Rate-limit erőforrás-tulajdonlás — MÉRT.** A `RateLimiter`
   (`backend/app/ratelimit.py`) példányait ma **modul-szintű** instance-ok
   birtokolják a routerben: `login_limiter`, `register_limiter`
   (`app/routers/auth.py`, a `conftest.py:12` importálja+reseteli). A tutor
   `usage.py` a SAJÁT limiter-instance-át birtokolja (additív, ugyanez a
   minta) — nem nyúl a meglévő limiterekhez; a `ratelimit.py` osztályt csak
   **importálja**. A `ratelimit.py` NINCS az engedélyezett listán → módosítani
   tilos, csak importálni.
3. **Config-minta — MÉRT.** `backend/app/config.py` `Settings(BaseSettings)`,
   `env_prefix="STRUMSIGHT_"`, `@model_validator(mode="before")` a
   környezet-érzékeny defaultokhoz (`config.py:56-65`). A tutor-flag(ek) és a
   provider-registry config ehhez a mintához illeszkedve, additívan kerülnek be.
4. **Router-mount minta — MÉRT.** `main.py` `app.include_router(...)` flag
   mögött (l. `diagnostics` a `settings.diagnostics_enabled`-nél, `main.py:137`).
   A tutor-router ugyanígy, `settings.tutor_enabled` mögött.
5. **Auth-függőség — MÉRT.** `backend/app/deps.py` `CurrentUser` /
   `DbSession` (`deps.py:35-36`) a hitelesített végpontokhoz — a tutor-turn
   végpont ezeket használja.

**Nincs lista-tágítás.** Minden fenti bővítés az `allowed_paths` blokkon belül
van (`config.py`, `main.py`, `backend/app/tutor/*`, `backend/tests/tutor/*`).
A `ratelimit.py`/`deps.py`/`security.py` csak **import**-forrás, nem szerkesztendő.

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

_Tutor modul kész, teszt fixture-ök és prod-boot tesztek javítva.

- backend/tests/tutor/conftest.py: új fájl, shared tutor fixture-ök
- backend/tests/tutor/test_tutor_proxy.py: import rendezés, hibás auth_headers → tutor_auth_headers  
- backend/tests/tutor/test_tutor_usage.py: usage hiba propagálásának tesztelése tutor fixture-ekkel
- backend/app/main.py:63-as sor környéke: fail-closed guard beépítve

Prod-boot tesztek frissítve psycopg2 dependency nélkülre (SQLite-re váltva)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r14-backend-tutor-proxy-usage-guard-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
