# E15-R07 — Practice Generator bekötése (route + flag), majd migrálása

- **Státusz:** PREPARED (újraírva 2026-09-01 user-döntés alapján, kód olvasva: `main @ c2c3801`)
- **Típus:** Chapter 15 (UI-aktiválás és -befejezés), Kör 7
- **Kör-azonosító:** `E15-R07`
- **Branch:** `<motor>/e15-r07-practice-generator-migration`
- **Előfeltétel:** `E15-R03` merge-elve (a visszavonási terv mérte meg, hogy a flow bekötetlen)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `0491` — a 2026-09-02-i pre-flight ÚJRA MEGMÉRTE (§0.0.C/1). A korábban ide írt `0481` KÖZBEN elkelt: a `docs/adr/0481-program-threat-model-and-release-security-scan.md` az `E12-R18` (PR #514, `3b49c501`) döntése, MERGE-ELVE a `main`-en. A `tools/round-slots.py reserve-adr --round E15-R07` foglalója a kör valódi számát **`0491`**-re adta (exit 0). A queue-sor `adr` oszlopát a driver vezeti (orchestrátor-tilalom a `pipeline-queue.tsv`-re).

**Visszakeresett előzmény:** [ADR 0306](../adr/0306-plan-preview-presentation-activation-boundary.md) (plan-preview aktiválási határ — a preview-felület a core útra nem hathat), [ADR 0471](../adr/0471-screen-reachability-is-measured-not-assumed.md) (az elérhetőség MÉRT tulajdonság; a `retire` verdikt JAVASLAT, a bekötés/nyugdíjazás produkt-döntés), [ADR 0255](../adr/0255-deterministic-practice-plan-generation.md) (a generátor szerződése).

## 0.0 MIÉRT íródott újra ez a brief — a régi premisszái MÉRTEN hamisak voltak

A kör korábbi változata tiszta megjelenés-migráció volt, két kimondott premisszára építve. **Mindkettő hamis**, ezért futott a lánc HALT-ra (2026-09-01):

| Régi állítás | MÉRT valóság |
|---|---|
| „az `E15-R02` óta a Practice Generator flag BE van kapcsolva az előnézeti buildekben" | `lib/app/config/feature_flags.dart:84` — `practiceGeneratorEnabled: false` a `forEnvironment` gyárban is, MINDEN környezetben. A mezőt a `feature_flag_registry.dart:144` `killSwitchPath`-ja szó szerint így írja le: „hardcoded to `false` in every environment … enabling it requires a source change". |
| „ezek a képernyők a fő navigációból elérhetők" | `docs/ui/retirement-plan.md:241–246` — mind a 6 képernyő `unreachable`: **nincs route és nincs építési hely sehol a `lib/`-ben**. A `lib/app/routing/app_route.dart` egyetlen `plan*` útvonalat sem deklarál. |

A `retirement-plan.md` §3.2 ezt „built, unwired" néven tartja nyilván, és kimondja: *„design tokens are moot on a screen nobody can open"* — a bekötés vagy nyugdíjazás **produkt/navigációs döntés**, amit az E15-R03 javasolt, de nem hozott meg.

> **A döntés megszületett (user, 2026-09-01): BEKÖTNI.** A Practice Generator kap belépési pontot (route + flag), és **utána** megy át a design-rendszerre. A `plannerAssistEnabled` (modell-segített javaslatok) ebben a körben **NEM** kapcsol be — a bekötés a determinisztikus generátorra szól.

Ezért a kör KÉT fázisú, és a fázisok sorrendje kötött: **F1 bekötés → F2 migráció**. Az F2 acceptance-e (szövegskála, locale, állapotok) csak akkor jelent bármit, ha az F1 után a képernyő valóban megnyitható.

### 0.0.B Revízió (ADR 0112 önjavító kör, 2026-09-01) — az F1-nek ELŐFELTÉTELE van

**Előfeltétel (ÚJ):** `E15-R14` (Practice Generator kompozíciós réteg,
[`e15-r14-practice-generator-composition-layer.md`](e15-r14-practice-generator-composition-layer.md))
merge-elve. A `docs/execution/pipeline-queue.tsv` sora ezért az `E15-R07` sora
FÖLÉ került — a `round-slots.py unmet_prerequisites` sor-sorrendben ÉS a fenti
`Előfeltétel` szóból egyaránt blokkol, amíg az `E15-R14` nem `done`.

**Miért.** A kör `stopped` jelzéssel állt meg (H3, 2026-09-01), és a STOP mérten
indokolt volt; az önjavító kör FÜGGETLENÜL reprodukálta (`main @ 1544e6bd`):

| Mérés | Eredmény |
|---|---|
| `grep -rln "Provider<\|NotifierProvider\|ChangeNotifierProvider" lib/features/practice_generator` | **ÜRES** — nulla Riverpod-provider a feature alatt |
| `grep -rn "implements PracticeEvidenceRepository" lib/` | **EGY** találat, és az a `domain/repository/practice_evidence_repository.dart:107` `InMemoryPracticeEvidenceRepository` **teszt-fake** („never forgets") |
| `plan_setup_screen.dart:96-99` | a step-4 „Befejezés" gomb csak `controller.next()`-et hív — nincs `onComplete`, nem indít generálást |

Ebből az F1 NEM „route + flag" méretű: a `PlanPrivacyScreen` `deleteUseCase`/
`exportUseCase`-e `PracticeEvidenceRepository`-t kér (`delete_practice_planning_data.dart:56`,
`export_practice_planning_data.dart:103`), a `PlanPreviewScreen` KÉSZ
`AdaptivePracticePlan`-t + `GenerationPlanActivation`-t, a `PlanChangeReviewScreen`
egy `PlanRevisionProposal`-t. A feloldás ÚJ `data/` + `presentation/providers/`
kód — amit EZ a brief a §0 és a §3 STOP-mondatával kifejezetten tilt („a
képernyők a meglévő providereikből élnek; **ha nem, az önálló kör**"). A brief
tehát önmagával volt ellentmondásban: bármely implementer újra `stopped`-ot ad.

**A javítás alakja.** A STOP-mondat MARAD (valódi védelem, nem gyengítjük); a
hiányzó kompozíciós réteget az `E15-R14` szállítja, és az `E15-R07` utána indul
újra — akkor az F1 valóban route + flag + belépési pont méretű lesz.

**A már elvégzett munka MEGŐRZENDŐ.** Az `sonnet-impl/e15-r07-practice-generator-migration`
ágon az **F2 KÉSZ** (mind a 6 képernyő design-rendszer migrációja, commit
`30bc31fd`, migráltság 69/96), nincs PR és nincs merge. Az újrainduló kör EZT AZ
ÁGAT viszi tovább (a `round-resume-probe.sh` hagyaték-méréssel), nem kezdi újra.
Az F2 önmagában továbbra sem merge-elhető (§0.0.A/5).

### 0.0.C Revízió (orchestrátor-pre-flight, 2026-09-02, `main @ 70eefdf4`) — az F1 a MÉRT kompozícióhoz szűkül

Az `E15-R14` merge-elve (PR #534, ADR 0482), tehát az §0.0.B előfeltétele
teljesült. A §0.0.A/2–4 kötelező újramérése viszont **nem** azt adta, amit az
önjavító kör előrevetített („akkor az F1 valóban route + flag + belépési pont
méretű lesz"): a kompozíciós gyökér **két seamet szándékosan nyitva hagyott**,
és ezek a mai `lib/`-ben `UnimplementedError`-t dobnak.

**MÉRÉS 1 — a két dobó seam** (`practice_generator_providers.dart:85`, `:149`):

```
exerciseCandidateResolverProvider   -> throw UnimplementedError(...)   # :85
generationPlanInputBuilderProvider  -> throw UnimplementedError(...)   # :149
```

`grep -rn "ExerciseCandidateResolver" lib/` és `grep -rn "GenerationPlanInputBuilder" lib/`:
mindkettő **csak `typedef` + a dobó provider** — KONKRÉT implementáció NULLA a
`lib/` egészében. `lib/main.dart:90` `overrides:` listája egyiket sem írja felül.

**MÉRÉS 2 — képernyőnkénti konstruálhatóság a kompozíciós gyökérből**, a
tranzitív seam-függés szerint (`localPracticePlanRepositoryProvider` a `:95`
soron `ref.watch(exerciseCandidateResolverProvider)`-t hív, tehát MINDEN rá
épülő provider dob):

| # | Képernyő | Provider-út | Verdikt |
|---|---|---|---|
| 1 | `PlanSetupScreen` | `planSetupControllerProvider` → draft + clock + id + locale | ✅ **konstruálható** |
| 2 | `TodayPlanScreen` | `todayPlanControllerProvider` → clock | ✅ **konstruálható** |
| 3 | `PlanPreviewScreen` | factory → `localPracticePlanRepositoryProvider` → **dob**; + kész `AdaptivePracticePlan` kell | ❌ seam |
| 4 | `PlanPrivacyScreen` | `delete`/`exportPracticePlanningDataProvider` → `localPracticePlanRepositoryProvider` → **dob** | ❌ seam |
| 5 | `WeeklyPlanScreen` | `activePracticePlanProvider` → `localPracticePlanRepositoryProvider` → **dob** | ❌ seam |
| 6 | `PlanChangeReviewScreen` | kötelező `proposal: PlanRevisionProposal` — a `revisePracticePlanProvider` use case aktív tervet igényel (3–5. út) | ❌ seam |

**Következtetés és a revízió alakja.** A 3–6. képernyő bekötése ma egy
`ExerciseCandidateResolver` (és a generáláshoz egy `GenerationPlanInputBuilder`)
MEGÍRÁSÁT követelné a `data/`+`application/` rétegben — pontosan az, amit ennek
a briefnek a §0/§3 STOP-mondata tilt, és amit a
`tools/tests/test_e15_r07_composition_prerequisite.py::StopClauseIsIntactTest`
merge-elt őre véd. A STOP-mondat tehát **MARAD**, és a kör **NEM** veszi
magához a kompozíciós fájlokat (ugyanennek az őrnek a
`test_the_blocked_round_still_excludes_them` cellája).

Ezért az F1 a **MÉRTEN konstruálható részhalmazra szűkül** — ez az `§0.0.A/5`
scope-fedezet-klauzula és az orchestrátor `ADR 0087 §2` szerinti
**lista-SZŰKÍTÉSI** jogköre (tágítás NEM történik):

- **F1 bekötése:** `PlanSetupScreen` + `TodayPlanScreen` — route-konstans,
  `practiceGeneratorEnabled`-re kapuzott `GoRoute`, és EGY belépési pont a
  practice hubon (§5.2), ami a `PlanSetupScreen`-re navigál.
- **Elhalasztva:** a 3–6. képernyő route-ja. Az a kör nyitja meg, amelyik előbb
  bekötötte a két seamet. Route-ot **regisztrálni tilos** olyan képernyőhöz,
  amelynek a providere ma dob — az nem „majdnem kész bekötés", hanem egy
  `UnimplementedError`-ba futó, kattintható út (a CLAUDE.md silent-no-op
  tilalmának crash-változata).
- **Az F2 KÉSZ és marad:** a §7 migráltság-mérés 2026-09-02-án mind a 6
  képernyőre `MIGRATED`-et ad (a `30bc31fd` commit) — a 3–6. képernyő
  design-rendszer-migrációja tehát MEGMARAD a diffben, csak a **route-juk**
  csúszik. Ez nem „F2 F1 nélkül": az 1–2. képernyő F1-e ebben a körben landol.

**Precedens (§4.9 visszakeresés):** [ADR 0078](../adr/0078-practice-feature-surface-and-routing.md)
ugyanezt a mintát rögzítette a Practice hubon — *„a Start ebben a körben nem
indít sessiont — a felület fél lépés, és ezt a UI-nak őszintén kell
kommunikálnia"*, a kockázat ellenszere pedig „acceptance-cella a csere
mérésére + a provider doc-commentje nevezze meg a kört". A `PlanSetupScreen`
varázsló-vége ma is ilyen fél lépés (§10, `plan_setup_screen.dart:96–99`):
`controller.next()`-et hív, nem generál. Ezt a kör **nem javítja meg és nem
hazudja el** — az A4′ cellája pontosan azt méri, hogy nincs hamis „generálás
elindult" visszajelzés. Lásd még [L583](../LESSONS.md#l583) (az `E15-R14`
kompozíciós gyökere két úton hazudott zölden) és
[L409](../LESSONS.md#l409) (route-élesítő brief hallgatólagos adat-feltevése).

**S11 brief-lint lelet (ADR 0171 §4) — javítva.** A
`test/accessibility/release_flow_text_scale_test.dart:86` `find.byType(PracticeHubScreen)`-nel
PINNELI a hub típusát, és a hubot **200%-os szövegskálán** járja végig, tehát a
belépési pont felvétele pirosra válthatja. A fájl felkerült az `allowed_paths`-ra
ÉS a `gate_tests`-re. A jogosultság PONTOSAN annyi, mint a §5.5-ben: az ÚJ
belépési pont miatt szükséges cella-kiegészítés — **cella törlése, `skip`-je
vagy gyengítése TILOS**, és a hub képernyő típusa nem cserélődik le.

### 0.0.A Pre-flight (indítás előtt KÖTELEZŐ)

1. **ADR-szám:** `tools/round-slots.py reserve-adr --round E15-R07` → a kapott számra írd át a brief fejlécét, a §5 ADR-hivatkozásait és a queue-sor `adr` oszlopát.
2. **Elérhetőség újramérése** (a kör KIINDULÓ bizonyítéka, a §7 parancsával): a 6 képernyő ma `unreachable`. Ha bármelyik időközben bekötődött, vedd ki az F1 scope-ból.
3. **Migráltság újramérése** (a §7 `grep design_system` parancsa): a megíráskor mind a 6 legacy volt. Ami migrálódott, az az F2 scope-ból kerül ki.
4. **Belépési pont helye:** a brief §5.2 a `practiceHub` (`/practice`) alá javasolja a flow-t. **Mérd meg** a mai shell-szerkezetet (`lib/app/routing/app_router.dart`, `adaptive_shell_routes.dart`), és ha a mérés más gazdát ad ki, a §5.2-t a MÉRÉSRE javítsd — az ADR a mért helyet rögzíti, nem a feltételezettet.
5. **Scope-fedezet:** ha a pre-flight mérése szerint az F1+F2 együtt nem fér egy körbe (az `E15-R06` precedense: a brief 8 képernyőt sorolt, a mérés hármat engedett), akkor **az F1 a kör**, és az F2 külön, ide hivatkozó körbe kerül — a §0.0.A-ban dokumentált mérésel. A fordítottja TILOS: F2 önmagában, F1 nélkül értelmetlen.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/app/routing/app_route.dart",
  "lib/app/routing/app_router.dart",
  "lib/app/config/feature_flags.dart",
  "lib/core/feature_flags/feature_flag_registry.dart",
  "lib/features/practice/presentation/screens/practice_hub_screen.dart",
  "lib/features/practice_generator/presentation/screens/today_plan_screen.dart",
  "lib/features/practice_generator/presentation/screens/weekly_plan_screen.dart",
  "lib/features/practice_generator/presentation/screens/plan_setup_screen.dart",
  "lib/features/practice_generator/presentation/screens/plan_preview_screen.dart",
  "lib/features/practice_generator/presentation/screens/plan_change_review_screen.dart",
  "lib/features/practice_generator/presentation/screens/plan_privacy_screen.dart",
  "test/app/config/feature_flags_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/features/practice/presentation/practice_a11y_audit_test.dart",
  "test/features/practice/presentation/practice_hub_screen_test.dart",
  "test/features/practice/presentation/practice_routing_test.dart",
  "test/accessibility/release_flow_text_scale_test.dart",
  "test/features/practice_generator/accessibility/planner_accessibility_test.dart",
  "test/features/practice_generator/presentation/plan_setup_screen_test.dart",
  "test/features/practice_generator/presentation/plan_preview_screen_test.dart",
  "test/features/practice_generator/presentation/today_plan_screen_test.dart",
  "docs/adr/0491-practice-generator-entry-point-and-rollout.md",
  "docs/ui/migration-status.md",
  "docs/ui/retirement-plan.md",
  "docs/rounds/e15-r07-practice-generator-migration.md",
]
gate_tests = [
  "test/tooling/screen_reachability_test.dart",
  "test/tooling/feature_flag_audit_test.dart",
  "test/tooling/route_literal_guard_test.dart",
  "test/app/config/feature_flags_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/features/practice/presentation/practice_a11y_audit_test.dart",
  "test/features/practice/presentation/practice_hub_screen_test.dart",
  "test/features/practice/presentation/practice_routing_test.dart",
  "test/ui/ui_inventory_test.dart",
  "test/accessibility/release_flow_text_scale_test.dart",
  "test/features/practice_generator/accessibility/planner_accessibility_test.dart",
  "test/features/practice_generator/presentation/plan_setup_screen_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a diff **új felhasználói utat nyit** egy eddig lezárt flow-hoz, és egy feature-flag rollout-határt mozdít el. A `security-reviewer` futtatása KÖTELEZŐ (a `plan_privacy_screen` consent-felület, és a bekötés adatgyűjtő utat tehet elérhetővé), a `flutter-reviewer` és a `flutter-devil-advocate` szintén.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a bekötéshez a `practice_generator` `application/`, `domain/` vagy `data/` rétegét kellene módosítani (pl. mert egy provider hiányzik a képernyő futásához), a kimenet `stopped` — a generátor-motor viselkedése NEM ennek a körnek a hatásköre ([ADR 0255](../adr/0255-deterministic-practice-plan-generation.md), [L478](../LESSONS.md#l478)). A képernyők a meglévő providereikből élnek; ha nem, az önálló kör.

## 1. Cél

A Practice Generator flow-ja **megnyithatóvá** válik egy mért belépési ponton a nem-production buildekben (production változatlanul zárt), és a 6 képernyője a design-rendszer komponenseit használja — hogy a felhasználó a megtervezett tervkészítő utat végig tudja járni, egységes felülettel, 200%-os szövegskálán és mindkét locale-on.

## 2. Jelenlegi állapot — mért tények

- **Flag:** `practiceGeneratorEnabled` létezik (`feature_flags.dart:22,84,169`), de `false` a default konstruktorban ÉS a `forEnvironment` gyárban. A `plannerAssistEnabled` ugyanígy.
- **Registry:** `feature_flag_registry.dart:144` — `risk: medium`, `failClosedDefault: false`, `adr: '0255'`, és a `killSwitchPath` a mai „forráskód-változás kell hozzá" állapotot írja le.
- **Pinnelő cellák:** `test/app/config/feature_flags_test.dart` HÁROM cellája rögzíti a `false`-t: default konstruktor (14), `production` (26), `development` (36).
- **Route:** `lib/app/routing/app_route.dart` egyetlen `plan*`/`generator*` útvonalat sem deklarál; `app_router.dart` egyetlen `practice_generator` képernyőt sem nevez meg.
- **Elérhetőség:** `docs/ui/retirement-plan.md:241–246` — mind a 6 képernyő `unreachable`, „no route and no measured construction site anywhere in lib/".
- **Migráltság:** a 6 képernyő egyike sem importálja a `core/design_system`-et.
- **Minta a flag-kapuzott route-ra:** `app_router.dart:561–573` (`if (visionEnabled && visionSetupEnabled) ...[ GoRoute(path: AppRoutes.visionSetup, …) ]`) — a bekötés EZT a bevett alakot követi.
- **Képernyő-leltár:** `test/ui/ui_inventory_test.dart:26` egzakt `hasLength(96)`. A kör **nem hoz létre és nem töröl** képernyőt, tehát ez a szám VÁLTOZATLAN — a bekötés route-ot ad, nem képernyőt.

## 3. Scope

### F1 — bekötés (a kör kötelező magja)

**Benne van:** route-konstansok a 6 képernyőhöz az `AppRoutes`-ban · a hozzájuk tartozó, `practiceGeneratorEnabled`-re kapuzott `GoRoute` regisztrációk `app_router.dart`-ban a §2 mért mintája szerint · EGY mért belépési pont, amiről a flow megnyitható (§5.2) · a flag `forEnvironment` határának átállítása a `nonProd` mintára (production továbbra is OFF) · a registry `killSwitchPath`/`adr` mezőjének igazítása az ÚJ igazsághoz · a három pinnelő cella átírása az ÚJ szerződésre (nem törlés, nem `skip`) · az ÚJ ADR.

### F2 — migráció

**Benne van:** a 6 képernyő vizuális migrálása a design-rendszer komponenseire (`SsContentCard`, `SsButton`, `SsEmptyState`, `SsFailureState`, `SsMetricCard` és társaik; `SsSpacing`/`SsTypography` tokenek) · a felesleges `*ThemeScope` burkoló eltávolítása (az `E15-R01` óta az app témája hordozza a tokeneket, ÚJ burkoló NEM vezethető be) · a `migration-status.md` és a `retirement-plan.md` érintett sorainak frissítése a MÉRT új értékekre.

> ⚠ **Komponens-nevek MÉRÉSBŐL:** az `E15-R05`/`E15-R06` kétszer mérte, hogy a briefekben szereplő `SsListTile`/`SsErrorState`/`SsMetricTile` **nem létezik** — a valódi nevek `SsContentCard`/`SsFailureState`/`SsMetricCard`. A pre-flight a `lib/core/design_system/public.dart`-ból ellenőrizze a használt neveket, mielőtt egy sort is ír.

Batch-specifikus kikötések:

- a `plan_change_review_screen` diff-nézete megtartja a MÉRT változás-kategóriákat; csak a megjelenítés kerül komponensekre
- a `plan_privacy_screen` szövegei és consent-kapcsolói VÁLTOZATLANOK (adatvédelmi felület) — a bekötés sem lazíthat a consent-úton
- az ADR 0306 határa érvényben marad: a preview-felület a core flow-t nem blokkolhatja

**NINCS benne (tilos):**

- a `practice_generator` `application/`, `domain/`, `data/`, `providers/` rétege (viselkedés-változás → STOP).
- `plannerAssistEnabled` bekapcsolása — külön rollout-döntés.
- Új képernyő létrehozása vagy meglévő törlése (a `ui_inventory` száma VÁLTOZATLAN).
- Új `*ThemeScope` burkoló bevezetése.
- ARB-kulcs törlése vagy szöveg-jelentés megváltoztatása (ÚJ kulcs felvehető, egyszerre `en` ÉS `hu`).
- `tools/**`, `.github/**`, `lib/core/design_system/**` (a komponenseket HASZNÁLJUK, nem módosítjuk).
- Minden más `lib/features/**` képernyő.

## 4. Engedélyezett fájlok

| Útvonal | Indok | Fázis |
|---|---|---|
| `lib/app/routing/app_route.dart` | a 6 route-konstans | F1 |
| `lib/app/routing/app_router.dart` | a flag-kapuzott `GoRoute` regisztrációk + belépési pont | F1 |
| `lib/app/config/feature_flags.dart` | a `forEnvironment` határ átállítása `nonProd`-ra | F1 |
| `lib/core/feature_flags/feature_flag_registry.dart` | `killSwitchPath` + `adr` az ÚJ igazságra | F1 |
| `test/app/config/feature_flags_test.dart` | a három pin átírása az ÚJ szerződésre | F1 |
| `test/app/routing/app_router_test.dart` | a route-ok és a flag-kapu cellái | F1 |
| `lib/features/practice/presentation/screens/practice_hub_screen.dart` | a flow EGY belépési pontja (§5.2) — flag-kapuzva | F1 |
| `test/app/navigation/{adaptive_scaffold,tab_state_restoration,legacy_route_redirect}_test.dart` | navigációs őrök — a jogosultság PONTOSAN §5.5 szerinti | F1 |
| `docs/adr/0491-practice-generator-entry-point-and-rollout.md` | az ÚJ döntés (a szám a pre-flightból) | F1 |
| a 6 `*_screen.dart` a `practice_generator/presentation/screens/`-ben | migráció design-rendszer komponensekre | F2 |
| `test/features/practice_generator/presentation/{plan_setup,plan_preview,today_plan}_screen_test.dart` | állapot- és variáns-cellák | F2 |
| `test/features/practice_generator/accessibility/planner_accessibility_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad | F2 |
| `docs/ui/migration-status.md`, `docs/ui/retirement-plan.md` | a MÉRT új arány és az elérhetőségi verdikt | F2 |

## 5. Kötött architekturális döntések (ADR 0491 — a §0.0.C pre-flight ÚJRAMÉRTE a számot)

### 5.1 A production zárva marad

A flag a `practiceEngineV2Enabled` mintáját veszi át: `nonProd` → ON, `production` → OFF. **NEM elfogadható gyengítés:** a flag globális `true`-ra állítása „hogy a teszt egyszerűbb legyen". A production-cella (`feature_flags_test.dart:26`) marad, és `isFalse`-t vár TOVÁBBRA IS.

### 5.2 EGY belépési pont, mérten

A flow-nak pontosan egy gazdája van (a pre-flight §0.0.A/4 méri meg; a javaslat a `practiceHub` = `/practice` felület). **NEM elfogadható gyengítés:** hat különálló, egymásra nem hivatkozó route bekötése belépési pont nélkül — az az elérhetőség-mérőt kielégítené, a felhasználót nem.

### 5.3 A route-literálok az `AppRoutes`-ból jönnek

Beégetett útvonal-string a routerben tilos (a `test/tooling/route_literal_guard_test.dart` gépi őre). **NEM elfogadható gyengítés:** az őr fellazítása a kör kedvéért.

### 5.4 A viselkedés bitre azonos marad (F2)

Ugyanaz az adat, sorrend, és ugyanazok az állapotok (üres, betöltés, hiba). **NEM elfogadható gyengítés:** „egyszerűsítettük a hibaállapotot" — az információvesztés.

### 5.5 A navigációs őrök jogosultsága PONTOSAN a belépési pont felvétele

A `test/app/navigation/` őrei (`adaptive_scaffold_test.dart`, `tab_state_restoration_test.dart`, `legacy_route_redirect_test.dart`) route-onként PINNELIK a renderelt képernyő típusát, ezért a shell egy destination-builderének átkötése pirosra váltja őket (MÉRVE: E13-R17 pre-flight, `flutter test test/app/navigation/` +33 → +30 -3 három destination átkötésével). Ez a kör **egyetlen meglévő destination buildert sem köt át** — ÚJ, flag-kapuzott route-okat vesz fel, és a `practice_hub_screen.dart`-ra EGY belépési pontot (§5.2). A jogosultság ezért PONTOSAN ennyi: az ÚJ belépési pont miatt szükséges cella-kiegészítés. Ugyanez áll a `practice_hub_screen.dart` TÍPUSÁT pinnelő négy őrre (`test/core/screen_size_guard_test.dart`, `test/features/practice/presentation/{practice_a11y_audit,practice_hub_screen,practice_routing}_test.dart`): a kör a hub képernyőt **nem cseréli le és nem alakítja át** — EGY belépési pont elemet vesz fel rá, flag-kapuzva —, tehát a jogosultság pontosan az ÚJ elem cellája. **Cella törlése, `skip`-je vagy gyengítése TILOS**, és a §10-ben szerepelnie kell a `flutter test test/app/navigation/` cellaszámának ELŐTTE és UTÁNA — a különbség csak az ÚJ cellák számával nőhet, csökkennie tilos.

### 5.6 A szöveg lokalizált marad

Beégetett felhasználói szöveg nem kerülhet a kódba; ÚJ szöveg egyszerre `en` ÉS `hu` ARB-kulcsot kap. **NEM elfogadható gyengítés:** angol placeholder „amíg lefordítjuk".

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték | Fázis |
|---|---|---|---|
| A1′ | **(§0.0.C-vel szűkítve)** A `PlanSetupScreen` ÉS a `TodayPlanScreen` verdiktje `unreachable`-ből **reachable**-be fordul a MÉRŐ ESZKÖZ kimenetében; a másik négy VÁLTOZATLANUL `unreachable`, és ezt a §10 kiírja | `dart run tool/check_screen_reachability.dart` előtte/utána (§7) | F1 |
| A1″ | A 3–6. képernyőhöz **NEM** kerül route-regisztráció, amíg a két seam (`exerciseCandidateResolverProvider`, `generationPlanInputBuilderProvider`) dob — a bekötött route-oknak a `ProviderScope`-ból ténylegesen fel kell épülniük | célzott cella: a két bekötött route megnyitása NEM dob `UnimplementedError`-t; a `git diff` nem tartalmaz `GoRoute`-ot a 3–6. képernyőre | F1 |
| A2 | A route-ok a `practiceGeneratorEnabled` kapuja MÖGÖTT vannak: a flag OFF-ra állítva a bekötött route-ok (A1′) NEM regisztrálódnak | `app_router_test.dart` flag-be/ki cellapár | F1 |
| A3 | A flag `nonProd`-on ON, `production`-ön OFF; a default konstruktor OFF marad | `feature_flags_test.dart` három átírt cellája | F1 |
| A4 | A belépési pontról a flow ténylegesen megnyitható (nem csak a route létezik) | célzott widget-teszt: a belépési pont megnyomása a `PlanSetupScreen`-re navigál | F1 |
| A4′ | **A fél lépés ŐSZINTE** (ADR 0078 precedens, §0.0.C): a Setup-varázsló vége ma NEM generál (`plan_setup_screen.dart:96–99`), és a kör ezen nem változtat — a UI tehát nem adhat „a terv elkészült/generálás elindult" visszajelzést, és a belépési pont felirata sem ígérhet kész tervet | célzott cella: a varázsló utolsó lépése után NINCS olyan látható szöveg/állapot, ami elkészült generálást állít; a `git diff` nem vezet be no-op `onComplete` callbacket | F1 |
| A5 | A `feature_flag_registry` `killSwitchPath`-ja az ÚJ igazságot írja le (nem a „hardcoded false"-t) | `feature_flag_audit_test.dart` + `git diff` | F1 |
| A6 | A `ui_inventory_test.dart` egzakt `hasLength(96)` VÁLTOZATLAN | a §7 gate | F1 |
| A7 | Mind a 6 képernyő importálja a `core/design_system`-et, és a mérés szerint migráltnak számít | a §7 mérő-parancs kimenete a §10-ben | F2 |
| A8 | Minden migrált képernyő üres/betöltés/hiba állapota design-rendszer-komponens | a batch célzott widget-tesztjei | F2 |
| A9 | A képernyők `textScaler 2.0` mellett, `en` ÉS `hu` locale-on túlcsordulás nélkül renderelnek **telefon-viewporton** | a küszöb-cellahármas (§6.2) | F2 |
| A10 | A típus-pinnelő tesztek VÁLTOZATLANUL zöldek, egyetlen cellájuk sem törölt/`skip`-elt | `git diff` a teszt-fájlokon + a §7 gate | F2 |
| A11 | Nincs beégetett felhasználói szöveg | `test/l10n/hardcoded_string_guard_test.dart` | F1+F2 |
| A12 | A `migration-status.md` és a `retirement-plan.md` a MÉRT új értékeket írja | a dokumentumok + a mérés parancsa | F2 |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A route bekötve, de a flag-kapu lemaradt (production is megnyitná) | A2 + A3 |
| A flag globálisan `true`-ra állítva | A3 (production-cella) |
| Hat route bekötve, de egyikre sem mutat semmi a felületen | A4 |
| A registry `killSwitchPath`-ja a régi „hardcoded false" szöveget hagyja | A5 |
| A képernyő megkapja a komponenseket, de a hibaállapot nyers `Text` marad | A8 |
| A migráció csak `en` locale-on lett kipróbálva, a hosszabb `hu` szöveg túlcsordul | A9 |
| Egy pinnelő cella `skip`-re kerül a zöldért | A10 |
| A képernyő importálja a design-rendszert, de a stílus továbbra is `AppColors`-ból jön | A7 |

**Valódi-sértés próbák (KÖTELEZŐ, a §10-ben dokumentálva):**
1. Vedd ki a flag-feltételt EGY route regisztrációjából → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.
2. Cserélj vissza EGY migrált képernyőn egy `SsFailureState`-et nyers `Text`-re → az **A8** cellának PIROSNAK kell lennie → állítsd vissza.

### 6.2 A szövegskála-cellák MÉRT szerződése (E15-R06 lecke, [L558](../LESSONS.md#l558)/[L559](../LESSONS.md#l559))

A `flutter_test` alapértelmezett viewportja **800×600** — szélesebb ÉS magasabb minden telefonnál, ezért a rajta mért „nincs túlcsordulás" **semmit nem bizonyít**. Az A9 cellái KÖTELEZŐEN:

- kipinnelt `tester.view.physicalSize = Size(360, 640)` + `devicePixelRatio = 1.0`, `addTearDown(tester.view.reset)`-tel;
- küszöb-cellahármas: a küszöb **alatt** (`1.5`) → nincs túlcsordulás; **pontosan rajta** (`2.0`) → nincs túlcsordulás, EZ az A9 feltétele; a küszöb **fölött** (`2.5`) → nem követelmény, és a `2.0` teljesítése nem hivatkozhat rá;
- `en` ÉS `hu` locale mindegyiken;
- lusta `ListView` esetén `scrollUntilVisible(...)` a mérendő widgetre **a `takeException()` ELŐTT** — különben a cella ÜRES fát mér, és a zöld mérési artefaktum.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/screen_reachability_test.dart test/tooling/feature_flag_audit_test.dart test/tooling/route_literal_guard_test.dart test/app/config/feature_flags_test.dart test/app/routing/app_router_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/tab_state_restoration_test.dart test/app/navigation/legacy_route_redirect_test.dart test/core/screen_size_guard_test.dart test/features/practice/presentation/practice_a11y_audit_test.dart test/features/practice/presentation/practice_hub_screen_test.dart test/features/practice/presentation/practice_routing_test.dart test/ui/ui_inventory_test.dart test/accessibility/release_flow_text_scale_test.dart test/features/practice_generator/accessibility/planner_accessibility_test.dart test/features/practice_generator/presentation/plan_setup_screen_test.dart
```

Az elérhetőség-mérés (a kimenet a §10-be, ELŐTTE és UTÁNA):

```bash
dart run tool/check_screen_reachability.dart | grep -i practice_generator
```

A migráltság-mérés (a kimenet a §10-be, MIGRATED/legacy sorokkal):

```bash
for f in lib/features/practice_generator/presentation/screens/today_plan_screen.dart lib/features/practice_generator/presentation/screens/weekly_plan_screen.dart lib/features/practice_generator/presentation/screens/plan_setup_screen.dart lib/features/practice_generator/presentation/screens/plan_preview_screen.dart lib/features/practice_generator/presentation/screens/plan_change_review_screen.dart lib/features/practice_generator/presentation/screens/plan_privacy_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
```

Ha a batch képernyőjének VAN golden PNG-je, az újrafelvétel KIZÁRÓLAG a merge-kapu architektúráján ([ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md)):

```bash
tools/golden-x86.sh record <a batch érintett golden-teszt fájljai>
```

## 8. Implementációs sorrend

1. **Pre-flight** (§0.0.A): ADR-szám, elérhetőség- és migráltság-mérés, a belépési pont gazdájának megmérése, komponens-nevek ellenőrzése a `design_system/public.dart`-ból.
2. **F1/a:** route-konstansok → flag-kapuzott `GoRoute` regisztrációk → belépési pont.
3. **F1/b:** a flag `nonProd` határa + registry `killSwitchPath`/`adr` → a három pin átírása → `app_router_test` flag-be/ki cellapár + a belépési pont cellája.
4. **F1/c:** ADR megírása, elérhetőség-mérés ÚJRA (A1 bizonyíték), valódi-sértés próba 1.
5. **F2:** képernyőnként komponens-csere → állapotok → tokenek → `*ThemeScope` eltávolítás; cellák a 360×640 viewporton (§6.2); valódi-sértés próba 2.
6. `migration-status.md` + `retirement-plan.md` frissítése a MÉRT értékekre.

## 9. Kockázatok

- **Néma bekötés.** A route létezik, de semmi nem navigál rá — a mérő eszköz zöld, a felhasználó nem jut oda (A4 fogja).
- **Kapu-szivárgás production-be.** Egy elfelejtett flag-feltétel élesben nyit meg egy nem kész flow-t (A2+A3 fogja; a `security-reviewer` kötelező).
- **Rossz viewport.** A 800×600-as alapértelmezésen mért zöld szövegskála-cella mérési artefaktum (§6.2, L558/L559).
- **Scope-csúszás a viselkedés felé.** Ha a képernyő futásához provider-módosítás kellene, az STOP-eset, nem „apró kiegészítés".
- **Kétfázisú túlvállalás.** Ha az F1+F2 nem fér egy körbe, az F1 a kör — a §0.0.A/5 szerint, MÉRÉSSEL dokumentálva.

## 10. Implementation handoff — az implementer tölti ki

**STATUS: DONE.** Ez a bejegyzés a §0.0.C revízió (2026-09-02, `main @
70eefdf4`) után újraindult kör tényleges eredménye — a korábbi, `E15-R14`
előfeltétel hiánya miatti STOPPED állapotot (lásd a lenti historikus
bejegyzésben, megőrizve bizonyítékként) ez váltja fel. Az `E15-R14` (ADR
0482, PR #534) azóta merge-elve; a kompozíciós gyökér két seamje
(`exerciseCandidateResolverProvider`, `generationPlanInputBuilderProvider`)
viszont a §0.0.C mérése szerint továbbra is dob, ezért az F1 a MÉRTEN
konstruálható részhalmazra (2/6 képernyő) szűkült — pontosan az ADR 0491
D1 szerint.

### F2 (változatlanul kész, `30bc31fd` commit)

Migráltság-mérés (`grep -q design_system`) mind a 6 képernyőn `MIGRATED`-et ad
— újramérve ennek a körnek a végén is, változatlan: `today_plan_screen.dart`,
`weekly_plan_screen.dart`, `plan_setup_screen.dart`, `plan_preview_screen.dart`,
`plan_change_review_screen.dart`, `plan_privacy_screen.dart`.

### F1 — a MÉRTEN konstruálható 2 képernyő bekötve

**Elérhetőség-mérés — ELŐTTE (cache: `/tmp/reach-before-e15-r07.txt`):**

```
plan_setup_screen.dart  | PlanSetupScreen  | unreachable | 3 teszt
today_plan_screen.dart  | TodayPlanScreen  | unreachable | 18 teszt
(a másik 4 képernyő szintén unreachable, változatlan)
```

**Elérhetőség-mérés — UTÁNA (cache: `/tmp/reach-after-e15-r07.txt`):**

```
plan_setup_screen.dart | PlanSetupScreen | lib/app/routing/app_router.dart:377 | practiceGeneratorEnabled | 7 teszt
today_plan_screen.dart | TodayPlanScreen | lib/app/routing/app_router.dart:385 | practiceGeneratorEnabled | 20 teszt
(a másik 4 képernyő VÁLTOZATLANUL unreachable — 0 route-regisztráció rájuk, a diffben sincs GoRoute a 3-6. képernyőre)
```

`Measured screens: 96. Reachable: 68 -> 70. Unreachable: 28 -> 26. Flag-gated:
25 -> 27.` (a `dart run tool/check_screen_reachability.dart` fejléce). A `git
diff` a routerben KIZÁRÓLAG a `PlanSetupScreen`/`TodayPlanScreen` két
`GoRoute`-ját veszi fel — A1" teljesül.

**Megjegyzés (mérési csapda, elkerülve):** az első próbálkozásban a
`practiceGeneratorEnabled` melletti doc-comment szó szerint tartalmazta a
`PlanSetupScreen` / `TodayPlanScreen` class-neveket — a reachability-tool
(`tool/check_screen_reachability.dart` D3) ezt egy guard NÉLKÜLI deklaratív
referenciának mérte, ami hamisan `isFlagGated = false`-ra váltotta mindkét
verdiktet (`Flag-gated: 25` maradt volna). A comment átírása (a class-nevek
kivétele belőle) után a mérés `Flag-gated: 27`-re javult — ez a MÉRT ok,
amiért a router kommentje explicit módon kerüli a két class-nevet.

### Implementációs elemek (§2 szerint)

1. **Route-konstansok** (`app_route.dart`): `practiceGeneratorSetup =
   '/practice/generator/setup'`, `practiceGeneratorToday =
   '/practice/generator/today'` — nem ütköznek a meglévő `practiceSetup`
   (`/practice/setup`, a Practice V2 katalógus útvonala) vagy `today`
   (`/today`, az adaptív shell Today Hubja) útvonalakkal.
2. **Flag-kapuzott `GoRoute`-ok** (`app_router.dart`): a `practiceEnabled`
   blokktól FÜGGETLEN `if (practiceGeneratorEnabled) [...]` — a §2 mért
   mintáját (`visionEnabled && visionSetupEnabled`) követi. Mindkét
   képernyő a kompozíciós gyökér valódi providereiből épül fel
   (`planSetupControllerProvider`, `todayPlanControllerProvider`), egy
   `Consumer` builderen át (a fájl más flag-kapuzott route-jainak, pl. a
   gamification hub routejának, mintáját követve).
3. **EGY belépési pont** (`practice_hub_screen.dart`): egy új, flag-kapuzott
   `_PlanBuilderCard`, ami a meglévő `_HubCard`-mintát használja, és
   `context.go(AppRoutes.practiceGeneratorSetup)`-ra navigál. A cím/alcím
   **meglévő** ARB-kulcsokat (`planSetupTitle` = "Build your practice plan" /
   hu "Gyakorlási terv összeállítása", `planSetupGoalTitle`) használ fel újra
   — ÚJ ARB-kulcs NEM került fel, mert az `app_en.arb`/`app_hu.arb` NINCS a
   kör engedélyezett fájllistáján (az implementer-őr ezt tényleg blokkolta,
   mérve: az első próbálkozás `PreToolUse:Edit` hook-hibával elutasítva).
4. **Flag rollout-határ** (`feature_flags.dart`): `practiceGeneratorEnabled:
   nonProd` a `forEnvironment` gyárban — a `practiceEngineV2Enabled`
   mintája. A default konstruktor OFF marad.
5. **Registry igazítása** (`feature_flag_registry.dart`): a
   `killSwitchPath` most a `nonProd` kaput írja le (az `adaptiveShellEnabled`
   bejegyzés mintája), az `adr` mező `0491`-re állítva.
6. **A három pinnelő cella** (`feature_flags_test.dart`): a default- és a
   production-cella VÁLTOZATLAN marad (mindkettő továbbra is `false`-t vár —
   ez az ÚJ szerződés alatt is igaz állítás); a fejlesztői/nonProd cella
   átírva `practiceGeneratorEnabled: isTrue, plannerAssistEnabled: isFalse`-ra.

### A4' — az őszinte fél lépés

`plan_setup_screen.dart:96-99` VÁLTOZATLAN — az 5. lépés gombja kizárólag
`controller.next()`-et hívja. Egy ÚJ célzott cella
(`plan_setup_screen_test.dart`, "A4': the last step never claims a plan was
generated or is ready") a step-4-en (a valódi utolsó lépésen) megméri, hogy
a Finish-gomb felirata "Finish setup" (nem "kész terv"), és hogy sem a
gomb megnyomása előtt, sem utána nincs "ready"/"generated" szöveg a fában.
A hub belépési pont felirata is a meglévő `planSetupTitle` ARB-kulcs
("Build your practice plan" / hu "Gyakorlási terv összeállítása") —
egyik sem ígér kész tervet.

### Valódi-sértés próbák (KÖTELEZŐ)

1. **A2 (flag-kapu).** A `practiceGeneratorSetup` `GoRoute`-ról ideiglenesen
   levéve az `if (practiceGeneratorEnabled)` feltétel ->
   `flutter test test/app/routing/app_router_test.dart --plain-name
   "Practice Generator routes are NOT registered"` **PIROSRA váltott**
   (`Expected: /live, Actual: /practice/generator/setup`) -> a feltétel
   visszaállítva, a teljes `app_router_test.dart` újra zöld (25/25).
2. **Elérhetőség (A1'/A1").** Lásd fent - a mérőeszköz kimenete tényleg
   `unreachable`-ből `reachable`-be váltott a két bekötött képernyőre, a
   másik 4-re nem.

### `test/app/navigation/` cellaszám ELŐTTE és UTÁNA (§5.5)

A kör **egyik `test/app/navigation/` fájlt sem módosította** — az ÚJ
belépési pont és az ÚJ route-ok az adaptív shell destination-buildereitől
függetlenek (a `PlanSetupScreen`/`TodayPlanScreen` nem shell-branch tag,
külön top-level `GoRoute`, ahogy a meglévő `/practice/setup` is). Mérve:

```
flutter test test/app/navigation/
ELŐTTE:  34/34 zöld
UTÁNA:   34/34 zöld — azonos szám, a fájlok byte-azonosak a HEAD-hez képest
```

A különbség 0 — ami a §5.5 "csak nőhet, nem csökkenhet" szabályát
trivilálisan teljesíti (a jogosultságot a kör nem használta fel, mert nem
volt rá szükség). A hub-típust pinnelő NÉGY őr (`screen_size_guard_test.dart`,
`practice_a11y_audit_test.dart`, `practice_hub_screen_test.dart`,
`practice_routing_test.dart`) viszont TÉNYLEGESEN kapott új cellákat az ÚJ
belépési pont elemre (jelenlét/hiány a flag mentén, és egy valódi
navigáció-teszt, ami megnyitja a `PlanSetupScreen`-t a hubról).

### Migráltság-mérés (UTÁNA, változatlan az F2-höz képest)

```
MIGRATED lib/features/practice_generator/presentation/screens/today_plan_screen.dart
MIGRATED lib/features/practice_generator/presentation/screens/weekly_plan_screen.dart
MIGRATED lib/features/practice_generator/presentation/screens/plan_setup_screen.dart
MIGRATED lib/features/practice_generator/presentation/screens/plan_preview_screen.dart
MIGRATED lib/features/practice_generator/presentation/screens/plan_change_review_screen.dart
MIGRATED lib/features/practice_generator/presentation/screens/plan_privacy_screen.dart
```

### Dokumentum-frissítés (A12)

`docs/ui/retirement-plan.md`: a §6 táblázat két sora (`PlanSetupScreen`,
`TodayPlanScreen`) `unreachable` -> `keep` (reachable, flag-gated,
migrated); a §2 összegző számok frissítve (`Reachable 68->70`, `Unreachable
28->26`, `Flag-gated 25->27`, `keep 27->29`); a §3.2 szöveg felülírva a
2/6 vs. 4/6 MÉRT állapotra. `docs/ui/migration-status.md`: új, tetejére
kerülő bekezdés dokumentálja az F1 landolást, és a §-végi
"practice_generator reached 6/6" mondat kiegészítve a reachability
állapottal.

### Gate (csonkítatlan, `tools/round-gate.sh`)

```
format                                                     zöld
analyze                                                    zöld
test test/tooling/screen_reachability_test.dart            zöld
test test/tooling/feature_flag_audit_test.dart             zöld
test test/tooling/route_literal_guard_test.dart            zöld
test test/app/config/feature_flags_test.dart               zöld
test test/app/routing/app_router_test.dart                 zöld
test test/app/navigation/adaptive_scaffold_test.dart       zöld
test test/app/navigation/tab_state_restoration_test.dart   zöld
test test/app/navigation/legacy_route_redirect_test.dart   zöld
test test/core/screen_size_guard_test.dart                 zöld
test test/features/practice/presentation/practice_a11y_audit_test.dart zöld
test test/features/practice/presentation/practice_hub_screen_test.dart zöld
test test/features/practice/presentation/practice_routing_test.dart zöld
test test/ui/ui_inventory_test.dart                        zöld
test test/accessibility/release_flow_text_scale_test.dart  zöld
test test/features/practice_generator/accessibility/planner_accessibility_test.dart zöld
test test/features/practice_generator/presentation/plan_setup_screen_test.dart zöld
architecture                                               zöld
secrets                                                    zöld
l10n                                                       zöld
```

MINDEN GATE ZÖLD.

### Amit ez a kör NEM csinált (STOP-protokoll érintetlen)

A 3-6. képernyő (`PlanPreviewScreen`, `PlanPrivacyScreen`, `WeeklyPlanScreen`,
`PlanChangeReviewScreen`) NEM kapott route-ot — a providereik ma is
`UnimplementedError`-t dobnak a két seamen át. A `practice_generator`
`application/`, `domain/`, `data/`, `presentation/providers/` rétege
ÉRINTETLEN. A `plannerAssistEnabled` NEM kapcsolt be.

---

<details>
<summary>Történeti bejegyzés - a kör ELSŐ futása (2026-09-01, STOPPED az
`E15-R14` előfeltétel hiánya miatt, azóta feloldva)</summary>

**STATUS: STOPPED (F1 nem indult el production-kódban) — a STOP-protokoll (§0, §3) mérten indokolt.**

Migráltság-mérés (`grep -q design_system`) mind a 6 képernyőn `MIGRATED`-et ad:
`today_plan_screen.dart`, `weekly_plan_screen.dart`, `plan_setup_screen.dart`,
`plan_preview_screen.dart`, `plan_change_review_screen.dart`,
`plan_privacy_screen.dart` — mindegyik importálja a `core/design_system/public.dart`-ot
és design-rendszer komponenseket (`SsButton`, `SsSpacing`, `SsColorScheme`,
`SsTypography`, `SsSkeleton`, ...) használ. Ez a mérés az F1 kezdete ELŐTT
készült, mert a briefet a kör közben írták újra (§0.0).

`dart run tool/check_screen_reachability.dart | grep -i practice_generator`
(cache: `/tmp/reach-before-e15-r07.txt`) — mind a 6 képernyő `unreachable`:
0 deklaratív és 0 imperatív referencia a routerben/`lib/`-ben.
`grep -rln "Provider<\|NotifierProvider\|ChangeNotifierProvider" lib/features/practice_generator`
-> **ÜRES** — a `practice_generator` alatt **nulla** Riverpod-provider létezik
bárhol. A brief §3 STOP-mondata ("a képernyők a meglévő providereikből élnek")
ezért literálisan nem teljesíthető feltétel volt — nincs "meglévő provider",
amiből élniük lehetne. Ezt a hiányt az `E15-R14` (ADR 0482) oldotta fel egy
kompozíciós gyökérrel; a §0.0.C pre-flight ezt újramérte, és a fennmaradó két
dobó seam miatt az F1-et a 2/6-os részhalmazra szűkítette (lásd fent).

Nem történt production-kód módosítás ebben a futásban; a repó a kör
indulásakor mért, tiszta állapotában maradt.

</details>

## 11. Review — a Claude tölti ki
