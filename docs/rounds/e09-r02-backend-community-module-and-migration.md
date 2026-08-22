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

## 11. Review — a Claude tölti ki
