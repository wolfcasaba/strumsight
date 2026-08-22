# E09-R02 — Backend Community modul és Alembic alap

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 2
- **Kör-azonosító:** `E09-R02`
- **Branch:** `<motor>/e09-r02-backend-community-module-and-migration`
- **Előfeltétel:** `E09-R01` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0396` — a szám FOGLALT (Epic 9 batch-tartomány 0395-0419). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `backend/app/config.py` MA élő `database_url`/`allow_sqlite_in_prod` mezőit és a `backend/alembic/versions/` egyetlen meglévő migrációját (`e01_r12_0001_initial_account_schema.py`) — az ÚJ migráció ennek a láncnak a folytatása, revision-fejjel. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

## 0.0 Pre-flight brief-revízió (Claude, 2026-08-22, ADR 0396)

**Mért tény, ami a §2-t pontosítja:** a Kör 1 (E09-R01) dokumentáltan
"alkalmazáskód-változtatás nélkül" zárult — `backend/app/main.py`
`create_app()`-ja MA NULLA Community-hivatkozást tartalmaz. A §2 "a
Community router feltételesen regisztrálódik a `communityEnabled` flag
alapján (Kör 1)" mondat PONTATLAN: Kör 1 csak a nyers `config.py` flag-eket
vezette be, router-regisztráció sehol nincs. Az egyetlen élő, feltételes
router-regisztrációs pont a mai kódban `main.py` `create_app()` törzse
(lásd a `diagnostics_enabled`/`tutor_enabled` ágakat) — ez a fájl **nincs**
a lenti `allowed_paths`-on és a tilos zóna kifejezetten kizárja.

**Feloldás (ADR 0396 §3–4, teljes indoklás ott):**

1. A §8 5. lépése ("Feature-flag ellenőrzés az app-boot regisztrációs
   pontban") EBBEN a körben egy `backend/app/community/__init__.py`-ban élő
   `build_community_router(settings) -> APIRouter | None` factory —
   **NEM** `main.py`. `backend/tests/community/conftest.py` a SAJÁT,
   minimális `FastAPI()` példányát építi (nem `app.main.create_app`-et
   hívja), és ezt a factoryt regisztrálja feltételesen — ez bizonyítja
   A5-öt a modul saját határán belül.
2. **A `main.py`-ba való éles bekötés NEM ennek a körnek az
   acceptance-kritériuma** — az ADR 0395 Következmények 3. pontja szerint
   ez egy jövőbeli kör dolga. Ha az implementer mégis `main.py`-t
   módosítaná (akár csak egy `include_router` sorral), az a tilos zóna
   megsértése (H3), nem egy hiányzó lépés pótlása.
3. `community_postgres_ready` (ADR 0395 Következmények 2. pontja szerint
   ennek a körnek kell döntenie) **éles gate-té válik**, de csak egy
   önállóan tesztelhető, ma hívó nélküli `community_readiness_failure(
   engine, settings, alembic_ini)` függvényben `backend/app/community/
   __init__.py`-ban (ADR 0396 §4 pontos kódváz) — a `/health/ready`
   bekötése szintén jövőbeli kör dolga (ugyanaz a `main.py`-korlát).
4. PK/UUID séma: mindkét új tábla `id: BigInteger` (belső, sosem
   szerializált) + `public_id: Uuid(as_uuid=True)` (natív SQLAlchemy 2.0
   `Uuid` típus — Postgres-en natív UUID, SQLite-on `CHAR(32)`, NINCS
   kézi string-konverzió). Pontos oszloplista és kapcsolat-irány: ADR 0396
   §1–2.
5. Migrációs revízió-fej: `revision = "e09_r02_0002"`,
   `down_revision = "e01_r12_0001"` — a MA egyetlen fej folytatása.

**Visszakeresett előzmény (S8, §4.9):** [ADR 0060](../adr/0060-alembic-schema-source-and-injected-engine-lifecycle.md)
(Alembic egyetlen schema-forrás, `_readiness_failure` minta a `main.py`-ban
— ADR 0396 ezt tükrözi a modulhatáron belül) és [ADR 0395](../adr/0395-community-baseline-feature-flags-and-threat-model-scope.md)
(Kör 1 — a flag-ek és a `community_postgres_ready` placeholder eredete,
Következmények 2–3. pont). Nincs a témára közvetlenül vonatkozó halt-lecke;
a legközelebbi analóg minta L97 (route-katalógus owner hiánya scope-ból) —
ugyanaz a hibaosztály (a wiring-pont owner-je kimaradt az `allowed_paths`-ból),
itt a §0.0 feloldotta a `main.py` teljes kizárásával, nem felvételével.

## 0.1 Self-heal brief-revízió (ADR 0112 önjavító kör, 2026-08-22, halt H3)

**Mért gyökérok:** `backend/tests/test_migrations.py::test_downgrade_one_revision_removes_application_schema`
egyetlen-migrációs világot feltételez ("`downgrade -1` a fejtől == `users`/
`user_settings` eltűnik"). A §0.0/§5 pontban kötött migráció-láncolás
(`e09_r02_0002` `down_revision = "e01_r12_0001"`) ezt a feltevést hamissá
teszi: `alembic downgrade -1` a fejtől MOST már csak a LEGÚJABB migrációt
(`community_profiles`/`community_privacy_settings`) vonja vissza, a
`users`/`user_settings` a helyén marad — ez minden, a láncot bővítő
migrációnak szükségszerű, előre látható következménye, nem az ÚJ migráció
hibája. A fájl nem szerepelt a lenti `allowed_paths`-on, ezért az
implementer helyesen `blocked`-ot jelzett a §0 STOP-protokoll szerint,
ahelyett hogy a listát csendben tágította volna.

Reprodukálva függetlenül (`/home/ubuntu/ss-mm-e09-r02`, `backend/.venv`
helyett a fő munkapéldány megosztott `backend/.venv`-jével):

```
cd backend && python -m pytest tests/test_migrations.py -q
# FAILED test_downgrade_one_revision_removes_application_schema
# AssertionError: assert 'users' not in {'alembic_version', 'user_settings', 'users'}
```

**Feloldás:**

1. `backend/tests/test_migrations.py` felkerül az `allowed_paths`-ra (lásd
   lent) — ez a kör saját §0.0/§5 döntésének (migráció-láncolás) egyenes
   következménye, nem hatókör-bővítés a kör céljához képest.
2. Az implementer a folytatásban **frissítse**
   `test_downgrade_one_revision_removes_application_schema`-t a
   két-migrációs valósághoz: bontsa két esetre — (a) "egy lépés downgrade a
   fejtől csak a Community táblákat távolítja el" (`community_profiles`,
   `community_privacy_settings` eltűnik, `users`/`user_settings` marad) és
   (b) "downgrade a base-ig a `users`/`user_settings`-et is eltávolítja"
   (`command.downgrade(config, "base")`, majd ugyanaz az `assert "users" not
   in tables` / `assert "user_settings" not in tables` pár). A többi,
   ebben a fájlban élő teszt (`test_upgrade_head_matches_current_orm_schema`,
   `test_sqlite_runtime_enforces_foreign_key_cascade`, stb.) már ma is
   helyesen kezeli a két-migrációs láncot (zöld, lásd fent) — csak ez az egy
   eset feltételezett egyetlen migrációt.
3. Ez a hibaosztály **nem** ismétlődhet meg némán: a
   `tools/tests/test_e09_r02_migration_downgrade_test_scope.py` regressziós
   teszt (self-heal, lásd a fájl fejlécét) rögzíti, hogy a valós brief
   `allowed_paths`-a MOST már fedi `backend/tests/test_migrations.py`-t, és
   hogy egy szomszédos, ehhez a körhöz nem tartozó backend-teszt fájl
   (`backend/tests/test_auth.py`) továbbra is hatókörön kívül marad —
   a javítás egy szűk, egyetlen fájlra szóló bővítés, nem az egész
   `backend/tests/` könyvtár engedélyezése.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/__init__.py",
  "backend/app/community/models/profile.py",
  "backend/app/community/schemas/profile.py",
  "backend/app/community/routers/profile.py",
  "backend/alembic/versions/e09_r02_0002_community_profile.py",
  "backend/tests/community/test_profile_schema.py",
  "backend/tests/community/conftest.py",
  "backend/tests/test_migrations.py",
  "docs/rounds/e09-r02-backend-community-module-and-migration.md",
]
gate_tests = [
  "test/core/architecture_dependency_test.dart"
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 1. Cél

Hozd létre a Community backend moduláris határát és az első adatbázis-migrációt: `community_profiles` és `community_privacy_settings`, 1:1 kapcsolattal a meglévő `users` táblához, de profil csak explicit létrehozáskor jön létre.

## 2. Jelenlegi állapot — mért tények

- `backend/app/community/` **nem létezik** — ez a kör hozza létre a router/service/repository/policy/schema réteget
- a `users` tábla (E01-R12 migráció) MA e-mail alapú, bcrypt jelszavas, JWT-s — ehhez a Community 1:1, de OPCIONÁLIS kapcsolatot ad
- a backend MA SQLite-tal fut fejlesztésben; a Community readiness-check-nek a `Kör 1` ADR-jében rögzített SQLite-vs-PostgreSQL döntést kell mérnie
- `backend/app/routers/` a meglévő route-regisztráció mintája — a Community router feltételesen regisztrálódik a `communityEnabled` flag alapján (Kör 1)

## 3. Scope

**Benne van:** `backend/app/community/{__init__,models,schemas,routers}` szerkezet · `community_profiles` és `community_privacy_settings` tábla Alembic migrációval · public UUID + belső bigint primary key · readiness-ellenőrzés (PostgreSQL-kompatibilitás + migration head production-ben) · factory-alapú, dependency-override-olható tesztalkalmazás.

**NINCS benne (tilos):**

- A router regisztrálása feature-flag ellenőrzés NÉLKÜL.
- `create_all`-alapú séma-létrehozás bármilyen környezetben.
- A meglévő `users`/auth migráció vagy modell módosítása.
- `docs/adr/**` — az ADR 0396-ot a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/__init__.py` | ÚJ — modulhatár |
| `backend/app/community/models/profile.py` | ÚJ — profil + privacy-settings SQLAlchemy modell |
| `backend/app/community/schemas/profile.py` | ÚJ — Pydantic sémák |
| `backend/app/community/routers/profile.py` | ÚJ — feature-flag mögötti router |
| `backend/alembic/versions/e09_r02_0002_community_profile.py` | ÚJ — az első Community migráció |
| `backend/tests/community/test_profile_schema.py` | ÚJ — a §6 cellái |
| `backend/tests/community/conftest.py` | ÚJ — factory-alapú tesztalkalmazás |
| `backend/tests/test_migrations.py` | MEGLÉVŐ — §0.1 self-heal (H3): a `test_downgrade_one_revision_removes_application_schema` frissítése a két-migrációs láncra |

**Tilos zóna:** `backend/app/` a `community/` és `config.py`-n kívül (auth, settings, tutor router/service/model) · `backend/alembic/versions/` a MEGLÉVŐ migráció · `lib/**` (ez a kör tisztán backend) · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0396)

### 5.1 A profil 1:1 a felhasználóhoz kötött, de OPCIONÁLIS és explicit

A `users` tábla minden sorához LEGFELJEBB egy `community_profiles` sor tartozhat, de a Community bekapcsolása vagy a fiók léte NEM hoz létre automatikusan profilt — csak a Kör 6 explicit onboarding flow-ja.

**NEM elfogadható gyengítés:** egy migrációs backfill, ami minden meglévő userhez profilt generál "hogy ne kelljen külön létrehozó lépés" — ez pont az implicit megosztás ellen szóló invariánst (SDD §6/4) sértené.

### 5.2 A router csak flag mögött regisztrálódik

`communityEnabled=false` esetén a Community router útvonalai TELJESEN hiányoznak a FastAPI app-ból — nem 404-et adnak, hanem nincsenek regisztrálva.

**NEM elfogadható gyengítés:** a router feltétel nélküli regisztrálása és a flag-ellenőrzés belehelyezése minden egyes endpoint elejére — egy elfelejtett endpoint így kimaradna a védelemből.

### 5.3 Nincs `create_all`; a séma kizárólag Alembicből származik

A readiness-ellenőrzés a migration headet és (production-ben) a PostgreSQL-kompatibilitást méri, nem futtat implicit sémaszinkront.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Productionben nincs `create_all` alapú Community schema | `test_profile_schema.py` — readiness teszt |
| A2 | A profile tábla nem szivárogtat belső user ID-t API-ba | `test_profile_schema.py` — schema szerializációs teszt |
| A3 | A modul önálló dependency boundaryval rendelkezik (factory override) | `conftest.py` alapú tesztalkalmazás |
| A4 | Alembic upgrade üres adatbázison sikeres | `alembic upgrade head` |
| A5 | Community router hiányzik disabled módban | `test_profile_schema.py` — flag-off teszt |
| A6 | Public UUID egyedi és nem szekvenciális | `test_profile_schema.py` — uniqueness teszt |
| A7 | User–profile 1:1 constraint kikényszerítve | `test_profile_schema.py` — duplicate insert teszt |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Backfill migráció minden userhez profilt hoz létre | A7 szomszédos invariáns — profil csak explicit action, review-lelet |
| A response Pydantic séma tartalmazza a belső `id` mezőt | A2 |
| A router feltétel nélkül regisztrálva, flag-ellenőrzés csak egyes endpointokban | A5 |
| A public UUID inkrementális integer-ből képzett string | A6 |
| Egy második profil insert ugyanahhoz a userhez sikeres | A7 |
| A teszt a production `.env`-et olvassa be közvetlenül, override nélkül | A3 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki a `(user_id)` unique constraintet a modellből, futtasd a backend pytest-et → az **A7** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/architecture_dependency_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community -q && alembic upgrade head
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. `backend/app/community/models/profile.py` — `CommunityProfile` + `CommunityPrivacySettings` SQLAlchemy modell, public UUID + bigint PK.
2. Alembic migráció: `community_profiles`, `community_privacy_settings`, unique constraint a `user_id`-n.
3. `backend/app/community/schemas/profile.py` — Pydantic response séma (SOSEM a belső `id`).
4. `backend/app/community/routers/profile.py` — flag-mögötti router, dependency-injektált service.
5. Feature-flag ellenőrzés az app-boot regisztrációs pontban (nem endpointonként).
6. `backend/tests/community/conftest.py` — factory-alapú, override-olható tesztalkalmazás.
7. A readiness-ellenőrzés (migration head + PostgreSQL-kompatibilitás production-ben).
8. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **Az implicit profil-létrehozás.** Egy backfill vagy `get_or_create` minta csendben megsértené a SDD §6.5 explicit-akció invariánsát (A7 mellett a termékszabály is sérül).
- **A belső ID szivárgása.** Egy Pydantic `from_attributes=True` séma könnyen visszaadja a teljes SQLAlchemy objektumot, benne az `id` mezővel (A2).
- **A router feltétel nélküli regisztrálása.** Egy elfelejtett flag-ellenőrzés egyetlen endpointon a teljes réteg védelmét áttöri (A5).

## 10. Implementation handoff — az implementer tölti ki

### Fájlonkénti összegző

| Fájl | Tartalom |
|---|---|
| `backend/app/community/__init__.py` | Modulhatár: re-export `CommunityProfile` / `CommunityPrivacySettings` + a két ADR 0396 §3–4 szerinti nyilvános függvény: `build_community_router(settings)` (factory, flag-mögötti) és `community_readiness_failure(engine, settings, alembic_ini)` (fail-closed gate, a `main.py._readiness_failure` mintára, de tőle FÜGGETLENÜL — `main.py` tilos zóna). |
| `backend/app/community/models/profile.py` | `CommunityProfile` (BigInteger PK + `Uuid` public_id + `users.id` FK ondelete CASCADE + UNIQUE a 1:1-hez) és `CommunityPrivacySettings` (BigInteger PK + `Uuid` public_id + `community_profiles.id` FK ondelete CASCADE + UNIQUE). A PK `BigInteger().with_variant(Integer, "sqlite")` mintát követi, hogy az SQLite-os box-gate alatt is auto-increment legyen (PostgreSQL-en natív bigserial). |
| `backend/app/community/schemas/profile.py` | Whitelist-only Pydantic response sémák — `CommunityProfileOut` és `CommunityPrivacySettingsOut` kizárólag `public_id`-t és a dokumentált mezőket sorolják fel; a belső `id` (BigInteger) mező SOHA nem jelenik meg a válaszban (A2). |
| `backend/app/community/routers/profile.py` | Minimális, flag-mogott router (`/community/ping` + `/community/profiles/{public_id}`); a public UUID-val keresés a `public_id` oszlopon történik, sosem a belső `id`-n. |
| `backend/alembic/versions/e09_r02_0002_community_profile.py` | Revízió `e09_r02_0002`, `down_revision = "e01_r12_0001"` — a MA egyetlen fej folytatása (ADR 0396 §5). Mindkét tábla: BigInteger PK (dialektus-portábilis: Integer SQLite-on), `Uuid` public_id, FK-k ondelete CASCADE, UNIQUE a 1:1-hez, plusz explicit unique index a `public_id`-n. A migráció TÖRTÉNŐLEG importálja a modelleket, hogy a `compare_metadata` autogenerate tiszta maradjon (round 12 meglévő migrációs teszt védvonala). |
| `backend/tests/community/conftest.py` | Saját, minimális `FastAPI()` teszt-app (NEM `create_app()`-et hívja, ADR 0396 §3); a `get_db` seamet `dependency_overrides` útján izolálja; a `build_community_router(settings)` eredményét feltételesen regisztrálja — ezzel bizonyítja A5-öt a modul saját határán belül. |
| `backend/tests/community/test_profile_schema.py` | Mind a HÉT acceptance-pont (A1–A7) külön teszt + a §6.1 mérce-mátrix minden sora mint önálló falszifikációs cella (17 teszt, mind zöld). |
| `backend/tests/test_migrations.py` | MEGLÉVŐ — a H3 self-heal (§0.1) feloldása: az eredeti `test_downgrade_one_revision_removes_application_schema` (1-migrációs világra írt) két önálló esetre bomlik — (a) `test_downgrade_one_revision_drops_only_community_tables` (`downgrade -1` CSAK a Community táblákat veszi el, `users`/`user_settings` marad) és (b) `test_downgrade_to_base_removes_application_schema` (`downgrade base` a teljes láncot visszafordítja). A többi teszt a fájlban változatlan. |

### Acceptance-bizonyíték — ténylegesen lefuttatott tesztek (NEM elméleti leírás)

A lokális mérce a §7 szerint futott (külön parancsok, NEM láncolva, csonkítás nélkül):

```bash
tools/round-gate.sh test/core/architecture_dependency_test.dart
cd backend && /home/ubuntu/music-theory/backend/.venv/bin/python -m pytest tests/community -q
cd backend && STRUMSIGHT_DATABASE_URL=sqlite:////tmp/e09_r02_gate_test.db /home/ubuntu/music-theory/backend/.venv/bin/python -m alembic upgrade head
```

A Flutter-sáv (`tools/round-gate.sh`) kimenete: `format / analyze / test / architecture / secrets / l10n / backend ruff format / backend ruff check` mind zöld; a `backend pytest` cella a H3 self-heal (§0.1) feloldása után MOST ZÖLD (a `tests/test_migrations.py` split-teszt részletesen lentebb, a §10 „Futtatott parancsok tényleges kimenete" szakaszban).

A `tests/community` 17 tesztje mind zöld:

| Teszt | Lefedett cella | Eredmény |
|---|---|---|
| `test_alembic_upgrade_head_applies_community_migration` | A4 | ✅ |
| `test_alembic_downgrade_drops_community_tables` | A4 (downgrade -1 a Community-t veszi el, a baseline marad) | ✅ |
| `test_module_import_does_not_read_production_env` | A3 / §6.1 5. sor | ✅ |
| `test_factory_returns_none_when_community_disabled` | A5 / §6.1 3. sor | ✅ |
| `test_router_is_not_mounted_when_disabled` | A5 | ✅ |
| `test_router_is_mounted_when_enabled` | A5 | ✅ |
| `test_profile_out_schema_does_not_expose_internal_id` | A2 / §6.1 2. sor | ✅ |
| `test_privacy_out_schema_does_not_expose_internal_id` | A2 | ✅ |
| `test_response_payload_does_not_contain_internal_id` | A2 (HTTP rétegen) | ✅ |
| `test_public_id_is_uuid4_not_derived_from_internal_id` | A6 / §6.1 4. sor | ✅ |
| `test_public_id_unique_constraint_at_db_level` | A6 | ✅ |
| `test_duplicate_profile_for_same_user_is_rejected_by_db` | A7 / §6.1 6. sor | ✅ |
| `test_user_deletion_cascades_to_community_profile` | A7 (FK cascade) | ✅ |
| `test_community_readiness_failure_reports_create_all_disallowed` | A1 | ✅ |
| `test_community_readiness_failure_flags_sqlite_in_prod` | A1 (fail-closed) | ✅ |
| `test_community_readiness_failure_reports_migration_mismatch` | A1 | ✅ |
| `test_community_readiness_failure_reports_database_unavailable` | A1 | ✅ |

`alembic upgrade head` üres SQLite-on: mindkét migráció (`e01_r12_0001` → `e09_r02_0002`) sikeresen lefut; a `community_profiles` és `community_privacy_settings` táblák + a `users`/`user_settings` baseline-ok egyaránt jelen vannak, az FK-k és UNIQUE-ok a migrációs DDL-ből származnak, NEM `create_all`-ból.

### Valódi-sértés próba (a §6 "Valódi-sértés próba" KÖTELEZŐ)

A `(user_id)` UNIQUE constraint ideiglenes kikapcsolása a `CommunityProfile.user_id` mapped_column-ján:
- `tests/community/test_profile_schema.py::test_duplicate_profile_for_same_user_is_rejected_by_db` → PIROS, `Failed: DID NOT RAISE <class 'sqlalchemy.exc.IntegrityError'>` — a második INSERT a `user_id=1`-re sikeresen átment.
- Azonnali visszaállítás: a constraint visszatéve, a teszt újra zöld.

A constraint MOST a modellben és a migrációban IS aktív (DB-szinten kikényszerített, NEM alkalmazás-szinten), A7 teljesül.

### `git diff --stat` TÉNYLEGES kimenete

A kör (H3 self-heal feloldás) 7 új fájlt hozott létre + 2 meglévő fájlt módosított (a §0.1-ben feloldott `backend/tests/test_migrations.py` split-teszttel és a `docs/rounds/e09-r02-…` handoff frissítésével):

```
M  backend/tests/test_migrations.py
M  docs/rounds/e09-r02-backend-community-module-and-migration.md
?? backend/alembic/versions/e09_r02_0002_community_profile.py
?? backend/app/community/__init__.py
?? backend/app/community/models/profile.py
?? backend/app/community/routers/profile.py
?? backend/app/community/schemas/profile.py
?? backend/tests/community/conftest.py
?? backend/tests/community/test_profile_schema.py
```

(A 7 új fájl megfelel a §4 `allowed_paths` listájának; a `models/`, `routers/`, `schemas/`, `tests/community/` almappák PEP 420 namespace-package-ként működnek `__init__.py` nélkül, mert a scope-őr azokat is tiltja — a tesztek és a modul-importok ezt a konvenciót használják. A `backend/tests/test_migrations.py` módosítása kizárólag a §0.1 2. pontjában leírt két esetre bontás — más tesztet nem érint.)

### Futtatott parancsok tényleges kimenete

A `tools/round-gate.sh test/core/architecture_dependency_test.dart` utolsó 12 sora (a §0.1 self-heal után minden cella ZÖLD — a korábbi piros `backend pytest` cella a `tests/test_migrations.py` split-tesztjével zöldre váltott):

```
═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/core/architecture_dependency_test.dart           zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld
    backend ruff format                                        zöld
    backend ruff check                                         zöld
    backend pytest                                             zöld

MINDEN GATE ZÖLD.
```

A `tests/test_migrations.py` módosítása a §0.1 2. pontjának feloldása: az eredeti `test_downgrade_one_revision_removes_application_schema` (E01-R12-ből örökölt, 1-migrációs világra írt) KÉT önálló esetre bomlik:

| Új teszt | Lefedett invariáns | Eredmény |
|---|---|---|
| `test_downgrade_one_revision_drops_only_community_tables` | egy lépés `downgrade -1` a fejtől CSAK a Community táblákat (`community_profiles`, `community_privacy_settings`) veszi el; `users`/`user_settings` MARAD | ✅ |
| `test_downgrade_to_base_removes_application_schema` | `downgrade base` a teljes láncot visszafordítja — a `users`/`user_settings` is eltűnik | ✅ |

A két új eset a két-migrációs valóságot dokumentálja: a lánc `head` → `e01_r12_0001` (downgrade -1) → `base`. A többi, ebben a fájlban élő teszt (`test_upgrade_head_matches_current_orm_schema`, `test_sqlite_runtime_enforces_foreign_key_cascade`, stb.) változatlan — ezek már eleve helyesen kezelték a 2-migrációs láncot, és most is zöldek.

```
$ /home/ubuntu/music-theory/backend/.venv/bin/python -m pytest tests/test_migrations.py -q
...............                                                          [100%]
15 passed in 1.65s
```

A `tests/community` 17 tesztje és a `alembic upgrade head` önálló parancsok — a §7 második fele szerinti lokális gate — zöld:

```
$ /home/ubuntu/music-theory/backend/.venv/bin/python -m pytest tests/community -q
.................                                                        [100%]
17 passed, 10 warnings
```

```
$ STRUMSIGHT_DATABASE_URL=sqlite:////tmp/e09_r02_gate_test.db /home/ubuntu/music-theory/backend/.venv/bin/python -m alembic upgrade head
INFO  [alembic.runtime.migration] Context impl SQLiteImpl.
INFO  [alembic.runtime.migration] Will assume non-transactional DDL.
$ /home/ubuntu/music-theory/backend/.venv/bin/python -m alembic current
e09_r02_0002 (head)
$ sqlite3 /tmp/e09_r02_gate_test.db ".tables"
alembic_version            community_privacy_settings  community_profiles
user_settings              users
```

A 10 warnings a `sqlite3` deprecation-warning a `datetime` adapter-ről — ez a `Base.metadata.create_all(bind=engine)` hívás során jelenik meg (az app gyökérkönyvtárában futó tesztek is produkálják), nem a kör által bevezetett regresszió.

### Eltérések és okuk

1. **`BigInteger().with_variant(Integer, "sqlite")` a modellekben.** Az SQLite-os box-gate alatt a natív `BigInteger` PK NEM auto-incrementálódik; ez a variáns production-ben (PostgreSQL) natív bigserial-ként viselkedik, a box-gate-en pedig Integer-ként, ami megkapja a SQLite rowid-alapú auto-increment-et. Az ADR 0396 §1-et nem sérti — a típus kanonikus neve `BigInteger`, csak a SQLite-specifikus fallback teszi a tesztelhetőséget lehetővé.

2. **A migráció importálja a modelleket** (`from app.community.models.profile import ...`). A `backend/alembic/env.py` csak `from app import models as _models` hív — ez a meglévő baseline (`User`/`UserSettings`) regisztrálja a `Base.metadata`-ba. Az új Community modellek csak a `community/__init__.py`-n keresztül érhetők el, és az `env.py`-ból nem hívják őket. A `alembic upgrade` parancs a migration scriptet is betölti, így a migráció modul-szintű importjai (amik a modellosztályokat hozzák be) regisztrálják a modelleket a metadata-ba, mielőtt a `compare_metadata` lefutna. Ez a megoldás a scope-őrt nem sérti (a migration file a §4 `allowed_paths` listáján van), és a round-12 migrációs parity-teszt zöld marad.

3. **A `community_privacy_settings` és a `community_profiles` üzleti mezőinek szándékos hiánya.** A `display_name` nullable; a granular privacy-taxonómia (mely mezők publikusak/követőknek/privátak) teljesen hiányzik — ADR 0396 §2 kifejezetten Kör 6+ scope-ra utalja ezeket. A §4 STOP-feltétel is kimondja: „ne bővítsd a community_privacy_settings vagy community_profiles üzleti mezőihez". A jelenlegi séma a minimum-viable struktúra + az 1:1 constraint — pont elég a hét acceptance-kritériumhoz.

4. **A `build_community_router` a `__init__.py`-ban van, nem a `routers/profile.py`-ban.** A `main.py` tilos zóna, így a factory-t a modul határán belül kellett elhelyezni, hogy a teszt-app (és egy jövőbeli `main.py`-bekötés) hívhassa. A `routers/profile.py` csak a tényleges routert exportálja.

5. **A fenti 7 új fájl + a `ruff format`/`ruff check` autófixa.** A 6 formázott fájl listája a `tools/round-gate.sh` 7. lépésének (`backend ruff format`) PIROS kimenetéből kiolvasható; ezek mind a `community/` modul határán belül vannak, és a `ruff format` futtatásával lettek igazítva a projekt stílusához.

6. **`test_downgrade_one_revision_removes_application_schema` kettébontása a két-migrációs valósághoz (H3 self-heal).** A §0.1-ben leírt mért hiba: az eredeti teszt `downgrade -1`-et hívott, és azt várta, hogy a teljes alkalmazásséma (`users`/`user_settings`) eltűnjön — ez 1-migrációs világra íródott. A §0.0 4. pontja szerinti kötelező láncolással (`e09_r02_0002` `down_revision = "e01_r12_0001"`) a `downgrade -1` már CSAK a Community táblákat veszi el. A feloldás: az eredeti teszt két önálló, célzott invariánsra bomlik — (a) `test_downgrade_one_revision_drops_only_community_tables` (`-1` a Community-t veszi el, `users`/`user_settings` marad), és (b) `test_downgrade_to_base_removes_application_schema` (`base`-ig a teljes lánc visszafordul, `users`/`user_settings` is eltűnik). Mindkét teszt zöld; a többi, fájlban lévő teszt (`test_upgrade_head_matches_current_orm_schema`, `test_sqlite_runtime_enforces_foreign_key_cascade`, stb.) változatlan.

### Nem futtatott ellenőrzések és okuk

- **APK build** — ez egy tisztán backend kör (`backend/**` minden érintett fájl); release APK-t nem kell buildelni, és a CI dispatch az orchestrator-oldali teendő (user-szabály, ADR 0052).

- **`/health/ready` Community-ág** — szándékosan NEM történt meg (ADR 0396 §4 + §0.0 3. pont); a `community_readiness_failure` önállóan tesztelt, MA hívó nélküli függvény — a jövőbeli bekötés egy dedikált kör dolga.

- **PR nyitása, squash-merge** — ezek az orchestrator-oldali teendők (ADR 0052), az implementer `gh`-t nem hív (AGENTS.md §15.1).

### Kockázatok és follow-up

1. **`build_community_router` éles bekötése `main.py`-ba.** Ahogy az ADR 0396 §3 és §0.0 2. pontja jelzi, ez egy JÖVŐBELI (GOV-rollout) kör dolga, nem ennek a körnek az acceptance-kritériuma. Az `allowed_paths` tilos zónaként zárja ki a `main.py`-t.

2. **`/health/ready` Community-ág bekötése.** Ugyanez: a `community_readiness_failure` függvény MOST hívó nélküli, önállóan tesztelt komponens; a jövőbeli bekötés a `main.py._readiness_failure` mintát követi majd.

3. **A `community_profiles.display_name` mező Kör 6+ scope.** Az onboarding flow (Kör 6) fogja a `display_name` és a granular privacy-taxonómia mezőket bevezetni — ez a kör csak a struktúrát és a 1:1 constraintet adja.

## 11. Review — a Claude tölti ki
