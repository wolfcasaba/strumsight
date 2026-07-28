# StrumSight Software Design Document

## Chapter 12 — Release Roadmap, Sprint Planning & Final Integration

**Dokumentumverzió:** 1.0  
**Státusz:** fejlesztésre kész program- és release-specifikáció  
**Repository:** `wolfcasaba/strumsight`  
**Alapértelmezett branch:** `main`  
**Elsődleges kliens:** Flutter, Android-first  
**Backend:** FastAPI + PostgreSQL production célállapot  
**Tervezési alapelv:** vertical-slice delivery, offline-first, evidence-driven gates, reversible rollout  
**Referenciaütemezés kezdete:** 2026. augusztus 3.  
**Sprint hossza:** 2 hét  
**Referenciaütemezés:** 36 sprint / 72 hét  
**Integrációs Codex-körök száma:** 36  
**Kapcsolódó fejezetek:** Chapter 1–11, különösen Chapter 2 Core Platform, Chapter 3 Practice Engine, Chapter 4 Song Trainer, Chapter 5 AI Guitar Teacher, Chapter 6 Computer Vision, Chapter 7 Audio Analysis 2.0, Chapter 8 AI Practice Generator, Chapter 9 Gamification, Chapter 10 Community Platform, Chapter 11 Offline AI  
**Végrehajtó:** Project Owner + Codex; szükség szerint célzott manuális QA, design, jogi és store review  
**Végrehajtási mód:** kis, külön ellenőrizhető fejlesztési körök; zöld minőségkapu nélkül nincs továbblépés

---

# 1. A fejezet célja

A Chapter 12 célja a korábbi tizenegy fejezetből egyetlen végrehajtható termékprogramot létrehozni. Ez a fejezet nem új, elszigetelt feature-t tervez. Meghatározza, milyen sorrendben, milyen függőségekkel, milyen release-kapukkal és milyen visszagörgetési lehetőségekkel kell a teljes StrumSight platformot megvalósítani és kiadni.

A dokumentum feladata:

- a teljes SDD dependency graph rögzítése;
- a kritikus út azonosítása;
- a Codex-körök és a kéthetes sprintek szétválasztása;
- a minimálisan kiadható vertical slice meghatározása;
- az Internal Alpha, Closed Beta, Open Beta, Release Candidate és General Availability kapuk definiálása;
- a Flutter, backend, DSP/ML, vision, tutor, community és offline AI workstreamek összehangolása;
- a feature flag-, environment-, versioning- és release channel rendszer lezárása;
- a cross-feature események és idempotencia szabályainak egységesítése;
- a legacy adatok migrációjának és visszagörgetésének biztosítása;
- a CI/CD, signing, provenance, SBOM és artifact integritás kialakítása;
- a valós eszközös audio-, kamera-, AI-, memória- és thermal tesztmátrix meghatározása;
- a privacy, security, accessibility, localization és store readiness kapuk meghatározása;
- a bétafelhasználók, visszajelzések, support és incident response folyamatának megtervezése;
- a fokozatos rollout, kill switch és rollback gyakorlati működésének igazolása;
- a launch utáni stabilizációs és technikaiadósság-ciklus meghatározása.

Az ütemterv nem arra épül, hogy minden fejezet minden ötletét egyszerre elkészítsük. A termék minden fázisban egy használható, mérhető vertical slice-ot ad. A következő feature csak akkor léphet release scope-ba, ha az alapul szolgáló mérési, adatvédelmi és életciklus-szerződések már stabilak.

Az Epic sikerének mércéje nem a lezárt issue-k száma. A siker az, hogy a StrumSight:

- megbízhatóan telepíthető és frissíthető;
- működik kijelentkezve és hálózat nélkül;
- nem veszít felhasználói adatot migráció közben;
- kontrolláltan használja a mikrofont, kamerát, helyi AI-t és hálózatot;
- azonos inputra verziózott és auditálható eredményt ad;
- visszagörgethető release-eket készít;
- béta és production környezetben megfigyelhető, de nem gyűjt nyers érzékeny adatot;
- piros quality gate mellett nem készít kiadható artifactot;
- a felhasználó számára világosan jelzi az offline, local AI, cloud és community állapotokat;
- támogatási és incident folyamattal rendelkezik;
- a launch után mérhetően javítja a gitárgyakorlási rendszerességet és minőséget.

---

# 2. Programalapelvek

## 2.1 Vertical slice mindenekelőtt

Minden release-nek végponttól végpontig használható tanulási útvonalat kell tartalmaznia. Egy vertical slice például:

```text
Felhasználó kiválaszt egy ritmusgyakorlatot
    → a mikrofon engedélye kontrollált
    → a Practice Engine elindul
    → a DSP strukturált megfigyelést ad
    → a session lezárható és menthető
    → a Progress frissül
    → a Gamification idempotensen jutalmaz
    → az AI Tutor bizonyíték alapján magyaráz
    → a Practice Generator következő feladatot javasol
```

Tilos olyan release-t kiadni, ahol a látványos felső réteg elkészült, de az adatmentés, hibakezelés, accessibility, migráció vagy rollback hiányos.

## 2.2 Offline core, opcionális online rétegek

A következő funkcióknek hálózat nélkül is működniük kell:

- onboarding és helyi profil;
- Live, Tuner és Metronome;
- Practice Engine;
- Song Trainer helyi dalokkal;
- Audio Analysis;
- Progress és Streak;
- deterministic tutor fallback;
- letöltött Offline AI modell;
- helyi gyakorlási terv;
- korábban szinkronizált közösségi tartalom olvasása, ahol értelmezhető.

A következő funkciók online kiegészítések:

- account és cloud settings sync;
- community feed, komment, reakció és klub;
- cloud tutor;
- modellcsomag és tudáscsomag letöltése;
- szerver által hitelesített challenge és leaderboard;
- béta feedback feltöltése explicit consent mellett.

Online hiba nem teheti használhatatlanná az offline tanulási felületet.

## 2.3 Reversible delivery

Minden kockázatos változtatás rendelkezzen legalább eggyel az alábbiak közül:

- feature flag;
- server-side kill switch;
- local capability gate;
- adatbázis backward-compatible migráció;
- modell rollback;
- előző app verzióval kompatibilis API;
- dual-read vagy dual-write átmenet;
- exportálható felhasználói backup;
- release channel visszavonás.

A visszagörgetés nem jelenthet felhasználói progress-, dal-, terv- vagy jutalomvesztést.

## 2.4 Evidence-driven release

Egy feature nem azért kerül release-be, mert „késznek tűnik”. Minden release decisionhez szükséges:

- zöld automatizált teszt;
- dokumentált valós eszközteszt;
- teljesítménymérés;
- privacy és security ellenőrzés;
- hozzáférhetőségi és lokalizációs ellenőrzés;
- migrációs teszt;
- rollback teszt;
- ismert korlátozások listája;
- release owner jóváhagyása.

## 2.5 Codex nem release manager

A Codex végrehajthat implementációs és dokumentációs feladatokat, de nem hozhat önállóan visszafordíthatatlan release-döntést.

Manuális jóváhagyás kötelező:

- production signing;
- production adatbázis-migráció;
- store submission;
- community moderation policy módosítása;
- privacy policy és terms publikálása;
- új AI modell aktiválása productionben;
- rollout százalék növelése;
- incident lezárása;
- felhasználói adat törlése vagy tömeges migrációja.

---

# 3. Kiinduló repository-állapot és release blokkolók

A program a `wolfcasaba/strumsight` publikus repository `main` branchére épül. A kiinduló kódbázis már jelentős DSP-, ML-, Flutter-, backend- és tesztinfrastruktúrát tartalmaz, de a jelenlegi állapotból közvetlenül nem készíthető production release.

## 3.1 Meglévő erősségek

- pure-Dart valós idejű DSP és CRNN inference;
- valós mikrofonfolyam és explicit engine interfészek;
- kiterjedt Flutter unit és property tesztcsomag;
- valós audio probe és külön ML training workflow-k;
- opcionális FastAPI account réteg;
- angol és magyar lokalizáció;
- local-first termékfilozófia;
- automatikus APK build;
- dokumentált handoff és iteratív fejlesztési kultúra.

## 3.2 Jelenlegi release blokkolók

A kiinduló snapshot és workflow-k alapján legalább az alábbi blokkolók rendezendők:

1. A Dart package név még `music_theory`.
2. A platformazonosítók és signing szabályok nem production-készek.
3. A release APK jelenleg debug keystore-ral is aláírható.
4. A versioning és release history nincs egyetlen auditált forráshoz kötve.
5. A build artifact nem tartalmaz kötelező provenance manifestet.
6. A Flutter CI és a backend CI nincs egyetlen release gate-be összefogva.
7. A Lab build és production build elkülönítését erősíteni kell.
8. A feature flag registry és kill switch policy még nem központi.
9. A backend production schema migrációját Alembicnek kell kezelnie.
10. Nincs teljes cross-feature contract és end-to-end tesztharness.
11. Nincs dokumentált production device matrix.
12. Nincs store release, privacy, support és incident readiness csomag.
13. Nincs staged rollout és rollback drill.
14. A korábbi Chapterek implementációja még program-szinten nincs sorrendbe rendezve.

A Chapter 12 ezeket nem egyetlen nagy refaktorral oldja meg. A blokkolók release trainenként és prioritási sorrendben kerülnek lezárásra.

---

# 4. SDD dependency graph és kritikus út

## 4.1 Fejezetfüggőségek

```text
Chapter 1  Architecture Principles
    ↓
Chapter 2  Core Platform & Infrastructure
    ├───────────────┬─────────────────┬─────────────────┐
    ↓               ↓                 ↓                 ↓
Chapter 3       Chapter 4         Chapter 7         Chapter 5
Practice        Song Trainer      Analysis 2.0      AI Tutor contracts
    │               │                 │                 │
    ├───────┬───────┴────────┬────────┘                 │
    ↓       ↓                ↓                          ↓
Chapter 8  Chapter 9      Chapter 6                 Chapter 11
Generator  Gamification  Computer Vision           Offline AI
    │       │                │                          │
    └───────┼────────────────┴──────────────┬───────────┘
            ↓                               ↓
        Chapter 10 Community            Final Integration
                    └───────────────────────┘
```

## 4.2 Kritikus út

A legfontosabb kritikus út:

```text
Core Platform
→ Audio lifecycle
→ Shared music/evidence contracts
→ Practice Engine
→ Progress persistence
→ Analysis evidence
→ Tutor context contracts
→ Practice Generator
→ Release quality gates
```

A Computer Vision, Community és generatív Offline AI nagy értékű, de nem blokkolhatja az első tanulási release-t. Ezek capability- és feature flag mögött későbbi trainben kapcsolhatók be.

## 4.3 Párhuzamosítható workstreamek

Biztonságosan párhuzamosítható:

- UI design system és backend migration, ha a contract stabil;
- content authoring és engine fejlesztés;
- Android device testing és backend load testing;
- accessibility audit és localization review;
- Community backend és Offline AI runtime bake-off, ha egyik sem módosít közös core contractot.

Nem párhuzamosítható kontroll nélkül:

- ugyanazon storage schema két migrációja;
- router és onboarding state egyidejű átírása;
- audio lifecycle és Live/Analyze engine tömeges refaktorja;
- reward ledger és legacy streak migráció;
- TutorModelGateway és Offline AI gateway szerződés egyidejű módosítása;
- production database migration és API contract breaking change.

---

# 5. Release scope rétegek

## 5.1 Core Learning Scope

Az első stabil tanulási termék kötelező részei:

- onboarding;
- Live és Tuner;
- Practice Engine legalább chord, rhythm és strumming móddal;
- helyi Song Trainer alapmód;
- Audio Analysis alapmetrikák;
- Progress, daily goal és streak;
- stabil storage migration;
- offline működés;
- angol és magyar UI;
- accessibility minimum;
- crash- és data-loss nélküli session lifecycle.

## 5.2 Intelligent Coaching Scope

A következő release train:

- AI Tutor deterministic és cloud gateway;
- evidence-alapú session debrief;
- AI Practice Generator;
- skill graph;
- confidence és provenance UI;
- Computer Vision opt-in preview;
- Offline AI capability preview támogatott eszközökön.

## 5.3 Engagement Scope

Későbbi train:

- idempotens XP és achievement;
- quest és challenge;
- community profile;
- following és feed;
- verified leaderboard;
- klub és közösségi megosztás;
- moderation és report rendszer.

## 5.4 GA scope szabály

General Availability release-be csak olyan capability kerülhet, amely:

- nem preview státuszú;
- rendelkezik support playbookkal;
- rendelkezik privacy adattérképpel;
- rendelkezik migrációs és rollback teszttel;
- a támogatott device matrixon teljesíti a minőségi kaput;
- nem növeli elfogadhatatlanul az app méretét vagy cold start idejét;
- nem igényel nem dokumentált manuális szerverbeavatkozást.

---

# 6. Release stage-ek

## 6.1 Development channel

Célközönség: fejlesztő és Codex által készített lokális build.

Jellemzők:

- debug vagy profile build;
- fake és fixture dependencyk;
- diagnosztikai overlay;
- részletes logok redaction mellett;
- nincs production adat;
- nincs store terjesztés.

## 6.2 Lab channel

Célközönség: explicit opt-in technikai tesztelők.

Jellemzők:

- külön application ID vagy channel marker;
- külön backend és token;
- diagnosztikai upload explicit consenttel;
- nyers audio csak külön megerősítéssel;
- rövid adatmegőrzés;
- nem használható production communityre vagy account adatra.

## 6.3 Internal Alpha

Célközönség: tulajdonos, fejlesztők, 5–15 megbízható tesztelő.

Kapuk:

- Core Platform kész;
- Practice vertical slice működik;
- storage migration stabil;
- nincs P0/P1 adatvesztés vagy mic leak;
- valós eszközteszt legalább három device tieren;
- signing és artifact provenance már production-szerű.

## 6.4 Closed Beta

Célközönség: 50–300 meghívott gitáros.

Kapuk:

- Song Trainer és Analysis stabil;
- Tutor és Generator legalább deterministic módban működik;
- feedback és support csatorna aktív;
- privacy policy és adatkezelési UI kész;
- migration és rollback drill sikeres;
- backend rate limit és moderation alapok aktívak.

## 6.5 Open Beta

Célközönség: szélesebb, kontrollált publikus tesztkör.

Kapuk:

- Gamification és Community alapfunkciók kész;
- verified leaderboard anti-cheat kapukkal;
- Offline AI opcionális és capability-gated;
- store listing draft kész;
- support SLA és incident on-call folyamat működik;
- crash-free és data-integrity célértékek tartósan teljesülnek.

## 6.6 Release Candidate

RC build csak akkor készülhet, ha:

- feature freeze aktív;
- kizárólag release blocker javítás merge-elhető;
- összes kötelező teszt zöld;
- release notes és migration notes kész;
- privacy, security és accessibility sign-off megtörtént;
- production backend deploy és rollback rehearsal sikeres;
- store package valid;
- nincs nyitott P0/P1 hiba;
- minden P2 hiba dokumentált és elfogadott.

## 6.7 General Availability

GA rollout fokozatos:

```text
Internal production cohort
→ 1%
→ 5%
→ 20%
→ 50%
→ 100%
```

A százalékok közötti továbblépés manuális döntés. Minden lépcsőn ellenőrizendő:

- crash és ANR;
- auth és sync error;
- migration failure;
- mic/camera lifecycle;
- backend latency és error rate;
- reward duplication;
- AI fallback és timeout;
- support ticket trend;
- rating és review jelzések;
- privacy vagy moderation incident.

---

# 7. Referencia roadmap — 36 kéthetes sprint

A referenciaütemezés akkor érvényes, ha a program 2026. augusztus 3-án indul. Ha a tényleges kezdés eltér, a sprintszám és a függőségek változatlanok maradnak, csak a dátumok tolódnak.

## 7.1 Fázisok

| Fázis | Sprintek | Referencia-időszak | Fő eredmény |
|---|---:|---|---|
| A — Foundation | 0–5 | 2026.08.03–2026.10.25 | Chapter 2, release baseline, stabil core |
| B — Core Learning | 6–13 | 2026.10.26–2027.02.14 | Practice, Song alap, Progress vertical slice |
| C — Analysis & Coaching | 14–20 | 2027.02.15–2027.05.23 | Analysis 2.0, Tutor, Generator |
| D — Vision & Engagement | 21–26 | 2027.05.24–2027.08.15 | Vision, Gamification, Closed Beta |
| E — Community & Offline AI | 27–31 | 2027.08.16–2027.10.24 | Community, Offline AI, Open Beta |
| F — RC & GA | 32–35 | 2027.10.25–2027.12.19 | Final integration, RC, staged GA |

## 7.2 Sprintenkénti cél

| Sprint | Fő cél | Kötelező kimenet |
|---:|---|---|
| 0 | Program baseline | auditált repo, SDD index, release history |
| 1 | Identity és config | package/app ID, environment, AppConfig |
| 2 | Failure, logging, storage | közös result/failure és migrátor |
| 3 | Network és backend alap | API factory, Alembic, health/readiness |
| 4 | Audio lifecycle | kizárólagos mic owner, lifecycle tesztek |
| 5 | CI és release foundation | signing, provenance, quality gate |
| 6 | Practice domain | session, exercise, observation contracts |
| 7 | Practice runtime | state machine, countdown, pause/resume |
| 8 | Rhythm és chord scoring | determinisztikus scorer, fixture corpus |
| 9 | Practice UI | setup, player, result, accessibility |
| 10 | Progress integration | practice log, skill evidence, daily goal |
| 11 | SongDocument V2 | migration és editor alap |
| 12 | Song playback | timeline, loop, tempo és transposition |
| 13 | Song scoring | chord/rhythm scoring, internal alpha gate |
| 14 | AnalysisDocument V2 | pipeline progress, cancellation, storage |
| 15 | Timing és tempo analysis | beat curve, rush/drag, confidence |
| 16 | Dynamics és pitch | signal quality, monophonic metrics |
| 17 | AI Tutor contracts | context, RAG, tool registry, safety |
| 18 | Tutor gateways | deterministic + cloud proxy, streaming |
| 19 | Practice Generator | policy engine, schedule, progression |
| 20 | Coaching integration | debrief → plan → practice vertical slice |
| 21 | Vision foundation | camera lifecycle, calibration, hand pose |
| 22 | Vision metrics | posture, guitar geometry, evidence sync |
| 23 | Gamification ledger | idempotens XP, achievements, streak V2 |
| 24 | Quest és challenge | daily/weekly quest, verified result |
| 25 | Closed Beta | beta distribution, feedback, support |
| 26 | Stabilizáció | P0/P1 javítás, device és performance gate |
| 27 | Community foundation | profile, follow, privacy, moderation |
| 28 | Feed és interaction | post, comment, reaction, notification |
| 29 | Challenge és leaderboard | verified result, anti-cheat, clubs |
| 30 | Offline AI runtime | bake-off, model package, local gateway |
| 31 | Offline AI product | RAG, tool calling, model manager, Open Beta |
| 32 | Feature freeze | contract lock, migration rehearsal, store draft |
| 33 | Release Candidate | full E2E, security, accessibility, RC build |
| 34 | Staged rollout | internal → 1% → 5% → 20% |
| 35 | GA és stabilization | 50% → 100%, support, completion report |

## 7.3 Kapacitási feltételezés

A referencia alapja:

- egy projektgazda;
- Codex mint elsődleges implementációs partner;
- heti 20–30 fókuszált fejlesztési óra;
- sprintenként 4–8 kis Codex-kör;
- legalább 20% kapacitás tesztre, review-ra és dokumentációra;
- minden negyedik sprintben kötelező stabilizációs tartalék;
- komplex natív, ML vagy store feladathoz célzott emberi szakértő bevonható.

Ha több fejlesztő dolgozik a projekten, csak az egymástól izolált workstreamek gyorsíthatók. A kritikus út contractjai és migrációi nem rövidíthetők pusztán párhuzamosítással.

---

# 8. Sprint operating model

## 8.1 Sprint ciklus

Minden kéthetes sprint:

1. **Planning:** cél, scope, függőség, kockázat és mérési terv.
2. **Implementation:** kis Codex-körökben, külön commitokkal.
3. **Continuous verification:** format, analyze, unit, contract és célzott integration teszt.
4. **Mid-sprint demo:** működő vertical slice vagy technikai bizonyíték.
5. **Hardening:** hibakezelés, accessibility, localization, migration.
6. **Sprint review:** acceptance evidence és benchmark.
7. **Retrospective:** mi lassított, milyen guard vagy tool szükséges.
8. **Handoff:** pontos következő kör és ismert kockázatok.

## 8.2 Sprint goal szabály

Egy sprintnek egy fő eredménye legyen. Tilos egyetlen sprint goalba összemosni:

- core refaktort;
- új feature-t;
- adatbázis breaking change-et;
- nagy UI-redesignt;
- modellcserét;
- production rolloutot.

## 8.3 WIP limit

Egy fejlesztő + Codex baseline:

```text
1 aktív architekturális változás
1 aktív feature vertical slice
1 aktív stabilizációs vagy dokumentációs feladat
```

Új feladat csak akkor indulhat, ha az előző kör:

- commitolt;
- tesztelt;
- dokumentált;
- vagy explicit blocked státuszba került pontos okkal.

## 8.4 Sprint completion evidence

Minden sprint végén archiválandó:

- commit és PR lista;
- tesztparancsok és eredmény;
- benchmark vagy mérési report;
- screenshot/video csak UX bizonyítékhoz;
- migration report;
- nyitott hibák severityvel;
- feature flag állapot;
- következő sprint előfeltételei.

---

# 9. Backlog és issue hierarchia

## 9.1 Hierarchia

```text
Program
  → Chapter / Epic
      → Capability
          → Codex development round
              → Task / test / documentation item
```

## 9.2 Kötelező issue mezők

Minden implementációs issue tartalmazza:

- cél;
- felhasználói vagy technikai érték;
- érintett chapter és kör;
- előfeltételek;
- scope;
- out of scope;
- érintett fájlok vagy komponensek;
- adat- és privacy hatás;
- failure mode;
- tesztek;
- acceptance criteria;
- rollback vagy feature flag;
- Definition of Done;
- becsült kockázat.

## 9.3 Label rendszer

Javasolt label-ek:

```text
chapter:02 ... chapter:12
area:flutter
area:audio
area:backend
area:ml
area:vision
area:ai
area:community
area:release
risk:low
risk:medium
risk:high
priority:p0
priority:p1
priority:p2
priority:p3
type:feature
type:refactor
type:test
type:docs
type:security
status:blocked
```

## 9.4 Severity

- **P0:** adatvesztés, privacy breach, security compromise, széles körű crash, hibás reward vagy account corruption.
- **P1:** core learning flow használhatatlan, mic/camera nem áll le, migration széles körben hibás, login vagy sync tartósan kiesik.
- **P2:** jelentős feature hiba működő workarounddal, performance regresszió, lokalizációs vagy accessibility blokk.
- **P3:** kisebb UX, vizuális vagy dokumentációs hiba.

