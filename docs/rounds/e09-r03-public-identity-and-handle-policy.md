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
  "backend/tests/test_migrations.py",
  "backend/tests/community/test_profile_schema.py",
  "docs/rounds/e09-r03-public-identity-and-handle-policy.md",
]
gate_tests = [
  "test/core/architecture_dependency_test.dart"
]
native_gate = false
```

## 0.1 Self-heal brief-revízió (ADR 0112, halt H3, 2026-08-22)

**Visszakeresett előzmény:** `docs/LESSONS.md` L411 — ugyanez a halt-osztály
(migráció-láncoló kör, cross-round teszt az `allowed_paths`-on kívül) az
E09-R02 self-heal-jében; ez a kör pontosan ugyanaz a minta EGY LÁNCSZEMMEL
MÉLYEBBEN, ezért L413 néven, a lánc-toleráns javítási utasítással bővítve
kerül a leckék közé.

**Amit az implementer helyesen jelzett `stopped`-ként (§10.4):** a kör saját
migrációja (`e09_r03_0003.down_revision = "e09_r02_0002"`) törvényszerűen
törte KÉT, E09-R02-ben írt cross-round tesztet, mert azok egy
két-migrációs világot feltételeztek. Ez az L411 lecke (E09-R02 self-heal,
ugyanez a halt-osztály) EGY LÁNCSZEMMEL MÉLYEBBEN — mért, reprodukálva,
lásd `docs/LESSONS.md` L413.

**A fenti `allowed_paths` MOST tartalmazza mindkét fájlt** —
`backend/tests/test_migrations.py` és
`backend/tests/community/test_profile_schema.py`. A folytatáshoz a
felfüggesztett implementer-motor (minimax, munkapéldány
`/home/ubuntu/ss-mm-e09-r03`, branch
`minimax/e09-r03-public-identity-and-handle-policy`, HEAD `3cca3ddd`)
resume-olva a KÖVETKEZŐ három hibát javítja — **chain-toleránsan**, hogy az
Epic 9 hátralévő ~29 köre ne ismételje ugyanezt minden migrációnál:

1. `backend/tests/community/test_profile_schema.py::test_alembic_upgrade_head_applies_community_migration`
   — a `assert set(script_heads) == {"e09_r02_0002"}` sort cseréld egy
   ANCESTOR-ellenőrzésre (NEM egy újabb hardcoded head-stringre):
   ```python
   config = _alembic_config()
   script_dir = ScriptDirectory.from_config(config)
   heads = script_dir.get_heads()
   assert len(heads) == 1, f"single-head chain required, got {heads}"
   ancestors = {rev.revision for rev in script_dir.walk_revisions(heads[0], "base")}
   assert "e09_r02_0002" in ancestors, (
       "e09_r02_0002 must remain an ancestor of head — round E09-R02 contract"
   )
   ```
2. `backend/tests/community/test_profile_schema.py::test_alembic_downgrade_drops_community_tables`
   — cseréld a `command.downgrade(config, "-1")` hívást
   `command.downgrade(config, "e01_r12_0001")`-re (explicit cél-revízió, NEM
   relatív lépésszám). Ez a Community migráció (és minden rá épülő későbbi
   lánctag) teljes visszavonását bizonyítja, függetlenül attól, hány
   migráció épül rá a jövőben.
3. `backend/tests/test_migrations.py::test_downgrade_one_revision_drops_only_community_tables`
   — generalizáld: NE nevezze meg konkrétan a `community_profiles` /
   `community_privacy_settings` táblákat (azok E09-R02-specifikusak), hanem
   mérje a tábla-halmaz VÁLTOZÁSÁT:
   ```python
   command.upgrade(config, "head")
   tables_at_head = set(inspect(engine).get_table_names())
   command.downgrade(config, "-1")
   tables_after = set(inspect(engine).get_table_names())
   assert tables_after < tables_at_head, (
       "one-step downgrade must remove at least the head migration's own tables"
   )
   assert {"users", "user_settings"}.issubset(tables_after), (
       "the E01-R12 account baseline must survive a single-step downgrade"
   )
   ```
   (docstringet/tesztnevet igazítsd az új, chain-agnosztikus jelentéshez.)

**Kör-jelzés:** a fenti három teszt javítása UTÁN futtasd újra
`cd backend && .venv/bin/python -m pytest tests/test_migrations.py
tests/community/test_profile_schema.py tests/community/test_handle_policy.py -q`
— mindnek zöldnek kell lennie, majd `tools/codex-signal.sh done`. A round
gate-je (`tools/round-gate.sh`) változatlan; a self-heal a mércét NEM
gyengítette, csak a scope-ot és a hibás tesztfeltevést pontosította.

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
