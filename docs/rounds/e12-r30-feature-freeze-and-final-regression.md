# E12-R30 — Feature freeze és final regression

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 30
- **Kör-azonosító:** `E12-R30`
- **Branch:** `<motor>/e12-r30-feature-freeze-and-final-regression`
- **Előfeltétel:** `E12-R28` és `E12-R29` merge-elve (GA-scope + Open Beta tapasztalat)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a kör eljárást és riportot szállít; a freeze szabályát az ADR 0464 (Kör 28) rögzíti.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "feature freeze final regression known issues changelog"` → a `halts/round-status-E08-R07`, `E09-R01` és `E09-R14` merge-elt körök (epic-nyitó/záró mérési minták). Release-domain előzmény nincs — ez a projekt ELSŐ feature-freeze köre.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd, hogy a `docs/release/blockers.md` naprakész-e, és hogy a Kör 25 RC-workflow-ja LEFUTOTT-e zölden legalább egyszer. A final regression a MÉRT kapuk újrafuttatása, nem újak kitalálása.

## 0.0 Mit jelent itt a „teljes regresszió"

A boxon a teljes Flutter-suite ~15 perc, a CI-ban 4–5; a MÉRT szabály (ADR 0053) szerint a teljes suite + property-gate + APK a CI-ban fut. A kör „final regression"-je ezért: (a) egy ZÖLD `build-apk.yml` / RC-dispatch az orchesztrátortól, (b) a backend és a release-eszközök lokális sávja, (c) a `known-issues.md` MÉRT tartalommal. A kör NEM ír új gate-et.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/release/feature-freeze.md",
  "docs/release/known-issues.md",
  "CHANGELOG.md",
  "tool/release/verify_freeze.py",
  "test/tooling/freeze_policy_test.dart",
  "docs/rounds/e12-r30-feature-freeze-and-final-regression.md",
]
gate_tests = [
  "test/tooling/freeze_policy_test.dart",
  "test/tooling/ga_scope_test.dart",
]
native_gate = true
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a regresszió P0/P1 hibát talál, a kimenet a `stopped` jelzés és jelentés — a javítás önálló kör, és a freeze pontosan azért van, hogy ez látszódjon.

## 1. Cél

Kimondott scope- és kódfagyasztás, MÉRT teljes regresszió és őszinte known-issues lista a Release Candidate előtt.

## 2. Jelenlegi állapot — mért tények

- `CHANGELOG.md` **nem létezik** a repóban (a történet a `HANDOFF.md`-ben és a PR-okban él).
- `docs/release/` a korábbi körök után gazdag; `feature-freeze.md` és `known-issues.md` **nincs**.
- A merge-kapu `build-apk.yml` / `full-gate.yml`; a választást a `tools/round-ci-plan.py` dönti a brief `native_gate` mezőjéből.
- A property-gate `test/property/` alatt él, CI-ban randomizált maggal fut (HORIZON konvenció).
- A `docs/release/blockers.md` (Kör 1) a blocker-nyilvántartás egyetlen forrása.

## 3. Scope

**Benne van:** `docs/release/feature-freeze.md` (mi fagy be, mi az engedélyezett változás — kizárólag P0/P1/P2 blocker, és ki hagyhatja jóvá) · `tool/release/verify_freeze.py` (a freeze utáni diff osztályozása: a nem-blocker változás nem-nulla kilépést ad) · `test/tooling/freeze_policy_test.dart` · `docs/release/known-issues.md` (a MÉRT nyitott hibák, súlyossággal és megkerülő úttal) · `CHANGELOG.md` (a release-történet első, generált változata a Kör 6 manifest-adataiból).

**NINCS benne (tilos):**

- Feature-fejlesztés vagy hibajavítás (a freeze tárgya éppen ez).
- ÚJ gate vagy workflow.
- A `blockers.md` átírása (olvasni kell, nem szépíteni).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/release/feature-freeze.md` | ÚJ — a fagyasztási szabály |
| `docs/release/known-issues.md` | ÚJ — a nyitott hibák |
| `CHANGELOG.md` | ÚJ — generált release-történet |
| `tool/release/verify_freeze.py` | ÚJ — a freeze-ellenőrző |
| `test/tooling/freeze_policy_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/**` · `backend/**` · `.github/**` · `docs/release/blockers.md` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések

Nincs ADR. Két kötelező szabály:

### 5.1 A freeze alatti változás OSZTÁLYOZOTT és indokolt

Minden commit vagy P0/P1/P2 blocker-javítás, vagy dokumentáció. **NEM elfogadható gyengítés:** „apró javítás, nem számít" kategória.

### 5.2 A known-issues lista ŐSZINTE

Minden ismert, nyitott hiba felkerül, még ha kellemetlen is. **NEM elfogadható gyengítés:** a „nem reprodukálható" kategóriába söprés mérési kísérlet nélkül.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | `verify_freeze.py` a nem-blocker változást nem-nulla kóddal jelzi | `freeze_policy_test.dart` |
| A2 | A `known-issues.md` minden tétele hordoz súlyosságot, hatást és megkerülő utat (vagy annak hiányát) | `freeze_policy_test.dart` |
| A3 | A `known-issues.md` minden P0/P1 tétele szerepel a `blockers.md`-ben is (nincs elrejtett blocker) | `freeze_policy_test.dart` |
| A4 | A `CHANGELOG.md` a Kör 6 manifest-mezőiből generált, és determinisztikus | `freeze_policy_test.dart` |
| A5 | ZÖLD teljes CI-futás a kör-branchen | orchesztrátor-dispatch linkje a §10-ben |
| A6 | A kör egyetlen termékkód-fájlt sem módosít | `git diff --stat` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A freeze-ellenőrző csak figyelmeztet a nem-blocker változásra | A1 |
| Egy P1 hiba csak a known-issues-ban szerepel, a blockers-ben nem | A3 |
| A CHANGELOG kézzel íródik, manifest-hivatkozás nélkül | A4 |
| A kör „menet közben" javít egy talált hibát | A6 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vegyél fel a `known-issues.md`-be egy P1 tételt, ami a `blockers.md`-ben NEM szerepel, futtasd a §7 gate-et → az **A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/freeze_policy_test.dart test/tooling/ga_scope_test.dart
```

A freeze-ellenőrző közvetlen futtatása (kimenet a §10-be):

```bash
python3 tool/release/verify_freeze.py --since <freeze-sha>
```

A teljes suite + property-gate + APK a CI-ban fut (ADR 0053) — a dispatch az orchesztrátoré.

## 8. Implementációs sorrend

1. `docs/release/feature-freeze.md` — a szabály.
2. `tool/release/verify_freeze.py` + `test/tooling/freeze_policy_test.dart`.
3. `docs/release/known-issues.md` a MÉRT nyitott hibákból.
4. `CHANGELOG.md` generálás.
5. A valódi-sértés próba a §10-be; a CI-dispatch az orchesztrátortól.

## 9. Kockázatok

- **Szépített known-issues.** A GA utáni meglepetések forrása (A2, A3).
- **Freeze-szivárgás.** „Apró" változások a freeze alatt (A1).
- **Regresszió-lelet elfedése.** A talált P0/P1 `stopped` jelzés, nem gyors javítás (§0.0).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
