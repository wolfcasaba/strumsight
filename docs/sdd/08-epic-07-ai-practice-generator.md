# StrumSight Software Design Document

## Chapter 8 — Epic 7: AI Practice Generator

**Dokumentumverzió:** 1.0  
**Státusz:** fejlesztésre kész specifikáció  
**Repository:** `wolfcasaba/strumsight`  
**Elsődleges kliens:** Flutter, Android-first  
**Tervezési alapelv:** deterministic-first, AI-assisted, offline-first  
**Adatkezelés:** a tanulói profil és gyakorlási előzmény alapértelmezetten helyben marad  
**Kapcsolódó fejezetek:** Chapter 2 Core Platform, Chapter 3 Practice Engine, Chapter 4 Song Trainer, Chapter 5 AI Guitar Teacher, Chapter 6 Computer Vision, Chapter 7 Audio Analysis 2.0  
**Végrehajtó:** Codex  
**Végrehajtási mód:** külön branchben vagy külön, önálló commitban végzett kis fejlesztési körök

---

# 1. Az Epic célja

Az Epic 7 célja egy olyan adaptív gyakorlástervező rendszer létrehozása, amely a felhasználó céljaiból, rendelkezésre álló idejéből, bizonyított készségállapotából és az alkalmazás tényleges gyakorlási képességeiből végrehajtható napi és heti terveket készít.

A rendszer nem egyszerűen véletlenszerű feladatlistát állít elő. Minden tervnek meg kell tudnia válaszolni az alábbi kérdéseket:

- Mi a felhasználó elsődleges célja?
- Milyen készségek előfeltételei ennek a célnak?
- Mely hiányosságokat támasztják alá megbízható mérések?
- Mely készségeket kell fenntartani, nem csak javítani?
- Mennyi idő áll ténylegesen rendelkezésre ma és ezen a héten?
- Mely gyakorlatok futtathatók az adott eszközön, tuningban és offline állapotban?
- Mi legyen a mai legfontosabb fókusz?
- Mikor indokolt gyorsítani, nehezíteni, ismételni vagy egyszerűsíteni?
- Mi változott a terv előző verziójához képest, és miért?
- Mely döntések támaszkodnak erős bizonyítékra, és melyek csak konzervatív kiindulási feltételezések?

A rendszer kimenete egy verziózott, validált és offline végrehajtható `AdaptivePracticePlan`. A terv blokkjai a Chapter 3 Practice Engine, a Chapter 4 Song Trainer és szükség esetén más biztonságos alkalmazásfunkciók által végrehajtható, típusos hivatkozások.

Az Epic végeredménye egy olyan személyes gyakorlási útvonal, amely:

- nem bünteti a kihagyott napokat;
- nem terheli túl a felhasználót;
- nem reagál túl egyetlen zajos vagy bizonytalan sessionre;
- nem talál ki nem létező gyakorlatot;
- nem tesz orvosi vagy sérülésdiagnosztikai állítást;
- nem igényel felhőt az alapvető tervkészítéshez;
- mindig lehetővé teszi a felhasználónak a terv megtekintését, módosítását, szüneteltetését és elutasítását.

---

# 2. Termékvízió

## 2.1 Felhasználói ígéret

A felhasználó ne egy általános tanácsot kapjon, például:

> Gyakorolj többet metronómmal.

Hanem egy végrehajtható tervet:

> Ma 20 perced van. Kezdd 3 perc könnyű akkordváltással, majd gyakorold a G–Am váltást 8 percig 72 BPM-en. Ezután játssz két négysávos loopot a kiválasztott dal refrénjéből 80%-os sebességen. A végén 4 perc szabad játék következik. Azért került előre a G–Am váltás, mert három külön sessionben ez lassította a refrént.

A terv ne csak tartalmat válasszon, hanem:

- adagolja az időt;
- megadja az induló nehézséget;
- leírja a siker feltételét;
- előre rögzítse a regresszió és progresszió szabályát;
- biztosítson könnyebb helyettesítést;
- megőrizze a motiváló, élvezeti blokkot;
- a végén mérhető eredményt gyűjtsön a következő tervhez.

## 2.2 A generátor nem autonóm tanár

A generátor nem hajthat végre rejtett, felhasználói kontroll nélküli döntéseket.

Nem teheti meg automatikusan:

- terv tartós mentését előnézet nélkül;
- aktív terv felülírását változáslista nélkül;
- session indítását;
- értesítések engedélyezését;
- felhőfeltöltést;
- profiladat módosítását;
- kényelmetlenség vagy fájdalom figyelmen kívül hagyását;
- fizetős tartalom kiválasztását anélkül, hogy ezt jelezné;
- nem elérhető dal vagy modell használatát.

## 2.3 Deterministic-first

A terv kiválasztási, időelosztási, prerequisite-, terhelési és validációs logikája determinisztikus policy-kból álljon.

Az AI-modell opcionális szerepei:

- természetes nyelvű cél strukturálása;
- felhasználóbarát indoklás megfogalmazása;
- a validált katalógusból alternatív blokk javaslata;
- tervváltozás közérthető összefoglalása;
- a Tutor beszélgetésből explicit, megerősített céljavaslat készítése.

Az AI-modell nem:

- hozhat létre ismeretlen exercise ID-t;
- adhat tetszőleges route-ot;
- módosíthat score-t vagy mért eredményt;
- kerülheti meg a prerequisite graphot;
- dönthet egyedül terhelésnövelésről;
- írhat közvetlenül repositoryba;
- láthat nyers audio- vagy videófolyamot;
- generálhat végrehajtható tervet validator nélkül.

## 2.4 Offline-first

A teljes alapfolyamat működjön internet nélkül:

1. cél és időkeret megadása;
2. lokális készségbizonyíték összegyűjtése;
3. gyakorlatjelöltek kiválasztása;
4. napi és heti terv létrehozása;
5. terv mentése;
6. terv végrehajtása;
7. sessioneredmények feldolgozása;
8. következő napi terv módosítása.

Felhő csak opcionális kiegészítés:

- AI által megfogalmazott magyarázat;
- Tutor integráció;
- account sync;
- későbbi felhőalapú content pack;
- anonimizált, opt-in minőségi telemetry.

## 2.5 A siker definíciója

Az Epic sikeres, ha a felhasználó:

- két percen belül képes első tervet készíteni;
- adat nélküli új felhasználóként is biztonságos starter tervet kap;
- mérési előzményekkel személyre szabott prioritást kap;
- egyetlen gombbal elindíthatja a mai következő blokkot;
- minden tervváltozásnál látja az okot;
- kihagyott nap után nem kap büntető, megduplázott terhelést;
- offline állapotban is végig tudja csinálni a tervet;
- bármely blokkot helyettesíthet vagy kihagyhat;
- a tervet szüneteltetheti és újraindíthatja;
- a rendszer bizonytalanságát érthetően látja.

---

# 3. Kapcsolat a jelenlegi kódbázissal

## 3.1 Jelenlegi, közvetlenül újrahasználandó elemek

A jelenlegi repository már tartalmaz olyan elemeket, amelyekből a generátor bemenetet és végrehajtható célt készíthet.

### Learn

A `learn` feature jelenleg rendelkezik:

- időzített `LessonEvent` modellel;
- BPM-mel és ütemmutatóval;
- nehézségi szintekkel;
- beépített lesson katalógussal;
- simplified variationnel;
- live timing- és direction-pontozással;
- lesson progress és csillaglogikával;
- unlock lánccal;
- practice speed beállítással;
- metronómmal;
- latency calibrationnel.

### Progress

A `progress` feature jelenleg tárol:

- practice entryket;
- napi és heti statisztikát;
- napi célbeállítást;
- összes gyakorlási időt.

### Streak

A `streak` feature jelenleg támogat:

- napi aktivitást;
- longest streaket;
- streak freeze logikát;
- determinisztikus daily challenge-et;
- időinjektálható teszteket.

### Songs és Setlists

A jelenlegi `songs` feature:

- lokális daltárolást;
- akkord- és baralapú dalmodellt;
- egyedi strumming patternt;
- 3/4 és 4/4 támogatást;
- Setlistet;
- Learn-indítást

biztosít.

### Analyze és Library

A jelenlegi Analyze rendszer:

- felvételt vagy WAV-importot elemez;
- BPM-et, akkordokat és strum eseményeket állít elő;
- Libraryben menthető eredményt ad;
- elemzésből lesson készíthető.

### Settings

A generátor figyelembe veheti:

- balkezes mód;
- capo;
- tuning reference;
- locale;
- latency beállítások;
- nudge preference;
- Lab mód;
- később tuning és accessibility preferenciák.

## 3.2 A korábbi SDD-fejezetek célarchitektúrája

Az Epic 7 elsődlegesen a korábbi fejezetek által létrehozott nyilvános szerződésekre épül.

### Chapter 3 — Practice Engine

A generátor a következőket használja:

- `PracticeDefinition`;
- `PracticeCatalogRepository`;
- `PracticeMode`;
- `PracticeDifficulty`;
- `PracticeSessionConfig`;
- Speed Builder policy;
- `PracticeSessionResult`;
- skill tagek;
- adaptív suggestionök;
- practice result persistence.

### Chapter 4 — Song Trainer

A generátor használhatja:

- `SongDocument`;
- `SongRange`;
- section és loop referenciák;
- tempo scaling;
- song capability;
- song performance result;
- Setlist V2.

### Chapter 5 — AI Guitar Teacher

A generátor használhatja:

- megerősített `StudentProfile` adatokat;
- `Goal` és `SkillGraph` állapotot;
- `TutorContextSnapshot` kivonatot;
- determinisztikus debrief insightokat;
- typed Tutor tool rendszert;
- `PracticePlanDraft` proposal DTO-t.

Fontos határ: a Chapter 5 `PracticePlanDraft` a Tutor által javasolt rövid tervelőnézet. Az Epic 7 vezeti be a kanonikus, többnapos és revíziózható `AdaptivePracticePlan` domaint. A kettő között explicit adapter szükséges.

### Chapter 6 — Computer Vision

A generátor kizárólag confidence-aware, származtatott vision evidence-et használhat:

- posture consistency;
- wrist angle proxy;
- fretting-hand stability proxy;
- picking-hand motion proxy;
- setup/calibration quality.

Nyers kamera frame nem kerülhet a generátorba.

### Chapter 7 — Audio Analysis 2.0

A generátor felhasználhatja:

- timing és rush/drag metrikákat;
- tempo stabilityt;
- rhythm consistencyt;
- stroke balance-t;
- chord evidence-et;
- monofonikus pitch capabilityt;
- confidence-et;
- hotspotokat;
- összehasonlítási trendet;
- determinisztikus coaching insightokat.

## 3.3 Jelenlegi technikai hiányok

Az Epic indulásakor a repositoryban nincs:

1. kanonikus többnapos practice plan domain;
2. explicit generation request;
3. heti elérhetőségi modell;
4. goal-to-skill prioritásmotor;
5. evidence normalizáló réteg;
6. exercise capability snapshot;
7. időkeret-elosztó algoritmus;
8. spaced repetition queue;
9. plan revision és change set;
10. missed-day policy;
11. adaptációs döntésnapló;
12. plan compiler;
13. today-plan orchestrator;
14. tervszintű persistence;
15. plan evaluation harness;
16. generátor feature UI.

## 3.4 Migrációs stratégia

A meglévő Learn és Progress funkciókat nem szabad egyszerre átírni.

A generátor első verziója adapterekkel dolgozzon:

```text
Legacy Learn lesson
        ↓
LegacyLessonCatalogAdapter
        ↓
PracticeCandidate

PracticeEntry / LessonProgress
        ↓
LegacyProgressEvidenceAdapter
        ↓
SkillEvidence
```

Amint a Chapter 3 és a többi korábbi Epic implementációja elkészül, az adapterek forrása lecserélhető a stabil public API-kra.

A generátor domainje nem függhet közvetlenül legacy provider vagy screen fájltól.

---

# 4. Hatókör

## 4.1 Az Epic része

- generátor feature és public API;
- practice goal és constraint domain;
- heti rendelkezésre állás;
- készségbizonyíték normalizálás;
- confidence- és recency-aware skill estimate;
- practice catalog capability adapter;
- exercise prescription;
- napi és heti terv;
- tervverzió és revízió;
- determinisztikus prioritásmotor;
- időkeret-elosztás;
- skill rotation és maintenance;
- spaced repetition;
- progresszió és regresszió;
- missed-day és catch-up policy;
- plan compiler;
- Today flow;
- sessioneredmény-feldolgozás;
- adaptív tervfelülvizsgálat;
- tervelőnézet és kézi szerkesztés;
- Tutor és opcionális model-assisted integráció;
- local-first persistence;
- optional cloud sync contract;
- localization és accessibility;
- evaluation és simulation harness;
- shadow rollout és legacy adapterek.

## 4.2 Nem része

- új audio DSP modell;
- új vision modell;
- teljes AI Tutor újraírása;
- tetszőleges LLM által létrehozott gyakorlatkód;
- emberi tanár piactér;
- közösségi edzéstervek;
- subscription vagy paywall implementáció;
- klinikai terhelés- vagy sérülésdiagnózis;
- background autonóm sessionindítás;
- naptárconnector;
- valós idejű többfelhasználós coaching;
- Chapter 11-ben tervezett helyi LLM runtime.

## 4.3 Függőségi előfeltételek

A teljes integrációhoz előnyös, de nem minden körhöz kötelező:

- Chapter 2 `AppResult`, `AppFailure`, `Clock`, storage és logging;
- Chapter 3 Practice Catalog és session result;
- Chapter 5 skill graph és tutor tool;
- Chapter 7 evidence és insight public API.

Ha egy előfeltétel még nincs implementálva, fake és legacy adapter szükséges. A generátor domainjét nem szabad az ideiglenes adapterhez igazítani.

---

# 5. Tervezési alapelvek

## 5.1 A terv egy verziózott döntési dokumentum

A terv nem egyszerű lista. Tartalmazza:

- a generáláskor használt bemenetek kivonatát;
- a policy verziókat;
- a kiválasztott blokkokat;
- az idő- és nehézségbeállítást;
- a blokk célját;
- az evidence referenciát;
- a success criteria-t;
- a fallbacket;
- a későbbi revíziók változásait.

## 5.2 Bizonytalanságtudatos működés

A rendszer különböztesse meg:

- nincs adat;
- kevés adat;
- ellentmondó adat;
- elavult adat;
- megbízható, ismételt adat.

Adathiány nem jelent gyengeséget. Ilyenkor starter vagy assessment blokk választható.

## 5.3 Felhasználói kontroll

A felhasználó:

