# ADR 0396 — Community backend modulhatár: PK/UUID séma, router-regisztráció hatóköre, readiness-gate

- **Státusz:** Elfogadva (E09-R02 pre-flight, 2026-08-22)
- **Kör:** E09-R02 — Backend Community modul és Alembic alap
- **Implementer motor:** MiniMax M3 — az ADR-t az orchesztrátor (Claude Sonnet 5)
  írta a pre-flightban (ADR 0055).
- **Epic:** Chapter 10 — Epic 9 (Community Platform), Kör 2 (a 32 kör közül a második)
- **Kontext-ADR-ek:** [0395](0395-community-baseline-feature-flags-and-threat-model-scope.md)
  (Kör 1 — a `community_enabled` flag-ek és a `community_postgres_ready`
  placeholder bevezetése; Következmények 2. pontja kifejezetten erre a
  körre bízza a placeholder éles gate-té alakítását vagy dokumentált
  elvetését), [0060](0060-alembic-schema-source-and-injected-engine-lifecycle.md)
  (Alembic mint egyetlen production schema-forrás, `_readiness_failure`
  mintája a `main.py`-ban).
- **Sorszám-jegyzet:** a szám a `tools/round-slots.py reserve-adr --round
  E09-R02` foglalótól jött (Epic 9 batch-tartomány 0395–0419).

## Kontextus

**Mért 2026-08-22-én, a pre-flightban:**

1. A `backend/app/config.py` MÁR tartalmazza a Kör 1-ben bevezetett
   `community_enabled` (+ 4 alkapcsoló) mezőt és a `community_postgres_ready`
   property-t (`not database_url.startswith("sqlite")`) — ezeket ez a kör
   OLVASSA, nem írja; `config.py` nincs a brief `allowed_paths`-án, tehát
   MÓDOSÍTANI nem szabad.
2. **A brief §2 pontatlanul állítja, hogy "a Community router feltételesen
   regisztrálódik a `communityEnabled` flag alapján (Kör 1)".** Mérve: a
   Kör 1 (E09-R01) dokumentáltan "alkalmazáskód-változtatás nélkül" zárult
   (`HANDOFF.md`), és a `backend/app/main.py` `create_app()` függvénye ma
   NULLA Community-hivatkozást tartalmaz — az egyetlen élő, feltételes
   router-regisztrációs pont a `create_app()` törzse (`app.include_router(
   diagnostics.router)` `if settings.diagnostics_enabled`, ill. a
   `tutor_router` `if settings.tutor_enabled` ága), és ez a pont **nincs**
   a brief `allowed_paths`-án — a tilos zóna kifejezetten kizárja
   (`backend/app/` a `community/` és `config.py`-n kívül).
