# E15-R03 — Elérhetőségi audit és az örökség-képernyők visszavonási terve

- **Státusz:** PREPARED (előre megírva 2026-08-28, kód olvasva: `main @ 4cb32eb0`)
- **Típus:** Chapter 15 (UI-aktiválás és -befejezés), Kör 3
- **Kör-azonosító:** `E15-R03`
- **Branch:** `<motor>/e15-r03-legacy-reachability-audit-and-retirement`
- **Előfeltétel:** `E15-R02` merge-elve (a shell bekapcsolása UTÁN mérhető, mi érhető el valójában)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0468` — a szám FOGLALT (Chapter 15 batch-tartomány).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "legacy screen retirement route reachability dead code deprecation"` → **[ADR 0065](../adr/0065-practice-engine-v2-parallel-rollout.md)** (a V2 a legacy MELLETT fut, availability flag mögött) és **[L449](../LESSONS.md#l449)** (a `StatefulShellRoute.indexedStack` életben tartja a fülek állapotát — az „elérhetetlen" képernyő nem feltétlenül halott). A kör ezért nem törölhet a `grep` alapján.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** futtasd újra a MÉRÉST, mert az `E15-R02` a shellel új utakat nyitott:
> ```bash
> for f in $(find lib/features -name '*_screen.dart' | sort); do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
> ```
> A megíráskor: **43 migrált / 96 képernyő**, ebből **53 legacy**; a routerben név szerint hivatkozott legacy képernyők száma **27**, a routerből közvetlenül NEM hivatkozott **26**.

## 0.0 Miért kell ez a kör a migráció ELÉ

53 képernyő migrálása drága. A MÉRÉS szerint azonban a legacy halmaz egy része felváltott, párhuzamos réteg (`library/` ↔ `library_v2/`, `songs/` ↔ `song_trainer/`, `progress/` ↔ `progress_v2/`, `analyze/` ↔ `audio_analysis/`): ezeket migrálni pazarlás, ha a felhasználó soha nem látja őket. A „nem hivatkozza a router" viszont NEM bizonyíték a halálra: egy képernyőt `Navigator.push` is elérhet egy másik képernyőről. A kör ezt a különbséget méri meg, és a döntést (migrálandó / visszavonandó / marad) írásba teszi.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "tool/check_screen_reachability.dart",
  "test/tooling/screen_reachability_test.dart",
  "docs/ui/legacy-backlog.md",
  "docs/ui/migration-status.md",
  "docs/ui/retirement-plan.md",
  "docs/rounds/e15-r03-legacy-reachability-audit-and-retirement.md",
]
gate_tests = [
  "test/tooling/screen_reachability_test.dart",
  "test/ui/ui_inventory_test.dart",
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

**STOP-protokoll:** ha az audit szerint egy képernyőt TÖRÖLNI kellene, a kimenet a `stopped` jelzés és a terv — a törlés önálló, review-zott kör, mert felhasználói útvonalat szüntet meg.

## 1. Cél

Gépi, ismételhető mérés arról, MELYIK képernyő érhető el a felhasználó számára, és ebből egy döntési tábla: mit migrálunk (E15-R04…R11), mit vonunk vissza, és mi marad érintetlenül.

## 2. Jelenlegi állapot — mért tények

- `dart run tool/ui_inventory.dart` → **96** képernyő-forrás; a `test/ui/ui_inventory_test.dart` EGZAKT `hasLength(...)` állítást tesz rá.
- MÉRT megoszlás: **43 migrált** (importálja a `core/design_system`-et közvetlenül vagy `*ThemeScope`-on át), **53 legacy**.
- A routerben név szerint hivatkozott legacy képernyők: **27** (pl. `tutor_*`, `analyze_screen`, `gamification/*`, `learn/*`, `library/*`, `practice/*`, `progress_screen`, `song_trainer/*`, `songs/*`, `streak_screen`, `onboarding_screen`).
- A routerből közvetlenül NEM hivatkozott legacy képernyők: **26** (pl. `song_trainer/song_library_screen`, `practice_generator/*`, `vision/*`, `audio_analysis/capture/*`, `community/followers_screen`) — ezek egy részét MÁS képernyő `Navigator.push`-olja; ezt a kör méri meg, nem feltételezi.
- `tool/check_screen_reachability.dart` és `docs/ui/retirement-plan.md` **nem létezik**.
- A `lib/features/library/`, `lib/features/songs/`, `lib/features/progress/`, `lib/features/analyze/` fák MÉRHETŐEN párhuzamosak a `library_v2` / `song_trainer` / `progress_v2` / `audio_analysis` fákkal.

## 3. Scope

**Benne van:** `tool/check_screen_reachability.dart` — MINDEN `*_screen.dart`-ra megmondja: (a) hivatkozza-e a router, (b) hivatkozza-e bármely másik képernyő/widget (`Navigator.push`, `context.go`, `showModalBottomSheet` konstruktor-hívás), (c) van-e rá teszt; a kimenet gépileg olvasható (JSON) és emberi tábla · `test/tooling/screen_reachability_test.dart` (a checker cellái + az az invariáns, hogy MINDEN elérhető képernyő szerepel a migrációs tervben) · `docs/ui/retirement-plan.md` — képernyőnként: elérhető? migrálandó? visszavonandó? melyik E15 kör viszi? · a `migration-status.md` és a `legacy-backlog.md` frissítése a MÉRT számokkal.

**NINCS benne (tilos):**

- Bármely `lib/**` fájl módosítása vagy törlése.
- Route eltávolítása.
- A `ui_inventory_test.dart` egzakt számának megváltoztatása (a kör nem hoz és nem visz képernyőt).
- `docs/adr/**` — az ADR 0468-at a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `tool/check_screen_reachability.dart` | ÚJ — az elérhetőség-mérő |
| `test/tooling/screen_reachability_test.dart` | a §6 cellái |
| `docs/ui/retirement-plan.md` | ÚJ — a döntési tábla |
| `docs/ui/migration-status.md` · `docs/ui/legacy-backlog.md` | a MÉRT számok frissítése |

**Tilos zóna:** `lib/**` · `test/ui/goldens/**` · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0468)

