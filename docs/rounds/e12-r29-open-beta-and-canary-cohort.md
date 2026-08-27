# E12-R29 — Open Beta és canary cohort

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 29
- **Kör-azonosító:** `E12-R29`
- **Branch:** `<motor>/e12-r29-open-beta-and-canary-cohort`
- **Előfeltétel:** `E12-R28` merge-elve (a GA-scope és a befagyasztott contractok)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a kör kapacitás- és cohort-eljárást szállít; a rate-limit és moderation szerződések már léteznek.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "open beta canary cohort rate limit moderation capacity cost"` → **[L34](../LESSONS.md#l34)** (a secret scan a megőrzött globális configra és backupra is terjedjen ki) és a `halts/round-status-E09-{18,21}` (média- és challenge-körök). A kapacitás-nézetnek tehát a MEGŐRZÖTT konfigurációra és a média-tárolásra is ki kell terjednie.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd a `backend/app/ratelimit.py` MÉRT korlátait és a Community moderation runbookot (`docs/operations/community-moderation-runbook.md`). A kapacitás-terv EZEKRE a mért értékekre épül.

## 0.0 EMBERI KAPU

Az Open Beta megnyitása (szélesebb cohort engedése) **user-döntés**. Az implementer terméke: a canary-cohort konfiguráció, a kapacitás- és költség-guard mérése, a rate-limit és moderation füst-cellák, valamint az indítási csomag. A kör NEM nyit cohortot.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/beta/open-beta-launch.md",
  "docs/operations/capacity-review.md",
  "backend/tests/test_capacity_guards.py",
  "test/tooling/canary_cohort_test.dart",
  "docs/rounds/e12-r29-open-beta-and-canary-cohort.md",
]
gate_tests = [
  "test/tooling/canary_cohort_test.dart",
  "test/tooling/ga_scope_test.dart",
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

**STOP-protokoll:** ha a kapacitás-mérés a MÉRT backend-korlátok mellett nem elégséges a tervezett cohort-méretre, a kimenet a `stopped` jelzés — a korlátok felemelése külön, üzemeltetési döntés.

## 1. Cél

A szélesebb cohort megnyitása legyen kapacitás- és moderáció-oldalról mérten előkészített, cohort-izolációval és bizonyított költség-guarddal.

## 2. Jelenlegi állapot — mért tények

- `backend/app/ratelimit.py` **létezik** — a MÉRT rate-limit forrás; `backend/tests/test_hardening.py` fedi.
- Community moderation: `e09_r27_0020_community_moderation` migráció + `docs/operations/community-moderation-runbook.md`.
- `docs/beta/`: a Kör 22/27 után `enrollment.md`, `tester-consent.md`, `feedback-triage.md`, `closed-beta-launch.md`, `cohort-profiles.yaml`, `daily-triage-template.md`.
- Költség-guard MA nincs implementálva (a Chapter 12 §23.3 kéri) — a kör MÉRÉST és eljárást ad, nem szolgáltatói integrációt.

## 3. Scope

**Benne van:** `docs/beta/open-beta-launch.md` — a canary-cohort profilja és a nyitási lépcsők (a Kör 27 `cohort-profiles.yaml` fájlját a kör NEM írja át; a canary-profil ebben a dokumentumban él, és a `canary_cohort_test.dart` méri az izolációját) · `docs/operations/capacity-review.md` (MÉRT rate-limit, tárolási és moderációs kapacitás, és a belőle következő MAXIMÁLIS cohort-méret) · `backend/tests/test_capacity_guards.py` (rate-limit füst, oversized upload, moderation-queue füst) · `test/tooling/canary_cohort_test.dart` (cohort-izoláció: a canary flag-profil nem szivárog a stabil cohortba).

**NINCS benne (tilos):**

- Cohort tényleges megnyitása vagy tesztelő-meghívás.
- `backend/app/**` és `lib/**` módosítás.
- A Kör 27 `cohort-profiles.yaml` átírása (kiegészítés csak akkor, ha az nem ütközik a Kör 27 mércéjével).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/beta/open-beta-launch.md` | ÚJ — canary-profil és lépcsők |
| `docs/operations/capacity-review.md` | ÚJ — mért kapacitás és cohort-plafon |
| `backend/tests/test_capacity_guards.py` | a backend-oldali §6 cellák |
| `test/tooling/canary_cohort_test.dart` | a kliens-oldali §6 cellák |

**Tilos zóna:** `backend/app/**` · `lib/**` · `docs/beta/cohort-profiles.yaml` · `.github/**` · `docs/adr/**`

## 5. Kötött architekturális döntések

Nincs ADR. Két kötelező szabály:

### 5.1 A cohort-plafon MÉRT korlátokból SZÁMOLT

**NEM elfogadható gyengítés:** kerek szám („1000 tesztelő") mérés nélkül.

### 5.2 A canary-profil nem szivároghat a stabil cohortba

**NEM elfogadható gyengítés:** közös flag-forrás cohort-megkülönböztetés nélkül.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A `capacity-review.md` a MÉRT rate-limit értékekből számolja a cohort-plafont, forrás-hivatkozással | a dokumentum + `canary_cohort_test.dart` |
| A2 | Rate-limit füst: a korlát fölötti kérés elutasított | `test_capacity_guards.py` |
| A3 | Oversized upload elutasított | `test_capacity_guards.py` |
| A4 | Moderation-queue füst: a bejelentés a sorba kerül és lekérdezhető | `test_capacity_guards.py` |
| A5 | A canary flag-profil izolált: a stabil cohort értékei nem változnak | `canary_cohort_test.dart` |
| A6 | A dokumentum kimondja, hogy a cohort megnyitása EMBERI döntés | a dokumentum |

**Küszöb-cellahármas a rate-limitre** (a MÉRT korlát `N` kérés/ablak; a határ INKLUZÍV, azaz az `N`-edik kérés MÉG átmegy): a küszöb **alatt** (`N-1`) → elfogadva; **pontosan rajta** (`N`) → elfogadva; a küszöb **fölött** (`N+1`) → elutasítva (429).

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A cohort-plafon becsült szám | A1 |
| A rate-limit cella csak a korlát alatti esetet méri | a küszöb-cellahármas „fölött" cellája |
| A canary flagek a stabil cohortra is hatnak | A5 |
| A dokumentum indítottnak írja le az Open Betát | A6 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** állítsd a canary-profil egyik flagjét a stabil cohortra is érvényesre a teszt-fixture-ben, futtasd a §7 gate-et → az **A5** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/canary_cohort_test.dart test/tooling/ga_scope_test.dart
```

Backend sáv (külön processzként):

```bash
cd backend && python -m pytest tests/test_capacity_guards.py tests/test_hardening.py -q
```

## 8. Implementációs sorrend

1. A MÉRÉS: `ratelimit.py` korlátai, média-tárolási korlátok, moderation-sor viselkedése.
2. `backend/tests/test_capacity_guards.py` — a küszöb-cellahármassal.
3. `docs/operations/capacity-review.md` — a SZÁMOLT plafon.
4. `test/tooling/canary_cohort_test.dart`.
5. `docs/beta/open-beta-launch.md` (emberi kapuval) + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Becsült kapacitás.** Egy kerek szám az első terhelésnél kiderül (A1).
- **Profil-szivárgás.** A canary-flagek stabil cohortra hatása valódi felhasználói kárt okoz (A5).
- **Moderációs terhelés.** A sor füst-cellája nem mér emberi kapacitást — a dokumentum ezt mondja ki, nem hallgatja el.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