3. **Ebből következő valódi ütközés (a pre-flight §1 „erőforrás-tulajdonlás"
   szabálya szerint mérve, nem feltételezve):** a §8 8. lépés ("Feladat-flag
   ellenőrzés az app-boot regisztrációs pontban") és az A5 acceptance
   ("Community router hiányzik disabled módban") szó szerint olvasva a
   `main.py`-t követelné meg — ami tilos zóna. A brief nem oldja fel ezt
   explicit módon.
4. Az ADR 0395 Következmények szakasza EZT a helyzetet előre látta: "Minden
   jövőbeli Epic 9 kör, amíg `communityEnabled` production-ben `false`
   marad, a `backend/app/community/**`-t hívó nélkül vagy flag-mögötti
   hívóval építheti — a production viselkedés bitre azonos marad, amíg egy
   külön, jövőbeli GOV-rollout-kör másképp nem dönt." A `main.py`-ba való
   valódi bekötés tehát EGY JÖVŐBELI kör dolga, nem ezé.
5. `backend/app/models.py` (a MEGLÉVŐ `User`/`UserSettings`) `Integer` PK-t
   használ; a brief §8 1. lépése viszont explicit "public UUID + bigint PK"
   párost ír elő az ÚJ Community modellekre — ez tudatos eltérés a meglévő
   mintától (a Community publikus felületei UUID-t adnak ki, sosem
   szekvenciális ID-t, A6/A2 miatt), nem véletlen inkonzisztencia.
6. `backend/requirements.txt`: `SQLAlchemy>=2.0,<2.1` — a natív, dialektus-
   portábilis `sqlalchemy.Uuid` típus (Postgres-en natív UUID, SQLite-on
   `CHAR(32)`) elérhető, külön csomag nélkül.
7. A `backend/tests/conftest.py` és `backend/tests/tutor/conftest.py` MÁR
   mutat egy mintát: mindkettő a saját, izolált `TestClient`-jét építi
   (`create_app(Settings(...))` + `app.dependency_overrides[get_db]`), NEM
   a globális app-singletont használja. A Community teszt-app ugyanezt a
   mintát követheti, de `create_app`-től FÜGGETLENÜL (2. pont miatt), egy
   a modulon belüli, önálló factory-n keresztül.

## Döntés

### 1. PK/UUID séma mindkét új táblán

```python
import uuid
from sqlalchemy import BigInteger, Uuid
from sqlalchemy.orm import Mapped, mapped_column

id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
public_id: Mapped[uuid.UUID] = mapped_column(
    Uuid(as_uuid=True), unique=True, index=True, default=uuid.uuid4, nullable=False
)
```

A belső `id` (BigInteger, autoinkrement) SOSEM hagyja el a folyamatot —
minden API-válasz kizárólag `public_id`-t szerializál (A2). A `Uuid` típus
dialektus-portábilis: SQLite-on `CHAR(32)`, egy jövőbeli Postgres-váltáskor
natív `UUID` — nincs kézi string-konverzió.

### 2. Táblák és kapcsolatok

- `community_profiles`: `id` (BigInteger PK) · `public_id` (Uuid, unique) ·
  `user_id` (BigInteger, `ForeignKey("users.id", ondelete="CASCADE")`,
  **unique** — ez kényszeríti ki az 1:1-et, A7) · `display_name`
  (String, nullable — a teljes profil-mező-készlet Kör 6+ onboarding
  scope-ja, NEM ez a kör) · `created_at` (DateTime tz-aware).
- `community_privacy_settings`: `id` (BigInteger PK) · `public_id` (Uuid,
  unique) · `profile_id` (BigInteger, `ForeignKey("community_profiles.id",
  ondelete="CASCADE")`, **unique** — 1:1 a profilhoz) · `updated_at`
  (DateTime tz-aware). A granuláris privacy-taxonómia (mely mezők legyenek
  publikusak/követőknek/privátak) Kör 6+ dolga — ez a kör csak a táblát és
  az 1:1 constraintet vezeti be, egyetlen dokumentált placeholder mezővel
  ha a modell üres tábla nem fordulna (pl. `updated_at`).
- **Explicit létrehozás, nincs backfill, nincs `get_or_create`.** A
  migráció NEM tölt fel egyetlen meglévő userhez sem sort (5.1 invariáns);
  a service-réteg (router) csak akkor hoz létre sort, ha egy jövőbeli Kör
  6 endpoint explicit meghívja — ez a kör NEM ír ilyen endpointot (csak a
  modellt, sémát és a modul-boundary tesztjeit), a routerben elég egy
  minimális, dependency-injektált olvasó végpont vagy stub, ami a modult
  ténylegesen importálhatóvá/tesztelhetővé teszi flag mögött.

### 3. A router-regisztráció hatóköre: `main.py` ÉRINTETLEN marad

A "app-boot regisztrációs pont" (brief §8 5. lépés) EZEN a körön egy, a
`backend/app/community/__init__.py`-ban élő, önálló factory-függvény:

```python
def build_community_router(settings: Settings) -> APIRouter | None:
    """Returns the Community router only when the module is enabled.

    Mirrors main.py's `if settings.tutor_enabled: app.include_router(...)`
    pattern, but lives entirely inside the community module so this round
    never has to touch the forbidden `backend/app/main.py`. Wiring this
    into the live `create_app()` app is a future round's job (ADR 0395
    Következmények 3. pont) — this function's only consumer THIS round is
    `backend/tests/community/conftest.py`'s own, self-contained test app.
    """
    if not settings.community_enabled:
        return None
    from .routers.profile import router
    return router
```

`backend/tests/community/conftest.py` épít egy MINIMÁLIS, saját
`FastAPI()` példányt (NEM `app.main.create_app`-et hívja), és
`build_community_router(settings)` eredményét regisztrálja feltételesen —
ez bizonyítja A5-öt ("router hiányzik disabled módban") a modul saját
határán belül, `main.py` érintése nélkül. **A `main.py`-ba való valódi
bekötés ennek a körnek NEM acceptance-kritériuma** — ha az implementer
mégis `main.py`-t módosítaná, az a brief tilos zónájának megsértése (H3),
NEM egy hiányzó lépés pótlása.

### 4. `community_postgres_ready` → éles gate, de NEM a `/health/ready`-ben

Az ADR 0395 Következmények 2. pontja szerint ez a kör dönt: a placeholder
**éles gate-té válik**, egy a modulon belüli, önállóan tesztelhető
függvényben (`backend/app/community/__init__.py`), a `main.py`
`_readiness_failure` mintáját követve (ADR 0060), de tőle FÜGGETLENÜL (nem
hívja és nem hívja meg — a `main.py` tilos zóna):

```python
def community_readiness_failure(
    engine: Engine, settings: Settings, alembic_ini: Path
) -> str | None:
    """Analogous to main.py's _readiness_failure, scoped to the Community
    migration chain. Not wired into /health/ready this round (that call
    site is main.py, out of scope) — a future round's job."""
    if settings.community_enabled and settings.env == "prod" and not settings.community_postgres_ready:
        return "community_requires_postgres"
    try:
        with engine.connect() as connection:
            current_heads = frozenset(
                MigrationContext.configure(connection).get_current_heads()
            )
    except SQLAlchemyError:
        return "database_unavailable"
    try:
        expected_heads = frozenset(
            ScriptDirectory.from_config(AlembicConfig(str(alembic_ini))).get_heads()
        )
    except (CommandError, OSError):
        return "migration_mismatch"
    return None if current_heads == expected_heads else "migration_mismatch"
```

Ez fail-closed: production-ben `community_enabled=true` + SQLite (`
community_postgres_ready=False`) → a gate pirosat jelez, MIELŐTT bármi
migration-head-et nézne. A gate-nek MA nincs élő hívója (nincs
`/health/ready` bekötés) — ez dokumentált, szándékos: a bekötés a
`main.py`-t igényelné, ami tilos zóna. A11 (A1) a `test_profile_schema.py`
saját unit-tesztje a függvényen, nem egy élő endpoint-integráció.

### 5. Migrációs revízió a meglévő lánc folytatása

`backend/alembic/versions/e09_r02_0002_community_profile.py`:
`revision = "e09_r02_0002"`, `down_revision = "e01_r12_0001"` — a MA
egyetlen meglévő fej (`e01_r12_0001`, `backend/alembic/versions/
e01_r12_0001_initial_account_schema.py`) folytatása, nem új ág.

**NEM elfogadható gyengítés:** a `community_profiles`/`community_privacy_settings`
tábla `create_all`-lal létrehozása bármilyen environmentben éles kódúton
(A1); a `user_id`/`profile_id` unique constraint elhagyása vagy alkalmazás-
szintre tolása (A7 kizárólag DB-constraint-tel mérhető megbízhatóan); a
`public_id` szekvenciális vagy `id`-ből képzett string (A6); a Pydantic
válasz-séma `from_attributes=True` a teljes ORM objektumon `id` mezővel
együtt (A2 — a séma explicit csak a whitelistelt mezőket sorolja fel); a
router feltétel nélküli regisztrálása a teszt-app factoryban, flag-
ellenőrzéssel csak egyes endpointokon belül (A5 — a döntés pontja a
factory-szintű `if`, nem az endpoint-szint).

## Elutasított alternatívák

- **`main.py` felvétele az `allowed_paths`-ra, hogy a router éles
  bekötése is megtörténjen ebben a körben.** Elvetve: a brief
  `allowed_paths`-a előre, írásban rögzített, és a bővítés MOST, ad hoc,
  a pre-flightban H3 határsértés lenne (ADR 0087 §2) — az ADR 0395
  Következmények 3. pontja már dokumentáltan egy JÖVŐBELI körre bízta ezt
  a lépést; ennek a körnek nem kell (és nem szabad) elébe mennie.
- **A `community_postgres_ready` placeholder változatlanul hagyása
  (nincs éles gate).** Elvetve: az ADR 0395 Következmények 2. pontja
  kifejezetten erre a körre bízta a döntést ("vagy éles gate-té alakítja,
  vagy dokumentáltan elveti"), és egy hallgatólagos elvetés (a property
  egyszerűen sosem kerül hívásra) nem "dokumentált" — a 4. döntési pont
  egy önállóan tesztelhető, bár ma hívó nélküli függvényt ad, ami a
  jövőbeli `main.py`-bekötést egy kész, tesztelt komponensre építheti.
- **Integer PK az új táblákon (a meglévő `User`/`UserSettings` mintája).**
  Elvetve: a brief §8 1. lépése explicit "public UUID + bigint PK" párost
  ír elő, és az A6 kritérium ("Public UUID egyedi és nem szekvenciális")
  csak akkor mérhető megbízhatóan, ha a publikus azonosító ténylegesen
  UUID, nem egy `Integer` PK string-re castolva.
- **Kézzel generált UUID string (`str(uuid.uuid4())`) `String(36)` oszlopon,
  natív `Uuid` típus helyett.** Elvetve: a `SQLAlchemy>=2.0` már biztosítja
  a dialektus-portábilis `Uuid` típust — a kézi string-konverzió
  felesleges kód, és egy jövőbeli Postgres-váltáskor elveszítené a natív
  `UUID` oszloptípus indexelési előnyét.

## Következmények

- A `main.py`-ba való éles router-bekötés (és a `/health/ready` Community-
  ágának bekötése) egy JÖVŐBELI Epic 9 kör dolga — ez a kör csak a
  modulhatárt és a moduluk saját tesztelhetőségét adja.
- A Kör 6 (onboarding, explicit profil-létrehozás) a `community_profiles`
  sor tényleges service-szintű létrehozását adja; ez a kör csak a modellt,
  a migrációt és a modul-boundary olvasó/teszt útját.
- A `community_readiness_failure` függvény ma hívó nélküli, tesztelt
  komponens — a következő kör (vagy a tényleges Postgres-váltás köre)
  köti be a `main.py` `/health/ready`-be, ADR 0060 mintájára.

## A visszavonás feltétele

Felülvizsgálandó, ha egy jövőbeli Kör mérten azt találja, hogy a
`main.py`-tól független, csak-a-modulon-belüli router-factory minta
gyakorlati problémát okoz (pl. a valódi bekötéskor duplikált logika lesz
`main.py` és `community/__init__.py` között) — ekkor a `main.py` explicit
felvétele egy dedikált, jövőbeli kör `allowed_paths`-ára a helyes lépés,
nem ennek a körnek a visszamenőleges bővítése.
