# ADR 0491 — A Practice Generator belépési pontja és rollout-határa: a bekötés a MÉRT kompozícióig megy, tovább nem

- **Státusz:** elfogadva
- **Dátum:** 2026-09-02
- **Kör:** `E15-R07` (Chapter 15, Kör 7 — F1 bekötés; az F2 migráció ugyanezen az ágon már kész)
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Kapcsolódó:**
  [`0255`](0255-deterministic-practice-plan-generation.md) (a determinisztikus
  generátor szerződése — ez a kör NEM nyúl hozzá),
  [`0482`](0482-practice-generator-composition-layer.md) (a kompozíciós gyökér,
  `E15-R14` — ez a kör annak a FOGYASZTÓJA),
  [`0078`](0078-practice-feature-surface-and-routing.md) (a Practice belépési
  felülete: flag mögötti routing és az ŐSZINTE fél lépés precedense),
  [`0197`](0197-song-trainer-shipping-rollout-boundary.md) (a rollout-határ
  áthelyezése; a belépési pont a rollout RÉSZE, nem utólagos ráadás),
  [`0471`](0471-screen-reachability-is-measured-not-assumed.md) (az elérhetőség
  MÉRT tulajdonság),
  [`0306`](0306-plan-preview-presentation-activation-boundary.md) (a preview
  aktiválási határa)

## Kontextus — a pre-flight MÉRT tényei (2026-09-02, `main @ 70eefdf4`)

A user döntése (2026-09-01) az volt, hogy a Practice Generator flow-ját **be
kell kötni**, nem nyugdíjazni. A flow 6 képernyője a `docs/ui/retirement-plan.md`
szerint „built, unwired": megvan, de nincs route és nincs építési hely.

Az `E15-R07` első futása `stopped` jelzéssel állt meg (H3, 2026-09-01), mert a
feature alatt **nulla** Riverpod-provider volt. Az önjavító kör ezt egy beszúrt
előkészítő körrel oldotta fel: az `E15-R14` (ADR 0482) leszállította a
kompozíciós gyökeret és a perzisztens `PracticeEvidenceRepository`-t, és a saját
ADR-je ki is mondja, hogy a navigációba kötés „`E15-R07 / F1`'s job".

**A jelen kör pre-flightja viszont mért egy olyan tényt, amit az önjavító kör
előrevetítése nem tartalmazott.** Az `E15-R14` kompozíciós gyökere két
függőséget SZÁNDÉKOSAN nyitva hagyott, „overridable production seam" néven —
és ezek a mai `lib/`-ben dobnak:

| Seam | Hely | Mai viselkedés |
|---|---|---|
| `exerciseCandidateResolverProvider` | `practice_generator_providers.dart:85` | `throw UnimplementedError(...)` |
| `generationPlanInputBuilderProvider` | `practice_generator_providers.dart:149` | `throw UnimplementedError(...)` |

`grep -rn "ExerciseCandidateResolver" lib/` és `grep -rn "GenerationPlanInputBuilder" lib/`:
mindkettő KIZÁRÓLAG `typedef` + a dobó provider — **konkrét implementáció nulla
a `lib/` egészében**, és `lib/main.dart:90` `overrides:` listája egyiket sem
írja felül.

Mivel a `localPracticePlanRepositoryProvider` (`:95`) `ref.watch(exerciseCandidateResolverProvider)`-t
hív, a dobás **tranzitívan** terjed. Képernyőnkénti mérés:

| # | Képernyő | Verdikt |
|---|---|---|
| 1 | `PlanSetupScreen` | ✅ konstruálható (draft + clock + id + locale) |
| 2 | `TodayPlanScreen` | ✅ konstruálható (clock) |
| 3 | `PlanPreviewScreen` | ❌ `localPracticePlanRepositoryProvider` → dob |
| 4 | `PlanPrivacyScreen` | ❌ `delete`/`export` use case → dob |
| 5 | `WeeklyPlanScreen` | ❌ `activePracticePlanProvider` → dob |
| 6 | `PlanChangeReviewScreen` | ❌ a kötelező `PlanRevisionProposal` aktív tervet igényel |

