# E15-R03 — Elérhetőségi audit és az örökség-képernyők visszavonási terve

- **Státusz:** READY (pre-flight lefutott 2026-08-28, kód ÚJRAMÉRVE: `main @ fc880063`)
- **Típus:** Chapter 15 (UI-aktiválás és -befejezés), Kör 3
- **Kör-azonosító:** `E15-R03`
- **Branch:** `sonnet-impl/e15-r03-legacy-reachability-audit-and-retirement`
- **Előfeltétel:** `E15-R02` merge-elve (a shell bekapcsolása UTÁN mérhető, mi érhető el valójában) — TELJESÜLT (`9dc0b1e6`)
- **Brief szerzője:** Claude (Opus 5)
- **Kiosztott ADR:** **`ADR 0471`** — lásd a §0.0.A/R1 revíziót (a brief eredeti `0468`-a időközben elkelt).

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

### R1 — Az ADR-szám `0468` → `0470` → **`0471`** (KÉT ütközés, mindkettő mérve)

**Első ütközés (pre-flight).** A brief `0468`-at foglalta le, de azt időközben
a merge-elt **E12-R09** kör használta el (`04ae8918 [E12-R09] Domain event
katalógus és schema registry (ADR 0468)`,
`docs/adr/0468-domain-event-catalog-and-schema-registry.md`). Egy merge-elt
ADR-hez nem nyúlunk (ADR 0087 §2 **H1**), ezért a szám a foglalótól jött, nem
`ls`-sel (ADR 0171 §1.0.1):

```bash
tools/round-slots.py reserve-adr --round E15-R03   # → 0470
```

