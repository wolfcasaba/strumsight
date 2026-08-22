# E09-R22 — Verified result submission és anti-cheat

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 22
- **Kör-azonosító:** `E09-R22`
- **Branch:** `<motor>/e09-r22-verified-result-submission-and-anti-cheat`
- **Előfeltétel:** `E09-R21` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0411` — a szám FOGLALT (Epic 9 batch-tartomány 0395-0419). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az E08-R28 ledger-szinkron `verified`/`unverified` szerződését (ha addigra merge-elve) — ez a kör UGYANAZT a mintát alkalmazza a challenge-eredményre: a szerver soha nem fogad el kliens-oldali `verified`/`rank` állítást. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/services/challenge_verification_service.py",
  "backend/app/community/models/challenge_result.py",
  "backend/app/community/policies/integrity_policy.py",
  "backend/alembic/versions/e09_r22_0016_community_challenge_result.py",
  "lib/features/community/application/controllers/challenge_result_controller.dart",
  "backend/tests/community/test_challenge_verification.py",
  "test/features/community/application/challenge_result_controller_test.dart",
  "docs/rounds/e09-r22-verified-result-submission-and-anti-cheat.md",
]
gate_tests = [
  "test/features/community/application/challenge_result_controller_test.dart"
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

Challenge-eredmények szerveroldali, idempotens ellenőrzése és a trust-állapot rögzítése — a szerver SOHA nem fogad el kliens-oldali `verified` flaget vagy rankot.

## 2. Jelenlegi állapot — mért tények

- A Kör 21 challenge-lifecycle MA `active` állapotig jut — ez a kör adja hozzá a tényleges eredmény-beküldést és annak ellenőrzését
- A gamifikáció E08-R28 (ha addigra kész) MÁR bizonyítja a "szerver soha nem fogad el kliens-oldali összesített értéket" mintát — ez a kör UGYANAZT a mintát alkalmazza, nem talál ki újat

## 3. Scope

**Benne van:** eredmény-submit endpoint stabil source-event-ID + server-issued nonce-szal · challenge-verzió, időablak, participant-állapot, metric-range, scorer-kompatibilitás validáció · SOSEM kliens által küldött rank vagy verified flag elfogadása · replay-deduplikáció + first/best-submission policy challenge-típusonként · verification state: pending, verified, unverified, rejected, review · anomaly signal reason-code-os, nyers audio NÉLKÜL · kliensen a pending verification elkülönül a lokális session sikerétől.

**NINCS benne (tilos):**

- Leaderboard — Kör 23 (ez a kör csak a verified receiptet állítja elő).
- `docs/adr/**` — az ADR 0411-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/services/challenge_verification_service.py` | ÚJ |
| `backend/app/community/models/challenge_result.py` | ÚJ |
| `backend/app/community/policies/integrity_policy.py` | ÚJ |
| `backend/alembic/versions/e09_r22_0016_community_challenge_result.py` | ÚJ |
| `lib/features/community/application/controllers/challenge_result_controller.dart` | ÚJ |
| `backend/tests/community/test_challenge_verification.py` | ÚJ — a §6 cellái |
| `test/features/community/application/challenge_result_controller_test.dart` | ÚJ |

**Tilos zóna:** `backend/app/community/models/challenge.py` (a Kör 21 lezárt lifecycle-je, csak a result-kapcsolat hozzáadása) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0411)

### 5.1 A SZERVER SOSEM fogad el kliens-oldali `verified` flaget vagy `rank`-ot

A submit-payload eredmény-adatot (metric, timestamp, source-event-ID) hordoz — a `verified` és a `rank` KIZÁRÓLAG a szerver saját kiértékeléséből származik, ugyanaz az elv, mint az E08-R28 ledger-szinkron `totalXp`-tilalma.

**NEM elfogadható gyengítés:** egy "gyorsítótárazott" `verified` vagy `rank` mező elfogadása a kérésben, akár csak ellenőrzésre — ami a kérésben van, arra a szerver támaszkodni fog, tehát ez triviálisan hamisítható csalássá válna.

### 5.2 A replay NEM hoz létre második eredményt

A stabil source-event-ID + server-issued nonce deduplikálja a beküldést; a challenge-típusonként dokumentált first/best policy dönt a végleges eredményről.

### 5.3 A verification hiba NEM törli a lokális session sikerét

A Community upload-hiba (hálózat, verzió-eltérés) NEM befolyásolja a Practice/Song-session lokális, már elmentett eredményét — a pending verification külön állapot a UI-ban.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Replay nem hoz létre második eredményt | `test_challenge_verification.py` |
| A2 | Forged `verified`/`rank` a kérésben figyelmen kívül marad | `test_challenge_verification.py` |
| A3 | Fizikailag lehetetlen (impossible) score elutasított | `test_challenge_verification.py` |
| A4 | Lejárt nonce elutasított | `test_challenge_verification.py` |
| A5 | Rossz challenge-verzió/scorer-inkompatibilitás elutasított | `test_challenge_verification.py` |
| A6 | First/best submission policy helyesen alkalmazott challenge-típusonként | `test_challenge_verification.py` |
| A7 | Community upload-hiba nem törli a lokális session sikerét | `challenge_result_controller_test.dart` |
| A8 | A döntés reason-code-dal auditált | `test_challenge_verification.py` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A submit-endpoint elfogadja a kérésben küldött `verified: true` mezőt | A2 |
| Ugyanaz a source-event-ID kétszer hoz létre eredményt | A1 |
| Egy fizikailag lehetetlen score (pl. negatív idő alatt teljes pontszám) átmegy | A3 |
| A lejárt nonce-szal küldött eredmény elfogadásra kerül | A4 |
| A Community upload-hiba a lokális practice-session eredményét is törli | A7 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** add hozzá a `verified` mező közvetlen elfogadását a submit-payloadból, futtasd a backend pytest-et forged-verified bemenettel → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/application/challenge_result_controller_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_challenge_verification.py -q
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

1. Migráció: `community_challenge_results` (source_event_id, nonce, metric, verification_state, reason_code).
2. `integrity_policy.py` — metric-range, scorer-kompatibilitás, impossible-score detekció.
3. `challenge_verification_service.py` — replay-dedup, first/best policy, a szerver SAJÁT verified/rank számítása.
4. `challenge_result_controller.dart` — pending-verification állapot, elkülönítve a lokális sikertől.
5. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **A kliens-adta `verified`/`rank` elfogadása.** Ez a legsúlyosabb lehetséges hiba az egész Epicben — a teljes versenyrendszer hitelességét vinné (A2), pontosan az E08-R28-cal analóg kockázat.
- **A replay.** Egy megismételt beküldés enélkül tetszőleges számú eredményt termelne (A1).
- **A Community-hiba összekapcsolása a lokális sikerrel.** A felhasználó azt hinné, elveszett a gyakorlása egy hálózati hiba miatt (A7).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
