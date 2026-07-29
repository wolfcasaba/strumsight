# E01-R12 — Backend konfiguráció és adatbázis-migráció

Státusz: PLANNING (pre-flight elvégezve 2026-07-29, kód újraolvasva: `main` @ `2bbcec5`)
SDD: docs/sdd/02-epic-01-core-platform.md § „Kör 12 — Backend konfiguráció és adatbázis-migráció"
Branch: `codex/epic-01-round-12-backend-migrations`
Brief szerzője: Claude · Implementáció: Codex

> ✅ **Pre-flight (Claude, 2026-07-29, `main` @ `2bbcec5` = E01-R11 merge után).**
> A `backend/app/{config,database,main,deps}.py` és a `backend/tests/conftest.py`
> újraolvasva: **nincs drift** — a 2. szekció minden állítása ma is igaz (az R11
> routing-kör tényleg nem nyúlt a backendhez). Amit a pre-flight ÚJONNAN mért, és
> ami kötelezően beépült a briefbe: a teszt-környezet a `backend/.venv` (a boxon
> **nincs `python` binary**, csak `python3` — a `python -m pytest` NEM fut le), az
> **alembic nincs telepítve** a venvbe (pip elérés ellenőrizve: `alembic 1.18.5`
> letölthető), és a mért baseline **29 passed** (`.venv/bin/python -m pytest -q`,
> exit 0). Lásd a 2. és 7. szekciót.

> 🔁 **R1 REVÍZIÓ (2026-07-29, a Codex első futásának `stopped` jelzése után).**
> A Codex az implementáció megkezdése ELŐTT megállt, helyesen: a brief §5.5
> (prod + SQLite → boot-hiba) közvetlenül ellentmond a meglévő
> `backend/tests/test_hardening.py::TestProdBootGuards::test_prod_with_real_config_boots`
> tesztnek, ami `env="prod"` + valódi secret + explicit CORS mellett — de a
> **default `sqlite:///./strumsight.db` URL-lel** — sikeres bootot állít; a §4-es
> fájllista pedig a `test_*.py` átírását csak a `create_app`-szignatúraváltás
> jogcímén engedte, ez pedig nem az. **A hiba az enyém (tervezői), nem
> implementációs:** viselkedésváltozást írtam elő úgy, hogy az azt rögzítő
> tesztet lezártam (ugyanaz az osztály, mint az E01-R11-ben). A feloldás a
> §5.8-as új kötött döntés + a §4 kiegészített sora + a §6 két új kritériuma.
> Az ütközés hatóköre mérve: `env="prod"`-ot a tesztfában CSAK ez a három
> hardening-teszt használ, és ebből egyedül ez a **sikeres-boot** eset ütközik.

## 1. Cél

A FastAPI backend ma import-időben, globálisan hozza létre a database engine-t, és a
`create_app` **feltétel nélkül** futtat `Base.metadata.create_all`-t — production
környezetben is. A kör kimenete: **Alembic** mint a production schema egyetlen
forrása, **injektálható engine-életciklus** (`create_app(settings)` tesztelhető
paraméterezéssel), **liveness/readiness endpointok** és **OpenAPI contract teszt**.
Azért most, mert a Kör 13 (security-elkülönítés) és a Kör 15 (backend CI, benne
`alembic upgrade head` gate) erre az alapra épül.

## 2. Jelenlegi állapot

Ténylegesen elolvasott kód (`backend/`, 2026-07-29):

- **`app/config.py`** — pydantic-settings, `STRUMSIGHT_` env-prefix, `env: "dev"`
  default; `database_url: "sqlite:///./strumsight.db"`; `get_settings()` `lru_cache`-elt.
- **`app/database.py`** — az **engine és a `SessionLocal` IMPORT-IDŐBEN** jön létre
  a module-szintű `get_settings()`-ből; a `Base` és a `get_db` is itt. Pontosan az,
  amit a §12.3 megszüntetni rendel.