- megváltoztathatja a heti napokat;
- csökkentheti vagy növelheti a napi időt;
- rögzíthet preferált és kerülendő gyakorlatot;
- helyettesíthet blokkot;
- kihagyhat blokkot;
- szüneteltetheti a tervet;
- új célt adhat hozzá;
- lezárhat vagy archiválhat tervet;
- elutasíthatja az adaptációt;
- törölheti a tervadatokat.

## 5.4 Egyértelmű indoklás

Minden automatikus döntés kapjon gépi reason code-ot és lokalizálható magyarázatot.

Példák:

```text
plan.reason.goal_alignment
plan.reason.repeated_timing_gap
plan.reason.prerequisite_missing
plan.reason.review_due
plan.reason.song_section_hotspot
plan.reason.maintenance_due
plan.reason.low_confidence_assessment
plan.reason.user_preference
plan.reason.device_capability
plan.reason.time_budget
```

## 5.5 Nem büntető adaptáció

Kihagyott nap esetén tilos:

- automatikusan megduplázni a következő nap idejét;
- streakvesztéssel fenyegető szöveget használni;
- „elmaradás” vagy „kudarc” nyelvezettel szégyeníteni;
- több nehéz blokkot összezsúfolni.

A rendszer inkább:

- átteszi a legfontosabb blokkot;
- elhagy alacsony prioritású maintenance blokkot;
- rövidített catch-up tervet ajánl;
- hagyja a hetet természetesen továbbhaladni.

## 5.6 Élvezet és fenntarthatóság

A terv nem lehet kizárólag hibajavítás.

A policy támogassa:

- song vagy repertoire blokkot;
- free playt;
- választott stílust;
- rövid sikerélményt;
- túlzott ismétlés elleni változatosságot.

## 5.7 Fizikai komfort

A felhasználó fájdalom- vagy kényelmetlenségjelzése elsőbbséget élvez a teljesítménymetrikákkal szemben.

A rendszer:

- ne diagnosztizáljon;
- javasolja a megállást vagy pihenést;
- ne emelje a terhelést;
- ajánljon könnyebb, alacsonyabb terhelésű vagy nem játékos blokkot;
- tartós panasz esetén javasoljon megfelelő szakembert.

---

# 6. Felhasználói történetek

## 6.1 Új kezdő, mérési előzmény nélkül

1. A felhasználó kiválasztja, hogy akkordozni és egyszerű dalokat szeretne játszani.
2. Heti négy napot, napi 15 percet ad meg.
3. A rendszer nem állítja, hogy tudja, miben gyenge.
4. Starter foundation tervet készít.
5. Az első hét assessment jellegű, de nem vizsgaszerű.
6. A sessionök után a terv fokozatosan személyre szabódik.

## 6.2 Visszatérő felhasználó timing problémával

1. A Chapter 7 három sessionben stabil late bias-t mutat.
2. A felhasználó célja egy pop strumming pattern tiszta lejátszása.
3. A generátor a timing fókuszt magas prioritásra emeli.
4. Napi egy rövid rhythm-only blokkot választ.
5. A dalgyakorlás előtt alacsonyabb BPM-en priming blokkot ad.
6. Két sikeres nap után kis tempóemelést javasol.

## 6.3 Dalra készülő felhasználó

1. A felhasználó kiválaszt egy Song Trainertől származó dalt és céldátumot.
2. A rendszer szakaszokra bontja a célt.
3. A nehéz refrén és a szükséges chord transition előnyt kap.
4. A terv fenntartó blokkokat is tartalmaz, de nem nyomja el a dalcélt.
5. A céldátum közeledtével több teljes playthrough kerül be.
6. Az utolsó napon nem vezet be új technikát.

## 6.4 Kevés idővel rendelkező felhasználó

1. A felhasználónak csak öt perce van.
2. A rendszer micro-plan módot készít.
3. Nem próbál teljes 30 perces tervet öt percbe zsúfolni.
4. Egy fontos fókusz és egy rövid sikerélmény kerül be.
5. A kimaradt maintenance blokk nem számít hibának.

## 6.5 Kihagyott hét

1. A felhasználó egy hétig nem gyakorol.
2. A terv státusza nem válik büntető állapottá.
3. Visszatéréskor readiness check vagy könnyebb első nap készül.
4. A rendszer nem feltételez automatikus készségvesztést.
5. Az első eredmények alapján újrakalibrál.

## 6.6 Kézi tervmódosítás

1. A felhasználó nem szereti a kiválasztott gyakorlatot.
2. Megnyitja a helyettesítést.
3. A rendszer csak azonos célt és kompatibilis capabilityt támogató alternatívákat mutat.
4. A választást tartós preferenciaként opcionálisan elmentheti.
5. A jövőbeni tervek figyelembe veszik ezt.

---

# 7. Funkcionális követelmények

## 7.1 Tervgenerálás

A rendszer legyen képes:

- 1–8 hetes tervet készíteni;
- napi 5–90 perces időkeretet kezelni;
- heti 1–7 napot kezelni;
- változó napi időkeretet kezelni;
- több célt kezelni prioritással;
- starter tervet készíteni evidence nélkül;
- cél- és skill-alapú tervet készíteni evidence-szel;
- dalcélt integrálni;
- offline gyakorlatot preferálni offline módban;
- tervelőnézetet készíteni mentés előtt;
- validációs hibát érthetően megjeleníteni;
- determinisztikusan újragenerálni azonos input és policy verzió mellett.

## 7.2 Napi terv

Egy `PracticeDay` tartalmazhat:

- optional readiness check;
- warmup;
- primary focus;
- secondary focus;
- repertoire/song;
- maintenance/review;
- free play;
- reflection;
- rest vagy recovery marker.

Nem kötelező minden kategóriát minden nap használni.

## 7.3 Blokk

Minden blokk tartalmazza:

- stabil ID;
- block kind;
- target skill;
- source exercise reference;
- duration vagy repetition prescription;
- effective BPM;
- difficulty variation;
- success criteria;
- progress rule;
- regression rule;
- substitution set;
- evidence refs;
- reason codes;
- offline availability;
- device capability requirement;
- estimated cognitive és physical load;
- optional song range;
- optional tutor note.

## 7.4 Adaptáció

A rendszer adaptálhat:

- BPM-et;
- loop hosszát;
- repetitionszámot;
- scoring strictness profilt;
- difficulty variationt;
- blokkidőt korlátozott tartományban;
- blokk sorrendjét;
- következő megjelenés dátumát;
- exercise helyettesítést;
- heti fókuszarányt.

Nem adaptálhat csendben aktív session közben.

## 7.5 Tervfelülvizsgálat

Felülvizsgálat történhet:

- session után, ha erős safety signal érkezik;
- napi terv végén;
- hét végén;
- célváltozáskor;
- availability változáskor;
- új dal kiválasztásakor;
- manuális kérésre;
- hosszabb kihagyás után.

## 7.6 Helyettesítés

Helyettesítés oka lehet:

- gyakorlat nem tetszik;
- dal asset hiányzik;
- eszközcapability hiányzik;
- tuning nem kompatibilis;
- túl nehéz;
- túl könnyű;
- kényelmetlen;
- időkeret rövidült;
- offline állapot;
- accessibility igény.

## 7.7 Tervállapot

Támogatott státuszok:

```text
draft
active
paused
completed
archived
superseded
cancelled
```

Egyszerre alapértelmezetten egy aktív elsődleges terv legyen. Kiegészítő event- vagy dalterv csak explicit multi-plan támogatással engedélyezhető később.

---

# 8. Célarchitektúra

```text
lib/features/practice_generator/
├── domain/
│   ├── id/
│   │   ├── practice_plan_id.dart
│   │   ├── practice_day_id.dart
│   │   ├── practice_block_id.dart
│   │   ├── practice_goal_id.dart
│   │   └── plan_revision_id.dart
│   ├── model/
│   │   ├── practice_generation_request.dart
│   │   ├── practice_goal.dart
│   │   ├── learner_constraints.dart
│   │   ├── weekly_availability.dart
│   │   ├── skill_evidence.dart
│   │   ├── skill_estimate.dart
│   │   ├── practice_catalog_snapshot.dart
│   │   ├── exercise_candidate.dart
│   │   ├── exercise_prescription.dart
│   │   ├── adaptive_practice_plan.dart
│   │   ├── practice_day.dart
│   │   ├── practice_block.dart
│   │   ├── plan_revision.dart
│   │   ├── plan_change_set.dart
│   │   ├── practice_outcome.dart
│   │   └── review_item.dart
│   ├── policy/
│   │   ├── priority_policy.dart
│   │   ├── time_allocation_policy.dart
│   │   ├── scheduling_policy.dart
│   │   ├── progression_policy.dart
│   │   ├── spaced_repetition_policy.dart
│   │   ├── missed_day_policy.dart
│   │   └── safety_policy.dart
│   ├── service/
│   │   ├── plan_validator.dart
│   │   ├── priority_engine.dart
│   │   ├── candidate_selector.dart
│   │   ├── time_budget_allocator.dart
│   │   ├── weekly_scheduler.dart
│   │   ├── plan_compiler.dart
│   │   └── plan_diff.dart
│   └── repository/
│       ├── practice_plan_repository.dart
│       ├── practice_evidence_repository.dart
│       └── plan_policy_repository.dart
├── application/
│   ├── controller/
│   │   ├── plan_generator_controller.dart
│   │   ├── active_plan_controller.dart
│   │   ├── today_plan_controller.dart
│   │   └── plan_revision_controller.dart
│   ├── usecase/
│   │   ├── create_practice_plan.dart
│   │   ├── revise_practice_plan.dart
│   │   ├── record_practice_outcome.dart
│   │   ├── substitute_practice_block.dart
│   │   ├── pause_practice_plan.dart
│   │   └── resume_practice_plan.dart
│   ├── port/
│   │   ├── skill_snapshot_reader.dart
│   │   ├── practice_catalog_reader.dart
│   │   ├── song_goal_reader.dart
│   │   ├── analysis_evidence_reader.dart
│   │   ├── vision_evidence_reader.dart
│   │   └── planner_assist_gateway.dart
│   └── service/
│       ├── evidence_aggregator.dart
│       ├── generation_orchestrator.dart
│       └── outcome_ingestion_service.dart
├── data/
│   ├── local/
│   │   ├── local_practice_plan_repository.dart
│   │   ├── practice_plan_serializer.dart
│   │   └── practice_plan_migrator.dart
│   ├── adapter/
│   │   ├── legacy_learn_catalog_adapter.dart
│   │   ├── practice_engine_catalog_adapter.dart
│   │   ├── progress_evidence_adapter.dart
│   │   ├── tutor_skill_snapshot_adapter.dart
│   │   ├── analysis_evidence_adapter.dart
│   │   └── vision_evidence_adapter.dart
│   └── ai/
│       ├── remote_planner_assist_gateway.dart
│       ├── fake_planner_assist_gateway.dart
│       └── planner_schema.dart
├── presentation/
│   ├── screens/
│   │   ├── plan_setup_screen.dart
│   │   ├── plan_preview_screen.dart
│   │   ├── weekly_plan_screen.dart
│   │   ├── today_plan_screen.dart
│   │   ├── plan_change_review_screen.dart
│   │   └── plan_settings_screen.dart
│   └── widgets/
│       ├── practice_goal_picker.dart
│       ├── availability_editor.dart
│       ├── plan_day_card.dart
│       ├── plan_block_card.dart
│       ├── plan_reason_sheet.dart
│       ├── evidence_badge.dart
│       └── block_substitution_sheet.dart
└── public.dart
```

## 8.1 Függőségi szabályok

- `domain` nem importál Fluttert, Riverpodot, Dio-t vagy más feature belső fájlt.
- `application` kizárólag portokon keresztül olvas más feature-ből.
- `data/adapter` importálhat más feature `public.dart` API-t.
- `presentation` nem férhet közvetlenül repositoryhoz.
- az AI gateway nem írhat tervet repositoryba;
- a validator minden mentés előtt kötelező;
- a compiler csak validált plan revisiont fordíthat végrehajtható lépéssé.

## 8.2 Public API

A `public.dart` csak stabil szerződéseket exportáljon:

```text
PracticeGenerationRequest
AdaptivePracticePlan
PracticePlanSummary
PracticeBlockSummary
ActivePlanReader
TodayPlanReader
PlanOutcomeWriter
PracticePlanProposalAdapter
```

Ne exportáljon:

- belső Riverpod notifiereket;
- serializer implementationt;
- AI promptot;
- policy belső súlyokat;
- data adaptert;
- presentation widgetet.

---

# 9. Domain azonosítók és verziózás

## 9.1 Typed ID-k

Minden azonosító külön value object legyen vagy legalább stabil, validált wrapper.

```dart
final class PracticePlanId {
  const PracticePlanId(this.value);
  final String value;
}
```

Az ID:

- nem lehet üres;
- nem tartalmazhat path karaktert;
- JSON round-trip stabil;
- ne függjön display title-től;
- generálása injektálható `IdGenerator` használatával történjen.

## 9.2 Schema version

A teljes terv és a fő beágyazott dokumentumok rendelkezzenek schema versionnel.

```text
AdaptivePracticePlan.schemaVersion
PracticeGenerationRequest.schemaVersion
ExercisePrescription.schemaVersion
PracticeOutcome.schemaVersion
```

## 9.3 Policy version

A terv külön rögzítse:

- priority policy version;
- allocation policy version;
- scheduling policy version;
- progression policy version;
- catalog revision;
- skill taxonomy version;
- model assist version, ha volt.

Azonos input, azonos seed és azonos policy verzió esetén a determinisztikus terv legyen reprodukálható.

## 9.4 Revision

A terv nem írható felül történet nélkül.

```dart
final class PlanRevision {
  const PlanRevision({
    required this.id,
    required this.planId,
    required this.number,
    required this.createdAt,
    required this.reason,
    required this.changeSet,
    required this.snapshot,
  });
}
```

A revision number monoton nő.

---

# 10. PracticeGenerationRequest

## 10.1 Kötelező mezők

```dart
final class PracticeGenerationRequest {
  const PracticeGenerationRequest({
    required this.id,
    required this.createdAt,
    required this.locale,
    required this.goals,
    required this.availability,
    required this.constraints,
    required this.planHorizon,
    required this.generationMode,
    required this.seed,
  });
}
```

## 10.2 Generation mode

```text
starter
adaptive
songGoal
maintenance
returningAfterBreak
microPlan
assessment
```

A módot a rendszer javasolhatja, de a felhasználó lássa és módosíthassa.

## 10.3 Plan horizon

A horizon:

- minimum 1 nap;
- maximum alapértelmezetten 8 hét;
- kezdő első tervnél javasolt 1–2 hét;
- hosszabb terv periodikus review pontokat tartalmazzon;
- céldátum után automatikusan ne generáljon végtelen folytatást.

## 10.4 Determinisztikus seed

A seed célja:

- tesztelhetőség;
- azonos jelöltek közötti stabil tie-break;
- változatosság kontrollált biztosítása.

A seed nem használható pedagógiai szabály megkerülésére.

---

# 11. Célmodell

## 11.1 PracticeGoal

```dart
final class PracticeGoal {
  const PracticeGoal({
    required this.id,
    required this.type,
    required this.priority,
    required this.status,
    required this.createdAt,
    this.targetDate,
    this.skillIds = const [],
    this.songReference,
    this.metricTarget,
    this.userNote,
  });
}
```

## 11.2 Goal típusok

```text
foundation
rhythm
chordChanges
strummingPattern
speed
songPerformance
repertoireMaintenance
musicTheory
technique
confidence
custom
```

A `custom` cél önmagában nem végrehajtható. Goal normalizernek stabil skill vagy song targetté kell alakítania, és bizonytalanság esetén megerősítést kérnie.

## 11.3 Prioritás

```text
primary
secondary
maintenance
optional
```

Egyszerre javasolt maximum:

- 1 primary;
- 1–2 secondary;
- több maintenance.

Túl sok primary goal esetén a UI kérjen rendezést vagy ajánljon fókuszciklust.

## 11.4 Metric target

Példák:

- stabil BPM tartomány;
- timing error threshold;
- chord transition success;
- song section completion;
- clean repetition count;
- lesson pass;
- practice frequency.

A target mindig tartalmazzon:

- metric code;
- desired direction;
- threshold;
- measurement capability;
- minimum confidence;
- minimum sample count;
- optional target date.

## 11.5 Goal lifecycle

```text
proposed
active
paused
achieved
abandoned
superseded
```

A rendszer nem jelölhet célt achieved állapotba egyetlen alacsony confidence session alapján.

---

# 12. LearnerConstraints és preferenciák

## 12.1 Kötelező constraint kategóriák

```text
time
schedule
equipment
tuning
capo
deviceCapability
connectivity
contentAccess
physicalComfort
accessibility
preference
avoidance
```

## 12.2 Idő és schedule

A weekly availability naponta tartalmazza:

- available vagy unavailable;
- preferred start window, opcionális;
- minimum minutes;
- target minutes;
- maximum minutes;
- hard vagy soft constraint;
- day-specific note.

A generátor ne feltételezze, hogy minden nap ugyanannyi idő van.

## 12.3 Eszköz és gitár

Figyelembe vehető:

- acoustic/electric/classical;
- standard vagy alternatív tuning;
- capo;
- balkezes mód;
- pick/fingerstyle preference;
- erősítő vagy backing track elérhetőség;
- mikrofon capability;
- kamera capability;
- fejhallgató preference.

## 12.4 Fizikai komfort

A constraint tartalmazhat:

- kerülendő barre chord;
- rövidített session;
- maximális folyamatos játékidő;
- gyakori pihenő;
- váll-, csukló- vagy ujjkényelmetlenség önbevallása;
- standing/sitting preference.

Ez nem diagnózis. A self-report hard safety constraintként kezelhető.

## 12.5 Preferencia és avoid list

A felhasználó megadhat:

- kedvelt stílust;
- kedvelt dalokat;
- kedvelt gyakorlatmódot;
- nem kedvelt click hangot;
- kerülendő gyakorlatot;
- free play arányt;
- feedback sűrűséget;
- gamification preference-t.

Hard avoid csak explicit user actionből jöhet. A modell nem tehet gyakorlatot hard avoid listára.

## 12.6 Constraint konfliktus

Példa:

- cél: gyors alternate picking;
- hard constraint: nincs pick használat.

A rendszer ne generáljon érvénytelen tervet. Mutasson konfliktust és kérjen cél- vagy constraint módosítást.

---

# 13. SkillEvidence és SkillEstimate

## 13.1 Evidence források

```text
practiceSession
songSession
audioAnalysis
visionAnalysis
lessonProgress
selfAssessment
tutorConfirmed
manualTeacherInput
legacyProgress
```

## 13.2 SkillEvidence

```dart
final class SkillEvidence {
  const SkillEvidence({
    required this.id,
    required this.skillId,
    required this.source,
    required this.observedAt,
    required this.value,
    required this.confidence,
    required this.sampleCount,
    required this.provenance,
    this.contextTags = const {},
    this.validUntil,
  });
}
```

## 13.3 Evidence szabályok

- confidence 0 és 1 között;
- sample count nem lehet negatív;
- observedAt nem lehet indokolatlanul jövőbeli;
- validUntil után az evidence stale;
- ugyanaz az outcome ne kerüljön be kétszer;
- raw audio és raw video nem része;
- self-assessment külön source;
- discomfort self-report nem átlagolható el teljesítménymetrikával.

## 13.4 SkillEstimate

```dart
final class SkillEstimate {
  const SkillEstimate({
    required this.skillId,
    required this.level,
    required this.uncertainty,
    required this.state,
    required this.lastObservedAt,
    required this.evidenceIds,
    required this.trend,
  });
}
```

State:

```text
unknown
initial
emerging
stable
strong
stale
conflicted
```

## 13.5 Aggregáció

Az aggregátor vegye figyelembe:

- source reliability;
- confidence;
- recency;
- sample count;
- context compatibility;
- measurement version;
- outlier detection;
- repeated evidence;
- trend.

Egyetlen session ne változtathassa meg korlátlanul a skill levelt.

## 13.6 Konfliktus

Példák:

- Practice Engine jó timingot mér, Analyze rosszat;
- egy dalban jó chord change, másikban rossz;
- vision low confidence, audio high confidence;
- self-report haladónak mondja, evidence kezdő szintet mutat.

Konfliktus esetén:

- `conflicted` vagy magas uncertainty;
- assessment vagy ismétlés;
- nincs agresszív progresszió;
- UI megmutathatja, hogy több adat szükséges.

## 13.7 Privacy

A generátor csak a szükséges, származtatott evidence kivonatot kapja. A Tutor vagy AI backend felé küldött kontextus külön redactionen megy át.

---

# 14. Practice catalog és capability snapshot

## 14.1 PracticeCandidate

A generátor nem közvetlenül `PracticeDefinition` objektumokat rangsorol. Először normalizált jelöltet használ.

```dart
final class ExerciseCandidate {
  const ExerciseCandidate({
    required this.exerciseId,
    required this.source,
    required this.skillTargets,
    required this.prerequisites,
    required this.supportedDurations,
    required this.difficultyRange,
    required this.capabilities,
    required this.loadProfile,
    required this.offlineAvailable,
    required this.contentRevision,
  });
}
```

## 14.2 Forrás

```text
practiceCatalog
legacyLesson
songRange
analysisHotspot
visionCalibration
assessment
freePractice
reflection
rest
```

## 14.3 Capability

Példák:

```text
requiresMicrophone
requiresCamera
requiresBackingTrack
requiresSongAsset
supportsTempo
supportsLoop
supportsDirectionScoring
supportsChordScoring
supportsPitchScoring
supportsOffline
supportsLeftHandedUi
supportsReducedMotion
```

## 14.4 Load profile

A load profile legalább:

- cognitive load;
- fretting-hand load;
- picking-hand load;
- repetition load;
- novelty;
- concentration demand.

Kezdetben ordinal skála használható:

```text
low
medium
high
```

A skála pedagógiai proxy, nem egészségügyi mérés.

## 14.5 Katalógus snapshot

A generáláskor használt katalógus revisiont rögzíteni kell. Ha később egy exercise eltűnik vagy megváltozik, a terv stale blockot jelezzen és helyettesítést kérjen.

## 14.6 Jelölt kizárása

Kizárási ok:

```text
missingPrerequisite
hardAvoid
unsupportedDevice
wrongTuning
missingAsset
offlineUnavailable
contentLocked
safetyConflict
durationIncompatible
localeUnavailable
revisionMissing
```

A kizárás reason code-ja diagnosztikára és UI-ra elérhető legyen.

---

# 15. ExercisePrescription

## 15.1 Cél

Az exercise reference önmagában nem elég. A prescription írja le, hogyan kell ma végrehajtani.

## 15.2 Modell

```dart
final class ExercisePrescription {
  const ExercisePrescription({
    required this.exerciseReference,
    required this.duration,
    required this.targetSkills,
    required this.difficulty,
    required this.successCriteria,
    required this.progressionRule,
    required this.regressionRule,
    required this.fallbacks,
    this.tempo,
    this.loopRange,
    this.repetitionTarget,
    this.restAfter,
  });
}
```

## 15.3 Success criteria

Lehetséges típusok:

```text
completion
minimumAccuracy
minimumStableRepetitions
timingWindow
minimumConfidence
songRangeCompletion
selfRatedComfort
assessmentOnly
```

Az assessment block nem adhat hamis pass/fail minősítést.

## 15.4 Tempo prescription

A tempo tartalmazhat:

- start BPM;
- target BPM;
- step policy;
- maximum within block;
- fallback BPM;
- source metric;
- calibration confidence.

A generátor ne használjon önkényes BPM-et, ha az exercise nem támogat tempót.

## 15.5 Repetition prescription

A repetition lehet:

- fixed count;
- clean streak count;
- time-boxed;
- loop count;
- until confidence threshold, maximum limittel.

Nyílt végű „addig gyakorold, amíg jó nem lesz” prescription tiltott.

## 15.6 Rest

Magas ismétlésterhelésű blokk után a prescription tartalmazhat rövid restet. A rest ne számítson aktív playing időnek, de a terv teljes elapsed idejébe beleszámíthat.

---

# 16. AdaptivePracticePlan domain

## 16.1 Tervmodell

```dart
final class AdaptivePracticePlan {
  const AdaptivePracticePlan({
    required this.id,
    required this.schemaVersion,
    required this.status,
    required this.title,
    required this.createdAt,
    required this.startDate,
    required this.endDate,
    required this.goals,
    required this.days,
    required this.activeRevisionId,
    required this.generationProvenance,
    required this.policyVersions,
  });
}
```

## 16.2 PracticeDay

```dart
final class PracticeDay {
  const PracticeDay({
    required this.id,
    required this.localDate,
    required this.status,
    required this.timeBudget,
    required this.blocks,
    required this.primaryFocusSkillIds,
    required this.reasonCodes,
  });
}
```

## 16.3 PracticeBlock

```dart
final class PracticeBlock {
  const PracticeBlock({
    required this.id,
    required this.kind,
    required this.order,
    required this.prescription,
    required this.reasonCodes,
    required this.evidenceRefs,
    required this.status,
    required this.estimatedElapsed,
  });
}
```

## 16.4 Block kind

```text
readiness
warmup
assessment
primaryFocus
secondaryFocus
maintenance
song
freePlay
reflection
rest
cooldown
```

## 16.5 Block status

```text
planned
ready
inProgress
completed
skipped
substituted
unavailable
expired
```

## 16.6 Terv snapshot

A plan revision teljes snapshotot tartalmazhat, de a repository deduplikálhat implementation szinten. Domain szinten a revision visszaállítható legyen.

## 16.7 Immutable múlt

Befejezett day és block eredménye ne változzon egy új tervgenerálás miatt. Új revision csak jövőbeli vagy még nem végrehajtott blokkot módosíthat, kivéve explicit adatkorrekciót audit loggal.

---

# 17. PlanValidator

## 17.1 Kötelező invariánsok

A validator ellenőrzi:

- plan date range érvényes;
- day date egyedi és rendezett;
- block ID egyedi;
- block order egyedi napon belül;
- duration pozitív;
- összidő megfelel a hard maximum constraintnek;
- referenced exercise létezik;
- content revision elérhető;
- prerequisite teljesül vagy assessment/simplified variation használható;
- hard avoid nem sérül;
- capability rendelkezésre áll;
- offline constraint nem sérül;
- tuning kompatibilis;
- safety constraint nem sérül;
- success criteria mérhető;
- progression és regression bounded;
- nincs végtelen ismétlés;
- nincs egymást követő túl sok high-load blokk;
- rest szabály teljesül;
- plan horizon maximumon belül;
- completed múlt nem változott;
- reason és provenance rendelkezésre áll.

## 17.2 Validation severity

```text
info
warning
error
fatal
```

Mentés:

- info engedett;
- warning felhasználói review-val engedett;
- error nem engedett;
- fatal programozási vagy schema hiba.

## 17.3 Repair

Deterministic repair megpróbálhatja:

- blokk rövidítését;
- alacsonyabb prioritású blokk eltávolítását;
- fallback exercise választását;
- rest beillesztését;
- tempo clampet;
- song blokk offline alternatívára cserélését.

Repair maximum iterációval fusson. Végtelen repair loop tiltott.

## 17.4 Felhasználói módosítás validálása

A kézi szerkesztés sem kerülheti meg a validatort. A UI azonnal mutassa a konfliktust.

---

# 18. Generálási pipeline

```text
PracticeGenerationRequest
        ↓
Request validation
        ↓
Capability snapshot
        ↓
Goal normalization
        ↓
Evidence aggregation
        ↓
Skill priority calculation
        ↓
Candidate generation
        ↓
Hard filtering
        ↓
Time budget allocation
        ↓
Weekly scheduling
        ↓
Prescription construction
        ↓
Spaced repetition insertion
        ↓
Enjoyment / maintenance balancing
        ↓
Plan validation
        ↓
Deterministic repair
        ↓
Optional AI explanation
        ↓
Draft preview
        ↓
User confirmation
        ↓
Persist active revision
```

## 18.1 Pipeline stage contract

Minden stage:

- explicit inputot és outputot kap;
- nem olvas globális providert;
- cancellable legyen;
- progress eventet adhat;
- strukturált failure-t adjon;
- determinisztikus legyen azonos input mellett;
- logoljon érzékeny adat nélkül;
- mérhető durationnel rendelkezzen.

## 18.2 Progress

Lehetséges eventek:

```text
validatingRequest
loadingEvidence
buildingSkillSnapshot
loadingCatalog
rankingPriorities
allocatingTime
schedulingWeek
validatingPlan
writingExplanation
readyForPreview
```

## 18.3 Cancellation

Cancellation esetén:

- részleges terv ne legyen aktív;
- temp erőforrás felszabadul;
- AI request megszakad;
- repository nem ír;
- új generálás indítható.

---

# 19. SkillPriorityEngine

## 19.1 Bemenetek

- active goals;
- skill estimates;
- prerequisite graph;
- recent practice coverage;
- review due state;
- song hotspotok;
- user preference;
- available exercise capability;
- safety constraints;
- plan horizon.

