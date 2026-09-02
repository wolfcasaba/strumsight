# E15-R14 — Kör-review (Practice Generator kompozíciós réteg)

- **Kör:** `E15-R14` · **Ág:** `sonnet-impl/e15-r14-practice-generator-composition-layer` · **Review-HEAD:** `6416d8db`
- **Implementer:** Claude Sonnet 5 (`sonnet-impl`, `--effort high`), 2026-09-02
- **Reviewer:** Claude Opus 5 (orchestrátor), READ-ONLY, izolált klón: `/tmp/review-e15-r14`
- **Kötelező ügynökök (brief §0.0, `risk = "high"`):** `security-reviewer` ✅ · `flutter-reviewer` ✅ · `flutter-devil-advocate` ✅ (mindhárom lefutott, mérésekkel)

## VÉGSŐ DÖNTÉS: CHANGES REQUESTED

**2 BLOCKER, 7 MAJOR, 7 MINOR, 3 NOTE.** Merge TILOS, amíg a BLOCKER-ek és a
MAJOR-ok nyitva vannak.

A gate ZÖLD — én magam is reprodukáltam izolált klónban (lásd §1) —, és a
**mechanikus** acceptance-cellák (A1, A5, A6, A7, A8, A9, scope) mind valóban
teljesülnek. A leletek pontosan az `AGENTS.md` §12 / `docs/LESSONS.md` L21
osztályába esnek: *a zöld gate nem bizonyíték*. A kör KÉT saját, kimondott
célja mérve nem teljesül:

1. **„a törlés TÉNY"** (brief §5.1, ADR 0482 / D2) — egy bukó `KeyValueStore`
   írás után a törlés sikert jelent, az adat a lemezen marad, és **soha többé
   nem törölhető** (B1).
2. **„MINDEN kötelező konstruktor-függőség felépül EGY `ProviderScope`-ból"**
   (A3, ADR 0482 / D1, §Következmények) — a production-alakú scope-ban a 6
   képernyőből **3-nak** a függősége és a **teljes generálási út** dob; az A3
   cella csak azért zöld, mert a saját tesztje felülírja a két hiányzó seamet (B2).

## 1. Amit magam mértem (nem bemondás)

**Gate — izolált klón, teljes, csonkítatlan futás** (`/tmp/review-e15-r14`,
`tools/round-gate.sh` a brief §7 tíz útvonalával), kimenet
`/tmp/review-gate-e15-r14.log`:

```
    format                                                     zöld
    analyze                                                    zöld
    test … local_practice_evidence_repository_test.dart        zöld
    test … practice_generator_providers_test.dart              zöld
    test … start_plan_generation_test.dart                     zöld
    test … planner_privacy_test.dart                           zöld
    test … evidence_aggregator_test.dart                       zöld
    test … local_repository_test.dart                          zöld
    test test/tooling/data_inventory_test.dart                 zöld
    test test/tooling/screen_reachability_test.dart            zöld
    test test/tooling/gen_public_barrel_test.dart              zöld
    test test/ui/ui_inventory_test.dart                        zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld

MINDEN GATE ZÖLD.
```

**Scope-audit:** `scope_audit=ok` (a wrapper gépi auditja,
`scope_audit_base=bab785bc`, `scope_audit_changed=11`); a teljes ág-diff 12
fájl, mind a brief §4 engedélyezett listáján. `docs/privacy/**`, `lib/app/**`,
`lib/core/**`, `tool/**`, `tools/**`, `.github/**`,
`presentation/screens/**` érintetlen. **Nincs scope-sértés.**

**Upstream-szinkron (prompt §0.3):** `git merge --no-ff origin/main` →
`bab785bc`, `merge-base --is-ancestor origin/main HEAD` = 0.

**CI:** `full-gate.yml` (a `tools/round-ci-plan.py` verdiktje: tisztán
Dart/dokumentum-diff), run `33669328025`, `headSha=6416d8db` = a lokális HEAD.

## 2. BLOCKER