- **`app/main.py`** — `create_app(settings=None)`: `_guard_prod` már létezik (prod:
  dev-secret és wildcard-CORS boot-hiba — round 120, **ez kész, nem e kör dolga**);
  utána `Base.metadata.create_all(bind=engine)` **feltétel nélkül** (§12.2 sértése);
  egyetlen `GET /health` (status+version) — nincs live/ready szétválasztás;
  `GET /download` (APK-kiszolgálás) — **a Kör 13 területe, ebben a körben tilos hozzányúlni**.
- **`app/deps.py`** — `get_current_user` a module-global `get_db`-re épül; a
  `get_db` a tesztek override-seamje.
- **`tests/conftest.py`** — a `get_db`-t in-memory StaticPool engine-nel írja felül,
  de az `from app.main import app` import mellékhatásként a VALÓDI engine-en is
  lefuttatja a `create_all`-t (`./strumsight.db` fájl keletkezik) — a tesztfutásnak
  ma fájlrendszeri mellékhatása van.
- **Alembic sehol nincs**: se `alembic.ini`, se migrációs könyvtár; a
  `requirements.txt`-ben nincs `alembic` és nincs Postgres-driver. A `backend/.venv`-be
  sincs telepítve (`import alembic` → `ModuleNotFoundError`).
- **Teszt-környezet (pre-flight mérés):** a virtualenv a `backend/.venv`; ezen a boxon
  **nincs `python` binary** (`which python` → semmi), ezért minden backend-parancs
  `.venv/bin/python -m …` alakban fut. `pytest.ini`: `pythonpath = .`, `testpaths = tests`.
- **Baseline (ma mérve, nem átvéve):** `.venv/bin/python -m pytest -q` → **29 passed**,
  exit 0.
- **`backend/strumsight.db`** létezik a munkapéldányban (a mai import-mellékhatás
  terméke); a `backend/.gitignore` `*.db` sora miatt nincs verziókövetve — a §6-os
  „nincs fájlrendszeri mellékhatás" kritérium tehát **nem** git-státusszal, hanem a
  fájl tényleges létrejöttével bizonyítandó (töröld, futtass tesztet, nézd meg,
  visszakeletkezik-e).

## 3. Scope

**Benne:**

- `backend/alembic.ini` + `backend/alembic/` — az `env.py` az app `Settings`-éből
  olvassa az URL-t (nem duplikált connection string).
- Kezdeti migráció: `users` + `user_settings` a MAI ORM-mal egyező schemával
  (email unique+index, FK `ondelete=CASCADE`, `user_settings.user_id` unique,
  timezone-os timestampek).
- `database.py` refaktor: az engine/`SessionLocal` a `create_app`-ban jön létre a
  kapott `Settings`-ből; module-szintű engine megszűnik; a `get_db` seam megmarad.
- `create_all` csak `env != "prod"` esetén (explicit dev-helper); prod-ban a
  schemát kizárólag migráció hozhatja létre.
- `GET /health/live` + `GET /health/ready` (ready: DB elérhető + alembic-verzió
  kompatibilis + konfiguráció érvényes; hiba → 503). A meglévő `/health` megmarad.
- Prod + SQLite: explicit engedély nélkül boot-hiba; Postgres dokumentálva.
- OpenAPI contract/snapshot teszt (title, version, route-készlet, lényeges schemák).
- `tests/test_migrations.py` + a §„Kötelező backend tesztek" teljes listája.

**Kívül (ebben a körben TILOS):**

- Diagnostics router, token, upload-limit, `/download` — mind Kör 13.
- Ruff, backend CI workflow — Kör 15. (A kör verifikációja pytest, nem CI.)
- Redis / többprocesszes skálázás; tényleges Postgres-üzembe helyezés.
- Bármi a Flutter-fa alatt (`lib/`, `test/`, `tool/`, `pubspec.yaml`).
- `app/models.py`, `app/schemas.py`, `app/security.py`, `app/ratelimit.py`,
  `app/routers/**` érdemi módosítása (importsor-igazítás megengedett, ha a
  `database.py` refaktor kényszeríti — semmi több).

## 4. Engedélyezett fájlok

