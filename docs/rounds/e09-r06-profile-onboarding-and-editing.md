# E09-R06 — Profil létrehozás, szerkesztés és Community gate UI

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 6
- **Kör-azonosító:** `E09-R06`
- **Branch:** `<motor>/e09-r06-profile-onboarding-and-editing`
- **Előfeltétel:** `E09-R05` merge-elve
- **Brief szerzője:** Claude (Opus 5); pre-flight revízió: Claude Sonnet 5 (E09-R06 pipeline, 2026-08-22)
- **Előre kiosztott ADR:** `ADR 0400` — a szám FOGLALT (`tools/round-slots.py reserve-adr`). A brief eredeti "nincs" besorolása a pre-flight méréssel megdőlt — lásd §0.0.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 5-ben lefektetett `public.dart` TÉNYLEGES export-listáját és a `lib/features/auth/public.dart` mintáját — a Community gate ugyanúgy épül, mint az `accountEnabledProvider`-re épülő auth-gate. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

> 🛑 **§0.0 brief-revízió (KÖTELEZŐ elolvasni INDÍTÁS ELŐTT) — lásd lent a "0.0 Pre-flight revízió" szakaszt.** A backend `allowed_paths` és a §2/§3/§4/§5 SZŰKEN bővült: a Kör 6-nak MÁR ADR 0396-ban kiosztott service-szintű profil-létrehozás mégis ebbe a körbe tartozik (nem "tisztán UI/integráció").

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/community/data/repositories/profile_repository_impl.dart",
  "lib/features/community/data/dto/profile_dto.dart",
  "lib/features/community/application/controllers/profile_controller.dart",
  "lib/features/community/presentation/screens/community_gate_screen.dart",
  "lib/features/community/presentation/screens/edit_profile_screen.dart",
  "lib/features/community/domain/repositories/community_profile_repository.dart",
  "lib/l10n/features/community_en.arb",
  "lib/l10n/features/community_hu.arb",
  "test/features/community/presentation/community_gate_test.dart",
  "test/features/community/presentation/profile_onboarding_test.dart",
  "backend/app/community/services/profile_service.py",
  "backend/app/community/schemas/profile.py",
  "backend/app/community/routers/profile.py",
  "backend/tests/community/conftest.py",
  "backend/tests/community/test_profile_service.py",
  "docs/adr/0400-profile-onboarding-service-and-community-gate-ui.md",
  "docs/rounds/e09-r06-profile-onboarding-and-editing.md",
]
gate_tests = [
  "test/features/community/presentation/community_gate_test.dart",
  "test/features/community/presentation/profile_onboarding_test.dart"
]
native_gate = false
```

**Kockázat = high, indoklás:** a `risk = "high"` a brief eredeti
besorolása szerint marad, és a pre-flight bővítés MEGERŐSÍTI, nem
gyengíti: az `allowed_paths` egyik útvonala sem egyezik szó szerint a
router `high_risk_path_fragments` listájával (auth, authorization,
camera, credential, crypto, encryption, migration, payment, privacy,
secret, share, upload, vision), de a kör tartalmilag **hitelesített
(auth-mögötti), írási HTTP-felületet nyit** — az ELSŐ Community backend
végpont, ami `INSERT`-et végez, és az ELSŐ, ami a megosztott
`CurrentUser`/`DbSession` auth-láncot (`app.deps`) használja a Community
modulban. Egy hibás uniqueness-kezelés vagy egy hiányzó auth-ellenőrzés
más felhasználó profilját hozhatná létre/módosíthatná — ezért a
független review mellett **dedikált biztonsági review kötelező**
(`security-reviewer` agent, a `.ai/router.toml` `high_risk_path_fragments`
szerinti automatikus triggerelés helyett explicit dispatch, mert egyik
fájlnév sem egyezik szó szerint).

## 0.0 Pre-flight brief-revízió (orchestrátor, Claude Sonnet 5, 2026-08-22, `main @ d6b006c8`)

**Mért tény (§1 "elérhetetlen cél-státusz" ellenőrzés):** a brief eredeti
§2 azt állította, hogy ez a kör "az ELSŐ, ami ténylegesen HTTP-n keresztül
hívja" a Kör 3/4 backend policy-kat, `backend/**`-et pedig teljes egészében
tilos zónának jelölte. `grep -rn "INSERT INTO community_profiles"
backend/` **nulla** találatot ad — nincs egyetlen backend endpoint sem, ami
`community_profiles` sort létrehozna; `identity_service.assign_handle`
egy MEGLÉVŐ `profile_id`-re `UPDATE`-el, nem `INSERT`-tel. A
`CommunityProfileRepository` (Kör 5, domain) sem tartalmaz
`create`/`update` metódust.

Ez NEM hiányzó dokumentáció, hanem egy MÁR MERGE-ELT ADR explicit,
névvel kiosztott következménye: `docs/adr/0396-…md` "Következmények" —
*"A Kör 6 (onboarding, explicit profil-létrehozás) a `community_profiles`
sor tényleges service-szintű létrehozását adja."* A batch-elt E09-R06
brief (PR #405) ezt nem vitte tovább az `allowed_paths`-ba. Ugyanaz az
ADR 0396 bekezdés és az E09-R04 review F1/N2 lelete (`docs/reviews/
e09-r04-review.md`) EGYÜTT azt is rögzíti, hogy a `main.py`/
`build_community_router` élő bekötése (router-mounting) **külön, még ki
nem osztott kör** feladata marad — ezt a kört ez a revízió NEM vonja be.

**Visszakeresett előzmény (ADR 0312, §4.9):**

```
node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "profile onboarding create endpoint missing backend not mounted"
node tools/knowledge-rag.mjs --corpus lessons,halts --top 5 "router not mounted into create_app deferred future round scope gap"
```

Releváns találatok: `adr/0396` §"Következmények" (Kör 6 service-szintű
létrehozás felelőssége — a fenti mért tény forrása); `adr/0397`/`0398`
Kontextus-szakaszai (ugyanaz a "mérd ki a tényleges kódot, ne az
átmenettáblát" minta, amit ez a revízió is követ); `halts/round-status-
E09-R04` — *"review APPROVED 0 BLOCKER/MAJOR, 2 MINOR deferred to
router-mounting round"* — megerősíti, hogy a bekötés egy elkülönült,
elismerten még ki nem osztott jövőbeli feladat, NEM ennek a körnek a
része. Nincs releváns korábbi HALT erre a konkrét mintára (első
előfordulás).

**A döntés — ADR 0400 (lásd a fájlt: `docs/adr/0400-…md`) — teljes
indoklással.** Összefoglalva:

1. `backend/**` a tilos zónából **szűken, öt névvel megadott fájlra**
   kikerül (lásd az `ai-router` blokk `allowed_paths`-át fent) — a
   service-szintű profil-létrehozás/-szerkesztés, amit ADR 0396 MÁR
   ennek a körnek szánt.
2. `backend/app/main.py`, `backend/app/community/__init__.py` és
   BÁRMILYEN `alembic/versions/**` **változatlanul tilos zóna** — a
   router-mounting és bármilyen új DB-migráció egy külön kör dolga marad.
3. `bio`/`skillInterests`/`badges`/`avatarUrl` ebben a körben **UI-only**
   marad (nincs backend oszlop rájuk, nincs migráció ebben a körben) — a
   form megjeleníti és megőrzi őket (A3 ezekre a mezőkre IS vonatkozik),
   de a Dio-hívás nem küldi el őket.
4. `CommunityProfileRepository` (Kör 5, domain, tilos zóna) a "bővítés
   indokolt esettel" kivétellel bővül: `createProfile`/`updateProfile` +
   két domain-kivétel (`ProfileAlreadyExistsException`,
   `HandleTakenException`).
5. Az ÚJ backend végpontok (`POST`/`PUT /community/profiles/me`) a
   megosztott `CurrentUser`/`DbSession` (`app.deps`) mintát használják
   (mint `backend/app/routers/settings.py`), NEM a router saját
   `_session_factory` hídját — a MEGLÉVŐ `ping`/`read_profile` végpontok
   érintetlenek maradnak.

A pontos service-szerződést (`create_profile`/`update_profile` vázlat,
hibafordítási tábla, tranzakció-sorrend) az ADR 0400 §2–3 tartalmazza —
az implementer AZT követi, nem ismétlem meg itt szó szerint.

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

Adj a felhasználónak kontrollált módot a közösségi profil létrehozására és szerkesztésére: disabled/logged-out/profile-missing/ready állapotú gate, handle-debounce, és a privacy beállítás mint a flow explicit lépése.

## 2. Jelenlegi állapot — mért tények

- A Kör 3 backend handle-policy és a Kör 4 access-policy MÁR élesek MODULON BELÜL, de EGYIK router (`handles.py`, `privacy.py`) sincs bekötve `build_community_router`-be — csak a saját, önálló tesztjeik hívják őket. `backend/app/community/routers/profile.py` MA csak `GET /community/ping` és `GET /community/profiles/{public_id}`-t ad; **nincs egyetlen backend endpoint sem, ami `community_profiles` sort létrehozna** (`grep -rn "INSERT INTO community_profiles" backend/` → 0 találat). Ez a kör az ELSŐ, ami service-szinten ténylegesen ÍR — lásd §0.0 és ADR 0400.
- `lib/features/auth/public.dart` `accountEnabledProvider`-t exportál — a Community gate erre épül, ugyanazzal a mintával, mint a `settings_sync.dart`
- a projekt konvenciója: repository-provider minta, Preview/in-memory repo a logged-out/mock-mode úthoz
- `CommunityProfileRepository` (Kör 5) MA nem tartalmaz create/update metódust — ez a kör bővíti (§0.0 4. pont)

## 3. Scope

**Benne van:** Community belépő gate: disabled, logged-out, profile-missing, ready állapot · profile repository Dio implementáció a közös API klienssel · handle availability debounced ellenőrzés + lokális validáció · profil létrehozó/szerkesztő képernyő (avatar placeholder, display name, bio, interest tag — bio/interest UI-only, §0.0 3. pont) · a privacy beállítás mint a létrehozó flow explicit lépése · logoutkor a Community személyes cache és pending draft törlése policy szerint · **backend service-szintű profil-létrehozás/-szerkesztés** (`profile_service.py`, `POST`/`PUT /community/profiles/me`, ADR 0400 §2–3) — ADR 0396 által MÁR ennek a körnek kiosztott felelősség.

**NINCS benne (tilos):**

- Follow, block, feed vagy poszt UI — Kör 7+.
- Média (avatar) tényleges feltöltése — Kör 18 mögötti feature flag.
- `backend/app/main.py`, `backend/app/community/__init__.py` (router-mounting, `/health/ready` bekötés — külön, még ki nem osztott kör, ADR 0396 "Következmények" + E09-R04 review F1/N2).
- BÁRMILYEN `alembic/versions/**` (új migráció — nincs ebben a körben, §0.0 3. pont).
- `backend/app/community/policies/**`, `backend/app/community/services/identity_service.py` (Kör 3, importálható, NEM módosítható).
- `docs/sdd/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/community/data/repositories/profile_repository_impl.dart` | ÚJ — Dio implementáció |
| `lib/features/community/data/dto/profile_dto.dart` | ÚJ — DTO mapping |
| `lib/features/community/application/controllers/profile_controller.dart` | ÚJ — Riverpod controller |
| `lib/features/community/presentation/screens/community_gate_screen.dart` | ÚJ |
| `lib/features/community/presentation/screens/edit_profile_screen.dart` | ÚJ |
| `lib/features/community/domain/repositories/community_profile_repository.dart` | BŐVÍTÉS — `createProfile`/`updateProfile` + 2 domain-kivétel (Kör 5 tilos zóna, "bővítés indokolt esettel", §0.0 4. pont) |
| `lib/l10n/features/community_en.arb` | ÚJ — a Community szöveges szegmens (ADR 0307 §4) |
| `lib/l10n/features/community_hu.arb` | ÚJ — magyar parity |
| `test/features/community/presentation/community_gate_test.dart` | ÚJ — a §6 cellái |
| `test/features/community/presentation/profile_onboarding_test.dart` | ÚJ |
| `backend/app/community/services/profile_service.py` | ÚJ — `create_profile`/`update_profile` (ADR 0400 §2–3) |
| `backend/app/community/schemas/profile.py` | BŐVÍTÉS — `CommunityProfileCreate`/`CommunityProfileUpdate` request-sémák |
| `backend/app/community/routers/profile.py` | BŐVÍTÉS — `POST`/`PUT /community/profiles/me`, `CurrentUser`/`DbSession` (ADR 0400 §6); a MEGLÉVŐ `ping`/`read_profile` érintetlen |
| `backend/tests/community/conftest.py` | BŐVÍTÉS — auth-header/test-user fixture az ÚJ végpontokhoz |
| `backend/tests/community/test_profile_service.py` | ÚJ — service + endpoint tesztek |
| `docs/adr/0400-profile-onboarding-service-and-community-gate-ui.md` | ÚJ — ez a pre-flight döntés |

**Tilos zóna:** `lib/features/community/domain/**` a fenti EGY bővített fájl kivételével (Kör 5 lezárt szerződése) · `lib/features/` más feature-je · `lib/l10n/app_{en,hu}.arb` (a generált aggregátum, nem kézzel szerkesztendő) · `lib/core/**` · `docs/adr/**` az ADR 0400 kivételével · `tools/**` · `.github/**` · `backend/app/main.py` · `backend/app/community/__init__.py` · BÁRMILYEN `alembic/versions/**` · `backend/app/community/policies/**` · `backend/app/community/services/identity_service.py` · `backend/**` bármely más fájlja a §4 táblán kívül

## 5. Kötött architekturális döntések

### 5.1 Community profil KIZÁRÓLAG explicit user actionre készül

A gate 4 állapota (disabled/logged-out/profile-missing/ready) sosem hoz létre implicit profilt — a `ready` állapotba csak a user saját, explicit létrehozó műveletén át kerülhet.

**NEM elfogadható gyengítés:** egy "gyorsítás" a bejelentkezés után automatikus profil-létrehozással, alapértelmezett handle-lel — ez pontosan az implicit megosztás elleni SDD-invariánst sértené.

### 5.2 A privacy beállítás a flow EXPLICIT lépése, nem utólagos beállítás

A létrehozó flow megállítja a felhasználót a privacy-választásnál; az alapérték `private`/`followers`, nem `public`.

### 5.3 A backend service a `user_id` UNIQUE constraint-re épít, nem csak egy előzetes SELECT-re (ADR 0400 §2)

`create_profile` egy előzetes olvasó ellenőrzést ad barátságos 409-hez, de
a VÉGSŐ enforcement a `commit_with_uniqueness_check` `IntegrityError`
fordítása — ugyanaz a "nincs check-then-insert anti-pattern mint egyetlen
védelmi vonal" elv, amit `identity_service.assign_handle` már követ
(ADR 0397 §5.1). Egy implementáció, ami KIZÁRÓLAG a SELECT-re
támaszkodik (nincs `try`/`except IntegrityError` a commit körül), NEM
felel meg — ezt az A8 méri.

### 5.4 Az ÚJ végpontok a hívó SAJÁT `user_id`-jára írnak, sosem a payloadéra

`POST`/`PUT /community/profiles/me` a `CurrentUser` (`app.deps`) által
feloldott `user.id`-t használja — a payload NEM tartalmazhat
`user_id`/`profile_id` mezőt (`extra="forbid"` a `CommunityProfileCreate`/
`CommunityProfileUpdate` sémán, a `PrivacySettingsUpdate` mintája). Egy
payload-ból olvasott `user_id` lehetővé tenné, hogy A hívó B profilját
hozza létre/módosítsa — ezt a biztonsági review méri.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Community profil csak explicit user actionre készül | `profile_onboarding_test.dart` |
| A2 | A privacy alapérték látható és módosítható a flow-ban | `profile_onboarding_test.dart` |
| A3 | Hálózati hiba nem veszti el a kitöltött profilt | `profile_onboarding_test.dart` — retry cella |
| A4 | Logged-out és feature-disabled gate helyesen jelenik meg | `community_gate_test.dart` |
| A5 | Handle debounce és dupla submit blokkolva | `profile_onboarding_test.dart` |
| A6 | Logoutkor a Community cache törlődik | `community_gate_test.dart` |
| A7 | 2.0 text scale mellett nincs kritikus overflow | `profile_onboarding_test.dart` — golden |
| A8 | A backend `create_profile` a DB-szintű `user_id`/`handle_normalized` uniqueness-re támaszkodik, nem csak egy előzetes SELECT-re; és a payload `user_id`/`profile_id` mezőt `extra="forbid"`-dal elutasítja | `backend/tests/community/test_profile_service.py` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A profil a bejelentkezés után automatikusan létrejön | A1 |
| A privacy-választás lépés kihagyható, alapérték `public` | A2 |
| Hálózati hiba a beírt szöveget törli | A3 |
| A dupla tap két profilt hoz létre | A5 |
| Logout után a régi user profilja megjelenik a cache-ből | A6 |
| Két egyidejű `POST /community/profiles/me` hívás (azonos userrel) mindkettő 2xx-et kap, két profil-sor jön létre | A8 |
| A payload egy `user_id` mezőt tartalmazhat, ami felülírja a `CurrentUser`-t | A8 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki a submit-gomb debounce/disable logikáját, futtasd a gate-et → az **A5** dupla-submit cellának PIROSNAK kell lennie → állítsd vissza. **MÁSODIK valódi-sértés próba (backend, KÖTELEZŐ, §10-ben dokumentálva):** vedd ki a `commit_with_uniqueness_check` `try`/`except IntegrityError` ágát (hagyj csupasz `db.commit()`-et) → az **A8** "két egyidejű hívás" cellának PIROSNAK kell lennie (500 vagy adatvesztés, nem 409) → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/presentation/community_gate_test.dart test/features/community/presentation/profile_onboarding_test.dart
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

**A `tools/round-gate.sh` a backend sávot ÖNMAGÁTÓL bekapcsolja**, mihelyt
a `backend/` fában bármi módosul (`backend_touched()` — git status/diff
alapú detekció) — a fenti parancs NEM változik attól, hogy ez a kör most
backend fájlokat is érint, a backend pytest sáv automatikusan lefut
ugyanazon hívás részeként. Az implementer `backend/tests/community/
test_profile_service.py`-t a `pytest backend/tests -q` teljes sávval
futtatja le maga is a commit előtt (ugyanaz a venv-fallback mint a
`tools/round-gate.sh` belsejében).

## 8. Implementációs sorrend

1. **Backend:** `profile_service.py` — `create_profile`/`update_profile` (ADR 0400 §2–3), `IntegrityError` fordítás.
2. **Backend:** `schemas/profile.py` bővítés — `CommunityProfileCreate`/`CommunityProfileUpdate` (`extra="forbid"`).
3. **Backend:** `routers/profile.py` bővítés — `POST`/`PUT /community/profiles/me`, `CurrentUser`/`DbSession`.
4. **Backend:** `conftest.py` auth fixture + `test_profile_service.py` (A8 + a második valódi-sértés próba).
5. **Flutter domain:** `community_profile_repository.dart` bővítés — `createProfile`/`updateProfile` + 2 kivétel.
6. `profile_repository_impl.dart` — Dio implementáció a Kör 3 handle és az ÚJ Kör 6 profil-create/update endpointokra (NEM a `handles.py`/`privacy.py` külön routerekre — azok nincsenek bekötve).
7. `profile_controller.dart` — állapotgép (disabled/logged-out/profile-missing/ready).
8. `community_gate_screen.dart` — a négy állapot UI-ja.
9. `edit_profile_screen.dart` — handle debounce, validáció, privacy-lépés, bio/interest UI-only mezők.
10. Logout cache-cleanup.
11. ARB szegmens (`community_en/hu.arb`).
12. A KÉT valódi-sértés próba §10-be.

## 9. Kockázatok

- **Az implicit profil-létrehozás "UX-gyorsításként".** Ez a legfontosabb invariáns ebben a körben (A1).
- **A privacy-lépés kihagyhatósága.** Egy `Skip` gomb alapértelmezett public audience-t eredményezne (A2).
- **A dupla submit.** Gyors, kettős tap két HTTP hívást indíthat; a DB-szintű `user_id`/`handle_normalized` uniqueness (§5.3, A8) a végső védelmi vonal, a kliens-oldali debounce (A5) a UX-vonal — mindkettő szükséges, egyik sem elég önmagában.
- **Auth-scoping hiba.** Egy `user_id` a payloadból (nem a `CurrentUser`-ből) lehetővé tenné, hogy A hívó B profilját írja (§5.4, A8) — ezért dedikált biztonsági review kötelező (fejléc "Kockázat = high" indoklás).
- **A router-mounting-függő funkciók (privacy utólagos módosítása, handle-változtatás) hiánya.** Az edit-képernyő ezért NEM kínál privacy-újraválasztást vagy handle-changet — ez egy jövőbeli, még ki nem osztott kör dolga (ADR 0400 "Következmények").

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