### B1 — A perzisztens írás/törlés hibája elnyelődik: a törlés sikert jelent, az adat marad, és ÖRÖKRE törölhetetlen lesz

**Fájl:** `lib/features/practice_generator/data/local/local_practice_evidence_repository.dart:82-84`, `:166-173`, `:175-177`

A `save`, a `_removeRecord` és a `_persistManifest` minden `KeyValueStore`
műveletet `unawaited(...)`-tel indít. A store szerződése
(`lib/core/storage/key_value_store.dart:28-31`) kimondja: *„Writes never fail
silently. A platform-level write failure completes the future with a
`StorageException`"* — ez az osztály viszont nem `await`-el, nem `catchError`-öl
és nem tart hibaállapotot, tehát a `StorageException` **kezeletlen aszinkron
hibaként** szökik el.

**Mérve** (eldobható próba, `InMemoryKeyValueStore.failingKeys` — a fake pont
ezért létezik, és a kör tesztjei egyszer sem használják):

```
deleteForPlan reported removed=1
record STILL on disk? true
manifest=[]
fresh instance sees it? false
fresh instance deleteForPlan removes=0
=> residue undeletable forever: true
UNHANDLED async errors escaping unawaited(): 1 [StorageException]
```

A manifest-írás sikerül (kiveszi az id-t), a rekord-törlés bukik → **árva
kulcs**, amit a repository többé nem lát, tehát semmilyen későbbi törlés nem
ér el, miközben a `DeletePracticePlanningData` (`:83-85`) a memóriabeli számot
jelenti a felhasználónak. Ugyanez fordítva a `save`-nél: a memória „mentve"-t
mutat, a lemezen semmi.

**Miért BLOCKER:** ez szó szerint a brief §5.1 és az ADR 0479 tiltott alakja
(hamis consent-felület), és a `CLAUDE.md` „cloud writes swallowed by
try/catch → silent no-op" mért csapdájának lokális tár-változata. A testvér
`LocalPracticePlanRepository` **await-eli** minden írását és
`AppResult`/`StorageFailure`-re képezi (`:314, 319, 337, 673, 684, 690, 726`,
`_persistManifest :832-834`) — a doc-comment (`:31-41`) azt állítja, hogy
„exactly like `LocalPracticePlanRepository`", ez az írás-posztúrában **hamis**.

**Javasolt irány (a fájlon belül, scope-on belül):** a `_removeRecord` sorrendje
forduljon meg (manifest CSAK a MEGERŐSÍTETT `remove` után), és a törlési/írási
útvonal tegye megfigyelhetővé a hibát — vagy `Future`-t adó, `AppResult`-ra
képző belső írás-út + a use case által megvárt `flush()`, vagy egy
`lastWriteFailure` állapot, amit a `DeletePracticePlanningData` beszámol.
**Kötelező kísérő cella:** `failingKeys`-alapú teszt, amely MA piros lenne.

### B2 — A production-kompozíció 3/6 képernyőre és a teljes generálási útra DOB; az A3 bizonyítéka körkörös

**Fájl:** `lib/features/practice_generator/presentation/providers/practice_generator_providers.dart:84-92`, `:136-144`
· **Teszt:** `test/features/practice_generator/presentation/practice_generator_providers_test.dart:14-23`

Az `exerciseCandidateResolverProvider` és a `generationPlanInputBuilderProvider`
`UnimplementedError`-t dob, és **sehol a `lib/`-ben nincs rájuk override**
(`main.dart:90-92` csak a `keyValueStoreProvider`-t írja felül). Egy
production-alakú konténer (kizárólag `keyValueStoreProvider` override) mérve:

```
  1/6 PlanSetup   planSetupControllerProvider            -> OK
  2/6 PlanPreview planPreviewControllerFactoryProvider   -> THROWS UnimplementedError
  3/6 PlanPrivacy deletePracticePlanningDataProvider     -> THROWS UnimplementedError
  3/6 PlanPrivacy exportPracticePlanningDataProvider     -> THROWS UnimplementedError
  4/6 PlanChange  revisePracticePlanProvider             -> OK
  5/6 TodayPlan   todayPlanControllerProvider            -> OK
  6/6 WeeklyPlan  practiceGeneratorTodayProvider         -> OK
  6/6 WeeklyPlan  activePracticePlanProvider (AWAITED)   -> THROWS UnimplementedError
  GEN startPlanGenerationProvider                        -> THROWS UnimplementedError
  GEN generationOrchestratorProvider                     -> THROWS UnimplementedError
```

Az A3 cella azért zöld, mert a saját `buildContainer()`-e **pontosan azt a két
seamet** felülírja, amelyik hiányzik. A kritérium szövege („MINDEN kötelező
konstruktor-függősége felépül egyetlen `ProviderScope`-ból") tehát erősebb,
mint amit a diff igazol; az **ADR 0482 §Következmények** pedig kifejezetten az
ellenkezőjét állítja: *„az `E15-R07 / F1` bekötése ezek után valóban »route +
flag« méretű: a képernyők függőségei egyetlen `ProviderScope`-ból felépülnek"*
— **mérve hamis 3/6-ra**.

**Elismerem a szűkösséget, és NEM kérem a bekötést:** valódi
`ExerciseCandidateResolver`-hez a `lib/features/practice/public.dart`-nak
exportálnia kellene a `practiceCatalogProvider`-t (más feature = tilos zóna),
és a `PracticeCatalogEntry` metaadatai (`prerequisites`, `offlineAvailable`,
`contentRevision`, `loadProfile`) ma nem állnak elő a fán; a
`GenerationPlanInput` pedig `WeeklyScheduleDecision` + `PlanValidationContext`
összeállítását igényli, ami a STOP-protokoll szerint más kör. **A seam
maga védhető — a hallgatás nem az.** Az idézett precedens (`tutorOrchestratorProvider`)
**félig** van lemásolva: ott a seamet a boot (`main.dart:37,40`) lezárja, itt
nincs és nem is lehet boot-override ebben a körben.

**Javasolt irány (mind a három kötelező):**
1. **ADR 0482 — ÚJ döntés (D9)**, amely kimondja a két nyitott seamet, az
   `UnimplementedError` fail-loud posztúrát, és **kötelezettségként rögzíti az
   `E15-R07 / F1` boot-override-ját**; a §Következmények „route + flag" mondata
   a mért igazságra javítva.
2. **Brief §10** — a §10.1 mondja ki nyíltan, hogy az A3 „két, még kitöltetlen
   seam mellett" teljesül, és nevezze meg, MELYIK kör tölti ki. (A jelenlegi
   §10.1 hivatkozása — „ADR 0482 §Kontextus 4. pont" — hibás: az a
   `data-inventory.yaml` EGRESS-hatóköréről szól; lásd M6.)
3. **Guard-cella** a `practice_generator_providers_test.dart`-ba: egy
   **kizárólag `keyValueStoreProvider`-t** felülíró konténeren tételesen mérje,
   MELYIK provider épül fel és melyik dob (`throwsUnimplementedError`). Így a
   hiány mért tény lesz, és az F1 köre pirosra futtatja a guardot, amikor
   betölti a seamet.

## 3. MAJOR

### M1 — Hidratáláskor olvashatatlan rekord ELVESZTI a tulajdonosát → örökre törölhetetlen; a doc-comment az ellenkezőjét állítja

`local_practice_evidence_repository.dart:199-222` (a hamis állítás: `:199-204`),
`:142-164`.

A `_hydrateRecord` a boríték `evidence` mezőjén `return`-öl, **mielőtt** a
`sourcePlanId`-t kiolvasná (`:212-218`), így `_ownership` üres marad, a
`deleteForPlan`/`deleteForOutcomes` tulajdonos-kapuja (`:145`, `:158`)
elutasítja, a kulcs viszont nyersen olvasható marad:

```
deleteForPlan removed=0        (a doc-comment szerint a rekord TÖRLŐDIK)
corrupt record still on disk? true
raw value still readable: {"evidence":"NOT-A-MAP","sourcePlanId":"plan.1"}
```

Kiváltó okok valósak: ismeretlen `EvidenceSource`/`DiscomfortCategory` kód,
`measuredAt > capturedAt`, tartományon kívüli `confidence` — mind
konstruktor-validáció, mind `catch`-elve. **Irány:** a `sourcePlanId` olvasása
kerüljön az `evidence`-dekódolás ELÉ (a tulajdonosság független adat-reláció),
és a nem dekódolható rekord is legyen törölhető; a doc-comment igazodjon a
tényhez. Kísérő cella kötelező.

### M2 — Elavult példány `_persistManifest`-je felülírja egy másik példány törlését (szellem-bejegyzés + láthatatlan maradék)

`local_practice_evidence_repository.dart:175-177`. A manifest a **teljes**
példány-lokális `_outcomeIds`-t írja, tehát egy provider-újraépülés után
életben maradt régi példány bármely `save`-je visszaírja a törölt id-t vagy
felülírja a friss manifestet:

```
removed=1 ; store keys AFTER stale re-save=[…manifest, …record.outcome.1]
manifest=[] ; record raw still on disk? true
NEW instance deleteForPlan(plan.1) removes=0 ; record raw STILL on disk: true
```

Az osztály saját doc-commentje (`:17-20`) kifejezetten a provider-újraépülést
nevezi meg hibamódként — a manifest-írás mégsem olvas-egyesít. **Irány:**
read-modify-write manifest (írás előtt a lemezről egyesítés), vagy a
példány-egyediség kikényszerítése; kísérő cella.

### M3 — `practiceGeneratorTodayProvider` befagyasztja a „ma" értéket

`practice_generator_providers.dart:236-239`. A `Provider` a Riverpod 3.3.2-ben
**nem** autoDispose, és semmi nem invalidálja: a `WeeklyPlanScreen` „ma"-értéke
az első olvasáskor megfagy, és éjfél után az app teljes életciklusára rossz
marad. Ez a memóriában rögzített „stale `DateTime.now()` a provider-state-ben"
csapda. A `TodayPlanController` (`today_plan_controller.dart:54`) helyesen
olvasáskor hívja a clockot. **Irány:** ne cache-elt `LocalDate`, hanem
olvasáskor számolt érték (vagy autoDispose + explicit napváltás-invalidálás).

### M4 — `activePracticePlanProvider` a `Failure`-t „nincs terv"-vé minősíti át

`practice_generator_providers.dart:241-247` — `result.valueOrNull`. A
`LocalPracticePlanRepository` (`:358-361`) doc-contractja épp az ellenkezőjét
mondja ki: *„A present-but-corrupt pointer is a controlled failure, never
silently reclassified as first launch."* Egy sérült store-on a `WeeklyPlanScreen`
üres állapotot mutatna: a felhasználó terve „eltűnik". (Megjegyzés: a
`.valueOrNull` itt `AppResult`-tag, tehát NEM a CLAUDE.md `AsyncValue`-csapdája
— a lelet a hiba elnyelése.) **Irány:** a hibát vigye fel a UI-ig
(`AppResult`-ot adó `FutureProvider`, vagy `AsyncError`), és — másodlagosan —
aktiválás után legyen invalidálható, különben egy frissen aktivált terv csak
újraindítás után jelenik meg.

### M5 — `generationOrchestratorProvider`: `StreamController` egy globális, sosem eldobott providerben (a brief §5.5 tiltott alakja)

`practice_generator_providers.dart:122-128`. A `ref.onDispose` produkcióban
soha nem fut (nem autoDispose `Provider` + a root scope nem dobódik el); a D8
cella `container.dispose()`-zal bizonyít, ami teszt-életciklus. A brief §5.5
szó szerint: *„NEM elfogadható gyengítés: lezáratlan `StreamController` egy
globális, sosem eldobott providerben."* **Irány:** `Provider.autoDispose`, és
vele együtt a rá `watch`-oló `startPlanGenerationProvider` is — különben egy
nem-autoDispose figyelő kipinneli (a repó saját `liveFrameProvider`-precedense).