Csak az alábbi útvonalak módosíthatók. Bármi más → **MEGÁLLÁS és jelentés**.

| Útvonal | Miért |
|---|---|
| `backend/alembic.ini` | ÚJ — Alembic konfiguráció |
| `backend/alembic/**` | ÚJ — env.py + versions/ (kezdeti migráció) |
| `backend/app/database.py` | engine-életciklus refaktor |
| `backend/app/config.py` | `allow_sqlite_in_prod` jellegű flag + readiness-hez kellő mezők |
| `backend/app/main.py` | create_all feltételessé tétele, health/live+ready, engine-injektálás |
| `backend/app/deps.py` | csak ha a session-injektálás megköveteli |
| `backend/app/routers/*.py` | CSAK importsor, ha a refaktor kényszeríti |
| `backend/tests/test_migrations.py` | ÚJ — migrációs tesztek |
| `backend/tests/conftest.py` | átállás a paraméterezett `create_app`-ra |
| `backend/tests/test_hardening.py` | **R1:** a `test_prod_with_real_config_boots` átírása + a §5.8 szerinti ÚJ tesztek. Az osztály többi tesztjéhez (dev-secret, wildcard-CORS, dev-default boot, rate limiter) NEM nyúlsz |
| `backend/tests/test_*.py` | egyebekben csak amennyit a `create_app` szignatúraváltása kényszerít |
| `backend/requirements.txt` | `alembic` felvétele |
| `backend/README.md` | migráció futtatása, prod-DB szabályok |
| `docs/rounds/e01-r12-backend-config-and-migrations.md` | **csak a 10. szekció** |

**Tilos zóna:** a repó minden más része — kiemelten `lib/**`, `test/**`, `tool/**`,
`.github/**`, `docs/**` (a fenti egy fájl §10-én kívül), `HANDOFF.md`, ADR-ek
(az ADR-t Claude írja).

Ha egy meglévő backend-teszt a változástól elbukik: **NE írd át a zöldért** — állj
meg és jelentsd, kivéve ahol az átírás oka pont a brief-ben előírt szignatúraváltás
(azt a §10-ben tételesen fel kell sorolni).

## 5. Kötött architekturális döntések

Előre kiosztott ADR-szám: **`0060`** — az ADR-t Claude írja, a Codex ne hozzon
létre `docs/adr/` fájlt.

1. **Alembic az egyetlen prod schema-forrás.** A kezdeti migráció autogenerate-tel
   készülhet, de kézzel ellenőrizve: az eredménynek a mai ORM-definícióval
   **üres autogenerate-diffet** kell adnia.
2. **Meglévő dev adatbázis átvétele explicit.** A `create_all`-lal létrejött dev DB
   `alembic stamp head`-del vehető át — dokumentált kézi lépés a README-ben; a
   backend NEM stampel automatikusan (rejtett írás tilos).
3. **Engine a `create_app`-ban.** `create_app(settings)` hozza létre az engine-t és
   a session factory-t a kapott Settings-ből; import-time engine nem maradhat.
   A tesztek továbbra is a `get_db` dependency-override-on izolálnak — a seam
   nem szűnhet meg.
4. **`/health` megmarad** (kliens/box-kompatibilitás), mellé jön a
   `/health/live` (process él, DB-t nem érint) és `/health/ready` (DB `SELECT 1`
   + `alembic current == head` + config érvényes; bármelyik hibája → 503 + gépi ok-kód).
5. **Fail-closed prod-DB szabály:** `env == "prod"` és SQLite URL → boot-hiba,
   kivéve explicit `STRUMSIGHT_ALLOW_SQLITE=true`. Postgres-driver NEM kerül a
   kötelező requirements-be (a box SQLite-on teszteli; a driver telepítése deploy-idejű,
   dokumentált lépés).
6. **Readiness ≠ boot-crash.** DB-kapcsolati hiba readiness-failure (503), nem
   process-halál — a liveness közben éljen.