A 3–6. feloldása egy `ExerciseCandidateResolver` (és a generáláshoz egy
`GenerationPlanInputBuilder`) MEGÍRÁSA a `data/`+`application/` rétegben —
pontosan az, amit a kör briefjének §0/§3 STOP-mondata tilt, és amit a merge-elt
`tools/tests/test_e15_r07_composition_prerequisite.py` őre véd.

## Döntés

### D1 — A bekötés a MÉRTEN konstruálható részhalmazig megy

Ez a kör a `PlanSetupScreen`-t és a `TodayPlanScreen`-t köti be:
route-konstans az `AppRoutes`-ban, `practiceGeneratorEnabled`-re kapuzott
`GoRoute` a routerben, és EGY belépési pont a practice hubon.

A 3–6. képernyő **route-ot NEM kap**. Egy route, amelynek a providere
`UnimplementedError`-t dob, nem „majdnem kész bekötés", hanem egy kattintható
út a crashbe — a CLAUDE.md silent-no-op tilalmának hangosabb változata. Az
elérhetőség-mérő zöldülne tőle, a felhasználó viszont hibaképernyőt kapna.

### D2 — A rollout-határ `nonProd`, a production zárva marad

A `practiceGeneratorEnabled` a `practiceEngineV2Enabled` mintáját veszi át:
`forEnvironment` → `nonProd` ON, `production` OFF. A default konstruktor OFF
marad. A flag globális `true`-ra állítása („hogy a teszt egyszerűbb legyen")
nem elfogadható gyengítés; a production-cella továbbra is `isFalse`-t vár.

A `plannerAssistEnabled` **nem** kapcsol be — az önálló rollout-döntés.

### D3 — A fél lépés ŐSZINTE (az ADR 0078 precedense)

A Setup-varázsló utolsó lépése ma nem indít generálást
(`plan_setup_screen.dart:96–99`: kizárólag `controller.next()`), és ez a kör
ezen **nem változtat** — a `startPlanGenerationProvider` a D-kontextusban leírt
`generationPlanInputBuilderProvider`-en át dobna.

Ezt a UI-nak őszintén kell kommunikálnia: **tilos** olyan visszajelzés
(„a terved elkészült", „generálás elindult") vagy olyan belépési pont-felirat,
ami kész tervet ígér, és **tilos** no-op `onComplete` callbacket bevezetni,
hogy a varázsló „késznek" tűnjön. Ez az ADR 0078 mért kockázatának
(„ha a Kör 13 elfelejti kicserélni, a Start csendben csak naplóz") az
ellenszere, ugyanabban az alakban: acceptance-cella méri, nem jószándék.

### D4 — A STOP-mondat érintetlen marad

A kör nem nyúl a `practice_generator` `application/`, `domain/`, `data/`,
`presentation/providers/` rétegéhez, és nem veszi az `allowed_paths`-ára az
`E15-R14` két kulcsfájlját. A szűkítés a scope-on történik, nem a mércén.

### D5 — A hiányzó seam bekötése önálló kör

A 3–6. képernyő route-ja azé a körré, amelyik előbb megírja a két seam
konkrét implementációját (katalógus-alapú `ExerciseCandidateResolver`, majd a
`GenerationPlanInputBuilder`), és bekötötte őket a `main.dart` boot-override
listájába. Amíg ez nincs meg, a négy képernyő `unreachable` marad — MÉRTEN, nem
feledékenységből.

## Következmények

**Jó:** a flow először megnyitható; a rollout-határ a mért `nonProd` mintára
kerül; a registry `killSwitchPath`-ja igazat mond; a bekötött két route
ténylegesen felépül a `ProviderScope`-ból; a maradék négy képernyő hiánya
NEVESÍTETT okkal és nevesített következő lépéssel áll.

**Ár:** a flow ebben a körben fél lépés — a felhasználó eljut a
terv-varázslóig és a „ma" nézetig, de tervet még nem generál. A 6-ból 4
képernyő továbbra is `unreachable`, tehát az `E15-R03` visszavonási terve
ezekre nyitva marad.

**Kockázat:** ha egy későbbi kör bekötné a két seamet, de elfelejtené a 3–6.
route-ot, a flow tartósan fél lépésben ragadna. Ellenszer: ez az ADR (D5) és a
`docs/ui/retirement-plan.md` frissített sorai nevezik meg a maradék munkát, a
`check_screen_reachability` mérése pedig körönként kimutatja.