**Második ütközés (merge előtt, MÉRVE 2026-08-29).** A kör CI-jének futása
közben a `main`-re merge-elődött a **HEAL E12-R11/H2** önjavító kör
([PR #499](https://github.com/wolfcasaba/strumsight/pull/499), `8e75e4f9`),
amely `docs/adr/0470-practice-setup-navigates-to-the-session-route.md` néven
**ugyanazt a 0470-es számot** használta el, noha ezt a kör a foglalótól
kapta meg. A merge előtti kötelező upstream-szinkron (prompt §0.3) hozta
felszínre: a `git merge origin/main` után KÉT `0470-*` fájl állt a fán.

**Feloldás — az ÉN, még nem merge-elt artefaktumomat számoztam át**
(ADR 0087 §2: a saját, nem merge-elt ADR a hatáskörömben van; a MÁSIK,
MÁR merge-elt 0470-hez nem nyúltam, az H1 lenne):

```bash
tools/round-slots.py reserve-adr --round E15-R03   # → 0471
git mv docs/adr/0470-screen-reachability-is-measured-not-assumed.md \
       docs/adr/0471-screen-reachability-is-measured-not-assumed.md
```

**A mért tanulság:** a foglaló `O_CREAT|O_EXCL` markere önmagában NEM elég,
ha egy párhuzamos sáv (itt egy önjavító kör) nem a foglalón keresztül kér
számot — a védelem csak addig ér, amíg MINDEN író használja. A hibaosztály
azonos az ADR 0171 §1.0.1-ben rögzített 2026-08-05-i `0139`-es ütközéssel,
csak most nem két kör-sáv, hanem egy kör és egy self-heal között. Az
ütközést nem a foglaló, hanem a **merge előtti upstream-szinkron** fogta meg.

A kör ADR-je: **[`docs/adr/0471-screen-reachability-is-measured-not-assumed.md`](../adr/0471-screen-reachability-is-measured-not-assumed.md)**,
a Claude írta ebben a pre-flightban. A brief §5 „Kötött architekturális
döntések (ADR 0468)" címe és a §3 tilos-zóna `docs/adr/**` sora ugyanígy
`0471`-re értendő.

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

**Ebből kötelező tervezési megkötés lett: [ADR 0471 D3](../adr/0471-screen-reachability-is-measured-not-assumed.md)
— a checker OSZTÁLYNÉVRE illeszt, nem fájlnévre.** Az import-útvonal legfeljebb
másodlagos jelzés lehet, önmagában SOHA nem dönthet „elérhetetlen"-ről.

### R4 — MÉRT csapda: a route-ok egy része FEATURE-FLAG mögött van

```bash
sed -n '561,571p' lib/app/routing/app_router.dart
#   if (visionEnabled && visionSetupEnabled) ...[  → AppRoutes.visionSetup
```

„A router regisztrálja" ≠ „a felhasználó ma eléri". Ez nem hiba, hanem az
[ADR 0065](../adr/0065-practice-engine-v2-parallel-rollout.md) szándékos
availability-flag mintája. **[ADR 0471 D4](../adr/0471-screen-reachability-is-measured-not-assumed.md):**
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
fájl nem került az engedélyezett listára (a `docs/adr/0471-…` fájlt a Claude
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
- `docs/adr/**` — az ADR 0471-et a Claude MÁR megírta a pre-flightban.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `tool/check_screen_reachability.dart` | ÚJ — az elérhetőség-mérő |
| `test/tooling/screen_reachability_test.dart` | a §6 cellái |
| `docs/ui/retirement-plan.md` | ÚJ — a döntési tábla |
| `docs/ui/migration-status.md` · `docs/ui/legacy-backlog.md` | a MÉRT számok frissítése |

**Tilos zóna:** `lib/**` · `test/ui/goldens/**` · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0471)

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

**Megjegyzés a futás történetéről:** ezt a szakaszt egy BEFEJEZŐ futás írta —
az előző futás (ugyanezen az ágon) az öt munkafájlt már elkészítette, de a
3600s abszolút időkorláton a gate futása közben megszakadt, COMMIT NÉLKÜL, és
a gate-et csővezetéken (`| head -40`) futtatta, ami tiltott (AGENTS.md §12).
Ez a futás a munkafájlokat NEM írta újra — csak a hiányzó két valódi-sértés
próbát futtatta le, ezt a §10-et töltötte ki, és a gate-et a brief §0.0.A/§2
szerinti, csővezeték nélküli alakban futtatta le.

### 10.1 Mi épült (fájlonként)

- **`tool/check_screen_reachability.dart`** — a mérő. `ScreenReachability`
  osztály egy `Directory` repository fölött (`ui_inventory.dart` mintáját
  követve), `render()` ad `ScreenReachabilityResult`-ot. Két csatorna (ADR
  0471 D2): **deklaratív** (a képernyő osztályneve szó szerint szerepel
  `lib/app/routing/{app_router,adaptive_shell_routes,route_guards}.dart`
  valamelyikében) VAGY **imperatív** (az osztály konstruálva van —
  `ClassName(` vagy `ClassName.namedCtor(` — bárhol máshol a `lib/` alatt).
  Mindkét csatorna OSZTÁLYNÉVVEL illeszt, sosem import-útvonallal vagy
  fájlnévvel (D3 — a barrel-csapda ellen). A flag-kapuzást (D4) egy
  behúzás-alapú `if (...Enabled...)` hatókör-számítás jelzi
  soronként — minden deklaratív hivatkozáshoz a rá vonatkozó flag-feltételek
  listája társul. `--format table|json` a `main()`-ben; a `main()` vékony
  burkoló, a mérés a teszt által is közvetlenül példányosítható osztályban él
  (R5 mintakövetés).
- **`test/tooling/screen_reachability_test.dart`** — A1 (mind a 96 képernyő
  ítéletet kap, forrás-hivatkozással, determinisztikusan), A2 (fixture: egy
  csak imperatívan elért képernyő elérhetőnek számít), **A2b** (fixture: a
  router csak egy `public.dart` barrelen át importál, a checker mégis
  elérhetőnek látja a hármat, mert osztálynévre illeszt), egy flag-gating
  fixture-csoport (D4), **A3** (a valódi `retirement-plan.md`-t parse-olja,
  és minden elérhető-és-még-legacy képernyőhöz nevesített `E15-Rxx` sort
  követel — a beépített valódi-sértés próbával együtt, ami a plan-sorok egy
  MÁSOLATÁBÓL veszi ki az egyik owner-round-ot), **A4** (minden `retire` sor
  valós indokot ÉS névvel megnevezett felváltót követel a valós tervből).
- **`docs/ui/retirement-plan.md`** (ÚJ) — a döntési tábla: §1 módszer, §2
  összesítő, §3 mért megállapítások (a `progress_v2` be nem kötve, a
  Practice Generator és az Audio Analysis capture wizard bekötetlen, a
  Community 15 képernyője flag nélkül route-olatlan, négy egyedi
  elérhetetlen), §4 kör-hozzárendelés (`E15-R04`…`E15-R11`, mind a 41
  elérhető-és-legacy képernyőre), §5 a 6 `retire`-javaslat indokkal és
  felváltóval, §6 a teljes 96 soros, gépileg mért tábla.
- **`docs/ui/migration-status.md`**, **`docs/ui/legacy-backlog.md`** — a MÉRT
  számokkal frissítve (68/96 elérhető, 28/96 elérhetetlen, 25/96 flag mögötti;
  a `progress`↔`progress_v2` "mindkettő elérhető" korábbi állítás javítva
  hamisra), a mérő paranccsal, és kereszthivatkozással a
  `retirement-plan.md`-re mint kanonikus per-screen forrásra.

### 10.2 `dart run tool/check_screen_reachability.dart --format table` — TÉNYLEGES kimenet

Összesítő sor (a teljes 96 soros tábla a `docs/ui/retirement-plan.md` §6-ban
van, szó szerint ugyanezekkel a számokkal):

```
Measured screens: 96. Reachable: 68. Unreachable: 28. Flag-gated: 25.
```

A parancs a `dart run` csomag-build-hook naplóját írja stdout-ra a tényleges
kimenet elé (`Running build hooks...Running build hooks...`) — ez a `dart
run` burkoló zaja, nem a checker kimenete; a `--format table` melletti tábla
egyébként a `docs/ui/retirement-plan.md` §6 tartalmával karakterre egyezik
(ugyanabból a mérésből származik). Két reprezentatív sor (egy sima
deklaratív és egy barrel-mentes, csak imperatív eset, valamint a `progress_v2`
hiányzó bejegyzés a §3.1 megállapításhoz):

```
| `lib/features/ai_tutor/presentation/screens/tutor_chat_screen.dart` | `TutorChatScreen` | lib/app/routing/app_router.dart:546 | — | 5 | aiTutorEnabled | lib/app/routing/app_router.dart:546 |
| `lib/features/practice/presentation/screens/practice_history_screen.dart` | `PracticeHistoryScreen` | — | lib/features/practice/presentation/screens/practice_result_screen.dart:498 | 3 | — | lib/features/practice/presentation/screens/practice_result_screen.dart:498 |
| `lib/features/progress_v2/screens/progress_dashboard_screen.dart` | `ProgressDashboardScreen` | — | — | 11 | — | lib/features/progress_v2/screens/progress_dashboard_screen.dart:16 |
```

### 10.3 §7 gate — TÉNYLEGES kimenet (csővezeték/`head`/`tail`/`&&` NÉLKÜL, egyetlen parancs)

```
tools/round-gate.sh test/tooling/screen_reachability_test.dart test/ui/ui_inventory_test.dart
```

Lépésenkénti verdiktek (csonkítatlan futásból):

```
    → [1] format: ZÖLD
    → [2] analyze: ZÖLD                      (Analyzing 3 items... No issues found! (ran in 5.9s))
    → [3] test test/tooling/screen_reachability_test.dart: ZÖLD   (9/9 teszt, "All tests passed!")
    → [4] test test/ui/ui_inventory_test.dart: ZÖLD               (1/1 teszt, "All tests passed!")
    → [5] architecture: ZÖLD                 (Architecture dependencies OK (12 allowlisted deviation(s)).)
    → [6] secrets: ZÖLD                      (Secret scan OK (4015 file(s) scanned, 0 finding(s)).)
    → [7] l10n: ZÖLD                         (L10n aggregate freshness OK; L10n parity OK (en → hu, 2289 message(s)).)

═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/tooling/screen_reachability_test.dart            zöld
    test test/ui/ui_inventory_test.dart                        zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld

MINDEN GATE ZÖLD.
```

### 10.4 §3/§6.1 kötelező valódi-sértés próbák — TÉNYLEGES kimenet

**(a) A3-próba.** A valós `docs/ui/retirement-plan.md`-ben a
`TutorChatScreen` sorának owner-round celláját (`E15-R05`) átmenetileg
`—`-re cseréltem, majd lefuttattam:

```
flutter test test/tooling/screen_reachability_test.dart --plain-name "every reachable-and-legacy screen has a migrate/retire verdict"
```

**A3 PIROSRA váltott**, a tényleges hibaüzenet:

```
Expected: empty
  Actual: ['lib/features/ai_tutor/presentation/screens/tutor_chat_screen.dart']
reachable-but-unmigrated screens with no named E15 round (ADR 0471 D6): [lib/features/ai_tutor/presentation/screens/tutor_chat_screen.dart]
```

Ezután a sort visszaállítottam `E15-R05`-re, és a tesztet újrafuttatva: `+1:
All tests passed!` — A3 zöld.

**(b) A2b barrel-próba.** Mivel `lib/**` módosítása tilos, a próbát a
checkeren (`tool/check_screen_reachability.dart`, engedélyezett fájl)
végeztem el ÁTMENETILEG: a deklaratív hurok `_references(lines[i],
className)` hívását (251. sor) egy szándékosan HIBÁS, útvonal/fájlnév-alapú
illesztésre cseréltem (`lines[i].contains(screenPath.split('/').last.split('.').first)`),
majd lefuttattam a barrel-fixture tesztet:

```
flutter test test/tooling/screen_reachability_test.dart --plain-name "the screen is declaratively reachable even though the router never imports its file"
```

**A2b PIROSRA váltott**, a tényleges hibaüzenet:

```
Expected: true
  Actual: <false>
```

— pontosan azt igazolva, amit a §3(b) kér: ha a checker fájlnévre/útvonalra
illesztene osztálynév helyett, a `vision/public.dart`-hoz hasonló barrel
mögötti képernyők (itt a fixture `HiddenScreen`-je) hamisan
„elérhetetlennek" mérődnének. Ezután a hurkot pontosan az eredeti
`_references(lines[i], className)` hívásra állítottam vissza (`git diff
tool/check_screen_reachability.dart` a próba előtt és után üres), és a teljes
`test/tooling/screen_reachability_test.dart` fájlt újrafuttatva mind a 9 teszt
zöld (`00:52 +9: All tests passed!` — a fenti §10.3-ban idézett futás ez).

### 10.5 Mért korlátok

- **Egy-ugrásos imperatív lánc (ADR 0471 D7).** A checker csak azt méri, hogy
  egy osztály konstruálva van-e VALAHOL a `lib/` alatt — nem azt, hogy az a
  konstruáló hely maga elérhető-e egy belépési pontból. Ez két mért hamis
  pozitívumot ad: `EditProfileScreen` csak a (mérten elérhetetlen)
  `CommunityGateScreen`-ből konstruálódik, `ClubMemberManagementScreen` csak
  a (mérten elérhetetlen) `ClubDetailScreen`-ből — mindkettő `keep`
  minősítést kap a táblában, de a valós bejárási lánc szakadt
  (`retirement-plan.md` §3.3).
- **Csak statikus szövegillesztés.** Reflexív vagy futásidejű string-kulcs
  alapú navigáció nem látható (a brief §9 kockázata, mérten megerősítve — a
  fenti két community-képernyőn túl nem találtam más ilyen esetet, de a
  checker ezt strukturálisan nem tudja kizárni).
- **A flag-hatókör-számítás behúzás-alapú, nem AST-parser.** `dart
  format`-tiszta fára támaszkodik (a projekt szabványa); egy kézzel rontott
  behúzású sor téves hatókört adna. A valós fán ez nem fordult elő (a §2
  gate `format` lépése ezt ellenőrzi is minden futásnál).
- **A `dart run` csomag-build-hook zaja** (`Running build hooks...`) a
  `--format json` kimenet elé is bekerül, ha valaki csővezetékben `jq`-val
  dolgozza fel — ez nem a checker hibája, hanem a `dart run` burkolóé; egy
  jövőbeli automatizált fogyasztónak `dart compile exe` vagy a stderr
  elválasztása javasolt (ezt a kör nem valósítja meg, kívül esik a scope-on).

### 10.6 Javító kör (a review MAJOR-1-jére) — TÉNYLEGES kimenet

A független review (`docs/reviews/e15-r03-review.md` MAJOR-1) megmérte, hogy a
`:323–332` A4 „kötelező valódi-sértés próbája" tautológia volt: egy helyben
megírt literált hasonlított önmagához, nem hívta meg sem a `_parsePlanRows`-t,
sem a valós tervet, sem az A4 tényleges állítás-logikáját.

**Javítás — (a) út, az A3-próba alakja.** A `:298–318` és a `:323–332` teszt
mostantól egy közös, top-level `_retireRowsMissingSuccessorOrReason(List<
_PlanRow>)` függvényt hív, amely pontosan az eredeti két `expect`
(üres/`—` successor, ≤10 karakteres reason) logikáját tartalmazza. Az A4-cella
a valós tervet (`_parsePlanRows` + a `retire` sorok) egyszer, `setUpAll`-ban
olvassa be:

- az eredeti teszt a valós `retire` sorokon hívja a függvényt, és üres listát
  vár;
- az új valódi-sértés próba a valós `retire` sorok egy MÁSOLATÁBAN kiüríti
  EGY tényleges sor successorát (`'—'`-re), majd UGYANAZT a függvényt hívja a
  módosított listán, és azt várja, hogy pontosan az az egy `screenPath` térjen
  vissza — az A3-próba (`:263–293`) alakjával megegyezően.

**A próba VALÓDI — mérve, a brief §2 szerint.**

1. **Az őr kiütve, csak az új próba fut.** A `_retireRowsMissingSuccessorOrReason`
   belsejében a feltételt ideiglenesen `if (false && (missingSuccessor ||
   trivialReason))`-ra cseréltem (vagyis a valós A4 állítás soha nem jelez
   sértést), majd KIZÁRÓLAG az új próbát futtattam:

   ```
   flutter test test/tooling/screen_reachability_test.dart --plain-name "blanking one real retire row's successor turns this cell red"
   ```

   **PIROSRA váltott**, a tényleges hibaüzenet:

   ```
   Expected: ['lib/features/analyze/screens/analyze_screen.dart']
     Actual: []
        Which: at location [0] is [] which shorter than expected
   test/tooling/screen_reachability_test.dart 352:7    main.<fn>.<fn>
   ```

   Vagyis a kiütött őr mellett az új próba maga bukik el — nem vákuumosan
   igaz, ténylegesen a `_retireRowsMissingSuccessorOrReason` viselkedését
   méri.

2. **Az őr visszaállítva.** A feltételt visszaállítottam az eredeti
   `if (missingSuccessor || trivialReason) failing.add(row.screenPath);`
   alakra, és újrafuttattam a teljes A4 csoportot:

   ```
   flutter test test/tooling/screen_reachability_test.dart --plain-name "A4"
   → 00:00 +2: All tests passed!
   ```

**Záró gate — TÉNYLEGES kimenet (csővezeték/`head`/`tail`/`&&` nélkül):**

```
tools/round-gate.sh test/tooling/screen_reachability_test.dart test/ui/ui_inventory_test.dart
```

```
    format                                                     zöld
    analyze                                                    zöld
    test test/tooling/screen_reachability_test.dart            zöld
    test test/ui/ui_inventory_test.dart                        zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld

MINDEN GATE ZÖLD.
```

A `git diff` a javító körben kizárólag
`test/tooling/screen_reachability_test.dart`-ot érinti (a `_PlanRow`-import,
`lib/**`, `docs/adr/**`, `tool/**` érintetlen).

### 10.7 Második javító kör (MAJOR-2 — a mérő négyzetes I/O-ja) — TÉNYLEGES kimenet

A review megmérte, hogy `tool/check_screen_reachability.dart` `render()`
hurka `O(képernyők × fájlok)` — minden 96 képernyőhöz újraolvasta a teljes
`lib/`+`test/` fát — és ez izolált klónban `real 3m0.848s`-ot mért egyetlen
teszt-fájlra.

**Javítás — a hurkok megfordítva, `O(fájlok)`-ra.** A `render()` mostantól:

1. előre kiszámolja mind a 96 `className → screen-index` leképezést
   (`screenIndicesByClassName`);
2. a `lib/app/routing/*` három fájlját (változatlanul, fájlonként EGYSZER
   olvasva) soronként egyetlen általánosított token-regexszel
   (`_referenceToken = r'\b([A-Za-z0-9_]*Screen)\b'`) vizsgálja, és a talált
   névvel a leképezésben néz utána, mely képernyő(ke)t érinti;
3. a `lib/` fákat **egyszer** olvassa be, soronként egyetlen konstrukciós
   token-regexszel (`_constructToken = r'\b([A-Za-z0-9_]*Screen)(?:\.[A-Za-z_]
   [A-Za-z0-9_]*)?\s*\('`) — a régi `_constructs(line, className)` 96×
   hívása helyett;
4. a `test/` fákat **egyszer** olvassa be, ugyanazzal a `_referenceToken`
   mintával;
5. minden sorra van egy olcsó előszűrő (`if (!line.contains('Screen'))
   continue;`) — mivel minden képernyő-osztály `Screen`-re végződik
   (`_classDeclaration` kikényszeríti), egy `Screen` alsztringet nem
   tartalmazó sor biztosan nem illeszkedhet, a regex-illesztés elkerülhető.

Az önhivatkozás-kizárás (egy képernyő saját fájlja nem számít saját
imperatív hivatkozásának) és a routing-fájlok kizárása az imperatív
csatornából megmaradt, csak fájl-szintre emelve (a `libPath ==
screenPaths[idx]` és `routingSources.contains(libPath)` ellenőrzés a hurok
megfelelő szintjén fut, nem képernyőnként újra).

A régi `_references`/`_constructs` privát segédfüggvényeket eltávolítottam
(a hívóik megszűntek, az analyzer `unused_element`-et jelzett volna) — a
helyettük belépő `_referenceToken`/`_constructToken` a KAPCSOLT, minden
képernyőre egyszerre futó megfelelőjük: mivel minden ismert osztálynév
`Screen`-re végződik, egy `[A-Za-z0-9_]*Screen`-alakú, szóhatárolt token
kinyerése és a leképezéssel való metszése pontosan azt a halmazt adja, amit
a régi, osztálynevenkénti `\bClassName\b`/konstrukciós regex 96-szori
lefuttatása adott volna (word-boundary szemantika azonos — lásd az
implementáció fenti kommentjét).

**A viselkedés NEM változott — mérve, byte-azonosan.** Mivel ezen a boxon a
review referencia-hasheléséhez (`sed 's/^Running build hooks\.\.\.//'`)
tartozó nyers kimenet MÁR a javítás előtt (tiszta, változatlan `HEAD`)
sem egyezett a brief §3-ban idézett `7cebc87d…` hash-sel — csak
környezeti eltérés (más doboz futtatta a review mérését), NEM a kör
diffje —, a helyes ellenőrzés a MOSTANI `HEAD` (javítás előtti) és a
MÓDOSÍTOTT fa kimenetének összevetése volt, izolált `git worktree`-ben:

```
git worktree add --detach /tmp/e15r03-baseline HEAD   # javítás előtti tiszta fa
cd /tmp/e15r03-baseline && dart run tool/check_screen_reachability.dart --format json \
  | sed 's/^Running build hooks\.\.\.//' | sha256sum
→ 49ae2e4084b278237c03df303a14164bf7ccf80962ec93cad34a5a10b9264df0  (6113 sor)

# a munkapéldányban (javítással):
dart run tool/check_screen_reachability.dart --format json \
  | sed 's/^Running build hooks\.\.\.//' | sha256sum
→ 49ae2e4084b278237c03df303a14164bf7ccf80962ec93cad34a5a10b9264df0  (6113 sor)

diff <(javítás előtti kimenet) <(javítás utáni kimenet)
→ (üres — byte-azonos)
```

A két hash **megegyezik** (`49ae2e40…`), a `diff` üres — a javítás
byte-azonos kimenetet ad a javítás előtti kódhoz képest ezen a boxon. Az
összesítő sor is változatlan:

```
Measured screens: 96. Reachable: 68. Unreachable: 28. Flag-gated: 25.
```

**Mért gyorsulás:**

```
time flutter test test/tooling/screen_reachability_test.dart
```

| | előtte (review mérése, izolált klón) | utána (ez a kör, ugyanez a box) |
| --- | --- | --- |
| real | 3m0.848s | **0m5.826s** |
| user | 2m47.740s | 0m6.381s |
| sys | 0m13.148s | 0m1.105s |

**~31×** gyorsulás — a `render()` most valóban `O(fájlok)`, nem
`O(képernyők × fájlok)`.

**Záró gate — TÉNYLEGES kimenet (csővezeték/`head`/`tail`/`&&` nélkül):**

```
tools/round-gate.sh test/tooling/screen_reachability_test.dart test/ui/ui_inventory_test.dart
```

```
    format                                                     zöld
    analyze                                                    zöld
    test test/tooling/screen_reachability_test.dart            zöld
    test test/ui/ui_inventory_test.dart                        zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld

MINDEN GATE ZÖLD.
```

A `git diff` ebben a javító körben kizárólag
`tool/check_screen_reachability.dart`-ot (a `render()` hurok-átalakítása +
`_referenceToken`/`_constructToken`) és ezt a szakaszt érinti;
`test/tooling/screen_reachability_test.dart` és a `lib/**`/`docs/adr/**`/
`tool/ui_inventory.dart` érintetlen maradt.

## 11. Review — a Claude tölti ki