## 19.2 Priority komponensek

A policy verziózott, normalizált komponenseket használjon:

```text
goalAlignment
skillGap
prerequisiteImportance
evidenceConfidence
recencyNeed
reviewDue
transferValue
songCriticality
userPreference
coverageDebt
fatiguePenalty
noveltyPenalty
```

A formula ne legyen szétszórva a kódban.

Példa konceptuális forma:

```text
priority =
  positive weighted factors
  - fatigue penalty
  - novelty penalty
  - uncertainty penalty
```

A konkrét súlyok policy configból jönnek és teszttel védettek.

## 19.3 Uncertainty

Magas uncertainty esetén a rendszer:

- ne tekintse automatikusan nagy skill gapnek;
- választhat assessment blokkot;
- használjon konzervatív nehézséget;
- csökkentse a progresszió sebességét.

## 19.4 Prerequisite

Ha egy cél magasabb szintű skillt igényel, de prerequisite hiányzik:

- prerequisite kap prioritást;
- a célhoz kapcsolódó motiváló blokk megmaradhat könnyített formában;
- a UI magyarázza el a kapcsolatot;
- a rendszer ne zárja ki teljesen a felhasználó választott dalát.

## 19.5 Coverage debt

A maintenance skill prioritása nőhet, ha hosszú ideje nem szerepelt a tervben. Coverage debt nem írhatja felül a safety vagy hard time constraintet.

## 19.6 Tie-break

Azonos score esetén stabil tie-break:

1. primary goal;
2. prerequisite;
3. review due;
4. alacsonyabb load;
5. régebben gyakorolt;
6. seed-alapú stabil választás.

---

# 20. CandidateSelector

## 20.1 Jelöltkészlet

Skillenként több candidate gyűjthető:

- direkt drill;
- rhythm-only variation;
- chord-only variation;
- song range;
- lesson;
- assessment;
- free play prompt;
- maintenance exercise.

## 20.2 Hard filter

A hard filter eltávolítja az érvénytelen jelölteket.

## 20.3 Soft ranking

Soft faktorok:

- célilleszkedés;
- skill coverage;
- nehézségilleszkedés;
- user preference;
- változatosság;
- mérhetőség;
- offline availability;
- setup cost;
- session flow;
- previous engagement;
- recent overuse.

## 20.4 Diversity

A rendszer kerülje:

- ugyanazt a gyakorlatot minden nap;
- ugyanazt a dalrészt túl sokszor;
- kizárólag egy modality használatát;
- egymás után több azonos high-load blokkot.

Diversity nem csökkentheti indokolatlanul a cél relevanciáját.

## 20.5 Exploration

Kis arányban választhat új, kompatibilis candidate-et, de:

- csak soft preference esetén;
- nem critical goal előtt;
- nem magas safety risk mellett;
- mindig fallbackkel;
- mérhető eredménnyel.

---

# 21. TimeBudgetAllocator

## 21.1 Budget típusok

```text
activePlaying
elapsedSession
rest
setup
reflection
```

A felhasználó által megadott napi idő alapértelmezetten elapsed session budget.

## 21.2 Minimum és maximum

Policy állítsa be:

- minimum block duration;
- maximum block duration;
- warmup maximum arány;
- reflection maximum;
- high-load continuous maximum;
- setup reserve;
- rounding increment.

## 21.3 Rövid tervek

### 5 perc

- egy rövid readiness vagy warmup;
- egy primary focus micro-block;
- opcionális egyperces fun finish.

### 10 perc

- rövid warmup;
- elsődleges fókusz;
- song vagy free play.

### 20–30 perc

- warmup;
- primary focus;
- secondary vagy maintenance;
- song;
- rövid reflection.

Ezek sablonok, nem merev hardcode-ok.

## 21.4 Allocation algoritmus

1. hard reserve és rest levonása;
2. primary minimum biztosítása;
3. goal priority szerinti súlyelosztás;
4. minimum block clamp;
5. túl kicsi blokkok összevonása vagy elhagyása;
6. enjoyment minimum, ha policy engedi;
7. duration rounding;
8. final exact budget repair.

## 21.5 Időcsökkentés aznap

Ha a felhasználó a napi tervet rövidíti:

- primary focus megőrzése;
- optional és alacsony maintenance eltávolítása;
- song blokk rövidített range-re cserélése;
- semmi ne legyen 30 másodperces értelmetlen töredék;
- változáslista készüljön.

## 21.6 Időnövelés

Többletidő esetén ne csak a legnehezebb blokkot hosszabbítsa. Előnyben:

- több song playthrough;
- free play;
- review due;
- rövid secondary focus;
- pihenő.

---

# 22. WeeklyScheduler

## 22.1 Cél

A scheduler a blockokat napokra osztja úgy, hogy a terv ne legyen ismétlődő vagy túlterhelő.

## 22.2 Napi fókusz

Alapértelmezés:

- maximum 1 primary focus skill;
- maximum 1 secondary focus skill;
- maintenance blokkok kis adagban;
- song blokk több skillt integrálhat.

## 22.3 Terhelésváltás

A scheduler kerülje:

- két egymást követő magas fretting-hand load napot;
- minden nap speed buildet;
- új skill és nehéz dalrész egyidejű csúcsterhelését;
- hosszú session utáni újabb kötelező hosszú napot.

## 22.4 Rest day

Rest day lehet:

- teljes pihenő;
- hallgatási/theory blokk;
- rövid reflection;
- optional free play.

A rest day nem számít kihagyásnak.

## 22.5 Céldátum periodizáció

Song goal esetén fázisok:

```text
foundation
section acquisition
section consolidation
full run integration
performance simulation
light review
```

A céldátum előtti utolsó időszakban a rendszer ne vezessen be nagy új technikai terhelést.

## 22.6 Heti review

A hét végén:

- eredményösszegzés;
- evidence frissítés;
- coverage ellenőrzés;
- goal progress;
- tervváltozás javaslat;
- user confirmation, ha jelentős változás.

---

# 23. Progression és regression policy

## 23.1 Alapelv

A nehézség csak elegendő és megbízható bizonyíték után változhat.

## 23.2 Progression signal

Példák:

- több sikeres attempt külön sessionben;
- stabil score;
- confidence megfelelő;
- nincs comfort warning;
- célhoz releváns javulás;
- minimum sample count.

## 23.3 Lehetséges progresszió

- BPM kis emelése;
- loop hossz növelése;
- több chord change;
- off-beat hozzáadása;
- simplified variationről full variationre váltás;
- scoring strictness kis emelése;
- song range bővítése;
- kevesebb vizuális segítség.

## 23.4 Boundok

A policy rögzítse:

- maximum BPM emelés per revision;
- maximum relatív emelés per nap;
- maximum difficulty step;
- minimum sikeres session;
- cooldown progressziók között.

A konkrét értékek configban legyenek, ne több fájlban.

## 23.5 Regression signal

- ismételt alacsony teljesítmény;
- timing szétesés;
- confidence magas és hiba konzisztens;
- user „too hard” jelzés;
- comfort warning;
- hosszabb kihagyás utáni readiness eredmény.

## 23.6 Regression action

- BPM csökkentés;
- loop rövidítés;
- chord gating ideiglenes egyszerűsítése;
- rhythm-only vagy chord-only bontás;
- kevesebb event;
- több rest;
- másik exercise;
- assessment.

A UI ne „visszaesésként”, hanem megfelelőbb kiindulási pontként kommunikálja.

## 23.7 Egy session elleni védelem

Alapértelmezetten egyetlen rossz session nem írja át a teljes hetet. Kivétel:

- safety signal;
- user explicit too-hard;
- exercise unavailable;
- technikai hiba.

---

# 24. Spaced repetition és review queue

## 24.1 ReviewItem

```dart
final class ReviewItem {
  const ReviewItem({
    required this.id,
    required this.skillOrContentRef,
    required this.dueDate,
    required this.interval,
    required this.strength,
    required this.lastOutcome,
    required this.reason,
  });
}
```

## 24.2 Mit lehet review-zni

- chord transition;
- strumming pattern;
- lesson;
- song section;
- scale pattern;
- technical cue;
- tuning routine;
- metronome subdivision.

## 24.3 Ütemezés

A policy használjon egyszerű, magyarázható intervallumot. Nem szükséges komplex flashcard algoritmust vakon átvenni.

A review időpont függjön:

- stabilitástól;
- korábbi eredménytől;
- skill fontosságtól;
- goal közelségétől;
- utolsó gyakorlástól;
- uncertaintytől.

## 24.4 Sikertelen review

Sikertelen review esetén:

- rövidebb következő intervallum;
- könnyebb prescription;
- nem automatikus nagy büntetés;
- conflict vagy measurement failure külön kezelése.

## 24.5 Review budget

A review queue nem töltheti ki a teljes napi időt. Policy maximum arányt adjon, kivéve kifejezett maintenance mód.

---

# 25. PlanCompiler és végrehajtás

## 25.1 Compiler szerepe

A kanonikus tervet konkrét alkalmazásműveletekre fordítja.

```text
PracticeBlock
        ↓
PlanCompiler
        ↓
CompiledPlanStep
        ├── OpenPracticeDefinition
        ├── OpenSongRange
        ├── OpenTuner
        ├── OpenVisionCalibration
        ├── StartReflection
        └── RestStep
```

## 25.2 CompiledPlanStep

Tartalmazza:

- exact public route/action;
- source revision;
- exercise snapshot reference;
- config;
- expected outcome contract;
- availability check;
- stale detection;
- fallback action.

## 25.3 Indítás

A Today screen:

1. validálja az aktuális blockot;
2. compile-olja;
3. megmutatja a rövid preview-t;
4. user actionre navigál;
5. visszatéréskor outcome-ot fogad;
6. idempotensen lezárja a blockot;
7. a következő blokkot ajánlja.

## 25.4 Stale block

Block stale, ha:

- exercise revision hiányzik;
- dal módosult;
- range törlődött;
- capability megváltozott;
- tuning változott;
- plan revision már nem aktív;
- block dátuma túl régi;
- goal megszűnt.

Stale block nem indulhat automatikusan. Helyettesítés vagy revízió szükséges.

## 25.5 Idempotencia

Ugyanaz a session result nem zárhatja le kétszer a blockot. Használjon `outcomeId` és `blockExecutionId` értéket.

---

# 26. Outcome ingestion és adaptáció

## 26.1 PracticeOutcome

Normalizált outcome:

```dart
final class PracticeOutcome {
  const PracticeOutcome({
    required this.id,
    required this.planId,
    required this.revisionId,
    required this.dayId,
    required this.blockId,
    required this.source,
    required this.startedAt,
    required this.completedAt,
    required this.activeDuration,
    required this.completionState,
    required this.metricEvidence,
    required this.userFeedback,
  });
}
```

## 26.2 Completion state

```text
completed
partial
skipped
cancelled
failedTechnical
unavailable
```

A skip önmagában nem performance failure.

## 26.3 User feedback

Opcionális gyors feedback:

```text
tooEasy
rightLevel
tooHard
uncomfortable
notEnjoyable
technicalProblem
```

Az `uncomfortable` azonnali safety hatást válthat ki.

## 26.4 Outcome feldolgozás

1. schema és idempotencia validáció;
2. block/revision egyezés;
3. metric evidence normalizálás;
4. user feedback prioritás;
5. review item frissítés;
6. skill estimate candidate frissítés;
7. adaptációs döntés;
8. plan change proposal;
9. persistence;
10. UI summary.

## 26.5 Jelentős és kisebb változás

Kisebb, automatikusan alkalmazható, ha user policy engedi:

- következő review dátum;
- egy blokk BPM-je kis boundon belül;
- azonos exercise easy variation;
- optional blokk sorrend.

Jelentős, megerősítést igényel:

- primary focus változik;
- napi idő változik;
- blokk törlődik több napra;
- song goal arány jelentősen változik;
- plan horizon változik;
- új camera requirement;
- content access változás;
- új hard constraint.

## 26.6 PlanChangeSet

Minden change set tartalmazza:

- before és after érték;
- change type;
- reason code;
- evidence refs;
- confidence;
- user confirmation requirement;
- reversible flag.

---

# 27. Missed-day, pause és visszatérés

## 27.1 Missed day

Egy nap missed, ha a nap lezárult és nem volt befejezett blokk. A rest day nem missed.

## 27.2 Policy lehetőségek

```text
leaveAsHistory
movePrimaryOnly
compressNextDay
rescheduleWithinWeek
skipWithoutChange
regenerateRemainingWeek
```

Alapértelmezés:

- ne mozgassa át automatikusan az összes blokkot;
- primary blokk reschedule javasolható;
- optional blokk elhagyható;
- maximum daily budget nem sérülhet.

## 27.3 Plan pause

Pause esetén:

- jövőbeli notification opcionálisan leáll;
- napok nem halmozódnak;
- active revision megmarad;
- outcome history megmarad;
- resume dátumkorrekciót igényel.

## 27.4 Returning after break

Hosszabb kihagyás után:

- availability újraellenőrzés;
- rövid readiness vagy assessment;
- konzervatív első nap;
- régi skill estimate stale lehet;
- nincs automatikus teljes reset;
- új revision készül.

## 27.5 Timezone

A day boundary a felhasználó lokális időzónáját használja. Timezone változás ne duplikáljon vagy veszítsen napot. `Clock` és explicit local date adapter szükséges.

---

# 28. AI-assisted planning

## 28.1 PlannerAssistGateway

```dart
abstract interface class PlannerAssistGateway {
  Stream<PlannerAssistEvent> suggest(
    PlannerAssistRequest request,
    CancellationToken cancellation,
  );
}
```

## 28.2 Megengedett feladatok

- natural-language goalból typed goal proposal;
- rövid tervindoklás;
- change set emberi összefoglalása;
- valid candidate listából alternatíva rangsorolása;
- user preference kivonat;
- motiváló, de nem manipulatív szöveg.

## 28.3 Strukturált schema

A modell csak ID-kat választhat az átadott allowlistből.

Példa:

```json
{
  "goalProposals": [
    {
      "type": "rhythm",
      "skillIds": ["rhythm.offbeat_upstroke"],
      "confidence": 0.82,
      "needsConfirmation": true
    }
  ],
  "explanation": "..."
}
```

## 28.4 Validator

Minden modelloutput:

- JSON schema validáció;
- ID allowlist;
- size limit;
- locale ellenőrzés;
- unsafe content filter;
- prompt injection guard;
- deterministic plan validator.

## 28.5 Cloud failure

Cloud hiba esetén:

- tervgenerálás folytatódik;
- deterministic explanation template használható;
- a user nem veszít inputot;
- nincs részleges aktív terv;
- retry explicit.