### M6 — A §10.1 olyan indoklásra hivatkozik, ami nem létezik; a két seam az ADR-ben SEHOL nincs

A §10.1 a `generationPlanInputBuilderProvider` `UnimplementedError`-jét „ADR
0482 §Kontextus 4. pont"-tal indokolja — az a pont a
`docs/privacy/data-inventory.yaml` EGRESS-hatóköréről szól. A D1–D8 döntések
**egyike sem** említi a két dobó seamet, azaz a kör legnagyobb hatású
tervezési döntése a saját ADR-jében dokumentálatlan. (A B2/1. pont javítja.)

### M7 — A `deleteForPlan` strukturálisan nem éri el azt, amit az egyetlen production író termel

`application/service/evidence_aggregator.dart:61` `_repository.save(evidence)` —
**tulajdonos nélkül**; a `lib/` fában nulla hívó ad `sourcePlanId`-t. A
`deleteForPlan` csak rögzített tulajdonosú rekordot töröl, a
`LocalPracticePlanRepository.deleteAllPlanningData()` pedig a
`ss.practice_generator.plan.` prefixre megy, tehát az evidence-t sem söpri:

```
deleteForPlan removed=0 ; readable after restart: true
plan delete-all: store still holds [evidence.record.o1, evidence.manifest]
```

Az ARB-szöveg (`practicePrivacyDeleteConfirmBody`, `practicePrivacyDeleteDone`)
viszont a bizonyíték törlését ígéri. **Ez a lelet ebben a körben NEM javítható**
(az `evidence_aggregator.dart` és az `l10n` a tilos zónában van, a javítása H3
lenne). **Kötelező kimenet:** az ADR 0482 / D9 (vagy egy külön D10) és a brief
§10 rögzítse ezt **az `E15-R07 / F1` nyitott, kötelező előfeltételeként**
(tulajdonos átadása az aggregátor hívási láncán VAGY `outcomePlanLookup` seam),
mert a bekötés pillanatában a látencia elfogy. Halasztás igen, hallgatás nem.

## 4. MINOR

1. **A `discomfort` és a `validUntil` szerializációs ág teszteletlen** —
   `local_practice_evidence_repository_test.dart:16-32` mindig `performance`-t
   állít, `DiscomfortReport` encode/decode sosem fut friss példányon.
2. **`sampleCount as int? ?? 1`** (`:268`) — csendes visszaesés `1`-re egy
   esetleg 200-mintás mérés helyett; vagy legyen kötelező, vagy verziózott.
3. **`planSetupControllerProvider` a `localeProvider`-t `watch`-olja**
   (`:157-166`) — futásidejű nyelvváltás eldobja a varázsló-kontrollert
   (draft-vesztés), és a `PlanSetupController` `notifyListeners()`-e
   (`plan_setup_controller.dart:270-273`) `_disposed`-guard nélkül fut egy
   `await` után → use-after-dispose. Irány: locale-olvasó függvény (mint a
   `clock`), vagy guard.
4. **A4 hiba-cellája nem a valós hibát fedi** — `start_plan_generation.dart:45`
   a `buildInput(draft)`-ot őrizetlenül értékeli ki, a teszt viszont csak
   orchestrátor-oldali validációs hibát mér; a „never a thrown exception"
   doc-állítás így túl széles.
5. **Tautologikus asszerciók** — `practice_generator_providers_test.dart:75-78`,
   `:146-147`: az `isA<Local…>` után az `isNot(isA<InMemory…>)` nem falszifikál külön.
