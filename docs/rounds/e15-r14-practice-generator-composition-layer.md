# E15-R14 — Practice Generator kompozíciós réteg (a bekötés előfeltétele)

- **Státusz:** PREPARED (az `E15-R07 / H3` önjavító kör írta, ADR 0112, 2026-09-01; kód olvasva: `main @ 1544e6bd`)
- **Típus:** Chapter 15 (UI-aktiválás és -befejezés), beszúrt előkészítő kör
- **Kör-azonosító:** `E15-R14`
- **Branch:** `<motor>/e15-r14-practice-generator-composition-layer`
- **Előfeltétel:** `E15-R03` merge-elve (a visszavonási terv mérte meg, hogy a flow bekötetlen)
- **Brief szerzője:** Claude (Opus 5), az `E15-R07 / H3` HALT mért leletéből
- **Előre kiosztott ADR:** `0482` — a szám ATOMIAN LEFOGLALVA (`tools/round-slots.py reserve-adr --round E15-R14` → `0482`, 2026-09-01). A pre-flight ELLENŐRIZZE, hogy a `docs/adr/0482-*.md` még nem létezik; ha közben elkelt, kérjen újat és írja át a briefet.

**Visszakeresett előzmény:** [ADR 0471](../adr/0471-screen-reachability-is-measured-not-assumed.md) (az elérhetőség MÉRT tulajdonság), [ADR 0255](../adr/0255-deterministic-practice-plan-generation.md) (a generátor szerződése), [ADR 0479](../adr/0479-privacy-data-inventory-and-consent-enforcement.md) (adat-leltár + consent enforcement — az ÚJ perzisztens tár ide is bekerül), [ADR 0306](../adr/0306-plan-preview-presentation-activation-boundary.md) (a preview aktiválási határa).

## 0.0 MIÉRT létezik ez a kör — az `E15-R07 / H3` HALT mért lelete

Az `E15-R07` (Practice Generator bekötése + migrálása) `stopped` jelzéssel állt
meg 2026-09-01-én. A STOP mérten indokolt volt, és a mérést az önjavító kör
FÜGGETLENÜL reprodukálta (`main @ 1544e6bd`):