7. **Secret és database URL sosem kerül logba vagy health-válaszba.**
8. **(R1) A prod-SQLite szabály és a meglévő „prod bootol" teszt feloldása.**
   A `test_prod_with_real_config_boots` ma azt rögzíti, hogy *egy helyesen
   konfigurált prod app elindul* — ez a szándék **érvényes marad**, csak a
   „helyesen konfigurált" definíciója bővül a §5.5-tel. Ezért:
   - a meglévő teszt **átírandó** úgy, hogy a prod Settings az explicit
     `allow_sqlite_in_prod=True` engedéllyel (a §5.5 escape hatch) bootoljon —
     így továbbra is a **sikeres prod-boot** útját fedi;
   - **ÚJ teszt**: `env="prod"` + valódi secret + explicit CORS + SQLite URL,
     engedély NÉLKÜL → `RuntimeError` (a §5.5 tilalma);
   - **ÚJ teszt**: a §5.5 engedélye a `STRUMSIGHT_ALLOW_SQLITE` env-változóból is
     jön (a `Settings` `STRUMSIGHT_` prefixén keresztül) — ne csak a kwarg-út legyen fedve.
   - **NEM megoldás** Postgres URL-t adni a tesztnek: a `create_engine` a DBAPI-t
     azonnal importálja, a driver pedig szándékosan nincs a requirements-ben (§5.5)
     — a teszt `ModuleNotFoundError`-ral halna el.
   Az átírás **jogcíme ez a pont**; a §10-ben tételesen fel kell sorolni.

## 6. Acceptance criteria

- [ ] Üres adatbázison `alembic upgrade head` → a schema egyezik az ORM-mal
      (autogenerate diff üres — teszt bizonyítja).
- [ ] `alembic downgrade -1` lefut (legalább egy lépés vissza).
- [ ] Prod módban (`env=prod` settings-szel épített app) `create_all` **nem** fut —
      teszt bizonyítja (pl. monkeypatch-számlálóval vagy tábla-hiánnyal).
- [ ] Readiness DB nélkül → 503; DB-vel + head-en → 200; a válasz nem tartalmaz
      URL-t/secretet.
- [ ] `create_app` izoláltan tesztelhető: settings + database URL + dependency
      override paraméterezéssel (a conftest már így épít).
- [ ] OpenAPI contract teszt: title/version/route-készlet + auth és settings
      schemák lényegi mezői rögzítve.
- [ ] A tesztfutásnak nincs fájlrendszeri mellékhatása (nem keletkezik
      `strumsight.db` a repo-gyökérben import-mellékhatásból).
- [ ] **(R1)** Prod + SQLite engedély nélkül → boot-hiba; `allow_sqlite_in_prod=True`
      mellett → bootol; az engedély env-változóból (`STRUMSIGHT_ALLOW_SQLITE`) is hat.
- [ ] **(R1)** A `TestProdBootGuards` többi tesztje (dev-secret, wildcard-CORS,
      dev-default boot) **változatlanul** zöld — a §5.5 nem lazíthatja a round-120-as
      guardokat, és a dev út továbbra is nulla setuppal indul.
- [ ] Mind a 29 meglévő backend-teszt zöld (átírás csak a §4-ben / §5.8-ban engedett okból).
- [ ] `git diff --stat main...` kizárólag a 4. szekció tábláját tartalmazza.

## 7. Kötelező ellenőrzések

Külön parancsokként (`AGENTS.md` §12):

```bash
cd backend
.venv/bin/pip install alembic                 # a venvbe; a requirements.txt-be is felveendő
.venv/bin/python -m pytest -q
.venv/bin/python -m alembic upgrade head      # friss, ideiglenes DB-re mutató URL-lel
.venv/bin/python -m alembic downgrade -1
```

**Nincs `python` binary a boxon** — a `python -m …` alak `command not found`-dal
hal el; mindig a `.venv/bin/python`-t hívd.

A Flutter-fa diffje üres kell legyen; a zöld gate-hez a Claude-oldal a szokásos
`gh workflow run build-apk.yml --ref codex/epic-01-round-12-backend-migrations`
dispatch-et is lefuttatja (ADR 0052 — a Codex ne hívjon `gh`-t).