6. **`outcomePlanLookup` interfész-seam nincs implementálva** — a
   `practice_evidence_repository.dart:33-47` doc-contractja említi, a konkrét
   osztálynak nincs ilyen paramétere (biztonságos irányba tér el, de a
   szerződés és az implementáció szétcsúszik).
7. **`start_plan_generation_test.dart` nem a `startPlanGenerationProvider`-en
   át mér**, és a három `GenerationOrchestrator`-t nem `dispose`-olja.

## 5. NOTE

- **`path_provider` `// ignore: depend_on_referenced_packages`**
  (`practice_generator_providers.dart:19-20`) — a csomag nincs a
  `pubspec.yaml`-ban, csak tranzitív. Van precedens
  (`analysis_providers.dart:19`, `song_trainer_providers.dart:19`), tehát nem
  ennek a körnek a bűne; ops-körben deklarálandó.
- **Az export-fájl a cache-gyökérbe kerül** és a delete-all nem söpri
  (`export_practice_planning_data.dart:197-207`; a precedens dedikált
  al-könyvtárat használ). A payload redaktált és kizárólag a felhasználó saját
  adata — nincs idegen-adat szivárgás.
- **Korlátlanul növő tár + szinkron hidratálás a provider-buildben**
  (`:45-47`, `:183-198`) — nincs felső korlát a manifest hosszára.

## 6. Amit függetlenül ÚJRAMÉRTEM és igazoltam (PASS)

| Kritérium | Bizonyíték |
|---|---|
| A1 | `grep -rn "implements PracticeEvidenceRepository" lib/` → **2** (a fake `:107` + az ÚJ `:44`) |
| A2 (szó szerinti alak) | friss példány ugyanarra a store-ra: `findByOutcomeId=null`, `manifest=[]` (a B1/M1/M2 arról szól, amit a megfogalmazás NEM fed) |
| A5 / A6 | `dart run tool/check_screen_reachability.dart` → „Measured screens: 96. Reachable: 68. Unreachable: 28." — a 6 terv-képernyő mind `unreachable`; `ui_inventory_test.dart` `hasLength(96)` változatlan |
| A7 | `grep -rn "InMemoryPracticeEvidenceRepository" lib/features/practice_generator/{presentation,data}` → ÜRES (exit 1) |
| A8 | `git diff --stat -- docs/privacy/` → ÜRES; a `data_inventory_test` zöld. A D5 határ-indoklás **helyes** (a leltár EGRESS-hatókörű) |
| A9 | a gate `architecture` lépése (`_checkGeneratedBarrels`) zöld, a fragmens + generált barrel együtt mozdult |
| Scope | 12 fájl, mind az `allowed_paths`-on; `scope_audit=ok` |
| Szerializációs round-trip | mezőnként átnézve: nincs elnyelt `SkillEvidence` mező (a lefedettség hiánya MINOR-1) |
| Névtér-izoláció (D3) | `ss.practice_generator.evidence.*` diszjunkt a terv- és draft-névterektől; próbával sem sikerült tervet/draftot felülírni |
| STOP-protokoll | a `StartPlanGeneration` nulla generálási logikát tartalmaz; a `domain/` és a szolgáltatások viselkedése változatlan |
| Egress / titkok / naplózás | nincs új kimenő út, nincs logger-import, nincs titok; `data_inventory` nem-regresszió zöld |
| D8 (teszt-életciklusban) | a `container.dispose()` lezárja a progress-streamet (a produkciós életciklus a M5) |

## 7. A javító kör kötelező kimenete

BLOCKER **B1**, **B2** és MAJOR **M1–M6** a kör engedélyezett fájljain belül
javítható. **M7 NEM javítható itt** (tilos zóna) — az ADR-ben és a §10-ben
rögzítendő az `E15-R07 / F1` nyitott előfeltételeként. Minden viselkedési
javításhoz **piros-képes cella** tartozzon (`failingKeys`, korrupt rekord,
elavult példány, override nélküli konténer) — a mérce nem gyengül.

## 8. Javító kör után — újraellenőrzés

_(a javító kör után tölti ki a reviewer)_
