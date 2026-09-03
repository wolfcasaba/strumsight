# E16-R02 — A Progress V2 bekötése és a router placeholder-mentesítése

- **Státusz:** IN PROGRESS (pre-flight mérve 2026-09-03, `main @ e367048f`)
- **Típus:** Chapter 16 (Kompozíció és rollout), Kör 2
- **Kör-azonosító:** `E16-R02`
- **Branch:** `<motor>/e16-r02-progress-projection-and-router-placeholders`
- **Előfeltétel:** `E16-R01` merge-elve (a gamification kompozíció mintája és a router-diff ott készül el)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** **`ADR 0500`** — a foglalótól kapott szám
  (`tools/round-slots.py reserve-adr --round E16-R02` → `.pipeline/inflight/adr/0500`).
  Az előre megírt brief `0491`-et állított, de az MÉRVE foglalt és merge-elt
  (`docs/adr/0491-practice-generator-entry-point-and-rollout.md`) — a §0.0.I revízió javította.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "progress projection dashboard skill detail unreachable screen wiring"` → az `E15-R03` saját mérése (`docs/ui/retirement-plan.md`): „progress_v2 is NOT wired into the router — `/profile/progress` still builds the legacy `ProgressScreen` (app_router.dart:528)", és **[ADR 0353](../adr/0353-caller-fed-compassionate-streak-v2-presentation.md)** (hívó-adta prezentáció). A kör ezt a MÉRT holt ágat élesíti.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd újra, hogy a `/profile/progress` route MÉG a legacy `ProgressScreen`-t építi-e, és hogy a `ProgressOverviewProjection` / `SkillDetailProjection` típusokra a `lib/features/progress_v2/`-n KÍVÜL még mindig **0** hivatkozás van-e.

## 0.0.H Módosítás (ADR 0112 önjavító kör, 2026-09-03) — a hiányzó mastery-forrás a kör RÉSZE lett

Az eredeti brief a `main @ 11d0d2bb` fán készült, és a §2 azt állította, hogy a
projekció mastery-oldalának forrása a gamification-profil és a ledger. A kör
pre-flightja ezt MEGCÁFOLTA (H3 halt, `.pipeline/halt-detail-E16-R02.md`), és az
önjavító kör a mérést újra elvégezte (`main @ 619232dd`):

| Mért parancs | Eredmény |
|---|---|
| `grep -rn "MasteryMilestone(" --include=*.dart lib test` | 9 hely: 1 definíciós fájl + 8 TESZT — produkciós katalógus **0** |
| `grep -rn "List<MasteryMilestone>\|milestoneCatalog\|masteryCatalog" --include=*.dart lib` | **0 találat** |
| `grep -rln "MasteryEvidence" --include=*.dart lib` | 4 fájl (2 domain, 1 evaluator, 2 progress_v2) — **egyetlen `data/` előállító sem** |
| `grep -o '"[a-zA-Z0-9]*"' lib/l10n/app_en.arb \| grep -i "mastery\|milestone"` | 3 kulcs, mind chrome — **0 milestone-cím/leírás** |

**A hibamód, amit az EREDETI A1–A7 cella NEM fogott volna meg.** Üres
`milestones` listával a `ProgressOverviewProjection.isNewUser` **igaz**
(`[].every(...)` → `true`, `progress_overview_projection.dart:65`), tehát a
`ProgressDashboardScreen` KIZÁRÓLAG a `_NewUserState`-et rendereli
(`progress_dashboard_screen.dart:38`) — a `/profile/progress` átkötése a MA
valós adatot mutató legacy `ProgressScreen`-t (`app_router.dart:545`) egy
ÖRÖKRE üres „get started" képernyőre cserélte volna, miközben minden cella zöld
marad, mert közvetlenül eteti a projekciót (L397/L449 hibaosztály).

**Az önjavítás döntése:** nem a cellákat gyengítjük és nem halasztjuk a
route-váltást — a hiányzó FORRÁST tesszük a kör részévé. Az `allowed_paths`
három darabbal bővül (mastery-katalógus, practice→evidence adapter,
milestone-l10n szegmens + a két generált aggregátum), az §5.4–5.7 pinneli a
küszöböket, a leképezést és az eldobási szabályokat, a §6 pedig ÚJ cellákat kap
(**A8–A12**), köztük az `A10`-et, ami pontosan a fenti hibamódot viszi pirosra.
A régi A1–A7 cellák közül egyet sem töröltünk és egyet sem lazítottunk.

**Miért ez a legkisebb javítás.** A route-váltás halasztása (a másik mért
opció) az A1/A2/A5 cella törlését jelentette volna, és az `E16-R03` kimondott
előfeltételét („a kompozíciós rétege valós adatot ad") is érintette volna —
tehát TÖBB mércét vett volna el, nem kevesebbet.

**Őrteszt:** `tools/tests/test_e16_r02_mastery_source_scope.py` — a revízió
ELŐTTI briefen PIROS.

**Az ADR-szám a foglalóból jön (L603).** *(§0.0.I: ez az előírás LEFUTOTT — a
foglaló `0500`-at adott, a fejléc javítva.)* A fejlécben állt szám az előre
megírt brief állítása; a kör indításakor a hiteles forrás a foglaló — a
pre-flight kérje le, és ha foglalt, a kapott számot használja.

## 0.0.I Módosítás (ADR 0112 önjavító kör, 2026-09-03) — a route-katalógus ownere a scope-ba kerül + négy mért brief-hiba

A kör MÁSODIK pre-flightja (`main @ 18a649ec`, tehát a §0.0.H revízióval együtt)
újabb H3-at mért: a `.pipeline/halt-detail-E16-R02.md`. A blokkoló és a mellette
mért négy hiba ebben az EGY revízióban van rendezve. Minden állítás mérve, a
mérő paranccsal együtt; ahol a törzs mást mond, **ez a szakasz az erősebb**.

### I1 — BLOKKOLÓ: az `app_route.dart` hiányzott az `allowed_paths`-ból

A §3 scope „a skill-detail útvonal bekötése", az **A2** cella pedig ezt méri —
ehhez ÚJ `AppRoutes` konstans kell, ami a `lib/app/routing/app_route.dart`
katalógusban él. A listán csak az `app_router.dart` szerepelt.

| Mért parancs | Eredmény |
|---|---|
| `grep -n "skill" lib/app/routing/app_route.dart` | **0** skill-konstans (a `progress` és a `profileProgress` megvan) |
| `grep -c "path: '" lib/app/routing/app_router.dart` | **0** — a fán EGYETLEN inline útvonal-literál sincs, minden `GoRoute.path` `AppRoutes`-konstans |
| `grep -rn "SkillDetailScreen" --include=*.dart lib` | csak a saját fájlja — a képernyő ma sehonnan nem érhető el |
| `sed -n '/```ai-router/,/```/p' docs/rounds/e16-r01-*.md \| grep app_route` | az ELŐZŐ kör (`E16-R01`) listáján **rajta van**, és pontosan így vette fel a `levelDetail` konstanst |

A `test/tooling/route_literal_guard_test.dart` tiltja a navigációs
útvonal-literálokat, a `SkillDetailScreen.onOpenEvidence` szerződése pedig
kimondottan „a cél `AppRoutes` konstans"-t vár (`skill_detail_screen.dart:26–29`)
— a listán belüli feloldás tehát nem létezik. **Ez ugyanaz a hibaosztály, mint
az [L97](../LESSONS.md#l97) (E03-R17: a wiring engedve, a katalógus nem) és az
[L246](../LESSONS.md#l246) (E06-R23: hiányzó owner-fájl → listán kívüli írás).**

**Javítás:** az `allowed_paths` és a §4 tábla megkapja a
`lib/app/routing/app_route.dart`-ot, KIZÁRÓLAG az új konstans HOZZÁADÁSÁRA, és
az új §5.8 pinneli az útvonal alakját. Cellát nem töröltünk és nem lazítottunk.

### I2 — a §5.4 milestone-azonosítói futásidőben DOBTAK volna

`MasteryMilestone` factory → `_requireStableId` a `^[a-z][a-z0-9_]*$` regexszel
(`mastery_milestone.dart:161`), és ugyanez köti a `MasteryProgress.milestoneId`-t:

```
python3 -c "import re;p=re.compile(r'^[a-z][a-z0-9_]*\$');print([(i,bool(p.match(i))) for i in ['mastery.chordTransition.v1','mastery_chord_transition_v1']])"
→ [('mastery.chordTransition.v1', False), ('mastery_chord_transition_v1', True)]
```

Mindhárom pontozott id `ArgumentError`-t dobott volna. A §5.4 táblája
snake_case-re javítva.

### I3 — a `const` katalógus-előírás MÉRHETŐEN teljesíthetetlen

`MasteryMilestone` és `MasteryTempoRange` publikus felülete **factory**
(`mastery_milestone.dart:39`, `:86`), a `const` konstruktor **privát**
(`:44`, `:136`) — publikus `const` példányosítás nem lehetséges. A katalógus
`final` + `List.unmodifiable`. A §6.1 2. próbája (`const <MasteryMilestone>[]`,
üres konstans lista) VÁLTOZATLANUL érvényes, mert az nem példányosít.

### I4 — hiányzott a `difficulty` oszlop, és ez az A10-et dönti el

`MasteryMilestone.difficulty` **required** (`:92`), és az evaluator az eltérő
nehézségű bizonyítékot ELDOBJA (`mastery_evaluator.dart:108`
`if (sample.difficulty != milestone.difficulty) continue;`). Mért forrás-eloszlás:

```
grep -c "id: 'builtin\."               lib/features/practice/data/builtin_practice_catalog.dart → 10
grep -n "difficulty: PracticeDifficulty" …                                                      → 2 (mindkettő intermediate, :160 és :214)
```

Tehát 10 builtin definícióból **8 `beginner`** (a `PracticeDefinition` default-ja)
és 2 `intermediate`. Oszlop nélkül az implementer olyan nehézséget választhatott
volna, amellyel az **A10** csak a saját fixture-jén zöld. A §5.4 most pinneli.

### I5 — a `practice/public.dart` export-engedélye szűkebb volt, mint az §5.5

Az §5.5 adapter `PracticeHistoryEntry` → `MasteryEvidence`, de a kereszt-feature
import GÉPI szabálya barrel-en át engedi csak a típus megnevezését
(`tool/check_architecture.dart:382`). Mérve a barrelen:

```
grep -n "practice_history_entry\|practice_metric_snapshot\|practice_catalog\|practice_difficulty" \
  lib/features/practice/public.dart → 0 találat