## 8. Implementációs sorrend

1. `database.py` + `create_app(settings)` refaktor (engine-injektálás) — a meglévő
   29 teszt zölden tartásával.
2. `conftest.py` átállás a paraméterezett appra; a fájl-mellékhatás megszüntetése.
3. Alembic bevezetése: `alembic.ini`, `env.py` a Settings-ből, kezdeti migráció;
   üres-diff ellenőrzés.
4. `create_all` feltételessé tétele + prod-SQLite szabály a configban.
5. `/health/live` + `/health/ready`.
6. `tests/test_migrations.py` + readiness/contract tesztek.
7. README (migráció futtatása, dev-DB stamp, prod szabályok) → §10 kitöltése.

## 9. Kockázatok

- **Import-graph.** A `database.py` module-globáljaira a `deps.py`, a routerek és
  mind a 4 tesztfájl épít — a refaktor sorrendje: előbb seam-tartó átállás, utána
  Alembic. Egy lépésben mindent átírni = piros erdő.
- **`get_settings()` `lru_cache`.** Tesztben környezet-alapú Settings-váltásnál a
  cache-t üríteni kell — ne rejtett env-mutációval, hanem explicit
  `create_app(settings=...)` paraméterrel dolgozz.
- **SQLite ALTER-korlátok.** A downgrade SQLite-on batch-mode-ot igényelhet
  (`render_as_batch`) — az env.py-ban be kell kapcsolni, különben a downgrade-teszt
  csak Postgresen menne.
- **A box élő szolgáltatása.** A boxon fut egy uvicorn (:8019, diagnosztika-tunnel).
  A kör NEM deployol — a futó szolgáltatás újraindítása Claude-oldali, kör utáni lépés.
- **Az alembic telepítése ≠ a requirements frissítése.** A `.venv/bin/pip install alembic`
  csak a te futásodat teszi zölddé; ha a `requirements.txt`-be nem kerül be a pin
  (a többi sorral azonos `>=x,<y` stílusban), a Kör 15 backend-CI-ja az első futáson
  elhasal — és az a hiba nem a te futásodban látszik.
- **A downgrade-teszt ideiglenes DB-t kíván.** Ne a `backend/strumsight.db`-n
  migrálj/downgrade-elj (az a box dev-adatbázisa) — `tmp_path`-ba mutató
  `sqlite:///…` URL-lel dolgozz.

## 10. Implementation handoff — a Codex tölti ki

### Összefoglaló fájlonként

- `backend/alembic.ini`: helyfüggetlen Alembic script-path és secretmentes
  logging-konfiguráció; database URL nincs duplikálva.
- `backend/alembic/env.py`: közvetlen `Settings()`-ből olvassa a database URL-t,
  explicit betölti az ORM metadata-t, online/offline módban type/default
  összevetést és SQLite batch-renderelést használ; az online SQLite
  kapcsolatain az FK enforcement is aktív.
- `backend/alembic/script.py.mako`: a későbbi verziózott revisionök sablonja.
- `backend/alembic/versions/e01_r12_0001_initial_account_schema.py`: kezdeti
  `users` + `user_settings` schema, unique email-index, `user_id` unique
  constraint, `ON DELETE CASCADE` FK és timezone-os timestamp deklarációk;
  fordított sorrendű downgrade.
- `backend/app/database.py`: megszűnt a module-global engine és `SessionLocal`;
  tiszta engine/session-factory konstruktorok készültek, a kanonikus `get_db`
  seam az aktuális FastAPI app state-jéből nyit és minden úton zár sessiont.
  Minden SQLite kapcsolat connect-hookkal `PRAGMA foreign_keys=ON` állapotban
  indul, így a deklarált cascade ténylegesen érvényesül.
- `backend/app/config.py`: `allow_sqlite_in_prod` flag; a kwarg mellett az
  explicit `STRUMSIGHT_ALLOW_SQLITE` env-nevet is elfogadja, prefix nélküli
  környezeti változó viszont nem nyithatja az escape hatch-et.
