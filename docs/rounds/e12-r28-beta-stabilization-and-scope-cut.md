# E12-R28 — Beta stabilization és scope cut

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 28
- **Kör-azonosító:** `E12-R28`
- **Branch:** `<motor>/e12-r28-beta-stabilization-and-scope-cut`
- **Előfeltétel:** `E12-R27` merge-elve ÉS a Closed Beta USER általi lefuttatása (a kör bemenete a béta tapasztalata)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0464` — a szám FOGLALT (Chapter 12 batch-tartomány): a **contract freeze** szabálya kötött architekturális döntés.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "beta stabilization scope cut contract freeze preview feature"` → **[ADR 0306](../adr/0306-plan-preview-presentation-activation-boundary.md)** (plan-preview aktiválási határ): a repóban MÁR van mintája annak, hogy egy preview-funkció a core útra nem hathat. A scope-cut ezt a mintát általánosítja.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd, hogy a Closed Beta MEGTÖRTÉNT-e és van-e a `docs/beta/`-ban lezárt triage-anyag. Ha nincs béta-adat, a kör NEM indítható (`blocked` jelzés) — a scope-cut mérési döntés, nem vélemény.

## 0.0 A kör bemenete emberi mérésből jön

A béta-tapasztalat (top issue-k, funnel, támogatási terhelés) a user és a triage-jegyzőkönyvek terméke. Az implementer feladata: ezt az ANYAGOT gépileg ellenőrizhető scope-döntéssé alakítani (GA / preview / disabled / postponed), a döntést flag-profilba fordítani, és a core contractokat lefagyasztani.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/release/beta-findings.md",
  "docs/release/ga-scope.md",
  "docs/release/contract-freeze.md",
  "tool/release/verify_ga_scope.py",
  "test/tooling/ga_scope_test.dart",
  "docs/rounds/e12-r28-beta-stabilization-and-scope-cut.md",
]
gate_tests = [
  "test/tooling/ga_scope_test.dart",
  "test/tooling/beta_profile_test.dart",
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

**STOP-protokoll:** ha egy capability besorolása a béta-adatból nem következik (nincs mérés), a kimenet a `stopped` jelzés — a besorolás nem lehet becslés.

## 1. Cél

A GA-scope legyen kisebb, de stabil: minden capability mért indoklással kap GA / preview / disabled / postponed besorolást, a core contractok pedig lefagynak.

## 2. Jelenlegi állapot — mért tények

- `docs/release/`: a korábbi körök után `program-baseline.md`, `blockers.md`, `environment-matrix.md`, `kill-switches.md`, `supply-chain.md`, `ai-quality-gates.md`, `rc-checklist.md`, `client-migration.md`; `ga-scope.md` **nincs**.
- A flag-katalógus (Kör 5) és a cohort-profil (Kör 27) MEGVAN — a scope-döntés ezekre képződik le.
- Az Epic 10 (Offline AI) sáv `hold`-on áll → a helyi AI besorolása alapból `postponed`, hacsak a béta-adat mást nem indokol.
- A Chapter 14 (felismerés-helyreállítás) sáv `prepared` — a felismerési pontosság GA-kritériumát a `docs/eval/recognition-release-guard.md` hordozza.

## 3. Scope

**Benne van:** `docs/release/beta-findings.md` (a triage-anyagból származtatott top-issue és funnel összefoglaló, MINDEN állításhoz forrás) · `docs/release/ga-scope.md` (capabilityenként: besorolás + indoklás + a bizonyíték hivatkozása) · `docs/release/contract-freeze.md` (mely publikus contractok fagynak be, és mi a változtatás feltétele) · `tool/release/verify_ga_scope.py` (a besorolás ↔ flag-profil konzisztencia; preview capability nem lehet a core flow kötelező eleme) · `test/tooling/ga_scope_test.dart`.

**NINCS benne (tilos):**

- Kód-változtatás bármely feature-ben (a scope-cut ITT dokumentum + profil).
- Új flag bevezetése.
- A `docs/eval/recognition-release-guard.md` küszöbeinek átírása.
- `docs/adr/**` — az ADR 0464-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/release/beta-findings.md` | ÚJ — a béta mért tapasztalata |
| `docs/release/ga-scope.md` | ÚJ — a besorolás |
| `docs/release/contract-freeze.md` | ÚJ — a befagyasztott contractok |
| `tool/release/verify_ga_scope.py` | ÚJ — konzisztencia-ellenőrző |
| `test/tooling/ga_scope_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/**` · `backend/**` · `.github/**` · `docs/eval/**` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések (ADR 0464)

### 5.1 A preview capability NEM lehet a core flow kötelező eleme

A core tanulási út preview-funkció nélkül is végigjárható (ADR 0306 mintája). **NEM elfogadható gyengítés:** „preview, de a Today-képernyő nélküle üres" — az funkcionálisan GA.

### 5.2 A besorolás MÉRT indoklást hordoz

**NEM elfogadható gyengítés:** „stabilnak tűnik" — a béta-adat vagy a mérési riport hivatkozása kötelező.

### 5.3 A contract freeze feloldása nevesített feltételhez kötött

**NEM elfogadható gyengítés:** „szükség esetén módosítható" megfogalmazás.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Minden capability pontosan egy besorolást kap, mért indoklással | `ga_scope_test.dart` |
| A2 | A besorolás és a cohort-flag-profil konzisztens (disabled ⇒ a profilban is `false`) | `ga_scope_test.dart` |
| A3 | Preview capability nélkül a core flow végigjárható | `ga_scope_test.dart` + a Kör 11 e2e cellái |
| A4 | Minden befagyasztott contracthoz tartozik feloldási feltétel | `ga_scope_test.dart` |
| A5 | Nyitott P0/P1 blocker mellett a GA-scope explicit „nem kész" jelzést kap | `ga_scope_test.dart` a `blockers.md` olvasásával |
| A6 | A Kör 27 `beta_profile_test.dart` VÁLTOZATLANUL zöld | a §7 gate |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egy capability besorolás nélkül marad, vagy kettőt kap | A1 |
| `disabled` besorolás mellett a flag a profilban `true` | A2 |
| A core flow egy preview capabilityre támaszkodik | A3 |
| A contract freeze feloldási feltétel nélkül íródik | A4 |
| Nyitott P0 mellett a scope „GA-kész" jelzést kap | A5 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** állítsd az egyik `disabled` capability flagjét a cohort-profilban `true`-ra, futtasd a §7 gate-et → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/ga_scope_test.dart test/tooling/beta_profile_test.dart
```

A konzisztencia-ellenőrző közvetlen futtatása (kimenet a §10-be):

```bash
python3 tool/release/verify_ga_scope.py --scope docs/release/ga-scope.md --profile docs/beta/cohort-profiles.yaml
```

## 8. Implementációs sorrend

1. `docs/release/beta-findings.md` a triage-anyagból.
2. `docs/release/ga-scope.md` — besorolás + indoklás.
3. `tool/release/verify_ga_scope.py`.
4. `test/tooling/ga_scope_test.dart`.
5. `docs/release/contract-freeze.md` + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Vélemény-alapú scope.** Béta-adat nélkül a besorolás becslés (`blocked` eset).
- **Rejtett GA.** Egy preview-nek nevezett, de a core flow-hoz szükséges capability (A3).
- **Örök freeze-kivétel.** Feltétel nélküli feloldhatóság a freeze-t értelmetlenné teszi (A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
