# E09-R21 — Community challenge és invite lifecycle

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 21
- **Kör-azonosító:** `E09-R21`
- **Branch:** `<motor>/e09-r21-challenge-and-invite-lifecycle`
- **Előfeltétel:** `E09-R20` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0410` — a szám FOGLALT (Epic 9 batch-tartomány 0395-0419). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a gamifikáció E08-R19 `ChallengeV2`/legacy-wrap TÉNYLEGES definícióját — a Community csak KOMPATIBILIS challenge-definíciót fogadhat el, nem definiál párhuzamosat. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/models/challenge.py",
  "backend/app/community/services/challenge_invite_service.py",
  "backend/app/community/routers/challenges.py",
  "backend/alembic/versions/e09_r21_0015_community_challenge.py",
  "lib/features/community/presentation/screens/community_challenges_screen.dart",
  "backend/tests/community/test_challenge_invite_service.py",
  "test/features/community/presentation/community_challenges_test.dart",
  "docs/rounds/e09-r21-challenge-and-invite-lifecycle.md",
]
gate_tests = [
  "test/features/community/presentation/community_challenges_test.dart"
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

Aszinkron kihívás-meghívások és résztvevői állapotgép — a lejárat szerveridőből, timezone-független, minden átmenet szerveroldali policyvel.

## 2. Jelenlegi állapot — mért tények

- A gamifikáció E08-R19 challenge-definíciója MA létezik — ez a kör kompatibilitást ellenőriz vele, nem definiál új challenge-típust
- A Kör 8 block-szűrő és a Kör 20 notification-infrastruktúra MA készen áll az invite-hoz

## 3. Scope

**Benne van:** challenge, participant, invite tábla version + időablak + verification policy · draft/sent/accepted/declined/expired/cancelled átmenetek · csak kompatibilis Gamification/Practice challenge-definíció használható · block, eligibility, feature-availability, invite rate-limit szerveroldali ellenőrzés · challenge list/detail Flutter képernyő offline cache-sel · accepted challenge indítása deep linkkel a megfelelő Practice/Song flow-ba · timezone-független lejárat-számítás szerveridőből.

**NINCS benne (tilos):**

- A tényleges eredmény-beküldés és anti-cheat — Kör 22.
- Leaderboard — Kör 23.
- `docs/adr/**` — az ADR 0410-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/models/challenge.py` | ÚJ |
| `backend/app/community/services/challenge_invite_service.py` | ÚJ |
| `backend/app/community/routers/challenges.py` | ÚJ |
| `backend/alembic/versions/e09_r21_0015_community_challenge.py` | ÚJ |
| `lib/features/community/presentation/screens/community_challenges_screen.dart` | ÚJ |
| `backend/tests/community/test_challenge_invite_service.py` | ÚJ — a §6 cellái |
| `test/features/community/presentation/community_challenges_test.dart` | ÚJ |

**Tilos zóna:** `lib/features/gamification/**` belső fájljai (csak `public.dart`) · `lib/features/practice/**`/`lib/features/songs/**` belső fájljai · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0410)

### 5.1 A lifecycle EXPLICIT állapotgép, minden átmenet szerveroldali policyvel

`draft → sent → accepted | declined | expired | cancelled`, majd `accepted → active → completed | forfeited | expired` — érvénytelen átmenet a szerveren elutasított.

**NEM elfogadható gyengítés:** egy kliensoldali állapotváltás, ami "optimistán" előreugorja az állapotgépet a szerver megerősítése előtt, majd csendben visszaáll hiba esetén — ez inkonzisztens UI-t és versenyhelyzetet okozna.

### 5.2 A lejárat SZERVERIDŐBŐL számítható, timezone-független

Az `endsAt` UTC timestamp; a lejárat-ellenőrzés a szerver óráján megy, nem a kliens helyi idején.

### 5.3 Ugyanaz a meghívás retry esetén NEM duplikálódik

Az invite-létrehozás idempotens, ugyanazzal az idempotency-key-mintával, mint a Kör 11 post-create.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Invalid transition (pl. `declined → accepted`) elutasított | `test_challenge_invite_service.py` |
| A2 | Lejárt invite accept-je elutasított | `test_challenge_invite_service.py` |
| A3 | Blockolt fél nem hívható meg és nem hívhat meg | `test_challenge_invite_service.py` |
| A4 | Duplikált invite retry nem hoz létre második rekordot | `test_challenge_invite_service.py` |
| A5 | Cancel race (egyidejű accept + cancel) determinisztikusan dől el | `test_challenge_invite_service.py` |
| A6 | Deep link csak kompatibilis Practice/Song flow-ra mutat | `community_challenges_test.dart` |
| A7 | A lejárat-számítás timezone-független (szerveridő) | `test_challenge_invite_service.py` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A `declined` állapotból `accepted`-be lehet lépni | A1 |
| Egy lejárt invite accept-je sikeres marad | A2 |
| Egy blockolt user meghívása átmegy a policy-n | A3 |
| Két retry két külön invite-rekordot hoz létre | A4 |
| A kliens helyi ideje alapján dől el a lejárat | A7 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki az idempotency-key ellenőrzést az invite-create hívásból, futtasd a backend pytest-et két egymást követő azonos kéréssel → az **A4** cellának PIROSNAK kell lennie (két invite jön létre) → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/presentation/community_challenges_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_challenge_invite_service.py -q
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

1. Migráció: `community_challenges`, `community_challenge_participants`, `community_challenge_invites`.
2. `challenge_invite_service.py` — az állapotgép, block/eligibility/rate-limit ellenőrzéssel.
3. A gamifikáció challenge-definíció kompatibilitás-ellenőrzése (`public.dart` hívás).
4. `challenges.py` router — invite/accept/decline/cancel endpointok.
5. `community_challenges_screen.dart` — lista, detail, offline cache, deep link.
6. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **Az optimista állapotgép-ugrás.** Egy kliensoldali "előreugrás" versenyhelyzetben inkonzisztens állapotot hagyna (A1/A5).
- **A kliens-idő alapú lejárat.** Egy rosszul beállított eszközóra meghosszabbítaná vagy lerövidítené a challenge-ablakot (A7).
- **A blockolt fél meghívása.** Ez közvetlen safety-regresszió lenne a Kör 8 invariánshoz képest (A3).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
