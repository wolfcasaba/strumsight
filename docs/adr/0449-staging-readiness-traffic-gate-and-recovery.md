# ADR 0449 — Readiness-vezérelt forgalmi kapu, mentés/visszaállítás és staging konténer-profil

- **Státusz:** elfogadva (2026-08-28, E12-R08 pre-flight)
- **Kontextus:** SDD Chapter 12, Kör 8;
  [`docs/rounds/e12-r08-staging-backend-migrations-and-recovery.md`](../rounds/e12-r08-staging-backend-migrations-and-recovery.md)
- **Kapcsolódó:** [ADR 0060](0060-alembic-schema-source-and-injected-engine-lifecycle.md)
  (az Alembic az EGYETLEN production séma-forrás; `create_all` csak dev, csak
  lifespanban — ez a kör ezt a döntést KÖVETI, nem tágítja),
  [ADR 0445](0445-environment-value-set-and-staging-isolation.md)
  (zárt `env` értékkészlet `dev | lab | staging | prod`, a staging fail-closed
  őre a `Settings._guard_staging`-ben; kimondja, hogy „egy backend nem tudja
  megállapítani, hogy egy kapott titok »a production titka«-e"),
  [ADR 0448](0448-production-signing-policy-and-secret-hardening.md)
  (a titok-kezelés fail-closed mércéje a release-oldalon)

## Kontextus — mért tények (E12-R08 pre-flight, `main @ 686bc260`)

1. **A migrációs fejre mérő readiness MÁR LÉTEZIK.** `backend/app/main.py`
   `_readiness_failure()` a kapcsolatot ÉS a fejet is méri: a
   `MigrationContext.get_current_heads()` és a `ScriptDirectory.get_heads()`
   halmazának eltérése `migration_mismatch` okkal 503-at ad a
   **`/health/ready`** végponton (`main.py:70–102`, `main.py:189–202`).
2. **A brief eredeti `/readyz` útvonala nem vezethető be.** A
   `backend/tests/test_migrations.py::test_openapi_contract_is_deterministic`
   (362–378. sor) a nyitott útvonalak halmazát **egyenlőségre** méri; egy új
   `/readyz` út ezt a — a kör tilos zónájában élő, átírni tilos — cellát
   pirosra váltaná (A7-sértés).
3. **Ami HIÁNYZIK, az a forgalmi kapu.** A `/settings` és az `/auth/*` útvonal
   ma **akkor is kiszolgál**, ha a `_readiness_failure()` `migration_mismatch`-t
   adna: a readiness egy külön végpont válasza, nem a kiszolgálás előfeltétele.
   Az „üzleti végpontot ne szolgáljunk ki migrálatlan sémán" előírásnak ma
   nincs gépi őre.
4. **Egy naiv, mindenre kiterjedő kapu ~20 meglévő tesztet törne el.** A
   `backend/tests/conftest.py` `client` fixture-je in-memory SQLite-on
   `Base.metadata.create_all`-lal áll fel, `alembic stamp` NÉLKÜL — a fej tehát
   szándékosan üres, a `_readiness_failure()` ezen `migration_mismatch`-et ad.
   Egy környezet-független 503-kapu az összes auth/settings cellát elbuktatná.
5. `backend/Dockerfile`, `backend/deploy/`, `backend/scripts/` **nem létezik**;
   a futtatás ma közvetlen `uvicorn` (`backend/README.md`).
6. `backend/alembic/versions/`: **21** migráció, lineáris lánc
   (`e01_r12_0001` → `e09_r27_0020`).
7. A staging fail-closed őre a `Settings._guard_staging`-ben él
   (`backend/app/config.py:153–184`) — dev-alapértelmezésű `secret_key`,
   wildcard CORS, dev diag-token és escape-hatch nélküli SQLite mind
   **példányosítási** hibát ad. A `config.py` ennek a körnek **tilos zónája**.
8. A registry elérhető erről a boxról: a `python:3.12-slim` manifest
   `docker-content-digest` fejlécében ma
   `sha256:09f7da3bc104798d0afb40bc08d23ab2da20a76130cec1f2ef170848f5d85217`
   (mérve 2026-08-28, `registry-1.docker.io/v2/library/python/manifests/`).

## Döntések

### D1 — A forgalmi kapu a MIGRÁCIÓS FEJRE mér, és a DEPLOY-környezetekben aktív

A readiness predikátuma változatlan (ADR 0060, 1. pont): elérhető DB **és** az
alkalmazott revízió = `alembic heads`. Ehhez a kör azt teszi hozzá, hogy a
predikátum **kiszolgálási előfeltétel** is: `env ∈ {staging, prod}` esetén, amíg
a predikátum hamis, minden üzleti végpont `503` + `{"status": "not_ready",
"reason": …}` választ ad, és az üzleti kezelő **nem fut le**.

A kapu **`dev` és `lab` alatt nem aktív.** Ez nem gyengítés, hanem az ADR 0060
tükre: ott a séma legitim forrása a lifespan `create_all`, amely szándékosan
**nem** stampel — a fej ott ELVÁRTAN üres (4. pont). A kapu pontosan azokban a
környezetekben véd, ahol az Alembic az egyetlen séma-forrás.

**NEM elfogadható gyengítés:** „a DB válaszol, tehát ready" — ez engedné
migrálatlan sémán a forgalmat. **NEM elfogadható szigorítás sem:** a kapu
környezet-független bekapcsolása (4. pont).

### D2 — A liveness és a health-útvonalak a kapu alatt is elérhetők

`/health`, `/health/live` és `/health/ready` a kapu aktív állapotában is
kiszolgál — különben az orchestrátor nem tudná megkülönböztetni a „migrálatlan,
de él" állapotot a halott konténertől, és a deploy nem tudna a saját
readiness-jelére várni. A `/download` (Lab) a deploy-környezetekben amúgy is
sötét (ADR 0445 D-lab default).

### D3 — Új útvonal NEM jön létre; a readiness marad a `/health/ready`

A 2. pont mérése miatt a kör **nem** vezet be `/readyz`-t. A brief `/readyz`
megnevezése a meglévő `/health/ready` végpontra vonatkozik; a deploy-leírók ezt
az útvonalat hivatkozzák.

### D4 — A restore alapértelmezésben SOHA nem ír felül létező adatot

A `restore.py` alapértelmezett célja üres (vagy nem létező) adatbázis. Ha a cél
már tartalmaz alkalmazás-adatot, a script **nem-nulla** kóddal, **adat-módosítás
nélkül** lép ki. A felülíráshoz KETTŐS megerősítés kell: explicit `--force` ÉS a
cél nevének szó szerinti megismétlése (`--confirm-target <név>`); a kettő közül
bármelyik hiánya vagy eltérése ugyanaz az elutasítás.

**NEM elfogadható gyengítés:** csendes felülírás „ez a szokásos eset"
indoklással; a `--force` egymagában elég volta.

### D5 — A mentés a MIGRÁCIÓS FEJET is menti, és a visszaállítás Alembickel épít sémát

A `backup.py` kimenete a sorokon kívül tartalmazza az alkalmazott revíziót és
táblánként a rekordszámot. A `restore.py` a friss célon **`alembic upgrade`**-del
állítja elő a sémát a mentésben rögzített fejre, majd tölti a sorokat —
`create_all` vagy kézzel írt DDL **tilos** (ADR 0060). Ha a mentés feje nem
szerepel a migrációs láncban, a restore elutasít.

### D6 — A staging profil-minta titkot nem hordoz, és a gépi mércéje a betöltés

Az ADR 0445 kimondja, hogy a backend nem tudja megállapítani egy titokról, hogy
„a production titka"-e — ez operatív szabály, nem gépi predikátum. Ezért a kör
azt méri, ami eldönthető:

1. a `backend/deploy/staging.env.example` **egyetlen** titok-jellegű kulcshoz sem
   rendel valódi értéket (üres vagy `<...>` alakú helyőrző), és
2. a staging profil a **dev-alapértelmezésű** `secret_key`-jel példányosítási
   hibát ad (a meglévő `_guard_staging`, 7. pont — a kör ezt **használja**, nem
   írja át).

A „staging ≠ production titok/adatbázis" előírás dokumentált operatív szabály
marad a [`docs/release/environment-matrix.md`](../release/environment-matrix.md)
mátrixában, a `deploy/README.md`-ből hivatkozva.

### D7 — A base image DIGESTRE van pinelve, a futtató user nem root

A `Dockerfile` `FROM <kép>@sha256:<64 hex>` alakot használ (tag-önmagában és
`latest` tilos), a futtatás nem-root userrel megy, és a függőségtelepítés a
commitolt `requirements.txt`-ből, hash-stabil módon történik. A digest
**eredetét** (melyik tag-hez tartozik, mikor mérve) a `deploy/README.md`
rögzíti. A gate a digest FORMÁJÁT és a nem-root futtatást méri; hogy a digest
egy valóban létező image-re mutat, **hálózati** művelet, ami a gate-en kívül
esik — ezt a `deploy/README.md` reprodukáló parancsa fedi.

## Következmények

- A deploy-környezetben egy elfelejtett `alembic upgrade head` mostantól
  **kiszolgálás-hiányt** okoz, nem migrálatlan sémán futó adatírást — ez a
  kívánt fail-closed viselkedés, és a deploy-runbook lépéssora ezért
  migráció → indulás sorrendű.
- A `dev`/`lab` fejlesztői út és a meglévő ~20 backend-cella érintetlen (4. pont).
- A visszaállítás útja bizonyított: a kör cellái friss adatbázison mérik a
  rekordszám- és fej-egyezést, illetve a felülírás elutasítását.
- A `python:3.12-slim` digest karbantartása üzemeltetési feladat lesz; a
  frissítés helye a `deploy/README.md` reprodukáló parancsa.

## Alternatívák

- **Új `/readyz` végpont.** Elutasítva: a determinisztikus OpenAPI-cella
  egyenlőségre mér, és az a cella tilos zónában van (2. pont).
- **Környezet-független forgalmi kapu.** Elutasítva: a meglévő teszt-fixture
  legitim, `create_all`-alapú sémáján ~20 cellát törne el (4. pont).
- **`create_all` a restore-ban** (gyorsabb, nincs Alembic-függés). Elutasítva:
  ADR 0060 — a staging/production séma szétcsúszna a migrációs lánctól.
- **Titok-„production-jelölés" felismerése a betöltéskor.** Elutasítva: az
  ADR 0445 mérése szerint nem eldönthető; a D6 az eldönthető részt méri.