### 5.1 Az elérhetőség MÉRT, nem feltételezett

A checker a router MELLETT az imperatív navigációt is nézi. **NEM elfogadható gyengítés:** „a router nem hivatkozza, tehát halott" következtetés — [L449](../LESSONS.md#l449) hibaosztálya.

### 5.2 A visszavonás JAVASLAT, nem végrehajtás

A kör tervet ír; a törlés/route-eltávolítás külön kör, mert felhasználói utat szüntet meg. **NEM elfogadható gyengítés:** „ez úgyis halott" alapon végrehajtott törlés.

### 5.3 Minden ELÉRHETŐ képernyőhöz tartozik migrációs kör

A terv nem hagyhat elérhető, de gazdátlan képernyőt. **NEM elfogadható gyengítés:** „később" bejegyzés kör-hozzárendelés nélkül.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A checker MIND a 96 képernyőre ad elérhetőségi ítéletet, forrás-hivatkozással | `screen_reachability_test.dart` |
| A2 | Az imperatív navigáció (`Navigator.push`, `context.go`) is számít elérhetőségnek | `screen_reachability_test.dart` fixture-cella |
| A3 | Minden ELÉRHETŐ, még legacy képernyőhöz tartozik nevesített E15 kör a tervben | `screen_reachability_test.dart` (a terv ↔ mérés összevetése) |
| A4 | A terv minden „visszavonandó" tételéhez indok és a felváltó képernyő szerepel | `docs/ui/retirement-plan.md` + a teszt mező-cellája |
| A5 | A `ui_inventory_test.dart` egzakt száma VÁLTOZATLAN | a §7 gate |
| A6 | A `migration-status.md` MÉRT (nem becsült) számokat tartalmaz, a mérés parancsával együtt | a dokumentum |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A checker csak a routert nézi | A2 |
| Egy elérhető legacy képernyő kimarad a tervből | A3 |
| A „visszavonandó" tétel indok nélkül kerül a listára | A4 |
| A kör „mellékesen" hozzáad vagy töröl egy képernyőt | A5 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vedd ki a tervből az egyik elérhető legacy képernyő sorát, futtasd a §7 gate-et → az **A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/screen_reachability_test.dart test/ui/ui_inventory_test.dart
```

A mérő közvetlen futtatása (a kimenet a §10-be):

```bash
dart run tool/check_screen_reachability.dart --format table
```

## 8. Implementációs sorrend

1. `tool/check_screen_reachability.dart` — router + imperatív navigáció + teszt-lefedettség.
2. `test/tooling/screen_reachability_test.dart`.
3. `docs/ui/retirement-plan.md` a MÉRT eredményből.
4. `migration-status.md` és `legacy-backlog.md` frissítés + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Hamis halott.** Egy imperatívan elért képernyő „halottnak" minősítése később felhasználói zsákutcát okozna (A2).
- **Terv-vakfolt.** Elérhető, de körhöz nem rendelt képernyő a sáv végén migrálatlan marad (A3).
- **Statikus elemzés korlátai.** A checker nem lát dinamikus (reflexív) navigációt — ezt a dokumentum mondja ki, nem hallgatja el.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
