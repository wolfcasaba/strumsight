# ADR 0060 — Alembic mint egyetlen production schema-forrás, injektált engine-életciklus

- **Státusz:** elfogadva (2026-07-29, E01-R12)
- **Kontextus:** SDD Chapter 2, Kör 12; kör-brief `docs/rounds/e01-r12-backend-config-and-migrations.md`
  (R1 revízió); review `docs/reviews/e01-r12-review.md`
- **Kapcsolódó:** [ADR 0052](0052-ci-apk-automerge-session-per-round.md) (zöld gate),
  [ADR 0055](0055-agent-role-protocol.md) (ágensszerepek)

## Kontextus

A backend engine-je és `SessionLocal`-ja **import-időben**, module-globálisan jött
létre a `database.py`-ban, a `create_app` pedig **feltétel nélkül** futtatott
`Base.metadata.create_all`-t — production környezetben is. Ennek három mérhető
következménye volt:

1. A schema forrása az ORM futásidejű állapota volt, nem egy verziózott artefaktum:
   egy oszlop törlése vagy típusváltása production adatbázison **észrevétlen** maradt
   volna (a `create_all` létező táblát nem módosít).
2. A tesztfutásnak **fájlrendszeri mellékhatása** volt: a `from app.main import app`
   import maga hozta létre a valódi `./strumsight.db`-t, mielőtt bármelyik fixture
   in-memory engine-t injektált volna.
3. A `create_app(settings)` paramétere félig volt igaz: a settings a guardokhoz
   eljutott, az adatbázis-URL viszont nem — az mindig a module-global engine-ből jött.

Emellett egyetlen `GET /health` volt, ami se DB-t, se migrációs állapotot nem
nézett — egy futó, de üres vagy elavult schemájú service is „ok"-ot mondott.

## Döntés

1. **Alembic az egyetlen production schema-forrás.** `backend/alembic.ini` +
   `backend/alembic/` (env.py, `versions/e01_r12_0001_initial_account_schema.py`).
   Az `env.py` az app **saját `Settings`-éből** olvassa az URL-t — connection string
   nincs duplikálva az ini-ben. A kezdeti migráció ORM-parityjét nem állítás, hanem
   **teszt** bizonyítja: friss DB-n `upgrade head` után az `alembic.autogenerate`
   `compare_metadata(...) == []` (`compare_type` és `compare_server_default` bekapcsolva).
2. **`create_all` csak dev, és csak lifespanban.** Prod-ban soha (spy-teszt: nulla
   hívás). A dev helper szándékosan **nem** `alembic stamp`-el: egy rejtett írás,
   ami migrációs tulajdonjogot hamisít, rosszabb, mint egy dokumentált kézi lépés
   (README: `alembic stamp head` a meglévő dev DB átvételéhez). **Következmény,
   amit tudatosan elfogadunk:** egy nem stampelt dev adatbázison a `/health/ready`
   `503 migration_mismatch` — a dev app működik, de nem „ready". A readiness a
   deploy-kapu, nem a dev-élmény mércéje.
3. **Engine az app tulajdonában.** A `database.py` module-globáljai megszűntek;
   `create_database_engine(url)` + `create_session_factory(engine)` tiszta
   konstruktorok, a `create_app` az app `state`-jébe teszi őket, a lifespan
   `finally`-ja `dispose()`-olja. Az engine-építés **nem** nyit kapcsolatot és nem
   nyúl a schemához — ezért az `import app.main` nem hoz létre adatbázis-fájlt
   (subprocessben, üres cwd-ben mérve).
4. **A `get_db` seam megmarad**, csak a forrása változik: `request.app.state.session_factory`.
   A teljes meglévő tesztfa a `dependency_overrides[get_db]` úton izolál továbbra is —
   a refaktor nem cserélte le a tesztelési modellt.