## 28.6 Chapter 11 kompatibilitás

A későbbi helyi LLM ugyanazt a `PlannerAssistGateway` interfészt implementálja. A generátor domainjét nem kell újraírni.

---

# 29. UI és UX specifikáció

## 29.1 Belépési pontok

- Home/Practice tab „Create my plan”;
- Progress „Build a plan from my progress”;
- Song detail „Prepare this song”;
- Analyze result „Practice these hotspots”;
- AI Tutor action proposal;
- onboarding utáni starter plan.

## 29.2 Plan setup wizard

Lépések:

1. cél kiválasztása;
2. dal kiválasztása, ha releváns;
3. heti napok és idő;
4. szint vagy „még nem tudom”;
5. equipment/tuning;
6. preferenciák és avoid;
7. comfort/accessibility;
8. összefoglaló és generálás.

A wizard mentse a draftot lokálisan, hogy megszakítás után folytatható legyen.

## 29.3 Generálási képernyő

Mutasson stage-alapú progresszt, ne hamis százalékot, ha nincs megbízható százalék.

Legyen:

- cancel;
- offline/AI státusz;
- hiba és retry;
- visszatérés a requesthez.

## 29.4 Plan preview

Mutassa:

- hetet napokra bontva;
- napi időt;
- primary fókuszt;
- blokklistát;
- „miért ezt?” magyarázatot;
- szükséges capabilityt;
- offline jelzést;
- plan confidence summaryt;
- warningot;
- edit és save actiont.

## 29.5 Weekly plan

- vízszintes vagy függőleges hétlista;
- today kiemelés;
- completed és rest day;
- plan status;
- cél progress;
- review dátum;
- pause/regenerate/settings.

## 29.6 Today screen

Fő elemek:

- hátralévő becsült idő;
- mai fókusz;
- következő block;
- start;
- swap;
- skip;
- shorten today;
- pause plan;
- completed summary.

## 29.7 Block card

Mutassa:

- cím;
- idő;
- BPM vagy difficulty;
- skill;
- reason;
- success criteria;
- required setup;
- fallback;
- status.

## 29.8 Evidence sheet

Ne öntsön nyers metrikatáblát a felhasználóra. Röviden:

- milyen sessionből jött;
- hányszor látszott;
- mennyire biztos;
- mikori adat;
- conflicting-e.

## 29.9 Change review

Mutassa diffként:

- mi változik;
- miért;
- mely napokat érinti;
- időváltozás;
- difficulty változás;
- visszavonhatóság.

## 29.10 Empty és degraded state

- nincs evidence: starter plan;
- nincs practice catalog: recovery error;
- offline AI: deterministic explanation;
- song hiányzik: substitution;
- capability hiányzik: compatible alternative;
- storage hiba: ne aktiváljon elvesző tervet.

## 29.11 Accessibility

- screen reader sorrend;
- nem csak szín jelzi a státuszt;
- minimum touch target;
- reduced motion;
- scalable text;
- rövid és hosszú címek;
- timeline nélkül is használható;
- hangos visszajelzés kikapcsolható;
- balkezes UI támogatás.

---

# 30. Persistence, sync és conflict resolution

## 30.1 Repository

```dart
abstract interface class PracticePlanRepository {
  Future<AppResult<AdaptivePracticePlan?>> getActivePlan();
  Future<AppResult<AdaptivePracticePlan?>> getById(PracticePlanId id);
  Future<AppResult<List<PracticePlanSummary>>> listPlans();
  Future<AppResult<void>> saveDraft(AdaptivePracticePlan plan);
  Future<AppResult<void>> activateRevision(PlanRevision revision);
  Future<AppResult<void>> appendOutcome(PracticeOutcome outcome);
  Future<AppResult<void>> archive(PracticePlanId id);
  Future<AppResult<void>> delete(PracticePlanId id);
}
```

## 30.2 Local-first

Az aktív terv, revisionök és outcome-ok helyben tárolódjanak. A feature ne használjon közvetlen SharedPreferences API-t.

A választott storage implementation:

- verziózott;
- atomikus írást használ;
- checksum vagy korrupciódetektálás;
- partial record recovery;
- bounded history;
- exportálható;
- törölhető.

## 30.3 Draft és aktív terv

A draft külön namespace-ben legyen. Draft generálás vagy szerkesztés nem írhatja felül az aktív tervet.

## 30.4 Sync

Opcionális account sync esetén:

- canonical local revision;
- server version/etag;
- explicit conflict;
- completed history merge csak idempotens ID alapján;
- két eltérő aktív revision automatikus összeolvasztása tiltott;
- user conflict review szükséges.

## 30.5 Retention

Javasolt:

- aktív terv teljes history;
- archivált tervek summary és bounded revision;
- outcome részlet policy szerint;
- raw audio/video nincs;
- user kérésre teljes törlés.

## 30.6 Export

A user exportálhat:

- emberileg olvasható tervet;
- JSON backupot;
- heti summaryt.

Az export ne tartalmazzon secretet vagy belső promptot.

---

# 31. Privacy, safety és etika

## 31.1 Data classification

```text
Public: built-in exercise metadata
User local: goals, plan, availability, preferences
Sensitive: discomfort, accessibility, private song title
Derived performance: skill evidence, metrics, trends
Restricted: auth token, raw audio, raw video
```

## 31.2 Minimal context

AI assist csak a szükséges kivonatot kapja:

- stabil goal codes;
- anonymizált skill summary;
- candidate allowlist;
- constraints;
- locale;
- plan diff.

Nem kap:

- teljes raw session adatot;
- raw audio/video;
- secure storaget;
- fölösleges account adatot;
- más beszélgetés teljes szövegét.

## 31.3 Fájdalom és kényelmetlenség

Az `uncomfortable` feedback:

- blokkolja az automatikus terhelésnövelést;
- javasolja a pihenést;
- felajánlja a terv könnyítését;
- nem diagnosztizál;
- nem bünteti a completiont.

## 31.4 Hallásvédelem

Backing track vagy metronóm esetén a terv nem állíthat automatikusan hangerőt veszélyes szintre. A generátor csak használati javaslatot adhat, volume control a megfelelő audio feature felelőssége.

## 31.5 Manipuláció

Tiltott UX:

- félelemkeltő streak copy;
- hamis sürgősség;
- „elveszíted a fejlődést” állítás;
- túlzó AI-bizonyosság;
- fizetős tartalom rejtett preferálása;
- végtelen session ösztönzése.

## 31.6 Gyermekek

Ha a termék gyermekfelhasználást támogat, külön korhatár-, consent- és adatkezelési policy szükséges. Ez az Epic nem implementál gyermekprofilt feltételezésből.

---

# 32. Teljesítmény és megbízhatóság

## 32.1 Latency célok

Középkategóriás eszközön, lokális adatokkal:

- plan input betöltés: észrevehető UI blokkolás nélkül;
- deterministic 7 napos terv: cél szerint 500 ms alatt;
- 8 hetes terv: cél szerint 2 másodperc alatt;
- preview scroll: stabil 60 fps vagy device capability szerint;
- outcome ingestion: cél szerint 300 ms alatt;
- plan diff: cél szerint 100 ms alatt.

A végleges threshold baseline mérésből származzon.

## 32.2 Isolate

Nagyobb simulation vagy evidence aggregáció isolate-ban futhat, ha profilozás indokolja. Egyszerű domain számítás ne kerüljön indokolatlanul isolate-ba.

## 32.3 Cache

Cache-elhető:

- catalog snapshot;
- skill snapshot;
- candidate matrix;
- plan preview.

Cache key tartalmazza:

- input hash;
- policy versions;
- catalog revision;
- skill taxonomy version;
- locale, ha explanation is cache-elt.

## 32.4 Determinizmus

A current time, random és ID generation injektálható. A generátor tesztben teljesen reprodukálható legyen.

## 32.5 Failure recovery

- storage failure: draft memóriában maradhat, de ne állítsa aktívnak;
- catalog failure: érthető retry;
- evidence failure: starter/conservative mód lehetséges;
- AI failure: deterministic fallback;
- compiler failure: block unavailable és substitution;
- sync failure: local plan tovább működik.

---

# 33. Observability és evaluation

## 33.1 Strukturált eventek

Példák:

```text
plan_generation_started
plan_generation_completed
plan_generation_failed
plan_preview_edited
plan_activated
plan_block_started
plan_block_completed
plan_block_skipped
plan_block_substituted
plan_revision_proposed
plan_revision_accepted
plan_revision_rejected
plan_paused
plan_resumed
```

## 33.2 Privacy-preserving telemetry

Opt-in telemetry ne tartalmazzon:

- song címet;
- user note-ot;
- raw evidence-et;
- discomfort részletes szöveget;
- account azonosítót plain textben.

## 33.3 Termékmetrikák

- plan setup completion;
- preview acceptance;
- first-block start;
- day completion;
- weekly adherence;
- substitution rate;
- skip reason distribution;
- plan pause rate;
- adaptation acceptance;
- deterministic fallback rate;
- technical failure rate.

Ezek nem egyenlők tanulási eredménnyel.

## 33.4 Tanulási evaluation

Offline és kontrollált datasetben mérhető:

- prerequisite correctness;
- goal coverage;
- time-budget correctness;
- plan validity;
- overload violation;
- evidence grounding;
- progression safety;
- missed-day behavior;
- content availability;
- explanation fidelity.

## 33.5 Counterfactual simulation

Simulation tesztelje:

- kezdő evidence nélkül;
- haladó, kevés idővel;
- conflicting evidence;
- egy hét kihagyás;
- comfort warning;
- dalcéldátum;
- offline capability;
- hiányzó song asset;
- túl sok goal;
- timezone változás.

## 33.6 Human review

Pedagógiai szakértő vagy tapasztalt gitártanár review-ja szükséges legalább:

- starter templates;
- progression policy;
- beginner prerequisite graph;
- song-goal periodizáció;
- safety copy;
- túlterhelési szabályok.

---

# 34. Tesztelési stratégia

## 34.1 Domain unit tesztek

- typed ID validáció;
- request validáció;
- goal lifecycle;
- constraint konfliktus;
- skill evidence aggregáció;
- priority calculation;
- candidate filtering;
- allocation;
- scheduling;
- progression;
- spaced repetition;
- plan validator;
- plan diff;
- missed-day policy;
- schema migration.

## 34.2 Property-based tesztek

Invariánsok:

- total time soha nem lépi túl hard maximumot;
- nincs negatív duration;
- block ID egyedi;
- completed múlt nem változik;
- hard avoid nem kerül tervbe;
- unavailable capability nem kerül tervbe;
- progression bound nem sérül;
- review queue nem tölti túl a napot;
- repair terminál;
- azonos input és seed azonos tervet ad.

## 34.3 Golden plan fixture

Fixture profilok:

```text
new_beginner_15m_4days
rhythm_gap_20m_5days
song_goal_30m_3days
return_after_break
conflicted_evidence
micro_plan_5m
comfort_constraint
left_handed_offline
```

A golden ne teljes szöveget, hanem stabil strukturális döntéseket védjen. Lokalizált explanation külön snapshot lehet.

## 34.4 Adapter contract tesztek

Minden adapter ugyanazt a port contractot teljesítse:

- legacy Learn;
- Practice Engine;
- Tutor skill graph;
- Analyze evidence;
- Vision evidence;
- Song Trainer.

## 34.5 Widget tesztek

- setup wizard;
- validation error;
- progress/cancel;
- preview;
- edit duration;
- block swap;
- plan activate;
- today start;
- skip reason;
- change review;
- accessibility semantics;
- large text;
- Hungarian és English overflow.

## 34.6 Integration tesztek

- starter plan teljes flow;
- evidence-based plan;
- block start és outcome return;
- plan revision;
- missed day;
- pause/resume;
- offline mode;
- AI failure fallback;
- storage restart;
- timezone változás.

## 34.7 Backend tesztek

Ha AI assist vagy sync backend készül:

- auth;
- schema validation;
- candidate allowlist;
- prompt injection;
- timeout;
- rate limit;
- no-secret log;
- provider failure;
- idempotent sync;
- conflict.

## 34.8 Valós eszköz tesztek

- Android középkategóriás eszköz;
- offline airplane mode;
- app restart aktív tervvel;
- notificationből Today screen;
- sessionből visszatérés;
- hosszú lista scroll;
- font scaling;
- locale switch;
- low storage failure;
- time zone change.

---

# 35. Codex végrehajtási szabályok

Minden kör elején:

1. Olvasd el az `AGENTS.md`, `HANDOFF.md` és az aktuális SDD-kört.
2. Vizsgáld meg az érintett public API-kat és teszteket.
3. Egy körben csak a megadott scope-on dolgozz.
4. Ne kezdj következő körbe.
5. Ne módosíts DSP- vagy vision-modellt.
6. Ne változtass policy súlyt teszt és dokumentáció nélkül.
7. Ne használj LLM-outputot validator nélkül.
8. Ne importálj más feature belső presentation vagy provider fájljából.
9. Minden új time/random/ID függőség legyen injektálható.
10. Minden persistence írás legyen idempotens vagy revisionvezérelt.
11. Ne használj üres catch blokkot.
12. Ne logolj user note-ot, song címet, tokent vagy érzékeny adatot.
13. Minden bugfixhez először reprodukáló teszt készüljön.
14. Minden kör végén futtasd külön parancsokban a format, analyze és releváns teszteket.
15. Frissítsd a `HANDOFF.md` fájlt rövid, aktuális állapottal.

Branch:

```text
codex/epic-07-round-01-baseline
codex/epic-07-round-02-domain-primitives
codex/epic-07-round-03-goals-constraints
```

Körvégi jelentés:

- módosított fájlok;
- implementált feladatok;
- futtatott parancsok;
- teszteredmények;
- policy változás;
- migrációs hatás;
- ismert kockázat;
- következő pontos kör.

---

# 36. Fejlesztési körök

# Kör 1 — Baseline, ADR-ek és feature flag

## Cél

A Practice Generator fejlesztési határainak, jelenlegi adapterforrásainak és rollout kapcsolóinak rögzítése alkalmazáslogika módosítása nélkül.

## Új vagy főként érintett fájlok

```text
docs/sdd/08-epic-07-ai-practice-generator.md
docs/adr/00xx-deterministic-first-practice-planning.md
docs/adr/00xx-practice-plan-revisions.md
lib/app/config/feature_flags.dart
test/core/architecture_dependency_test.dart
```

## Feladatok

