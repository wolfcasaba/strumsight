# E09-R03 — Public identity és handle policy

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 3
- **Kör-azonosító:** `E09-R03`
- **Branch:** `<motor>/e09-r03-public-identity-and-handle-policy`
- **Előfeltétel:** `E09-R02` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0397` — a szám FOGLALT (Epic 9 batch-tartomány 0395-0419). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 2-ben létrejött `community_profiles` tábla TÉNYLEGES oszlopneveit és a `backend/app/community/schemas/profile.py` séma-mezőit. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

## 0.0 Pre-flight brief-revízió (Claude, 2026-08-22, ADR 0397)

**§2 mért ellenőrzés — a `community_profiles`/`profile.py` állítások PONTOSAK.**
`backend/app/community/models/profile.py` ma valóban a Kör 2 minimál sémáját
hordozza (`id` BigInteger/Integer-variant PK, `public_id` `Uuid(as_uuid=True)
unique=True nullable=False`, `user_id`, `display_name`, `created_at`) —
kézzel grep-elve, nincs `handle` mező és nincs `policies/`/`services/`
alkönyvtár a `backend/app/community/` fában. A §6.1 mérce-mátrix (A1: nyers
oszlop indexelése, A2: `id` bigint stringgé alakítva) a ma élő sémán
reprodukálható állapotot ír le.

**§2 pontosítás (kisebb, nem gate-hordozó):** a "Pydantic `field_validator`"
konvenció-hivatkozás útvonala hibás — `backend/app/schemas/auth.py` NEM
létezik, a minta ténylegesen `backend/app/schemas.py`-ban van
(`UserCreate._reject_passwords_over_bcrypt_byte_limit`, sor 34). A minta maga
(egy `@field_validator` + `@classmethod`, `ValueError`-t dobó normalizáló
metódus) érvényes referencia a handle-validációhoz, csak a fájlnév téves;
mivel egyik acceptance-cella sem hivatkozik erre az útvonalra, ez §0.0-jegyzet,
nem blokkoló javítás.

**Visszakeresés (ADR 0312, szűkítve → teljes korpusz):** `lessons/L295`
("A publikus policy-mező constructor-validációja nem bizonyítja, hogy a mező
vezérli a viselkedést", emb#1) közvetlenül releváns — a `handle_policy.py`
normalizáló/validáló mezőihez a §7 gate mellé legalább egy nem-default,
tényleges hívási utat olvasó unit-cella kell (nem csak konstruktor-validáció),
ezt a §6 A1/A4 cellák már mérik, de az implementer-promptban explicit
hivatkozom rá. `adr/0396` (Kör 2 modulhatár — a `from_attributes=True` teljes
ORM-lekérdezés elleni whitelist-mintát ez a kör is követi az availability
válaszban). A konkurens-claim SQLite-race témára (A5) nincs közvetlen találat
sem szűkített, sem teljes korpuszon — a §6.1 valódi-sértés próba és a §8 6.
lépés (DB-constraint, nem app-szintű lock) pótolja az előzmény hiányát.

**Kockázat = high, indoklás:** a `risk = "high"` a brief eredeti besorolása
szerint marad, bár egyik `allowed_paths` sem egyezik szó szerint a router
`high_risk_path_fragments` listájával (auth, authorization, camera,
credential, crypto, encryption, migration, payment, privacy, secret, share,
upload, vision). Az indok tartalmi: ez a kör az első publikusan
kereshető/felfedhető identitás-felület (public handle) — egy Unicode-collision
gyengeség impersonation-vektor (két látszólag azonos handle közül az egyik
más felhasználót adhat ki magát), az availability endpoint pedig egy
tervezési hiba esetén regisztrált userek enumerálására használható
felderítő-csatorna válna (ez funkcionálisan azonos súlyú, mint egy
`privacy`/`credential`-fragmensű útvonal, csak a fájlnévben nem jelenik meg
szó szerint). A `backend/alembic/versions/e09_r03_0003_community_handle.py`
maga is sémamódosítás (unique index + új tábla) éles adatbázison. Ezt a §6.1
kötelező valódi-sértés próba (A1-re) és az A5 konkurens-claim race-teszt fogja
gépi mércével.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/policies/handle_policy.py",
  "backend/app/community/services/identity_service.py",
  "backend/app/community/models/handle_history.py",
  "backend/app/community/routers/handles.py",
  "backend/alembic/versions/e09_r03_0003_community_handle.py",
  "backend/tests/community/test_handle_policy.py",
  "docs/rounds/e09-r03-public-identity-and-handle-policy.md",
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

Implementáld a biztonságos publikus identitást: injektálható UUID-generátor, Unicode-normalizált handle egyediséggel, reserved/blocked handle policy, handle-change cooldown és rövid redirect-ablakos history.

## 2. Jelenlegi állapot — mért tények

- `community_profiles.public_id` (Kör 2) MA `UUID UNIQUE NOT NULL`, de nincs generátor-absztrakció és nincs handle-mező
- `backend/app/community/models/profile.py` a Kör 2 minimál sémáját hordozza — a handle és a history tábla ÚJ ebben a körben
- a projekt konvenciója a Pydantic `field_validator` (lásd `backend/app/schemas/auth.py`-szerű minták) — a handle-validáció ugyanezt a mintát követi

## 3. Scope

**Benne van:** injektálható public UUID generátor · Unicode-normalizálás, case-folding, hossz- (3–24) és karaktervalidáció · reserved/blocked handle katalógus · adatbázis-szintű egyediség a normalizált handle-re · availability endpoint rate limittel (nincs tömeges enumerációs API) · handle-change cooldown + handle history rövid redirect-ablakkal.

**NINCS benne (tilos):**

- E-mailből automatikus handle-generálás.
- A `users` tábla vagy az auth réteg módosítása.
- Profil egyéb mezőinek (bio, avatar) bevezetése — Kör 4/8.
- `docs/adr/**` — az ADR 0397-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/policies/handle_policy.py` | ÚJ — normalizálás + reserved lista |
| `backend/app/community/services/identity_service.py` | ÚJ — UUID generátor + handle-váltás |
| `backend/app/community/models/handle_history.py` | ÚJ — handle history tábla |
| `backend/app/community/routers/handles.py` | ÚJ — availability endpoint |
| `backend/alembic/versions/e09_r03_0003_community_handle.py` | ÚJ — handle oszlop + history migráció |
| `backend/tests/community/test_handle_policy.py` | ÚJ — a §6 cellái |

**Tilos zóna:** `backend/app/community/models/profile.py` a handle-oszlop hozzáadásán kívül más mezők bevezetése · `backend/app/` a Community-n kívül · `lib/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0397)

### 5.1 A handle NORMALIZÁLT egyediségen áll, nem a nyers stringen

Az egyediség Unicode-normalizált (NFKC) + case-folded formán kényszerített adatbázis-szinten (unique index a normalizált oszlopon), NEM alkalmazás-szintű, race-hajlamos ellenőrzésen.

**NEM elfogadható gyengítés:** egy alkalmazás-szintű "nézd meg, foglalt-e, majd írd be" mintázat külön adatbázis-constraint nélkül — ez pontosan az az O_EXCL-hiányzó verseny, amit a projekt az ADR-foglaláson már megmért.

### 5.2 A publikus ID stabil és nem kitalálható

Az UUID-generátor injektálható (teszthez determinisztikus), de production-ben kriptográfiailag nem-kitalálható forrásból jön — SOSEM szekvenciális integer vagy annak string-alakja.

### 5.3 Az availability API NEM enumerációs eszköz

A handle-elérhetőség lekérdezése rate-limitált és egyetlen handle-t kérdez le egyszerre — nincs tömeges/prefix-listázó végpont, ami regisztrált userek listáját szivárogtatná.

**NEM elfogadható gyengítés:** egy "kényelmi" batch-availability endpoint, ami N handle-t fogad egy hívásban — ez a rate limitet megkerülő enumerációs csatorna.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Két vizuálisan/normalizáltan azonos handle nem foglalható le | `test_handle_policy.py` — Unicode collision property teszt |
| A2 | A public ID stabil és nem kitalálható szekvenciális integer | `test_handle_policy.py` |
| A3 | Az availability API nem ad érzékeny account információt és rate-limitált | `test_handle_policy.py` |
| A4 | Reserved/blocked handle nem regisztrálható | `test_handle_policy.py` |
| A5 | Concurrent handle-claim csak az egyik felet engedi át | `test_handle_policy.py` — race teszt |
| A6 | Handle-change cooldown érvényesül; a régi handle rövid ideig redirectel | `test_handle_policy.py` |
| A7 | E-mailből nem keletkezik automatikus nyilvános handle | `test_handle_policy.py` — regresszió |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A normalizálás csak a UI-ban fut, az adatbázis nyers stringet indexel | A1 |
| A public ID az `id` bigint stringgé alakítva | A2 |
| Az availability endpoint listát fogad egy hívásban | A3 |
| A reserved-lista üres vagy nem ellenőrzött regisztrációkor | A4 |
| Két konkurens kérés mindkettő sikeres ugyanarra a normalizált handle-re | A5 |
| A cooldown nincs ellenőrizve, a handle azonnal újra váltható | A6 |

**A küszöb három kötelező cellája** (a handle hossza (3–24 karakter, a §8.2 szerint)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | `"ab"` (2 karakter) | elutasítva — `ArgumentError`/`ValidationError` |
| **rajta** (a küszöbön) | `"abc"` (pontosan 3) ÉS egy pontosan 24 karakteres handle | MINDKETTŐ elfogadva — a határ inkluzív mindkét oldalon |
| a küszöb **fölött** | `"a" * 25` (25 karakter) | elutasítva |

A hármas tömören: **alatt** → elutasít · **rajta** → elfogad (mindkét szélső érték) · **fölött** → elutasít.

A határ a `[3, 24]` zárt intervallumhoz tartozik — mindkét szélső érték legitim.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** cseréld a normalizált-oszlop unique indexet a nyers `handle_display` oszlopra, futtasd a backend pytest-et → az **A1** Unicode-collision cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/architecture_dependency_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_handle_policy.py -q
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

1. `identity_service.py` — injektálható UUID-generátor.
2. `handle_policy.py` — NFKC-normalizálás, case-fold, hossz- és karakterellenőrzés, reserved lista.
3. Alembic migráció: `handle_normalized` unique index + `community_handle_history` tábla.
4. `handles.py` router — availability endpoint rate limittel.
5. Handle-change cooldown + history redirect-ablak.
6. Concurrent-claim regressziós teszt (DB constraint, nem app-szintű lock).
7. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **Az alkalmazás-szintű egyediség-ellenőrzés.** Verseny esetén két user ugyanazt a handle-t kapja meg — az adatbázis-constraint az egyetlen megbízható védelem (A5).
- **Az e-mail-eredetű automatikus handle.** A kényelem csábító, de a §3.1 kifejezetten tiltja — az e-mail sosem válhat nyilvános azonosítóvá (A7).
- **A batch-availability endpoint.** Egy "UX-javító" tömeges lekérdezés user-enumerációs csatornává válik (A3).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