P0 és P1 mellett rollout nem növelhető.

---

# 10. Git és review stratégia

## 10.1 Branch modell

```text
main
  stabil integrációs branch, mindig zöld

codex/chXX-round-YY-description
  kis fejlesztési kör

release/<train-name>
  csak RC időszakban, rövid életű

hotfix/<issue>
  production blocker javítás
```

Hosszú életű `develop` branch nem szükséges. A feature flag biztosítsa, hogy félkész capability merge-elhető legyen kikapcsolt állapotban.

## 10.2 Merge policy

- squash merge javasolt egy Codex-körre;
- PR title Conventional Commit formátumú;
- zöld required check kötelező;
- unresolved review thread mellett nincs merge;
- high-risk PR-hez manuális review checklist;
- generated model vagy binary asset változás külön manifesttel;
- dependency lockfile változás magyarázattal;
- breaking contract változás ADR-rel.

## 10.3 Branch protection

A `main` ágon:

- direct push tiltott;
- required PR;
- required Flutter CI;
- required backend CI, ha backend érintett;
- required architecture gate;
- required model integrity gate, ha asset érintett;
- signed vagy hitelesített commit policy a lehetőségek szerint;
- force push tiltott;
- branch delete tiltott.

---

# 11. Versioning és release naming

## 11.1 Release history audit

A jelenlegi `pubspec.yaml` verziója önmagában nem bizonyítja, hogy történt-e publikus GA release. Az első release management körben auditálandó:

- Play Store vagy más store history;
- korábban terjesztett APK-k;
- package/application ID;
- installált tesztverziók;
- backend API verzió;
- adatbázis schema verzió.

Ha még nem volt publikus GA, ADR dönthet pre-1.0 semantic versionről. Ha volt publikus release, verziót csökkenteni tilos.

## 11.2 Verzió komponensek

```text
App semantic version: MAJOR.MINOR.PATCH
Build number: monoton növekvő egész
API version: /api/v1
Storage schema version: külön egész
Database migration revision: Alembic revision
Model package version: semantic + checksum
Knowledge package version: semantic + locale
Content catalog version: semantic
```

## 11.3 Artifact név

```text
strumsight-<semver>-<build>-<sha>-<environment>-<abi>.aab
strumsight-<semver>-<build>-<sha>-lab.apk
strumsight-backend-<image-tag>-<sha>
strumsight-model-<model-id>-<version>-<sha256>.zip
```

## 11.4 Build provenance

Minden artifact tartalmazzon vagy mellékeljen manifestet:

- Git commit SHA;
- branch vagy tag;
- build timestamp UTC;
- Flutter és Dart verzió;
- Java/Gradle verzió;
- Python verzió a backendhez;
- dependency lock hash;
- feature flag profile;
- environment;
- model manifest hash;
- signing certificate fingerprint;
- CI run azonosító.

---

# 12. Environment és release channel mátrix

| Tulajdonság | Development | Lab | Staging | Production |
|---|---|---|---|---|
| Application ID | dev suffix | lab suffix | internal/prod-like | production |
| Backend | local/mock | lab | staging | production |
| Adat | fixture | tesztelői opt-in | szintetikus/anonym | valódi |
| Diagnostics | részletes | consenttel | redacted | minimális |
| Raw audio upload | tiltott alapból | explicit consent | kontrollált | tiltott |
| Community | fake/staging | staging | staging | production |
| AI cloud | mock/test | staging provider | staging | production consenttel |
| Signing | debug/dev | internal | internal secure | production secure |
| Distribution | local | artifact/internal | internal testing | staged store rollout |

Environmentek között account, token, media és adatbázis nem keverhető.

---

# 13. Feature flag és kill switch rendszer

## 13.1 Flag típusok

- compile-time environment flag;
- local persisted preference;
- capability flag;
- signed remote release flag;
- server-side endpoint flag;
- cohort rollout flag;
- emergency kill switch.

## 13.2 Kötelező flag metadata

```dart
final class FeatureFlagDefinition {
  const FeatureFlagDefinition({
    required this.key,
    required this.owner,
    required this.defaultValue,
    required this.environments,
    required this.expiresAfter,
    required this.rollbackBehavior,
  });

  final String key;
  final String owner;
  final bool defaultValue;
  final Set<AppEnvironment> environments;
  final DateTime? expiresAfter;
  final String rollbackBehavior;
}
```

## 13.3 Fail-closed szabályok

Productionben alapértelmezetten kikapcsolt:

- Lab diagnostics;
- raw audio upload;
- experimental exact fret recognition;
- unverified leaderboard;
- local AI ismeretlen modellen;
- cloud AI consent nélkül;
- community media upload moderation nélkül;
- destructive migration;
- developer overlay.

## 13.4 Flag takarítás

Egy flag nem maradhat örökké. Minden flag rendelkezzen:

- ownerrel;
- létrehozási dátummal;
- eltávolítási feltétellel;
- mérési céllel;
- cleanup issue-val.

---

# 14. Cross-feature integration contract

## 14.1 Közös események

A feature-ök nem olvashatják egymás belső storage-át. Integráció közös domain eseményekkel és public API-val történik.

Kötelező eseménycsaládok:

```text
PracticeSessionCompleted
SongAttemptCompleted
AnalysisDocumentCreated
VisionEvidenceCreated
PracticePlanGenerated
PracticePlanAdjusted
TutorDebriefCreated
RewardGranted
AchievementUnlocked
ChallengeResultVerified
CommunityPostPublished
UserConsentChanged
ModelPackageActivated
StorageMigrationCompleted
```

## 14.2 Esemény envelope

```dart
final class DomainEventEnvelope<T> {
  const DomainEventEnvelope({
    required this.eventId,
    required this.eventType,
    required this.schemaVersion,
    required this.occurredAt,
    required this.idempotencyKey,
    required this.source,
    required this.payload,
  });

  final String eventId;
  final String eventType;
  final int schemaVersion;
  final DateTime occurredAt;
  final String idempotencyKey;
  final String source;
  final T payload;
}
```

## 14.3 Idempotencia

Ugyanaz a session completion:

- egyszer frissítheti a progresszt;
- egyszer adhat XP-t;
- egyszer számíthat streakbe;
- egyszer hozhat létre challenge resultot;
- többször újraolvasható és újrapróbálható adatvesztés nélkül.

A hálózati retry, app restart és offline sync nem duplikálhat jutalmat vagy közösségi posztot.

## 14.4 Contract versioning

- additive mező alapértelmezéssel megengedett;
- mező törlése vagy jelentésmódosítása új schema version;
- consumernek ismeretlen mezőt tolerálnia kell;
- ismeretlen enum controlled unknown értékre essen;
- breaking eventhez migration és dual-read szükséges.

---

# 15. Adat- és migrációs stratégia

## 15.1 Adatkategóriák

- settings;
- secure auth token;
- local profile;
- practice history;
- song és setlist;
- analysis document;
- skill evidence;
- plan és schedule;
- reward ledger;
- community outbox/cache;
- tutor conversation;
- local model metadata;
- consent és privacy preference.

## 15.2 Migrációs elvek

- minden schema verziózott;
- migráció idempotens;
- régi adat csak sikeres új írás után törölhető;
- migration előtt szükség esetén backup;
- hiba esetén read-only recovery mód;
- részleges hiba nem törölhet más feature adatot;
- a migration report exportálható;
- downgrade támogatás helyett forward-compatible read preferált, ahol reális.

## 15.3 Production migration rehearsal

Minden RC előtt:

1. anonimizált vagy szintetikus legacy fixture létrehozása;
2. előző production verzió telepítése;
3. valós adatszerkezet generálása;
4. RC-re frissítés;
5. minden feature adat ellenőrzése;
6. app kill és restart migráció közben;
7. alacsony tárhely teszt;
8. storage corruption teszt;
9. rollback és újra-upgrade teszt;
10. report archiválása.

---

# 16. Quality gate rendszer

## 16.1 Pull request gate

- format;
- static analyze;
- unit tests;
- architecture dependency test;
- affected contract tests;
- affected serialization tests;
- secret scan;
- dependency audit;
- asset manifest verification.

## 16.2 Nightly gate

- teljes Flutter test;
- property tests random seed-del;
- backend test;
- migration smoke;
- end-to-end happy paths;
- deterministic audio fixtures;
- model package integrity;
- localization parity;
- accessibility static audit.

## 16.3 Weekly gate

- valós eszköztesztek;
- real-audio regression corpus;
- performance benchmark;
- memory/leak soak;
- backend load smoke;
- AI quality evaluation;
- security scan;
- open-source license report.

## 16.4 Release gate

- clean checkout reproducible build;
- production signing;
- artifact provenance;
- SBOM;
- database migration rehearsal;
- device matrix pass;
- privacy sign-off;
- accessibility sign-off;
- localization sign-off;
- store package validation;
- rollout és rollback drill;
- support és incident readiness.

---

# 17. Tesztstratégia és végponttól végpontig forgatókönyvek

## 17.1 Kötelező E2E utak

### Offline kezdő felhasználó

```text
fresh install
→ onboarding
→ microphone permission
→ tuner
→ first practice
→ result
→ progress
→ app restart
→ history restored
```

### Visszatérő tanuló

```text
daily plan
→ practice block
→ song section
→ analysis
→ tutor debrief
→ streak and reward
→ next-day schedule
```

### Offline–online átmenet

```text
offline practice
→ reward ledger update
→ community share queued
→ network returns
→ authenticated sync
→ no duplicate reward/post
```

### Helyi AI

```text
model installed
→ local-only mode
→ session evidence
→ retrieval
→ token stream
→ stop
→ tool proposal
→ user confirmation
→ valid practice action
```

### Adatmigráció

```text
legacy app data
→ update
→ migration interruption
→ restart
→ migration resume
→ no data loss
```

### Rollback

```text
new feature flag on
→ error threshold exceeded
→ remote kill switch
→ core learning remains available
```

## 17.2 Failure injection

Tesztelendő:

- permission denied;
- mic plugin exception;
- camera unavailable;
- audio focus elvesztése;
- process kill;
- alacsony memória;
- alacsony tárhely;
- database unavailable;
- timeout és connection reset;
- 401 és expired token;
- duplicate event;
- out-of-order sync;
- corrupt model package;
- signature mismatch;
- thermal throttling;
- backend partial outage;
- moderation service unavailable.

---

# 18. Device matrix

## 18.1 Android tier-ek

Legalább:

- alacsony memória / régebbi támogatott Android;
- középkategóriás referenciaeszköz;
- modern flagship;
- különböző gyártói audio stack;
- legalább egy olyan készülék, ahol a background lifecycle agresszív;
- headset és beépített mikrofon;
- 44.1 kHz és 48 kHz viselkedés;
- különböző képarány és display density.

## 18.2 Kötelező mérés eszközönként

- install és update;
- cold start;
- Live start latency;
- mic release;
- 20 perces practice soak;
- Analyze memory peak;
- camera preview és thermal;
- local AI load és TTFT, ha támogatott;
- background/resume;
- battery saver;
- airplane mode;
- low storage;
- text scale 200%;
- screen reader alapútvonal.

## 18.3 Device support policy

Támogatott eszközön a core learning működik. A Vision és Offline AI külön capability matrix alapján lehet korlátozott vagy nem elérhető. Az app nem állíthatja, hogy az egész készülék inkompatibilis csak azért, mert a helyi generatív modell nem fut rajta.

---