- Dokumentáld a jelenlegi Learn, Progress, Streak, Songs és Analyze bemeneteket.
- Vezesd be a `practiceGeneratorEnabled` és külön `plannerAssistEnabled` feature flaget.
- Rögzítsd ADR-ben, hogy a modell nem hozhat létre közvetlenül végrehajtható tervet.
- Rögzítsd ADR-ben a revision-alapú immutable múlt szabályt.
- Készíts dependency allowlistet, amely új cross-feature belső importot tilt.
- Dokumentáld a baseline teszt- és buildállapotot.

## Kötelező tesztek

- flutter analyze lib/ test/
- flutter test
- architecture dependency test

## Elfogadási feltételek

- [ ] Feature flag alapértelmezetten kikapcsolt productionben, amíg rollout nincs.
- [ ] Alkalmazásfunkció nem regresszál.
- [ ] Nincs új hálózati kérés.
- [ ] A dokumentáció egyértelműen megnevezi a legacy adaptereket.

## Javasolt commit

```text
chore(planner): establish adaptive planning baseline
```

---

# Kör 2 — Typed ID-k, enumok és domain primitívek

## Cél

A generátor stabil, Flutter-független alaptípusainak létrehozása.

## Új vagy főként érintett fájlok

```text
lib/features/practice_generator/domain/id/
lib/features/practice_generator/domain/model/plan_enums.dart
lib/features/practice_generator/public.dart
test/features/practice_generator/domain/
```

## Feladatok

- Implementáld a plan, day, block, goal, revision és outcome typed ID-kat.
- Implementáld a státusz-, mód-, block-kind-, severity- és source-enumokat.
- Adj JSON round-trip támogatást stabil string code-okkal.
- Ismeretlen enum code migrációkor kontrollált failure legyen.
- Használj injektálható IdGeneratort.

## Kötelező tesztek

- ID equality és validation
- JSON round-trip
- unknown enum code
- architecture import test

## Elfogadási feltételek

- [ ] A domain nem importál Fluttert.
- [ ] Üres és érvénytelen ID elutasított.
- [ ] Az enum szerializáció stabil.
- [ ] A public API csak szükséges primitíveket exportál.

## Javasolt commit

```text
feat(planner): add typed planning domain primitives
```

---

# Kör 3 — Goal, availability és learner constraint domain

## Cél

A felhasználói szándék és a tervezési hard/soft korlátok típusos modellezése.

## Új vagy főként érintett fájlok

```text
lib/features/practice_generator/domain/model/practice_goal.dart
lib/features/practice_generator/domain/model/weekly_availability.dart
lib/features/practice_generator/domain/model/learner_constraints.dart
lib/features/practice_generator/domain/service/request_validator.dart
```

## Feladatok

- Implementáld a PracticeGoal és metric target modelleket.
- Implementáld a naponta változó availabilityt.
- Különítsd el a hard és soft constraintet.
- Modellezd equipment, tuning, capability, comfort, accessibility, preference és avoid kategóriákat.
- Implementáld a goal lifecycle-t.
- Készíts constraint-conflict validátort.

## Kötelező tesztek

- goal lifecycle
- availability edge cases
- constraint conflict
- timezone-neutral local date fixtures

## Elfogadási feltételek

- [ ] Túl sok primary goal warningot ad.
- [ ] Hard időmaximum nem sérülhet.
- [ ] Comfort hard constraintként kezelhető.
- [ ] Custom goal normalizálás nélkül nem végrehajtható.

## Javasolt commit

```text
feat(planner): model goals availability and learner constraints
```

---

# Kör 4 — PracticeGenerationRequest és draft persistence

## Cél

A generálás teljes inputjának verziózott, megszakítás után folytatható dokumentummá alakítása.

## Új vagy főként érintett fájlok

```text
lib/features/practice_generator/domain/model/practice_generation_request.dart
lib/features/practice_generator/data/local/generation_request_serializer.dart
lib/features/practice_generator/data/local/generation_draft_repository.dart
test/features/practice_generator/data/
```

## Feladatok

- Implementáld a request schema versiont és generation mode-okat.
- Adj determinisztikus seedet.
- Készíts request validációt horizon, locale, goal és availability szabályokkal.
- Mentsd a setup wizard draftját lokálisan.
- Biztosíts schema migrációt.
- Ne írd felül az aktív tervet request mentésekor.

## Kötelező tesztek

- request round-trip
- migration
- corrupt draft
- hash stability
- draft/active isolation

## Elfogadási feltételek

- [ ] App restart után a wizard folytatható.
- [ ] Sérült draft nem omlasztja össze az appot.
- [ ] A request determinisztikusan hash-elhető.
- [ ] Draft törölhető.

## Javasolt commit

```text
feat(planner): add versioned generation requests
```

---

# Kör 5 — SkillEvidence normalizálás és evidence repository

## Cél

A különböző mérési források közös, confidence-aware evidence formába rendezése.

## Új vagy főként érintett fájlok

```text
lib/features/practice_generator/domain/model/skill_evidence.dart
lib/features/practice_generator/domain/repository/practice_evidence_repository.dart
lib/features/practice_generator/application/service/evidence_aggregator.dart
test/features/practice_generator/evidence/
```

## Feladatok

- Implementáld a SkillEvidence és provenance modelleket.
- Deduplicáld source outcome ID alapján.
- Kezeld recencyt, validUntil-t és measurement versiont.
- Különítsd el performance evidence-et és discomfort self-reportot.
- Készíts in-memory fake repositoryt.
- Adj bounded query API-t skill és időtartomány szerint.

## Kötelező tesztek

- deduplication
- stale evidence
- confidence bounds
- source round-trip
- privacy log redaction

## Elfogadási feltételek

- [ ] Raw audio/video nem része a modellnek.
- [ ] Ugyanaz az outcome nem kerül be kétszer.
- [ ] Jövőbeli és hibás timestamp kontrollált.
- [ ] Sensitive note nincs logban.

## Javasolt commit

```text
feat(planner): normalize skill evidence inputs
```

---

# Kör 6 — SkillEstimate reducer és konfliktuskezelés

## Cél

Több evidence-ből stabil, trendet és bizonytalanságot tartalmazó skill snapshot készítése.

## Új vagy főként érintett fájlok

```text
lib/features/practice_generator/domain/model/skill_estimate.dart
lib/features/practice_generator/domain/policy/evidence_weight_policy.dart
lib/features/practice_generator/application/service/skill_estimate_reducer.dart
test/features/practice_generator/skill_estimate/
```

## Feladatok

- Implementáld a source reliability, confidence, recency és sample count súlyozást.
- Korlátozd egyetlen evidence maximális hatását.
- Detektáld az outliert és a konfliktust.
- Számíts trendet bounded historyból.
- Unknown adatot ne alakíts gyengeséggé.
- Adj human-readable evidence summary DTO-t.

## Kötelező tesztek

- single-session cap
- repeated evidence
- conflict
- stale decay
- unknown state
- property bounds

## Elfogadási feltételek

- [ ] Azonos input azonos estimate-et ad.
- [ ] Egyetlen session nem ugrathat több szintet.
- [ ] Conflicted evidence magas uncertaintyt ad.
- [ ] Discomfort nem átlagolódik performance score-ba.

## Javasolt commit

```text
feat(planner): derive confidence-aware skill estimates
```

---

# Kör 7 — Legacy Learn és Progress evidence adapterek

## Cél

A jelenlegi repository adataiból használható skill evidence előállítása a generátor domainjének szennyezése nélkül.

## Új vagy főként érintett fájlok

```text
lib/features/practice_generator/data/adapter/legacy_lesson_catalog_adapter.dart
lib/features/practice_generator/data/adapter/legacy_progress_evidence_adapter.dart
lib/features/practice_generator/application/port/skill_snapshot_reader.dart
test/features/practice_generator/adapter/legacy_*.dart
```

## Feladatok

- Mapeld a lesson difficultyt, skill tageket és best accuracyt.
- Mapeld a practice log aktív idejét és session típust.
- Ne következtess olyan skillre, amelyhez nincs explicit mapping.
- Tedd verziózottá a mapping táblát.
- Adj fixture-t a beépített lesson katalógushoz.
- Dokumentáld, mely legacy adat csak gyenge evidence.

## Kötelező tesztek

- lesson mapping
- progress mapping
- unknown lesson
- duplicate legacy entries
- adapter contract

## Elfogadási feltételek

- [ ] Nincs közvetlen legacy provider import a domainben.
- [ ] Ismeretlen lesson nem okoz crash-t.
- [ ] A mapping determinisztikus.
- [ ] A legacy adat source-ként jelölt.

## Javasolt commit

```text
feat(planner): adapt legacy learning progress into evidence
```

---

# Kör 8 — Practice catalog capability adapter

## Cél

A végrehajtható gyakorlatok egységes, revisionözött candidate snapshotjának létrehozása.

## Új vagy főként érintett fájlok

```text
lib/features/practice_generator/domain/model/practice_catalog_snapshot.dart
lib/features/practice_generator/domain/model/exercise_candidate.dart
lib/features/practice_generator/application/port/practice_catalog_reader.dart
lib/features/practice_generator/data/adapter/practice_engine_catalog_adapter.dart
```

## Feladatok

- Normalizáld a Practice Engine definitionöket candidate-té.
- Add hozzá a capability, duration, difficulty, load és offline metadata-t.
- Készíts legacy lesson candidate adaptert fallbackként.
- Rögzíts catalog revisiont és content revisiont.
- Validáld a hiányzó skill taget és prerequisite-et.
- Adj deterministic catalog sortot.

## Kötelező tesztek

- catalog snapshot
- capability mapping
- revision mismatch
- missing metadata
- offline filters

## Elfogadási feltételek

- [ ] Candidate csak létező source-ra mutat.
- [ ] Unsupported capability explicit.
- [ ] Offline availability helyes.
- [ ] A katalógus sorrendje stabil.

## Javasolt commit

```text
feat(planner): expose executable practice candidates
```

---

# Kör 9 — ExercisePrescription és success criteria

## Cél

A generátor által kiválasztott gyakorlat konkrét, bounded végrehajtási receptjének modellezése.

## Új vagy főként érintett fájlok

```text
lib/features/practice_generator/domain/model/exercise_prescription.dart
lib/features/practice_generator/domain/model/success_criteria.dart
lib/features/practice_generator/domain/model/progression_rule.dart
test/features/practice_generator/prescription/
```

## Feladatok

- Implementáld duration-, tempo-, repetition-, loop- és rest-prescriptiont.
- Implementáld a success criteria typed változatait.
- Korlátozd a nyílt végű ismétlést maximummal.
- Adj progression és regression rule-t.
- Adj fallback candidate listát.
- Validáld, hogy a criteria mérhető a candidate capabilityből.

## Kötelező tesztek

- duration bounds
- tempo capability
- criteria capability
- fallback validation
- JSON round-trip

## Elfogadási feltételek

- [ ] Nincs végtelen prescription.
- [ ] Tempo csak támogatott candidate-nél használható.
- [ ] A fallback kompatibilis céllal.
- [ ] A success criteria explicit.

## Javasolt commit

```text
feat(planner): define bounded exercise prescriptions
```

---

# Kör 10 — AdaptivePracticePlan, day, block és revision domain

## Cél

A többnapos terv kanonikus, immutable és revisionözött dokumentummodelljének létrehozása.

## Új vagy főként érintett fájlok

```text
lib/features/practice_generator/domain/model/adaptive_practice_plan.dart
lib/features/practice_generator/domain/model/practice_day.dart
lib/features/practice_generator/domain/model/practice_block.dart
lib/features/practice_generator/domain/model/plan_revision.dart
lib/features/practice_generator/domain/model/plan_change_set.dart
```

## Feladatok

- Implementáld a plan/day/block státuszokat és modelleket.
- Rögzíts generation provenance-et és policy versionöket.
- Implementáld a revision numbert és teljes snapshotot.
- Implementáld a machine-readable change setet.
- Védd a completed múlt immutable szabályát.
- Adj summary DTO-kat UI-hoz.

## Kötelező tesztek

- plan round-trip
- revision monotonicity
- immutable history
- change set diff
- status transition

## Elfogadási feltételek

- [ ] Revision monoton.
- [ ] Completed block nem módosítható silent módon.
- [ ] A plan JSON verziózott.
- [ ] A summary nem szivárogtat érzékeny note-ot.

## Javasolt commit

```text
feat(planner): add revisioned adaptive practice plans
```

---

# Kör 11 — PlanValidator és deterministic repair

## Cél

Minden generált és kézzel szerkesztett terv teljes invariáns-ellenőrzése.

## Új vagy főként érintett fájlok

```text
lib/features/practice_generator/domain/service/plan_validator.dart
lib/features/practice_generator/domain/service/plan_repairer.dart
lib/features/practice_generator/domain/model/plan_validation_issue.dart
test/features/practice_generator/validation/
```

## Feladatok

- Implementáld a teljes hard invariánslistát.
- Adj info/warning/error/fatal severityt.
- Készíts bounded deterministic repairt.
- Repair logolja a change setet.
- Kezeld missing asset, capability, tuning és hard avoid hibát.
- Tiltsd a completed history módosítását.

## Kötelező tesztek

- all invariants
- repair termination
- hard avoid
- load sequencing
- completed history
- property fuzz

## Elfogadási feltételek

- [ ] Error/fatal mellett terv nem aktiválható.
- [ ] Repair terminál.
- [ ] Repair nem növeli az időt hard max fölé.
- [ ] Minden repair reasonnel rendelkezik.

## Javasolt commit

```text
feat(planner): validate and repair generated plans
```

---

# Kör 12 — SkillPriorityEngine és policy config

## Cél

A célokból, evidence-ből és prerequisite-ekből magyarázható prioritási sorrend készítése.

## Új vagy főként érintett fájlok

```text
lib/features/practice_generator/domain/service/priority_engine.dart
lib/features/practice_generator/domain/policy/priority_policy.dart
lib/features/practice_generator/domain/model/skill_priority.dart
test/features/practice_generator/priority/
```

## Feladatok

- Implementáld a normalizált priority faktorokat.
- Vezesd be a prerequisite boostot és uncertainty penaltyt.
- Implementáld coverage debtet.
- Adj fatigue és novelty penaltyt.
- Készíts stabil tie-breaket.
- Tedd a súlyokat verziózott policy configgá.

## Kötelező tesztek

- goal alignment
- prerequisite
- uncertainty
- coverage debt
- fatigue
- tie-break

## Elfogadási feltételek

- [ ] Primary goal előnyt kap, de safety nem sérül.
- [ ] Unknown skill assessmentet kaphat, nem automatikus gapet.
- [ ] Az indoklás faktorokra bontható.
- [ ] A tie-break reprodukálható.

## Javasolt commit

```text
feat(planner): rank skills with grounded priorities
```

---

