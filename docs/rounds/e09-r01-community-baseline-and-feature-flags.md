# E09-R01 — Community baseline, threat model és feature flag

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 1
- **Kör-azonosító:** `E09-R01`
- **Branch:** `<motor>/e09-r01-community-baseline-and-feature-flags`
- **Előfeltétel:** `E08-R30` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0395` — a szám FOGLALT (Epic 9 batch-tartomány 0395-0419). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/app/config/feature_flags.dart` és a `backend/app/config.py` TÉNYLEGES mezőlistáját — az új flagek ezekhez csatlakoznak, nem önálló fájlba kerülnek. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/app/config/feature_flags.dart",
  "backend/app/config.py",
  "docs/security/community-threat-model.md",
  "docs/baseline/epic-09-community-start.md",
  "test/app/config/feature_flags_test.dart",
  "backend/tests/test_community_config.py",
  "docs/rounds/e09-r01-community-baseline-and-feature-flags.md",
]
gate_tests = [
  "test/app/config/feature_flags_test.dart"
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

Rögzítsd a Community fejlesztés biztonsági, adatvédelmi és architekturális kereteit **alkalmazáskód-változtatás nélkül**: a feature flag családot, a threat modelt és a baseline leltárt. Ez a kör nem ír domain- vagy UI-kódot.

## 2. Jelenlegi állapot — mért tények

- `lib/features/community/` **nem létezik** — ez az Epic 9 első kör
- `lib/app/config/feature_flags.dart` MA 30+ boolean flaget hordoz kötelező named paraméterekkel, dart-define override mintával (`accountEnabled` a `STRUMSIGHT_ACCOUNT` define-t olvassa) — az új Community flagek ugyanezt a mintát követik
- `backend/app/config.py` a `Settings(BaseSettings)` osztály; `tutor_enabled` már mutatja a feature-flaggelt opcionális szolgáltatás mintáját (`STRUMSIGHT_` env-prefix, dev-safe default)
- a backend MA SQLite-ot használ fejlesztésben (`sqlite:///./strumsight.db`), `allow_sqlite_in_prod` explicit false default mellett — a Community readiness-ellenőrzésnek (Kör 2) ez a TÉNYLEGES induló állapot, nem a SDD §20 PostgreSQL-feltételezése
- a `lib/features/share/` feature már létezik `strum_card.dart` és `wrapped_card.dart` widgetekkel — ez a Kör 10 share-artifact alapja
- `backend/alembic/versions/` MA egyetlen migrációt tartalmaz (`e01_r12_0001_initial_account_schema.py`) — a Community saját migrációs láncot indít Kör 2-ben

## 3. Scope

**Benne van:** `communityEnabled`, `communityWritesEnabled`, `communityMediaEnabled`, `communityLeaderboardEnabled`, `communityClubsEnabled` feature flag (Flutter + backend) · threat model dokumentum (identity, IDOR, audience bypass, block bypass, spam, media upload, challenge replay, moderation abuse) · baseline leltár a jelenlegi auth, share, progress, gamification és backend modulokról · a backend és mobil rollout kill switch viselkedésének dokumentálása.

**NINCS benne (tilos):**

- Bármilyen `lib/features/community/**` fájl létrehozása — ez Kör 5-től kezdődik.
- `backend/app/community/**` létrehozása — Kör 2 dolga.
- Meglévő flag viselkedésének módosítása (csak ÚJ flag hozzáadás).
- `docs/adr/**` — az ADR 0395-öt a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/app/config/feature_flags.dart` | ÚJ Community flagek hozzáadása (bővítés, nem átírás) |
| `backend/app/config.py` | ÚJ Community flagek hozzáadása a Settings osztályhoz |
| `docs/security/community-threat-model.md` | ÚJ — a threat model |
| `docs/baseline/epic-09-community-start.md` | ÚJ — a baseline leltár |
| `test/app/config/feature_flags_test.dart` | a §6 cellái — production default teszt |
| `backend/tests/test_community_config.py` | ÚJ — production default + readiness placeholder teszt |

**Tilos zóna:** `lib/features/community/**` (a feature még nem létezik) · `lib/features/` bármely más feature-je · `lib/core/**` · `lib/app/**` a `feature_flags.dart`-on kívül · `backend/app/community/**` · `backend/app/` a `config.py`-n kívül · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0395)

### 5.1 A Community asynchronous-first, és a magas kockázatú felületek KI vannak zárva ebből az Epicből

Élő audio jam, videóhívás, privát chat, typing indicator és állandó online presence NEM ennek az Epicnek a része — ezek külön threat modelt, gyermekvédelmi tervet és jelentősen nagyobb infrastruktúrát igényelnek. Az első verzió poszt, komment, követés, aszinkron challenge és klubcél köré épül.

**NEM elfogadható gyengítés:** egy "ideiglenes" privát üzenet vagy élő jelenlét funkció bevezetése "amíg a valódi megoldás elkészül" — ez pontosan az elhalasztott kockázati osztály, és a threat model erre nem készült fel.

### 5.2 Backend modular monolith, nyilvános UUID identitás

A Community ugyanabban a FastAPI deployban fut, saját modul- és adatboundaryval — külön mikroszolgáltatás csak mérés alapján indokolt. A nyilvános identitás UUID, sosem a belső bigint primary key vagy az e-mail cím.

**NEM elfogadható gyengítés:** a belső `users.id` bigint közvetlen visszaadása API response-ban "egyszerűség kedvéért, majd migráljuk később" — ez a user-enumeration kockázatot azonnal élesíti.

### 5.3 Production alapértelmezésben a Community KIKAPCSOLT

`communityEnabled` (és a négy alkapcsoló) production build-ben explicit engedély nélkül `false`. A dart-define/env override minta megegyezik a meglévő `accountEnabled`/`tutorEnabled` mintával.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A Community productionben explicit engedély nélkül nem indul | `feature_flags_test.dart` — production default teszt |
| A2 | Mind az öt Community flag development/lab környezetben elérhető, production-ben alapból KI | `feature_flags_test.dart` |
| A3 | A threat model lefedi az összes §6 nem-tárgyalható invariánst (audience bypass, block bypass, spam, media, replay, moderation abuse) | review — dokumentum-audit |
| A4 | Nincs új hálózati kérés és nincs funkcionális regresszió | `tools/round-gate.sh` — teljes cél-terület zöld |
| A5 | A backend `Settings` readiness placeholder-je dokumentálja a SQLite-vs-PostgreSQL éles döntést | `test_community_config.py` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `communityEnabled` alapértéke production-ben `true` | A1 |
| Csak egy flag kap production-off védelmet, a többi négy nem | A2 |
| A threat model kihagyja a media upload vagy a challenge replay kockázatot | A3 |
| A flag hozzáadása egy meglévő flag nevét vagy alapértékét is módosítja | A4 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** állítsd `communityEnabled` production defaultját `true`-ra, futtasd a gate-et → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/app/config/feature_flags_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/test_community_config.py -q
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

1. A négy alkapcsoló + `communityEnabled` hozzáadása a Flutter `FeatureFlags`-hoz, dart-define mintával.
2. Ugyanaz a Community-flag-készlet a backend `Settings`-hez, `STRUMSIGHT_COMMUNITY_*` env-prefixekkel.
3. `docs/security/community-threat-model.md` — a nyolc kötelező kockázati kategória (identity, IDOR, audience bypass, block bypass, spam, media upload, challenge replay, moderation abuse).
4. `docs/baseline/epic-09-community-start.md` — a meglévő auth/share/progress/gamification/backend leltár.
5. A production-default teszt mindkét oldalon (Flutter + backend).
6. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A flag alapértelmezésének elrontása.** Egyetlen `true` érték a rossz helyen kikapcsolt védelem nélkül tenné élessé egy még nem biztonságos réteget (A1/A2).
- **A threat model hiányossága.** Egy ki nem mondott kockázati osztály (pl. Sybil-regisztráció) a Kör 20+ tájékán derülne ki, amikor már drága a visszamenőleges javítás.
- **A backend readiness-ellenőrzés elhalasztása.** A SDD PostgreSQL-t feltételez, a valóság SQLite — ha ez a kör nem dokumentálja a döntést, Kör 2 vakon nekifut a driftnek.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