# 19. Teljesítmény- és erőforrás-budget

A pontos célértékeket baseline mérésből kell véglegesíteni. Kötelező budget kategóriák:

- app cold start;
- first interactive frame;
- Live start;
- audio frame processing;
- UI dropped frame;
- 20 perces memory growth;
- Analysis throughput;
- camera FPS és latency;
- local AI TTFT és token/s;
- cancellation latency;
- app package méret;
- model package méret;
- backend p50/p95/p99 latency;
- sync payload méret;
- battery és thermal trend.

Release blocker:

- dokumentálatlan 5%-nál nagyobb core audio regresszió;
- tartós memória-szivárgás;
- mic vagy camera resource leak;
- UI isolate-ban futó nehéz inference;
- local AI miatt használhatatlan Practice vagy Live;
- store limithez közelítő indokolatlan package-növekedés.

---

# 20. AI, ML és content release governance

## 20.1 Modellrelease

Minden modellhez:

- model card;
- license;
- training/evaluation source;
- checksum;
- input/output contract;
- supported runtime;
- device tier;
- quality report;
- safety report;
- rollback target.

## 20.2 DSP és scoring változás

Scoring vagy detector változás csak akkor release-elhető, ha:

- fixture regresszió zöld;
- real-audio report friss;
- korábbi shipping verzióval összehasonlítás készült;
- skill/reward hatás elemzett;
- nem növeli mesterségesen a pontszámot;
- challenge integrity megmarad.

## 20.3 Tudás- és tartalomcsomag

A lesson, RAG és exercise catalog:

- verziózott;
- locale-onként validált;
- source/provenance mezővel rendelkezik;
- offline telepíthető;
- kompatibilitást deklarál az app és skill schema verzióval;
- hibás csomag esetén visszagörgethető.

---

# 21. Security, privacy és compliance readiness

## 21.1 Threat model scope

- account takeover;
- token leak;
- API abuse;
- diagnostics abuse;
- media upload attack;
- path traversal;
- leaderboard manipulation;
- reward replay;
- community spam és harassment;
- prompt injection;
- model package tampering;
- local database extraction;
- supply-chain dependency compromise;
- signing key compromise.

## 21.2 Privacy adattérkép

Minden adatmezőhöz rögzítendő:

- cél;
- forrás;
- local vagy server storage;
- retention;
- törlési mód;
- exportálhatóság;
- consent szükségesség;
- logolhatóság;
- community visibility;
- gyermek vagy érzékeny adat kockázat.

## 21.3 Kötelező felhasználói kontroll

- account nélkül használható core;
- analytics opt-out, ha analytics aktív;
- diagnostics külön opt-in;
- community profile visibility;
- block/report;
- conversation és local AI history törlése;
- model package törlése;
- account és server data törlési flow;
- adat export, ahol kötelező vagy termékileg indokolt.

## 21.4 Supply chain

Release előtt:

- dependency lock;
- secret scan;
- SBOM;
- license inventory;
- pinned CI action verziók vagy digest policy;
- model és dataset provenance;
- artifact signature;
- signing key access audit.

---

# 22. Observability és analytics

## 22.1 Privacy-safe observability

Megengedett aggregált esemény:

- app version;
- environment;
- feature flag cohort;
- operation success/failure code;
- duration bucket;
- device capability tier;
- network state category;
- migration result;
- model/runtime identifier;
- crash és ANR technikai metadata.

Tilos alapértelmezésként:

- nyers audio;
- videóframe;
- teljes tutor prompt vagy válasz;
- jelszó vagy token;
- teljes e-mail;
- community private draft;
- pontos gitárfelvétel tartalma.

## 22.2 Product metric-ek

Elsődleges:

- első sikeres practice completion;
- 1., 7. és 30. napi visszatérés;
- heti gyakorlási napok;
- session completion rate;
- plan adherence;
- skill evidence javulás;
- song section mastery;
- tutor answer helpfulness;
- streak fenntarthatóság;
- crash-free users;
- data migration success.

Guardrail:

- túl hosszú sessionből eredő fáradás;
- büntető streak viselkedés;
- túlzott notification;
- alaptalan AI claim;
- reward inflation;
- community abuse rate;
- battery/thermal panasz;
- uninstall vagy account deletion trend.

## 22.3 SLO-k

A végleges számokat béta alapján kell rögzíteni. SLO kategóriák:

- backend availability;
- auth success;
- sync success;
- community write success;
- migration success;
- crash-free sessions;
- local AI successful completion;
- model download integrity;
- support response idő.

---

# 23. Backend operation és költségkontroll

## 23.1 Környezetek

- local;
- CI ephemeral;
- staging;
- production.

Minden környezet külön:

- database;
- secret;
- media bucket;
- model package bucket;
- domain;
- logging sink;
- rate limit konfiguráció.

## 23.2 Production readiness

- infrastructure as code vagy reprodukálható deploy script;
- Alembic migration;
- backup és restore;
- database connection pool;
- health és readiness;
- structured log redaction;
- rate limit;
- media size/type validation;
- background job policy;
- secret rotation;
- dependency patching;
- capacity dashboard.

## 23.3 Költség guard

Minden fizetős erőforráshoz:

- owner;
- havi projektlimit;
- usage alert;
- hard vagy soft cap;
- fallback viselkedés;
- törlési/retention policy.

Cloud AI nem használható korlátlanul. Költségtúllépésnél a rendszer local vagy deterministic módra válthat, de ezt a felhasználónak jelezni kell.

---

# 24. Beta program

## 24.1 Tesztelői cohortok

- teljesen kezdő;
- 3–12 hónap tapasztalat;
- középhaladó;
- akusztikus és elektromos gitár;
- balkezes;
- különböző telefon tier;
- angol és magyar nyelv;
- gyenge vagy nincs internet;
- accessibility igény.

## 24.2 Feedback csatorna

A feedback tartalmazhat:

- feature;
- app version;
- device tier;
- issue category;
- severity;
- reprodukciós lépések;
- opcionális screenshot;
- opcionális diagnosztikai csomag explicit consenttel.

Nyers audio feltöltése külön, második megerősítést igényel.

## 24.3 Beta triage

- P0 azonnali rollout stop;
- P1 24 órán belüli owner review;
- P2 sprintbe priorizálva;
- P3 backlog;
- duplikátumok összekapcsolása;
- AI vagy scoring panaszhoz evidence és model version szükséges;
- privacy és safety report külön csatorna.

---

# 25. Store és distribution readiness

Kötelező csomag:

- production application ID;
- production signing;
- AAB build;
- verzió és build number;
- app icon és adaptive icon;
- splash;
- store description;
- screenshotok valós UI-ról;
- privacy policy;
- terms vagy community guidelines, ahol szükséges;
- permission rationale;
- data safety nyilatkozat;
- support elérhetőség;
- release notes;
- internal, closed, open és production track mapping;
- account deletion flow leírása;
- content moderation és report flow leírása, ha Community aktív.

A store szöveg nem állíthat orvosi, professzionális vagy garantált tanulási eredményt. Az AI és vision korlátait világosan kell közölni.

---

# 26. Rollout, kill switch és rollback

## 26.1 Rollout decision packet

Minden lépcső előtt:

- build és commit;
- active flags;
- migration version;
- model version;
- known issues;
- dashboard snapshot;
- support readiness;
- rollback target;
- döntéshozó.

## 26.2 Automatikus riasztás, manuális döntés

A rendszer riaszthat threshold alapján, de a rollout stop vagy növelés manuális. P0 esetén előre engedélyezett emergency kill switch automatikusan kikapcsolhat izolált online feature-t, de nem törölhet adatot.

## 26.3 Rollback sorrend

1. cohort rollout megállítása;
2. kockázatos feature flag kikapcsolása;
3. backend endpoint vagy job korlátozása;
4. modellcsomag rollback;
5. app release rollback vagy hotfix;
6. adat-helyreállítás csak ellenőrzött runbook szerint.

---

# 27. Incident response és support

## 27.1 Incident severity

- **SEV-0:** aktív adatvédelmi vagy security breach.
- **SEV-1:** széles körű adatvesztés, crash loop, hibás migration vagy account corruption.
- **SEV-2:** core feature jelentős kiesése, backend részleges leállás, reward vagy leaderboard integritási hiba.
- **SEV-3:** korlátozott feature hiba vagy degradáció.

## 27.2 Runbook minimum

- incident commander;
- kommunikációs csatorna;
- érintett verzió és cohort;
- first containment;
- kill switch;
- rollback;
- adatellenőrzés;
- felhasználói kommunikáció;
- postmortem;
- regressziós teszt;
- prevention task.

## 27.3 Support tudásbázis

Legalább:

- mikrofonengedély;
- nincs hangfelismerés;
- tuner eltérés;
- latency calibration;
- app update és migration;
- account/login;
- offline működés;
- local AI modell letöltés és törlés;
- community report és block;
- adat export/törlés;
- battery és thermal viselkedés.

---

# 28. Final integration matrix

| Producer | Esemény/adat | Consumer | Kötelező guard |
|---|---|---|---|
| Practice | Session result | Progress | idempotency |
| Practice | Skill evidence | Generator | confidence + schema |
| Practice | Completion | Gamification | verified source |
| Song | Attempt result | Analysis/Tutor | timeline version |
| Analysis | AnalysisDocument | Tutor/Generator | provenance |
| Vision | VisionEvidence | Tutor/Analysis | consent + confidence |
| Generator | Plan | Practice | catalog validation |
| Tutor | Action proposal | Practice/Settings | confirmation |
| Gamification | Reward ledger | Community profile | privacy visibility |
| Challenge | Verified result | Leaderboard | anti-replay |
| Community | Post/report | Moderation | rate limit |
| Offline AI | Model state | Tutor UI | capability + origin |
| Consent | Preference change | minden érintett feature | immediate enforcement |

Minden sorhoz contract test, error mapping és fallback szükséges.

---

# 29. Launch success és exit criteria

## 29.1 Technical exit criteria

- nincs nyitott P0/P1;
- zöld release CI;
- sikeres migration rehearsal;
- sikeres rollback rehearsal;
- támogatott device matrix zöld;
- core offline E2E zöld;
- crash-free és ANR cél teljesül;
- backend SLO teljesül;
- privacy/security sign-off;
- accessibility/localization sign-off;
- model/content manifest valid;
- production signing és provenance valid.

## 29.2 Product exit criteria

- új felhasználó segítség nélkül teljesít első gyakorlatot;
- a session eredmény érthető;
- a következő javasolt lépés világos;
- daily plan nem túlterhelő;
- streak nem büntető;
- tutor megkülönbözteti a mérést és következtetést;
- offline állapot érthető;
- community privacy beállítás egyszerű;
- tesztelők többsége újra használja az appot legalább egy héten belül.

## 29.3 Go/no-go

No-go, ha:

- adatvesztés reprodukálható;
- mic vagy camera nem szabadul fel;
- migration failure nem recoverable;
- signing/provenance bizonytalan;
- AI rendszeresen kitalál mért adatot;
- challenge jutalom duplikálható;
- community report nem működik;
- privacy consent figyelmen kívül marad;
- rollback nincs gyakorolva.

---

# 30. Fő kockázatok és contingency

## 30.1 Scope túlterhelés

Kockázat: mind a tíz Epic teljes scope-ja túl nagy egyetlen release-hez.

Válasz:

- GA scope Core Learning + stabil coaching;
- Vision, Community és Offline AI capability-gated;
- preview feature nem blokkolhatja core release-t;
- minden sprintben scope cut list.

## 30.2 Audio pontosság valós környezetben

Válasz:

- real-audio corpus;
- confidence és signal quality;
- honesty-first UX;
- detector/scoring verziózás;
- manual calibration és fallback.

## 30.3 Offline AI eszközfragmentáció

Válasz:

- device tier;
- runtime bake-off;
- optional model download;
- deterministic fallback;
- kill switch és package rollback.

## 30.4 Backend/Community üzemeltetési teher

Válasz:

- aszinkron community MVP;
- nincs privát üzenet az első release-ben;
- rate limit és moderation queue;
- retention és cost cap;
- staged cohort.

## 30.5 Codex által okozott nagy refaktor

Válasz:

- kis körök;
- fájl- és scope limit;
- explicit out of scope;
- architecture guard;
- test-first regresszió;
- PR diff review;
- automatikus handoff.

---

# 31. Codex végrehajtási protokoll

Minden alábbi kör külön branchben vagy külön, önálló commitban hajtandó végre.

A Codex minden kör elején:

1. olvassa el az `AGENTS.md` fájlt;
2. olvassa el a Chapter 12-t és a hivatkozott korábbi fejezetet;
3. ellenőrizze a repository aktuális állapotát;
4. írja le a módosítandó fájlokat;
5. futtassa az érintett baseline tesztet;
6. csak az adott kör scope-ját valósítsa meg.

Minden kör végén:

- formázás;
- statikus ellenőrzés;
- célzott teszt;
- teljes regresszió, ha core contract változott;
- dokumentációfrissítés;
- `HANDOFF.md` frissítés;
- módosított fájlok és kockázatok jelentése;
- következő kör megkezdése nélkül megállás.

---

# Kör 1 — Program baseline és release history audit

## Cél

A tényleges kiinduló állapot, a publikus release history és az összes blokkoló bizonyítható dokumentálása.

## Feladatok

- Készíts auditot a pubspec verzióról, package ID-ról, korábbi APK/AAB artifactokról és store historyról.
- Rögzítsd a main branch, CI workflow-k, signing, backend, model asset és migration állapotát.
- Hozd létre a release blocker listát ownerrel, severityvel és kapcsolódó Chapterrel.
- Ne módosíts production kódot ebben a körben.

## Fő érintett fájlok

```text
docs/release/program-baseline.md
docs/release/release-history-audit.md
docs/release/blockers.md
```

## Kötelező tesztek és ellenőrzések

- Dokumentumok belső linkjeinek és fájlútvonalainak ellenőrzése.
- Minden állítás repository bizonyítékhoz kötött.

## Elfogadási feltételek

- [ ] A publikus/pre-release verzióstratégia eldönthető.
- [ ] Minden P0/P1 release blocker látható.
- [ ] Nincs alkalmazáskód-változás.

## Javasolt commit

```text
docs(release): establish program and release baseline
```

---

# Kör 2 — SDD index és dependency graph

## Cél

A 12 Chapter egyetlen navigálható, verziózott programindexbe rendezése.

## Feladatok

- Hozd létre a Chapter indexet státusz, dependency és implementation progress mezőkkel.
- Generálj géppel olvasható dependency manifestet.
- Jelöld a kritikus utat és a capability-gated feature-öket.
- Adj ellenőrzést a hiányzó vagy duplikált Chapter fájlokra.

## Fő érintett fájlok

```text
docs/sdd/00-index.md
docs/sdd/dependency-graph.yaml
tool/check_sdd_index.dart
```

## Kötelező tesztek és ellenőrzések

- Az index minden Chaptert pontosan egyszer tartalmaz.
- A dependency graph körmentes.
- Minden hivatkozott fájl létezik.

## Elfogadási feltételek

- [ ] A Codex egyértelműen megtalálja az aktuális fejezetet.
- [ ] A kritikus út automatikusan ellenőrizhető.

## Javasolt commit

```text
docs(sdd): add program index and dependency graph
```

---

# Kör 3 — GitHub delivery workflow, branch protection és review policy

## Cél

Egységes backlog, PR evidence, review ownership és védett main branch kialakítása.

## Feladatok

- Készíts feature, bug, security, migration és release issue template-et.
- Adj kötelező mezőt Chapter, kör, privacy, rollback, teszt és acceptance számára.
- Dokumentáld a label- és severity-rendszert.
- Készíts PR template-et release evidence checklisttel.
- Hozz létre CODEOWNERS szabályokat audio, backend, security, model és release területre.
- Dokumentáld a required check és merge policyt.
- Adj scriptet a branch protection elvárt beállításainak auditálására, ahol API jogosultság elérhető.
- Tiltsd a release asset változás magyarázat nélküli merge-ét.

## Fő érintett fájlok

```text
.github/ISSUE_TEMPLATE/
.github/pull_request_template.md
docs/process/backlog-policy.md
.github/CODEOWNERS
docs/process/branch-protection.md
tool/audit_repository_policy.py
```

## Kötelező tesztek és ellenőrzések

- Template YAML vagy Markdown validáció.
- A kötelező mezők minden releváns template-ben szerepelnek.
- CODEOWNERS path minták fixture tesztje.
- Policy audit dry-run.

## Elfogadási feltételek

- [ ] Új feladat nem jöhet létre scope és acceptance nélkül.
- [ ] Release PR tartalmaz rollback és teszt evidence részt.
- [ ] Kritikus fájlokhoz kijelölt review owner tartozik.
- [ ] A main direct push és force push policy dokumentált.

## Javasolt commit

```text
chore(process): standardize backlog and pull request evidence
```

---

# Kör 4 — Environment és channel konfiguráció lezárása

## Cél

Development, Lab, Staging és Production teljes, fail-closed elkülönítése.

## Feladatok

- Egységesítsd az AppConfig és backend Settings environment értékeit.
- Adj külön application ID/channel marker stratégiát.
- Biztosítsd, hogy production nem olvashat Lab tokent vagy endpointot.
- Készíts environment matrix contract teszteket.

## Fő érintett fájlok

```text
lib/app/config/
backend/app/config.py
docs/release/environment-matrix.md
test/app/config/
```

## Kötelező tesztek és ellenőrzések

- Production localhost és Lab secret elutasítás.
- Development fixture config elfogadása.
- Channel marker UI teszt.

## Elfogadási feltételek

- [ ] A négy környezet adata és secretje nem keverhető.
- [ ] Production fail-closed.

## Javasolt commit

```text
refactor(config): finalize isolated release environments
```

---

# Kör 5 — Feature flag registry és emergency kill switch

## Cél

Minden kockázatos capability központi, auditálható és eltávolítható flag mögé helyezése.

## Feladatok

- Implementáld a typed FeatureFlagDefinition katalógust.
- Adj local, capability, signed remote és emergency flag forrást prioritási szabállyal.
- Készíts flag expiration auditot.
- Védd a Vision preview, Offline AI, Community write és cloud tutor feature-öket.

## Fő érintett fájlok

```text
lib/app/config/feature_flags.dart
lib/core/feature_flags/
tool/check_feature_flags.dart
docs/release/kill-switches.md
```

## Kötelező tesztek és ellenőrzések

- Fail-closed default.
- Lejárt flag audit.
- Remote signature failure fallback.
- Kill switch nem töröl adatot.

## Elfogadási feltételek

- [ ] Minden high-risk feature távolról vagy lokálisan izolálható.
- [ ] Flag owner és cleanup feltétel rögzített.

## Javasolt commit

```text
feat(release): add typed feature flags and emergency controls
```

---

# Kör 6 — Versioning, provenance, SBOM és release manifest

## Cél

Minden app-, backend- és modellartifact egyértelmű verziózásának, provenance-ának és supply-chain csomagjának létrehozása.

## Feladatok

- A release history audit alapján készíts ADR-t a semantic versioningről.
- Automatizáld a build number és Git SHA beágyazását.
- Generálj release manifestet minden Flutter artifact mellé.
- Jelenítsd meg a verziót és channel-t a Settings/Diagnostics felületen.
- Generálj Flutter/Android dependency inventoryt és SBOM-ot.
- Generálj backend SBOM-ot és Python license reportot.
- Kapcsold a model manifestet a release manifesthez.
- Csomagold a third-party notice és license fájlokat.

## Fő érintett fájlok

```text
docs/adr/versioning.md
tool/generate_release_manifest.dart
lib/app/build_info.dart
.github/workflows/
tool/release/generate_sbom.py
THIRD_PARTY_NOTICES.md
docs/release/supply-chain.md
.github/workflows/release-android.yml
```

## Kötelező tesztek és ellenőrzések

- Manifest determinisztikus mezők.
- Build number monoton szabály.
- Settings megjelenítés.
- Hiányzó license vagy model checksum blokkol.
- SBOM artifact feltöltés ellenőrzése.

## Elfogadási feltételek

- [ ] Minden artifact commitig visszakövethető.
- [ ] Version decrease nem lehetséges publikus release után.
- [ ] Minden release dependency és modell visszakövethető.
- [ ] License konfliktus release előtt látható.

## Javasolt commit

```text
feat(build): add versioned release provenance manifest
```

---

# Kör 7 — Production signing és secret hardening

## Cél

A debug-aláírású release lehetőségének megszüntetése és a signing folyamat védelme.

## Feladatok

- Válaszd szét a development/Lab és production signing configot.
- Production signing secret hiányában a build álljon le.
- Dokumentáld a kulcs backup, rotáció és hozzáférés policyt.
- Adj certificate fingerprintet a provenance manifesthez.

## Fő érintett fájlok

```text
android/app/build.gradle.kts
.github/workflows/release-android.yml
docs/security/signing-key-runbook.md
```

## Kötelező tesztek és ellenőrzések

- Production build secret nélkül fail.
- Lab build dev kulccsal működik.
- Debug certificate productionben elutasítva.

## Elfogadási feltételek

- [ ] Production artifact nem használ debug keystore-t.
- [ ] Signing key nem kerül repositoryba vagy logba.

## Javasolt commit

```text
fix(release): enforce secure production signing
```

---

# Kör 8 — Staging backend, migrations és recovery alap

## Cél

Production-szerű staging, reprodukálható deploy, adatbázis-migráció, backup és restore bizonyítása.

## Feladatok

- Készíts reprodukálható backend container buildet.
- Adj staging configot külön adatbázissal és media storage-dzsal.
- Implementálj migration-before-start és readiness gate-et.
- Dokumentáld a deploy, rollback és secret rotáció lépéseit.
- Készíts backup és restore runbookot.
- Automatizálj staging migration rehearsal workflow-t.
- Tesztelj partial migration és connection loss esetet.
- Rögzíts schema compatibility window-t az app verziókhoz.

## Fő érintett fájlok

```text
backend/Dockerfile
backend/deploy/
backend/app/main.py
docs/operations/backend-deploy.md
backend/scripts/backup.py
backend/scripts/restore.py
.github/workflows/backend-migration-drill.yml
docs/operations/database-recovery.md
```

## Kötelező tesztek és ellenőrzések

- Fresh staging deploy smoke.
- Readiness migration nélkül fail.
- Rollback előző image-re.
- Backup → új DB restore.
- Upgrade failure rollback.
- Előző kliens API smoke.

## Elfogadási feltételek

- [ ] Staging production-szerű, de production adathoz nem fér.
- [ ] Deploy egyértelműen reprodukálható.
- [ ] Restore idő és adatellenőrzés dokumentált.
- [ ] Migration rollback/forward recovery döntés egyértelmű.

## Javasolt commit

```text
feat(backend): add reproducible staging deployment
```

---

# Kör 9 — Domain event catalog és schema registry

## Cél

A feature-integrációhoz használt események egységes és verziózott katalógusa.

## Feladatok

