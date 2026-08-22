# E09-R07 — Follow és follow request social graph

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 7
- **Kör-azonosító:** `E09-R07`
- **Branch:** `<motor>/e09-r07-follow-and-follow-request-graph`
- **Előfeltétel:** `E09-R06` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0400` — a szám FOGLALT (Epic 9 batch-tartomány 0395-0419). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 4 `CommunityAccessPolicy` TÉNYLEGES relationship-paraméter alakját — a follow-service ebbe a szerződésbe kell illeszkedjen, nem egy párhuzamos, önálló relationship-fogalmat vezet be. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/models/social_graph.py",
  "backend/app/community/services/follow_service.py",
  "backend/app/community/routers/social_graph.py",
  "backend/alembic/versions/e09_r07_0005_community_follow.py",
  "lib/features/community/application/controllers/relationship_controller.dart",
  "lib/features/community/data/repositories/relationship_repository_impl.dart",
  "lib/features/community/presentation/screens/followers_screen.dart",
  "backend/tests/community/test_follow_service.py",
  "test/features/community/application/relationship_controller_test.dart",
  "docs/rounds/e09-r07-follow-and-follow-request-graph.md",
]
gate_tests = [
  "test/features/community/application/relationship_controller_test.dart"
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

Idempotens, privacy-kompatibilis követési rendszer: public profilnál azonnali follow, private profilnál explicit accept/decline lifecycle.

## 2. Jelenlegi állapot — mért tények

- A Kör 4 policy-mátrixa MA egy `RelationshipContext` paramétert fogad, de a tényleges follow-tábla és -szolgáltatás még nem létezik — ez a kör hozza létre
- `ProfileVisibility.private` (Kör 4) MA a request-alapú follow előfeltétele

## 3. Scope

**Benne van:** `community_follows` és `community_follow_requests` migráció egyedi constrainttel · public profilnál azonnali follow, private profilnál request lifecycle · accept, decline, cancel, unfollow, follower-removal · idempotency key minden mutációhoz · follower/following cursor pagination endpoint · kliens: optimistic follow CSAK public profilnál; private requestnél pending state.

**NINCS benne (tilos):**

- Block/mute — Kör 8.
- Feed vagy post látás a follow alapján — Kör 13.
- `docs/adr/**` — az ADR 0400-at a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/models/social_graph.py` | ÚJ — follow + follow_request tábla |
| `backend/app/community/services/follow_service.py` | ÚJ — lifecycle + idempotency |
| `backend/app/community/routers/social_graph.py` | ÚJ — endpointok |
| `backend/alembic/versions/e09_r07_0005_community_follow.py` | ÚJ |
| `lib/features/community/application/controllers/relationship_controller.dart` | ÚJ |
| `lib/features/community/data/repositories/relationship_repository_impl.dart` | ÚJ |
| `lib/features/community/presentation/screens/followers_screen.dart` | ÚJ |
| `backend/tests/community/test_follow_service.py` | ÚJ — a §6 cellái |
| `test/features/community/application/relationship_controller_test.dart` | ÚJ |

**Tilos zóna:** `lib/features/community/domain/**` (csak olvasás, bővítés indokolt esettel) · `backend/app/community/policies/access_policy.py` (Kör 4 lezárt szerződése) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0400)

### 5.1 A follow-mutáció idempotens és adatbázis-szinten védett self-follow ellen

`CHECK (follower_profile_id != followed_profile_id)` és `UNIQUE (follower_profile_id, followed_profile_id)` — a védelem NEM alkalmazás-szintű `if` ág, mert azt egy race megkerülheti.

**NEM elfogadható gyengítés:** egy service-szintű `if follower == followed: raise` ellenőrzés adatbázis-constraint nélkül — versenyhelyzetben duplikált vagy self-follow rekord keletkezhet.

### 5.2 Private profilnál a follow REQUEST-alapú, explicit elfogadással

`requested → accepted | declined | cancelled` — a kliens optimistic UI-ja CSAK a public úton engedett; private profilnál a UI `pending` állapotot mutat, amíg a szerver nem erősít vissza.

### 5.3 A follower eltávolítása NEM igényel blockot

A profil tulajdonosa eltávolíthat egy követőt anélkül, hogy blockolná — ez két külön, egymástól független művelet.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Self-follow tiltott adatbázis-szinten | `test_follow_service.py` |
| A2 | Duplikált follow retry vagy versenyhelyzet mellett sem keletkezik | `test_follow_service.py` — concurrent teszt |
| A3 | Private profil accept/decline/cancel lifecycle helyes | `test_follow_service.py` |
| A4 | Follower removal nem igényel blockot | `test_follow_service.py` |
| A5 | Cursor pagination stabil, nincs duplikált oldal | `test_follow_service.py` |
| A6 | Optimistic follow rollback hálózati hiba esetén (Flutter) | `relationship_controller_test.dart` |
| A7 | Public profilnál a follow azonnali, private profilnál pending | `relationship_controller_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A self-follow csak service-szinten ellenőrzött, DB-constraint nélkül | A1 |
| Két konkurens follow-kérés mindkettő sikeres rekordot hoz létre | A2 |
| Private profilnál a follow azonnal `accepted`-ként kerül be | A3 |
| A follower-removal blockot is létrehoz | A4 |
| Public profilnál a UI `pending` állapotot mutat a tényleges azonnali siker helyett | A7 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki a `(follower_profile_id, followed_profile_id)` unique constraintet, futtasd a backend pytest-et konkurens kérésekkel → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/application/relationship_controller_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_follow_service.py -q
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

1. Migráció: `community_follows` (unique + check constraint), `community_follow_requests`.
2. `follow_service.py` — public azonnali / private request lifecycle, idempotency key.
3. `social_graph.py` router — follow, accept, decline, cancel, unfollow, follower-removal, cursor pagination.
4. `relationship_controller.dart` — optimistic (public) / pending (private) állapotgép.
5. `followers_screen.dart` — lista cursor paginationnel.
6. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **Az alkalmazás-szintű self-follow/duplikáció-ellenőrzés.** Ez a legkritikusabb invariáns — csak DB-constraint biztosítja versenyben (A1/A2).
- **A private-follow azonnali elfogadása.** Ha a request-lifecycle kihagyható, a privát profil védelme illúzió (A3).
- **A follower-removal és a block összemosása.** A termék két külön eszközt kínál különböző súlyossággal (A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