# Kör 13 — CandidateSelector, hard filter és diversity

## Cél

Skill prioritásokhoz kompatibilis gyakorlatjelöltek kiválasztása és rangsorolása.

## Új vagy főként érintett fájlok

```text
lib/features/practice_generator/domain/service/candidate_selector.dart
lib/features/practice_generator/domain/policy/candidate_policy.dart
lib/features/practice_generator/domain/model/candidate_decision.dart
test/features/practice_generator/candidates/
```

## Feladatok

- Implementáld a hard exclusion reasonöket.
- Rangsorold a jelölteket cél, difficulty, preference és mérhetőség alapján.
- Implementáld recent overuse és diversity szabályt.
- Adj stable exploration policyt seeddel.
- Készíts fallback láncot.
- Ne válassz locked vagy unavailable contentet.

## Kötelező tesztek

- hard filters
- preference ranking
- overuse
- seed stability
- fallback
- locked content

## Elfogadási feltételek

- [ ] Hard filter nem kerülhető meg.
- [ ] Diversity nem írja felül primary relevance-et.
- [ ] Fallback azonos skillt támogat.
- [ ] Decision tartalmazza az elutasított okokat diagnosztikára.

## Javasolt commit

```text
feat(planner): select compatible diverse exercises
```

---

# Kör 14 — TimeBudgetAllocator és micro-plan

## Cél

A napi rendelkezésre álló idő értelmes, exact és pedagógiailag használható felosztása.

## Új vagy főként érintett fájlok

```text
lib/features/practice_generator/domain/service/time_budget_allocator.dart
lib/features/practice_generator/domain/policy/time_allocation_policy.dart
lib/features/practice_generator/domain/model/time_budget.dart
test/features/practice_generator/allocation/
```

## Feladatok

- Különítsd el active, elapsed, rest és setup budgetet.
- Implementáld minimum block és rounding szabályt.
- Készíts 5 perces micro-plan policyt.
- Biztosíts primary minimumot.
- Egyesíts vagy törölj értelmetlenül rövid blokkokat.
- Implementáld shorten-today és extend-today döntést.

## Kötelező tesztek

- 5/10/20/45/90 minute budgets
- rounding
- minimum blocks
- shorten
- extend
- property exactness

## Elfogadási feltételek

- [ ] Hard maximum soha nem sérül.
- [ ] Nincs negatív vagy 30 másodperces töredékblokk.
- [ ] Az összeg rounding után is helyes.
- [ ] Rövidítés reason change setet ad.

## Javasolt commit

```text
feat(planner): allocate realistic daily time budgets
```

---

# Kör 15 — WeeklyScheduler és terhelésrotáció

## Cél

A kiválasztott prescriptionök napokra rendezése fókusz-, pihenő- és periodizációs szabályokkal.

## Új vagy főként érintett fájlok

```text
lib/features/practice_generator/domain/service/weekly_scheduler.dart
lib/features/practice_generator/domain/policy/scheduling_policy.dart
lib/features/practice_generator/domain/model/schedule_decision.dart
test/features/practice_generator/scheduling/
```

## Feladatok

- Implementáld a napi primary/secondary fókusz limitet.
- Implementáld high-load egymásutániság védelmét.
- Kezeld rest dayt.
- Készíts song-goal fázisokat céldátumhoz.
- Ütemezd review due itemeket bounded arányban.
- Tartsd tiszteletben a naponta változó availabilityt.

## Kötelező tesztek

- availability
- load rotation
- rest day
- song periodization
- review budget
- date boundaries

## Elfogadási feltételek

- [ ] Unavailable napra nincs kötelező blokk.
- [ ] High-load limit nem sérül.
- [ ] Céldátum előtt light review lehetséges.
- [ ] A scheduler reprodukálható.

## Javasolt commit

```text
feat(planner): schedule sustainable weekly practice
```

---

# Kör 16 — Progression és regression policy

## Cél

Bizonyítékalapú, bounded nehézségváltoztatás implementálása.

## Új vagy főként érintett fájlok

```text
lib/features/practice_generator/domain/policy/progression_policy.dart
lib/features/practice_generator/domain/service/adaptation_decider.dart
lib/features/practice_generator/domain/model/adaptation_decision.dart
test/features/practice_generator/adaptation/
```

## Feladatok

- Definiáld a minimum evidence és confidence feltételeket.
- Implementáld tempo, loop, variation és strictness progressziót.
- Implementáld too-hard és repeated-struggle regressziót.
- Adj cooldownt két progresszió között.
- Safety és discomfort blokkolja az emelést.
- Egy rossz session elleni guard.

## Kötelező tesztek

- progression threshold
- single bad session
- repeated struggle
- comfort guard
- cooldown
- tempo clamp

## Elfogadási feltételek

- [ ] Boundok centralizáltak.
- [ ] Nincs több difficulty step ugrás.
- [ ] A döntés evidence refet tartalmaz.
- [ ] Too-hard user feedback gyorsan érvényesül.

## Javasolt commit

```text
feat(planner): adapt difficulty with bounded evidence rules
```

---

# Kör 17 — Spaced repetition és maintenance queue

## Cél

A korábban megtanult skill- és tartalomelemek időzített, korlátozott fenntartása.

## Új vagy főként érintett fájlok

```text
lib/features/practice_generator/domain/model/review_item.dart
lib/features/practice_generator/domain/policy/spaced_repetition_policy.dart
lib/features/practice_generator/domain/service/review_queue.dart
test/features/practice_generator/review/
```

## Feladatok

- Implementáld a ReviewItem lifecycle-t.
- Készíts egyszerű, magyarázható interval policyt.
- Kezeld successful, partial, failed és uncertain review-t.
- Korlátozd a napi review budgetet.
- Támogasd chord, pattern, lesson és song section referenciát.
- Deduplicáld az azonos review targetet.

## Kötelező tesztek

- interval updates
- budget cap
- deduplication
- uncertain outcome
- deleted content
- timezone dates

## Elfogadási feltételek

- [ ] A queue nem tölti ki a teljes napot.
- [ ] Uncertain measurement nem büntet.
- [ ] A due date deterministic.
- [ ] Törölt content helyettesítést igényel.

## Javasolt commit

```text
feat(planner): schedule bounded skill maintenance
```

---

# Kör 18 — GenerationOrchestrator, progress és cancellation

## Cél

A teljes pipeline alkalmazásszintű, megszakítható és állapotgéppel vezérelt futtatása.

## Új vagy főként érintett fájlok

```text
lib/features/practice_generator/application/service/generation_orchestrator.dart
lib/features/practice_generator/application/controller/plan_generator_controller.dart
lib/features/practice_generator/application/model/generation_state.dart
test/features/practice_generator/application/generation_orchestrator_test.dart
```

## Feladatok

- Implementáld a pipeline stage-eket.
- Adj immutable state machine-t.
- Implementáld progress eventeket és cancellationt.
- Azonos request párhuzamos futását kezeld.
- Részleges eredmény ne aktiválódjon.
- Minden failure mapelődjön AppFailure-re.

## Kötelező tesztek

- happy path
- cancel each stage
- concurrent generation
- stage failure
- retry
- no partial activation

## Elfogadási feltételek

- [ ] Cancel után nincs repository write.
- [ ] Retry tiszta futást indít.
- [ ] UI isolate nem blokkol hosszú számításon.
- [ ] State transition tesztelt.

## Javasolt commit

```text
feat(planner): orchestrate cancellable plan generation
```

---

# Kör 19 — Local repository, migráció és korrupcióvédelem

## Cél

Draftok, aktív tervek, revisionök és outcome-ok biztonságos local-first tárolása.

## Új vagy főként érintett fájlok

```text
lib/features/practice_generator/data/local/local_practice_plan_repository.dart
lib/features/practice_generator/data/local/practice_plan_serializer.dart
lib/features/practice_generator/data/local/practice_plan_migrator.dart
test/features/practice_generator/data/local_repository_test.dart
```

## Feladatok

- Implementáld a repository contractot.
- Válaszd szét draft, active és archive namespace-t.
- Használj atomikus írást vagy a Core storage atomikus API-ját.
- Adj checksum/korrupciódetektálást.
- Implementáld schema migrációt.
- Korlátozd a revision és outcome historyt policy szerint.

## Kötelező tesztek

- restart
- atomic failure
- corrupt record
- migration
- idempotent outcome
- bounded history

## Elfogadási feltételek

- [ ] Aktív terv app restart után visszatér.
- [ ] Sérült egy rekord nem törli az összes tervet.
- [ ] Outcome append idempotens.
- [ ] Draft nem írja felül az aktív tervet.

## Javasolt commit

```text
feat(planner): persist revisioned practice plans locally
```

---

# Kör 20 — Plan setup wizard és input UX

## Cél

A generálási request egyszerű, hozzáférhető és megszakítás után folytatható felhasználói felületének elkészítése.

## Új vagy főként érintett fájlok

```text
lib/features/practice_generator/presentation/screens/plan_setup_screen.dart
lib/features/practice_generator/presentation/widgets/practice_goal_picker.dart
lib/features/practice_generator/presentation/widgets/availability_editor.dart
test/features/practice_generator/presentation/plan_setup_screen_test.dart
```

## Feladatok

- Implementáld a cél-, schedule-, equipment-, preference- és comfort-lépéseket.
- Támogasd a „nem tudom” válaszokat.
- Mentsd a draftot lépésenként.
- Mutasd a hard conflictot azonnal.
- Készíts reduced-motion és screen-reader támogatást.
- Adj magyar és angol lokalizációt.

## Kötelező tesztek

- wizard navigation
- draft restore
- validation
- large text
- semantics
- hu/en localization

## Elfogadási feltételek

- [ ] Két percen belül végigvihető alapflow.
- [ ] Back navigation nem veszít adatot.
- [ ] Large textnél nincs overflow.
- [ ] Comfort adat nem jelenik meg logban.

## Javasolt commit

```text
feat(planner): add accessible plan setup wizard
```

---

# Kör 21 — Plan preview, explanation és kézi szerkesztés

## Cél

A generált terv teljes, átlátható előnézete mentés és aktiválás előtt.

## Új vagy főként érintett fájlok

```text
lib/features/practice_generator/presentation/screens/plan_preview_screen.dart
lib/features/practice_generator/presentation/widgets/plan_day_card.dart
lib/features/practice_generator/presentation/widgets/plan_block_card.dart
lib/features/practice_generator/presentation/widgets/plan_reason_sheet.dart
```

## Feladatok

- Rendereld a napokat és blockokat.
- Mutasd a reason code alapján lokalizált magyarázatot.
- Adj idő-, nap-, blokk- és preference-editet.
- Minden edit után újravalidálás.
- Warning esetén explicit review.
- Aktiválás csak user confirmationre.

## Kötelező tesztek

- preview render
- edit duration
- swap block
- warning confirm
- activation
- offline explanation

## Elfogadási feltételek

- [ ] Nincs rejtett automatikus mentés.
- [ ] A módosított terv validált.
- [ ] Evidence sheet nem állít többet a confidence-nél.
- [ ] A preview offline működik.

## Javasolt commit

```text
feat(planner): preview and edit plans before activation
```

---

# Kör 22 — Weekly Plan és Today screen

## Cél

Az aktív terv napi használati felületének és egygombos következő lépésének létrehozása.

## Új vagy főként érintett fájlok

```text
lib/features/practice_generator/presentation/screens/weekly_plan_screen.dart
lib/features/practice_generator/presentation/screens/today_plan_screen.dart
lib/features/practice_generator/application/controller/active_plan_controller.dart
lib/features/practice_generator/application/controller/today_plan_controller.dart
```

## Feladatok

- Implementáld a hét- és Today nézetet.
- Mutasd a remaining time-ot és next blockot.
- Adj start, swap, skip, shorten, pause actiont.
- Kezeld rest dayt és completed dayt.
- Today számítás lokális dátummal történjen.
- Notification deep link biztonságosan nyisson Todayre.

## Kötelező tesztek

- week render
- today selection
- rest day
- shorten action
- pause
- deep link
- timezone

## Elfogadási feltételek

- [ ] Nincs terv esetén megfelelő empty state.
- [ ] Rest day nem missed.
- [ ] Today timezone váltásnál nem duplikálódik.
- [ ] A next block deterministic.

## Javasolt commit

```text
feat(planner): deliver weekly and today plan experiences
```

---

# Kör 23 — PlanCompiler és Practice Engine végrehajtás

## Cél

A plan blockok validált Practice Engine lépéssé fordítása és session outcome visszacsatolása.

## Új vagy főként érintett fájlok

```text
lib/features/practice_generator/domain/service/plan_compiler.dart
lib/features/practice_generator/application/service/plan_execution_coordinator.dart
lib/features/practice_generator/data/adapter/practice_outcome_adapter.dart
test/features/practice_generator/execution/
```

## Feladatok

- Implementáld az OpenPracticeDefinition compiled stepet.
- Ellenőrizd exercise revisiont és capabilityt start előtt.
- Add át a prescription configot.
- Készíts blockExecutionId-t.
- Fogadd és normalizáld a PracticeSessionResultot.
- Kezeld cancel, partial és technical failure eredményt.

## Kötelező tesztek

- compile practice
- stale revision
- outcome mapping
- duplicate return
- cancel
- technical failure

## Elfogadási feltételek

- [ ] Stale block nem indul.
- [ ] Outcome idempotens.
- [ ] Session config megfelel a prescriptionnek.
- [ ] Technical failure nem számít skill failure-nek.

## Javasolt commit

```text
feat(planner): execute plan blocks through Practice Engine
```

---

# Kör 24 — Song goal és Song Trainer integráció

## Cél

Dal- és szakaszcélok beépítése a heti tervbe prerequisite és céldátum figyelembevételével.

## Új vagy főként érintett fájlok

```text
lib/features/practice_generator/data/adapter/song_goal_reader_adapter.dart
lib/features/practice_generator/domain/service/song_goal_planner.dart
lib/features/practice_generator/domain/service/song_block_compiler.dart
test/features/practice_generator/song_goal/
```

## Feladatok

- Olvasd a song sectionöket és hotspotokat public API-n.
- Készíts song range candidate-eket.
- Implementáld a foundation→integration→simulation fázisokat.
- Kapcsold a chord/rhythm prerequisite skillhez.
- Kezeld missing assetet és revisiont.
- Normalizáld a SongSessionResult outcome-ot.

## Kötelező tesztek

- section selection
- periodization
- prerequisite
- missing asset
- date boundary
- outcome mapping

## Elfogadási feltételek

- [ ] Dal nem nyomja el teljesen az alap skillt.
- [ ] Céldátum után nincs új blokk automatikusan.
- [ ] Missing songnál fallback vagy explicit hiba.
- [ ] Utolsó fázisban nincs indokolatlan új technika.

