# E09-R32 — Teljes integráció, load evaluation és release readiness

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 32
- **Kör-azonosító:** `E09-R32`
- **Branch:** `<motor>/e09-r32-integration-load-evaluation-and-release-readiness`
- **Előfeltétel:** `E09-R31` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — ez a kör nem hoz új kötött architekturális döntést (tisztán UI/integráció/lezárás).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `docs/sdd/epic-06-completion-report.md` és `epic-07-completion-report.md` TÉNYLEGES szerkezetét — az Epic 9 completion report ugyanazt a mintát követi (nyitott tételek tábla, rollout-terv, mért kockázatok). Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "docs/sdd/epic-09-completion-report.md",
  "docs/operations/community-rollout-plan.md",
  "backend/tests/load/community/test_feed_load.py",
  "backend/tests/load/community/test_burst_load.py",
  "test/features/community/integration/community_full_flow_test.dart",
  "docs/rounds/e09-r32-integration-load-evaluation-and-release-readiness.md",
]
gate_tests = [
  "test/features/community/integration/community_full_flow_test.dart"
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

Az Epic lezárása teljes regresszióval, terhelésméréssel, manuális safety teszttel és rollout tervvel — a Community nem regresszálja a Practice/Song/Analysis/Gamification funkciókat.

## 2. Jelenlegi állapot — mért tények

- A Kör 1-31 MOST fedezi le a teljes Community-funkciót — ez a ZÁRÓ kör, tisztán mérés/dokumentáció, ÚJ funkciókód nélkül
- a backend MA SQLite-tal fut fejlesztésben; a terhelésmérés dokumentálja a PostgreSQL-re történő éles váltás előfeltételét (a Kör 1 ADR 0395 döntése szerint)

## 3. Scope

**Benne van:** teljes Flutter + backend tesztcsomag, architecture guard, migrációteszt futtatása · terhelésteszt: feed, comment-burst, challenge-leaderboard, notification-burst · account-disabled és community-disabled állapotban NULLA Community request ellenőrzése · kétaccountos manuális teszt: follow, private, block, report, challenge, delete · offline/online, app-kill, token-expiry, account-switch teszt · moderation + incident tabletop teszt · staged rollout terv (belső → kis beta → opt-in beta → production) rollback-feltételekkel · `epic-09-completion-report.md` a maradék kockázatokkal.

**NINCS benne (tilos):**

- ÚJ funkciókód bármilyen formában — ez tisztán mérési/dokumentációs kör.
- A rollout flag-ek TÉNYLEGES bekapcsolása production-ben — az emberi döntés, nem ennek a körnek a hatásköre.
- `docs/adr/**` — ez a záró kör nem hoz új kötött döntést.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/sdd/epic-09-completion-report.md` | ÚJ |
| `docs/operations/community-rollout-plan.md` | ÚJ |
| `backend/tests/load/community/test_feed_load.py` | ÚJ |
| `backend/tests/load/community/test_burst_load.py` | ÚJ |
| `test/features/community/integration/community_full_flow_test.dart` | ÚJ — a §6 cellái |

**Tilos zóna:** `lib/**` ÉS `backend/**` a fent felsorolt ÚJ teszt-/mérés-fájlokon kívül (ez a kör NEM módosít production kódot) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések

### 5.1 Ez a kör NEM hoz új kötött architekturális döntést — kizárólag mérés és dokumentáció

Minden Kör 1-31 döntés VÁLTOZATLAN marad; ez a kör a meglévő rendszert méri és a rollout-tervet írja meg, nem módosít production-viselkedést.

**NEM elfogadható gyengítés:** egy "gyors javítás" beillesztése a záró körben egy mérés közben talált hibára — a helyes válasz egy dokumentált, follow-up körként rögzített hiba, nem egy scope-on kívüli élő módosítás.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Minden CI zöld és a known-risk lista explicit | teljes gate + `epic-09-completion-report.md` |
| A2 | Account-disabled és community-disabled állapotban nulla Community request | `community_full_flow_test.dart` — network-spy (L140 minta) |
| A3 | A feed és mutációk elérik a dokumentált load-baseline-t | `test_feed_load.py`, `test_burst_load.py` |
| A4 | Rollback lehetséges adatvesztés nélkül | `docs/operations/community-rollout-plan.md` + manuális teszt |
| A5 | A Community nem regresszálja a Practice/Song/Analysis/Gamification funkciókat | teljes meglévő suite futtatása változatlanul zöld |
| A6 | Kétaccountos E2E (follow/private/block/report/challenge/delete) zöld | `community_full_flow_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A network-spy egy örökölt, más transportra épülő probe-ot használ (L140 hibaosztály) | A2 |
| A load-teszt csak fejlesztői SQLite-on fut, nem méri a PostgreSQL-célt | A3 mellett follow-up kockázat, dokumentálandó |
| A regresszió-suite kihagy egy meglévő Gamification/Practice tesztet | A5 |
| A kétaccountos E2E nem méri a block utáni AZONNALI szétválást | A6 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** docs-only/mérési kör — a falszifikáció a reviewer eldobható próbája: töröld a `docs/operations/community-rollout-plan.md` rollback-feltétel szakaszát → az **A4** cella bizonyíthatatlanná válik → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/integration/community_full_flow_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/load/community -q && python -m pytest -q
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

1. A teljes Flutter + backend tesztcsomag, architecture guard, migrációteszt futtatása és eredmény-rögzítés.
2. A load-tesztek megírása és futtatása (feed, comment-burst, leaderboard, notification-burst).
3. A network-spy alapú account/community-disabled regresszió (L140 minta — a Kör 1 flag-tesztek kiterjesztése a TELJES Community transportra).
4. A kétaccountos manuális/E2E teszt-jegyzőkönyv.
5. `docs/operations/community-rollout-plan.md` — staged rollout + rollback.
6. `docs/sdd/epic-09-completion-report.md` — a nyitott kockázatok táblája.

## 9. Kockázatok

- **A vak network-probe.** Az L140 hibaosztály (E04-R24) pontosan ezt mérte: egy régi, más transportra épülő probe nem látja az ÚJ Community-transportot (A2) — ez a legfontosabb mért lecke erre a körre.
- **A SQLite-alapú load-mérés PostgreSQL-célra vetítése.** A Kör 1 ADR 0395 döntése szerint a production PostgreSQL-t igényel — a load-baseline ezt explicit kockázatként kell rögzítse, nem hallgatólagosan extrapolálja.
- **A záró körben becsempészett "gyors javítás".** Scope-on kívüli módosítás egy záró/mérési körben pont az a minta, amit az AGENTS.md §4 kizár — minden találat follow-up, nem élő fix.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
