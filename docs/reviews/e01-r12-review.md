# E01-R12 — Review

Brief: `docs/rounds/e01-r12-backend-config-and-migrations.md` (R1 revízió)
Diff: `git diff origin/main...codex/epic-01-round-12-backend-migrations` (`0e187ad`)
Reviewer: Claude · Dátum: 2026-07-29
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 3 · NOTE: 2

A kör azt szállította, amit a brief kért, és a kritikus állításai **viselkedési
tesztekkel** vannak bizonyítva, nem definíció-olvasással: az ORM-parity
`compare_metadata == []`, az import-mellékhatás subprocess-szel üres cwd-ben, a
SQLite cascade pedig tényleges parent-törléssel. A kör első futása helyesen
megállt egy tervezői ütközésnél (a brief R1 revíziójegyzete); a második futás a
revideált szerződés szerint dolgozott. A Codex a brief fölött egy valódi
korrektségi rést is zárt (SQLite `PRAGMA foreign_keys=ON` — enélkül a migráció
deklarált cascade-je nem viselkedés, csak szöveg).

## Acceptance criteria — tételesen

| # | Kritérium | Bizonyíték | Áll |
|---|---|---|---|
| 1 | `upgrade head` üres DB-n = ORM schema, autogenerate diff üres | `test_upgrade_head_matches_current_orm_schema`: revision == head, `compare_metadata == []` (compare_type+server_default), unique index/constraint/FK tételesen; **valódi sértéssel kipróbálva** (CASCADE→SET NULL a migrációban → a teszt PIROS, visszaállítva zöld) | ✅ |
| 2 | `downgrade -1` lefut | `test_downgrade_one_revision_removes_application_schema` + független CLI-gate ideiglenes DB-n: upgrade → downgrade → upgrade, exit 0 | ✅ |
| 3 | Prod módban `create_all` nem fut | `test_production_startup_never_calls_create_all` (monkeypatch-spy, `calls == []`) | ✅ |
| 4 | Readiness: DB nélkül 503, head-en 200, nincs URL/secret a válaszban | 4 readiness-teszt (`database_unavailable` / `migration_mismatch` / `configuration_invalid` / 200), a 503-as expliciten állítja, hogy a secret és az URL nincs a válaszban | ✅ |
| 5 | `create_app` izoláltan paraméterezhető | `test_create_app_uses_explicit_database_url_without_override` (override NÉLKÜL ír a megadott fájlba); a conftest `create_app(Settings(database_url="sqlite://"))`-ra állt át a `get_db` seam megtartásával | ✅ |
| 6 | OpenAPI contract teszt | `test_openapi_contract_is_deterministic`: title/version, teljes route-készlet, auth+settings schemák mezőszintű állításai, bearer security | ✅ |
| 7 | Nincs fájlrendszeri mellékhatás | subprocess-teszt (üres cwd, `import app.main` → nincs `.db`); függetlenül ellenőrizve: teljes 44-es suite után `backend/*.db` nem létezik | ✅ |
| 8 | **(R1)** prod+SQLite engedély nélkül boot-hiba; kwarg- és env-engedéllyel bootol | `test_prod_with_sqlite_without_explicit_permission_refuses_to_boot`, `test_prod_sqlite_permission_can_come_from_environment`, + a prefix nélküli env-név tiltása (`test_unprefixed_sqlite_permission_environment_is_ignored`) | ✅ |
| 9 | **(R1)** a többi round-120 prod-guard változatlan | diff: dev-secret, wildcard-CORS, dev-default teszt érintetlen; egyedül a `test_prod_with_real_config_boots` kapott `allow_sqlite_in_prod=True`-t (§5.8 jogcím) | ✅ |
| 10 | Mind a meglévő teszt zöld | függetlenül újrafuttatva: **44 passed** (29 régi + 15 új) | ✅ |
| 11 | `git diff --stat` csak a §4 tábláját tartalmazza | 13 fájl, mind a listán; `app/models.py`, `schemas.py`, `security.py`, `ratelimit.py`, `deps.py`, `routers/**`, `/download` érintetlen; Flutter-fa diffje **üres** | ✅ |

## Gate-bizonyíték (függetlenül újrafuttatva ezen a boxon)

