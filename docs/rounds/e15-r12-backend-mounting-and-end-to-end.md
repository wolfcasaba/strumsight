# E15-R12 — A Community/Gamification backend bekötése és a teljes végponti lefedés

- **Státusz:** PREPARED (előre megírva 2026-08-28, kód olvasva: `main @ 4cb32eb0`)
- **Típus:** Chapter 15 (UI-aktiválás és -befejezés), Kör 12
- **Kör-azonosító:** `E15-R12`
- **Branch:** `<motor>/e15-r12-backend-mounting-and-end-to-end`
- **Előfeltétel:** `E15-R11` merge-elve (a felület kész, tehát a backend-bekötés valódi képernyőkön mérhető)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0469` — a szám FOGLALT (Chapter 15 batch-tartomány).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "backend account login settings sync community tutor end-to-end device"` → **[ADR 0400](../adr/0400-profile-onboarding-service-and-community-gate-ui.md)** (profil-onboarding service és Community gate UI) és **[ADR 0061](../adr/0061-lab-route-isolation-and-hardened-diagnostics.md)** (regisztráció-szintű route-elkülönítés) — a bekötés MINTÁJA adott: a modul a saját flagje mögött, regisztráció szintjén kapcsolódik be.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `backend/app/community/__init__.py` `build_community_router()` docstringjét — az EXPLICIT kimondja, hogy az élő `create_app()`-ba kötés „a future round's job (ADR 0395 Következmények 3. pont)". Ez a kör az a jövőbeli kör. Ellenőrizd, hogy a `main.py` `include_router` sorai időközben nem bővültek.

## 0.0 A MÉRT hiány: a Community API nincs felcsatolva

A `backend/app/main.py` MA **négy** routert regisztrál: `auth`, `settings`, `diagnostics` (flag mögött) és `tutor` (flag mögött). A Community modul **14 routert** hordoz (`backend/app/community/routers/`: profile, handles, social_graph, privacy, feed, posts, bookmarks, search, challenges, leaderboards, reports, safety, moderation) és **20 Alembic migrációt** — de a `build_community_router()` csak a `profile` routert adja vissza, és azt sem hívja senki a production alkalmazásban. Vagyis az Epic 9 teljes szerver-oldali felülete a felhasználó számára MA elérhetetlen; a kliens Community-képernyői ezért maradnak üresek vagy hibásak, akárhogy is néznek ki.

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
- `docs/adr/**` — az ADR 0469-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/main.py` | a Community router és a readiness bekötése |
| `backend/app/community/__init__.py` | a 13 router aggregálása al-flagek szerint |
| `backend/tests/test_community_mounting.py` | a §6 kapu-cellái |
| `backend/tests/test_client_contract_parity.py` | a §6 szerződés-cellái |
| `docs/contracts/client-backend-endpoints.json` | ÚJ — a kliens végpont-listája |
| `docs/operations/device-backend-runbook.md` | ÚJ — eszközös futtatás |

**Tilos zóna:** `backend/alembic/**` · `backend/app/models.py` · `backend/app/community/` egyéb moduljai · `lib/**` · `.github/**` · `docs/adr/**`

## 5. Kötött architekturális döntések (ADR 0469)

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
| A4 | Bekapcsolt modul + migrálatlan séma → `/health/ready` NOT READY | `test_community_mounting.py` |
| A5 | A kliens által hívott MINDEN végpont szerepel az OpenAPI sémában (nincs kliens↔szerver drift) | `test_client_contract_parity.py` |
| A6 | A runbook végigvezet a valódi eszközös futtatáson (indítás → elérhetőség → `STRUMSIGHT_API_URL` → ellenőrző hívás) | `docs/operations/device-backend-runbook.md` |
| A7 | A meglévő backend-tesztek (auth, settings, diagnostics, community unit) VÁLTOZATLANUL zöldek | a §7 backend-futtatás |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A router mindig regisztrálódik, a flag csak 403-at ad | A1 |
| Az aggregátor csak a `profile` routert adja vissza (a mai állapot) | A2 |
| A fő flag minden al-ágat bekapcsol | A3 |
| A readiness nem néz community migrációs fejet | A4 |
| A kliens hív egy végpontot, ami a szerveren nincs (vagy más az útja) | A5 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vegyél ki egy útvonalat a `client-backend-endpoints.json`-ból a szerver oldalán (nevezd át a route-ot), futtasd a backend-cellákat → az **A5** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

Backend sáv (külön processzként):

```bash
cd backend && python -m pytest tests/test_community_mounting.py tests/test_client_contract_parity.py tests/community -q
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
5. `backend/tests/test_community_mounting.py` — a kapu-cellák.
6. `docs/operations/device-backend-runbook.md` + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Túl korán megnyitott felület.** Egy hitelesítés nélküli community-route valódi adatvédelmi incidens (A2).
- **Séma-drift.** A bekötött modul migrálatlan sémán indulna (A4).
- **Kliens↔szerver útvonal-eltérés.** A felület „üres marad" tünete pontosan ebből jön (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
