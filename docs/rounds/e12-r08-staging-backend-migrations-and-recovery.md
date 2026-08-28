# E12-R08 — Staging backend, migrations és recovery alap

- **Státusz:** AKTÍV — pre-flight elvégezve 2026-08-28 (`main @ 686bc260`), §0.0 revízióval
  (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 8
- **Kör-azonosító:** `E12-R08`
- **Branch:** `<motor>/e12-r08-staging-backend-migrations-and-recovery`
- **Előfeltétel:** `E12-R04` merge-elve (a zárt `env` értékkészlet és a staging fogalma onnan jön)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0449` — a szám FOGLALT (Chapter 12 batch-tartomány).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "backend staging deploy docker alembic migration readiness backup restore"` → **[ADR 0060](../adr/0060-alembic-schema-source-and-injected-engine-lifecycle.md)** (score 3.00): az Alembic az EGYETLEN production séma-forrás, az engine-életciklus injektált. A readiness-gate és a migration-before-start ezt a döntést KÖVETI — `create_all` bevezetése tilos.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** számold újra a `backend/alembic/versions/` migrációit (a megíráskor **21**, `e01_r12_0001` … `e09_r27_0020`) és olvasd el a `backend/app/main.py` jelenlegi indulási/health útvonalait. A `backend/README.md` futtatási parancsait a §7 a MÉRT alakban idézze.

## 0.0 Pre-flight revízió (Claude, 2026-08-28, `main @ 686bc260`) — KÖTELEZŐ OLVASNI

A pre-flight mérése négy ponton írja felül a PREPARED brief szövegét. A
revíziók az **[ADR 0449](../adr/0449-staging-readiness-traffic-gate-and-recovery.md)**-ben
vannak megindokolva; az alábbi §5–§8 szakaszok MÁR a revideált alakot
tartalmazzák.

**R1 — `/readyz` NEM jön létre; a readiness a meglévő `/health/ready`.**
A migrációs fejre mérő readiness MÁR implementált (`main.py::_readiness_failure`,
70–102. sor: `MigrationContext.get_current_heads()` ≠ `ScriptDirectory.get_heads()`
→ 503 `migration_mismatch`), és a `backend/tests/test_migrations.py::test_openapi_contract_is_deterministic`
(362–378. sor) a nyitott útvonalak halmazát **egyenlőségre** méri — egy új
`/readyz` út ezt a tilos zónában élő, átírni tilos cellát pirosra váltaná
(A7-sértés). Ahol a brief `/readyz`-t mond, ott a `/health/ready` értendő.

**R2 — A kör ÚJ tartalma a forgalmi kapu, nem a readiness-végpont.**
A `/settings` és az `/auth/*` ma **akkor is kiszolgál**, ha a readiness
`migration_mismatch`-et adna — ennek nincs gépi őre. Ezt a kaput építi a kör
(ADR 0449 D1). Az A1/A2 cellái ezt mérik, nem a már meglévő és már tesztelt
readiness-választ (annak őrei: `test_migrations.py:301–360`, azok
**változatlanul** maradnak).

**R3 — A kapu `env ∈ {staging, prod}` alatt aktív, `dev`/`lab` alatt nem.**
Mért ok: a `backend/tests/conftest.py` `client` fixture-je in-memory SQLite-on
`Base.metadata.create_all`-lal áll fel, `alembic stamp` NÉLKÜL — a fej ott
ELVÁRTAN üres, tehát egy környezet-független kapu a ~20 meglévő auth/settings
cellát elbuktatná (A7-sértés). Ez az ADR 0060 tükre, nem gyengítés
(ADR 0449 D1).

**R4 — Az A5 a betöltésre és a profil-mintára mér, nem „production-jelölésű
titokra".** Az [ADR 0445](../adr/0445-environment-value-set-and-staging-isolation.md)
kimondja: „egy backend nem tudja megállapítani, hogy egy kapott titok »a
production titka«-e". Az eldönthető mérce (ADR 0449 D6): (a) a
`staging.env.example` egyetlen titok-jellegű kulcshoz sem rendel valódi értéket,
és (b) a staging profil a dev-alapértelmezésű `secret_key`-jel példányosítási
hibát ad — a MEGLÉVŐ `Settings._guard_staging` őrén (`config.py:153–184`), amit a
kör **használ**, nem ír át (tilos zóna).

**Visszakeresés (ADR 0312).** `--corpus lessons,halts,adr`: **ADR 0060** (score
3.00, `bm25#1 emb#1`) — Alembic az egyetlen séma-forrás, `create_all` csak dev;
**ADR 0445** (score 2.25) — zárt `env` értékkészlet és a nem-eldönthető
titok-provenancia. A `lessons,halts` korpusz a mentés/visszaállítás útra
**nem adott releváns előzményt** (a találatok — L455, L459, L391 — a
`safe-force-push`/rebase osztályról szólnak, nem a restore-ról).

## 0.0.1 Mit jelent itt a „staging deploy"

Ezen a boxon nincs futó staging infrastruktúra. A kör TERMÉKE a reprodukálható artefaktum és a bizonyíthatóan működő eljárás: Dockerfile, deploy-leírók, migration-before-start readiness gate, backup/restore script és a hozzájuk tartozó, LOKÁLISAN futtatható pytest-cellák (SQLite/ideiglenes DB felett). A valódi felhő-deploy operátori (user-) lépés, és a §6 egyik cellája sem függ tőle.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/Dockerfile",
  "backend/deploy/staging.env.example",
  "backend/deploy/README.md",
  "backend/app/main.py",
  "backend/scripts/backup.py",
  "backend/scripts/restore.py",
  "backend/tests/test_readiness_and_recovery.py",
  "docs/operations/backend-deploy.md",
  "docs/operations/database-recovery.md",
  "docs/rounds/e12-r08-staging-backend-migrations-and-recovery.md",
]
gate_tests = [
  "test/app/config/feature_flags_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a diff az adatbázis-migráció és a mentés/visszaállítás útját érinti — egy hibás restore-script felhasználói adatot semmisíthet meg, egy hiányos readiness-gate pedig migrálatlan sémán indítaná a szolgáltatást. A `security-reviewer` futtatása a review-ban KÖTELEZŐ.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

A kör-jelzés KÖTELEZŐ: a munka végén (vagy elakadáskor) pontosan egy terminális
jelzés megy ki. A **§8 a terved** — nincs külön task-lista. Doc-commentben csak
tesztben bizonyított állítás szerepeljen.

**STOP-protokoll (`stopped` jelzés + jelentés, brief-revíziót kérve):** ha a
munkához ÚJ Alembic migráció, a `backend/app/models.py`, a
`backend/app/config.py`, a `backend/app/routers/**`, a `backend/app/database.py`,
a `backend/requirements*.txt` vagy BÁRMELY meglévő backend-teszt módosítása
kellene. Ez a kör séma-változást NEM hoz, és meglévő tesztet NEM ír át. Ha a
forgalmi kapu a §4 engedélyezett listáján belül nem építhető meg, az is `stopped`
— nem listatágítás.

## 1. Cél

Production-szerű staging: reprodukálható konténer-build, migráció-vezérelt indulás, bizonyított mentés/visszaállítás és dokumentált rollback.

## 2. Jelenlegi állapot — mért tények

Mind ÚJRAMÉRVE a pre-flightban (`main @ 686bc260`):

- `backend/Dockerfile`, `backend/deploy/` és `backend/scripts/` **nem létezik**; a futtatás ma közvetlen `uvicorn` a `backend/README.md` szerint.
- `backend/alembic/versions/`: **21** migráció (`ls *.py | wc -l` = 21), lineáris lánc (`e01_r12_0001` → `e09_r27_0020`). ADR 0060: az Alembic az egyetlen séma-forrás.
- `backend/app/config.py`: `database_url` alapértelmezés `sqlite:///./strumsight.db`, `allow_sqlite_in_prod` flag létezik, és a **staging fail-closed őre** (`_guard_staging`, 153–184. sor) példányosításkor tüzel. **Tilos zóna.**
- **`backend/app/main.py::_readiness_failure` MÁR a migrációs fejre mér** (70–102. sor) és a `/health/ready` (189–202. sor) 503-at ad `migration_mismatch` okkal. A hiányzó darab a **forgalmi kapu** (§0.0 R2).
- A lifespan `create_all`-ja `env != "prod"` alatt fut (`main.py:105–117`) — dev-kényelem, ADR 0060 szerint.
- `backend/tests/test_migrations.py` **létezik** — a migrációs lánc, a `create_all`-tilalom, a readiness-válaszok (301–360. sor) és a **determinisztikus OpenAPI-útvonalhalmaz** (362–378. sor) regresszió-őre; **átírása a zöldért TILOS**.
- `backend/tests/conftest.py` `client` fixture-je `create_all`-lal, `alembic stamp` NÉLKÜL áll fel (§0.0 R3).
- `docs/operations/` MA egyetlen fájlt tartalmaz: `community-moderation-runbook.md`.
- A `tools/round-gate.sh` ismer backend-sávot (247–255. sor): ha a diff a `backend/`-hez ér, magától futtat `ruff format --check`, `ruff check` és **teljes** `pytest -q` lépést — a Python-cellák tehát a gate artefaktumon belül futnak.
- A registry elérhető: a `python:3.12-slim` `docker-content-digest`-je 2026-08-28-án `sha256:09f7da3bc104798d0afb40bc08d23ab2da20a76130cec1f2ef170848f5d85217`.

## 3. Scope

**Benne van:** `backend/Dockerfile` (digestre pinelt base image, nem-root user, determinisztikus `requirements` telepítés) · `backend/deploy/staging.env.example` + `deploy/README.md` (külön DB és media-cél; a mintában titok-érték TILOS) · **readiness-vezérelt forgalmi kapu** a `main.py`-ban: `env ∈ {staging, prod}` alatt migrálatlan sémán az üzleti végpontok 503 `not_ready` választ adnak és a kezelő nem fut le, míg a `/health`, `/health/live`, `/health/ready` elérhető marad (ADR 0449 D1–D3) · `backend/scripts/backup.py` és `restore.py` (konzisztens dump a migrációs fejjel + visszatöltés friss adatbázisba, ellenőrző összesítéssel, kettős megerősítésű felülírás) · `backend/tests/test_readiness_and_recovery.py` · `docs/operations/backend-deploy.md` (deploy, rollback, secret-rotáció lépések) és `docs/operations/database-recovery.md` (RTO/RPO, ellenőrzési lépések).

**NINCS benne (tilos):**

- ÚJ Alembic migráció vagy `models.py` változás.
- ÚJ HTTP-útvonal (`/readyz` sem — §0.0 R1); a nyitott útvonalak halmaza változatlan.
- `create_all` vagy bármely, az Alembicet megkerülő séma-létrehozás — a `restore.py`-ban is (ADR 0060, ADR 0449 D5). A `main.py` meglévő dev-lifespan `create_all`-ja VÁLTOZATLANUL marad.
- A forgalmi kapu kiterjesztése `dev`/`lab` környezetre (§0.0 R3).
- Bármely meglévő backend-teszt átírása vagy fixture-jének módosítása.
- Valódi felhő-deploy, DNS, TLS vagy titok-kiosztás.
- `docs/adr/**` — az ADR 0449-et a Claude MÁR megírta.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/Dockerfile` | ÚJ — reprodukálható image |
| `backend/deploy/staging.env.example` | ÚJ — staging profil (titok NÉLKÜL) |
| `backend/deploy/README.md` | ÚJ — deploy-lépések |
| `backend/app/main.py` | readiness-vezérelt forgalmi kapu (ÚJ útvonal NÉLKÜL) |
| `backend/scripts/backup.py` | ÚJ — mentés |
| `backend/scripts/restore.py` | ÚJ — visszaállítás |
| `backend/tests/test_readiness_and_recovery.py` | a §6 cellái |
| `docs/operations/backend-deploy.md` | ÚJ — üzemeltetési runbook |
| `docs/operations/database-recovery.md` | ÚJ — recovery runbook |

**Tilos zóna:** `backend/alembic/**` · `backend/app/models.py` · `backend/app/config.py` · `backend/app/routers/**` · `backend/app/database.py` · `backend/tests/**` a `test_readiness_and_recovery.py` KIVÉTELÉVEL (különösen `test_migrations.py` és `conftest.py`) · `backend/requirements*.txt` · `lib/**` · `.github/**` · `tools/**` · `docs/adr/**`

## 5. Kötött architekturális döntések (ADR 0449)

### 5.1 A forgalmi kapu a MIGRÁCIÓS FEJRE mér, és deploy-környezetben aktív (D1–D3)

A readiness predikátuma (DB elérhető ÉS alkalmazott revízió = `alembic heads`) MÁR
implementált a `_readiness_failure()`-ben. A kör azt teszi hozzá, hogy `env ∈
{staging, prod}` alatt ez **kiszolgálási előfeltétel**: amíg hamis, az üzleti
végpontok `503` + `{"status": "not_ready", "reason": <a meglévő okkód>}` választ
adnak és az üzleti kezelő nem fut le; a `/health`, `/health/live`,
`/health/ready` elérhető marad.

- **NEM elfogadható gyengítés:** „a DB válaszol, tehát ready" (puszta `SELECT 1`).
- **NEM elfogadható szigorítás:** a kapu `dev`/`lab` alatti bekapcsolása (§0.0 R3).
- **NEM elfogadható megvalósítás:** új útvonal, vagy a `_readiness_failure()`
  predikátumának átírása.

### 5.2 A restore SOHA nem ír felül létező adatot KETTŐS megerősítés nélkül (D4)

A `restore.py` alapértelmezett célja üres vagy nem létező adatbázis. Ha a cél már
tartalmaz alkalmazás-adatot, a script **nem-nulla** kóddal, **adat-módosítás
nélkül** lép ki. Felülíráshoz `--force` **ÉS** a cél nevének szó szerinti
megismétlése (`--confirm-target <név>`) kell; bármelyik hiánya vagy eltérése
ugyanaz az elutasítás. **NEM elfogadható gyengítés:** csendes felülírás, vagy a
`--force` egymagában elég volta.

### 5.3 A mentés a migrációs fejet is menti, a restore Alembickel épít sémát (D5)

A `backup.py` kimenete a sorokon kívül rögzíti az alkalmazott revíziót és
táblánként a rekordszámot. A `restore.py` a friss célon `alembic upgrade`-del
állítja elő a sémát a mentésben rögzített fejre, majd tölti a sorokat. A
mentésben nem szereplő vagy a láncban ismeretlen fej **elutasítás**.
**NEM elfogadható gyengítés:** `create_all` vagy kézzel írt DDL a restore-ban.

### 5.4 A staging profil-minta titkot nem hordoz; a gépi mérce a betöltés (D6)

(a) a `backend/deploy/staging.env.example` egyetlen titok-jellegű kulcshoz sem
rendel valódi értéket (üres vagy `<...>` helyőrző); (b) a staging profil a
**dev-alapértelmezésű** `secret_key`-jel példányosítási hibát ad — a MEGLÉVŐ
`Settings._guard_staging` őrén, amit a kör használ, nem ír át. A „staging ≠
production titok/adatbázis" operatív szabály a
[`docs/release/environment-matrix.md`](../release/environment-matrix.md)-ben él,
a `deploy/README.md`-ből hivatkozva (§0.0 R4).

### 5.5 A base image DIGESTRE pinelt, a futtató user nem root (D7)

`FROM <kép>@sha256:<64 hex>`; tag önmagában és `latest` tilos; `USER` nem root; a
telepítés a commitolt `requirements.txt`-ből. A digest eredetét (tag + mérés
dátuma + a reprodukáló parancs) a `deploy/README.md` rögzíti. A digest **mai
mért értéke** `python:3.12-slim`-hez:
`sha256:09f7da3bc104798d0afb40bc08d23ab2da20a76130cec1f2ef170848f5d85217`
(a reprodukáló parancs a `deploy/README.md`-be kerül).

## 6. Acceptance criteria

Minden cella a `backend/tests/test_readiness_and_recovery.py`-ban él (a §0.0 R1–R4
szerinti alakban), kivéve az A7-et.

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | `env="staging"` (és `env="prod"`) alkalmazásban, migrálatlan sémán egy üzleti végpont (`GET /settings`) **503 `not_ready`**-t ad, és az üzleti kezelő **nem fut le** (a válasz nem 401/422/200) | `test_readiness_and_recovery.py` |
| A2 | Ugyanabban az alkalmazásban `alembic upgrade head` után a `/health/ready` **200 `ready`**, és ugyanaz az üzleti végpont a NORMÁL viselkedését adja (token nélkül 401, nem 503) | `test_readiness_and_recovery.py` |
| A2b | A kapu aktív állapotában a `/health`, `/health/live` és `/health/ready` **elérhető** (nem 503-as blokk alá esik; a `/health/live` nem nyúl a DB-hez) | `test_readiness_and_recovery.py` |
| A3 | `backup.py` → friss DB → `restore.py` után a táblánkénti rekordszámok ÉS az alkalmazott migrációs fej egyeznek a forrással | `test_readiness_and_recovery.py` |
| A4 | `restore.py` adatot tartalmazó célra `--force` nélkül, illetve `--force`-szal de hibás/hiányzó `--confirm-target`-tel **nem-nulla** kóddal, a cél rekordjainak **változatlanul hagyásával** lép ki | `test_readiness_and_recovery.py` |
| A5 | (a) a `staging.env.example` egyetlen titok-jellegű kulcshoz sem rendel valódi értéket (üres vagy `<...>`); (b) `Settings(env="staging", secret_key=<dev alapértelmezés>, …)` **ValidationError** | `test_readiness_and_recovery.py` |
| A6 | A `Dockerfile` `@sha256:<64 hex>` digestre pinel (nincs `latest`, nincs csupasz tag), és nem-root `USER`-rel fut | `test_readiness_and_recovery.py` statikus cellája |
| A7 | A meglévő backend-cellák (`test_migrations.py`, `conftest.py`-alapú auth/settings cellák) VÁLTOZATLAN forrással zöldek — köztük a `dev` környezet `create_all`-alapú útja **nem** esik a kapu alá | a §7 gate artefaktum |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A kapu a readiness helyett puszta DB-kapcsolatot (`SELECT 1`) néz | A1 |
| A kapu megépül, de a health-útvonalakat is blokkolja | A2b |
| A kapu környezet-független (a `dev` fixture-ökre is tüzel) | A7 (a meglévő auth/settings cellák) |
| A kapu READY állapotban is 503-at ad (túl-blokkolás) | A2 |
| A restore alapértelmezésben felülírja a célt | A4 |
| A restore `--force`-ra `--confirm-target` nélkül is felülír | A4 |
| A backup nem menti a migrációs fejet, csak a táblákat | A3 |
| A restore `create_all`-lal épít sémát (a fej üresen marad) | A3 |
| A `Dockerfile` `latest` vagy csupasz taget használ / rootként fut | A6 |
| A staging profil-minta valódi titkot hordoz, vagy a staging betöltés elfogadja a dev-alapértelmezésű `secret_key`-t | A5 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** cseréld a forgalmi
kapu predikátumát puszta `SELECT 1`-re (vagy vedd ki a kaput), futtasd a backend
cellákat → az **A1** cellának PIROSNAK kell lennie → állítsd vissza, és
dokumentáld a §10-ben a kimenetet.

## 7. Kötelező ellenőrzések

Fejlesztés közbeni szűk kör (MÉRT alak — a munkapéldányban nincs saját
`backend/.venv`, az a `~/music-theory` fáé; a `round-gate.sh` is így oldja fel):

```bash
cd backend && /home/ubuntu/music-theory/backend/.venv/bin/python -m pytest tests/test_readiness_and_recovery.py tests/test_migrations.py -q
```

A KÖTELEZŐ mérce ettől függetlenül a gate artefaktum — mivel a diff a
`backend/`-hez ér, a gate MAGÁTÓL futtatja a `ruff format --check`, `ruff check`
és a **teljes** backend `pytest -q` lépést is (`tools/round-gate.sh:247–255`),
és ez bizonyítja a Flutter-oldal érintetlenségét is:

```bash
tools/round-gate.sh test/app/config/feature_flags_test.dart
```

## 8. Implementációs sorrend

1. `backend/tests/test_readiness_and_recovery.py` — az A1/A2/A2b cellák
   megírása ELŐSZÖR, RED-ből (a kapu még nincs meg).
2. `backend/app/main.py` — a readiness-vezérelt forgalmi kapu (ADR 0449 D1–D3),
   ÚJ útvonal nélkül, a `_readiness_failure()` predikátumának átírása nélkül.
3. `backend/scripts/backup.py` + `restore.py` — A3/A4 (RED-ből).
4. `backend/Dockerfile` + `backend/deploy/` — A5/A6.
5. A két `docs/operations/` runbook.
6. A valódi-sértés próba lefuttatása és dokumentálása a §10-ben.

## 9. Kockázatok

- **Adatvesztés a restore úton.** A legsúlyosabb: csendes felülírás (A4).
- **Az Alembic megkerülése.** Egy „gyors" `create_all` a tesztekhez ADR 0060-at sértene, és a staging/production séma szétcsúszna.
- **A meglévő migrációs teszt regressziója.** A `main.py` indulási sorrendjének átrendezése könnyen elmozdítja (A7).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
