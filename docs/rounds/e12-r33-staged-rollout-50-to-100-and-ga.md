# E12-R33 — Staged rollout 50–100 százalék és GA

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 33
- **Kör-azonosító:** `E12-R33`
- **Branch:** `<motor>/e12-r33-staged-rollout-50-to-100-and-ga`
- **Előfeltétel:** `E12-R32` merge-elve ÉS a 20%-os lépcső USER általi lezárása
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a kör GA-rekordot és záró ellenőrzést szállít.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "general availability rollout 100 percent release notes support"` → **[ADR 0065](../adr/0065-practice-engine-v2-parallel-rollout.md)** és **[ADR 0197](../adr/0197-song-trainer-shipping-rollout-boundary.md)** — a repó MÉRT rollout-mintái (párhuzamos futás, availability flag, belépési pont). A GA-rekordnak ezért a FLAG-PROFILT is rögzítenie kell, nem csak a verziót.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd, hogy a `staged-rollout-log.md` 1/5/20%-os lépcsői KITÖLTVE és jóváhagyva vannak-e. Üres napló mellett a kör nem indítható (`blocked`).

## 0.0 EMBERI KAPU

A 50% és 100% lépcső, valamint a store-oldali GA **user-művelet**. Az implementer terméke: a GA-rekord sablonja és ellenőrzője (build, flag-profil, modell-verzió, időbélyeg, támogatási linkek), a végleges release-notes generálása, és a záró konzisztencia-ellenőrzés. A kör NEM tesz közzé semmit.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/release/ga-record.md",
  "docs/release/release-notes.md",
  "tool/release/verify_ga_record.py",
  "test/tooling/ga_record_test.dart",
  "docs/rounds/e12-r33-staged-rollout-50-to-100-and-ga.md",
]
gate_tests = [
  "test/tooling/ga_record_test.dart",
  "test/tooling/rollout_decision_test.dart",
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

**STOP-protokoll:** ha a GA-rekord egy mezőjéhez nincs bizonyíték (pl. hiányzó modell-verzió a manifestben), a kimenet a `stopped` jelzés — kitöltetlen mező nem maradhat, és kitalált érték sem kerülhet bele.

## 1. Cél

A teljes elérhetőség elérése auditálhatóan: a GA-állapot minden lényeges paramétere rögzített, a support- és rollback-készenlét pedig fennmarad.

## 2. Jelenlegi állapot — mért tények

- `docs/release/staged-rollout-log.md` és `rollout-decision.md` a Kör 32 termékei.
- A release-manifest (Kör 6) hordozza a build-, modell- és tudáscsomag-verziót; a flag-profil a Kör 5 katalógus + a Kör 28 GA-scope.
- `docs/release/ga-record.md` és `release-notes.md` **nincs**.
- Store-jelenlét MA nincs (Kör 1) — a GA-rekord ezért a publikálás UTÁN kitöltendő mezőket EXPLICIT emberi jelöléssel viszi.

## 3. Scope

**Benne van:** `docs/release/ga-record.md` (GA időbélyeg, build-azonosító + SHA, flag-profil pillanatkép, modell- és tartalom-verzió, ismert hibák hivatkozása, rollback-cél, támogatási linkek) · `tool/release/verify_ga_record.py` (kitöltetlen kötelező mező, manifesttel nem egyező verzió, hiányzó rollback-cél → nem-nulla kilépés) · `test/tooling/ga_record_test.dart` · `docs/release/release-notes.md` (a Kör 6 manifestjéből és a `known-issues.md`-ből generált, determinisztikus jegyzet).

**NINCS benne (tilos):**

- Store-művelet, publikálás vagy rollout-százalék állítása.
- `lib/**`, `backend/**`, `.github/**` módosítás.
- A `staged-rollout-log.md` átírása.
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/release/ga-record.md` | ÚJ — a GA-rekord |
| `docs/release/release-notes.md` | ÚJ — végleges jegyzet |
| `tool/release/verify_ga_record.py` | ÚJ — a rekord ellenőrzője |
| `test/tooling/ga_record_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/**` · `backend/**` · `.github/**` · `docs/release/staged-rollout-log.md` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések

Nincs ADR. Három kötelező szabály:

### 5.1 A GA-rekord a FLAG-PROFILT is rögzíti

A repó mért tapasztalata (ADR 0065/0197): a rollout nem csak verzió, hanem elérhetőségi kapcsolók és belépési pontok kérdése. **NEM elfogadható gyengítés:** csak a verziószám rögzítése.

### 5.2 A verzió-mezők a MANIFESTBŐL származnak

**NEM elfogadható gyengítés:** kézzel írt verzió, ami a manifesttől eltérhet.

### 5.3 A rollback-készenlét a GA UTÁN is fennáll

A rekord megnevezi az érvényes rollback-célt és annak elérhetőségét. **NEM elfogadható gyengítés:** „GA után nincs visszaút" megfogalmazás.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Kitöltetlen kötelező mező → `verify_ga_record.py` nem-nulla kilépés | `ga_record_test.dart` |
| A2 | A rekord verzió-mezői egyeznek a release-manifesttel | `ga_record_test.dart` |
| A3 | A rekord tartalmazza a flag-profil pillanatképét | `ga_record_test.dart` |
| A4 | A rekord megnevezi az érvényes rollback-célt | `ga_record_test.dart` |
| A5 | A release-notes determinisztikus és a `known-issues.md`-re hivatkozik | `ga_record_test.dart` |
| A6 | A dokumentum kimondja, hogy a publikálás EMBERI művelet | a dokumentum |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A verziót kézzel írjuk be, manifest-ellenőrzés nélkül | A2 |
| A flag-profil kimarad a rekordból | A3 |
| A rollback-cél mező üresen marad | A4 |
| A release-notes generálási időbélyeget tartalmaz | A5 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** írj a GA-rekordba a manifestétől ELTÉRŐ build-számot, futtasd a §7 gate-et → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/ga_record_test.dart test/tooling/rollout_decision_test.dart
```

Az ellenőrző közvetlen futtatása (kimenet a §10-be):

```bash
python3 tool/release/verify_ga_record.py --record docs/release/ga-record.md
```

## 8. Implementációs sorrend

1. `docs/release/ga-record.md` sablon (emberi mezők jelölésével).
2. `tool/release/verify_ga_record.py`.
3. `test/tooling/ga_record_test.dart`.
4. `docs/release/release-notes.md` generálás.
5. A valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Auditálhatatlan GA.** Flag-profil nélkül később nem rekonstruálható, mit kaptak a felhasználók (A3).
- **Verzió-eltérés.** Kézi mező és manifest szétcsúszása (A2).
- **Rollback-készenlét elvesztése.** A GA nem szünteti meg a visszaút kötelezettségét (§5.3).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