- `backend/app/main.py`: a guard után apponként épül engine + session factory;
  dev `create_all` csak lifespanban fut, prod-ban soha, shutdownkor az engine
  dispose-olódik. Új `/health/live` és sanitizált `/health/ready` contract
  (`SELECT 1`, Alembic current/head, config guard).
- `backend/tests/conftest.py`: tesztenként paraméterezett `create_app(Settings(
  database_url="sqlite://"))`, a meglévő `get_db` override-seam megtartásával;
  a fixture-engine FK enforcementtel fut és teardownkor dispose-olódik.
- `backend/tests/test_migrations.py`: 13 új
  lifecycle/migráció/readiness/OpenAPI/config teszt, köztük ORM-parity,
  upgrade/downgrade, viselkedési SQLite cascade, prod `create_all`-tilalom,
  import-mellékhatás, prefix nélküli escape-hatch tiltás,
  DB-hiba/migration-mismatch/head readiness és auth/settings schema-contract.
- `backend/tests/test_hardening.py`: az R1 §5.8 szerinti egy meglévő teszt
  pontosítása és két új prod-SQLite guard teszt.
- `backend/requirements.txt`: `alembic>=1.18,<1.19`.
- `backend/README.md`: upgrade/current/downgrade és explicit dev-DB stamp
  workflow, prod PostgreSQL/driver szabály, SQLite escape hatch és health API.

### Futtatott parancsok és tényleges eredmények

- Seam-refaktor utáni meglévő-suite checkpoint:
  `.venv/bin/python -m pytest -q tests/test_auth.py tests/test_settings.py
  tests/test_diagnostics.py tests/test_hardening.py` →
  `............................. [100%]` (**29 passed**, exit 0).
- TDD RED bizonyítékok:
  - import-regresszió: az új teszt először bukott, mert
    `tmp_path/strumsight.db.exists()` `True` volt;
  - prod SQLite tiltás: először `Failed: DID NOT RAISE RuntimeError`;
  - `/health/live`: először `404`, nem a várt `200`;
  - config namespace: a prefix nélküli `ALLOW_SQLITE_IN_PROD=true` tesztje
    először `assert True is False` eredménnyel bukott;
  - SQLite cascade: friss migrált DB-n először
    `PRAGMA foreign_keys == 0` (várt: 1), és kézi reprodukcióban a parent
    törlése után `children_after_delete 1` maradt;
  - az első ready-route regisztráció a FastAPI által jelzett érvénytelen
    `dict | JSONResponse` response-fielddel állt meg; az explicit
    `response_model=None` javítás után ugyanaz az 5 health/startup teszt
    `..... [100%]` lett.
- Új R12 tesztfájl:
  `.venv/bin/python -m pytest -q tests/test_migrations.py` →
  `............. [100%]` (**13 passed**, exit 0).
- Végső teljes backend gate (a default DB eltávolítása, a config-namespace
  szigorítása és az SQLite FK enforcement után):
  `.venv/bin/python -m pytest -q` →
  `............................................ [100%]`
  (**44 passed**, exit 0). Korábban három 42 tesztes és egy 43 tesztes teljes
  gate is exit 0-val futott.
- Friss ideiglenes DB:
  `STRUMSIGHT_DATABASE_URL=sqlite:////tmp/strumsight-r12-fk-gate.HHLuZf/gate.db
  .venv/bin/python -m alembic upgrade head` → exit 0,
  `Running upgrade -> e01_r12_0001`.
- Ugyanazon ideiglenes DB:
  `STRUMSIGHT_DATABASE_URL=sqlite:////tmp/strumsight-r12-fk-gate.HHLuZf/gate.db
  .venv/bin/python -m alembic downgrade -1` → exit 0,
  `Running downgrade e01_r12_0001 ->`.
- Fájlrendszeri mellékhatás külön bizonyítéka: a meglévő
  `backend/strumsight.db` eltávolítása után két 42 tesztes, egy 43 tesztes és a
  végső 44 tesztes teljes suite is futott; utána
  `.venv/bin/python -c ...Path("strumsight.db").exists()` →
  `strumsight.db: exists=False`. A fájl biztonsági mentése ideiglenesen:
  `/tmp/strumsight-r12-db-backup.2ixrDh/strumsight.db`.