```

A `PracticeMetricDimensionAvailable` ráadásul a `practice_metric_snapshot.dart:104`-ben
él, NEM a barrel által exportált `practice_metrics.dart`-ban. A §4 sora ezért
felsorolja a szükséges export-sorokat — ez szöveges pontosítás, a barrel-fájl
maga MÁR a listán volt.

**Őrteszt:** `tools/tests/test_e16_r02_route_catalog_scope.py` — a revízió ELŐTTI
briefen mind a 8 cellája PIROS; minden állítását a KÓDHOZ méri (a regexet a
`mastery_milestone.dart`-ból olvassa ki, az export hiányát a barrelből), nem
kézzel másolt elváráshoz.

## 0.0.J Módosítás (ADR 0112 önjavító kör, 2026-09-03) — az útvonal-szintű képernyőcserét PINNELŐ tesztek a scope-ba kerülnek

A kör HARMADIK pre-flightja (`main @ b685831a`) egy ÚJ blokkolót mért ki
(H3, `.pipeline/halt-detail-E16-R02.md`): az **A1** cella a `/profile/progress`
útvonalat a `ProgressDashboardScreen`-re köti át, a `ProgressScreen`-t viszont
a briefen KÍVÜL élő tesztek pinnelik a legacy típusra. A halt-detail §1/§2
teljes lánca mérve; az önjavító kör a mérést újra elvégezte:

| Mért parancs | Eredmény |
|---|---|
| `sed -n '544,545p' lib/app/routing/app_router.dart` | `path: AppRoutes.profileProgress` → `const ProgressScreen()` — ezt írja át az A1 |
| `sed -n '247,255p' test/features/today/hub_navigation_test.dart` | shell-ON routeren `router.go(AppRoutes.progress)` után `expect(find.byType(ProgressScreen), findsOneWidget)` |
| `flutter test test/features/today/hub_navigation_test.dart` | `00:03 +8: All tests passed!` — MA ZÖLD, tehát élő regresszió-őr, nem előre piros teszt |
| `python3 tools/brief-lint.py --brief <ez a brief> --level strict` (a lint javítása UTÁN) | **S11**: `progress_screen.dart` → `offline_network_guard_test.dart`, `app_router_test.dart`, `hub_navigation_test.dart` |

A lint mind a HÁROM tesztet felsorolja, mert mindhárom a `/progress` →
`/profile/progress` láncon jut a képernyőhöz (`AppRoutes.progress` /
`AppRoutes.profileProgress` a forrásukban). Kettő közülük ma azért marad zöld,
mert a harness shellje KI van kapcsolva — ez azonban futásidejű konfiguráció,
nem szerződés: egy útvonal-átkötésnek pontosan ezek a legközelebbi őrei, ezért
a kör SAJÁT kapuján is futniuk kell (L593: a célzott gate mérje azt, amit a kör
elronthat). A `test/core/screen_size_guard_test.dart` és a
`test/features/progress/progress_screen_test.dart` NEM kerül a listára: azok a
képernyőt közvetlenül építik (`home: ProgressScreen()`), a routertől
függetlenül futnak tovább, és az utóbbi ráadásul a kör TILOS zónájában él.

**A revízió:** a három teszt bekerül az `allowed_paths`-ba ÉS a `gate_tests`-be
(a §7 gate-parancs is bővül, S12), a §4 tábla pedig a MEGLÉVŐ három-őr sorral
azonos szigorral pinneli a jogosultságot. **Cellát nem töröltünk, nem
gyengítettünk, küszöböt nem lazítottunk** — a `hub_navigation_test.dart` A5
cellájában a VÁRT KÉPERNYŐ-TÍPUS változik (`ProgressScreen` →
`ProgressDashboardScreen`), maga az állítás (a legacy `/progress` mélylink a
redirect végén a `/profile/progress` képernyőjét adja) VÁLTOZATLAN.

**Az eszköz-oldali gyökérok is javítva** (ADR 0112 §1/A osztály): a
`tools/brief-lint.py` `owned_existing_screens()` a képernyő-cserét
FÁJL-TULAJDONLÁSBÓL mérte, ezért erre a briefre (0 db `*_screen.dart` és 0 db
`lib/` könyvtár-előtag az `allowed_paths`-on) az S11/S14 strukturálisan néma
volt. A `route_level_swapped_screens()` ezt zárja, őrteszt:
`tools/tests/test_brief_lint_route_level_screen_swap.py`.

## 0.0.K Pre-flight (E16-R02 orchestrátor, 2026-09-03, `main @ e367048f`) — a §0.0.H–J revíziók MÉRVE állnak, egy fájl-útvonal javítva

A kör NEGYEDIK pre-flightja a §0.0.H, §0.0.I és §0.0.J revíziókkal EGYÜTT futott
le. **Nincs új blokkoló** — a §0.0.J óta merge-elt fán a kör indulhat. A mérés:

| Mért parancs | Eredmény | Következtetés |
|---|---|---|
| `sed -n '543,546p' lib/app/routing/app_router.dart` | `path: AppRoutes.profileProgress` → `const ProgressScreen()` | a fejléc pre-flight-előírása ÁLL: a route MÉG a legacy képernyőt építi |
| `grep -rn "ProgressOverviewProjection\|SkillDetailProjection" --include=*.dart lib \| grep -v progress_v2/` | **0** | a projekciós típusokra a feature-en kívül továbbra is 0 hivatkozás |
| `grep -n "skill" lib/app/routing/app_route.dart` | **0** | az §5.8 ÚJ konstansa tényleg hiányzik (I1 áll) |
| `python3 tools/brief-lint.py --brief <ez a brief> --level strict` | `nincs lelet` (exit 0) | S1–S14 mind rendben |
| `find lib -name "*mastery*"` + `grep -n "difficulty" …/application/mastery_evaluator.dart` | `:108 if (sample.difficulty != milestone.difficulty) continue;` | az I4 ÁLLÍTÁSA áll; a fájl útvonala kimondva (K1) |
| `grep -n "_requireStableId\|factory MasteryMilestone\|const MasteryMilestone._" …/mastery_milestone.dart` | `:161` regex, `:86` factory, `:136` privát const | az I2 és az I3 áll |
| `grep -n "practice_metric_snapshot\|practice_difficulty\|practice_history_entry\|practice_catalog" lib/features/practice/public.dart` | **0** | az I5 áll: az export-sorok tényleg hiányoznak |
| `grep -c "id: 'builtin\."` / `grep -n "difficulty: PracticeDifficulty"` a builtin katalóguson | `10` / `:160`, `:214` | az §5.4 nehézség-indoklása áll: 8 `beginner`, 2 `intermediate` |
| a §7 `gate_tests` 16 útvonalának létezés-próbája | 12 létezik, 4 a kör ÚJ tesztje | egyik meglévő útvonal sem elgépelés |
| `ls -d /home/ubuntu/ss-*e16-r02*` + `git ls-remote --heads origin \| grep e16-r02` | üres / üres | a hagyaték-mérés (`ÁLLAPOT: NINCS`) megerősítve |

### K1 — a `mastery_evaluator.dart` útvonala kimondva (a §0.0.I/I4 és az §5.4 csak a fájlnevet adta)

A §0.0.I/I4 és az §5.4 a nehézség-szűrőt csupasz fájlnévvel hivatkozza
(`mastery_evaluator.dart:108`), könyvtár nélkül, miközben a körülötte lévő
hivatkozások (`mastery_milestone.dart`, `mastery_progress.dart`) mind a
`domain/mastery/` könyvtárban élnek. A fájl MÉRVE **nem ott** van:

```
find lib -name "*mastery*"
→ lib/features/gamification/application/mastery_evaluator.dart
→ lib/features/gamification/domain/mastery/{mastery_badge,mastery_milestone,mastery_progress}.dart
```

A hivatkozott **sor és állítás helyes** (`:108` valóban
`if (sample.difficulty != milestone.difficulty) continue;`), csak a helye volt
kikövetkeztethető rosszul. A pre-flight ezért kimondja:
**`lib/features/gamification/application/mastery_evaluator.dart`**.

**Ez pontosítás, nem scope-változás.** Az `allowed_paths` NEM változik: az
evaluator egyik alakban sem szerepel rajta, tehát a gépi scope-audit mindkét
könyvtárban tiltja az írását, és a tilos zóna „az evaluator … VÁLTOZATLAN"
sora könyvtár-független. Cellát nem töröltünk, nem gyengítettünk, küszöböt nem
lazítottunk.

### K2 — az ADR-szám a foglalóból: `0500`

`tools/round-slots.py reserve-adr --round E16-R02` MÉRVE három markert hagyott
maga után az ismételt pre-flightok miatt (`.pipeline/inflight/adr/0500`, `0501`,
`0502` — **mind `round=E16-R02`**), és egyik sincs a lemezen (`ls docs/adr/0500*`
→ üres). A hiteles szám a **`0500`**: ezt hordozza a
`docs/execution/pipeline-queue.tsv` E16-R02 sora és a §0.0.I-ben javított
fejléc is. A `0501`/`0502` az ismételt foglalás mellékterméke, nem külön döntés.
Az ADR megírva: `docs/adr/0500-progress-v2-projection-source-and-route-activation.md`.

### K3 — visszakeresés (ADR 0312), szűkítve majd teljes korpuszon

- `--corpus lessons,halts,adr "progress projection builder router screen swap dead code wiring"` →
  **[ADR 0471](../adr/0471-screen-reachability-is-measured-not-assumed.md)** (a
  képernyő elérhetősége MÉRT, és a `progress/` ↔ `progress_v2/` párhuzamos réteg
  nevesítve van), `halts/round-status-E08-R30` (route-bekötés `lib/features`
  írás nélkül).
- `--corpus lessons,halts "route rebinding legacy screen regression guard test expectations"` →
  **[L393](../LESSONS.md#l393)** (a lecserélt típus scope-ja a legacy
  finder-contractot IS magában foglalja — pontosan a §0.0.J hibaosztálya),
  **[L397](../LESSONS.md#l397)** (a `ui_inventory_test` bázisvonala CI-only
  leletként bukott — a §7 gate ezért futtatja), **[L449](../LESSONS.md#l449)**
  (az `indexedStack` shell életben tartja a brancheket).
- teljes korpuszon: a találatok a kör SAJÁT forrásfájljai
  (`progress_overview_projection.dart`, `dashboard_states_test.dart`,
  `progress_dashboard_screen.dart`) — új normatív előzmény nincs.

A §0.0.J által már lefedett L393/L397 osztályt a `gate_tests` 16 útvonala
(köztük az `ui_inventory_test.dart` és a három útvonal-szintű őr) fedi.

## 0.0 A MÉRT hiba: kész felület, amihez nincs adatforrás

A `progress_v2` feature **hét** fájlt tartalmaz: két képernyőt (`ProgressDashboardScreen`, `SkillDetailScreen`), négy domain-projekciót (`progress_overview_projection`, `skill_detail_projection`, `progress_trend`, `metric_version_segment`) és egy téma-burkolót. A képernyők „hívó-adta" szerződésűek (`required this.projection`), de **a projekciót SENKI nem állítja elő**: a típusokra a feature-en kívül nulla hivatkozás van, és a router `/profile/progress` útvonala ma is a legacy `ProgressScreen`-t építi. A felület tehát elkészült, de halott kód.

Ez a kör a hiányzó ELŐÁLLÍTÓT írja meg a MEGLÉVŐ adatforrásokból (gyakorlás-történet, gamification-profil, elemzési eredmények), és élesíti a route-ot.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/domain/mastery/mastery_milestone_catalog.dart",
  "lib/features/gamification/data/practice_mastery_evidence_adapter.dart",
  "lib/features/gamification/public.dart",
  "lib/features/practice/public.dart",
  "lib/l10n/features/gamification_en.arb",
  "lib/l10n/features/gamification_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "lib/features/progress_v2/application/progress_projection_builder.dart",
  "lib/features/progress_v2/application/progress_providers.dart",
  "lib/features/progress_v2/public.dart",
  "lib/app/routing/app_route.dart",
  "lib/app/routing/app_router.dart",
  "test/features/gamification/domain/mastery_milestone_catalog_test.dart",
  "test/features/gamification/data/practice_mastery_evidence_adapter_test.dart",
  "test/features/progress_v2/progress_projection_builder_test.dart",
  "test/app/routing/progress_composition_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/features/today/hub_navigation_test.dart",
  "test/ui/ui_inventory_test.dart",
  "docs/ui/migration-status.md",
  "docs/rounds/e16-r02-progress-projection-and-router-placeholders.md",
]
gate_tests = [
  "test/features/gamification/domain/mastery_milestone_catalog_test.dart",
  "test/features/gamification/data/practice_mastery_evidence_adapter_test.dart",
  "test/features/progress_v2/progress_projection_builder_test.dart",
  "test/features/progress_v2/dashboard_states_test.dart",
  "test/features/progress_v2/mastery_evidence_test.dart",
  "test/app/routing/progress_composition_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/features/today/hub_navigation_test.dart",
  "test/ui/ui_inventory_test.dart",
  "test/l10n/arb_parity_test.dart",
  "test/tooling/gen_l10n_segments_test.dart",
  "test/core/architecture_dependency_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a kör a `/profile/progress` felhasználói útvonalat cseréli át egy másik képernyőre, és tanulási előrehaladást jelenít meg — hibás projekció esetén a felhasználó a saját fejlődéséről kapna téves képet. A `flutter-reviewer` + `flutter-devil-advocate` KÖTELEZŐ.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha egy projekciós mező kiszámításához olyan adat kellene, ami a fán MÉRHETŐEN nem létezik (nincs forrás-repository), a kimenet a `stopped` jelzés és a mező-lista — kitalált vagy szintetikus érték TILOS.

## 1. Cél

A `/profile/progress` a Progress V2 dashboardot mutassa, VALÓS, meglévő adatokból számított projekcióval — a legacy `ProgressScreen` pedig kontrolláltan váltson át (átirányítás vagy visszavonás az `E15-R03` terve szerint).

## 2. Jelenlegi állapot — mért tények

- `lib/features/progress_v2/`: 2 képernyő + 4 domain-projekció + 1 téma-burkoló; **0 provider**, **0 application/data fájl**.
- `ProgressOverviewProjection` és `SkillDetailProjection` hivatkozás a feature-en kívül: **0**.
- `app_router.dart` `/profile/progress` → a legacy `ProgressScreen` (az `E15-R03` audit mérte).
- Elérhető adatforrások: gyakorlás-történet (`lib/features/practice/data/`, 14 fájl), gamification-profil és ledger (`E16-R01` providerei), elemzési eredmények (`lib/features/audio_analysis/data/`, 23 fájl), song-trainer eredmények (`lib/features/song_trainer/data/`, 40 fájl).
- A `legacy_route_redirect_test.dart` a tizenegy legacy útvonal célját pinneli — a route-váltás ezt érinti.
- **A mastery-oldalnak a §0.0.H szerint NINCS forrása a fán** (0 produkciós milestone-katalógus, 0 evidencia-előállító, 0 milestone-l10n kulcs) — a §2 korábbi „gamification-profil és ledger" állítása MÉRVE téves. A forrás előállítása ezért ennek a körnek a része (§5.4–5.6).
- MÉRT, felhasználható mezők a gyakorlás-történetben: `PracticeHistoryEntry.{id, createdAt, definitionId, finalMetricSnapshot.{chord,rhythm,direction,overall}}` (`practice_history_entry.dart:28`), a nehézség és a tempó pedig a `PracticeDefinition.{difficulty, defaultTempo}` (`practice_definition.dart:19`, `builtin_practice_catalog.dart`).
- A ténylegesen játszott tempót a history NEM őrzi: a `highestStableTempoBpm` egyedül a Speed Builder futásából származik (`speed_builder_engine.dart:74`, `practice_session_result_history_mapper.dart:91`) — ez a hiány az §5.5-ben van kezelve.

## 3. Scope

**Benne van (a §0.0.H revízió szerint):** `domain/mastery/mastery_milestone_catalog.dart` — a v1 mastery-katalógus az §5.4 tábla szerint · `data/practice_mastery_evidence_adapter.dart` — a gyakorlás-történet → `MasteryEvidence` tiszta leképezés az §5.5 szerint · a milestone cím/leírás kulcsok a `lib/l10n/features/gamification_{en,hu}.arb` szegmensbe + a generált aggregátum újragenerálása · a `gamification`/`practice` publikus barrel MINIMÁLIS bővítése (a katalógus, az adapter és a `practiceCatalogProvider` + `PracticeDefinition.difficulty` eléréséhez) · `application/progress_projection_builder.dart` — a `ProgressOverviewProjection` és a `SkillDetailProjection` előállítása a MEGLÉVŐ forrásokból (tiszta Dart, óra és véletlen nélkül) · `application/progress_providers.dart` — a kompozíciós réteg (az `E16-R01` mintájára) · `public.dart` export · a router `/profile/progress` útvonalának átkötése a `ProgressDashboardScreen`-re + a skill-detail útvonal bekötése (az ÚJ `AppRoutes` konstans az `app_route.dart`-ban, az §5.8 szerint — §0.0.I/I1) · a legacy `ProgressScreen` kezelése az `E15-R03` terve szerint (átirányítás; a fájl TÖRLÉSE nem ennek a körnek a dolga) · `migration-status.md` frissítése.

**NINCS benne (tilos):**

- Új metrika vagy pontszám-definíció (`domain/` szabály) — a projekció a MEGLÉVŐ mezőket tölti.
- Szintetikus/„demo" adat bármilyen formában.
- Más feature képernyőinek átírása.
- A legacy `ProgressScreen` fájljának törlése.
- `docs/adr/**` — az ADR **0500**-at a Claude írja (§0.0.I).

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/domain/mastery/mastery_milestone_catalog.dart` | ÚJ — a v1 mastery-katalógus (§5.4) |
| `lib/features/gamification/data/practice_mastery_evidence_adapter.dart` | ÚJ — gyakorlás-történet → `MasteryEvidence` (§5.5) |
| `lib/features/gamification/public.dart` | a katalógus és az adapter export-sora (barrel-szabály) |
| `lib/features/practice/public.dart` | KIZÁRÓLAG export-sor, PONTOSAN az §5.5 adapterhez kellő nevekre: `practiceCatalogProvider` (`application/practice_catalog_controller.dart`), `PracticeDifficulty` (`domain/model/practice_difficulty.dart`), `PracticeHistoryEntry` (`domain/model/practice_history_entry.dart`), valamint a `domain/model/practice_metric_snapshot.dart` `PracticeMetricSnapshot` + `PracticeMetricDimension` hierarchiája (`PracticeMetricDimensionAvailable` is — ez NEM a már exportált `practice_metrics.dart`-ban él). A `PracticeDefinition` már exportált. Meglévő export-sor átírása/törlése és minden más változtatás TILOS (§0.0.I/I5) |
| `lib/l10n/features/gamification_{en,hu}.arb` | a 3 milestone cím + 3 leírás kulcsa, mindkét locale (§5.6) |
| `lib/l10n/app_{en,hu}.arb` | **generált aggregátum** — `dart run tool/gen_l10n_segments.dart --write` kimenete, kézzel **közvetlenül nem szerkeszthető** |
| `test/features/gamification/domain/mastery_milestone_catalog_test.dart` | az A8 cella |
| `test/features/gamification/data/practice_mastery_evidence_adapter_test.dart` | az A9 cella |
| `lib/features/progress_v2/application/progress_projection_builder.dart` | ÚJ — a projekció-előállító |
| `lib/features/progress_v2/application/progress_providers.dart` | ÚJ — a kompozíciós réteg |
| `lib/features/progress_v2/public.dart` | export |
| `lib/app/routing/app_route.dart` | KIZÁRÓLAG az ÚJ skill-detail útvonal-konstans HOZZÁADÁSA az §5.8 szerint (`profileProgressSkill`); meglévő konstans átírása, átnevezése vagy törlése TILOS (§0.0.I/I1) |
| `lib/app/routing/app_router.dart` | a `/profile/progress` átkötése + az ÚJ skill-detail `GoRoute` regisztrálása |
| `test/features/progress_v2/progress_projection_builder_test.dart` | a §6 projekció-cellái |
| `test/app/routing/progress_composition_test.dart` | a §6 útvonal-cellái |
| `test/app/navigation/*.dart` (három őr) · `test/ui/ui_inventory_test.dart` | regresszió-őrök — a jogosultság PONTOSAN a `/profile/progress` adapter típusának átírása; cella törlése, `skip`-je vagy gyengítése TILOS |
| `test/features/today/hub_navigation_test.dart` · `test/app/routing/app_router_test.dart` · `test/app/offline_network_guard_test.dart` | útvonal-szintű regresszió-őrök (§0.0.J) — a jogosultság PONTOSAN annyi, hogy a `/profile/progress`-en VÁRT képernyő-típus `ProgressScreen` → `ProgressDashboardScreen` legyen ott, ahol a teszt ezen az útvonalon jut a képernyőhöz; minden más állítás (a redirect-lánc, a shell-OFF `/progress` viselkedés, az offline-őr) VÁLTOZATLAN, cella törlése, `skip`-je, átnevezése vagy gyengítése TILOS |
| `docs/ui/migration-status.md` | a MÉRT állapot |

**Tilos zóna:** `lib/features/progress/**` (a legacy fájl) · `lib/features/progress_v2/domain/**` · `lib/features/{audio_analysis,song_trainer}/**` (olvasás igen, írás nem) · `lib/features/gamification/**` a §4 táblában NEM szereplő minden fájlja (az evaluator, a `mastery_progress.dart` és a `mastery_milestone.dart` VÁLTOZATLAN — a katalógus a MEGLÉVŐ típusokat tölti) · `lib/features/practice/**` a `public.dart` export-során kívül · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések (ADR 0500)

### 5.1 A projekció DETERMINISZTIKUS és tiszta

Azonos bemenet → azonos kimenet; `DateTime.now()` és `Random` a builderben TILOS (a hívó adja az időt). **NEM elfogadható gyengítés:** „az aktuális dátum kell hozzá" — az paraméter, nem mellékhatás.

### 5.2 Hiányzó forrás = EXPLICIT üres állapot

Ha egy készség-tengelyhez nincs mérés, a projekció ezt jelöli, és a képernyő üres állapotot mutat. **NEM elfogadható gyengítés:** nulla értékkel „kitöltött" trend, ami visszaesésnek látszik.

### 5.3 A legacy útvonal átirányít, nem tűnik el

**NEM elfogadható gyengítés:** a `/progress` mélylink csendes megszüntetése.

### 5.4 A v1 mastery-katalógus — annyi, amennyire MÉRT forrás van

`masteryMilestoneCatalogV1` — a **`final List<MasteryMilestone>`**, `List.unmodifiable(...)`-be
csomagolva, `catalogVersion: 1`. **`const` katalógus TILOS és lehetetlen**
(§0.0.I/I3): a `MasteryMilestone` és a `MasteryTempoRange` publikus felülete
factory, a `const` konstruktoruk privát.

Az id-k **lower snake_case**-ek, mert a domain saját `_requireStableId`-je a
`^[a-z][a-z0-9_]*$` regexet követeli (§0.0.I/I2) — pontozott id futásidőben dob.

| id | skill | metric | forrás-dimenzió (`finalMetricSnapshot`) | `minimumThreshold` | `minEvidenceSessions` | `difficulty` | `tempoRange` |
|---|---|---|---|---|---|---|---|
| `mastery_chord_transition_v1` | `chordTransition` | `accuracy` | `.chord` | `0.8` | `3` | `MasteryDifficulty.beginner` | `40–240` |
| `mastery_rhythm_accuracy_v1` | `rhythmAccuracy` | `accuracy` | `.rhythm` | `0.8` | `3` | `MasteryDifficulty.beginner` | `40–240` |
| `mastery_strum_consistency_v1` | `strumConsistency` | `accuracy` | `.direction` | `0.8` | `3` | `MasteryDifficulty.beginner` | `40–240` |

**A `difficulty` MÉRT választás, nem ízlés** (§0.0.I/I4). Az evaluator az eltérő
nehézségű bizonyítékot ELDOBJA (`mastery_evaluator.dart:108`), a builtin
katalógus 10 definíciójából pedig **8 `beginner`** és 2 `intermediate`
(`builtin.cGAmFProgression.v1:160`, `builtin.syncopatedUps.v1:214`). A v1
milestone-ok ezért `MasteryDifficulty.beginner`-ek, és **az `intermediate`
definícióból származó session a v1-ben SZÁNDÉKOSAN nem ad bizonyítékot** — ezt
az A8/A9 cellának ki kell mondania, nem elhallgatnia. **NEM elfogadható
gyengítés:** a nehézség-szűrő megkerülése azzal, hogy az adapter minden
sessiont `beginner`-nek jelöl (az §5.5 ezt külön tiltja).

`MasterySkill.tempoStability` a v1-ben **NEM kap milestone-t**: a fán nincs mért
`tempoAdherence` forrás (a `highestStableTempoBpm` a Speed Builder csúcs-tempója,
nem adherence-metrika). Ez DOKUMENTÁLT hiány — kitölteni TILOS.

**NEM elfogadható gyengítés:** a küszöb csökkentése azért, hogy „legyen mit
mutatni"; a `minEvidenceSessions` 2 alá vitele (a domain amúgy elutasítja).

### 5.5 A bizonyíték MÉRT mezőkből jön, és ami nem mérhető, az KIMARAD

`PracticeHistoryEntry` → `MasteryEvidence` (tiszta függvény, óra és véletlen nélkül):

- `sessionId` = `entry.id` · `observedAt` = `entry.createdAt.toUtc()` ·
  `origin` = `MasteryEvidenceOrigin.device` (a mérés a készüléken, gyakorlás
  közben történt); `confidence` marad `null` — a `device` origin nem követeli
  meg, és nincs mért forrása.
- `metricValue` = a milestone skilljéhez rendelt dimenzió, **kizárólag**
  `PracticeMetricDimensionAvailable` esetén. `notApplicable` /
  `insufficientData` → **NINCS bizonyíték** (nem `0`).
- `difficulty` = a `entry.definitionId`-hoz tartozó `PracticeDefinition.difficulty`
  1:1 leképezése. Ismeretlen `definitionId` → **NINCS bizonyíték**.
- `tempoBpm` = ugyanannak a definíciónak a `defaultTempo.bpm`-je. **MÉRT hiány:**
  a history nem őrzi a ténylegesen játszott tempót, ezért a v1 milestone-ok
  tempó-hatóköre szándékosan a teljes tartomány — a tempó így egyetlen
  bizonyítékot sem zár ki és egyetlen felhasználói számot sem befolyásol. A
  hiányt a §10 handoff rögzíti egy későbbi history-séma körnek.
- Egy `sessionId` skillenként EGY bizonyíték; a dedup és a monotonitás az
  `MasteryEvaluator` dolga — azt a kör NEM írja át.

**NEM elfogadható gyengítés:** hiányzó dimenzió `?? 0`-val; ismeretlen nehézség
„beginnernek" vétele; a nem mért tempó kitalálása.

### 5.6 A lokalizált cím a kompozíciós rétegből jön, EXPLICIT leképezéssel

A 3 cím + 3 leírás kulcs a `lib/l10n/features/gamification_{en,hu}.arb`
szegmensbe kerül (MINDKÉT locale), majd `dart run tool/gen_l10n_segments.dart --write`
futtatása következik: a `lib/l10n/app_{en,hu}.arb` **generált aggregátum**, ami
kézzel **közvetlenül nem szerkeszthető** (ADR 0307 §4, [L497 osztály: E08-R12/H6]).
A `titleKey`/`descriptionKey` → lokalizált szöveg feloldás a kompozíciós
rétegben, EXPLICIT `switch`-csel; dinamikus kulcs-feloldás TILOS (E13-R31 §0.0.B/B7).

### 5.7 Két projekciós mező MÉRT ÁLLANDÓ, nem kitöltés

- `ProgressOverviewProjection.isOffline` = `false`: a fejlődés-adat 100%-ban
  helyi (a `practiceHistoryRepositoryProvider` lokális tár, a progress semmit nem
  szinkronizál a fiókkal), tehát „még nem szinkronizált helyi állapot" nem
  létezhet. Mért állandó, nem hiányzó forrás.
- `SkillDetailProjection.recommendation` = `null`: ajánlás-katalógus a fán nincs,
  a mező opcionális — az EXPLICIT hiány a helyes érték. Kitalált ajánlás TILOS.

### 5.8 A skill-detail útvonal alakja KÖTÖTT (§0.0.I/I1)

Az implementer NEM talál ki sémát; a három döntés mérve, forrással:

- **A konstans:** `AppRoutes.profileProgressSkill = '/profile/progress/skills/:skillId'`
  — az SDD UI-50 kanonikus route-ja (`docs/sdd/13-chapter-13-ui-ux-design-system.md:7780`),
  amit a `SkillDetailScreen` doc-commentje is néven nevez
  (`skill_detail_screen.dart:15`: „the SDD's `/profile/progress/skills/:skillId`
  route does not exist on this tree"). **Paraméteres útvonal-szegmens, NEM
  `extra`-alapú** — az UI-50 mélylink-alak az SDD-ben pinnelt; az `extra` csak
  a `profileLibrarySession` precedensének erőforrás-átadási mintája.
- **A paraméter:** `:skillId` = `MasterySkill.code` (`chordTransition`,
  `rhythmAccuracy`, `strumConsistency`, `tempoStability`;
  `mastery_milestone.dart:2–11`). Ismeretlen vagy hiányzó `skillId` →
  átirányítás az `AppRoutes.profileProgress`-ra (a `profileLibrarySession`
  hiányzó-`extra` ágának merge-elt mintája, `app_route.dart:107–113`) — 404 vagy
  dobás TILOS.
- **A képernyő callbackje:** az `onOpenEvidence` az `AppRoutes.profileLibrarySession`
  konstanst + a `sessionId`-t kapja — ez az `E13-R31` A2 cellájában MÁR
  merge-elt szerződés; a `route_literal_guard_test` miatt string-literál TILOS.

A konstans HOZZÁADÁS: meglévő `AppRoutes` konstans átírása, átnevezése vagy
törlése TILOS, és az `AppRoutes.shellTabs` / `adaptiveShellDestinations` listák
VÁLTOZATLANOK (a skill-detail nem shell-cél).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A `/profile/progress` a `ProgressDashboardScreen`-t rendereli valós projekcióval | `progress_composition_test.dart` |
| A2 | A skill-detail útvonal (`AppRoutes.profileProgressSkill`, §5.8) a `SkillDetailScreen`-re visz a `:skillId` szerint kiválasztott készséggel, ismeretlen `skillId` esetén pedig a `/profile/progress`-ra irányít át (nem dob, nem 404) | `progress_composition_test.dart` |
| A3 | A builder determinisztikus: ugyanaz a bemenet kétszer ugyanazt adja | `progress_projection_builder_test.dart` |
| A4 | Mérés nélküli készség EXPLICIT „nincs adat" jelölést kap (nem nullát) | `progress_projection_builder_test.dart` |
| A5 | A legacy `/progress` mélylink továbbra is működik (átirányít) | `legacy_route_redirect_test.dart` |
| A6 | A builderben nincs `DateTime.now()` és `Random` | statikus cella a `progress_projection_builder_test.dart`-ban |
| A7 | A képernyő-leltár és a navigációs őrök VÁLTOZATLANUL zöldek | a §7 gate |
| A8 | A `masteryMilestoneCatalogV1` pontosan az §5.4 táblát pinneli (id, küszöb, `minEvidenceSessions`, `catalogVersion`), és `tempoStability` milestone NINCS benne | `mastery_milestone_catalog_test.dart` |
| A9 | Az adapter a nem mérhető sessiont ELDOBJA (nem elérhető dimenzió, ismeretlen `definitionId`), a mérhetőből pedig a mért mezőkkel állít elő bizonyítékot | `practice_mastery_evidence_adapter_test.dart` |
| A10 | Három, a küszöböt elérő builtin gyakorlás-történettel a `/profile/progress` **NEM** a new-user állapotot rendereli, hanem a mért készség-sorokat | `progress_composition_test.dart` |
| A11 | Az új milestone-kulcsok MINDKÉT locale-ban megvannak, és a generált aggregátum a szegmensekből újragenerálva változatlan | `arb_parity_test.dart`, `gen_l10n_segments_test.dart` |
| A12 | A `minimumThreshold` (`0.8`) MINDHÁROM oldala mérve: a küszöb **alatt** (`0.79`) nincs elsajátítás, **rajta** (`0.80`) van, **fölött** (`0.81`) van — és ugyanígy a `minEvidenceSessions` (`3`): két bizonyíték-sessionnel nincs, hárommal van | `progress_projection_builder_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A route átkötve marad a legacy képernyőre | A1 |
| A builder `DateTime.now()`-ot hív | A3 és A6 |
| Hiányzó mérés 0-val töltődik ki (hamis visszaesés) | A4 |
| A `/progress` mélylink 404-re fut | A5 |
| A katalógus üres marad (a projekció üres milestone-listát kap) | A8 és **A10** |
| Az adapter a hiányzó dimenziót `0`-val tölti | A9 (és A4) |
| Az ARB-kulcs csak `en`-be kerül be, vagy az aggregátum nincs újragenerálva | A11 |
| A küszöb szigorú `>` helyett `>=` (vagy fordítva) — a „rajta" eset elcsúszik | A12 |

**Valódi-sértés próba (KÖTELEZŐ, MINDKETTŐ, a §10-ben dokumentálva):**
1. cseréld a hiányzó-mérés ágat konstans `0`-ra, futtasd a §7 gate-et → az **A4**
   cellának PIROSNAK kell lennie → állítsd vissza;
2. ürítsd ki a katalógust (`const <MasteryMilestone>[]`), futtasd a §7 gate-et →
   az **A8** ÉS az **A10** cellának PIROSNAK kell lennie → állítsd vissza. Ez az
   a hibamód, ami a kör első pre-flightját megállította (§0.0.H).

## 7. Kötelező ellenőrzések

```bash
dart run tool/gen_l10n_segments.dart --write   # az ARB-kulcsok felvétele UTÁN, a gate ELŐTT
tools/round-gate.sh test/features/gamification/domain/mastery_milestone_catalog_test.dart test/features/gamification/data/practice_mastery_evidence_adapter_test.dart test/features/progress_v2/progress_projection_builder_test.dart test/features/progress_v2/dashboard_states_test.dart test/features/progress_v2/mastery_evidence_test.dart test/app/routing/progress_composition_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/legacy_route_redirect_test.dart test/app/navigation/tab_state_restoration_test.dart test/app/offline_network_guard_test.dart test/app/routing/app_router_test.dart test/features/today/hub_navigation_test.dart test/ui/ui_inventory_test.dart test/l10n/arb_parity_test.dart test/tooling/gen_l10n_segments_test.dart test/core/architecture_dependency_test.dart
```

## 8. Implementációs sorrend

1. A MÉRÉS: milyen mezőket vár a két projekció, és melyikhez van forrás (a §0.0.H tábla az induló állapot).
2. `mastery_milestone_catalog.dart` az §5.4 tábla szerint + az A8 teszt (RED-ből).
3. Az ARB-kulcsok a `lib/l10n/features/gamification_{en,hu}.arb`-ba, majd `dart run tool/gen_l10n_segments.dart --write`.
4. `practice_mastery_evidence_adapter.dart` az §5.5 szerint + az A9 teszt (RED-ből); a `practice/public.dart` export-sora.
5. `progress_projection_builder.dart` (tiszta Dart, RED-ből).
6. `progress_providers.dart` + a két `public.dart`.
7. Az ÚJ `AppRoutes.profileProgressSkill` konstans az `app_route.dart`-ba (§5.8),
   majd a router átkötése + a skill-detail `GoRoute` + a legacy átirányítás +
   az A2 és az A10 cella.
8. `migration-status.md` + a KÉT valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Hamis fejlődés-kép.** Kitöltött nullák visszaesésnek látszanak (A4).
- **Mélylink-törés.** A `/progress` megszüntetése mentett hivatkozásokat törne (A5).
- **Forráshiány.** Ha egy projekciós mezőhöz nincs adat, az `stopped` — nem szintetikus kitöltés.
- **Örökre üres dashboard.** Ha a katalógus vagy a bizonyíték-lánc üresen marad, a képernyő a new-user állapotba ragad, miközben a felhasználónak VAN gyakorlás-története — ezt az **A10** cella méri (§0.0.H).
- **Nem mért tempó.** A history nem őrzi a játszott tempót; a v1 tempó-hatókör ezért nem szűr (§5.5). A hiányt a §10 handoff adja tovább.

## 10. Implementation handoff — az implementer tölti ki

**Amit a kör megírt (§8 sorrend szerint):**

1. `lib/features/gamification/domain/mastery/mastery_milestone_catalog.dart` —
   `masteryMilestoneCatalogV1` (`final` + `List.unmodifiable`, 3 milestone,
   pontosan az §5.4 tábla), `test/features/gamification/domain/
   mastery_milestone_catalog_test.dart` (A8, RED-ből — hiányzó export miatt
   bukott, majd a `gamification/public.dart` export után zöld).
2. Az ARB-kulcsok (`lib/l10n/features/gamification_{en,hu}.arb`, 3 cím + 3
   leírás) + `dart run tool/gen_l10n_segments.dart --write` (a generált
   `lib/l10n/app_{en,hu}.arb`).
3. `lib/features/gamification/data/practice_mastery_evidence_adapter.dart` —
   `masteryEvidenceFromPracticeHistoryEntry`/`masteryEvidenceFromPracticeHistory`
   (§5.5), a `practice/public.dart` export-sorai (`practiceCatalogProvider`,
   `PracticeDifficulty`, `PracticeHistoryEntry`, a
   `practice_metric_snapshot.dart` típusai), `test/features/gamification/data/
   practice_mastery_evidence_adapter_test.dart` (A9, RED-ből).
4. `lib/features/progress_v2/application/progress_projection_builder.dart` —
   `buildProgressOverviewProjection`/`buildSkillDetailProjection`, tiszta
   Dart (nincs `DateTime.now()`, nincs `Random`), a `localize` paraméter a
   caller-adta EXPLICIT switch-nek (§5.6). `test/features/progress_v2/
   progress_projection_builder_test.dart` (A3/A4/A6/A12).
5. `lib/features/progress_v2/application/progress_providers.dart` — `now`
   provider, a gyakorlás-történet provider (`practiceHistoryV2ListProvider`
   `.value ?? []` mintája), a `progressV2IsOffline` mért állandó (§5.7), és a
   `progressV2LocalizedText` EXPLICIT l10n-switch (a router `Consumer`
   buildere hívja, `AppLocalizations`-t ad neki — NEM `Ref`, mert a
   `WidgetRef`/`Ref` nem közös szupertípus, `gamification_providers.dart`
   precedense). Mindkét fájl exportálva a `progress_v2/public.dart`-ból.
6. `lib/app/routing/app_route.dart` — az ÚJ
   `AppRoutes.profileProgressSkill = '/profile/progress/skills/:skillId'`
   konstans (KIZÁRÓLAG hozzáadás). `lib/app/routing/app_router.dart` — a
   `/profile/progress` GoRoute-ja most a valós projekciót építő
   `ProgressDashboardScreen`-t adja; ÚJ, top-level (nem shell-branch)
   `GoRoute` a skill-detailhez, `profileLibrarySession` mintájára —
   `redirect` az ismeretlen/nem-mért `skillId`-re a `profileProgress`-ra megy
   (a `tempoStability` is ide esik, mert nincs milestone-ja). `test/app/
   routing/progress_composition_test.dart` (A1/A2/A10, ÚJ fájl).
7. A három útvonal-szintű regressziós őr (§0.0.J) + a meglévő három-őr sor
   cellája frissítve `ProgressScreen` → `ProgressDashboardScreen`-re,
   KIZÁRÓLAG ott, ahol a teszt ténylegesen a `/profile/progress` útvonalon
   jut a képernyőhöz (`hub_navigation_test.dart` — shell-ON;
   `adaptive_scaffold_test.dart`, `legacy_route_redirect_test.dart` —
   szintén shell-ON). `app_router_test.dart` és `offline_network_guard_test.dart`
   VÁLTOZATLANOK maradtak: a saját harnessük shell-OFF, tehát a `/progress`
   ott továbbra is a bare, unconditional `GoRoute`-on át a legacy
   `ProgressScreen`-t adja — ez a §0.0.J saját szövege szerint várt,
   futásidejű-konfiguráció-függő különbség, nem hiba.

**A KÉT KÖTELEZŐ valódi-sértés próba eredménye:**

1. `practice_mastery_evidence_adapter.dart`-ban a hiányzó-mérés ágat
   (`if (dimension is! PracticeMetricDimensionAvailable) return null;`)
   ideiglenesen `metricValue = dimension is PracticeMetricDimensionAvailable
   ? dimension.value : 0.0;`-ra cserélve (a `null`-ág eltávolítva) — az
   **A4** cella PIROSRA váltott mindkét mérő tesztfájlban
   (`practice_mastery_evidence_adapter_test.dart`: 6 bukás,
   `progress_projection_builder_test.dart`: 2 A4-bukás). Visszaállítva,
   `git diff` üres.
2. `masteryMilestoneCatalogV1`-et ideiglenesen `List.unmodifiable(const
   <MasteryMilestone>[])`-ra cserélve — az **A8** cella (mind a 10 al-teszt)
   ÉS az **A10** cella (`progress_composition_test.dart`, 7 al-teszt) PIROSRA
   váltott: a dashboard visszaesett a „get started" új-felhasználói
   állapotba, miközben a seedelt gyakorlás-történet valós adatot tartalmazott
   — pontosan a §0.0.H hibaosztálya. Visszaállítva, `git diff` üres (mért
   `diff` paranccsal ellenőrizve).

**Továbbadott hiány (a §5.5 szerint, egy jövőbeli history-séma körnek):** a
`PracticeHistoryEntry` nem őrzi a ténylegesen játszott tempót
(`highestStableTempoBpm` kizárólag a Speed Builder csúcs-tempója, nem
adherence-metrika) — a v1 milestone-ok tempó-hatóköre (`40..240`) ezért
szándékosan nem szűr semmit (minden builtin definíció `60..90` BPM). Egy
jövőbeli kör, ha a history-séma bővül a ténylegesen játszott tempóval, ezt a
hatókört szűkítheti/pontosíthatja.

**Továbbadott hiány (review MINOR-2, egy jövőbeli körnek):** a lecserélt
`ProgressScreen` a V1 `practiceLogProvider`-t olvasta
(`progress_screen.dart:48`), amit a Live, az Analyze és a Learn ír
(`live_screen.dart:198`, `analyze_providers.dart:228`,
`learn_screen.dart:349`); az új `ProgressDashboardScreen` KIZÁRÓLAG V2
`PracticeHistoryEntry`-t olvas (`progressPracticeHistoryProvider`,
`progress_providers.dart:23-28`). Egy csak V1-előzménnyel rendelkező
felhasználó tehát a „get started" új-felhasználói állapotot látja ott, ahol
korábban statisztikát látott. Az §5.5 a `PracticeHistoryEntry`-t pinneli, és a
V1-bejegyzések nem hordoznak metrika-pillanatképet, tehát ez specifikáció
szerint helyes — de a hiányt egy jövőbeli körnek dokumentálni kell, ugyanabban
az osztályban, aminek megelőzésére a §0.0.H/A10 létrejött.

**Másodlagos, dokumentált (nem blokkoló) rés:** a `SkillDetailScreen.
onOpenEvidence` callback a router `context.push(route.replaceFirst(
':sessionId', sessionId))`-t hívja `extra` nélkül (a callback szerződése
csak `(route, sessionId)`-t ad, `LibraryItem`-et nem) — a
`profileLibrarySession` route redirectje ilyenkor a hiányzó `extra` miatt a
`/profile/library`-ra irányít, nem a konkrét session-re. Ez a
`profileLibrarySession` E13-R31-ben MÁR merge-elt szerződésének mért
korlátja, nem ennek a körnek a hibája — a callback pontosan azt a route+id
párt kapja meg, amit a screen ad, a router nem tud extra objektumot
fabrikálni belőle.

**Gate:** `tools/round-gate.sh` a 16 megadott teszt-útvonallal, zöld (lásd a
kör-jelzés melletti `done` üzenetet).

## 11. Review — a Claude tölti ki