## Javasolt commit

```text
feat(planner): build goal-driven song practice plans
```

---

# Kör 25 — Analyze és Computer Vision evidence integráció

## Cél

A Chapter 7 és Chapter 6 származtatott, confidence-aware jeleinek bekötése a tervprioritásba.

## Új vagy főként érintett fájlok

```text
lib/features/practice_generator/data/adapter/analysis_evidence_adapter.dart
lib/features/practice_generator/data/adapter/vision_evidence_adapter.dart
lib/features/practice_generator/application/port/analysis_evidence_reader.dart
lib/features/practice_generator/application/port/vision_evidence_reader.dart
```

## Feladatok

- Mapeld timing, tempo stability, stroke balance, chord és hotspot evidence-et.
- Mapeld csak engedélyezett vision proxykat.
- Kezeld capability unavailable és low-confidence állapotot.
- Ne használj raw frame-et vagy raw audiot.
- Különítsd el signal quality hibát a skill hibától.
- Készíts cross-source conflict fixture-t.

## Kötelező tesztek

- analysis mapping
- vision mapping
- low confidence
- signal quality
- no-vision fallback
- cross-source conflict

## Elfogadási feltételek

- [ ] Low confidence nem vált ki agresszív fókuszt.
- [ ] Signal quality esetén setup/assessment ajánlható.
- [ ] Vision nélkül a generátor teljesen működik.
- [ ] Privacy boundary tesztelt.

## Javasolt commit

```text
feat(planner): ground plans in audio and vision evidence
```

---

# Kör 26 — Outcome ingestion, review update és plan revision

## Cél

A befejezett blokkok eredményének feldolgozása és átlátható jövőbeli tervmódosítás készítése.

## Új vagy főként érintett fájlok

```text
lib/features/practice_generator/application/service/outcome_ingestion_service.dart
lib/features/practice_generator/application/usecase/record_practice_outcome.dart
lib/features/practice_generator/application/usecase/revise_practice_plan.dart
lib/features/practice_generator/presentation/screens/plan_change_review_screen.dart
```

## Feladatok

- Validáld outcome és active revision egyezést.
- Frissíts evidence-et és review queue-t.
- Futtasd az adaptation decidert.
- Készíts change setet csak jövőbeli blokkokra.
- Különítsd el minor és major változást.
- Mutasd a major diffet confirmation előtt.

## Kötelező tesztek

- outcome ingestion
- duplicate
- minor revision
- major confirmation
- rejection
- immutable past

## Elfogadási feltételek

- [ ] Completed múlt változatlan.
- [ ] Duplicate outcome nincs duplán feldolgozva.
- [ ] Major change user confirmationt igényel.
- [ ] Elutasított change set auditálható, de nem aktív.

## Javasolt commit

```text
feat(planner): revise future practice from completed outcomes
```

---

# Kör 27 — Missed day, catch-up, pause és returning flow

## Cél

Nem büntető tervfolytatás kihagyás, tervszünet és hosszabb visszatérés után.

## Új vagy főként érintett fájlok

```text
lib/features/practice_generator/domain/policy/missed_day_policy.dart
lib/features/practice_generator/application/usecase/pause_practice_plan.dart
lib/features/practice_generator/application/usecase/resume_practice_plan.dart
lib/features/practice_generator/presentation/widgets/catch_up_sheet.dart
```

## Feladatok

- Implementáld a missed-day policy opciókat.
- Ne duplázd a következő napi budgetet.
- Készíts primary-only reschedule-t.
- Implementáld pause/resume dátumkorrekciót.
- Hosszabb break után readiness plan proposal.
- Kezeld timezone változást.

## Kötelező tesztek

- missed day
- primary move
- budget guard
- pause/resume
- long break
- timezone travel

## Elfogadási feltételek

- [ ] Rest day nem missed.
- [ ] Pause alatt nincs backlog.
- [ ] Resume új revisiont készít.
- [ ] Copy nem szégyenítő.

## Javasolt commit

```text
feat(planner): handle missed days without punitive backlog
```

---

# Kör 28 — Tutor és PlannerAssistGateway integráció

## Cél

A Tutor és opcionális AI segítség biztonságos bekötése typed proposalokkal és deterministic fallbackkel.

## Új vagy főként érintett fájlok

```text
lib/features/practice_generator/application/port/planner_assist_gateway.dart
lib/features/practice_generator/data/ai/remote_planner_assist_gateway.dart
lib/features/practice_generator/data/ai/fake_planner_assist_gateway.dart
lib/features/practice_generator/data/adapter/tutor_plan_proposal_adapter.dart
```

## Feladatok

- Implementáld a structured request/output schemát.
- Csak allowlistelt goal, skill és candidate ID-t engedj.
- Mapeld a Chapter 5 Tutor PracticePlanDraftot generation request/proposal formára.
- Adj deterministic explanation fallbacket.
- Kezeld timeoutot, cancellationt és rate limitet.
- Prompt injection és untrusted user note elkülönítés.

## Kötelező tesztek

- schema validation
- allowlist
- timeout
- prompt injection
- fallback
- Tutor proposal mapping

## Elfogadási feltételek

- [ ] AI nélkül minden core funkció működik.
- [ ] Modell nem aktiválhat tervet.
- [ ] Hibás ID elutasított.
- [ ] Cloud hiba nem veszít draftot.

## Javasolt commit

```text
feat(planner): add validated AI-assisted plan explanations
```

---

# Kör 29 — Accessibility, localization, privacy és safety hardening

## Cél

A teljes feature publikálás előtti hozzáférhetőségi, adatvédelmi és safety megerősítése.

## Új vagy főként érintett fájlok

```text
lib/l10n/app_en.arb
lib/l10n/app_hu.arb
lib/features/practice_generator/presentation/
test/features/practice_generator/accessibility/
docs/privacy/practice-planning-data.md
```

## Feladatok

- Teljes hu/en string parity.
- Auditáld large textet és screen reader sorrendet.
- Implementáld reduced motiont és nem színalapú státuszt.
- Redactáld a telemetryt és logokat.
- Comfort feedback safety flow.
- Adj teljes delete/export UX-et.
- Auditáld a manipulatív copyt.

## Kötelező tesztek

- l10n parity
- semantics
- large text
- redaction
- comfort safety
- delete/export

## Elfogadási feltételek

- [ ] Nincs érzékeny adat logban.
- [ ] Minden action billentyűzet/screen reader által elérhető.
- [ ] Fájdalomjelzés nem indít progressziót.
- [ ] Delete után plan és evidence policy szerinti adat törlődik.

## Javasolt commit

```text
fix(planner): harden accessibility privacy and safety
```

---

# Kör 30 — Evaluation harness, shadow rollout és Epic lezárás

## Cél

A generátor determinisztikus minőségének mérhető igazolása és fokozatos bekapcsolása.

## Új vagy főként érintett fájlok

```text
tool/practice_plan_eval/
test/fixtures/practice_planner/
test/features/practice_generator/property/
docs/sdd/epic-07-completion-report.md
.github/workflows/flutter-ci.yml
```

## Feladatok

- Készíts golden profile és simulation fixture-öket.
- Implementáld invariant és property teszteket.
- Készíts plan-quality reportot.
- Shadow módban generálj tervet aktiválás nélkül, ha privacy policy engedi.
- Hasonlítsd össze deterministic és AI-assisted explanation fidelityt.
- Mérd latencyt és memóriahasználatot.
- Frissíts README/HANDOFF/SDD completion reportot.
- Kapcsold be a feature flaget csak a release gate után.

## Kötelező tesztek

- flutter analyze
- full flutter test
- property suite
- golden fixture evaluation
- offline integration
- real-device checklist

## Elfogadási feltételek

- [ ] Minden CI zöld.
- [ ] Nincs hard invariant violation a fixture corpuson.
- [ ] Azonos seed reprodukálható.
- [ ] AI explanation nem mond ellent a tervnek.
- [ ] Offline teljes flow valós eszközön működik.

## Javasolt commit

```text
docs(planner): close Epic 7 adaptive practice generation
```

---

# 37. Epic 7 végső Definition of Done

## Domain és architektúra

- [ ] Létezik a Flutter-független practice generator domain.
- [ ] Minden terv, nap, blokk, goal, revision és outcome typed ID-t használ.
- [ ] A schema és policy versionök rögzítettek.
- [ ] A domain nem importál más feature belső fájljából.
- [ ] Más feature csak public API-n vagy application porton keresztül érhető el.
- [ ] A Tutor `PracticePlanDraft` és a kanonikus `AdaptivePracticePlan` határa egyértelmű.

## Request, goals és constraints

- [ ] A setup request verziózott és app restart után folytatható.
- [ ] A célok prioritással és lifecycle-lal rendelkeznek.
- [ ] A naponta változó availability támogatott.
- [ ] Hard és soft constraint külön kezelhető.
- [ ] Equipment, tuning, capability, comfort és accessibility figyelembe vett.
- [ ] Constraint conflict nem eredményez érvénytelen tervet.

## Evidence és skill state

- [ ] Minden evidence provenance-t, confidence-et, időt és measurement versiont tartalmaz.
- [ ] Egy outcome nem kerül be kétszer.
- [ ] Egyetlen session nem változtathat korlátlanul skill estimate-et.
- [ ] Unknown adat nem jelent automatikus gyengeséget.
- [ ] Conflicting és stale evidence explicit.
- [ ] Discomfort self-report elsőbbséget kap terhelésnöveléssel szemben.
- [ ] Raw audio és raw video nem kerül a generátor domainbe.

## Candidate és prescription

- [ ] A generátor kizárólag katalógusból származó, létező candidate-et használ.
- [ ] Minden candidate capability- és revision-metaadattal rendelkezik.
- [ ] Hard avoid, hiányzó capability és unavailable content kiszűrt.
- [ ] Minden végrehajtható blokk bounded prescriptiont tartalmaz.
- [ ] Nincs nyílt végű, maximum nélküli ismétlés.
- [ ] Success criteria mérhető vagy assessment-only.
- [ ] Fallbackek kompatibilisek a céllal.

## Prioritás, idő és schedule

- [ ] A priority engine verziózott policyből dolgozik.
- [ ] A decision magyarázható faktorokra bontható.
- [ ] Prerequisite graph érvényesül.
- [ ] Hard daily maximum soha nem sérül.
- [ ] Nincs értelmetlenül rövid blokk.
- [ ] 5 perces micro-plan használható.
- [ ] High-load egymásutániság korlátozott.
- [ ] Rest day támogatott és nem missed day.
- [ ] Song goal periodizáció támogatott.

## Progression, review és adaptáció

- [ ] Progresszió több, megfelelő confidence evidence-et igényel.
- [ ] Egy rossz session nem írja át automatikusan a teljes tervet.
- [ ] User too-hard és discomfort gyorsan érvényesül.
- [ ] Tempo és difficulty változás bounded.
- [ ] Spaced repetition queue bounded napi aránnyal működik.
- [ ] Outcome ingestion idempotens.
- [ ] Completed múlt nem változik új revisionben.
- [ ] Major plan change confirmationt igényel.
- [ ] Minden change set reasonnel és evidence refekkel rendelkezik.

## Végrehajtás

- [ ] PlanCompiler csak validált blokkot fordít actionné.
- [ ] Stale exercise vagy song range nem indul el.
- [ ] Practice Engine outcome helyesen normalizálódik.
- [ ] Song Trainer outcome helyesen normalizálódik.
- [ ] Technical failure nem számít skill failure-nek.
- [ ] Today screen a következő blokkot egyértelműen indítja.
- [ ] Skip, swap, shorten és pause működik.
- [ ] Timezone váltás nem duplikál napot.

## AI és offline működés

- [ ] Determinisztikus tervgenerálás teljesen offline működik.
- [ ] AI csak typed, allowlistelt proposalokat ad.
- [ ] AI nem aktiválhat és nem menthet tervet közvetlenül.
- [ ] Minden AI-output validatoron megy át.
- [ ] Cloud failure esetén deterministic fallback működik.
- [ ] A későbbi local LLM ugyanazt a gateway interfészt használhatja.

## Persistence és sync

- [ ] Draft és aktív terv külön tárolódik.
- [ ] Terv, revision és outcome app restart után megmarad.
- [ ] Storage írás atomikus vagy tranzakciós.
- [ ] Sérült rekord nem törli az összes tervet.
- [ ] Schema migráció tesztelt.
- [ ] Optional sync konfliktus explicit és nem ír felül automatikusan két aktív revisiont.
- [ ] User export és delete működik.

## UX, accessibility és privacy

- [ ] Setup wizard megszakítás után folytatható.
- [ ] Preview nélkül nincs automatikus tervaktiválás.
- [ ] Minden automatikus döntéshez van érthető indoklás.
- [ ] Evidence confidence nem jelenik meg hamis bizonyossággal.
- [ ] Large text és screen reader támogatott.
- [ ] Státusz nem csak színnel jelölt.
- [ ] Manipulatív streak vagy sürgető copy nincs.
- [ ] Sensitive profile, discomfort és user note nincs logban.
- [ ] Offline állapotban nincs nem várt hálózati request.

## Minőség és rollout

- [ ] Teljes format és analyze zöld.
- [ ] Unit, widget, integration és property tesztek zöldek.
- [ ] Golden profile evaluation zöld.
- [ ] Nincs hard invariant violation a simulation corpuson.
- [ ] Azonos input, seed és policy verzió azonos tervet ad.
- [ ] Valós Android eszközön offline flow ellenőrzött.
- [ ] Performance baseline dokumentált.
- [ ] Completion report elkészült.
- [ ] Feature flag csak release gate után aktív.

---

# 38. Az Epic eredménye

Az Epic 7 végére a StrumSight rendelkezik egy teljes, local-first gyakorlástervező platformmal, amely:

- a felhasználó célját strukturált tervvé alakítja;
- a bizonyított skill állapotból indul;
- a bizonytalanságot nem rejti el;
- kizárólag végrehajtható, validált gyakorlatot választ;
- napi és heti időkeretet tart;
- progressziót és regressziót kontrolláltan alkalmaz;
- fenntartó review-t ütemez;
- dalcélt és mért hotspotot integrál;
- kihagyott napot nem büntet;
- minden változást revisionben és change setben rögzít;
- a Practice Engine és Song Trainer felé típusos lépéseket fordít;
- az AI-t csak korlátozott, validált segítőként használja;
- internet nélkül is működik;
- készen áll a Chapter 9 Gamification és a Chapter 11 Offline AI integrációjára.

A következő logikai fejezet:

```text
Chapter 9 — Epic 8: Gamification
```