- Implementáld a DomainEventEnvelope core típust.
- Dokumentáld a producer, consumer, schema és idempotency szabályokat.
- Adj JSON fixture-t minden cross-feature eseményhez.
- Készíts schema compatibility tesztet.

## Fő érintett fájlok

```text
lib/core/events/
docs/contracts/event-catalog.md
test/fixtures/events/
test/core/events/
```

## Kötelező tesztek és ellenőrzések

- Round-trip serialization.
- Unknown field tolerance.
- Duplicate idempotency fixture.

## Elfogadási feltételek

- [ ] Feature nem olvassa más feature belső storage-át.
- [ ] Minden eseménynek owner és schema versionje van.

## Javasolt commit

```text
feat(core): add versioned domain event catalog
```

---

# Kör 10 — Idempotens integration dispatcher és outbox

## Cél

A progress, reward, challenge és sync frissítések duplikációmentes feldolgozása.

## Feladatok

- Implementálj local event dispatcher és processed-event store interfészt.
- Adj offline outboxot online side effectekhez.
- Definiáld a retry és dead-letter policyt.
- Integráld elsőként a PracticeSessionCompleted eseményt.

## Fő érintett fájlok

```text
lib/core/events/event_dispatcher.dart
lib/core/sync/outbox/
test/core/events/idempotency_test.dart
```

## Kötelező tesztek és ellenőrzések

- Ugyanaz az event 100 ismétléssel egyszer hat.
- Process kill utáni resume.
- Out-of-order event.

## Elfogadási feltételek

- [ ] Nincs dupla XP, streak vagy post retry miatt.
- [ ] Sikertelen online side effect nem blokkolja a local state-et.

## Javasolt commit

```text
feat(core): add idempotent event dispatch and offline outbox
```

---

# Kör 11 — End-to-end test harness

## Cél

A fő vertical slice-ok automatizált integrációs futtatásának alapja.

## Feladatok

- Hozz létre integration_test struktúrát fake mic, clock, network és storage adapterrel.
- Adj deterministic app bootstrap profilt.
- Automatizáld az offline first-practice és returning-user flow-t.
- Készíts screenshotot csak hibánál.

## Fő érintett fájlok

```text
integration_test/
test_support/fakes/
.github/workflows/e2e.yml
docs/testing/e2e-harness.md
```

## Kötelező tesztek és ellenőrzések

- Fresh install flow.
- App restart persistence.
- Offline network guard.

## Elfogadási feltételek

- [ ] A core learning flow CI-ben reprodukálható.
- [ ] Fixture nem használ production hálózatot.

## Javasolt commit

```text
test(e2e): add deterministic vertical-slice harness
```

---

# Kör 12 — Release fixture corpus és golden data

## Cél

A scoring, analysis, migration és AI regresszióhoz verziózott, stabil fixture-készlet.

## Feladatok

- Rendezd a szintetikus és valós, jogtisztán használható audio fixture-öket.
- Adj legacy storage és database fixture-öket.
- Adj tutor, retrieval és tool-calling evaluation corpusokat.
- Készíts manifestet licenccel és checksumokkal.

## Fő érintett fájlok

```text
test/fixtures/release/
ml/fixtures/release/
local_ai/evaluation/
test/fixtures/manifest.json
```

## Kötelező tesztek és ellenőrzések

- Checksum audit.
- Missing fixture license fail.
- Fixture schema compatibility.

## Elfogadási feltételek

- [ ] Release regresszió azonos corpuson mérhető.
- [ ] Érzékeny felhasználói adat nincs fixture-ben.

## Javasolt commit

```text
test(release): establish versioned golden fixture corpus
```

---

# Kör 13 — Device matrix és device lab nyilvántartás

## Cél

A támogatott Android készülékek és capability tier-ek mérhető kezelése.

## Feladatok

- Hozz létre device inventory sémát OS, RAM, ABI, audio, camera és AI tier mezőkkel.
- Definiáld a kötelező tesztcsomagot tierenként.
- Adj manuális eredményimport és report generálást.
- Jelöld a release-blocking és informational eszközöket.

## Fő érintett fájlok

```text
docs/testing/device-matrix.yaml
tool/device_report.py
docs/testing/device-lab.md
```

## Kötelező tesztek és ellenőrzések

- Schema validation.
- Minden GA capabilityhez legalább egy blocking device.
- Report generation.

## Elfogadási feltételek

- [ ] Device support döntés evidence alapú.
- [ ] Offline AI hiánya nem jelenti a core inkompatibilitását.

## Javasolt commit

```text
test(device): add supported device matrix and reports
```

---

# Kör 14 — Performance budget harness

## Cél

Cold start, audio, analysis, vision és local AI regresszió automatikus és manuális mérése.

## Feladatok

- Definiáld a benchmark result sémát és baseline verziót.
- Adj Flutter timeline és memory mérési helper-eket.
- Integráld az audio pipeline benchmarkot.
- Adj report összehasonlítást 5%-os figyelmeztetési küszöbbel.

## Fő érintett fájlok

```text
benchmark/
tool/compare_benchmarks.py
docs/performance/budgets.md
.github/workflows/benchmark.yml
```

## Kötelező tesztek és ellenőrzések

- Baseline parse.
- Regression threshold.
- Hiányzó mérés release reportban fail.

## Elfogadási feltételek

- [ ] Core audio regresszió látható.
- [ ] Minden benchmark tartalmaz device/build metadata-t.

## Javasolt commit

```text
perf(release): add versioned performance budget harness
```

---

# Kör 15 — Audio, camera és local AI resource coexistence

## Cél

A nagy erőforrású modulok kölcsönös blokkolási és degradációs szabályainak igazolása.

## Feladatok

- Definiáld a ResourceCoordinator prioritási szerződését.
- Teszteld Live + camera, Analyze + local AI és background váltásokat.
- Implementálj kontrollált local AI pause/unload policyt audio prioritásnál.
- Adj thermal és low-memory fallbacket.

## Fő érintett fájlok

```text
lib/core/resources/
test/core/resources/
integration_test/resource_coexistence_test.dart
```

## Kötelező tesztek és ellenőrzések

- Mic priority.
- Camera release.
- AI cancellation.
- Low-memory recovery.

## Elfogadási feltételek

- [ ] Live és Practice nem akad el background AI miatt.
- [ ] Nincs resource leak.

## Javasolt commit

```text
fix(core): coordinate audio vision and local ai resources
```

---

# Kör 16 — AI és ML összesített release gate

## Cél

A DSP, scoring, tutor, retrieval, vision és offline AI értékelések egyetlen release riportba integrálása.

## Feladatok

- Definiáld az AIReleaseReport sémát.
- Importáld a real-audio, vision, tutor, retrieval és model benchmark eredményeket.
- Adj shipping baseline összehasonlítást.
- Blokkold a release-t hiányzó kritikus evaluation esetén.

## Fő érintett fájlok

```text
tool/release/build_ai_report.py
docs/release/ai-quality-gates.md
.github/workflows/ai-release-gate.yml
```

## Kötelező tesztek és ellenőrzések

- Missing report fail.
- Regression classification.
- Model version mismatch fail.

## Elfogadási feltételek

- [ ] AI feature nem release-elhető önálló mérés nélkül.
- [ ] Minden állítás model/build verzióhoz kötött.

## Javasolt commit

```text
ci(ai): aggregate evidence-based model release gates
```

---

# Kör 17 — Privacy data inventory és consent enforcement

## Cél

A teljes alkalmazás adatfolyamának és consent határainak auditálható lezárása.

## Feladatok

- Készíts géppel olvasható data inventoryt minden feature-höz.
- Kapcsold a consent változást azonnali feature enforcementhez.
- Adj privacy dashboardot a Settingsben.
- Teszteld diagnostics, cloud AI, community és media consentet.

## Fő érintett fájlok

```text
docs/privacy/data-inventory.yaml
lib/features/settings/privacy/
test/privacy/
backend/tests/test_privacy.py
```

## Kötelező tesztek és ellenőrzések

- Consent revoke azonnal blokkol.
- Local-only nem küld hálózatra.
- Export/törlés contract.

## Elfogadási feltételek

- [ ] Minden adatmezőnek célja és retentionje van.
- [ ] Nincs csendes cloud fallback.

## Javasolt commit

```text
feat(privacy): add data inventory and enforce consent boundaries
```

---

# Kör 18 — Security threat model és release scan

## Cél

A teljes támadási felület, dependency és secret kockázat release előtti ellenőrzése.

## Feladatok

- Készíts STRIDE-szerű threat modelt a releváns komponensekre.
- Adj secret, dependency és container scan workflow-t.
- Teszteld reward replay, media validation, path traversal és model tampering esetet.
- Készíts security exception registryt lejárati dátummal.

## Fő érintett fájlok

```text
docs/security/threat-model.md
.github/workflows/security.yml
docs/security/exceptions.yaml
backend/tests/security/
```

## Kötelező tesztek és ellenőrzések

- Known secret fixture detection.
- Tampered model rejection.
- Replay rejection.
- Upload path traversal.

## Elfogadási feltételek

- [ ] Nyitott kritikus security finding mellett nincs RC.
- [ ] Exception owner és expiry kötelező.

## Javasolt commit

```text
security(release): add threat model and automated security gates
```

---

# Kör 19 — Privacy-safe observability, SLO és release dashboard

## Cél

Érzékeny tartalom nélküli telemetry, SLO és rollout döntést támogató dashboard kialakítása.

## Feladatok

- Hozz létre typed analytics/telemetry event katalógust.
- Implementálj redaction és consent gate-et.
- Adj operation result, duration bucket és capability metadata eseményeket.
- Tiltsd raw prompt/audio/video payload logolását.
- Definiáld a dashboard input és threshold sémát.
- Adj crash, migration, auth, sync, community és AI fallback nézetet.
- Implementálj release cohort filtert.
- Készíts alert runbook linkeket.

## Fő érintett fájlok

```text
lib/core/telemetry/
docs/analytics/event-catalog.md
backend/app/telemetry/
test/core/telemetry/
docs/operations/slo.yaml
backend/monitoring/
docs/operations/release-dashboard.md
```

## Kötelező tesztek és ellenőrzések

- Sensitive field redaction.
- Opt-out no-op.
- Event schema validation.
- Synthetic alert.
- Cohort filter.
- Missing metric marked unknown, nem success.

## Elfogadási feltételek

- [ ] Core SLO mérhető.
- [ ] Érzékeny tanulási tartalom nem kerül telemetrybe.
- [ ] Rollout packethez dashboard snapshot készíthető.
- [ ] Unknown állapot nem minősül zöldnek.

## Javasolt commit

```text
feat(observability): add privacy-safe telemetry contracts
```

---

# Kör 20 — Accessibility és localization release audit

## Cél

A teljes core flow angol és magyar nyelvű, nagyított és képernyőolvasós kiadásra alkalmassá tétele.

## Feladatok

- Futtasd a localization parity ellenőrzést minden új feature-re.
- Teszteld a core E2E flow-t 200% text scale mellett.
- Auditáld semantics, focus order, tap target és color-independent state jelzést.
- Adj release checklistet és ismert kivétel registryt.

## Fő érintett fájlok

```text
tool/check_l10n.dart
docs/accessibility/release-audit.md
test/accessibility/
lib/l10n/
```

## Kötelező tesztek és ellenőrzések

- Missing translation fail.
- Overflow widget tests.
- Semantics smoke.

## Elfogadási feltételek

- [ ] Core learning flow mindkét nyelven használható.
- [ ] P1 accessibility blokk mellett nincs GA.

## Javasolt commit

