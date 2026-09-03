# E15-R12 — A Community/Gamification backend bekötése és a teljes végponti lefedés

- **Státusz:** PREPARED (előre megírva 2026-08-28, kód olvasva: `main @ 4cb32eb0`)
- **Típus:** Chapter 15 (UI-aktiválás és -befejezés), Kör 12
- **Kör-azonosító:** `E15-R12`
- **Branch:** `<motor>/e15-r12-backend-mounting-and-end-to-end`
- **Előfeltétel:** `E15-R11` merge-elve (a felület kész, tehát a backend-bekötés valódi képernyőkön mérhető)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** ~~`ADR 0469`~~ → **`ADR 0497`** (lásd §0.0 R1).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "backend account login settings sync community tutor end-to-end device"` → **[ADR 0400](../adr/0400-profile-onboarding-service-and-community-gate-ui.md)** (profil-onboarding service és Community gate UI) és **[ADR 0061](../adr/0061-lab-route-isolation-and-hardened-diagnostics.md)** (regisztráció-szintű route-elkülönítés) — a bekötés MINTÁJA adott: a modul a saját flagje mögött, regisztráció szintjén kapcsolódik be.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `backend/app/community/__init__.py` `build_community_router()` docstringjét — az EXPLICIT kimondja, hogy az élő `create_app()`-ba kötés „a future round's job (ADR 0395 Következmények 3. pont)". Ez a kör az a jövőbeli kör. Ellenőrizd, hogy a `main.py` `include_router` sorai időközben nem bővültek.

## 0.0 Pre-flight revízió (Claude / orchestrátor, 2026-09-03, `main @ 5edd4544`)

A brief 2026-08-28-án készült; az alábbi pontok az indítás előtti ÚJRAMÉRÉS
eredményei. A `brief-lint (strict)` külön leletet nem adott.

**Visszakeresés (ADR 0312, szűkítve → majd teljes korpuszon):**

- `--corpus lessons,halts,adr "community router mounting feature flag registration 404 backend main.py"`
  → **[ADR 0396](../adr/0396-community-backend-module-boundary-and-first-migration.md)**
  (Következmények 3. pont: „a `main.py`-ba való éles router-bekötés … egy
  JÖVŐBELI Epic 9 kör dolga"; A visszavonás feltétele: a `main.py` felvétele
  egy dedikált jövőbeli kör `allowed_paths`-ára a HELYES lépés) és
  **[ADR 0400](../adr/0400-profile-onboarding-service-and-community-gate-ui.md)**
  (Következmények: tételes „router-mounting kör" lista — (a) routerek
  bekötése, (b) E09-R04 F1 TOCTOU, (c) `privacy.py` authz, (d)
  `main.py`/`/health/ready` élesítés). **Ez a kör az (a) és a (d) pontot
  zárja; a (b) és (c) NYITOTT tartozás marad** — azok a
  `backend/app/community/` moduljait írnák át, ami e kör tilos zónája.
- `--corpus lessons,halts "backend contract parity openapi client endpoint drift test"`
  → **L556** (E12-R17): egy leltár teljesség-ellenőrzője akkor is vak marad,
  ha helyesen a fából mér — a MINTAOSZTÁLYOKAT kell teljesnek bizonyítani.
  Alkalmazva az A5-re: lásd R5.
- Teljes korpuszon: nem hozott a fentieken túli releváns előzményt.

**R1 — Az előre kiosztott `0469` szám FOGLALT, a kör ADR-je `0497`.**
Mérve: `docs/adr/0469-outbox-idempotency-is-measured-on-the-ledger-effect.md`
egy MÁR MERGE-ELT döntés, a `0469` tehát nem osztható ki újra (ADR 0087 §4).
A foglaló (`tools/round-slots.py reserve-adr --round E15-R12`) a **`0497`**
számot adta; a kör ADR-je
[`docs/adr/0497-community-router-mounting-and-client-contract-parity.md`](../adr/0497-community-router-mounting-and-client-contract-parity.md),
és a §5 kötött döntései ennek a D1–D5 pontjai.

**R2 — A backend mércéje a `backend-ci.yml`, és RUFF-ot is futtat.**
Mérve: a `.github/actions/flutter-gates` composite (és így a `full-gate.yml`
/ `build-apk.yml`) **egyáltalán nem futtat pytestet**; a backend mércéje a
`.github/workflows/backend-ci.yml`, amely a `backend/**` útvonalra triggerel
és három lépést futtat: `ruff check app tests`, `ruff format --check app tests`,
`pytest -q`. A §7 ezért kiegészül a ruff-sorokkal — enélkül a kör diffje
zöld lokális pytest mellett is pirosra viszi a CI-t.

**R3 — A 13 router prefixei ÁTFEDNEK; a sorrend a szerződés része.**
Mérve (`grep -n "APIRouter(" backend/app/community/routers/*.py`):

| prefix | router-modulok |
|---|---|
| `/community` | `profile`, `feed`, `reports`, `safety`, `social_graph` |
| `/community/profiles` | `search` |
| `/community/bookmarks` · `/community/challenges` · `/community/handles` · `/community/leaderboards` · `/community/moderation` · `/community/posts` · `/community/privacy` | egyenként 1-1 |

FastAPI-ban az ELSŐ illeszkedő route nyer, ezért egy paraméteres útvonal
(`/community/profiles/{handle}`) árnyékolhatja a literált
(`/community/profiles/me`, `profile.py`). Az aggregátor sorrendjét ezért az
ADR 0497 D3 köti meg, és a §6 A8 cellája pinneli.

**R4 — A `build_community_router()` kiterjesztése VISSZAHAT a meglévő
teszt-appra — de a tesztfa TILOS ZÓNA.** Mérve:
`backend/tests/community/conftest.py:77` (`_build_app`) és
`backend/tests/community/test_profile_schema.py:175-194` a factory
visszatérési értékére épül; a kiterjesztés után ez a teszt-app a TELJES
Community felületet kapja. Ezek a fájlok **nincsenek** az `allowed_paths`-on.
Ezért: a `backend/tests/community/**` suite-nak **változatlanul zöldnek kell
maradnia** (A7). Ha nem hozható zöldre a tesztek MÓDOSÍTÁSA nélkül, az a kör
**`stopped` jelzése**, nem a tilos zóna feloldása (H3).

**R5 — Az A4 cella a MAI kóddal triviálisan zöld lenne; élesítve.** Mérve: a
`community_readiness_failure()` a migrációs fejet UGYANARRA az
`alembic.ini`-re méri, mint a `main.py` MÁR MEGLÉVŐ `_readiness_failure()`-je
(`backend/app/main.py:102-111`) — a „migrálatlan séma → NOT READY" tehát ma is
igaz, community-hívás NÉLKÜL, vagyis a cella nem az új viselkedést mérné. Az
A4 ezért a gate ÖNÁLLÓ ágára, a `community_requires_postgres` hibakódra mér
(ADR 0497 D4).

**R6 — Az A5 (L556) csak a MÉRT kliens-hívásokra köt.** A
`docs/contracts/client-backend-endpoints.json` a kliens tényleges hívásaiból
készül; a mai `lib/features/community/data/` MÉRT community-útvonalai:
`/community/profiles/me`, `/community/profiles/{id}/follow|mute|block`,
`/community/profiles/{id}/followers|following`,
`/community/profiles/{owner}/followers/{follower}`,
`/community/follow-requests/{id}/accept|decline`, `/community/blocked`,
`/community/muted`, `/community/challenges` (+ `/{id}`, `/{id}/invites`,
`/{id}/me`, `/{id}/results`, `/invites/{id}[/accept|/decline]`),
`/community/leaderboards/{id}` — az `auth`/`settings`/`diagnostics`
végpontokon felül. A lista NEM kívánságlista: csak a fából mért hívás kerül
bele, és minden bejegyzés mellé kerüljön a forrás (`lib/**` fájl:sor).

**R7 — A `docs/contracts/` és a `docs/operations/` könyvtár LÉTEZIK** (S13
ellenőrizve), az `allowed_paths` tehát valós fákat fed.

**R8 — Párhuzamos kör fut** (`E16-R01`, `sonnet-impl/e16-r01-gamification-composition-layer`).
Az ADR 0495 mérése szerint az `E15-R12` (`backend/**` + docs) **egyetlen
fájlban sem** ütközik vele. A záró rituálék és a merge a merge-záron
(`tools/round-land.sh`) mennek (ADR 0087 §4.1).

## 0.0.1 A MÉRT hiány: a Community API nincs felcsatolva

A `backend/app/main.py` MA **négy** routert regisztrál: `auth`, `settings`, `diagnostics` (flag mögött) és `tutor` (flag mögött). A Community modul **13 routert** hordoz (mérve 2026-09-03; a brief eredetileg 14-et írt, de a felsorolás maga is 13 nevet ad) (`backend/app/community/routers/`: profile, handles, social_graph, privacy, feed, posts, bookmarks, search, challenges, leaderboards, reports, safety, moderation) és **20 Alembic migrációt** — de a `build_community_router()` csak a `profile` routert adja vissza, és azt sem hívja senki a production alkalmazásban. Vagyis az Epic 9 teljes szerver-oldali felülete a felhasználó számára MA elérhetetlen; a kliens Community-képernyői ezért maradnak üresek vagy hibásak, akárhogy is néznek ki.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/main.py",
  "backend/app/community/__init__.py",
  "backend/tests/test_community_mounting.py",
  "backend/tests/test_client_contract_parity.py",
  "docs/contracts/client-backend-endpoints.json",
  "docs/operations/device-backend-runbook.md",
  "docs/rounds/e15-r12-backend-mounting-and-end-to-end.md",
]
gate_tests = [
  "test/app/app_config_test.dart",
  "test/app/config/feature_flags_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a diff a szerver publikus API-felületét bővíti — hitelesítés, adatvédelmi kapuk és moderációs útvonalak kerülnek elérhetővé; egy rosszul kapuzott router hitelesítés nélküli adathozzáférést nyitna. A `security-reviewer` futtatása a review-ban KÖTELEZŐ.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha egy router bekötése séma-változást (ÚJ Alembic migrációt) igényelne, a kimenet a `stopped` jelzés — ez a kör meglévő modult csatol fel, nem sémát módosít.

## 1. Cél

A meglévő Community (és ahol van, Gamification) szerver-oldali felület legyen ténylegesen elérhető a saját flagjei mögött, a kliens által hívott ÖSSZES végpont létezzen, és mindez gépi szerződés-egyezéssel legyen bizonyítva.

## 2. Jelenlegi állapot — mért tények

- `backend/app/main.py:143-184`: `auth`, `settings`, `diagnostics` (ha `diagnostics_enabled`), `tutor` (ha `tutor_enabled`). **Community: nincs.**
- `backend/app/community/routers/` → **13 router-modul**; `build_community_router()` közülük CSAK a `profile`-t adja vissza, és ma egyetlen hívója a teszt-conftest.
- `backend/app/community/__init__.py` `community_readiness_failure()` **létezik**, de a `/health/ready` nem hívja.
- `backend/alembic/versions/`: **20 community migráció** (`e09_r02_0002` … `e09_r27_0020`).
- Kliens-oldalon MÉRT végpont-hívások: `/auth/login`, `/auth/register`, `/auth/me`, `/settings`, `/diagnostics` + a `lib/features/community/data/` repository-k útvonalai.
- `backend/app/config.py`: `community_enabled`, `community_writes_enabled`, `community_media_enabled`, `community_leaderboard_enabled`, `community_clubs_enabled` — mind `False` alapértelmezés.

## 3. Scope

**Benne van:** `build_community_router()` kiterjesztése úgy, hogy a MIND a 13 router-modult egyetlen, prefix-elt `APIRouter`-be aggregálja, al-flagek szerint (írás, média, ranglista, klubok) · a `main.py` bekötése: `if settings.community_enabled: app.include_router(build_community_router(settings))` · a `/health/ready` kiegészítése a `community_readiness_failure()` hívásával, ha a modul be van kapcsolva · `backend/tests/test_community_mounting.py` (flag KI → 404; flag BE → a route-ok léteznek és hitelesítést kérnek; al-flag KI → az adott ág 404/403) · `docs/contracts/client-backend-endpoints.json` (a kliens által hívott végpontok gépi listája) + `backend/tests/test_client_contract_parity.py` (minden listázott végpont szerepel az app OpenAPI sémájában) · `docs/operations/device-backend-runbook.md` (hogyan fut a backend valódi eszközhöz: indítás, elérhetővé tétel, a `STRUMSIGHT_API_URL` beállítása, mit KELL bekapcsolni).

**NINCS benne (tilos):**

- ÚJ Alembic migráció vagy modell-változás.
- `lib/**` módosítás.
- A flagek alapértelmezésének megváltoztatása (a bekapcsolás továbbra is telepítési döntés).
- Valódi deploy vagy titok-kiosztás.
- `docs/adr/**` — az ADR 0497-et a Claude MÁR megírta (§0.0 R1).
- `backend/tests/community/**` és `backend/tests/conftest.py` — a meglévő
  suite-nak MÓDOSÍTÁS NÉLKÜL kell zöldnek maradnia (§0.0 R4); ha nem megy,
  `stopped`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/main.py` | a Community router és a readiness bekötése |
| `backend/app/community/__init__.py` | a 13 router aggregálása al-flagek szerint |
| `backend/tests/test_community_mounting.py` | a §6 kapu-cellái |
| `backend/tests/test_client_contract_parity.py` | a §6 szerződés-cellái |
| `docs/contracts/client-backend-endpoints.json` | ÚJ — a kliens végpont-listája |
| `docs/operations/device-backend-runbook.md` | ÚJ — eszközös futtatás |

**Tilos zóna:** `backend/alembic/**` · `backend/app/models.py` · `backend/app/community/` egyéb moduljai · **`backend/tests/community/**` és `backend/tests/conftest.py`** (§0.0 R4) · `lib/**` · `.github/**` · `docs/adr/**`

## 5. Kötött architekturális döntések ([ADR 0497](../adr/0497-community-router-mounting-and-client-contract-parity.md))

### 5.1 A felcsatolás REGISZTRÁCIÓ-szintű, flag mögött

Kikapcsolt modul esetén a route létre sem jön (404, nem 403) — ez az ADR 0061 mintája. **NEM elfogadható gyengítés:** mindig regisztrált route futásidejű tiltással.

### 5.2 Az al-flagek ÖNÁLLÓAN kapuznak

Az írás, a média, a ranglista és a klubok külön flaget kapnak; a fő flag bekapcsolása nem nyitja meg mindet. **NEM elfogadható gyengítés:** „a `community_enabled` mindent bekapcsol".

### 5.3 A readiness a Community migrációs fejre is mér

Bekapcsolt modul mellett migrálatlan community-séma → NOT READY. **NEM elfogadható gyengítés:** a modul bekapcsolása readiness-ellenőrzés nélkül.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | `community_enabled=false` → a community útvonalak **404**-et adnak (a route nem létezik) | `test_community_mounting.py` |
| A2 | `community_enabled=true` → mind a 13 router útvonalai léteznek, és hitelesítés nélkül **401/403**-at adnak | `test_community_mounting.py` |
| A3 | Al-flag KI (pl. `community_writes_enabled=false`) → az írási ág nem elérhető, az olvasási igen | `test_community_mounting.py` |
| A4 | Bekapcsolt modul + `env=prod` + SQLite (`allow_sqlite_in_prod=true`) → `/health/ready` **503**, `reason == "community_requires_postgres"` (§0.0 R5, ADR 0497 D4) | `test_community_mounting.py` |
| A5 | A kliens által hívott MINDEN végpont szerepel az OpenAPI sémában (nincs kliens↔szerver drift) | `test_client_contract_parity.py` |
| A6 | A runbook végigvezet a valódi eszközös futtatáson (indítás → elérhetőség → `STRUMSIGHT_API_URL` → ellenőrző hívás) | `docs/operations/device-backend-runbook.md` |
| A7 | A meglévő backend-tesztek (auth, settings, diagnostics, community unit) **a fájljaik módosítása NÉLKÜL** zöldek (§0.0 R4) | a §7 teljes backend-futtatás |
| A8 | Az aggregátor sorrendje determinisztikus: `GET /community/profiles/me` a `profile.py` kezelőjéhez megy, NEM a `search.py` paraméteres útvonalához (§0.0 R3, ADR 0497 D3) | `test_community_mounting.py` |
| A9 | A `ruff check` és a `ruff format --check` zöld az `app` és a `tests` fán (§0.0 R2) | a §7 ruff-sorok |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A router mindig regisztrálódik, a flag csak 403-at ad | A1 |
| Az aggregátor csak a `profile` routert adja vissza (a mai állapot) | A2 |
| A fő flag minden al-ágat bekapcsol | A3 |
| A readiness nem hívja a `community_readiness_failure()`-t | A4 |
| A kliens hív egy végpontot, ami a szerveren nincs (vagy más az útja) | A5 |
| Az aggregátor a `search`-öt a `profile` ELÉ regisztrálja (a `/me` literált árnyékolja) | A8 |
| A bekötés töri a meglévő community teszt-appot | A7 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vegyél ki egy útvonalat a `client-backend-endpoints.json`-ból a szerver oldalán (nevezd át a route-ot), futtasd a backend-cellákat → az **A5** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

Backend sáv — a `backend-ci.yml` HÁROM lépése, ugyanabban a sorrendben, külön
processzként (§0.0 R2). A `pytest` a TELJES backend suite-ra megy: az A7 pont
azt méri, hogy a bekötés semmit nem tört el.

```bash
cd backend && python -m ruff check app tests
cd backend && python -m ruff format --check app tests
cd backend && python -m pytest -q
```

A Flutter-oldal érintetlenségének bizonyítéka a gate artefaktumon:

```bash
tools/round-gate.sh test/app/app_config_test.dart test/app/config/feature_flags_test.dart
```

## 8. Implementációs sorrend

1. `docs/contracts/client-backend-endpoints.json` — a kliens MÉRT hívásaiból.
2. `backend/tests/test_client_contract_parity.py` (RED: a community végpontok hiányoznak).
3. `build_community_router()` aggregálás al-flagekkel.
4. `main.py` bekötés + readiness.
5. `backend/tests/test_community_mounting.py` — a kapu-cellák (A1–A4, **A8**).
6. `docs/operations/device-backend-runbook.md` + a valódi-sértés próba a §10-be.
7. A §7 HÁROM backend-parancsa (ruff check, ruff format --check, pytest -q) —
   a `pytest -q` a TELJES suite-on, az A7 bizonyítékaként.

## 9. Kockázatok

- **Túl korán megnyitott felület.** Egy hitelesítés nélküli community-route valódi adatvédelmi incidens (A2).
- **Séma-drift.** A bekötött modul migrálatlan sémán indulna (A4).
- **Kliens↔szerver útvonal-eltérés.** A felület „üres marad" tünete pontosan ebből jön (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
