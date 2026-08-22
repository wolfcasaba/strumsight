# E09-R08 — Block, mute és safety kapcsolatkezelés

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 8
- **Kör-azonosító:** `E09-R08`
- **Branch:** `<motor>/e09-r08-block-mute-and-safety-relationships`
- **Előfeltétel:** `E09-R07` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0401` — a szám FOGLALT (Epic 9 batch-tartomány 0395-0419). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 7 `follow_service.py` TÉNYLEGES tranzakció-határait — a block-tranzakciónak ugyanabban a DB-tranzakcióban kell törölnie a follow kapcsolatot és a pending requestet, nem külön hívásokban. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/models/safety_relationships.py",
  "backend/app/community/services/block_service.py",
  "backend/app/community/policies/query_filters.py",
  "backend/app/community/policies/access_policy.py",
  "backend/alembic/versions/e09_r08_0006_community_safety.py",
  "lib/features/community/presentation/screens/safety_relationships_screen.dart",
  "backend/tests/community/test_block_service.py",
  "backend/tests/community/test_block_query_regression.py",
  "docs/rounds/e09-r08-block-mute-and-safety-relationships.md",
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

A felhasználó azonnal és megbízhatóan megszakíthassa a nem kívánt interakciókat: block minden read/write útvonalon érvényesül, mute lokális nézetváltozás marad.

## 2. Jelenlegi állapot — mért tények

- A Kör 4 `CommunityAccessPolicy` MA a `RelationshipContext.blocked` mezőt olvassa, de a mező forrása (a tényleges block-tábla) még nem létezik
- A Kör 7 follow-rendszere MA nem ismeri a blockot — ez a kör köti be a block-törlést a follow-hoz tranzakcióban

## 3. Scope

**Benne van:** block és mute tábla egyedi pair constrainttel · block létrehozásakor TRANZAKCIÓBAN follow + request + pending challenge invite törlése · block policy alkalmazása profile/search/feed/comments/clubs/notifications/challenge querykben · mute feed- és notification-szűrés a másik fél értesítése NÉLKÜL · Blocked/Muted users beállítási képernyő · regressziós teszt MINDEN Community read endpoint ellen.

**NINCS benne (tilos):**

- Report/moderation workflow — Kör 26/27.
- Feed vagy keresés TÉNYLEGES implementációja (csak a policy-integráció) — Kör 9/13.
- `docs/adr/**` — az ADR 0401-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/models/safety_relationships.py` | ÚJ — block + mute tábla |
| `backend/app/community/services/block_service.py` | ÚJ — tranzakciós block-létrehozás |
| `backend/app/community/policies/query_filters.py` | ÚJ — közös block/mute szűrő minden read queryhez |
| `backend/app/community/policies/access_policy.py` | BŐVÍTÉS — a `RelationshipContext.blocked` valódi forrásra kötése |
| `backend/alembic/versions/e09_r08_0006_community_safety.py` | ÚJ |
| `lib/features/community/presentation/screens/safety_relationships_screen.dart` | ÚJ |
| `backend/tests/community/test_block_service.py` | ÚJ — a §6 cellái |
| `backend/tests/community/test_block_query_regression.py` | ÚJ — minden read endpoint elleni regresszió |

**Tilos zóna:** `backend/app/community/models/social_graph.py` a follow-törlés hívásán kívül (Kör 7 lezárt szerződése) · `lib/features/community/domain/**` · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0401)

### 5.1 A block ATOMIKUS: egy tranzakcióban törli a follow/request/invite kapcsolatokat

Ha a follow-törlés vagy a block-létrehozás bármelyike hibázik, EGYIK sem íródik be — nincs olyan köztes állapot, ahol a block létezik, de a follow még él.

**NEM elfogadható gyengítés:** két külön hívás (előbb töröld a follow-t, majd hozd létre a blockot) — egy hiba a kettő között inkonzisztens, potenciálisan biztonsági rést hagyó állapotot eredményezne.

### 5.2 A mute NEM értesíti a másik felet és nem szünteti meg a followt

A mute kizárólag a mutoló saját nézetét befolyásolja — a másik fél semmilyen jelet nem kap, és a follow kapcsolat érintetlen marad.

### 5.3 Unblock NEM állítja vissza a korábbi follow-t

A block feloldása után a kapcsolat state-je `none` — ha a felek újra kapcsolódni akarnak, explicit új follow-műveletet kell indítaniuk.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Block tranzakcióban törli a follow/request/pending-invite kapcsolatokat | `test_block_service.py` |
| A2 | Blocked user kiesik a search/feed/comment/club/notification querykből mindkét irányban | `test_block_query_regression.py` |
| A3 | Mute nem értesíti a másik felet és nem törli a followt | `test_block_service.py` |
| A4 | Unblock nem állítja vissza a korábbi followt | `test_block_service.py` |
| A5 | Egy ÚJ Community endpoint sem kerülhet block-filter nélkül CI-be | `test_block_query_regression.py` — endpoint-lista regresszió |
| A6 | Közös klubban a blockolt tartalom minimalizált placeholderként jelenik meg | `test_block_query_regression.py` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A block-létrehozás és a follow-törlés két külön, nem-tranzakciós hívás | A1 |
| A search endpoint nem ellenőrzi a block-relációt | A2/A5 |
| A mute push-értesítést küld a mutolt félnek | A3 |
| Unblock után a régi follow automatikusan visszaáll | A4 |
| Egy jövőbeli endpoint kimarad a `query_filters.py` közös szűrőjéből | A5 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki a `query_filters.py` block-szűrőjének hívását a search endpointból, futtasd a regressziós tesztet → az **A2/A5** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/architecture_dependency_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_block_service.py tests/community/test_block_query_regression.py -q
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

1. Migráció: `community_blocks`, `community_mutes` egyedi pár-constrainttel.
2. `block_service.py` — atomikus tranzakció (block + follow/request/invite törlés).
3. `query_filters.py` — egyetlen, minden read query által hívott közös szűrő.
4. Az ÖSSZES meglévő Community read endpoint bekötése a szűrőre (Kör 2-7 endpointjai).
5. `safety_relationships_screen.dart` — Blocked/Muted lista.
6. A regressziós teszt-csoport (minden endpoint egyszerre).
7. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **A nem-atomikus block-létrehozás.** Egy félbeszakadt tranzakció inkonzisztens, biztonsági rést hagyó állapotot eredményezne (A1).
- **Egy elfelejtett endpoint.** A `query_filters.py` KÖZÖS szűrő nélkül minden ÚJ endpoint saját, elfelejthető block-ellenőrzést igényelne — ez a kör legfontosabb, jövőbe mutató kockázata (A2/A5).
- **A mute-értesítés szivárgása.** Ha a mute bármilyen jelet küld a másik félnek, a funkció célja (csendes, önvédő szűrés) meghiúsul (A3).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