```text
test(a11y): add release localization and accessibility gates
```

---

# Kör 21 — Content catalog és pedagógiai readiness

## Cél

A gyakorlatok, leckék, dalpéldák és tutor tudáscsomag release-minőségének igazolása.

## Feladatok

- Készíts content inventoryt difficulty, skill, locale és source mezőkkel.
- Validáld, hogy minden Practice Generator output létező exercise-re mutat.
- Auditáld a beginner progressiont és a zsákutcákat.
- Adj content package versiont a release manifesthez.

## Fő érintett fájlok

```text
content/catalog/
tool/validate_content_catalog.py
docs/content/release-readiness.md
```

## Kötelező tesztek és ellenőrzések

- Broken reference fail.
- Locale coverage.
- Difficulty progression invariants.

## Elfogadási feltételek

- [ ] Nincs generált, nem létező gyakorlat.
- [ ] A kezdő tanulási út végigjárható.

## Javasolt commit

```text
content(release): validate learning catalog readiness
```

---

# Kör 22 — Beta distribution, tester enrollment és feedback

## Cél

Kontrollált béta terjesztés, tájékozott tesztelői részvétel és consent-alapú diagnosztikai visszajelzés létrehozása.

## Feladatok

- Dokumentáld a channel, cohort és enrollment folyamatot.
- Automatizáld az internal artifact release notes generálását.
- Adj tester consent és privacy tájékoztatót.
- Készíts visszavonási és verziókényszerítési eljárást.
- Implementálj kategorizált feedback flow-t.
- Készíts redacted diagnostics bundle generátort.
- Nyers audio legyen külön opcionális attachment külön consenttel.
- Kapcsold a reportot app/build/device metadata-hoz.

## Fő érintett fájlok

```text
docs/beta/enrollment.md
docs/beta/tester-consent.md
tool/release/generate_beta_notes.py
.github/workflows/beta-release.yml
lib/features/feedback/
lib/core/diagnostics/
backend/app/routes/feedback.py
docs/beta/feedback-triage.md
```

## Kötelező tesztek és ellenőrzések

- Beta build channel marker.
- Production endpoint tiltás Lab buildben és fordítva.
- Release notes generation.
- Consent nélkül nincs upload.
- Token és e-mail redaction.
- Oversized attachment rejection.

## Elfogadási feltételek

- [ ] Tesztelő pontosan tudja, milyen adat gyűlhet.
- [ ] Hibás beta build visszavonható.
- [ ] A feedback reprodukálható metadata-t ad.
- [ ] Érzékeny attachment nem kerül automatikusan csomagba.

## Javasolt commit

```text
feat(beta): add controlled distribution and enrollment
```

---

# Kör 23 — Legacy user migration release candidate

## Cél

A korábbi StrumSight adatok biztonságos frissítésének teljes gyakorlatba vitele.

## Feladatok

- Készíts legacy fixture-t minden ismert storage verzióból.
- Futtasd az update, kill, resume, low-storage és corruption teszteket.
- Implementálj recovery UI-t és exportálható migration reportot.
- Dokumentáld a rollback korlátait.

## Fő érintett fájlok

```text
test/fixtures/migrations/
integration_test/upgrade_test.dart
lib/app/migration/
docs/release/client-migration.md
```

## Kötelező tesztek és ellenőrzések

- Minden legacy fixture upgrade.
- Interruption resume.
- No data loss invariant.

## Elfogadási feltételek

- [ ] Sikertelen migráció nem indít üres profilt csendben.
- [ ] Felhasználó recovery útvonalat kap.

## Javasolt commit

```text
test(migration): qualify legacy user upgrade path
```

---

# Kör 24 — Store listing, privacy és legal package

## Cél

A production distribution dokumentumainak és store metadata-jának lezárása.

## Feladatok

- Készíts store description, screenshot plan és permission rationale anyagot.
- Kösd össze a data inventoryt a data safety nyilatkozattal.
- Készíts privacy policy és community guidelines release checklistet.
- Ellenőrizd az account deletion és support elérhetőséget.

## Fő érintett fájlok

```text
docs/store/
docs/legal/privacy-policy-draft.md
docs/legal/community-guidelines-draft.md
```

## Kötelező tesztek és ellenőrzések

- Store metadata link audit.
- Minden permissionhöz indoklás.
- Deletion flow URL/route smoke.

## Elfogadási feltételek

- [ ] Store csomag konzisztens a tényleges adatkezeléssel.
- [ ] Nem tesz túlzó AI vagy tanulási ígéretet.

## Javasolt commit

```text
docs(store): prepare privacy and distribution package
```

---

# Kör 25 — Release Candidate assembly workflow

## Cél

Egyetlen manuálisan jóváhagyható workflow-val RC app, backend és manifest készítése.

## Feladatok

- Készíts RC workflow-t clean checkoutból.
- Futtasd az összes release gate-et.
- Buildeld az AAB-t és backend image-et.
- Csomagold provenance, SBOM, release notes, model/content manifest és test report artifactokat.

## Fő érintett fájlok

```text
.github/workflows/release-candidate.yml
tool/release/assemble_rc.py
docs/release/rc-checklist.md
```

## Kötelező tesztek és ellenőrzések

- Missing approval fail.
- Dirty/uncommitted source nem lehetséges CI-ben.
- Artifact checksum audit.

## Elfogadási feltételek

- [ ] RC reprodukálható és auditálható.
- [ ] Piros gate mellett nincs AAB upload.

## Javasolt commit

```text
ci(release): assemble auditable release candidates
```

---

# Kör 26 — Rollback és disaster recovery rehearsal

## Cél

A kritikus rollback lépések időzített, dokumentált gyakorlata.

## Feladatok

- Gyakorold a feature kill switch, backend image rollback és model rollback folyamatot.
- Gyakorold a database restore-t stagingen.
- Mérd a recovery time-ot és az adatkonzisztenciát.
- Frissítsd a runbookokat a tényleges hibák alapján.

## Fő érintett fájlok

```text
docs/operations/disaster-recovery-drill.md
tool/release/verify_rollback.py
```

## Kötelező tesztek és ellenőrzések

- Rollback target deploy.
- Migration compatibility smoke.
- Feature flag cache expiry.

## Elfogadási feltételek

- [ ] A recovery lépések bizonyítottak, nem csak dokumentáltak.
- [ ] Tulajdonos ismeri a manuális döntési pontokat.

## Javasolt commit

```text
ops(release): rehearse rollback and disaster recovery
```

---

# Kör 27 — Closed Beta launch és monitoring

## Cél

A meghívott tesztelői kör biztonságos elindítása és első hét stabilizációja.

## Feladatok

- Aktiváld a Closed Beta cohortot a jóváhagyott feature profilokkal.
- Figyeld a migration, crash, practice completion, support és privacy jelzéseket.
- Tarts napi triage-ot az első héten.
- Ne növeld a cohortot nyitott P0/P1 mellett.

## Fő érintett fájlok

```text
docs/beta/closed-beta-launch.md
docs/beta/daily-triage-template.md
```

## Kötelező tesztek és ellenőrzések

- Production-like smoke a beta tracken.
- Kill switch dry-run.
- Feedback ingestion smoke.

## Elfogadási feltételek

- [ ] Első hét completion report elkészült.
- [ ] Minden P0/P1 lezárt vagy rollout stop aktív.

## Javasolt commit

```text
release(beta): launch monitored closed beta
```

---

# Kör 28 — Beta stabilization és scope cut

## Cél

A béta eredmények alapján a GA scope véglegesítése és a nem stabil feature-ök leválasztása.

## Feladatok

- Készíts top issue és funnel elemzést.
- Osztályozd a feature-öket GA, preview, disabled vagy postponed státuszra.
- Távolítsd el a release blocker technikai adósságot.
- Fagyaszd a core contractokat.

## Fő érintett fájlok

```text
docs/release/ga-scope.md
docs/release/beta-findings.md
docs/release/contract-freeze.md
```

## Kötelező tesztek és ellenőrzések

- Feature flag profile snapshot.
- Core contract compatibility suite.
- No open P0/P1 audit.

## Elfogadási feltételek

- [ ] GA scope kisebb lehet, de stabil.
- [ ] Preview feature nem befolyásolja a core flow-t.

## Javasolt commit

```text
chore(release): stabilize beta and freeze ga scope
```

---

# Kör 29 — Open Beta és canary cohort

## Cél

Szélesebb eszköz- és felhasználói körön a production rendszer validálása.

## Feladatok

- Indíts Open Beta canary cohortot.
- Figyeld gyártó, OS, device tier és locale szerinti hibákat.
- Teszteld a community moderation és support kapacitást.
- Ellenőrizd a backend költség- és kapacitás guardokat.

## Fő érintett fájlok

```text
docs/beta/open-beta-launch.md
docs/operations/capacity-review.md
```

## Kötelező tesztek és ellenőrzések

- Cohort flag isolation.
- Rate limit smoke.
- Moderation queue smoke.
- Cost alert test.

## Elfogadási feltételek

- [ ] Nincs ismeretlen kritikus device cluster.
- [ ] Backend és support terhelés kezelhető.

## Javasolt commit

```text
release(beta): expand to controlled open beta
```

---

# Kör 30 — Feature freeze és final regression

## Cél

A Release Candidate előtti teljes scope- és kódfagyasztás.

## Feladatok

- Csak P0/P1/P2 release blocker változtatás engedélyezett.
- Futtasd a teljes Flutter, backend, device, AI, migration és security kaput.
- Készíts final known-issues listát.
- Frissítsd a release notes és support KB anyagokat.

## Fő érintett fájlok

```text
docs/release/feature-freeze.md
docs/release/known-issues.md
CHANGELOG.md
```

## Kötelező tesztek és ellenőrzések

- Full release matrix.
- Clean checkout build.
- Store package validation.

## Elfogadási feltételek

- [ ] Nincs nem jóváhagyott scope változás.
- [ ] RC blocker lista üres vagy explicit waiverrel ellátott.

## Javasolt commit

```text
chore(release): freeze features and complete final regression
```

---

# Kör 31 — Production deployment és internal production cohort

## Cél

A production backend és app belső cohorton történő validálása publikus rollout előtt.

## Feladatok

- Deployold a production backendet migration gate-tel.
- Telepítsd a production-signed appot belső cohortnak.
- Ellenőrizd auth, sync, community, model package és offline core flow-t.
- Készíts rollout decision packetet.

## Fő érintett fájlok

```text
docs/release/internal-production-checklist.md
docs/release/rollout-packet-template.md
```

## Kötelező tesztek és ellenőrzések

- Production smoke.
- No Lab endpoint.
- Signing fingerprint.
- Database readiness.

## Elfogadási feltételek

- [ ] Production környezet valid, de publikus cohort még nincs.
- [ ] Rollback target elérhető.

## Javasolt commit

```text
release(prod): validate internal production cohort
```

---

# Kör 32 — Staged rollout 1–20 százalék

## Cél

A GA release első publikus lépcsőinek kontrollált végrehajtása.

## Feladatok

- Indíts 1%-os rolloutot.
- Minden observation window után manuálisan értékeld a gate-eket.
- Lépj 5%, majd 20% szintre csak zöld packet mellett.
- P0/P1 vagy threshold breach esetén állítsd meg a rolloutot.

## Fő érintett fájlok

```text
docs/release/staged-rollout-log.md
docs/release/rollout-decision.md
```

## Kötelező tesztek és ellenőrzések

- Dashboard cohort filtering.
- Kill switch production dry-run biztonságos feature-rel.

## Elfogadási feltételek