| Mérés | Parancs | Eredmény |
|---|---|---|
| Riverpod-providerek a feature alatt | `grep -rln "Provider<\|NotifierProvider\|ChangeNotifierProvider" lib/features/practice_generator` | **ÜRES** — nulla provider |
| A `PracticeEvidenceRepository` konkrét implementációi | `grep -rn "implements PracticeEvidenceRepository" lib/` | **EGY** találat, és az a `domain/repository/practice_evidence_repository.dart:107` `InMemoryPracticeEvidenceRepository` **teszt-fake** (a doc-commentje szerint „never forgets") |
| A Setup-varázsló vége | `plan_setup_screen.dart:96–99` | a step-4 „Befejezés" gomb KIZÁRÓLAG `controller.next()`-et hív — nem indít generálást, nem navigál, nincs `onComplete` |

Ebből következik, hogy az `E15-R07` F1 fázisa (route + flag + belépési pont)
**nem route-méretű feladat**: a `PlanPrivacyScreen` `deleteUseCase`/`exportUseCase`-e
`PracticeEvidenceRepository`-t kér, a `PlanPreviewScreen` egy KÉSZ
`AdaptivePracticePlan`-t és egy `GenerationPlanActivation`-t, a
`PlanChangeReviewScreen` egy `PlanRevisionProposal`-t — és egyik sem áll elő a mai
kompozícióból. Az `E15-R07` saját STOP-mondata (§0, §3) pedig kimondja: *„a
képernyők a meglévő providereikből élnek; ha nem, az önálló kör."*

**Ez az az önálló kör.** A hiány NEM a motorban van — a `GenerationOrchestrator`
(`application/service/generation_orchestrator.dart:62`), a `PlanGeneratorController`,
a `RevisePracticePlan` (`PlanRevisionProposal`-t termel) és a
`LocalPracticePlanRepository` (ami `implements GenerationPlanActivation`, `:139`)
MIND KÉSZEN VAN. Ami hiányzik, az **egyetlen dolog: az összeszerelés** (plusz egy
darab valódi repository-implementáció).

> **A kör határa: KOMPOZÍCIÓ, nem felület és nem motor.** Ez a kör route-ot NEM
> nyit, feature-flaget NEM kapcsol, képernyőt NEM hoz létre és NEM módosít, és a
> generátor viselkedésén NEM változtat. A 6 terv-képernyő a kör UTÁN is
> `unreachable` marad — a bekötés az `E15-R07 / F1` dolga, ami erre a körre épül.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice_generator/data/local/local_practice_evidence_repository.dart",
  "lib/features/practice_generator/presentation/providers/practice_generator_providers.dart",
  "lib/features/practice_generator/application/usecase/start_plan_generation.dart",
  "lib/features/practice_generator/public/data.dart",
  "lib/features/practice_generator/public/application.dart",
  "lib/features/practice_generator/public/presentation.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/data/local_practice_evidence_repository_test.dart",
  "test/features/practice_generator/presentation/practice_generator_providers_test.dart",
  "test/features/practice_generator/application/start_plan_generation_test.dart",
  "docs/adr/0482-practice-generator-composition-layer.md",
  "docs/rounds/e15-r14-practice-generator-composition-layer.md",
]
gate_tests = [
  "test/features/practice_generator/data/local_practice_evidence_repository_test.dart",
  "test/features/practice_generator/presentation/practice_generator_providers_test.dart",
  "test/features/practice_generator/application/start_plan_generation_test.dart",
  "test/features/practice_generator/accessibility/planner_privacy_test.dart",
  "test/features/practice_generator/evidence/evidence_aggregator_test.dart",
  "test/features/practice_generator/data/local_repository_test.dart",
  "test/tooling/data_inventory_test.dart",
  "test/tooling/screen_reachability_test.dart",
  "test/tooling/gen_public_barrel_test.dart",
  "test/ui/ui_inventory_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a diff egy ÚJ perzisztens tárat vezet be, amely
gyakorlási bizonyítékot (`SkillEvidence`) őriz, és amelyre egy felhasználói
**törlés/exportálás** (adatvédelmi) útvonal fog épülni. Egy néma törlés-no-op
itt hamis consent-felületet adna. A `security-reviewer` futtatása a review-ban
**KÖTELEZŐ** ([ADR 0479](../adr/0479-privacy-data-inventory-and-consent-enforcement.md)),
a `flutter-reviewer` és a `flutter-devil-advocate` szintén.

## 0.0.A Pre-flight (indítás előtt KÖTELEZŐ) — LEFUTOTT, az eredménye a §0.0.B

> Az alábbi öt teendő az orchestrátor pre-flightjáé, és 2026-09-01-én **lefutott**.
> Az eredményt és a belőle következő **kötelező brief-revíziókat** a §0.0.B
> tartalmazza; ütközés esetén a §0.0.B szövege az érvényes.

1. **ADR-szám:** ellenőrizd, hogy a `docs/adr/0482-*.md` NEM létezik. Ha időközben
   elkelt, `tools/round-slots.py reserve-adr --round E15-R14` és a brief fejlécét
   + a §5-öt + az `allowed_paths` ADR-sorát a kapott számra írod át.
2. **A hiány újramérése** — a §0.0 három sora a kör KIINDULÓ bizonyítéka, és a
   §10-be MÉRT kimenettel kerül. Ha bármelyik időközben megszűnt (pl. valaki
   írt egy konkrét `PracticeEvidenceRepository`-t), az a rész kikerül a scope-ból,
   és ezt a §10 dokumentálja.
3. **A kulcs-tár mérése:** a `GenerationDraftRepository` (`data/local/generation_draft_repository.dart`)
   MÉRT `keyValueStore` mintája az ÚJ repository mintája is — olvasd el, mielőtt
   egy sort írsz, és KÖVESD (kulcs-névtér, szerializáció, hibakezelés).
4. **Az adat-leltár mérése:** `docs/privacy/data-inventory.yaml` — nézd meg, melyik
   route-hoz tartozik ma a gyakorlási bizonyíték, és hogy az ÚJ tár ÚJ mezőt vagy
   meglévő mező `storage`-ának pontosítását igényli-e. A `test/tooling/data_inventory_test.dart`
   a fát és a leltárt EGYMÁSHOZ méri (ADR 0479 D1) — a leltár-frissítés nem
   opcionális kozmetika, hanem gate-cella.
5. **Barrel-mérés:** `test/tooling/gen_public_barrel_test.dart` — mérd meg, hogy a
   `public/{data,application,presentation}.dart` barrelek generáltak-e, és ha igen,
   milyen paranccsal; az ÚJ fájlok exportját a MÉRT úton vedd fel, ne kézzel, ha a
   generátor a forrás.

## 0.0.B Pre-flight EREDMÉNY és brief-revízió (Claude / Opus 5, 2026-09-01, `main @ 26753c6f`)

A pre-flight lefutott. A §0.0 három kiinduló mérése VÁLTOZATLANUL érvényes
(a kimenetek a §10-be is bekerülnek, ELŐTTE-oszlopként):

| Mérés | Parancs | Eredmény |
|---|---|---|
| Provider a feature alatt | `grep -rln "Provider<\|NotifierProvider\|ChangeNotifierProvider" lib/features/practice_generator` | **ÜRES** (exit 1) |
| Konkrét evidence-repository | `grep -rn "implements PracticeEvidenceRepository" lib/` | **EGY** találat (`domain/repository/practice_evidence_repository.dart:107`, a teszt-fake) |
| Setup-varázsló vége | `plan_setup_screen.dart:96–99` | csak `controller.next()` |
| ADR-szám | `ls docs/adr/0482-*` | nem létezett → az ADR 0482 ebben a pre-flightban MEGÍRVA |

A pre-flight NÉGY további mérése a briefet módosítja. **A revíziók kötelezőek,
az implementer ezeket követi, nem a revízió előtti szöveget.**

### R1 — a generált `public.dart` az engedélyezett listára KERÜL (lista-bővítés)

**Mérés:** a `public/{data,application,presentation}.dart` fájlok **fragmensek**;
a `lib/features/practice_generator/public.dart` belőlük **generált**
(`tool/gen_public_barrel.dart`, fájlnév-sorrendű összefűzés). A
`tool/check_architecture.dart:760` `_checkGeneratedBarrels` **code_failure**-t ad
elavult barrelre („run: `dart run tool/gen_public_barrel.dart --write`"), és a
`tools/round-gate.sh` `architecture` lépése pontosan ezt futtatja.

**Következmény:** a §4 engedélyezett fragmens-szerkesztés MECHANIKUS
következménye a barrel újragenerálása. Enélkül a kör kötelező kapuja
**bizonyíthatóan** piros (H7), a barrellel viszont scope-sértés lenne (H3) — a
két hibaosztály közti kiút a lista-bővítés, egyetlen, származtatott fájlra.
Precedens ugyanerre a mintára: `docs/rounds/e12-r15-*` (`lib/core/resources/public.dart`),
`docs/rounds/e09-r05-*` (`lib/features/community/public.dart`).

**Az implementer teendője:** a barrelt **NEM kézzel** írja — a fragmens
szerkesztése után `dart run tool/gen_public_barrel.dart --write`, és a
generátor kimenetét commitolja (ADR 0482 / D6).

### R2 — az adat-leltár KIKERÜL a scope-ból, az A8 átfogalmazva (lista-szűkítés)

**Mérés:** a `docs/privacy/data-inventory.yaml` a saját fejléce szerint
**EGRESS**-leltár („this document inventories EGRESS routes — data that LEAVES
the device… `lib/core/storage/storage_keys.dart` declares 56 persisted keys;
NONE of them are inventoried here, on purpose"), a checker
(`tool/check_data_inventory.dart:431`) kizárólag `Dio`/`ApiClient`/`SharePlus`/
direkt-HTTP osztályokat talál a fában, és `wired: true` sorra, amit a fa nem
termel, **violationt** ad (`:825`).

**Következmény:** az ÚJ, eszközön belüli bizonyíték-tár nem egy kibocsátási út.
Felvétele vagy gate-sértés (`wired: true`), vagy szemantikailag hamis bejegyzés
(`wired: false`) egy dokumentumban, amelynek fejléce ezt kimondottan tiltja („Do
not add a route here that the tree does not also produce"). A `docs/privacy/data-inventory.yaml`
ezért **kikerül az engedélyezett fájllistából**; a
`test/tooling/data_inventory_test.dart` a §7 gate-ben MARAD, immár **nem-regressziós**
cellaként. A határt az ADR 0482 / D5 mondja ki (az on-device tár-leltár a
`docs/privacy/consent-enforcement.md` „What this document does not cover"
szakaszában már deklarált, önálló feladat).

**Az A8 új alakja a §6-ban.** Az adat-leltár szerkesztése ebben a körben
**tilos zóna**.

### R3 — két mért szűkösség, amit az implementernek a repository-fájlon BELÜL kell megoldania

1. **A `SkillEvidence`-nek nincs szerializációja** (`grep -n "toJson\|fromJson"
   .../domain/model/skill_evidence.dart` → üres; a `data/` fában sincs
   evidence-serializer). A JSON-kép a `local_practice_evidence_repository.dart`
   fájlba kerül — **külön serializer-fájl létrehozása H3** (nincs a listán).
2. **A `KeyValueStore`-nak nincs kulcs-felsorolása**
   (`lib/core/storage/key_value_store.dart:22`). A planner mért megoldása a
   perzisztens **manifest** (`local_practice_plan_repository.dart:168`,
   `manifestKey`, „hydration is the only way to make delete-all / export-all
   restart-stable"). Az ÚJ tár ugyanezt a mintát követi, saját, elkülönített
   kulcs-névtérben (`ss.practice_generator.evidence…`) — enélkül a `deleteForPlan`
   egy FRISS példányon nem tudná, mit töröljön, és az A2 cella pirosra vált.

`lib/core/**` szerkesztése változatlanul tilos: a `StorageKeys` a mérés szerint
ma sem sorolja fel a planner kulcsait (`grep -n "practice_generator\|generation_draft"
lib/core/storage/storage_keys.dart` → üres), tehát az új kulcs-konstans a
repository fájljában él, pontosan úgy, mint a `GenerationDraftRepository.draftStorageKey`.

### R4 — az A3 „minden kötelező konstruktor-függőség" MÉRT olvasata

A 6 képernyő konstruktora MÉRVE (a `presentation/screens/` fából). Az A3 cella
képernyőnként azt bizonyítja, hogy az alábbi jobb oldali oszlop MINDEN eleme
előáll `container.read`-del egyetlen `ProviderScope`-ból — az adatot (`plan`,
`proposal`, `today`) az azt ELŐÁLLÍTÓ provider/szolgáltatás formájában:

| Képernyő | Kötelező konstruktor-paraméter (mérve) | Amit a kompozíciós gyökérből fel kell építeni |
|---|---|---|
| `PlanSetupScreen` | `controller: PlanSetupController` | `PlanSetupController` (`draftRepository`, `clock`, `generateId`, `locale`) |
| `PlanPreviewScreen` | `controller: PlanPreviewController` | `PlanPreviewController` (köztük `activation` = a konkrét `LocalPracticePlanRepository`, ADR 0482 / D4) |
| `PlanPrivacyScreen` | `deleteUseCase`, `exportUseCase` | `DeletePracticePlanningData` + `ExportPracticePlanningData` (mindkettő a PERZISZTENS evidence-repositoryval, ADR 0482 / D2) |
| `PlanChangeReviewScreen` | `proposal`, `onAccepted`, `onRejected` | a `proposal`-t TERMELŐ `RevisePracticePlan` (`:54`); a két callback a hívó (`E15-R07 / F1`) dolga, nem provider |
| `TodayPlanScreen` | `controller: TodayPlanController` | `TodayPlanController` (`clock`) |
| `WeeklyPlanScreen` | `plan: AdaptivePracticePlan?`, `today: LocalDate` | az aktív tervet adó provider (a `LocalPracticePlanRepository`-ból) + a `today`-t adó provider |

Ahol a konstruktor-paraméter **callback** (`onAccepted`, `onStart`, …), az a
bekötő réteg (`E15-R07 / F1`) felelőssége; a kompozíciós gyökérnek nem kell
navigációs closure-t gyártania — az route-tudást igényelne, ami ebben a körben
tilos.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a kompozícióhoz a generátor-motor **viselkedését** kellene
megváltoztatni (a `domain/`, vagy az `application/service/`-ben egy meglévő
szolgáltatás algoritmusa), a kimenet `stopped` — az [ADR 0255](../adr/0255-deterministic-practice-plan-generation.md)
szerződése nem ennek a körnek a hatásköre. Az ÚJ `start_plan_generation.dart`
use case KIZÁRÓLAG a meglévő `GenerationOrchestrator`-t hívja, nem ír új
generálási logikát.

**Ugyanígy STOP**, ha a kompozícióhoz route-ot vagy flaget kellene nyitni: az az
`E15-R07 / F1`, és a fázisok sorrendje kötött.

## 1. Cél

A Practice Generator 6 terv-képernyőjének MINDEN kötelező konstruktor-függősége
előáll egyetlen, valódi (nem no-op, nem in-memory-fake) Riverpod-kompozícióból,
és a Setup-varázsló végén van egy ténylegesen meghívható út a generáláshoz — hogy
az `E15-R07 / F1` bekötése utána valóban „route + flag" méretű legyen, és a
megnyíló felület mögött valódi adat, valódi aktiválás és **valódi törlés** legyen.

## 2. Jelenlegi állapot — mért tények (`main @ 1544e6bd`)

**KÉSZ (nem ez a kör írja):**

- `application/service/generation_orchestrator.dart:62` — `GenerationOrchestrator({required activation, validator, repairer})`, `generate(GenerationPlanInput) → Future<AppResult<AdaptivePracticePlan>>`.
- `data/local/local_practice_plan_repository.dart:139` — `LocalPracticePlanRepository implements GenerationPlanActivation` (tehát az aktiválás konkrét implementációja MEGVAN).
- `application/usecase/revise_practice_plan.dart:61` — `PlanRevisionProposal`-t TERMEL (a `PlanChangeReviewScreen` bemenete).
- `application/controller/{plan_generator,today_plan,active_plan}_controller.dart`, `presentation/controller/{plan_setup,plan_preview}_controller.dart` — mind létezik.
- `data/local/generation_draft_repository.dart` — a `keyValueStore`-alapú perzisztencia MÉRT mintája.

**HIÁNYZIK (ez a kör):**

- **Nulla** Riverpod-provider a `lib/features/practice_generator` fa alatt (mérve, §0.0).
- **Nulla** konkrét `PracticeEvidenceRepository` a `lib/`-ben — csak az `InMemoryPracticeEvidenceRepository` teszt-fake (`domain/repository/practice_evidence_repository.dart:106-107`), amit a `delete`/`export` use case MÖGÉ kötni hamis adatvédelmi felület lenne (CLAUDE.md „silent no-op" csapda).
- A `PlanSetupScreen` varázsló-vége → `GenerationOrchestrator` út: a `plan_setup_screen.dart:96-99` step-4 gombja csak `controller.next()`-et hív.

**A többi feature MÉRT konvenciója a providerek helyére:** `presentation/providers/`
(`lib/features/{practice,ai_tutor,vision,gamification}/presentation/providers/` — négy
rétegzett feature, mind ott tartja). Ez a kör EZT követi.

## 3. Scope

**Benne van:**

1. **`LocalPracticeEvidenceRepository`** (`data/local/`) — a `PracticeEvidenceRepository`
   interfész PERZISZTENS implementációja a `GenerationDraftRepository` MÉRT
   `keyValueStore` mintájára, a `deleteForPlan` hookkal együtt.
2. **`practice_generator_providers.dart`** (`presentation/providers/`) — a
   kompozíciós gyökér: a 6 képernyő MINDEN kötelező konstruktor-függősége
   (repository-k, use case-ek, orchestrator, kontrollerek) provider mögül.
3. **`start_plan_generation.dart`** (`application/usecase/`) — a Setup-varázsló
   draftjából `GenerationPlanInput`-ot állít elő és a MEGLÉVŐ
   `GenerationOrchestrator.generate`-et hívja; a visszaadott `AppResult<AdaptivePracticePlan>`
   az, amiből az `E15-R07 / F1` a `PlanPreviewScreen`-t felépíti.
4. A `public/` barrel-FRAGMENSEK kiegészítése az ÚJ típusokkal, majd a generált
   `public.dart` újragenerálása (`dart run tool/gen_public_barrel.dart --write`;
   §0.0.B/R1, ADR 0482 / D6).
5. Az ÚJ ADR (§5).

**NINCS benne (tilos):**

- **Route, `AppRoutes`-konstans, `app_router.dart`, belépési pont** — az az `E15-R07 / F1`.
- **Feature-flag** (`practiceGeneratorEnabled`, `plannerAssistEnabled`) bárminemű mozdítása.
- **Bármelyik `*_screen.dart`** a `presentation/screens/` alatt — sem itt, sem máshol
  (az `E15-R07` ága ezeket MÁR migrálta; egy párhuzamos írás ott merge-konfliktus).
- Új képernyő létrehozása vagy törlése (a `ui_inventory` egzakt száma VÁLTOZATLAN).
- A `domain/` és a meglévő `application/service/` szolgáltatások VISELKEDÉSÉNEK módosítása (STOP).
- `lib/app/**`, `lib/core/**`, `tools/**`, `.github/**`.
- ARB-kulcs törlése vagy jelentés-változtatás (ÚJ kulcs felvehető, egyszerre `en` ÉS `hu` — de ez a kör felületet nem ír, tehát várhatóan NEM kell).

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/practice_generator/data/local/local_practice_evidence_repository.dart` | ÚJ — a `PracticeEvidenceRepository` perzisztens implementációja |
| `lib/features/practice_generator/presentation/providers/practice_generator_providers.dart` | ÚJ — a kompozíciós gyökér (a mért `presentation/providers/` konvenció) |
| `lib/features/practice_generator/application/usecase/start_plan_generation.dart` | ÚJ — a Setup-draft → `GenerationOrchestrator` use case |
| `lib/features/practice_generator/public/{data,application,presentation}.dart` | az ÚJ típusok exportja — a barrel FRAGMENSEI (kézzel írt forrás) |
| `lib/features/practice_generator/public.dart` | a fragmensekből GENERÁLT barrel; kézi szerkesztése tilos, a `dart run tool/gen_public_barrel.dart --write` kimenete (§0.0.B/R1) |
| `test/features/practice_generator/data/local_practice_evidence_repository_test.dart` | ÚJ — perzisztencia + a törlés TÉNY cellái |
| `test/features/practice_generator/presentation/practice_generator_providers_test.dart` | ÚJ — mind a 6 képernyő függőségének felépítése `ProviderScope`-ból |
| `test/features/practice_generator/application/start_plan_generation_test.dart` | ÚJ — a Setup→generálás lánc cellái |
| `docs/adr/0482-practice-generator-composition-layer.md` | az ÚJ döntés (a pre-flightban MÁR MEGÍRVA) |
| `docs/rounds/e15-r14-practice-generator-composition-layer.md` | a §10 kitöltése |

**Tilos zóna:** `lib/features/practice_generator/presentation/screens/**` · `lib/features/practice_generator/domain/**` · `lib/app/**` · `lib/core/**` · minden más `lib/features/**` · `tools/**` · `tool/**` · `.github/**` · `docs/execution/pipeline-*` · **`docs/privacy/**`** (§0.0.B/R2: az adat-leltár EGRESS-hatókörű, az ÚJ tár nem tartozik bele)

## 5. Kötött architekturális döntések (ADR 0482)

### 5.1 A törlés TÉNY — az in-memory fake SOHA nem kerül a production-kompozícióba

A `PracticeEvidenceRepository` production-implementációja PERZISZTENS, és a
`deleteForPlan` után az érintett bizonyíték **egy ÚJ store-példányról sem
olvasható vissza**. **NEM elfogadható gyengítés:** az `InMemoryPracticeEvidenceRepository`
bekötése „amíg a valódi elkészül" — a doc-commentje szerint az soha nem felejt,
tehát a `PlanPrivacyScreen` törlés-gombja hamis consent-felület lenne
(CLAUDE.md „silent no-op" csapda, [ADR 0479](../adr/0479-privacy-data-inventory-and-consent-enforcement.md)).

### 5.2 Nincs no-op `GenerationPlanActivation`

A `PlanPreviewController.activation` a MÉRT, konkrét `LocalPracticePlanRepository`-t
kapja (`:139` — az implementáció MEGVAN). **NEM elfogadható gyengítés:** egy
`_NoopActivation` osztály, amitől a „Megerősítés" gomb aláír, de semmi nem
aktiválódik.

### 5.3 EGY kompozíciós gyökér

A 6 képernyő függőségei EGY fájlból (`presentation/providers/practice_generator_providers.dart`)
oldódnak fel, a mért feature-konvenció szerint. **NEM elfogadható gyengítés:**
képernyőnként külön, egymásra nem hivatkozó, duplikált összeszerelés — az az
`E15-R07` bekötését ugyanoda vinné vissza, ahonnan ez a kör kiment.

### 5.4 A kör NEM tesz elérhetővé képernyőt

A `dart run tool/check_screen_reachability.dart` verdiktje a 6 terv-képernyőre a
kör UTÁN is `unreachable` (A5). **NEM elfogadható gyengítés:** „mindjárt kell
úgyis" alapon egy route felvétele — a fázissorrend kötött, és a flag-kapu
biztonsági indoklása (`security-reviewer`) az `E15-R07`-hez tartozik.

### 5.5 A providerek `autoDispose`-hoz igazodnak, ha mikrofont/erőforrást tartanak

MÉRT precedens a repó saját naplójából (a `liveFrameProvider` esete): egy
erőforrást tartó provider-t figyelő provider maga is `autoDispose` kell legyen,
különben az erőforrás bekapcsolva marad. Ez a kör nem nyit mikrofont, de a terv-generálás
futásidejű `GenerationOrchestrator`-a `StreamController`-t tart (`:74`) — a
provider `dispose`-a ezt zárja le. **NEM elfogadható gyengítés:** lezáratlan
`StreamController` egy globális, sosem eldobott providerben.

### 5.6 Riverpod 3 konvenció

Kézzel írt `Provider`/`Notifier`/`AsyncNotifier`, NINCS codegen (CLAUDE.md). Az
`AsyncValue` a `.value` (nullable) mezőt használja, **NEM** `.valueOrNull`-t
(Riverpod 3.3.2, CLAUDE.md mért igazság).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A `PracticeEvidenceRepository`-nak van PERZISZTENS konkrét implementációja a `lib/`-ben | `grep -rn "implements PracticeEvidenceRepository" lib/` KETTŐT ad (a fake + az új); a kimenet a §10-ben |
| A2 | A törlés TÉNY: `deleteForPlan` után a bizonyíték egy ÚJ repository-példányról (ugyanarra a store-ra nyitva) sem olvasható vissza | `local_practice_evidence_repository_test.dart` round-trip cellája |
| A3 | Mind a **6** terv-képernyő MINDEN kötelező konstruktor-függősége felépül egyetlen `ProviderScope`-ból, route nélkül | `practice_generator_providers_test.dart` — képernyőnként EGY cella, ami a függőségeket `container.read`-del előállítja |
| A4 | A Setup-draftból a `StartPlanGeneration` a MEGLÉVŐ `GenerationOrchestrator`-on át `AdaptivePracticePlan`-t ad, és a hibaágat is `AppResult`-tal jelzi | `start_plan_generation_test.dart` siker- ÉS hiba-cellapár |
| A5 | A 6 terv-képernyő elérhetőségi verdiktje VÁLTOZATLANUL `unreachable` (a kör nem köt be route-ot) | `dart run tool/check_screen_reachability.dart` előtte/utána, a §10-ben |
| A6 | A `ui_inventory_test.dart` egzakt `hasLength(96)` VÁLTOZATLAN | a §7 gate |
| A7 | Nincs `InMemoryPracticeEvidenceRepository` a production-kompozícióban | `grep -rn "InMemoryPracticeEvidenceRepository" lib/features/practice_generator/presentation lib/features/practice_generator/data` → ÜRES, a kimenet a §10-ben |
| A8 | **(§0.0.B/R2 szerint átírva)** Az ÚJ, eszközön belüli tár NEM kerül az EGRESS adat-leltárba, és a leltár-kapu VÁLTOZATLANUL zöld: a `docs/privacy/data-inventory.yaml` diffje ÜRES | `git diff --stat -- docs/privacy/` → üres (a §10-ben), és `test/tooling/data_inventory_test.dart` zöld a §7 gate-ben |
| A9 | A generált barrel FRISS: a `public.dart` a fragmensekből generált állapotban van | a §7 gate `architecture` lépése (`tool/check_architecture.dart` `_checkGeneratedBarrels`) zöld; a §10 rögzíti a futtatott `dart run tool/gen_public_barrel.dart --write` parancsot |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A provider az `InMemoryPracticeEvidenceRepository`-t köti be | A1 (nincs ÚJ konkrét implementáció) + A7 |
| A repository ír, de a `deleteForPlan` csak a memóriabeli másolatot üríti | A2 (az ÚJ példány visszaolvassa) |
| Csak 5 képernyő függősége áll elő, a `PlanPrivacyScreen`-é nem | A3 (a hatodik cella piros) |
| A `StartPlanGeneration` saját, új generálási logikát ír a `GenerationOrchestrator` helyett | A4 (a hiba-cella nem `AppResult`-ot ad) + STOP-sértés |
| A kör „mindjárt kell úgyis" alapon felvesz egy route-ot | A5 (az elérhetőség-mérés megváltozik) |
| A kör mégis beír egy sort az EGRESS adat-leltárba | A8 (a `docs/privacy/` diff nem üres) + `wired: true` esetén a `data_inventory_test` is piros |
| A fragmens bővül, de a generált `public.dart` elavult marad | A9 (a gate `architecture` lépése code_failure-t ad) |
| A `deleteForPlan` manifest nélkül, csak a memóriában nyilvántartott kulcsokra fut | A2 (friss példány visszaolvassa) |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** cseréld a provider
mögötti repository-t vissza `InMemoryPracticeEvidenceRepository`-ra, futtasd a §7
gate-et → az **A2** cellának PIROSNAK kell lennie → állítsd vissza. Ez pontosan
azt a hibát falszifikálja, ami miatt az `E15-R07` megállt: hogy egy „működőnek
látszó" fake mögé kötött adatvédelmi felület átcsússzon a mércén.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/data/local_practice_evidence_repository_test.dart test/features/practice_generator/presentation/practice_generator_providers_test.dart test/features/practice_generator/application/start_plan_generation_test.dart test/features/practice_generator/accessibility/planner_privacy_test.dart test/features/practice_generator/evidence/evidence_aggregator_test.dart test/features/practice_generator/data/local_repository_test.dart test/tooling/data_inventory_test.dart test/tooling/screen_reachability_test.dart test/tooling/gen_public_barrel_test.dart test/ui/ui_inventory_test.dart
```

A hiány- és elérhetőség-mérés (a kimenet a §10-be, ELŐTTE/UTÁNA):

```bash
grep -rln "Provider<\|NotifierProvider\|ChangeNotifierProvider" lib/features/practice_generator
grep -rn "implements PracticeEvidenceRepository" lib/
dart run tool/check_screen_reachability.dart
```

## 8. Implementációs sorrend

1. **Pre-flight — KÉSZ** (§0.0.B): az ADR 0482 megírva, a három hiány újramérve, a
   `GenerationDraftRepository` kulcs-tár mintája, a manifest-kényszer, az
   adat-leltár hatóköre és a barrel-generálás mért útja rögzítve. Az implementer
   a §0.0.B revízióit követi.
2. `LocalPracticeEvidenceRepository` (saját kulcs-névtér + manifest + a
   fájlon belüli `SkillEvidence` JSON-kép, §0.0.B/R3) + a perzisztencia/törlés
   cellái (A1, A2) — **először a teszt, RED → GREEN**.
3. `StartPlanGeneration` a meglévő orchestratorra + siker/hiba cellapár (A4).
4. `practice_generator_providers.dart` — a §0.0.B/R4 táblája szerint
   képernyőnként haladva, míg mind a 6 függőség-halmaz felépül (A3).
5. Barrel-fragmensek bővítése, majd `dart run tool/gen_public_barrel.dart --write` (A9).
6. Elérhetőség-mérés ÚJRA (A5), valódi-sértés próba (§6.1), a §10 kitöltése
   (a mért kimenetekkel, `docs/privacy/` üres diffjével együtt — A8).

## 9. Kockázatok

- **Hamis adatvédelmi felület.** A legnagyobb kockázat: a fake bekötése „ideiglenesen". Ezt az A2 + a valódi-sértés próba fogja meg.
- **Scope-csúszás a bekötés felé.** Egy „apró" route a fázissorrendet borítja (A5 fogja).
- **Kulcs-névtér ütközés.** Az ÚJ tár kulcsai ütközhetnek a `GenerationDraftRepository`-éval — a §0.0.A/3 mérése ezért kötelező.
- **Motor-módosítás kísértése.** Ha a kompozíció közben egy szolgáltatás „majdnem jó", a helyes kimenet a STOP, nem a csendes átírás.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