- `.venv/bin/python -m pip check` → `No broken requirements found.` (exit 0).
- `git diff --check` → üres kimenet, exit 0.
- Flutter-scope audit:
  `git status --short -- lib test tool pubspec.yaml` → üres kimenet.
- Secret-marker audit a backend diffen → nincs találat (az `rg` exit 1-e itt
  „nincs egyezés”).

### Acceptance criteria

- Az üres DB upgrade-je és az ORM-mal üres autogenerate-diff tesztelt; a teszt
  külön ellenőrzi a revision headet, a unique indexet/constraintet és a cascade
  FK-t. Külön viselkedési teszt igazolja, hogy runtime SQLite-on a parent
  törlése ténylegesen cascade-eli a `user_settings` sort.
- A `downgrade -1` tesztben és külön CLI-gate-ben is lefutott.
- Prod lifespanban a `create_all` spy hívásszáma nulla.
- Readiness: elérhetetlen DB → sanitizált 503; unstamped DB → 503
  `migration_mismatch`; migrált head → 200; liveness DB-kapcsolat nélkül 200.
- Explicit Settings/database URL működik dependency override nélkül is; a teljes
  régi suite a megtartott `get_db` override-on fut.
- OpenAPI title/version, teljes üzleti route-készlet, auth/settings request és
  response refek, bearer security és lényeges mezőkorlátok rögzítve.
- Import és teljes tesztfutás után sem keletkezik default `strumsight.db`.
- Prod SQLite engedély nélkül boot-hiba; kwarg- és env-engedéllyel bootol.
- A 29 meglévő teszt checkpointja és a végső 44 tesztes teljes suite zöld.
- A módosított/új fájlok mind a brief §4 engedélyezett listáján vannak; a
  Flutter-fa diffje üres.

### Eltérések, átírt meglévő tesztek

- Funkcionális eltérés a briefhez képest nincs. A dev `create_all` lifespanba
  került (nem közvetlen factory-hívásba), mert csak így marad meg egyszerre a
  zero-setup dev helper és az import-időbeli fájlmellékhatás tilalma.
- A kért törlés visszaállítható módon történt: a gitignore-olt dev DB nincs a
  backendben és nem keletkezett újra, de a fenti `/tmp` backupból a box
  újraindításáig visszaállítható.
- Egyetlen meglévő teszt lett átírva:
  `TestProdBootGuards::test_prod_with_real_config_boots` — hozzáadott
  `allow_sqlite_in_prod=True`; jogcím: brief **§5.8**. Ugyanitt a §5.8 által
  előírt két új teszt készült (engedély nélküli boot-hiba; env-flag).
- Más meglévő teszt állítása nem változott. A `conftest.py` fixture-átállítása a
  brief §4-ben engedett `create_app`/dependency-injection refaktor.

### Nem futtatott ellenőrzések és follow-upok

- Flutter format/analyze/test és lokális APK-build nem futott: a Flutter-fa
  érintetlen, a brief ezt kifejezetten nem kéri; APK-build amúgy is CI-only.
- CI-dispatch, `gh`, PR, merge és deploy nem futott: Claude-oldali feladat.
- PostgreSQL integration nem futott: a driver a brief szerint szándékosan nincs
  a kötelező requirements-ben; deploykor kompatibilis Psycopg driver és valódi
  Postgres smoke-test kell.
- Claude follow-up: ADR 0060, CI/PR/review/merge, HANDOFF/RTM és a merge utáni
  független gate-ek. A repó tanulságlogjába érdemes felvenni: SQLite-on a
  deklarált FK/cascade csak minden kapcsolatra kiadott
  `PRAGMA foreign_keys=ON` mellett működik. Ismert implementációs blocker nincs.

## 11. Review — a Claude tölti ki

Link: `docs/reviews/e01-r12-review.md`