5. **Liveness ≠ readiness.** `GET /health/live` a process életét jelzi és **nem
   nyúl az adatbázishoz**; `GET /health/ready` `SELECT 1` + `alembic current == head`
   + konfiguráció-ellenőrzés, hiba esetén **503 + stabil gépi ok-kód**
   (`database_unavailable` / `migration_mismatch` / `configuration_invalid`).
   A DB-kimaradás **readiness-hiba, nem boot-crash** — a process éljen, hogy az
   orchestrátor lássa. A régi `GET /health` **változatlanul megmarad** (a Flutter
   kliens és a box tunnel kompatibilitása).
6. **Prod + SQLite fail-closed.** `env == "prod"` és `sqlite…` URL → boot-hiba,
   kivéve az explicit `STRUMSIGHT_ALLOW_SQLITE=true` escape hatch. A flag
   `validation_alias`-szal **pontosan ezt a nevet** fogadja el; egy prefix nélküli
   `ALLOW_SQLITE_IN_PROD=true` a környezetben **nem** nyitja ki (teszt fedi) — a
   véletlen névegyezés nem lehet biztonsági kapu. Postgres-driver **nem** kerül a
   kötelező requirements-be: a box SQLite-on tesztel, a driver deploy-idejű lépés.
7. **A válasz és a log nem szivárogtat.** A readiness ok-kódok szándékosan
   üzenetmentesek; teszt állítja, hogy sem a secret, sem a database URL nem
   szerepel a válasz törzsében.
8. **SQLite-on a deklarált FK/cascade csak `PRAGMA foreign_keys=ON` mellett igaz.**
   Ezért minden SQLite kapcsolat connect-hookkal kapja meg a pragmát (app és
   Alembic online mód egyaránt). Enélkül a migráció `ON DELETE CASCADE`-je
   **dokumentáció lett volna, nem viselkedés** — a bizonyíték itt is viselkedési
   teszt (parent törlése után a `user_settings` sor tényleg eltűnik), nem a DDL
   szövegének olvasása.

## Következmények

- Schema-változás mostantól **verziózott artefaktum**; a Kör 15 backend-CI-ja
  `alembic upgrade head` gate-et tud rá építeni (`alembic` a **futásidejű**
  requirements-blokkban van, mert a readiness importálja).
- A tesztfutás fájlrendszeri mellékhatása megszűnt (subprocess-teszt őrzi).
- **Deploy-lépés lett:** a `main.py` futásidőben importál `alembic`-ot, tehát egy
  meglévő deploy-környezet (köztük a boxon futó uvicorn) `pip install -r
  requirements.txt` NÉLKÜL újraindításkor `ImportError`-ral halna el. A merge utáni
  Claude-oldali lépés ezt tartalmazza.
- Egy meglévő teszt állítása változott (`test_prod_with_real_config_boots` most
  explicit SQLite-engedéllyel bootol) — a brief **R1 revíziójának §5.8** jogcímén,
  mellé két új guard-teszt. A round-120-as prod-guardok érintetlenek.
- Nyitott adósság (a review rögzíti): a dev lifespan `create_all` hibája ma némán
  egy soha nem olvasott `state` flagbe megy, és a nem stampelt dev DB readinessének
  `migration_mismatch` oka félrevezető lehet.

## Alternatívák

- **`create_all` megtartása prodban is** — elutasítva: nem migrál, csak létrehoz,
  így egy schema-drift csendben marad.
- **Automatikus `alembic stamp head` a dev booton** — elutasítva: rejtett írás,
  ami egy nem egyező schemára hamis migrációs tulajdonjogot ad.
- **Postgres-driver a kötelező requirements-be** — elutasítva: a boxon nincs
  Postgres, a `create_engine` viszont azonnal importálja a DBAPI-t, tehát a driver
  jelenléte tesztet nem javít, csak telepítést nehezít.
- **A `get_db` seam elhagyása (session a state-ből közvetlenül)** — elutasítva:
  a teljes meglévő tesztfa erre a seamre épül, cseréje a kör hasznos részét
  elmosta volna.
