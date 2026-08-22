# E09-R30 — Rate limit, observability és security hardening

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 30
- **Kör-azonosító:** `E09-R30`
- **Branch:** `<motor>/e09-r30-rate-limit-observability-and-security-hardening`
- **Előfeltétel:** `E09-R29` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0418` — a szám FOGLALT (Epic 9 batch-tartomány 0395-0419). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `.github/workflows/full-gate.yml` TÉNYLEGES lépéseit (mint az E08-R29-ben) — ez a kör is CSAK HOZZÁAD, meglévő lépést nem módosít (H-GATEGUARD). Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/security/rate_limits.py",
  "backend/app/community/security/abuse_signals.py",
  "backend/app/community/observability.py",
  "docs/operations/community-incident-runbook.md",
  ".github/workflows/full-gate.yml",
  "backend/tests/community/test_security_hardening.py",
  "docs/rounds/e09-r30-rate-limit-observability-and-security-hardening.md",
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

A Community production-biztonságának, mérhetőségének és abuse-védelmének megerősítése — IDOR, forged-mező és audience-bypass tesztcsomaggal bizonyítva.

## 2. Jelenlegi állapot — mért tények

- Az összes megelőző kör MA egyenként rendelkezik valamilyen rate-limit/audit gondolattal, de nincs KÖZÖS, multi-worker-safe rate-limit store és nincs egységes security-tesztcsomag — ez a kör ezt konszolidálja

## 3. Scope

**Benne van:** endpoint- és action-specifikus rate limit policy KÖZÖS store-adapterrel (nem process-local) · request ID + strukturált audit event + redacted application log · abuse-signal aggregátor: account-age, velocity, duplicate-hash, report/block-rate · IDOR, forged-author, forged-verified, audience-bypass, admin-auth teszt · security headers + request-body-limit a Community route-okon · metrics dashboard specifikáció (post-success, feed-latency, moderation-queue, outbox-failure, verification-latency) · emergency write-disable + media-disable runbook.

**NINCS benne (tilos):**

- A `full-gate.yml` MEGLÉVŐ lépéseinek törlése vagy lazítása — H-GATEGUARD.
- Bármely `lib/**` fájl módosítása.
- `docs/adr/**` — az ADR 0418-at a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/security/rate_limits.py` | ÚJ |
| `backend/app/community/security/abuse_signals.py` | ÚJ |
| `backend/app/community/observability.py` | ÚJ |
| `docs/operations/community-incident-runbook.md` | ÚJ |
| `.github/workflows/full-gate.yml` | CSAK ÚJ lépések HOZZÁADÁSA — meglévő lépés NEM módosítható |
| `backend/tests/community/test_security_hardening.py` | ÚJ — a §6 cellái |

**Tilos zóna:** `lib/**` (a TELJES alkalmazáskód) · `tools/round-gate.sh` · `.github/workflows/` MINDEN más fájlja · `docs/adr/**` · `backend/**` a fent felsoroltakon kívül

## 5. Kötött architekturális döntések (ADR 0418)

### 5.1 A MEGLÉVŐ gate-lépések SÉRTHETETLENEK

Ez a kör a `full-gate.yml`-hez CSAK hozzáad. Meglévő lépés törlése, feltételessé tétele vagy küszöbének lazítása tilos — ez a H-GATEGUARD határa és emberi döntést igényel.

**NEM elfogadható gyengítés:** egy meglévő lépés `continue-on-error: true` jelölése "amíg az új Community-őrök stabilizálódnak".

### 5.2 A rate-limit store KÖZÖS, multi-worker-safe

Production, több worker-folyamat mellett a rate-limit állapota egy megosztott store-ban él (nem process-local memóriában) — enélkül a limit worker-enként külön számolna.

### 5.3 Az application log NEM tartalmaz teljes UGC-t, e-mailt, tokent vagy media URL-t

A redaction-szabály a teljes Community réteget lefedi, konzisztensen a Kör 20 push-payload redaction elvével.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Production multi-worker környezetben közös rate-limit store használható | `test_security_hardening.py` |
| A2 | IDOR-tesztcsomag zöld minden Community-endpointra | `test_security_hardening.py` |
| A3 | Forged author/verified/rank mező minden endpointon elutasított | `test_security_hardening.py` |
| A4 | Request-body-limit aktív | `test_security_hardening.py` |
| A5 | Application log nem tartalmaz teljes UGC-t/e-mailt/tokent | `test_security_hardening.py` |
| A6 | A MEGLÉVŐ CI-lépések bitre változatlanok | `git diff .github/workflows/full-gate.yml` — csak hozzáadás |
| A7 | Emergency write-disable tanulási funkció-leállás nélkül aktiválható | `test_security_hardening.py` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A rate-limit process-local memóriában él | A1 |
| Egy endpoint kimarad az IDOR-tesztcsomagból | A2 |
| Egy forged `verified` mező átmegy egy eddig nem tesztelt endpointon | A3 |
| Egy log-sor a teljes komment-szöveget tartalmazza | A5 |
| Egy meglévő CI-lépés `continue-on-error`-t kap | A6 — H-GATEGUARD, emberi döntés kell |

**A küszöb három kötelező cellája** (a request-body mérete a konfigurált `MAX_REQUEST_BODY_BYTES`-hoz képest):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | `size = MAX_REQUEST_BODY_BYTES - 1` | elfogadva |
| **rajta** (a küszöbön) | `size == MAX_REQUEST_BODY_BYTES` | elfogadva — a határ inkluzív |
| a küszöb **fölött** | `size = MAX_REQUEST_BODY_BYTES + 1` | elutasítva, 413-as válasz |

A hármas tömören: **alatt** → elfogad · **rajta** → elfogad · **fölött** → elutasít.

A határ a `MAX_REQUEST_BODY_BYTES` a záró, elfogadott érték — ez a body-size DoS-védelem alapja.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** állíts be egy process-local (nem megosztott) rate-limit store-t, futtasd a multi-worker szimulációs tesztet → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/architecture_dependency_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_security_hardening.py -q
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

1. `rate_limits.py` — közös store-adapter (pl. Redis-kompatibilis interfész, mock implementációval erre a körre).
2. `abuse_signals.py` — az aggregátor (account-age, velocity, duplicate-hash, report/block-rate).
3. `observability.py` — request ID, strukturált audit event, redaction.
4. A teljes IDOR/forged-field/audience-bypass tesztcsomag az összes eddigi Community-endpointra.
5. `full-gate.yml` bővítése ÚJ lépésekkel (meglévő érintése nélkül).
6. `docs/operations/community-incident-runbook.md` — emergency write/media-disable.
7. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **A gate lazítása.** A legkomolyabb határ — `continue-on-error` vagy lépés-törlés emberi döntést igényel (H-GATEGUARD, A6), a self-heal sem oldhatja fel.
- **A process-local rate-limit.** Multi-worker productionben ez gyakorlatilag hatástalanná tenné a limitet (A1).
- **Az UGC-szivárgás a logokba.** Egy debug-célú `logger.info(comment)` sor visszamenőleg nehezen felderíthető adatvédelmi incidens (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