- [ ] Minden lépcső döntése dokumentált.
- [ ] Nincs automatikus vak rollout.

## Javasolt commit

```text
release(prod): execute monitored initial rollout
```

---

# Kör 33 — Staged rollout 50–100 százalék és GA

## Cél

A teljes publikus elérhetőség biztonságos elérése.

## Feladatok

- Értékeld a 20%-os cohort minimum observation window-ját.
- Lépj 50%-ra, majd 100%-ra manuális approval mellett.
- Publikáld a végleges release notes és support anyagot.
- Rögzítsd a GA timestampet, buildet, flag profilt és model verziót.

## Fő érintett fájlok

```text
docs/release/ga-record.md
docs/release/release-notes.md
```

## Kötelező tesztek és ellenőrzések

- 100% cohort dashboard.
- Store availability smoke.
- Support links.

## Elfogadási feltételek

- [ ] GA állapot auditálható.
- [ ] Rollback és support készenlét fennmarad.

## Javasolt commit

```text
release(prod): complete staged general availability
```

---

# Kör 34 — Post-launch stabilization, hotfix és incident automation

## Cél

A GA utáni stabilizáció, auditálható hotfix út és incident/postmortem automatizálás kialakítása.

## Feladatok

- Tarts napi health és issue review-t.
- Prioritás legyen a crash, migration, battery, audio és support hiba.
- Feature fejlesztés helyett csak stabilizáció és observability javítás történjen.
- Készíts 7. és 14. napi reportot.
- Készíts hotfix branch és approval workflow-t.
- Futtasd a kötelező minimum gate-eket és affected full regressiont.
- Generálj hotfix release manifestet és notes-t.
- Kapcsold az incidenthez és postmortemhez.

## Fő érintett fájlok

```text
docs/release/post-launch-day7.md
docs/release/post-launch-day14.md
.github/workflows/hotfix.yml
docs/operations/hotfix-runbook.md
docs/operations/postmortem-template.md
```

## Kötelező tesztek és ellenőrzések

- Regression suite minden hotfixhez.
- Hotfix signing/provenance gate.
- Hotfix build production signinggal.
- Missing incident ID fail.
- Version increment enforcement.

## Elfogadási feltételek

- [ ] Nincs aktív P0/P1.
- [ ] SLO és support trend stabil.
- [ ] Hotfix nem kerüli meg a security/signing kaput.
- [ ] Minden hotfixhez regressziós teszt tartozik.

## Javasolt commit

```text
chore(release): complete post-launch stabilization
```

---

# Kör 35 — Technikaiadósság- és flag cleanup

## Cél

A release során ideiglenesen fenntartott kompatibilitási és flag rétegek rendezése.

## Feladatok

- Auditáld a deprecated exportokat, allowlistet, TODO/FIXME-t és lejárt flaget.
- Távolítsd el a bizonyítottan szükségtelen dual-read/write réteget.
- Ne törölj compatibility kódot, amíg a támogatott régi verziók használják.
- Készíts következő minor release debt backlogot.

## Fő érintett fájlok

```text
docs/release/technical-debt.md
tool/check_deprecations.dart
tool/check_feature_flags.dart
```

## Kötelező tesztek és ellenőrzések

- Architecture allowlist nem nő.
- Lejárt flag fail.
- Supported old-client contract smoke.

## Elfogadási feltételek

- [ ] Ideiglenes kódnak owner és eltávolítási terv van.
- [ ] Release utáni core tisztább, nem törékenyebb.

## Javasolt commit

```text
refactor(release): retire temporary compatibility debt
```

---

# Kör 36 — Program completion report és következő roadmap

## Cél

A 12 Chapter végrehajtási állapotának, eredményeinek és következő prioritásainak lezárása.

## Feladatok

- Készíts Chapterenként completion matrixot.
- Rögzítsd a tényleges sprintidőt, eltéréseket és fő tanulságokat.
- Archiváld a release, benchmark, security, privacy és quality reportokat.
- Készíts következő 6 hónapos outcome-alapú roadmapet, nem automatikus feature-listát.

## Fő érintett fájlok

```text
docs/sdd/program-completion-report.md
docs/roadmap/next-six-months.md
docs/sdd/00-index.md
HANDOFF.md
```

## Kötelező tesztek és ellenőrzések

- Minden Chapter státusza és linkje valid.
- Nincs lezáratlannak jelölt release blocker rejtve.

## Elfogadási feltételek

- [ ] A program átadható más fejlesztőnek vagy Codex sessionnek.
- [ ] A következő roadmap termékmetrikákból indul ki.

## Javasolt commit

```text
docs(program): close sdd roadmap and final integration
```

---

# 32. Chapter 12 Definition of Done

## Program és tervezés

- [ ] A 12 Chapter egyetlen validált indexben szerepel.
- [ ] A dependency graph körmentes és aktuális.
- [ ] A kritikus út dokumentált.
- [ ] A GA scope és preview scope különválasztott.
- [ ] A tényleges release history auditált.
- [ ] Minden release blocker ownerrel és severityvel rendelkezik.
- [ ] A sprint- és Codex-kör fogalma nem keveredik.

## Repository és release management

- [ ] A `main` branch védett.
- [ ] Direct és force push tiltott.
- [ ] Required CI check-ek aktívak.
- [ ] CODEOWNERS lefedi a kritikus területeket.
- [ ] A versioning és build number szabály auditált.
- [ ] Minden artifact provenance manifesttel rendelkezik.
- [ ] Production release nem használ debug signingot.
- [ ] SBOM és third-party license bundle elkészül.
- [ ] Hotfix pipeline működik.

## Environment és feature kontroll

- [ ] Development, Lab, Staging és Production elkülönített.
- [ ] Production nem használ Lab tokent vagy endpointot.
- [ ] High-risk feature-ek typed flag mögött vannak.
- [ ] Emergency kill switch működik.
- [ ] Kill switch nem töröl adatot.
- [ ] Lejárt feature flaget a CI jelzi.
- [ ] Local-only mód nem route-ol cloudra.

## Integráció és adat

- [ ] Cross-feature event catalog kész.
- [ ] Event schema verziózott.
- [ ] Idempotency key kötelező.
- [ ] Retry nem duplikál XP-t, streaket, challenge-et vagy postot.
- [ ] Offline outbox process kill után folytatható.
- [ ] Legacy storage fixture-ek migrálódnak.
- [ ] Migration interruption recoverable.
- [ ] Sikertelen migráció nem indít csendben üres profilt.
- [ ] Backend backup és restore bizonyított.

## Flutter és eszközminőség

- [ ] Core offline E2E zöld.
- [ ] Fresh install és update flow zöld.
- [ ] Mic minden kilépési útvonalon felszabadul.
- [ ] Camera lifecycle zöld.
- [ ] Audio, Vision és Offline AI resource policy zöld.
- [ ] Device matrix dokumentált.
- [ ] Performance budget report elkészült.
- [ ] Nincs elfogadhatatlan core audio regresszió.
- [ ] 200% text scale core flow használható.
- [ ] Screen reader alapútvonal használható.
- [ ] Angol és magyar localization parity zöld.

## Backend és Community

- [ ] Staging és production reprodukálhatóan deployolható.
- [ ] Alembic migration gate aktív.
- [ ] Liveness és readiness működik.
- [ ] Rate limit és upload validation aktív.
- [ ] Community report és block működik.
- [ ] Moderation queue működik.
- [ ] Leaderboard result verified és replay-védett.
- [ ] Production Lab route-ot nem regisztrál.
- [ ] Backend rollout és rollback rehearsal sikeres.

## AI, ML és content

- [ ] Model manifest és checksum valid.
- [ ] Model card és license bundle kész.
- [ ] Real-audio regression report kész.
- [ ] Tutor/retrieval quality report kész.
- [ ] Vision evaluation report kész, ha Vision GA scope.
- [ ] Offline AI device report kész, ha Offline AI GA scope.
- [ ] AI nem talál ki mért adatot a release corpuson.
- [ ] Tool calling schema-validált és megerősítéses.
- [ ] Content catalog referenciái érvényesek.
- [ ] Practice Generator csak validált exercise-t használ.

## Privacy és security

- [ ] Data inventory teljes.
- [ ] Minden consent azonnal enforce-olódik.
- [ ] Raw audio/video nincs alapértelmezett telemetryben.
- [ ] Token és jelszó nem kerül logba.
- [ ] Secret scan zöld.
- [ ] Dependency és container scan zöld.
- [ ] Threat model friss.
- [ ] Model package tampering elutasított.
- [ ] Reward replay teszt zöld.
- [ ] Privacy policy és store data nyilatkozat konzisztens.
- [ ] Account/data deletion flow működik.

## Beta, rollout és operations

- [ ] Internal Alpha completion report kész.
- [ ] Closed Beta completion report kész.
- [ ] Open Beta completion report kész vagy dokumentáltan kihagyott.
- [ ] Feedback és diagnostics consent működik.
- [ ] Support tudásbázis elérhető.
- [ ] Incident severity és runbook kész.
- [ ] Rollback és disaster recovery drill sikeres.
- [ ] RC clean checkoutból reprodukálható.
- [ ] Rollout 1%, 5%, 20%, 50%, 100% döntése dokumentált.
- [ ] Nincs nyitott P0/P1 GA-kor.
- [ ] 7. és 14. napi stabilization report elkészült.

---

# 33. Kötelező végső ellenőrző parancsok

Flutter és Dart:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test integration_test tool
flutter analyze lib test integration_test tool
flutter test
flutter test test/property
dart run tool/check_architecture.dart
dart run tool/check_feature_flags.dart
dart run tool/check_sdd_index.dart
```

Android:

```bash
cd android
./gradlew test
./gradlew connectedAndroidTest
```

Backend:

```bash
cd backend
python -m ruff check app tests
python -m ruff format --check app tests
python -m pytest -q
alembic upgrade head
```

ML és AI tooling:

```bash
cd ml
python -m pytest -q

cd ../local_ai
python -m pytest -q
python evaluation/run_quality_eval.py --profile release
python evaluation/run_tool_eval.py --profile release
python evaluation/run_retrieval_eval.py --profile release
```

Release assembly:

```bash
python tool/release/assemble_rc.py --profile production
python tool/release/verify_artifacts.py --directory <artifact-directory>
python tool/release/build_ai_report.py --profile production
python tool/release/generate_sbom.py --profile production
```

A production signing, store submission, production migration és rollout százalék módosítása továbbra is manuális jóváhagyást igényel.

---

# 34. A teljes SDD program eredménye

A Chapter 12 lezárása után a StrumSight nem csupán feature-ek gyűjteménye, hanem kiadható és üzemeltethető gitártanulási platform.

A végállapot:

- tiszta és védett repository workflow;
- fokozatosan megvalósított Core, Practice, Song, Analysis, Tutor, Vision, Generator, Gamification, Community és Offline AI capability-k;
- offline működő core tanulási út;
- verziózott és migrálható felhasználói adatok;
- idempotens cross-feature integráció;
- production-kész signing és artifact provenance;
- reprodukálható Flutter és backend release;
- valós eszközös quality gate;
- mérhető DSP/ML/AI minőség;
- privacy-first telemetry és adatkezelés;
- accessibility és localization kapu;
- kontrollált beta program;
- fokozatos rollout, kill switch és rollback;
- support, incident és post-launch folyamat;
- outcome-alapú következő roadmap.

A projekt ezután nem egy újabb automatikus feature-fejezettel folytatódik. A következő prioritást a valódi felhasználói eredmények, a tanulási minőség, a stabilitás, a támogatási terhelés és a fenntartható üzemeltetés határozza meg.
