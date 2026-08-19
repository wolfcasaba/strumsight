# E07-R29 — Accessibility, localization, privacy és safety hardening

- **Státusz:** PREPARED — self-heal E07-R29/H3 brief-bővítés után (2026-08-19,
  `main @ 1cad061e`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 29
- **Kör-azonosító:** `E07-R29`
- **Branch:** `<motor>/e07-r29-accessibility-privacy-hardening`
- **Előfeltétel:** `E07-R28` merge-elve (assist gateway)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a határokat az ADR 0260 §4 (érzékeny szöveg),
  0265 §3 (discomfort blokkol) és 0270 rögzíti. A §0.0.1 önjavítás sem hoz
  létre újat: brief-szintű scope-bővítés, nem normatív döntés.

## 0.0 Pre-flight revízió (2026-08-19, `main @ 1cad061e`)

**Végrehajthatósági eredmény: STOP — H3 (tilos zóna).** Ez a revízió a
dispatch előtti mérést rögzíti; nem tágítja az engedélyezett fájllistát és nem
változtat acceptance-kritériumot. (Eredetileg a lánc saját, Terra-vezényelt
E07-R29 orchestrátor-sessionje mérte és írta meg, commitolva a
`minimax/e07-r29-accessibility-privacy-hardening` ág `29863cba` commitjában —
soha nem érte el a `main`-t, mert a session a mérés után korrektül `H3`-mal
állt le implementer-dispatch nélkül. Ez az önjavítás szó szerint innen
portolja a `main`-re, és a §0.0.1-ben old fel.)

### Mért tények

- A l10n-őrt a `tool/ci/check_l10n_parity.dart` adja (a round gate is ezt
  futtatja). Az `app_en.arb`/`app_hu.arb` kulcs-, üresség- és
  placeholder-paritását méri, de saját kommentje szerint nem tudja bizonyítani,
  hogy a UI minden szöveget ARB-n keresztül használ. Ezért A1 gépi része
  rendelkezésre áll, az A2–A5 UI-audit viszont csak az érintett képernyőkön
  mérhető.
- `docs/privacy/` ezen a HEAD-en még nem létezik; az új, engedélyezett
  `docs/privacy/practice-planning-data.md` létrehozható.
- A tényleges perzisztens planning-adatok tulajdonosa nem az új use case-ek:
  a draftot a kizárt
  `data/local/generation_draft_repository.dart`, az active plan/revision/
  outcome archive-ot a kizárt
  `data/local/local_practice_plan_repository.dart` kezeli. Az utóbbi publikus
  mutációi között nincs policy-szerinti teljes törlés vagy export, a
  `KeyValueStore` pedig kulcs-enumerálást sem ad. A `PracticeEvidenceRepository`
  szintén kizárt domain-fájl, és a szerződése szándékosan csak `save`-ot,
  keresést és lekérdezést definiál — törlést nem.
- Az A2–A5 és A9 viselkedése ma a szintén kizárt, már létező
  `presentation/screens/today_plan_screen.dart`,
  `weekly_plan_screen.dart`, `plan_setup_screen.dart` és a hozzájuk tartozó
  controller/domain útvonalakon él. Az új `plan_privacy_screen.dart` nem tudja
  a meglévő státuszok, akciók, nagybetűs layout vagy reduced-motion viselkedését
  auditálhatóan megváltoztatni.
- A discomfort input tényleges útja már biztonságos: az
  `EvidenceAggregator.ingest(..., discomfortNote:)` az ingyenes szöveget
  eldobja, és csak stabil kategóriát naplóz; az `AdaptationDecider` a
  discomfortot progresszió-blokkolónak kezeli. Ez A6/A9 kiindulási bizonyíték,
  nem engedély az érintetlen rétegek átírására.

### Kötelező feloldás a következő, új briefben

Az E07-R29 jelen szerződésével implementer-dispatch tilos. Egy új, önálló
briefnek tételesen engedélyeznie kell a planning storage-owner és evidence-port
fájlokat, azok tesztjeit, valamint az auditált meglévő planner képernyőket; és
meg kell határoznia a felhasználó által indított törlés policyjét az ADR 0260
§5 immutable/expiry szabályával összhangban. Ez architekturális scope-bővítés,
nem szűkítés, ezért ebben a körben H3.

**Visszakeresett előzmények:** `lessons/L260` (redakciós teszt csak
értékoldali kanárival bizonyít szivárgást), `lessons/L261` (saját tiltott zóna
és kötelező működés ütközésekor bound feloldás kell, nem csendes tágítás),
`lessons/L107` (a meglévő őr lefedettségét mérni kell, nem feltételezni).
Nincs olyan releváns, már elfogadott ADR, amely a planning evidence explicit
felhasználói törlésének teljes storage-körét definiálná.

### 0.0.1 Önjavító kör (ADR 0112, E07-R29/H3) — a hiányzó storage-owner, evidence-port és képernyő fájlok engedélyezése

**Mérés (self-heal, 2026-08-19, izolált worktree `main @ 1cad061e`-ről,
1/3. kísérlet).** A §0.0 mérése helyes és a `.pipeline/HALTED`
(`halted_at=2026-08-19T15:08:58+00:00`) `detail=` mezőjével egyezik:

```
rg -n "clearDraft|readArchive|remove\(" \
  lib/features/practice_generator/data/local/local_practice_plan_repository.dart \
  lib/features/practice_generator/data/local/generation_draft_repository.dart
sed -n '1,120p' lib/core/storage/key_value_store.dart
```

Ez a self-heal a fenti reprodukciót és a §0.0-ban névre szólóan megnevezett
mindhárom fájlt (a két repository + a evidence-port) teljes terjedelmében
újraolvasta, majd a §0.0 saját „Kötelező feloldás" ajánlását hajtja végre —
**egyetlen** brief-bővítéssel, új ADR nélkül, ahogy a §0.0 explicit kimondta,
hogy ide nem tartozik elfogadott ADR.

**Egy pontban SZŰKEBB, mint amit a §0.0 sugallt.** A §0.0 megjegyezte, hogy „a
`KeyValueStore` kulcs-enumerálást sem ad" — ez a self-heal megmérte, hogy ez
NEM akadály: a `LocalPracticePlanRepository` minden saját kulcsát maga
generálja (`activePointerKey`, `activePlanRevisionKey`,
`archiveRevisionsIndexKey`/`archiveRevisionKey`,
`archiveOutcomesIndexKey`/`archiveOutcomeKey` —
`local_practice_plan_repository.dart:157–202`), és már MA is egyenként hívja
`keyValueStore.remove(<ismert kulcs>)`-ot a bounded-history evikció során
(`appendRevision`/`appendOutcome`, ugyanott 438–445. és 477–483. sor). Egy
teljes, egy-terv-re-szóló törlés tehát ugyanezzel a mintával (az archive-index
beolvasása → az abból származtatható kulcsok egyenkénti eltávolítása)
megírható **kizárólag ebben az egy fájlban**, a megosztott `KeyValueStore`
interfész módosítása NÉLKÜL. `lib/core/storage/key_value_store.dart` ezért
**nem** kerül az engedélyezett listára — ez önmagában is méri, hogy a
bővítés a lehető legszűkebb, nem egy megosztott, más feature-öket is
kiszolgáló interfészt tör fel.

**A képernyő-oldali granularitás forrása.** A §0.0 által megnevezett három
képernyő importlistájának tényleges elolvasása (nem feltevés):
`today_plan_screen.dart` a saját `application/controller/
today_plan_controller.dart`-ját importálja (a `TodayPlanMode` enum —
`noActivePlan/notScheduled/restDay/unavailableDay/completedDay/plannedDay` —
pontosan az A4 nem-szín-alapú státuszjelöléshez szükséges vetület, 182 sor,
tisztán prezentációs projekció, nincs domain-mutáció); `plan_setup_screen.dart`
a saját `presentation/controller/plan_setup_controller.dart`-ját és két
widgetjét (`availability_editor.dart`, `practice_goal_picker.dart`) importálja;
`weekly_plan_screen.dart`-nak nincs saját controllere (a `plan`/`today`
paraméterben kapja az adatot). Egyik érintett fájl sem importálja vagy
mutálja a tiltott domain/application réteget saját magán túl.

**`allowed_paths` az alábbi 17 bejegyzéssel bővül, `gate_tests` a belőle 7
`test/`-tel** (az eredeti 11 `allowed_paths`/2 `gate_tests` bejegyzés
változatlan):

```
lib/features/practice_generator/data/local/local_practice_plan_repository.dart
lib/features/practice_generator/data/local/generation_draft_repository.dart
lib/features/practice_generator/domain/repository/practice_evidence_repository.dart
lib/features/practice_generator/presentation/screens/today_plan_screen.dart
lib/features/practice_generator/presentation/screens/weekly_plan_screen.dart
lib/features/practice_generator/presentation/screens/plan_setup_screen.dart
lib/features/practice_generator/application/controller/today_plan_controller.dart
lib/features/practice_generator/presentation/controller/plan_setup_controller.dart
lib/features/practice_generator/presentation/widgets/availability_editor.dart
lib/features/practice_generator/presentation/widgets/practice_goal_picker.dart
test/features/practice_generator/data/local_repository_test.dart
test/features/practice_generator/data/generation_draft_repository_test.dart
test/features/practice_generator/evidence/evidence_repository_fake_test.dart
test/features/practice_generator/application/today_plan_controller_test.dart
test/features/practice_generator/presentation/today_plan_screen_test.dart
test/features/practice_generator/presentation/plan_setup_screen_test.dart
test/features/practice_generator/presentation/availability_editor_test.dart
```

(17 fájl összesen — a fenti lista 10 `lib/` + 7 `test/` bejegyzést számlál;
`gate_tests`-be csak a 7 `test/` bejegyzés kerül, a `lib/` fájlok csak
`allowed_paths`-ban szerepelnek, ahogy a séma megköveteli.)

A pontos indoklás fájlonként a §4 táblázatban; az ADR 0260 §5
(automatikus/lekérdezés-idejű elévülés vs. felhasználó-kezdeményezett
tényleges törlés) viszonyát az új §5.7 rögzíti. **`EvidenceAggregator`,
`AdaptationDecider` és minden domain/policy fájl (pl.
`scheduling_policy.dart`, amit `weekly_plan_screen.dart` csak importál, nem
módosít) a tiltott zónában marad** — a §0.0 saját megfigyelése szerint ezek
már ma helyesen működnek, nincs mért ok a megnyitásukra.

**Regressziós védelem** (ennél az önjavításnál, nem a follow-up
implementernél): `tools/tests/test_e07_r29_accessibility_privacy_scope.py` —
a valódi `audit_legacy_scope()`-ot futtatja a ténylegesen committolt brief
ellen, méri, hogy mind a 17 új bejegyzés hatókörbe kerül, hogy egy-egy
szomszédos (nem engedélyezett) fájl mindkét érintett területen (storage és
UI) kívül marad, és hogy `allowed_paths`/`gate_tests` pontosan az eredeti +
ez a 17/7 bejegyzéssel bővült — sem többel, sem kevesebbel.

## 0.0 Pre-flight revízió (2026-08-19, `main @ 1cad061e`)

**Végrehajthatósági eredmény: STOP — H3 (tilos zóna).** Ez a revízió a
dispatch előtti mérést rögzíti; nem tágítja az engedélyezett fájllistát és nem
változtat acceptance-kritériumot.

### Mért tények

- A l10n-őrt a `tool/ci/check_l10n_parity.dart` adja (a round gate is ezt
  futtatja). Az `app_en.arb`/`app_hu.arb` kulcs-, üresség- és
  placeholder-paritását méri, de saját kommentje szerint nem tudja bizonyítani,
  hogy a UI minden szöveget ARB-n keresztül használ. Ezért A1 gépi része
  rendelkezésre áll, az A2–A5 UI-audit viszont csak az érintett képernyőkön
  mérhető.
- `docs/privacy/` ezen a HEAD-en még nem létezik; az új, engedélyezett
  `docs/privacy/practice-planning-data.md` létrehozható.
- A tényleges perzisztens planning-adatok tulajdonosa nem az új use case-ek:
  a draftot a kizárt
  `data/local/generation_draft_repository.dart`, az active plan/revision/
  outcome archive-ot a kizárt
  `data/local/local_practice_plan_repository.dart` kezeli. Az utóbbi publikus
  mutációi között nincs policy-szerinti teljes törlés vagy export, a
  `KeyValueStore` pedig kulcs-enumerálást sem ad. A `PracticeEvidenceRepository`
  szintén kizárt domain-fájl, és a szerződése szándékosan csak `save`-ot,
  keresést és lekérdezést definiál — törlést nem.
- Az A2–A5 és A9 viselkedése ma a szintén kizárt, már létező
  `presentation/screens/today_plan_screen.dart`,
  `weekly_plan_screen.dart`, `plan_setup_screen.dart` és a hozzájuk tartozó
  controller/domain útvonalakon él. Az új `plan_privacy_screen.dart` nem tudja
  a meglévő státuszok, akciók, nagybetűs layout vagy reduced-motion viselkedését
  auditálhatóan megváltoztatni.
- A discomfort input tényleges útja már biztonságos: az
  `EvidenceAggregator.ingest(..., discomfortNote:)` az ingyenes szöveget
  eldobja, és csak stabil kategóriát naplóz; az `AdaptationDecider` a
  discomfortot progresszió-blokkolónak kezeli. Ez A6/A9 kiindulási bizonyíték,
  nem engedély az érintetlen rétegek átírására.

### Kötelező feloldás a következő, új briefben

Az E07-R29 jelen szerződésével implementer-dispatch tilos. Egy új, önálló
briefnek tételesen engedélyeznie kell a planning storage-owner és evidence-port
fájlokat, azok tesztjeit, valamint az auditált meglévő planner képernyőket; és
meg kell határoznia a felhasználó által indított törlés policyjét az ADR 0260
§5 immutable/expiry szabályával összhangban. Ez architekturális scope-bővítés,
nem szűkítés, ezért ebben a körben H3.

**Visszakeresett előzmények:** `lessons/L260` (redakciós teszt csak
értékoldali kanárival bizonyít szivárgást), `lessons/L261` (saját tiltott zóna
és kötelező működés ütközésekor bound feloldás kell, nem csendes tágítás),
`lessons/L107` (a meglévő őr lefedettségét mérni kell, nem feltételezni).
Nincs olyan releváns, már elfogadott ADR, amely a planning evidence explicit
felhasználói törlésének teljes storage-körét definiálná.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd meg a projekt **l10n
> paritás-ellenőrzőjét** (`tools/check_l10n_parity` vagy a `test/tooling/`
> megfelelője) és a meglévő adatvédelmi dokumentumok helyét
> (`docs/privacy/`). Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "lib/features/practice_generator/presentation/screens/plan_privacy_screen.dart",
  "lib/features/practice_generator/application/usecase/delete_practice_planning_data.dart",
  "lib/features/practice_generator/application/usecase/export_practice_planning_data.dart",
  "lib/features/practice_generator/public.dart",
  "docs/privacy/practice-planning-data.md",
  "test/features/practice_generator/accessibility/planner_accessibility_test.dart",
  "test/features/practice_generator/accessibility/planner_privacy_test.dart",
  "test/fixtures/practice_generator/accessibility/",
  "docs/rounds/e07-r29-accessibility-privacy-hardening.md",
  "lib/features/practice_generator/data/local/local_practice_plan_repository.dart",
  "lib/features/practice_generator/data/local/generation_draft_repository.dart",
  "lib/features/practice_generator/domain/repository/practice_evidence_repository.dart",
  "lib/features/practice_generator/presentation/screens/today_plan_screen.dart",
  "lib/features/practice_generator/presentation/screens/weekly_plan_screen.dart",
  "lib/features/practice_generator/presentation/screens/plan_setup_screen.dart",
  "lib/features/practice_generator/application/controller/today_plan_controller.dart",
  "lib/features/practice_generator/presentation/controller/plan_setup_controller.dart",
  "lib/features/practice_generator/presentation/widgets/availability_editor.dart",
  "lib/features/practice_generator/presentation/widgets/practice_goal_picker.dart",
  "test/features/practice_generator/data/local_repository_test.dart",
  "test/features/practice_generator/data/generation_draft_repository_test.dart",
  "test/features/practice_generator/evidence/evidence_repository_fake_test.dart",
  "test/features/practice_generator/application/today_plan_controller_test.dart",
  "test/features/practice_generator/presentation/today_plan_screen_test.dart",
  "test/features/practice_generator/presentation/plan_setup_screen_test.dart",
  "test/features/practice_generator/presentation/availability_editor_test.dart",
]
gate_tests = [
  "test/features/practice_generator/accessibility/planner_accessibility_test.dart",
  "test/features/practice_generator/accessibility/planner_privacy_test.dart",
  "test/features/practice_generator/data/local_repository_test.dart",
  "test/features/practice_generator/data/generation_draft_repository_test.dart",
  "test/features/practice_generator/evidence/evidence_repository_fake_test.dart",
  "test/features/practice_generator/application/today_plan_controller_test.dart",
  "test/features/practice_generator/presentation/today_plan_screen_test.dart",
  "test/features/practice_generator/presentation/plan_setup_screen_test.dart",
  "test/features/practice_generator/presentation/availability_editor_test.dart",
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

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

A teljes funkció publikálás előtti hozzáférhetőségi, adatvédelmi és
biztonsági megerősítése (SDD Ch8 Kör 29).

## 2. Jelenlegi állapot — mért tények

- Az R20-R22, R26-R27 UI-köreiben már ARB-alapú szövegek vannak.
- Az ADR 0260 §4: **érzékeny szabad szöveg nem naplózható**.
- Az ADR 0265 §3: **a fájdalomjelzés blokkolja a nehezítést**.
- A flagek **OFF** — ez a kör sem kapcsol be semmit.

## 3. Scope

**Benne van:** teljes hu/en paritás · nagy betűméret és képernyőolvasó-sorrend
auditja · reduced motion és **nem szín-alapú** státuszjelölés · telemetria és
napló redakciója · kényelmetlenség-visszajelzés biztonsági folyamata ·
**teljes törlés/export** UX · a manipulatív szövegezés auditja · (self-heal
E07-R29/H3, §0.0.1) a törlés/export tényleges storage-owner és evidence-port
metódusai, valamint az auditált meglévő planner-képernyők/controllerek
accessibility-javítása.

**NINCS benne (tilos):** új funkció · flag `true`-ra állítása · a domain
módosítása (a §0.0.1 alatt névre szólóan engedélyezett storage-owner,
evidence-port és planner-képernyő/controller fájlok kivételével) ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/l10n/app_en.arb`, `app_hu.arb` | a paritás lezárása |
| `presentation/screens/plan_privacy_screen.dart` | **ÚJ** — törlés/export |
| `application/usecase/delete_practice_planning_data.dart` | **ÚJ** |
| `application/usecase/export_practice_planning_data.dart` | **ÚJ** |
| `docs/privacy/practice-planning-data.md` | **ÚJ** — mit tárolunk és meddig |
| `public.dart` | a barrel bővítése |
| `test/…/accessibility/*_test.dart` (2 db) | a §6 cellái |
| `docs/rounds/e07-r29-…md` | a §10 handoff |
| `data/local/local_practice_plan_repository.dart` | **(§0.0.1)** az active/archive/draft tulajdonosa — ide kell a policy-szerinti teljes törlés metódusa |
| `data/local/generation_draft_repository.dart` | **(§0.0.1)** a wizard-draft tulajdonosa — a törlés/export kör része |
| `domain/repository/practice_evidence_repository.dart` | **(§0.0.1)** jelenleg SOSEM töröl (szándékos) — a felhasználó-kezdeményezett törléshez egy SZŰK, csak erre a hívási útra fenntartott metódus kell, ld. §5.7 |
| `presentation/screens/today_plan_screen.dart` | **(§0.0.1)** A2–A5/A9 él itt — audit + fix |
| `presentation/screens/weekly_plan_screen.dart` | **(§0.0.1)** ugyanaz |
| `presentation/screens/plan_setup_screen.dart` | **(§0.0.1)** ugyanaz |
| `application/controller/today_plan_controller.dart` | **(§0.0.1)** a `TodayPlanMode` nem-szín-alapú vetület forrása (A4) |
| `presentation/controller/plan_setup_controller.dart` | **(§0.0.1)** a `plan_setup_screen.dart` állapota |
| `presentation/widgets/availability_editor.dart` | **(§0.0.1)** a `plan_setup_screen.dart` gyermeke — az űrlap accessibility-je itt él |
| `presentation/widgets/practice_goal_picker.dart` | **(§0.0.1)** ugyanaz |
| a fenti 10 fájl saját, meglévő tesztje (7 db, ld. §0.0.1 listája) | **(§0.0.1)** a bővített/módosított viselkedés regressziója — az implementer bővítheti, nem törölheti a meglévő eseteket |

**Tilos zóna:** `lib/app/config/feature_flags.dart` · a generátor domain- és
application-logikája (a két új use case, valamint a §0.0.1 alatt névre
szólóan felsorolt 10 `lib/`-fájl kivételével — ezen 10 fájlon KÍVÜL minden
más domain/application/presentation fájl, pl. `EvidenceAggregator`,
`AdaptationDecider`, `scheduling_policy.dart`, `plan_preview_screen.dart`,
`plan_change_review_screen.dart`, továbbra is tiltott) · más `lib/features/**` ·
`docs/adr/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 Érzékeny adat SEHOL nem kerül naplóba vagy telemetriába

Az ADR 0260 §4 kiterjesztése a telemetriára is. A napló azonosítót és
kategóriát írhat, tartalmat nem.

### 5.2 A fájdalomjelzés NEM indít progressziót — UI-oldalon is

Az ADR 0265 §3 felületi betartása: a kényelmetlenség jelzése után a UI nem
kínál nehezítést, és a biztonsági folyamat elérhető.

### 5.3 A státusz NEM lehet csak szín-alapú

Minden állapot (kész, kihagyott, pihenő) **szövegesen vagy ikonnal** is
jelölt. Szín-vakság mellett is használható.

### 5.4 Minden akció elérhető billentyűzettel és képernyőolvasóval

Nincs csak-érintéses vagy csak-gesztus akció.

### 5.5 A törlés TÉNYLEGES, és a policy szerinti kört törli

A „minden adat törlése" a tervet, a revíziókat és a hozzájuk kötött
evidence-et is törli a dokumentált policy szerint — nem csak elrejti.
Az export ugyanezt a kört adja ki.

### 5.6 A szövegezés NEM manipulatív

Se bűntudatkeltés, se hamis sürgetés („már 3 napja nem…"). Ez acceptance-cella
(A8), az R27 §5.5 folytatása.

### 5.7 A felhasználó-kezdeményezett teljes törlés az ADR 0260 §5 SZŰK, dokumentált kivétele (self-heal E07-R29/H3, §0.0.1)

Az ADR 0260 §5 szerint az elévült evidence **automatikusan sosem törlődik** —
az elévülés lekérdezés-idejű súly, nem storage-idejű törlés; ez a szabály
**változatlan marad** minden automatikus és lekérdezési útvonalon (a Kör 6
skill-becslő reducer, a normál `query`/`allForSkill` hívók). A §5.5 „teljes
törlés" egy **strukturálisan különböző** trigger: kizárólag a felhasználó
explicit, egyszeri „minden gyakorlás-tervezési adatom törlése" kérése
indíthatja — sosem elévülés, ütemezett takarítás vagy más automatika.

A `PracticeEvidenceRepository`-n a §0.0.1 alatt hozzáadott törlés-metódus
ezért **kizárólag** a `delete_practice_planning_data.dart` use case hívási
útján érhető el; minden más hívó az evidence-et továbbra is
elévülés-immutábilisnak látja. A jelenlegi docstring
(„there is deliberately no delete/expire operation") az eddigi, törlés
nélküli szerződést dokumentálja — az implementernek az ÚJ metódus nevével és
saját dokumentációjával kell egyértelművé tennie, hogy az kizárólag a
felhasználói jog-gyakorlás belépési pontja, nem egy általános törlés-API.
A megkülönböztetés bizonyítéka a §6.1 valódi-sértés próba (A6/A7 mellett): a
törlés a `planId`/forrás-outcome azonosítókra szűkített, a küszöb fölötti
(más feature) adatot **nem** éri el.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Teljes hu/en ARB-paritás | l10n paritás-ellenőrző |
| A2 | Nagy betűméretnél nincs túlcsordulás a generátor képernyőin | `planner_accessibility_test.dart` |
| A3 | Minden akció elérhető képernyőolvasóval | ugyanott |
| A4 | A státusz nem csak szín-alapú | ugyanott |
| A5 | Reduced motion tiszteletben tartva | ugyanott |
| A6 | Érzékeny adat nincs naplóban/telemetriában | `planner_privacy_test.dart` |
| A7 | Törlés után a policy szerinti adat ténylegesen eltűnik | ugyanott |
| A8 | A szövegek nem manipulatívak (audit + review) | review + ARB diff |
| A9 | Fájdalomjelzés után a UI nem kínál nehezítést | `planner_accessibility_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A szabad szöveg telemetriában | **A6** |
| Csak szín jelzi a kihagyott napot | **A4** |
| A törlés csak elrejti az adatot | **A7** |
| Fix magasságú sor nagy betűméretnél | A2 |
| Csak-gesztus akció | A3 |
| Fájdalom után is felkínált nehezítés | **A9** |

**A törlés három kötelező cellája** (a küszöb: a policy szerinti kör):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | csak a terv törlése | a terv eltűnik, az evidence a policy szerint marad |
| rajta (a küszöbön) | „minden tervezési adat" | a **teljes** policy-kör törlődik |
| a küszöb fölött | más feature adata (pl. Learn-előzmény) | **érintetlen** — nem törlünk túl |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** írd a tanuló
kényelmetlenség-megjegyzését a telemetriába → az **A6** cellának PIROSNAK
kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/accessibility/planner_accessibility_test.dart test/features/practice_generator/accessibility/planner_privacy_test.dart test/features/practice_generator/data/local_repository_test.dart test/features/practice_generator/data/generation_draft_repository_test.dart test/features/practice_generator/evidence/evidence_repository_fake_test.dart test/features/practice_generator/application/today_plan_controller_test.dart test/features/practice_generator/presentation/today_plan_screen_test.dart test/features/practice_generator/presentation/plan_setup_screen_test.dart test/features/practice_generator/presentation/availability_editor_test.dart
```

A gate-lista (self-heal E07-R29/H3, §0.0.1) a két ÚJ tesztfájl mellé felveszi
a §0.0.1-ben megnyitott 10 meglévő fájl mind a 7 saját tesztjét — a bővített
storage/evidence/screen viselkedés regresszióját a kör SAJÁT gate-je fogja
meg, nem csak a végső CI teljes suite-ja.

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. ARB-paritás lezárása (hu + en).
2. `docs/privacy/practice-planning-data.md` — mit tárolunk, meddig, mit törlünk.
3. `delete_…` és `export_…` use case-ek a dokumentált kör szerint.
4. `plan_privacy_screen.dart`.
5. Hozzáférhetőségi audit: nagy betű, semantics, nem-szín státusz, reduced motion.
6. Redakciós audit a naplón és telemetrián.
7. Tesztek a §6.1 három törlés-cellájával.
8. A valódi-sértés próba, §10-be dokumentálva.
9. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A telemetria mint kiskapu.** A naplót figyeljük, a telemetriát elfelejtjük
  — és a legérzékenyebb adat ott megy ki (A6).
- **A túl sokat törlő „mindent töröl".** Más feature adatát is elvinné (A7,
  a harmadik cella).
- **A szín-alapú státusz.** Szépen néz ki, és a felhasználók egy része nem
  látja (A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
