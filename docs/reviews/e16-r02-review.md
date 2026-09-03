# E16-R02 — kör-review (ADR 0055, `sdd-round-review`)

- **Kör:** `E16-R02` — A Progress V2 bekötése és a router placeholder-mentesítése
- **Branch:** `sonnet-impl/e16-r02-progress-projection-and-router-placeholders`
- **Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Reviewer:** Claude (Opus 5) orchestrátor, read-only, izolált `/tmp` klónban
- **Review-elt HEAD:** `5420777e` (a javító kör után; első review: `c2b1362a`)
- **Merge-bázis:** `origin/main @ 9ba54399`
- **ADR:** `0500` (a pre-flightban az orchestrátor írta)

## VÉGSŐ DÖNTÉS: **CHANGES REQUESTED — a kör HALT-ol (H3)**

**A kör TERMÉKE kész és jó minőségű.** A két MAJOR lelet a javító körben
lezárult, a célzott gate és a **Full Gate CI is zöld**. A merge-et **nem a kör
diffje blokkolja**, hanem egy a kör **tilos zónájában** (`tools/**`) élő,
mérve önellentmondó őr-teszt-csoport, amit ez a session nem javíthat
(ADR 0087 §4 — „a mérce nem módosulhat attól, akit mér"). Részletek a
**§4 Merge-blokkoló** szakaszban.

---

## 1. Elvégzett mérések

| Mérés | Eredmény |
|---|---|
| Gépi scope-audit (implementer-only, `47e062f8..5420777e`) | **OK** — 22 útvonal, 0 sértés |
| `tools/round-gate.sh` a §7 16 útvonalával, izolált `/tmp` klónban (`c2b1362a`) | **21/21 ZÖLD** |
| Ugyanaz a gate a javító kör után (`5420777e`) | lásd §5 |
| Full Gate CI (`full-gate.yml`) a `c2b1362a` SHA-n | **success** (run 33792199608) |
| Router CI (`router-ci.yml`) a `c2b1362a` SHA-n | **failure** — 5 teszt, mind `tools/tests/**` |
| `tools/round-ci-plan.py` | `dispatch: full-gate.yml`, `router_ci_expected: true` |
| `flutter-reviewer` ügynök (kötelező, `risk = high`) | 0 BLOCKER, 2 MAJOR, 5 MINOR, 5 NOTE |
| `flutter-devil-advocate` ügynök (kötelező, `risk = high`) | **verdikt nélkül állt le** (§6 NOTE-4) |

### 1.1 A pre-flight két kötelező mérése (a brief fejléce)

| Állítás | Mérve `main @ e367048f`-on | Eredmény |
|---|---|---|
| a `/profile/progress` MÉG a legacy `ProgressScreen`-t építi | `app_router.dart:544-545` | IGAZ |
| a projekciós típusokra a feature-en kívül 0 hivatkozás | `grep -rn … \| grep -v progress_v2/` | **0** |

---

## 2. Acceptance criteria — tételes bizonyíték

| # | Kritérium | Bizonyíték | Verdikt |
|---|---|---|---|
| A1 | `/profile/progress` → `ProgressDashboardScreen` valós projekcióval | `progress_composition_test.dart:113-140` — a VALÓDI `routerProvider`-en át; a cella a `MilestoneOverviewEntry`-t is megnézi (`evidenceSessionCount == 3`, `isAchieved`), nem csak a widget-típust | ✅ |
| A2 | skill-detail útvonal `:skillId` szerint, ismeretlenre redirect | `:165-253` — érvényes id, ismeretlen id, `tempoStability`, és a dashboard-sor tap-ja; `takeException()` is mérve | ✅ |
| A3 | a builder determinisztikus | `progress_projection_builder_test.dart` A3 cella | ✅ |
| A4 | mérés nélküli készség EXPLICIT „nincs adat", nem nulla | A4 három cellája (üres dimenzió, testvér-milestone kontroll, ismeretlen `definitionId`) | ✅ |
| A5 | a legacy `/progress` mélylink továbbra is működik | `legacy_route_redirect_test.dart`, `hub_navigation_test.dart:247` | ✅ |
| A6 | nincs `DateTime.now()` / `Random` a builderben | statikus cella + a forrás olvasása (`now` kötelező paraméter) | ✅ (korlát: NOTE-2) |
| A7 | a képernyő-leltár és a navigációs őrök változatlanul zöldek | a §7 gate 21/21 | ✅ |
| A8 | a katalógus pontosan az §5.4 táblát pinneli, `tempoStability` nincs | `mastery_milestone_catalog_test.dart` 10 cellája (id-k, `0.8`, `3`, `beginner`, `40..240`, `catalogVersion: 1`, snake_case, unmodifiable) | ✅ |
| A9 | az adapter a nem mérhető sessiont ELDOBJA | `practice_mastery_evidence_adapter_test.dart` 9 cellája | ✅ |
| A10 | három küszöböt elérő session → NEM new-user állapot | `progress_composition_test.dart` A10; a javító kör után a VALÓDI repository-láncon át (MAJOR-2) | ✅ |
| A11 | mindkét locale + a generált aggregátum újragenerálva | `arb_parity_test.dart`, `gen_l10n_segments_test.dart` zöld; a diff mindkét szegmenst és mindkét aggregátumot tartalmazza | ✅ |
| A12 | a `0.8` küszöb és a `3` session MINDHÁROM oldala mérve | `progress_projection_builder_test.dart` — `0.79`/`0.80`/`0.81` és `2`/`3` | ✅ |

**A §6.1 mérce-mátrix** minden sorához tartozik cella. A KÉT kötelező
valódi-sértés próbát az implementer elvégezte és a §10-ben dokumentálta; a
2. próba (üres katalógus → A8 **és** A10 piros) pontosan a §0.0.H
hibaosztályát méri.

---

## 3. Leletek

### MAJOR-1 — a skill-detail útvonal shell-OFF alatt megszegte a §5.8 redirect-szerződését — **ZÁRVA** (`5420777e`)

**Mérve** (a reviewer ügynök eldobható próbájával, `adaptiveShellEnabled: false`):

```
PROBE-A path=/profile/progress/skills/chordTransition  skillDetail=1  dashboard=0
PROBE-B path=/profile/progress/skills/notARealSkill    → a user a /live-on köt ki
```

Az ÚJ `GoRoute` (`app_router.dart:350`) top-level volt, a redirect CÉLJA
(`AppRoutes.profileProgress`, `:605`) viszont csak az
`if (adaptiveShellEnabled)` ágon (`:493`) belül létezik. Shell-OFF alatt tehát
az ismeretlen `skillId` egy nem regisztrált útvonalra irányított →
`onException` → `/live`; egy ÉRVÉNYES `skillId` pedig mélylinkkel elérhetővé
tette a `SkillDetailScreen`-t egy olyan buildben, ahol a teljes progress_v2
felület szándékosan ki van kapcsolva. Egyik cella sem fedte: a
`progress_composition_test.dart` mind az öt esete `adaptiveShellEnabled: true`.

**Javítás (`app_router.dart:349-358`):** a redirect shell-OFF alatt az
MINDIG regisztrált legacy `AppRoutes.progress`-ra megy. Új, shell-OFF cella
méri mindkét ágat. A `profileLibrarySession` (ugyanilyen látens hibával,
`:338` → `:592`) érintetlen maradt — az az E13-R31 merge-elt szerződése.

> **NOTE:** az §5.8 a redirect célját `AppRoutes.profileProgress`-ként
> rögzíti, és nem rendelkezik a shell-OFF esetről. A választott megoldás
> szemantikailag ezzel egyirányú (shell-ON alatt a `/progress` amúgy is a
> `/profile/progress`-ra irányít), de az **§5.8 szövege egy későbbi körben
> pontosítandó** a shell-OFF céllal. Ez nem blokkoló.

### MAJOR-2 — az A10 cella nem futtatta a repository→dashboard szakaszt — **ZÁRVA** (`5420777e`)

A `progress_composition_test.dart` minden cellája a
`progressPracticeHistoryProvider`-t overrideolta, ezért a provider TÖRZSÉT
(`ref.watch(practiceHistoryV2ListProvider).value ?? []`) a fán **egyetlen
teszt sem** futtatta — a kör SAJÁT hibaosztálya (§0.0.H) egy réteggel kijjebb.
A bekötés MÉRVE helyes volt (`PROBE-D isNewUser=false sessions=[3,0,0]`), tehát
ez mérce-hézag volt, nem élő hiba.

**Javítás:** az A10 cella egy `_FakeHistoryRepository`-t injektál a
`practiceHistoryRepositoryProvider`-be, így a teljes lánc (repository →
`practiceHistoryV2ListProvider` → `progressPracticeHistoryProvider` → builder →
képernyő) végigfut. A többi cella szándékosan a szűkebb override-on maradt.

### MINOR-1 — a néma `_ => key` l10n-ág — **ZÁRVA** (mérve)

`progress_providers.dart:52`. A hat kulcsból cella csak kettőt járt be, tehát
a másik négy elgépelése zöld gate mellett nyers ARB-azonosítót renderelt volna
a felhasználónak. A javító kör felvette azt a cellát, amely a katalógus
**mind a hat** kulcsát feloldja és megköveteli, hogy ne a kulcsot kapja vissza.

### MINOR-2 — a V1 gyakorlás-történet láthatatlan az új dashboardnak — **DOKUMENTÁLVA**

A lecserélt `ProgressScreen` a V1 `practiceLogProvider`-t olvasta
(`progress_screen.dart:48`), amit a Live, az Analyze és a Learn ír. Az új
dashboard KIZÁRÓLAG V2 `PracticeHistoryEntry`-t olvas, tehát egy csak V1
előzménnyel rendelkező felhasználó a „get started" állapotot látja ott, ahol
eddig statisztikát. Az §5.5 a `PracticeHistoryEntry`-t pinneli és a V1
bejegyzések nem hordoznak metrika-pillanatképet, tehát ez **specifikáció
szerint helyes** — de a §10 eredetileg csak a tempó-hiányt sorolta. A javító
kör átvezette a §10-be, egy jövőbeli körnek továbbadva.

### MINOR-3 — a `hub_navigation_test.dart:247` teszt-leírása elavult — **SZÁNDÉKOSAN NYITVA**

A név (`'legacy /progress still redirects to ProgressScreen'`) már nem
pontos, de a §4 tábla a három útvonal-szintű őrre az **átnevezést
KIFEJEZETTEN tiltja**. Nem javítható ebben a körben; egy későbbi kör briefje
adjon rá kifejezett engedélyt.

### MINOR-4 — az evidence-sor dead-endje — **KÖRÖN KÍVÜL**

A `SkillDetailScreen.onOpenEvidence` a `profileLibrarySession`-t `extra`
nélkül pusholja, aminek a redirectje a `/profile/library`-ra visz. Ez az
E13-R31 **merge-elt** szerződésének mért korlátja (a callback csak
`(route, sessionId)`-t ad), nem ennek a körnek a hibája — javítása H2 lenne.
A §10 őszintén közli. Follow-up kör tárgya.

---

## 4. MERGE-BLOKKOLÓ — H3: a Router CI öt őr-tesztje a kör tilos zónájában él

**Ez a halt oka, és NEM a kör diffjének hibája.**

A `router-ci.yml` a merge SHA-n (`c2b1362a`) **piros**:

```
FAILED tools/tests/test_e16_r02_route_catalog_scope.py::…::test_new_route_shape_is_pinned_and_matches_the_sdd
FAILED tools/tests/test_e16_r02_route_catalog_scope.py::…::test_practice_barrel_permission_covers_every_adapter_type
FAILED tools/tests/test_brief_lint_route_level_screen_swap.py::…::test_the_outside_pin_is_named_by_the_rule
FAILED tools/tests/test_brief_lint_route_level_screen_swap.py::…::test_the_revised_brief_leaves_no_route_level_pin_open
FAILED tools/tests/test_brief_lint_route_level_screen_swap.py::…::test_the_rule_is_silent_for_routes_the_brief_never_names
5 failed, 897 passed, 2 skipped, 755 subtests passed
```

### A MÉRT gyökérok

Ezek az őrök az ADR 0112 önjavító köreiben születtek (§0.0.I és §0.0.J
„Őrteszt" sorai), és a kör MUNKÁJÁNAK HIÁNYÁT pinnelik — vagyis pontosan
azt, aminek a kör sikerével meg kell szűnnie. Két példa a saját szövegükkel:

```python
# tools/tests/test_e16_r02_route_catalog_scope.py:127
self.assertNotIn(
    "/profile/progress/skills/:skillId",
    ROUTE_CATALOGUE.read_text(encoding="utf-8"),
    "the constant does not exist yet — if it lands outside this "
    "round, this guard must be rewritten, not deleted",
)

# tools/tests/test_e16_r02_route_catalog_scope.py:188
self.assertNotIn(
    type_name, barrel,
    f"{type_name} is already exported — this guard's premise "
    "moved; re-measure instead of relaxing it",
)
```

Az §5.8 KÖTELEZI a körre a `profileProgressSkill` konstans felvételét, az
§0.0.I/I5 pedig KÖTELEZI a `PracticeHistoryEntry` barrel-exportját — tehát a
kör csak úgy teljesíthetné ezeket az őröket, ha megszegné a saját briefjét.

A `test_brief_lint_route_level_screen_swap.py` három cellája ugyanez az
osztály a lint felől: a `route_level_swapped_screens()` a MAI fát olvassa, és
mivel a `/profile/progress` már a `ProgressDashboardScreen`-re mutat, a
lint már nem a `progress_screen.dart`-ot jelenti, hanem az
`unified_library_screen.dart`-ot — a cellák viszont az előbbit várják.

### A bizonyíték, hogy ez nem a kör diffjének hibája

```
# a kör indulási bázisán (main @ 9ba54399):
python3 -m pytest tools/tests/test_e16_r02_route_catalog_scope.py \
    tools/tests/test_brief_lint_route_level_screen_swap.py \
    tools/tests/test_e16_r02_mastery_source_scope.py -q
→ 19 passed

# a kör HEAD-jén:
→ 5 failed, 14 passed
```

Vagyis az őrök a bázison zöldek, és pontosan a brief által ELŐÍRT munka viszi
őket pirosra.

### Miért nem javíthatja ez a session

Mind az öt fájl a `tools/tests/**` alatt van. A brief **Tilos zóna** sora
szó szerint felsorolja a `tools/**`-ot, és az `allowed_paths` nulla `tools/`
bejegyzést tartalmaz. Az ADR 0087 §4 szerint egy útközben talált,
mérce-oldali akadály **halt**, nem ad hoc javítás — „a mérce nem módosulhat
attól, akit mér".

**A Router CI ezen felül kétszer piros ezen a körön** (`ea763545` és
`c2b1362a`), ami önmagában H5 — de mindkettőnek EZ az egy gyökéroka, ezért a
pontosabb kód a **H3**.

> A `1c6ca6fc` (pre-flight) SHA-n mért HARMADIK piros ettől független és már
> **tárgytalan**: a `test_completion_matrix_sync.py` az E15-R12 merge-e utáni
> átmeneti drift miatt bukott, amit a `9ba54399` javított; a rebase után
> `tools/sync-completion-matrix.py --check` → `completion matrix is in sync`.

---

## 5. A javító kör utáni saját gate-futás

Az izolált `/tmp/review2-e16-r02` klónban, a `5420777e` HEAD-en, a §7
teljes útvonal-listájával:

```
→ [1] format: ZÖLD          → [12] test app/offline_network_guard_test.dart: ZÖLD
→ [2] analyze: ZÖLD         → [13] test app/routing/app_router_test.dart: ZÖLD
→ [3]…[11] a 9 cél-teszt: ZÖLD  → [14]…[18] a maradék öt teszt: ZÖLD
→ [19] architecture: ZÖLD   → [20] secrets: ZÖLD   → [21] l10n: ZÖLD

MINDEN GATE ZÖLD.
```

**21/21 ZÖLD** — a javító kör egyetlen regressziót sem hozott, és a két MAJOR
új cellája is zölden fut. (A `[17]` lépés kimenetében látható
`aggregátum ELÁVULT — PIROS` sor a `gen_l10n_segments_test.dart` SAJÁT
őr-cellájának várt belső kimenete, nem gate-hiba: maga a lépés ZÖLD.)

## 6. NOTE-ok (nem blokkolnak)

1. `progress_projection_builder.dart:44-54` — a trend-pontok a *mastery
   katalógus* verziójával címkéződnek, miközben a pontok a
   `finalMetricSnapshot.overall`-ból jönnek, amit az a katalógus nem
   verziózik. A `segmentByCatalogVersion` így mindig pontosan egy szegmenst
   ad — a verzió-szegmentálás jelenleg inert.
2. Az A6 cella substring-vizsgálat; `DateTime.timestamp()`, `clock.now()`
   vagy egy változóban tartott `Random` átmenne rajta.
3. `practice_mastery_evidence_adapter.dart:95-100` — `StateError` egy
   leképezetlen nehézség-kódra. Ma elérhetetlen (mindkét enum
   `beginner`/`intermediate`/`advanced`), de ez egy **dobás a router
   build-jében**: egy új `PracticeDifficulty` érték piros képernyőt adna a
   `/profile/progress`-on ahelyett, hogy az §5.5 előírása szerint eldobná a
   bizonyítékot.
4. A kötelező `flutter-devil-advocate` ügynök 60 tool-hívás és ~20 perc után
   **verdikt nélkül** állt le (utolsó sora egy szándéknyilatkozat volt). A
   futása nem tekinthető elvégzett ellenőrzésnek; a lefedettséget a
   `flutter-reviewer` mért leletei és a saját méréseim adják. A `risk = high`
   briefek ügynök-követelménye emiatt ebben a körben csak részben teljesült.
5. `app_router.dart` — a `_hasMasteryMilestoneForSkill` és a
   `buildSkillDetailProjection` ugyanazt az invariánst (`skill.code ==
   skillId`) két külön karbantartott függvényben duplikálja; a `!`-ok emiatt
   biztonságosak, de az invariáns nincs egy helyen.

## 7. Amit a self-heal körnek javasolok

1. Írd át a `tools/tests/test_e16_r02_route_catalog_scope.py` két celláját
   (`:127`, `:188`) a saját üzenetük szerint (**„must be rewritten, not
   deleted"**, **„re-measure instead of relaxing it"**): a kör LANDOLÁSA után
   a helyes mérce a jelenlét, nem a hiány.
2. A `tools/tests/test_brief_lint_route_level_screen_swap.py` három celláját
   kösd fixture-höz (a brief és a fa egy rögzített pillanatképéhez), ne az
   ÉLŐ fához — így egy kör landolása nem fordítja meg őket.
3. Általánosabb tanulság a `docs/LESSONS.md`-be: **egy önjavító kör
   „Őrtesztje" nem pinnelheti a javított kör munkájának HIÁNYÁT az élő fán**,
   különben a kör sikere garantáltan pirosra viszi a Router CI-t, és a kört a
   saját őre zárja ki a merge-ből.
