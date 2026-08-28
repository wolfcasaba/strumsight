# E15-R03 — Elérhetőségi audit és az örökség-képernyők visszavonási terve

- **Státusz:** READY (pre-flight lefutott 2026-08-28, kód ÚJRAMÉRVE: `main @ fc880063`)
- **Típus:** Chapter 15 (UI-aktiválás és -befejezés), Kör 3
- **Kör-azonosító:** `E15-R03`
- **Branch:** `sonnet-impl/e15-r03-legacy-reachability-audit-and-retirement`
- **Előfeltétel:** `E15-R02` merge-elve (a shell bekapcsolása UTÁN mérhető, mi érhető el valójában) — TELJESÜLT (`9dc0b1e6`)
- **Brief szerzője:** Claude (Opus 5)
- **Kiosztott ADR:** **`ADR 0470`** — lásd a §0.0.A/R1 revíziót (a brief eredeti `0468`-a időközben elkelt).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "legacy screen retirement route reachability dead code deprecation"` → **[ADR 0065](../adr/0065-practice-engine-v2-parallel-rollout.md)** (a V2 a legacy MELLETT fut, availability flag mögött) és **[L449](../LESSONS.md#l449)** (a `StatefulShellRoute.indexedStack` életben tartja a fülek állapotát — az „elérhetetlen" képernyő nem feltétlenül halott). A kör ezért nem törölhet a `grep` alapján.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** futtasd újra a MÉRÉST, mert az `E15-R02` a shellel új utakat nyitott:
> ```bash
> for f in $(find lib/features -name '*_screen.dart' | sort); do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
> ```
> A megíráskor: **43 migrált / 96 képernyő**, ebből **53 legacy**; a routerben név szerint hivatkozott legacy képernyők száma **27**, a routerből közvetlenül NEM hivatkozott **26**.
>
> **A pre-flight ezt LEFUTTATTA — az eredmény a §0.0.A-ban. A fenti 27/26 ELAVULT, ne használd.**

## 0.0.A Pre-flight revízió (Claude / Opus 5, 2026-08-28, `main @ fc880063`)

Ez a szakasz a brief kötelező §0.0 revíziója. Minden állítása MÉRT, a mérő
paranccsal együtt. Ahol a brief törzse mást mond, **ez a szakasz az erősebb**.

### R1 — Az ADR-szám `0468` → **`0470`**

A brief `0468`-at foglalta le, de azt időközben a merge-elt **E12-R09** kör
használta el (`04ae8918 [E12-R09] Domain event katalógus és schema registry
(ADR 0468)`, `docs/adr/0468-domain-event-catalog-and-schema-registry.md`).
Egy merge-elt ADR-hez nem nyúlunk (ADR 0087 §2 **H1**), ezért a szám a
foglalótól jött, nem `ls`-sel (ADR 0171 §1.0.1):

```bash
tools/round-slots.py reserve-adr --round E15-R03   # → 0470
```

A kör ADR-je: **[`docs/adr/0470-screen-reachability-is-measured-not-assumed.md`](../adr/0470-screen-reachability-is-measured-not-assumed.md)**,
a Claude írta ebben a pre-flightban. A brief §5 „Kötött architekturális
döntések (ADR 0468)" címe és a §3 tilos-zóna `docs/adr/**` sora ugyanígy
`0470`-re értendő.

### R2 — A képernyő-számok VÁLTOZATLANOK, a router-bontás NEM

```bash
find lib/features -name '*_screen.dart' | wc -l          # 96   (a brief 96-ja áll)
# migrált/legacy:
mig=0; leg=0
for f in $(find lib/features -name '*_screen.dart' | sort); do
  if grep -q design_system "$f"; then mig=$((mig+1)); else leg=$((leg+1)); fi
done; echo "MIGRATED=$mig LEGACY=$leg"                    # 43 / 53  (a brief 43/53-a áll)
```

A **§2 router-bontása viszont elavult**, és a szám mérés-MÓDSZER-függő — épp
ezért a kör terméke a gépi mérő, nem egy szám a briefben. A pre-flight három
módszert futtatott ugyanazon az 53 legacy képernyőn:

| Módszer | Hivatkozott | Nem hivatkozott |
|---|---|---|
| a brief §2 állítása (megíráskor) | 27 | 26 |
| basename-egyezés CSAK `app_router.dart`-ban | 28 | 25 |
| **osztálynév VAGY basename, mind a három `lib/app/routing/*` fájlban** | **33** | **20** |

A növekmény oka MÉRT és várt: az `E15-R02` (ADR 0467) bekapcsolta az adaptív
shellt, tehát a `lib/app/routing/adaptive_shell_routes.dart` új utakat nyitott
(pl. `AppRoutes.visionSession`, `adaptive_shell_routes.dart:42`).

**Az implementer NEM ezeket a számokat írja be a dokumentumokba** — a
`tool/check_screen_reachability.dart` MÉRT kimenetét írja be. A fenti tábla
csak azt bizonyítja, hogy a brief §2 két száma (27/26) nem használható
bemenetként.

### R3 — MÉRT csapda: a router BARREL-en át is hivatkozik → az útvonal-egyezés HAMIS „halottat" ad

```bash
grep -c "public.dart'"  lib/app/routing/app_router.dart   # 3
grep -c "_screen.dart'" lib/app/routing/app_router.dart   # 46
grep -n "screen" lib/features/vision/public.dart          # 3 képernyőt RE-EXPORTÁL
```

A router 46 képernyőt közvetlenül importál, de **3 feature-t a `public.dart`
barrelén keresztül** ér el, és pl. a `vision/public.dart` három képernyőt
re-exportál (`vision_setup_screen`, `guitar_calibration_screen`,
`vision_session_screen`). Egy CSAK import-útvonalat néző checker ezt a hármat
„elérhetetlennek" jelentené — ez a [L190](../LESSONS.md#l190) /
[L193](../LESSONS.md#l193) barrel-szimbólum-rés hibaosztálya, és egy élő
felhasználói út törlését javasolná.

**Ebből kötelező tervezési megkötés lett: [ADR 0470 D3](../adr/0470-screen-reachability-is-measured-not-assumed.md)
— a checker OSZTÁLYNÉVRE illeszt, nem fájlnévre.** Az import-útvonal legfeljebb
másodlagos jelzés lehet, önmagában SOHA nem dönthet „elérhetetlen"-ről.

### R4 — MÉRT csapda: a route-ok egy része FEATURE-FLAG mögött van

```bash
sed -n '561,571p' lib/app/routing/app_router.dart
#   if (visionEnabled && visionSetupEnabled) ...[  → AppRoutes.visionSetup
```

„A router regisztrálja" ≠ „a felhasználó ma eléri". Ez nem hiba, hanem az
[ADR 0065](../adr/0065-practice-engine-v2-parallel-rollout.md) szándékos
availability-flag mintája. **[ADR 0470 D4](../adr/0470-screen-reachability-is-measured-not-assumed.md):**
a flag-kapu JELENTETT dimenzió a tervben (a `retirement-plan.md` sorában
látszik, melyik flag nyitja), nem hallgatólagos „elérhető" és nem is „halott".

### R5 — Házi minta a mérőhöz

A `tool/ui_inventory.dart` a követendő alak: **osztály egy `Directory` fölött**
(`UiInventory(this.repository)` + `render()`), a `main()` csak vékony burkoló.
Így a `test/tooling/screen_reachability_test.dart` közvetlenül példányosít,
nem shell-hívást mér. A `--format table|json` a `main()` dolga.

### R6 — Visszakeresés (ADR 0312, kötelező)

Szűkítve először, a mért sorrendben:

```bash
node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 \
  "legacy screen retirement route reachability dead code deprecation"
node tools/knowledge-rag.mjs --corpus lessons,halts --top 5 \
  "static analysis barrel export re-export import resolution false negative tooling checker"
node tools/knowledge-rag.mjs --top 5 \
  "screen reachability audit tool/check_screen_reachability.dart retirement plan docs/ui"
```

Releváns előzmény: **[ADR 0065](../adr/0065-practice-engine-v2-parallel-rollout.md)**
(V2 a legacy MELLETT, flag mögött) · **[L449](../LESSONS.md#l449)** (az
`indexedStack` életben tartja a brancheket — „nem látszik" ≠ „halott") ·
**[L409](../LESSONS.md#l409)** (a képernyő LÉTEZÉSE és a PÉLDÁNYOSÍTÁSA külön
mérés — az E08-R30 brief pont ezt feltételezte hibásan) ·
**[L190](../LESSONS.md#l190)/[L193](../LESSONS.md#l193)** (barrel-szimbólum-rés
→ R3) · **[L20](../LESSONS.md#l20)** (a tábla megléte nem bizonyítja, hogy az
él bejárható).

### R7 — Amit a revízió NEM változtat

A §3 tilos zónája, a §4 engedélyezett fájllistája, a §6 acceptance-cellái és a
§7 gate-sora **változatlan**. A revízió szűkít és pontosít, nem tágít: új
fájl nem került az engedélyezett listára (a `docs/adr/0470-…` fájlt a Claude
írta a pre-flightban, az implementernek `docs/adr/**` továbbra is TILOS).

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
- `docs/adr/**` — az ADR 0470-et a Claude MÁR megírta a pre-flightban.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `tool/check_screen_reachability.dart` | ÚJ — az elérhetőség-mérő |
| `test/tooling/screen_reachability_test.dart` | a §6 cellái |
| `docs/ui/retirement-plan.md` | ÚJ — a döntési tábla |
| `docs/ui/migration-status.md` · `docs/ui/legacy-backlog.md` | a MÉRT számok frissítése |

**Tilos zóna:** `lib/**` · `test/ui/goldens/**` · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0470)

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