| Gate | Eredmény |
|---|---|
| `.venv/bin/python -m pytest` | **44 passed** in 8.78s, exit 0 |
| `alembic upgrade head` (friss tmp DB) | exit 0, `Running upgrade -> e01_r12_0001` |
| `alembic downgrade -1` (ugyanott) | exit 0, `Running downgrade e01_r12_0001 ->` |
| ismételt `upgrade head` a downgrade után | exit 0 (a downgrade valóban visszavonható állapotot hagy) |
| ORM-parity guard valódi sértéssel | migráció `ondelete` átírva → PIROS (0.10s), visszaállítva → zöld |
| Mellékhatás-próba | teljes suite után `backend/*.db`: No such file |

## Megállapítások

### MINOR-1 — a dev `create_all` hibája néma: a flag-et semmi nem olvassa, log sincs

`app/main.py` lifespan: a dev `create_all` `SQLAlchemyError`-ja
`application.state.dev_schema_initialization_failed = True`-ba megy — ezt a
flag-et **semmi nem olvassa**, és log sem készül. Ez a projekt dokumentált „néma
elnyelés" hibaosztálya (CLAUDE.md); ráadásul ilyenkor a readiness
`migration_mismatch`-ot mond, ami a tényleges okról (DB-írási hiba) félrevezet.
Dev-only út, ezért nem MAJOR. Javasolt: a flag helyett stderr-log, és/vagy a
readiness külön ok-kódja. **Follow-up: E01-R13** (backend security & diagnostics).

### MINOR-2 — a nem stampelt dev DB readinesse tartósan 503, a README ezt nem mondja ki

A brief kötött döntéséből (nincs auto-stamp) következik és tesztelt viselkedés,
de a README „adopt it explicitly once" szövege nem mondja ki a következményt:
amíg a dev DB nincs stampelve, a `/health/ready` `503 migration_mismatch` — egy
dev-környezeti healthcheck pirosan állna. Egy mondat a README-be elég.
**Follow-up: E01-R13** (útközben úgyis README-t érint).

### MINOR-3 — a prod-SQLite tiltó teszt env-érzékeny

`test_prod_with_sqlite_without_explicit_permission_refuses_to_boot` a
környezetből épít `Settings()`-t, `monkeypatch.delenv("STRUMSIGHT_ALLOW_SQLITE")`
nélkül. A README épp azt javasolja egynode-os deployra, hogy ez az env-változó
exportálva legyen — egy ilyen boxon futtatott teszt-suite-ban ez a teszt
elhasalna. A szomszédos `test_unprefixed_...` már helyesen `delenv`-el. Egysoros
javítás. **Follow-up: E01-R13** (vagy az R15 backend-CI, ami env-mátrixot futtat).

### NOTE-1 — a readiness kérésenként olvassa az alembic script directory-t

A `/health/ready` minden hívásnál beolvassa az `alembic.ini`-t + a
`versions/` könyvtárat a head-hez. Readiness-endpointnál (ritka, orchestrátor
hívja) ez rendben van; ha valaha hot path lenne, a head cache-elhető, mert a
script directory a process élete alatt nem változik.

### NOTE-2 — `alembic` a futásidejű requirements-blokkban

Szándékos és helyes: a `main.py` a readinesshez importálja, tehát nem
dev-dependency. Következmény (ADR 0060): a **boxon futó uvicorn újraindítása
előtt `pip install -r requirements.txt` kötelező** — enélkül `ImportError`.
Ez merge utáni Claude-oldali lépés, a kör helyesen nem deployolt.

## Scope és architektúra

- 13 fájl, +1193/−34 — minden útvonal a brief §4 (R1) tábláján; a tilos zóna
  (models/schemas/security/ratelimit/routers/`/download`, Flutter-fa, ADR-ek)
  érintetlen. A `CODEX_ROUND_PROMPT.md` szándékosan untracked.
- A `deps.py`-hoz nem kellett hozzányúlni: a `get_db(request)` szignatúra a
  FastAPI dependency-mechanizmusán át kompatibilis maradt — a seam-tartó
  refaktor pontosan azt csinálta, amit a brief kért.
- Secret/URL a válaszokban: tesztelt, hogy nincs; az `alembic.ini` nem tartalmaz
  connection stringet.

## Verdikt

**APPROVED.** BLOCKER és MAJOR nincs; a három MINOR follow-upként az
E01-R13/R15-be megy (egyik sem érinti a kör helyességét ezen a boxon). A merge
az ADR 0052 zöld-kapus szabálya szerint mehet, a CI-run megvárásával.
