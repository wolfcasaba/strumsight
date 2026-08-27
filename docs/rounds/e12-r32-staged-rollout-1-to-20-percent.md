# E12-R32 — Staged rollout 1–20 százalék

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 32
- **Kör-azonosító:** `E12-R32`
- **Branch:** `<motor>/e12-r32-staged-rollout-1-to-20-percent`
- **Előfeltétel:** `E12-R31` merge-elve (belső production cohort + rollout-csomag sablon)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a kör döntési eljárást és naplózó eszközt szállít.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "staged rollout percentage observation window decision packet"` → **[ADR 0197](../adr/0197-song-trainer-shipping-rollout-boundary.md)** (a rollout-határ áthelyezése és a belépési pont mint a rollout része) — a repó MÉRT tapasztalata, hogy a rollout nem csak százalék, hanem BELÉPÉSI PONT kérdése is. A napló ezt is rögzíti.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd, hogy a Kör 31 rollout-csomag sablonja és a Kör 19 dashboard-sémája MEGVAN, és hogy a Kör 5 kill switch dry-runja lefutott. Enélkül a lépcsőzés vak.

## 0.0 EMBERI KAPU

A rollout-százalék állítása **kizárólag user-művelet** (store/console hozzáférés). Az implementer terméke: a döntési napló SÉMÁJA és ellenőrzője, ami minden lépcsőhöz kötelezővé teszi a megfigyelési ablakot, a mért adatot és a döntést — és amely a hiányos csomagot elutasítja. A kör NEM állít rollout-százalékot.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/release/staged-rollout-log.md",
  "docs/release/rollout-decision.md",
  "tool/release/verify_rollout_decision.py",
  "test/tooling/rollout_decision_test.dart",
  "docs/rounds/e12-r32-staged-rollout-1-to-20-percent.md",
]
gate_tests = [
  "test/tooling/rollout_decision_test.dart",
  "test/tooling/freeze_policy_test.dart",
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

**STOP-protokoll:** ha a döntési séma egy kötelező mezőjéhez a fán nincs adatforrás (pl. nincs telemetria), a kimenet a `stopped` jelzés vagy a mező EXPLICIT „manuális megfigyelés" jelölése — kitalált automatizmus TILOS.

## 1. Cél

Az első publikus lépcsők (1% → 5% → 20%) legyenek dokumentált, mért döntések: minden lépés előtt megfigyelési ablak, mért adat és explicit jóváhagyás — vak, automatikus rollout nélkül.

## 2. Jelenlegi állapot — mért tények

- `docs/release/rollout-packet-template.md` a Kör 31 terméke; `staged-rollout-log.md` **nincs**.
- Telemetria-GYŰJTÉS nincs (a Kör 19 szerződést adott) — a megfigyelés forrása a store-konzol, a visszajelzés és a diagnosztikai bundle. A séma ezt EXPLICIT jelöléssel kezeli.
- A kill switch (Kör 5) és a rollback (Kör 26) MÉRT úton elérhető — a döntési csomag ezekre hivatkozik.
- A `docs/release/blockers.md` a P0/P1 forrás.

## 3. Scope

**Benne van:** `docs/release/rollout-decision.md` (a döntési séma: lépcső, megfigyelési ablak hossza, mért mutatók, forrásuk — GÉPI vagy MANUÁLIS —, döntés, döntéshozó, rollback-cél) · `tool/release/verify_rollout_decision.py` (hiányzó mező, hiányzó megfigyelési ablak, nyitott P0/P1 melletti előrelépés → nem-nulla kilépés) · `test/tooling/rollout_decision_test.dart` · `docs/release/staged-rollout-log.md` (a napló váza az 1/5/20%-os lépcsőkkel, kitöltésre készen).

**NINCS benne (tilos):**

- Tényleges rollout-százalék állítása vagy store-művelet.
- Automatikus (emberi jóváhagyás nélküli) lépcsőzés bármilyen formában.
- `lib/**`, `.github/**` módosítás.
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/release/rollout-decision.md` | ÚJ — a döntési séma |
| `tool/release/verify_rollout_decision.py` | ÚJ — az ellenőrző |
| `test/tooling/rollout_decision_test.dart` | a §6 cellái |
| `docs/release/staged-rollout-log.md` | ÚJ — a napló váza |

**Tilos zóna:** `lib/**` · `backend/**` · `.github/**` · `docs/release/blockers.md` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések

Nincs ADR. Három kötelező szabály:

### 5.1 Nincs automatikus lépcsőzés

Minden lépcső explicit emberi jóváhagyás. **NEM elfogadható gyengítés:** „ha 24 órán át nincs hiba, automatikusan lépjünk" szabály.

### 5.2 Nyitott P0/P1 mellett NINCS előrelépés

**NEM elfogadható gyengítés:** „ismert, de nem kritikus" átsorolás mérési indoklás nélkül.

### 5.3 A mutató FORRÁSA jelölt: gépi vagy manuális

**NEM elfogadható gyengítés:** olyan mutató, amiről a séma azt sugallja, hogy automatikusan gyűlik, holott nincs gyűjtés.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Hiányzó kötelező mező (ablak, mutató, döntéshozó) → nem-nulla kilépés | `rollout_decision_test.dart` |
| A2 | Nyitott P0/P1 melletti előrelépés → nem-nulla kilépés | `rollout_decision_test.dart` (a `blockers.md` olvasásával) |
| A3 | Minden mutató forrás-jelölést hordoz (`machine` / `manual`) | `rollout_decision_test.dart` |
| A4 | A napló váza mind a három lépcsőt (1%, 5%, 20%) tartalmazza, rollback-céllal | a dokumentum |
| A5 | A séma kimondja: a százalék állítása EMBERI művelet | a dokumentum |
| A6 | A Kör 30 `freeze_policy_test.dart` VÁLTOZATLANUL zöld | a §7 gate |

**Küszöb-cellahármas a megfigyelési ablakra** (a séma szerinti minimális ablak `W` óra; a határ INKLUZÍV, azaz pontosan `W` óra elteltével a lépés engedélyezett): a küszöb **alatt** (`W-1` óra megfigyelés) → az ellenőrző nem-nulla kóddal lép ki; **pontosan rajta** (`W`) → engedélyezett; a küszöb **fölött** (`W+1`) → engedélyezett.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Az ellenőrző nem olvassa a `blockers.md`-t | A2 |
| A mutatók forrás-jelölés nélkül kerülnek a sémába | A3 |
| Az ablak-ellenőrzés szigorú `>`-t használ | a küszöb-cellahármas „pontosan rajta" cellája |
| A séma automatikus előrelépést enged | A5 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vedd ki a `blockers.md`-olvasást az ellenőrzőből, futtasd a §7 gate-et → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/rollout_decision_test.dart test/tooling/freeze_policy_test.dart
```

Az ellenőrző közvetlen futtatása (kimenet a §10-be):

```bash
python3 tool/release/verify_rollout_decision.py --log docs/release/staged-rollout-log.md
```

## 8. Implementációs sorrend

1. `docs/release/rollout-decision.md` — a séma, forrás-jelöléssel.
2. `tool/release/verify_rollout_decision.py`.
3. `test/tooling/rollout_decision_test.dart` — a küszöb-cellahármassal.
4. `docs/release/staged-rollout-log.md` váz.
5. A valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Vak rollout.** Telemetria hiányában a „mért adat" könnyen üres marad — ezért kötelező a forrás-jelölés (A3).
- **Automatizmus-csábítás.** Az automatikus lépcsőzés kényelmes és pontosan az, amit a SDD tilt (A5).
- **Blocker-átsorolás.** A P1 „nem kritikus"-sá minősítése a legolcsóbb módja a kapu megkerülésének (§5.2).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
