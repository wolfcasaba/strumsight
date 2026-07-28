---
id: 111
topic: SDD Ch9 / Epic 8 — Gamification: 30 kör (canonical learning event, idempotens reward ledger, XP/level, achievement, quest, Streak V2, etikus design)
tags: [sdd, epic8, gamification, xp, ledger, streak, quests, ethics]
status: active
depends_on: [106]
canonical_target: docs/sdd/09-epic-08-gamification.md
verify: reward duplication rate 0 + legacy streak migráció zöld
source: chatgpt-plan 2026-07-28 (Codex Execution Pack, 58-file manifest)
---

# StrumSight Software Design Document

## Chapter 9 — Epic 8: Gamification

**Dokumentumverzió:** 1.0  
**Státusz:** fejlesztésre kész specifikáció  
**Repository:** `wolfcasaba/strumsight`  
**Elsődleges kliens:** Flutter, Android-first  
**Tervezési alapelv:** learning-first, deterministic, compassionate, offline-first  
**Adatkezelés:** a jutalmak, streak és haladás alapértelmezetten helyben maradnak  
**Kapcsolódó fejezetek:** Chapter 2 Core Platform, Chapter 3 Practice Engine, Chapter 4 Song Trainer, Chapter 5 AI Guitar Teacher, Chapter 6 Computer Vision, Chapter 7 Audio Analysis 2.0, Chapter 8 AI Practice Generator  
**Végrehajtó:** Codex  
**Végrehajtási mód:** külön branchben vagy külön, önálló commitban végzett kis fejlesztési körök

---

# 1. Az Epic célja

Az Epic 8 célja egy olyan gamification platform létrehozása, amely a StrumSightban végzett valódi tanulási munkát láthatóvá, követhetővé és motiválóvá teszi anélkül, hogy a jutalmazási mechanika átvenné az irányítást a tanulás felett.

A rendszernek nem pusztán XP-t, jelvényeket és animációkat kell hozzáadnia. A cél egy közös, determinisztikus és auditálható motivációs réteg, amely:

- kizárólag igazolt tanulási eseményekből számít jutalmat;
- nem jutalmaz mikrofon előtt lejátszott zajt vagy üres képernyőidőt;
- nem büntet negatív XP-vel;
- nem manipulálja a felhasználót veszteségfélelemmel;
- nem alakítja a gyakorlást végtelen grinddé;
- nem teszi fizetőssé a megszerzett haladás megőrzését;
- offline állapotban is teljesen működik;
- ugyanazt az eseményt legfeljebb egyszer jutalmazza;
- meg tudja magyarázni, hogy egy jutalom miért járt;
- tiszteletben tartja az accessibility, reduced-motion és értesítési beállításokat;
- felkészíti a rendszert a későbbi Community funkciókra anélkül, hogy ellenőrizetlen lokális XP-t globális ranglistára küldene.

Az Epic végeredménye egy közös `GamificationEngine`, amely a Practice Engine, Song Trainer, Analyze, Computer Vision, AI Tutor és AI Practice Generator által kibocsátott típusos tanulási eseményeket feldolgozza, majd idempotens reward ledgerben rögzíti az XP-t, szinteket, achievementeket, quest progresszt, streaket és mastery mérföldköveket.

---

# 2. Termékvízió

## 2.1 Felhasználói ígéret

A felhasználó ne azt érezze, hogy egy játék miatt kell gitároznia. Azt érezze, hogy a rendszer felismeri és megmutatja a valódi fejlődését.

A kívánt élmény:

> Ma 18 percet gyakoroltál, teljesítettél három tervblokkot, és 72 BPM-ről 78 BPM-re emelted a tiszta akkordváltásodat. Megszerezted a „Stabil váltás I” mérföldkövet. A heti célod 64%-on áll.

A nem kívánt élmény:

> Még 43 XP kell. Ismételd ugyanazt a könnyű feladatot hatszor, különben elveszíted a sorozatodat.

## 2.2 Learning-first gamification

A gamification feladata:

- láthatóvá tenni az erőfeszítést;
- megerősíteni a rendszerességet;
- jelezni a készségfejlődést;
- kisebb, elérhető célokra bontani a hosszú tanulási utat;
- segíteni a felhasználót a következő értelmes lépés kiválasztásában;
- ünnepelni a tartós javulást;
- közérthetően összekötni a jutalmat a teljesítménnyel.

A gamification nem:

- helyettesíti a tanítást;
- írja felül a Practice Generator szakmai prioritását;
- módosít mért pontosságot;
- kényszerít ismétlésre kizárólag XP miatt;
- büntet kihagyott napért;
- használ szándékosan félrevezető vagy szégyenítő nyelvet;
- jelenít meg hamis sürgősséget;
- támaszkodik loot boxra, véletlen fizetős jutalomra vagy szerencsejáték-szerű mechanikára.

## 2.3 Motivációs rétegek

A rendszer öt, egymást kiegészítő motivációs réteget használ:

1. **Erőfeszítés:** gyakorlási idő és érvényes sessionök.
2. **Minőség:** pontosság, timing, következetesség és megfelelő nehézség.
3. **Fejlődés:** személyes baseline-hoz képesti javulás.
4. **Rendszeresség:** rugalmas streak, heti cél és visszatérési ritmus.
5. **Felfedezés:** különböző módok, dalok, technikák és tanulási útvonalak kipróbálása.

Egyik réteg sem dominálhatja tartósan a teljes rendszert. A kizárólag időalapú grindot, a kizárólag accuracy-alapú perfekcionizmust és a kizárólag streak-alapú veszteségfélelmet egyaránt kerülni kell.

## 2.4 Compassionate design

A rendszer kezelje természetesnek, hogy a felhasználó:

- beteg lehet;
- utazhat;
- kevés idővel rendelkezhet;
- néha csak két percet tud gyakorolni;
- sérülés vagy kényelmetlenség miatt szünetet tarthat;
- elveszítheti az eszközét;
- offline maradhat;
- más időzónába utazhat;
- kezdőként alacsony pontossággal indulhat.

Ezért:

- nincs negatív XP;
- nincs achievement visszavonás;
- nincs fizetős streak-megmentés;
- nincs szégyenítő „lustaság” üzenet;
- a recovery quest fontosabb, mint az elvesztett streak dramatizálása;
- a heti rendszeresség a napi tökéletességnél nagyobb súlyt kaphat;
- a felhasználó szüneteltetheti a motivációs értesítéseket;
- a rendszer külön kezeli a tervezett pihenőnapot és a kihagyott napot.

## 2.5 A siker definíciója

Az Epic sikeres, ha:

- a felhasználó minden jutalomnál látja a forrását;
- ugyanaz a session újranyitással vagy sync retryjal nem ad kétszer XP-t;
- offline gyakorlat után azonnal megjelenik a jutalom;
- a régi streak, lesson stars és practice history adatvesztés nélkül migrálódik;
- a napi kihívás továbbra is használható internet nélkül;
- az XP ismételt könnyű feladattal nem farmolható korlátlanul;
- az alacsony pontosságú kezdő is kap erőfeszítésért és befejezésért jutalmat;
- a magas pontosságú játékos minőségi és mastery mérföldköveket kap;
- reduced-motion módban nincs zavaró animáció;
- a rendszer nem indít automatikus sessiont és nem módosít napi célt jóváhagyás nélkül;
- a globális leaderboard későbbi bevezetéséig nincs nem ellenőrzött kompetitív rangsor.

---

# 3. Kapcsolat a jelenlegi kódbázissal

## 3.1 Meglévő Progress rendszer

A repository jelenleg tartalmazza:

- `PracticeEntry` modellt;
- `PracticeSource` értékeket: `live`, `analyze`, `learn`;
- gyakorlási másodperceket, stroke- és chord-számot;
- direction accuracy értéket;
- `PracticeStats` napi és heti aggregációkat;
- napi gyakorlási célt;
- heti oszlopdiagramot;
- teljes session-, idő- és stroke-statisztikát.

Ez értékes bemenet, de önmagában nem alkalmas reward ledgernek, mert egy `PracticeEntry` nem rendelkezik globálisan egyedi event ID-val, reward állapottal, schema versionnel, trust szinttel vagy idempotency kulccsal.

## 3.2 Meglévő Streak rendszer

A jelenlegi rendszer támogatja:

- current streaket;
- longest streaket;
- utolsó gyakorlási napot;
- total practiced days értéket;
- hét naponta szerzett, legfeljebb három freeze-t;
- pontosan egy kihagyott nap freeze-zel történő lefedését;
- epoch-day alapú, DST-t kerülő logikát;
- időinjektálható unit teszteket;
- Streak képernyőt és kompakt badge-et.

A meglévő tiszta `StreakLogic` jó alap. Az Epic nem törli ezt a logikát, hanem verziózott policy mögé helyezi, migrálja a tárolást, és hozzáad tervezett pihenőnapot, grace állapotot, recovery flow-t és auditálható ledger kapcsolatot.

## 3.3 Meglévő napi kihívás

A `DailyChallenge.forDay(epochDay)`:

- determinisztikus;
- offline;
- napi seedből készít strum patternt;
- 4, 6 vagy 8 stroke hosszúságú;
- zenei szabályt alkalmaz az on-beat/down és off-beat/up arányra;
- Learn lessonné alakítható.

Ez a rendszer megtartandó legacy content providerként, majd a Challenge V2 katalógus egyik generátorává válik.

## 3.4 Meglévő lesson progress

A Learn feature:

- lessonenként legjobb accuracyt tárol;
- 70%, 80% és 90% küszöbnél 1, 2 és 3 csillagot ad;
- prerequisite-alapú unlockot használ;
- recommended next lesson funkcióval rendelkezik.

A csillagok megmaradnak szakmai teljesítménymérőként. Az XP nem válthatja ki és nem módosíthatja őket.

## 3.5 Meglévő weekly recap

A `WeeklyRecap` már aggregálja:

- gyakorlási perceket;
- sessionöket;
- stroke-okat;
- aktív napokat;
- legjobb napot;
- átlagos direction accuracyt;
- streaket.

A heti quest és recap rendszer ezt az adatot használhatja, de a jutalom számításához a jövőben canonical learning eventek szükségesek.

## 3.6 Azonosított technikai adósságok

Az Epic során rendezendő:

1. A streak, practice log, daily goal és lesson progress közvetlenül SharedPreferences-t használ.
2. A PracticeSource enum nem tartalmazza a későbbi Practice, Song, Tutor és Vision forrásokat.
3. A jutalmazásnak nincs közös event ID-ja.
4. Nincs idempotens reward ledger.
5. Nincs XP- vagy level-domain.
6. Nincs achievement katalógus és progress storage.
7. Nincs quest lifecycle.
8. A napi challenge teljesítése nincs külön, tartósan tárolva.
9. A streak több feature-ből közvetlenül hívott mutációval frissül.
10. Nincs clock-skew vagy timezone-változás audit.
11. Nincs közös celebration coordinator.
12. Nincs reduced-motion kompatibilis reward presentation.
13. Nincs ismétlésfarm elleni szabály.
14. Nincs globális daily XP cap vagy diminishing-return policy.
15. A későbbi account sync konfliktuskezelése nincs definiálva.
16. A lokális haladás nem választható szét verified és unverified forrásra.

---

# 4. Kapcsolat a korábbi SDD-fejezetekkel

## 4.1 Chapter 2 — Core Platform

Az Epic használja:

- `AppResult` és `AppFailure`;
- `Clock`;
- `KeyValueStore` és verziózott repositorykat;
- strukturált loggingot;
- environment és feature flag rendszert;
- offline-first hálózati szabályokat;
- architecture guardot.

## 4.2 Chapter 3 — Practice Engine

A Practice Engine a legfontosabb canonical event forrás:

- session started;
- session completed;
- block completed;
- valid attempt;
- accuracy és timing score;
- difficulty;
- speed milestone;
- skill tagek;
- quality/confidence;
- cancellation reason.

A Gamification Engine nem számolhat újra DSP-t vagy score-t. Kizárólag a Practice Engine által lezárt, immutable resultból dolgozhat.

## 4.3 Chapter 4 — Song Trainer

A Song Trainer kibocsáthat:

- song section completion;
- A-B loop completion;
- full-song completion;
- speed milestone;
- clean take;
- new song discovery;
- setlist completion;
- personal-best event.

## 4.4 Chapter 5 — AI Guitar Teacher

Az AI Tutor:

- megmagyarázhatja a megszerzett mérföldkövet;
- javasolhat nem kötelező questet;
- összefoglalhat heti fejlődést;
- nem írhat közvetlenül XP-t;
- nem adhat achievementet;
- nem módosíthat streaket;
- csak típusos, validált actiont kérhet.

## 4.5 Chapter 6 — Computer Vision

A Vision rendszerből csak olyan esemény jutalmazható, amely:

- rendelkezik megfelelő quality gate-tel;
- nem pusztán egyetlen bizonytalan frame;
- sessionhöz és event ID-hoz kötött;
- megadja a confidence és evidence window értéket;
- nem tesz orvosi állítást.

## 4.6 Chapter 7 — Audio Analysis 2.0

Az Analysis rendszer adhat:

- first valid analysis;
- signal-quality milestone;
- timing consistency improvement;
- tempo stability improvement;
- personal-best comparison;
- valid insight resolution.

Egy WAV újraelemzése ugyanazzal a source hash-sel és analyzer verzióval nem adhat újra ugyanazért XP-t.

## 4.7 Chapter 8 — AI Practice Generator

A Practice Generator:

- napi és heti plan objectiveket ad;
- jelzi a tervezett pihenőnapot;
- quest-compatible blokkazonosítókat ad;
- a Gamification Engine progressét olvashatja;
- nem optimalizálhat kizárólag XP maximalizálásra;
- a szakmai prioritásokat nem írhatja felül jutalmi okból.

---

# 5. Hatókör

## 5.1 Az Epic része

- canonical learning activity event;
- event trust és reward eligibility;
- idempotens reward ledger;
- XP és level rendszer;
- achievement katalógus;
- achievement progress és unlock;
- napi és heti questek;
- Challenge V2;
- Streak V2 és legacy migráció;
- mastery milestone és badge rendszer;
- reward inbox;
- celebration coordinator;
- home, progress és profile integráció;
- offline persistence;
- opcionális account sync contract;
- clock-skew és duplicate védelem;
- accessibility és reduced motion;
- ethical design szabályok;
- analytics és evaluation;
- Flutter és domain tesztek;
- CI quality gate.

## 5.2 Az Epic nem tartalmazza

- globális ranglistát;
- nyilvános ligákat;
- barátlistát;
- követést;
- versenyző profilok összehasonlítását;
- social feedet;
- multiplayer kihívást;
- valódi vagy virtuális pénzt;
- vásárolható XP-t;
- loot boxot;
- NFT-t vagy kereskedhető jutalmat;
- pay-to-win funkciót;
- automatikus közösségi megosztást;
- teljes achievement content pack végleges szerkesztését minden jövőbeli technikához.

Ezek közül a közösségi elemek a későbbi Community Epicben tervezhetők. A Chapter 9 csak olyan publikus szerződéseket készít elő, amelyekkel verified, privacy-safe teljesítmény később megosztható.

---

# 6. Kötelező tervezési elvek

## 6.1 A jutalom ledgerből származik

A UI soha nem növelheti közvetlenül az XP-t.

Helyes folyamat:

```text
Feature result
    ↓
LearningActivityEvent
    ↓
Event validation
    ↓
Reward eligibility
    ↓
Reward policy
    ↓
RewardLedgerEntry
    ↓
Profile projection
    ↓
UI
```

Tiltott:

```text
Button onPressed → xp += 10
```

## 6.2 Idempotencia

Minden jutalmazható esemény rendelkezzen stabil `eventId` értékkel.

Ugyanaz az esemény:

- retry;
- app restart;
- sync replay;
- provider invalidation;
- route újranyitás;
- background worker újrafutás

esetén sem hozhat létre második reward ledger sort.

## 6.3 Determinisztikus reward policy

Azonos input event, azonos policy verzió és azonos profilállapot azonos reward döntést adjon.

Az AI nem számol XP-t.

## 6.4 Nincs negatív XP

Rossz teljesítmény, félbehagyott session vagy kihagyott nap miatt:

- XP nem vonható le;
- level nem csökken;
- achievement nem veszhet el;
- mastery állapot nem romlik automatikusan.

A rendszer jelezhet szakmai regressziót külön progress metrikában, de ezt nem gamification büntetésként jeleníti meg.

## 6.5 Erőfeszítés és minőség egyensúlya

A session completion adhat alap XP-t, ha valódi gyakorlás történt. Minőségi bónusz csak valid, megfelelő confidence-ű score esetén járhat.

A kezdőt nem szabad azért kizárni a jutalomból, mert még nem ér el magas accuracyt.

## 6.6 Diminishing returns

Ugyanaz a rövid, könnyű exercise nem farmolható végtelenül.

A rendszer alkalmazhat:

- napon belüli ismétlési görbét;
- exercise-instance capet;
- minimum valid durationt;
- nehézséghez kötött eligibilityt;
- personal-best vagy improvement bónuszt;
- változatossági bónuszt.

A cap nem akadályozhatja a szakmailag indokolt ismétlést. A felhasználó tovább gyakorolhat, csak a további XP csökkenhet nulláig.

## 6.7 Jutalom magyarázhatósága

Minden reward receipt tartalmazza:

- forrás eventet;
- policy verziót;
- base XP-t;
- bónuszokat;
- cap vagy diminishing-return alkalmazását;
- achievement/quest progress változást;
- lokalizálható reason code-ot.

## 6.8 Offline-first

Az XP, achievement, streak és quest progress helyben frissül.

A hálózati sync:

- opcionális;
- késleltethető;
- nem blokkolhat rewardot;
- nem írhat felül újabb lokális állapotot;
- ledger merge-re épül, nem teljes profil last-write-wins cserére.

## 6.9 Etikus motiváció

Tilos:

- hamis countdown;
- véletlen jutalom vásárláshoz kötése;
- „minden barátod megelőzött” jellegű szégyenítés;
- értesítési engedélyért XP adása;
- adatmegosztásért XP adása;
- fizetésért streak freeze adása;
- visszatartott, lejáró megszerzett reward;
- korlátlan push notification;
- gyermekekre célzott vásárlási nyomás.

---

# 7. Célarchitektúra

```text
lib/features/gamification/
├── public.dart
├── domain/
│   ├── activity/
│   │   ├── learning_activity_event.dart
│   │   ├── activity_source.dart
│   │   ├── evidence_trust.dart
│   │   └── reward_eligibility.dart
│   ├── rewards/
│   │   ├── reward_decision.dart
│   │   ├── reward_ledger_entry.dart
│   │   ├── reward_reason.dart
│   │   └── experience_points.dart
│   ├── levels/
│   │   ├── level_definition.dart
│   │   ├── level_curve.dart
│   │   └── level_progress.dart
│   ├── achievements/
│   │   ├── achievement_definition.dart
│   │   ├── achievement_progress.dart
│   │   └── achievement_catalog.dart
│   ├── quests/
│   │   ├── quest_definition.dart
│   │   ├── quest_objective.dart
│   │   ├── quest_progress.dart
│   │   └── quest_schedule.dart
│   ├── streak/
│   │   ├── streak_state.dart
│   │   ├── streak_policy.dart
│   │   └── streak_transition.dart
│   ├── mastery/
│   │   ├── mastery_milestone.dart
│   │   ├── mastery_progress.dart
│   │   └── mastery_badge.dart
│   └── profile/
│       ├── gamification_profile.dart
│       └── reward_inbox_item.dart
│
├── application/
│   ├── gamification_engine.dart
│   ├── activity_event_ingestor.dart
│   ├── reward_policy_engine.dart
│   ├── achievement_evaluator.dart
│   ├── quest_evaluator.dart
│   ├── streak_service.dart
│   ├── mastery_evaluator.dart
│   ├── celebration_coordinator.dart
│   └── profile_projector.dart
│
├── data/
│   ├── gamification_repository.dart
│   ├── local_gamification_repository.dart
│   ├── reward_ledger_repository.dart
│   ├── quest_repository.dart
│   ├── achievement_repository.dart
│   ├── streak_repository.dart
│   ├── gamification_migrator.dart
│   └── sync/
│       ├── gamification_sync_contract.dart
│       └── ledger_merge_policy.dart
│
├── presentation/
│   ├── providers/
│   ├── screens/
│   │   ├── gamification_hub_screen.dart
│   │   ├── achievements_screen.dart
│   │   ├── achievement_detail_screen.dart
│   │   ├── quests_screen.dart
│   │   ├── level_detail_screen.dart
│   │   └── reward_inbox_screen.dart
│   └── widgets/
│       ├── xp_progress_bar.dart
│       ├── level_badge.dart
│       ├── quest_card.dart
│       ├── achievement_tile.dart
│       ├── reward_summary_sheet.dart
│       └── mastery_badge_chip.dart
│
└── infrastructure/
    ├── default_reward_policy.dart
    ├── default_achievement_catalog.dart
    ├── default_quest_catalog.dart
    └── default_level_curve.dart
```

## 7.1 Feature boundary

Más feature nem importálhatja a gamification `data` vagy `presentation` belső fájljait.

Más feature kizárólag:

- a `public.dart` eseményküldő API-ját;
- vagy közös core event buszt

használhatja.

## 7.2 Event delivery

A javasolt első implementáció process-local, explicit application service hívás. Nem szükséges általános, reflektív globális event bus.

Helyes:

```dart
await gamificationEngine.ingest(
  LearningActivityEvent.practiceSessionCompleted(...),
);
```

A feature result mentése legyen elsődleges. A gamification ingestion failure nem teheti sikertelenné a már lezárt practice sessiont. A feldolgozatlan event helyi outboxba kerülhet retryhoz.

---

# 8. Domain modell

## 8.1 LearningActivityEvent

```dart
sealed class LearningActivityEvent {
  const LearningActivityEvent({
    required this.eventId,
    required this.occurredAt,
    required this.localEpochDay,
    required this.source,
    required this.trust,
    required this.schemaVersion,
  });

  final String eventId;
  final DateTime occurredAt;
  final int localEpochDay;
  final ActivitySource source;
  final EvidenceTrust trust;
  final int schemaVersion;
}
```

Javasolt konkrét eventek:

```text
PracticeSessionCompleted
PracticeBlockCompleted
SongSectionCompleted
SongCompleted
AnalysisCompleted
PersonalBestReached
SkillEvidenceImproved
DailyPlanCompleted
WeeklyPlanProgressed
TutorActionCompleted
VisionTechniqueWindowCompleted
LessonMilestoneReached
```

A `eventId` a forrás feature immutable result ID-jából származzon. Nem generálható minden ingestion retrynál újra.

## 8.2 ActivitySource

```dart
enum ActivitySource {
  live,
  analyze,
  learn,
  practice,
  songTrainer,
  vision,
  tutor,
  practicePlan,
}
```

A régi `PracticeSource` értékeket schema migrationnel vagy adapterrel kell leképezni. A perzisztált enumneveket nem szabad kontrollálatlanul átnevezni.

## 8.3 EvidenceTrust

```dart
enum EvidenceTrust {
  unverified,
  userConfirmed,
  deviceObserved,
  scored,
  verified,
}
```

Értelmezés:

- `unverified`: csak UI aktivitás vagy importált, nem ellenőrzött adat;
- `userConfirmed`: felhasználó jelölte késznek;
- `deviceObserved`: valódi audio vagy vision aktivitás észlelve;
- `scored`: valid scorer eredménnyel rendelkezik;
- `verified`: több evidence source, szerveres aláírás vagy későbbi kompetitív ellenőrzés.

Lokális XP-hez általában `deviceObserved` vagy `scored` elegendő. Későbbi globális leaderboardhoz külön, szigorúbb `verified` szabály szükséges.

## 8.4 RewardEligibility

```dart
final class RewardEligibility {
  const RewardEligibility({
    required this.eligible,
    required this.reasonCode,
    required this.validDuration,
    required this.quality,
    required this.difficultyBand,
  });

  final bool eligible;
  final String reasonCode;
  final Duration validDuration;
  final double? quality;
  final int difficultyBand;
}
```

## 8.5 RewardLedgerEntry

```dart
final class RewardLedgerEntry {
  const RewardLedgerEntry({
    required this.ledgerId,
    required this.sourceEventId,
    required this.createdAt,
    required this.policyVersion,
    required this.baseXp,
    required this.bonusXp,
    required this.totalXp,
    required this.reasonCodes,
    required this.achievementChanges,
    required this.questChanges,
    required this.streakTransition,
  });

  final String ledgerId;
  final String sourceEventId;
  final DateTime createdAt;
  final int policyVersion;
  final int baseXp;
  final int bonusXp;
  final int totalXp;
  final List<String> reasonCodes;
  final List<AchievementProgressChange> achievementChanges;
  final List<QuestProgressChange> questChanges;
  final StreakTransition? streakTransition;
}
```

Kötelező invariantok:

- `baseXp >= 0`;
- `bonusXp >= 0`;
- `totalXp == baseXp + bonusXp`;
- egy `sourceEventId` legfeljebb egyszer szerepelhet reward ledgerben;
- reason code legalább egy legyen, ha `totalXp > 0`;
- policy version kötelező;
- ledger entry immutable.

## 8.6 GamificationProfile

```dart
final class GamificationProfile {
  const GamificationProfile({
    required this.totalXp,
    required this.currentLevel,
    required this.levelXp,
    required this.streak,
    required this.achievementProgress,
    required this.activeQuests,
    required this.masteryProgress,
    required this.unseenRewardIds,
    required this.schemaVersion,
  });

  final int totalXp;
  final int currentLevel;
  final int levelXp;
  final StreakState streak;
  final Map<String, AchievementProgress> achievementProgress;
  final Map<String, QuestProgress> activeQuests;
  final Map<String, MasteryProgress> masteryProgress;
  final Set<String> unseenRewardIds;
  final int schemaVersion;
}
```

A profile projection újraépíthető legyen a reward ledgerből és a canonical activity eventekből. A performance érdekében snapshot tárolható, de nem lehet az egyetlen igazságforrás.

## 8.7 LevelDefinition

```dart
final class LevelDefinition {
  const LevelDefinition({
    required this.level,
    required this.requiredTotalXp,
    required this.titleKey,
    required this.iconKey,
  });

  final int level;
  final int requiredTotalXp;
  final String titleKey;
  final String iconKey;
}
```

A level title ne sugalljon szakmai minősítést. Például a „Haladó gitáros” csak XP alapján félrevezető lenne. Javasolt semleges progression címek:

- Explorer;
- Builder;
- Groover;
- Performer;
- Mentor Path.

A lokalizált végleges nevek content review-t igényelnek.

## 8.8 AchievementDefinition

```dart
final class AchievementDefinition {
  const AchievementDefinition({
    required this.id,
    required this.category,
    required this.titleKey,
    required this.descriptionKey,
    required this.objectives,
    required this.visibility,
    required this.rewardXp,
    required this.version,
  });

  final String id;
  final AchievementCategory category;
  final String titleKey;
  final String descriptionKey;
  final List<AchievementObjective> objectives;
  final AchievementVisibility visibility;
  final int rewardXp;
  final int version;
}
```

Achievement kategóriák:

```text
consistency
practice
songs
rhythm
chords
technique
analysis
exploration
personalBest
accessibilityNeutral
```

Az `accessibilityNeutral` nem külön achievement kategória a UI számára, hanem catalog audit jelzés: achievement nem követelhet olyan képességet, amely bizonyos fogyatékossággal vagy eszközzel indokolatlanul kizáró.

## 8.9 QuestDefinition

A quest időben korlátozott, de nem manipuláló feladatcsomag.

```dart
final class QuestDefinition {
  const QuestDefinition({
    required this.id,
    required this.period,
    required this.objectives,
    required this.reward,
    required this.generatedForEpochDay,
    required this.expiresAt,
    required this.version,
  });

  final String id;
  final QuestPeriod period;
  final List<QuestObjective> objectives;
  final QuestReward reward;
  final int generatedForEpochDay;
  final DateTime expiresAt;
  final int version;
}
```

A quest lejárása után a megszerzett progress nem törlődik a practice historyból. Csak a quest reward eligibility zárul le.

## 8.10 StreakState V2

```dart
final class StreakState {
  const StreakState({
    required this.current,
    required this.longest,
    required this.lastQualifiedDay,
    required this.totalQualifiedDays,
    required this.freezes,
    required this.graceState,
    required this.plannedRestDays,
    required this.policyVersion,
  });

  final int current;
  final int longest;
  final int lastQualifiedDay;
  final int totalQualifiedDays;
  final int freezes;
  final StreakGraceState graceState;
  final Set<int> plannedRestDays;
  final int policyVersion;
}
```

A `qualified day` nem feltétlenül bármely egyetlen detected strum. A minimumot policy határozza meg, például:

- legalább 120 másodperc valid practice;
- vagy egy teljes, érvényes Practice/Song blokk;
- vagy egy rövidebb recovery session, ha azt a napi terv kifejezetten engedélyezi.

A minimum küszöb product evaluation tárgya, nem hardcode-olható szétszórtan.

---

# 9. Canonical learning event és outbox

## 9.1 Feature result az elsődleges igazság

A Practice vagy Song session először saját domain resultját menti. Ezután készül a gamification event.

Ha a reward feldolgozás sikertelen:

- a session akkor is sikeres marad;
- az event outboxban marad;
- a következő app start vagy explicit retry feldolgozza;
- a stabil event ID garantálja az idempotenciát.

## 9.2 Local outbox

Javasolt rekord:

```dart
final class PendingActivityEvent {
  const PendingActivityEvent({
    required this.event,
    required this.enqueuedAt,
    required this.attemptCount,
    required this.lastFailureCode,
  });
}
```

Szabályok:

- bounded queue;
- exponential backoff nem szükséges tisztán lokális feldolgozáshoz, de retry loop tilos;
- sérült event karanténba kerül;
- unknown schema nem törlődik automatikusan;
- a user session lezárását nem blokkolja.

## 9.3 Event deduplication

Deduplication kulcs elsődlegesen `eventId`.

Content hash csak migrációs vagy importált legacy eseménynél használható.

Nem elegendő:

- timestamp;
- route;
- lesson ID önmagában;
- session type;
- napi sorszám.

---

# 10. XP policy

## 10.1 XP szerepe

Az XP hosszú távú aktivitás- és felfedezési progress indicator. Nem tekinthető szakmai képességpontszámnak.

Az XP nem használható:

- accuracy helyettesítésére;
- AI Tutor szakmai döntésére;
- nehézség automatikus növelésére;
- community skill rankingre;
- előfizetéshez kötött feature unlockra;
- tanulási tartalom mesterséges blokkolására.

## 10.2 Reward komponensek

Javasolt formula:

```text
session XP = base completion XP
           + valid duration XP
           + quality bonus
           + improvement bonus
           + diversity bonus
           + quest/achievement reward
           - applied cap reduction
```

A kimenet nem lehet negatív.

## 10.3 Példa policy

Az első implementációhoz a számok konfigurálhatók és verziózottak legyenek. Példa, nem végleges product balance:

```text
Valid block completion:       5 XP
Valid session completion:    10 XP
Minden teljes 5 perc:          3 XP, legfeljebb 18 XP/session
Quality bonus:                0–8 XP
Personal-best bonus:          5 XP
Új mode első befejezése:      5 XP
Napi quest:                  10–25 XP
Heti quest:                  30–80 XP
Achievement:                  0–100 XP kategóriától függően
```

A nagyon nagy egyszeri achievement jutalmak ne torzítsák el tartósan a level curve-öt.

## 10.4 Quality bonus

Quality bonus csak akkor adható, ha:

- a scorer verzió ismert;
- confidence megfelelő;
- a feladat score-olható;
- nincs fatal signal-quality probléma;
- a difficulty nem triviálisan a felhasználó bizonyított szintje alatt van.

A quality bonus ne legyen lineárisan az accuracyval azonos. Egy 55%-ról 68%-ra javuló kezdő több improvement bonusra lehet jogosult, mint egy 95%-os játékos ugyanazon a könnyű feladaton.

## 10.5 Daily cap és diminishing return

A rendszer különböztesse meg:

- base learning XP;
- repeat XP;
- quest/achievement XP.

A napi cap ne törölje a quest vagy achievement rewardot, de korlátozhatja a korlátlan repeat XP-t.

Javasolt rule:

- első három érvényes ismétlés: teljes base XP;
- következő három: 50%;
- további azonos exercise/difficulty/day: 0 repeat XP;
- personal-best és skill milestone továbbra is jutalmazható;
- practice history továbbra is teljesen rögzül.

## 10.6 Policy version

Minden ledger entry tárolja a policy verziót.

Policy változáskor:

- korábbi XP nem számolódik újra automatikusan;
- új event az új policyt használja;
- migration csak hibajavítás vagy jogi/adatbiztonsági ok esetén történjen;
- balance változás nem csökkentheti a már megszerzett XP-t.

---

# 11. Level rendszer

## 11.1 Görbe

A level curve legyen:

- monoton növekvő;
- tisztán determinisztikus;
- overflow-biztos;
- tesztelhető;
- kezdetben gyors visszajelzést adó;
- később fokozatosan lassuló;
- felső hard limit nélkül vagy dokumentált maximum mellett.

Javasolt első görbe:

```text
requiredTotalXp(level) = round(60 × level^1.55)
```

A formula csak példa. A végleges görbét szimulációval kell ellenőrizni különböző felhasználói ritmusokra.

## 11.2 Level-up

Level-up során:

- profile projection frissül;
- reward inbox item készül;
- celebration coordinator dönt a megjelenítésről;
- reduced-motion esetén statikus banner jelenik meg;
- több level egyszerre átlépése egy összefoglalóban jelenik meg;
- level-up nem szakítja meg a folyamatban lévő zenélést.

## 11.3 Nincs content lock XP alapján

A szakmai tartalom prerequisite és skill evidence alapján nyíljon, ne XP alapján.

Az XP level adhat:

- kozmetikai, helyi profilkeretet;
- új recap témát;
- opcionális vizuális badge-et;
- statisztikai összefoglalót.

Nem zárhat el alapvető tanulási funkciót.

---

# 12. Achievement rendszer

## 12.1 Achievement típusok

### Egyszeri milestone

Példák:

- első érvényes session;
- első teljes dal;
- első Analyze összehasonlítás;
- első 3-star lesson;
- első personal best.

### Számlálós

Példák:

- 10 valid practice session;
- 5 különböző dal;
- 1000 érvényes stroke;
- 20 tervblokk.

### Progresszív tier

Példák:

- Rhythm Builder I–IV;
- Song Explorer I–III;
- Consistency I–V.

### Feltételhalmaz

Példa:

- gyakorolj legalább három különböző módot egy héten;
- teljesíts song, practice és analysis sessiont ugyanazon a héten.

### Personal-best milestone

Példák:

- 10 BPM javulás ugyanazon skill/difficulty környezetben;
- timing deviation tartós csökkenése;
- három külön sessionben megerősített technikai javulás.

## 12.2 Hidden achievement

Hidden achievement csak pozitív felfedezés lehet. Nem használható a felhasználó kontroll nélküli pszichológiai profilozására.

A hidden achievement leírása unlock után megjelenik.

## 12.3 Achievement progress

A progress:

- canonical eventekből épül;
- idempotens;
- verziózott;
- újraépíthető;
- nem csökken;
- completion timestampet tárol;
- reward ledger entryhez kötött.

## 12.4 Katalógusvalidáció

CI ellenőrizze:

- egyedi ID;
- létező localization key;
- nem negatív reward;
- érvényes objective;
- tier dependency körmentes;
- accessibility audit mező;
- deprecated achievement migration;
- ikon asset létezése.

---

# 13. Quest és Challenge rendszer

## 13.1 Quest és plan különbsége

A Practice Plan szakmai terv. A Quest opcionális motivációs cél.

A quest nem írhatja felül a tervet. Ideális esetben a quest a tervből választ teljesíthető célt.

Példa:

- terv: ma G–Am váltás, refrén loop, szabad játék;
- quest: teljesíts két tervblokkot;
- nem megfelelő quest: játssz öt másik lesson-t csak XP-ért.

## 13.2 Napi quest

A napi quest:

- legfeljebb három objektív;
- legalább egy rövid, elérhető objective;
- offline generálható;
- figyelembe veszi a mai tervet;
- figyelembe veszi a planned rest dayt;
- nem követel nem elérhető feature-t vagy assetet;
- nem követel accountot;
- nem követel kameraengedélyt;
- nem követel értesítési engedélyt.

## 13.3 Heti quest

A heti quest elsősorban:

- rendszerességet;
- változatosságot;
- tervkövetést;
- legalább egy élvezeti blokkot;
- személyes javulást

ösztönözzön.

A heti quest ne követeljen hét egymást követő napot.

## 13.4 Challenge V2

A Challenge V2 támogatja:

- legacy daily strum patternt;
- akkordváltás challenge-et;
- rhythm challenge-et;
- song-section challenge-et;
- timing consistency challenge-et;
- optional vision technique challenge-et;
- difficulty bandet;
- fallbacket;
- content versiont;
- completion policyt.

A napi challenge generálás determinisztikus maradjon ugyanazon catalog version és epoch day mellett.

## 13.5 Expiration

Lejáratkor:

- a megszerzett reward megmarad;
- a practice eredmény megmarad;
- a részleges progress archiválható;
- nincs negatív üzenet;
- a UI egyszerűen új időszakot mutat;
- offline időzónaváltásnál nem generálható korlátlan új quest.

---

# 14. Streak V2

## 14.1 Streak célja

A streak rendszeres visszatérést jelez, nem szakmai szintet.

## 14.2 Qualified practice day

Egy nap akkor minősül, ha legalább egy policy szerint érvényes aktivitás történt.

A policy támogathat:

- teljes Practice blockot;
- teljes Song sectiont;
- legalább minimális valid practice időt;
- rövid recovery sessiont;
- teljes napi tervet.

Egyetlen véletlen strum ne feltétlenül minősítse a napot.

## 14.3 Freeze

A legacy freeze megmaradhat, de:

- nem vásárolható;
- automatikus, átlátható szabállyal szerezhető;
- használata auditálható;
- a felhasználó látja, mikor fogyott el;
- nagyobb utazásra nem alkalmas, erre planned break szükséges.

## 14.4 Planned rest és pause

A Practice Generator tervezett pihenőnapot adhat.

A streak policy két lehetséges módját ADR-ben kell kiválasztani:

1. A pihenőnap nem növeli, de nem is töri meg a streaket.
2. A pihenőnap heti consistency streaket használ, a napi streak külön marad.

Javasolt: a napi streak mellett vezessünk külön `weeklyConsistency` metrikát, és a planned rest day a napi streaket semleges állapotban tartsa legfeljebb dokumentált keretben.

## 14.5 Grace és recovery

Ha a streak megszakad:

- a UI ne használjon büntető animációt;
- ajánljon rövid recovery sessiont;
- jelenítse meg a longest streaket és total days értéket;
- hangsúlyozza, hogy a tanulási haladás nem veszett el;
- az új streak első napja ne nullázza a történeti achievementeket.

## 14.6 Clock és timezone

A streak repository tárolja:

- local epoch day;
- UTC timestamp;
- last observed timezone offset;
- clock anomaly flaget.

Hátrafelé állított óránál:

- ne adjon új napot;
- ne büntessen;
- logoljon clock anomalyt;
- kompetitív verified státuszt ne adjon.

---

# 15. Mastery és badge rendszer

## 15.1 Mastery nem XP

A mastery kizárólag készségbizonyítékból származik.

Példák:

- strum direction consistency;
- chord transition stability;
- tempo stability;
- timing control;
- song section fluency;
- technique posture consistency.

## 15.2 Több sessionös megerősítés

Mastery milestone ne járjon egyetlen zajos mérésből.

Javasolt feltétel:

- legalább három külön session;
- legalább két külön napon, ha releváns;
- megfelelő confidence;
- összehasonlítható difficulty és tempo;
- minimum sample count.

## 15.3 Badge

A mastery badge:

- lokalizált;
- megmagyarázza a bizonyítékot;
- nem szakmai diploma;
- nem használ félrevezető „mester” címet alacsony küszöbnél;
- verziózott definitionhöz kötött;
- nem vész el.

A későbbi Community csak olyan badge-et tehet megoszthatóvá, amelynek privacy és verification szabálya ezt engedi.

---

# 16. Reward presentation és celebration budget

## 16.1 CelebrationCoordinator

A domain eredmény nem nyit közvetlenül dialogot.

A `CelebrationCoordinator`:

- összegyűjti a session során szerzett rewardokat;
- prioritást ad;
- összevonja a kis XP eseményeket;
- megakadályozza a popup-spamet;
- figyelembe veszi a reduced-motion beállítást;
- csak a session vagy flow természetes lezárásakor jelenít meg összefoglalót.

## 16.2 Priority

Javasolt sorrend:

1. accessibility/safety üzenet;
2. session result;
3. mastery milestone;
4. level-up;
5. achievement;
6. quest completion;
7. XP összefoglaló.

A session közben csak nem zavaró, rövid progress indicator engedélyezett.

## 16.3 Reward inbox

Ha a felhasználó:

- bezárja az appot;
- háttérben kap rewardot;
- sync után kap korrigált receiptet;
- több rewardot egyszerre kap,

azok reward inboxba kerülnek.

Az inbox item:

- egyszer megtekinthetőként jelölhető;
- később is visszakereshető;
- nem jár le;
- nem blokkolja az appot;
- nem követel kötelező claim gombot a már megszerzett XP-hez.

## 16.4 Animáció

- maximum rövid, nem blokkoló animáció;
- haptic opcionális;
- hang alapértelmezetten a globális sound settinget követi;
- reduced motion esetén fade/static state;
- seizure-safe vizuális szabályok;
- nincs villogó fény vagy gyors ismétlődő flash.

---

# 17. Fő felhasználói felületek

## 17.1 Gamification Hub

Tartalma:

- level és XP progress;
- mai questek;
- heti quest;
- streak és weekly consistency;
- legutóbbi achievement;
- mastery summary;
- reward inbox indicator;
- magyarázó „Hogyan működik az XP?” link.

## 17.2 Achievements

Szűrők:

- összes;
- megszerzett;
- folyamatban;
- kategória;
- hidden unlock után.

Minden tile mutassa:

- title;
- description;
- progress;
- megszerzés dátuma;
- reward;
- evidence explanation;
- share eligibility későbbi placeholderét.

## 17.3 Quests

- napi questek;
- heti quest;
- objective progress;
- remaining time semleges megfogalmazással;
- planhez kötött jelzés;
- helyettesítés, ha objective nem végrehajtható;
- lejárt quest history opcionálisan.

## 17.4 Progress integráció

A meglévő Progress képernyőn jelenjen meg:

- XP és level összefoglaló;
- consistency trend;
- achievement milestone;
- mastery evidence;
- a skill progress és a gamification egyértelmű szétválasztása.

## 17.5 Streak integráció

A meglévő Streak képernyő fokozatosan V2 projectiont olvas, de a legacy route és badge átmenetileg megmaradhat.

---

# 18. Integrációs szerződések

## 18.1 Practice Engine

A Practice Engine csak lezárt result után küld eseményt.

Kötelező mezők:

- session ID;
- block ID;
- exercise ID;
- duration;
- completion state;
- difficulty;
- tempo;
- score és confidence, ha létezik;
- skill tagek;
- personal-best flag domain által számolva vagy összehasonlítható adatokkal.

## 18.2 Song Trainer

A full-song completion ne adjon automatikusan sokszoros XP-t ugyanazon barok külön completionje mellett. A policy ismerje a parent-child event kapcsolatot.

## 18.3 Audio Analysis

Analysis completion alap XP csak valid analysisnél jár. Import és re-analysis deduplication source hash + analyzer version alapján történhet.

## 18.4 Computer Vision

Vision-only reward konzervatív legyen. Alacsony confidence mellett achievement vagy mastery nem oldható fel.

## 18.5 Tutor

Tutor conversation önmagában nem ad XP-t. Csak tutor által indított, majd ténylegesen teljesített és más feature által igazolt action jutalmazható.

## 18.6 Practice Generator

Plan completion jutalmazható, de ugyanazok a practice blokkok már kaptak base XP-t. A plan reward kizárólag completion bonus, nem a teljes reward megduplázása.

---

# 19. Persistence és sync

## 19.1 Lokális tárolás

Külön tárolandó:

- activity event outbox;
- processed event ID index;
- reward ledger;
- profile snapshot;
- achievement progress;
- quest instances;
- streak state;
- reward inbox;
- migration state.

Nagyobb adatmennyiségnél SharedPreferences helyett strukturált lokális adatbázis szükséges. Az Epic első körében ADR döntse el, hogy a Core Platform által választott lokális adatbázist használja-e.

## 19.2 Ledger retention

A ledger hosszú távú, de bounded vagy archivált tárolást igényel.

Lehetséges stratégia:

- teljes ledger az utolsó 12 hónapra;
- régebbi ledger havi aggregátum és checksum;
- achievementhez és vitatott rewardhoz szükséges receipt megőrzése;
- user export támogatás később.

A végleges retention privacy review tárgya.

## 19.3 Account sync

Sync unit a ledger entry és immutable activity receipt.

Nem javasolt:

```text
serverProfile.totalXp overwrites localProfile.totalXp
```

Javasolt:

```text
merge unique ledger entries by ledgerId/sourceEventId
validate signatures/trust
rebuild projection
```

## 19.4 Konfliktus

- azonos event, azonos reward: deduplicate;
- azonos event, eltérő policy output: server policy vagy migration decision szükséges;
- lokális unverified és szerver verified receipt: verified supersede, dupla XP nélkül;
- régi device offline rewardja: merge után egyszer kerül be;
- törölt account: lokális offline profile külön policy szerint maradhat vagy törölhető, felhasználói döntéssel.

---

# 20. Anti-abuse és integritás

## 20.1 Lokális rendszer korlátai

A teljesen lokális XP technikailag módosítható rootolt eszközön. Ez elfogadható személyes motivációhoz, de nem alkalmas automatikusan pénzdíjas vagy globális kompetitív rangsorra.

## 20.2 Védelem

- idempotent event ID;
- monotonic event sequence sessionön belül;
- duplicate index;
- duration sanity check;
- impossible score check;
- clock anomaly;
- daily repeat cap;
- parent-child reward deduplication;
- analyzer source hash;
- optional server signature a későbbi verified eventhez;
- structured anomaly log, személyes tartalom nélkül.

## 20.3 Nem büntető reakció

Gyanús event esetén:

- local practice history megmarad;
- reward eligibility lehet `unverified`;
- nincs vádló üzenet;
- nincs account tiltás pusztán kliensheurisztikából;
- community verified rangsor külön döntést kér.

---

# 21. Accessibility, lokalizáció és inkluzív design

## 21.1 Accessibility

Minden reward UI:

- screen reader labellel rendelkezik;
- nem csak színnel jelzi a státuszt;
- támogat nagy betűméretet;
- landscape és kis képernyőn nem vág le tartalmat;
- reduced motiont követ;
- haptics kikapcsolható;
- hangjelzés nélkül is teljes értékű;
- billentyűzettel és switch access-szel navigálható, ahol a platform támogatja.

## 21.2 Achievement fairness

Nem készíthető kötelező achievement, amely kizárólag:

- kamerahasználatot;
- hallható hangjelzést;
- gyors kézmozgást;
- meghatározott kézdominanciát;
- közösségi megosztást;
- account létrehozását

követeli alternatíva nélkül.

## 21.3 Lokalizáció

- minden title és description ARB kulcs;
- plural szabályok;
- dátum és idő locale szerint;
- XP rövidítés lokalizációs review;
- nincs hardcoded angol badge név;
- hidden achievement reveal is lokalizált;
- hosszú magyar szövegek layout tesztje kötelező.

---

# 22. Privacy és etikai követelmények

- raw audio vagy video nem kerül reward ledgerbe;
- csak aggregált result és stabil source ID tárolható;
- e-mail, token és user-generated text nem kerül reason mezőbe;
- analytics alapértelmezetten nem tartalmaz event payload részleteket;
- notification permissionért nincs jutalom;
- account létrehozásért nincs olyan XP, amely tanulási levelt torzít;
- social sharing opcionális és explicit;
- reward history exportálható/törölhető legyen a későbbi account adatkezelési folyamatban;
- gyermekek vagy fiatalkorúak esetén nincs vásárlásra vagy közösségi nyomásra épülő design;
- AI nem személyre szabhat manipulációs intenzitást pszichológiai profil alapján.

---

# 23. Analytics és evaluation

## 23.1 Product analytics

Opt-in vagy privacy-safe aggregált események:

- gamification hub megnyitás;
- quest elfogadás vagy helyettesítés;
- reward summary megtekintés;
- achievement detail megnyitás;
- reduced-motion reward presentation;
- reward processing failure code;
- duplicate prevention count;
- streak recovery flow használata.

Nem küldhető:

- teljes practice event payload;
- raw score timeline;
- nyers audio;
- nyers vision landmark;
- teljes user-generated goal text;
- token vagy email.

## 23.2 Minőségi mutatók

- reward duplication rate: 0;
- reward processing success: legalább 99,9% lokális valid eventekre;
- crash-free reward flow;
- quest completion arány;
- practice variety változás;
- heti visszatérés;
- session hossz változás;
- XP farm koncentráció;
- streak recovery utáni visszatérés;
- notification opt-out arány;
- reduced-motion hibaarány.

## 23.3 Guardrail metric

A gamification nem tekinthető sikeresnek, ha nő az app megnyitása, de csökken:

- az érvényes practice idő;
- a nehéz, szakmailag releváns blokkok aránya;
- a plan adherence;
- a skill improvement;
- a felhasználói kontroll;
- a notification satisfaction.

---

# 24. Tesztelési stratégia

## 24.1 Unit tesztek

- event validation;
- eligibility;
- XP formula;
- diminishing returns;
- daily cap;
- level curve;
- achievement objective;
- quest objective;
- streak transitions;
- planned rest;
- freeze;
- clock anomaly;
- ledger projection;
- sync merge;
- migration.

## 24.2 Property-based tesztek

Invariantok:

- total XP soha nem csökken;
- level monoton;
- ugyanaz az event kétszer nem növeli XP-t;
- reward total nem negatív;
- achievement completion nem fordul vissza;
- streak current nem negatív;
- freeze nem haladja meg a maximumot;
- quest progress nem haladja meg kontrollálatlanul a targetet;
- random event sorrendben a projection determinisztikus, ha a policy order-independent;
- ledger merge kommutatív azonos receipt halmazra.

## 24.3 Widget tesztek

- Hub üres állapot;
- XP progress;
- level-up;
- multiple reward summary;
- achievement grid;
- quest progress;
- streak grace;
- reward inbox;
- reduced motion;
- nagy text scale;
- magyar lokalizáció;
- offline state.

## 24.4 Integrációs tesztek

- Practice completion → event → ledger → UI;
- Song completion parent-child deduplication;
- offline restart;
- outbox retry;
- legacy streak migration;
- account sync merge;
- timezone change;
- clock rollback;
- app background reward;
- multiple level jump;
- Chapter 8 plan completion bonus.

## 24.5 Golden és accessibility tesztek

Kötelező képernyők:

- Gamification Hub;
- achievement detail;
- quest list;
- level-up summary;
- streak recovery;
- reward inbox.

Legalább:

- light/dark;
- hu/en;
- 1.0 és 1.5 text scale;
- reduced motion equivalent state;
- kis telefon.

---

# 25. Teljesítménykövetelmények

- reward decision tipikusan 20 ms alatt fusson középkategóriás eszközön;
- ledger write ne blokkolja az audio threadet;
- profile projection snapshotból azonnal olvasható legyen;
- teljes ledger rebuild háttér isolate-ban vagy chunkokban fusson;
- Hub első frame nem várhat cloud syncre;
- achievement catalog parse egyszer történjen;
- celebration asset ne növelje indokolatlanul az APK méretét;
- egy event feldolgozása ne indítson teljes achievement katalóguson szükségtelen O(n) scan-t, indexelés szükséges;
- reward inbox bounded paginationt használjon.

---

# 26. Codex kötelező végrehajtási szabályai

Minden kör elején:

1. Olvasd el az `AGENTS.md`, Chapter 2 és ezt a fejezetet.
2. Vizsgáld meg az érintett jelenlegi feature kódját és tesztjeit.
3. Egy körben csak az adott scope-ot valósítsd meg.
4. Ne módosíts DSP vagy ML algoritmust.
5. Ne adj XP-t közvetlen UI kódból.
6. Ne vezess be globális mutable event bust.
7. Ne adj negatív XP-t.
8. Ne adj rewardot permission, account vagy sharing engedélyért.
9. Minden perzisztált modell legyen verziózott.
10. Minden reward legyen idempotens.
11. Minden új content ID legyen stabil és egyedi.
12. Minden új UI szöveg ARB-be kerüljön.
13. Minden kör végén futtasd a releváns és teljes teszteket.
14. Frissítsd a `HANDOFF.md` fájlt.
15. Ne kezdd el a következő kört.

## 26.1 Branch minták

```text
codex/epic-08-round-01-baseline
codex/epic-08-round-02-activity-contracts
codex/epic-08-round-03-reward-ledger
```

## 26.2 Kötelező körzáró jelentés

- módosított fájlok;
- új domain invariantok;
- migration hatás;
- futtatott parancsok;
- teszteredmények;
- reward balance feltételezések;
- accessibility ellenőrzés;
- ismert kockázatok;
- elhalasztott feladatok.

---

# 27. Fejlesztési körök

---

# Kör 1 — Baseline, ADR-ek és gamification audit

## Cél

Rögzítsd a jelenlegi Progress, Streak, Daily Challenge, Learn stars és Weekly Recap működését, valamint a nem manipuláló gamification alapelveit.

## Elsődlegesen érintett fájlok

```text
docs/adr/00xx-learning-first-gamification.md
docs/adr/00xx-reward-ledger-and-idempotency.md
docs/adr/00xx-compassionate-streak-policy.md
docs/baseline/epic-08-start.md
```

## Feladatok

1. Készíts fájl- és dependency térképet a progress, streak, learn, share, live és analyze integrációkról.
2. Rögzítsd a jelenlegi storage kulcsokat és JSON schema alakokat.
3. Dokumentáld a jelenlegi streak freeze szabályt, daily challenge generálást és lesson star küszöböket.
4. Készíts dark-pattern tiltólistát és ethical design checklistet.
5. Mérd fel a jelenlegi teszteket, race teszteket és screen-size guardokat.
6. Ne módosíts alkalmazáskódot ebben a körben.

## Kötelező tesztek és ellenőrzések

```bash
flutter analyze lib/ test/
```
```bash
flutter test test/features/streak
```
```bash
flutter test test/features/progress
```
```bash
flutter test test/features/learn
```
```bash
flutter test test/features/share
```

## Elfogadási feltételek

- [ ] Baseline dokumentum elkészült.
- [ ] Minden legacy storage kulcs dokumentált.
- [ ] A reward és streak elvek ADR-ben rögzítettek.
- [ ] Alkalmazáskód nem változott.
- [ ] A meglévő tesztek zöldek.

## Javasolt commit

```text
docs(gamification): establish Epic 8 baseline and principles
```

---

# Kör 2 — Canonical activity event contracts

## Cél

Hozd létre a feature-agnosztikus, immutable és verziózott tanulási eseményeket.

## Elsődlegesen érintett fájlok

```text
lib/features/gamification/domain/activity/learning_activity_event.dart
lib/features/gamification/domain/activity/activity_source.dart
lib/features/gamification/domain/activity/evidence_trust.dart
lib/features/gamification/domain/activity/reward_eligibility.dart
test/features/gamification/domain/activity_event_test.dart
```

## Feladatok

1. Implementáld a sealed event hierarchiát stabil event ID-val, timestamp-pel és epoch day értékkel.
2. Definiáld a Practice, Song, Analysis, Plan, Tutor és Vision eseménytípusokat.
3. Minden event validálja a negatív durationt, hibás score-t és ismeretlen schema verziót.
4. Készíts JSON round-trip támogatást explicit type discriminatorral.
5. Az eventek ne importáljanak Flutter, Riverpod, storage vagy UI típust.
6. Hozz létre public exportot, de még ne integráld feature-ökbe.

## Kötelező tesztek és ellenőrzések

- JSON round-trip minden eventre.
- Ismeretlen event type kontrollált failure.
- Negatív duration elutasítása.
- Event ID equality és hash.
- Domain Flutter-import guard.

## Elfogadási feltételek

- [ ] Minden canonical event immutable.
- [ ] Stabil type discriminator létezik.
- [ ] Domain tiszta Dart.
- [ ] Schema version kötelező.
- [ ] Teszt coverage legalább 90% az új contractokra.

## Javasolt commit

```text
feat(gamification): add canonical learning activity contracts
```

---

# Kör 3 — Reward ledger és idempotency index

## Cél

Hozd létre a jutalmak egyetlen, auditálható igazságforrását.

## Elsődlegesen érintett fájlok

```text
lib/features/gamification/domain/rewards/reward_ledger_entry.dart
lib/features/gamification/domain/rewards/reward_reason.dart
lib/features/gamification/data/reward_ledger_repository.dart
lib/features/gamification/data/local_reward_ledger_repository.dart
test/features/gamification/data/reward_ledger_repository_test.dart
```

## Feladatok

1. Implementáld az immutable ledger entryt sourceEventId unique invarianttal.
2. Készíts atomikus append-if-absent műveletet.
3. Tárold a policy verziót, XP komponenseket és reason code-okat.
4. Készíts processed event ID indexet gyors deduplicationhöz.
5. Kezeled a részleges write és app crash esetét tranzakciós vagy recovery journal megoldással.
6. Biztosíts paginált olvasást és projection rebuild támogatást.

## Kötelező tesztek és ellenőrzések

- Azonos event kétszer csak egy ledger sort hoz létre.
- Crash/recovery fixture.
- Sérült rekord karantén.
- Pagináció.
- Nagy event ID halmaz lookupja.

## Elfogadási feltételek

- [ ] Dupla reward technikailag blokkolt.
- [ ] Ledger immutable.
- [ ] Append atomikus.
- [ ] Unknown schema nem törlődik.
- [ ] UI nem írhat közvetlenül ledgerbe.

## Javasolt commit

```text
feat(gamification): introduce idempotent reward ledger
```

---

# Kör 4 — Activity outbox és megbízható feldolgozás

## Cél

A feature result és reward feldolgozás közötti hibákat adatvesztés nélkül kezeld.

## Elsődlegesen érintett fájlok

```text
lib/features/gamification/application/activity_event_ingestor.dart
lib/features/gamification/data/activity_outbox_repository.dart
lib/features/gamification/data/local_activity_outbox_repository.dart
test/features/gamification/application/activity_ingestor_test.dart
```

## Feladatok

1. Készíts bounded local outboxot pending eventekhez.
2. A feature result mentése után enqueue, majd feldolgozás történjen.
3. Feldolgozási hiba ne változtassa sikertelenné a practice sessiont.
4. Implementálj retryt app startkor és explicit drain művelettel.
5. Ismeretlen vagy sérült event kerüljön quarantine állapotba.
6. Ne hozz létre végtelen retry loopot.

## Kötelező tesztek és ellenőrzések

- Enqueue után restart.
- Reward engine failure és későbbi siker.
- Duplicate outbox event.
- Quarantine.
- Bounded queue pruning policy.

## Elfogadási feltételek

- [ ] Valid event nem vész el.
- [ ] Session completion nem függ rewardtól.
- [ ] Retry idempotens.
- [ ] Quarantine látható diagnosztikában.
- [ ] Outbox bounded.

## Javasolt commit

```text
feat(gamification): add reliable activity event outbox
```

---

# Kör 5 — Reward eligibility és trust policy

## Cél

Döntsd el központilag, hogy egy esemény jutalmazható-e.

## Elsődlegesen érintett fájlok

```text
lib/features/gamification/application/reward_eligibility_policy.dart
lib/features/gamification/infrastructure/default_reward_eligibility_policy.dart
test/features/gamification/application/reward_eligibility_policy_test.dart
```

## Feladatok

1. Definiáld forrásonként a minimum valid durationt és trust szintet.
2. Kezeld a cancelled, failed, low-confidence és fatal signal-quality eseményeket.
3. Különítsd el az alap XP, quality bonus, mastery és verified eligibilityt.
4. Adj stabil reason code-ot minden elutasításhoz.
5. A policy legyen verziózott és konfigurációból felépíthető.
6. Ne használj AI modellt eligibility döntéshez.

## Kötelező tesztek és ellenőrzések

- Rövid zajos Live event elutasítása.
- Érvényes kezdő session elfogadása alacsony accuracy mellett.
- Low-confidence Vision nem ad mastery-t.
- Cancelled session policy.
- Unknown source fail-closed.

## Elfogadási feltételek

- [ ] Minden reward előtt eligibility fut.
- [ ] Reason code lokalizálható.
- [ ] Kezdő effort reward megmarad.
- [ ] Bizonytalan evidence nem old fel mastery-t.
- [ ] Policy determinisztikus.

## Javasolt commit

```text
feat(gamification): implement evidence-based reward eligibility
```

---

# Kör 6 — XP policy engine és diminishing returns

## Cél

Implementáld a verziózott, magyarázható és farmolásálló XP számítást.

## Elsődlegesen érintett fájlok

```text
lib/features/gamification/domain/rewards/experience_points.dart
lib/features/gamification/application/reward_policy_engine.dart
lib/features/gamification/infrastructure/default_reward_policy.dart
test/features/gamification/application/reward_policy_engine_test.dart
```

## Feladatok

1. Implementáld a base, duration, quality, improvement és diversity komponenseket.
2. Adj napi és exercise-specifikus diminishing returnt.
3. Korlátozd a repeat XP-t, de ne a practice historyt.
4. Kezeld a parent-child eventeket a dupla reward elkerülésére.
5. Tárold a cap reduction reasonjét a receiptben.
6. Készíts balance konfigurációt és policy versiont.

## Kötelező tesztek és ellenőrzések

- XP soha nem negatív.
- Azonos input azonos output.
- Ismétlési görbe.
- Daily cap.
- Personal best cap után is jutalmazható.
- Parent-child deduplication.

## Elfogadási feltételek

- [ ] Nincs korlátlan repeat farm.
- [ ] Kezdő session kap base XP-t.
- [ ] Minden komponens magyarázható.
- [ ] Policy verzió ledgerbe kerül.
- [ ] A számok egyetlen configból származnak.

## Javasolt commit

```text
feat(gamification): add transparent XP reward policy
```

---

# Kör 7 — Level curve és profile projection

## Cél

Készíts stabil level rendszert és ledgerből újraépíthető profilt.

## Elsődlegesen érintett fájlok

```text
lib/features/gamification/domain/levels/level_definition.dart
lib/features/gamification/domain/levels/level_curve.dart
lib/features/gamification/domain/profile/gamification_profile.dart
lib/features/gamification/application/profile_projector.dart
test/features/gamification/domain/level_curve_test.dart
```

## Feladatok

1. Implementálj monoton level curve-öt overflow védelemmel.
2. Számíts total XP-ből current levelt és next-level progresszt.
3. Készíts profile snapshotot schema versionnel.
4. Támogasd a teljes ledger rebuildet és incremental projectiont.
5. Kezeld a több szint egyszerre átlépését.
6. Ne használj XP levelt szakmai skill gate-ként.

## Kötelező tesztek és ellenőrzések

- Monoton curve 1–10000 szintig.
- Boundary XP értékek.
- Multiple level jump.
- Snapshot és rebuild parity.
- Nagy XP overflow.

## Elfogadási feltételek

- [ ] Profile újraépíthető.
- [ ] Level nem csökken.
- [ ] Curve egyetlen forrásban van.
- [ ] Level címek localization keyek.
- [ ] Skill unlock nem függ XP-től.

## Javasolt commit

```text
feat(gamification): add level curve and profile projection
```

---

# Kör 8 — Gamification repository és storage schema

## Cél

Központosítsd a gamification persistence réteget verziózott, tesztelhető repositorykba.

## Elsődlegesen érintett fájlok

```text
lib/features/gamification/data/gamification_repository.dart
lib/features/gamification/data/local_gamification_repository.dart
lib/features/gamification/data/gamification_storage_schema.dart
test/features/gamification/data/gamification_repository_test.dart
```

## Feladatok

1. Definiáld a profile snapshot, catalog version, inbox és migration state tárolását.
2. Használd a Chapter 2 KeyValueStore vagy strukturált DB absztrakcióját.
3. Ne importálj közvetlenül SharedPreferences-t presentation vagy application rétegben.
4. Implementálj atomikus snapshot csere és corruption recovery folyamatot.
5. Adj repository watch streamet vagy Riverpod-compatible state frissítést.
6. Dokumentáld retention és méretkorlátokat.

## Kötelező tesztek és ellenőrzések

- Cold start.
- Concurrent write.
- Corrupt snapshot.
- Schema upgrade.
- Repository fake.
- Profile persistence.

## Elfogadási feltételek

- [ ] Storage központosított.
- [ ] Perzisztált modellek verziózottak.
- [ ] Nincs adatvesztő fallback.
- [ ] Fake repositoryval tesztelhető.
- [ ] SharedPreferences közvetlen használata nincs az új feature-ben.

## Javasolt commit

```text
refactor(gamification): add versioned persistence repositories
```

---

# Kör 9 — Legacy progress adapter és activity backfill

## Cél

A meglévő PracticeEntry history használható legyen az új rendszerben dupla jutalom nélkül.

## Elsődlegesen érintett fájlok

```text
lib/features/gamification/data/migration/legacy_practice_adapter.dart
lib/features/gamification/data/migration/gamification_migrator.dart
test/features/gamification/data/legacy_practice_migration_test.dart
```

## Feladatok

1. Készíts determinisztikus legacy event ID-t a régi PracticeEntry rekordokhoz.
2. Mappeld a live, analyze és learn forrásokat új ActivitySource értékekre.
3. A backfill elsődlegesen történeti statisztikát és profile baseline-t építsen.
4. Döntsd el ADR-ben, hogy a régi activity ad-e visszamenőleges XP-t; javasolt egyszeri, korlátozott legacy grant vagy nulla retroaktív XP.
5. Ne duplikáld a future eventeket migration újrafuttatásakor.
6. Tárold a migration checkpointot.

## Kötelező tesztek és ellenőrzések

- Ugyanaz a migration kétszer.
- 400 entry cap history.
- Ismeretlen legacy source.
- Negatív legacy mezők.
- Részleges migration restart.

## Elfogadási feltételek

- [ ] Régi practice history megmarad.
- [ ] Nincs dupla XP.
- [ ] Migration idempotens.
- [ ] Döntés dokumentált.
- [ ] Profile baseline konzisztens.

## Javasolt commit

```text
feat(gamification): migrate legacy practice history safely
```

---

# Kör 10 — Streak V2 domain és legacy migráció

## Cél

Migráld a jelenlegi StreakData modellt verziózott, policy-alapú StreakState V2-re.

## Elsődlegesen érintett fájlok

```text
lib/features/gamification/domain/streak/streak_state.dart
lib/features/gamification/domain/streak/streak_policy.dart
lib/features/gamification/domain/streak/streak_transition.dart
lib/features/gamification/data/migration/legacy_streak_migrator.dart
test/features/gamification/domain/streak_policy_test.dart
```

## Feladatok

1. Őrizd meg current, longest, freezes, totalDays és lastPracticeDay értékeket.
2. Adj policyVersion, graceState és plannedRestDays mezőket.
3. A legacy `practice_streak_v1` kulcsból idempotens migration történjen.
4. A régi `StreakLogic` tesztjeit portold vagy adapterrel tartsd meg.
5. Definiáld a qualified day contractot, de még ne cseréld le az összes feature hívást.
6. Készíts backward-compatible projectiont a régi StreakBadge számára.

## Kötelező tesztek és ellenőrzések

- Legacy JSON migration.
- Freeze megőrzés.
- Longest megőrzés.
- Ismeretlen mező.
- Kétszeri migration.
- Legacy UI projection.

## Elfogadási feltételek

- [ ] Nincs streak adatvesztés.
- [ ] V2 schema verziózott.
- [ ] Régi route tovább működik.
- [ ] Pure streak logic tesztelhető.
- [ ] Storage key migration dokumentált.

## Javasolt commit

```text
refactor(streak): migrate to versioned compassionate streak state
```

---

# Kör 11 — Qualified day, planned rest és recovery policy

## Cél

A streaket valódi gyakorláshoz és rugalmas visszatéréshez kösd.

## Elsődlegesen érintett fájlok

```text
lib/features/gamification/application/streak_service.dart
lib/features/gamification/infrastructure/default_streak_policy.dart
test/features/gamification/application/streak_service_test.dart
```

## Feladatok

1. Definiáld a minimum valid activityt és recovery session szabályt.
2. Integráld a planned rest dayt a Practice Generator contractból.
3. Implementáld a freeze, grace és broken transitionöket.
4. Kezeld az egy napon belüli többszörös eventet idempotensen.
5. Adj weekly consistency projectiont külön a daily streaktől.
6. Clock anomaly esetén ne növeld és ne törd automatikusan a streaket.

## Kötelező tesztek és ellenőrzések

- Qualified és nem qualified event.
- Planned rest.
- Freeze.
- Grace.
- Recovery.
- Clock rollback.
- Timezone forward/back.

## Elfogadási feltételek

- [ ] Egy véletlen strum nem minősít automatikusan napot.
- [ ] Pihenőnap policy dokumentált.
- [ ] Nincs büntető XP-vesztés.
- [ ] Weekly consistency elérhető.
- [ ] Átmenetek reason code-dal rendelkeznek.

## Javasolt commit

```text
feat(streak): add qualified-day rest and recovery policies
```

---

# Kör 12 — Streak UI V2 és recovery flow

## Cél

Frissítsd a Streak képernyőt együttérző, magyarázható V2 állapotra.

## Elsődlegesen érintett fájlok

```text
lib/features/gamification/presentation/screens/streak_detail_screen.dart
lib/features/gamification/presentation/widgets/streak_status_card.dart
lib/features/gamification/presentation/widgets/weekly_consistency_card.dart
test/features/gamification/presentation/streak_detail_screen_test.dart
```

## Feladatok

1. Mutasd current, longest, total days, freeze és weekly consistency értékeket.
2. A broken state hangsúlyozza, hogy a skill progress nem veszett el.
3. Adj recovery session CTA-t, nem büntető countdownot.
4. Mutasd, ha planned rest day védi a ritmust.
5. Tartsd meg a régi `/streak` route kompatibilitását redirecttel vagy wrapperrel.
6. Adj reduced-motion és nagy text scale layoutot.

## Kötelező tesztek és ellenőrzések

- First-time empty.
- Active streak.
- At risk.
- Planned rest.
- Broken/recovery.
- Freeze used.
- 1.5 text scale.

## Elfogadási feltételek

- [ ] Nincs shame copy.
- [ ] Recovery elérhető.
- [ ] Régi deep link működik.
- [ ] Screen reader label teljes.
- [ ] Kis képernyőn nincs overflow.

## Javasolt commit

```text
feat(streak): deliver compassionate Streak V2 experience
```

---

# Kör 13 — Achievement domain és katalógus

## Cél

Hozz létre típusos, validálható és lokalizálható achievement rendszert.

## Elsődlegesen érintett fájlok

```text
lib/features/gamification/domain/achievements/achievement_definition.dart
lib/features/gamification/domain/achievements/achievement_progress.dart
lib/features/gamification/domain/achievements/achievement_catalog.dart
lib/features/gamification/infrastructure/default_achievement_catalog.dart
test/features/gamification/domain/achievement_catalog_test.dart
```

## Feladatok

1. Definiáld az objective típusokat: count, threshold, distinct, sequence és compound.
2. Készíts első, kis curated katalógust 20–30 achievementtel.
3. Használj stabil ID-kat és ARB kulcsokat.
4. Támogasd a tier dependencyket és hidden státuszt.
5. Adj content versiont és deprecation mezőt.
6. Készíts catalog validator scriptet.

## Kötelező tesztek és ellenőrzések

- Duplicate ID.
- Missing l10n key.
- Cyclic tier dependency.
- Invalid threshold.
- Negative reward.
- Missing icon.

## Elfogadási feltételek

- [ ] Katalógus CI-ben validálható.
- [ ] Nincs hardcoded UI szöveg.
- [ ] Objective típusos.
- [ ] Tier graph körmentes.
- [ ] Accessibility audit mező létezik.

## Javasolt commit

```text
feat(gamification): add validated achievement catalog
```

---

# Kör 14 — Achievement evaluator és progress projection

## Cél

Canonical eventekből idempotensen építs achievement progresszt.

## Elsődlegesen érintett fájlok

```text
lib/features/gamification/application/achievement_evaluator.dart
lib/features/gamification/application/achievement_index.dart
test/features/gamification/application/achievement_evaluator_test.dart
```

## Feladatok

1. Indexeld az achievementeket event type és metric alapján.
2. Egy event csak releváns objectiveket értékeljen.
3. Kezeld a count, distinct, threshold és compound progresszt.
4. Completion egyszer történjen és ledgerhez kötődjön.
5. Későn hozzáadott achievementhez támogass bounded backfillt.
6. Unknown objective fail-closed legyen.

## Kötelező tesztek és ellenőrzések

- Single completion.
- Duplicate event.
- Distinct song count.
- Compound objective.
- Tier unlock.
- Backfill parity.

## Elfogadási feltételek

- [ ] Achievement nem oldódik fel kétszer.
- [ ] Evaluator nem scan-eli szükségtelenül a teljes katalógust.
- [ ] Progress újraépíthető.
- [ ] Completion timestamp stabil.
- [ ] Reward receipt létrejön.

## Javasolt commit

```text
feat(gamification): evaluate achievement progress from events
```

---

# Kör 15 — Achievement UI és részletes evidence

## Cél

Készíts jól navigálható achievement listát és részletes magyarázatot.

## Elsődlegesen érintett fájlok

```text
lib/features/gamification/presentation/screens/achievements_screen.dart
lib/features/gamification/presentation/screens/achievement_detail_screen.dart
lib/features/gamification/presentation/widgets/achievement_tile.dart
test/features/gamification/presentation/achievements_screen_test.dart
```

## Feladatok

1. Implementáld az all, unlocked, in-progress és category filtereket.
2. Mutasd a progresszt és completion dátumot.
3. Hidden achievement csak unlock után fedje fel a részleteket.
4. Az evidence nézet reason code-okból készítsen közérthető magyarázatot.
5. Ne mutass nyers audio vagy érzékeny session adatot.
6. Készíts empty state-et új felhasználónak.

## Kötelező tesztek és ellenőrzések

- Empty catalog.
- Progress tile.
- Unlocked detail.
- Hidden locked.
- Filter.
- Hungarian long text.

## Elfogadási feltételek

- [ ] Minden achievement érthető.
- [ ] Evidence privacy-safe.
- [ ] Hidden state nem szivárog.
- [ ] Accessibility semantics rendben.
- [ ] Navigation route argumentum validált.

## Javasolt commit

```text
feat(gamification): add achievement discovery and detail UI
```

---

# Kör 16 — Quest domain, objective és lifecycle

## Cél

Hozd létre a napi és heti questek típusos lifecycle-ját.

## Elsődlegesen érintett fájlok

```text
lib/features/gamification/domain/quests/quest_definition.dart
lib/features/gamification/domain/quests/quest_objective.dart
lib/features/gamification/domain/quests/quest_progress.dart
lib/features/gamification/domain/quests/quest_schedule.dart
test/features/gamification/domain/quest_model_test.dart
```

## Feladatok

1. Definiáld active, completed, expired, replaced és archived állapotokat.
2. Quest objective hivatkozzon skill tagre, plan blokkra, mode-ra vagy metricre típusosan.
3. Tárold a generation dayt, timezone offsetet, catalog versiont és expiry-t.
4. Completion és reward külön állapot legyen, de reward automatikusan járjon, ne claimhez kötve.
5. Támogasd a helyettesítést reason code-dal.
6. Lejárt quest ne törölje a practice eredményt.

## Kötelező tesztek és ellenőrzések

- Lifecycle transitions.
- Expiry.
- Replacement.
- Completion idempotency.
- Invalid objective.
- Timezone boundary.

## Elfogadási feltételek

- [ ] Quest state gép determinisztikus.
- [ ] Reward nem vész el claim hiányában.
- [ ] Expiry semleges.
- [ ] Objective típusos.
- [ ] Schema verziózott.

## Javasolt commit

```text
feat(gamification): define quest objectives and lifecycle
```

---

# Kör 17 — Napi quest generátor

## Cél

Generálj offline, elérhető és a napi tervhez illeszkedő questeket.

## Elsődlegesen érintett fájlok

```text
lib/features/gamification/application/daily_quest_generator.dart
lib/features/gamification/infrastructure/default_quest_catalog.dart
test/features/gamification/application/daily_quest_generator_test.dart
```

## Feladatok

1. Használd a mai plan objectiveket, feature availabilityt és device capabilityt.
2. Legyen legalább egy rövid objective és legfeljebb három objective.
3. Planned rest day esetén recovery vagy reflection jellegű, opcionális quest legyen, ne kötelező practice grind.
4. Ne válassz camera, account vagy cloud requirementet, ha nem elérhető.
5. Ugyanazon day, profile snapshot és catalog version azonos questet adjon.
6. Adj fallback questet üres katalógus vagy új felhasználó esetén.

## Kötelező tesztek és ellenőrzések

- Determinism.
- No plan.
- Planned rest.
- Camera unavailable.
- Offline.
- Beginner profile.
- Advanced profile.

## Elfogadási feltételek

- [ ] Quest végrehajtható.
- [ ] Nem írja felül a tervet.
- [ ] Nincs permission-kényszer.
- [ ] Deterministic seed dokumentált.
- [ ] Fallback működik.

## Javasolt commit

```text
feat(gamification): generate contextual daily quests offline
```

---

# Kör 18 — Heti quest és consistency objective

## Cél

Hozz létre rugalmas heti célokat, amelyek nem követelnek napi tökéletességet.

## Elsődlegesen érintett fájlok

```text
lib/features/gamification/application/weekly_quest_generator.dart
test/features/gamification/application/weekly_quest_generator_test.dart
```

## Feladatok

1. Használd a heti practice plan és availability adatokat.
2. Támogasd az aktív napok, plan block, mode diversity és improvement objectiveket.
3. Ne generálj hét egymást követő napot kötelező objectiveként.
4. Utazás vagy csökkentett heti idő esetén skálázd a targetet.
5. A hét közbeni tervváltozásnál ne csökkents már teljesített progresszt.
6. Adj következő hétre semleges rollover összefoglalót.

## Kötelező tesztek és ellenőrzések

- 3-day availability.
- 7-day availability.
- Midweek plan edit.
- Missed days.
- Completed early.
- No measurements.

## Elfogadási feltételek

- [ ] Heti quest reális.
- [ ] Progress nem regresszál.
- [ ] Nem büntet kihagyott napért.
- [ ] Target magyarázható.
- [ ] WeeklyRecap integráció előkészített.

## Javasolt commit

```text
feat(gamification): add flexible weekly consistency quests
```

---

# Kör 19 — Challenge V2 és legacy DailyChallenge migráció

## Cél

Bővítsd a determinisztikus napi kihívást több challenge típussal, a legacy pattern megőrzésével.

## Elsődlegesen érintett fájlok

```text
lib/features/gamification/domain/quests/challenge_definition.dart
lib/features/gamification/application/daily_challenge_service.dart
lib/features/gamification/data/migration/legacy_daily_challenge_adapter.dart
test/features/gamification/application/daily_challenge_service_test.dart
```

## Feladatok

1. Csomagold a jelenlegi strum pattern generátort legacy providerként.
2. Adj chord-transition, rhythm, song-section és timing challenge definíciót.
3. A generátor csak elérhető content ID-t használjon.
4. Tárold a napi challenge instance ID-t és completiont.
5. Ugyanazon napi challenge újrajátszható legyen, de reward csak egyszer járjon.
6. Catalog version változásnál az aznapi aktív challenge ne cserélődjön váratlanul.

## Kötelező tesztek és ellenőrzések

- Legacy pattern parity.
- Same-day determinism.
- Replay no duplicate reward.
- Missing content fallback.
- Catalog update mid-day.

## Elfogadási feltételek

- [ ] A régi napi kihívás működik.
- [ ] Challenge completion tartós.
- [ ] Reward idempotens.
- [ ] Offline teljes.
- [ ] Több challenge típus támogatott.

## Javasolt commit

```text
feat(gamification): evolve daily challenge into versioned Challenge V2
```

---

# Kör 20 — Quest és challenge felhasználói felület

## Cél

Készíts áttekinthető napi/heti quest és challenge élményt.

## Elsődlegesen érintett fájlok

```text
lib/features/gamification/presentation/screens/quests_screen.dart
lib/features/gamification/presentation/widgets/quest_card.dart
lib/features/gamification/presentation/widgets/challenge_card.dart
test/features/gamification/presentation/quests_screen_test.dart
```

## Feladatok

1. Mutasd objective progresszt, rewardot és source plan kapcsolatot.
2. Adj Start vagy Continue CTA-t típusos route actionnel.
3. Lehetőséget adj helyettesítésre, ha objective nem elérhető.
4. Expiration copy legyen semleges, ne sürgető dark pattern.
5. Completed reward automatikusan jelenjen meg, claim nélkül.
6. Készíts offline és empty state-et.

## Kötelező tesztek és ellenőrzések

- Daily and weekly.
- Completed.
- Expired.
- Replaced.
- Offline.
- Invalid route action.
- Large text.

## Elfogadási feltételek

- [ ] CTA biztonságos.
- [ ] Nincs kötelező claim.
- [ ] Lejárat nem szégyenítő.
- [ ] Progress pontos.
- [ ] Accessibility rendben.

## Javasolt commit

```text
feat(gamification): deliver quest and challenge experience
```

---

# Kör 21 — Mastery milestone domain és evaluator

## Cél

Különítsd el az XP progresszt a több sessionnel igazolt készség-mérföldkövektől.

## Elsődlegesen érintett fájlok

```text
lib/features/gamification/domain/mastery/mastery_milestone.dart
lib/features/gamification/domain/mastery/mastery_progress.dart
lib/features/gamification/domain/mastery/mastery_badge.dart
lib/features/gamification/application/mastery_evaluator.dart
test/features/gamification/application/mastery_evaluator_test.dart
```

## Feladatok

1. Definiáld a skill tag, metric, difficulty, tempo range és evidence count követelményeket.
2. Legalább több sessionös megerősítést követelj.
3. Kezeld az összehasonlíthatatlan sessionöket.
4. Vision és Analysis evidence csak megfelelő confidence mellett használható.
5. Mastery completion immutable legyen.
6. Adj evidence summaryt privacy-safe mezőkkel.

## Kötelező tesztek és ellenőrzések

- Single noisy session no unlock.
- Three valid sessions unlock.
- Different difficulty excluded.
- Low confidence excluded.
- Duplicate session.
- Personal improvement threshold.

## Elfogadási feltételek

- [ ] Mastery nem XP-ből származik.
- [ ] Több evidence szükséges.
- [ ] Badge magyarázható.
- [ ] Nincs orvosi claim.
- [ ] Completion nem regresszál.

## Javasolt commit

```text
feat(gamification): add evidence-based mastery milestones
```

---

# Kör 22 — Reward inbox és celebration coordinator

## Cél

A jutalmakat nem zavaró, összevont és accessibility-kompatibilis módon jelenítsd meg.

## Elsődlegesen érintett fájlok

```text
lib/features/gamification/domain/profile/reward_inbox_item.dart
lib/features/gamification/application/celebration_coordinator.dart
lib/features/gamification/presentation/screens/reward_inbox_screen.dart
lib/features/gamification/presentation/widgets/reward_summary_sheet.dart
test/features/gamification/application/celebration_coordinator_test.dart
```

## Feladatok

1. Prioritizáld és vond össze a session rewardokat.
2. Több level-up egy összefoglaló legyen.
3. Ne jelenjen meg popup zenélés közben.
4. Background vagy bezárt flow rewardja inboxba kerüljön.
5. A reward már jóváírt, az inbox nem claim mechanika.
6. Kezeld reduced motion, haptics és sound settinget.

## Kötelező tesztek és ellenőrzések

- Multiple rewards.
- Background reward.
- Seen/unseen.
- Reduced motion.
- No haptics.
- Session in progress.

## Elfogadási feltételek

- [ ] Nincs popup spam.
- [ ] Reward azonnal ledgerben van.
- [ ] Inbox tartós.
- [ ] Reduced motion teljes értékű.
- [ ] Priority sorrend tesztelt.

## Javasolt commit

```text
feat(gamification): coordinate accessible reward celebrations
```

---

# Kör 23 — Gamification Hub és level UI

## Cél

Hozd létre a gamification központi, de nem domináló áttekintő felületét.

## Elsődlegesen érintett fájlok

```text
lib/features/gamification/presentation/screens/gamification_hub_screen.dart
lib/features/gamification/presentation/screens/level_detail_screen.dart
lib/features/gamification/presentation/widgets/xp_progress_bar.dart
lib/features/gamification/presentation/widgets/level_badge.dart
test/features/gamification/presentation/gamification_hub_screen_test.dart
```

## Feladatok

1. Mutasd levelt, XP progresszt, questeket, streaket, mastery és legutóbbi achievementet.
2. Adj „Hogyan működik?” magyarázó nézetet az XP komponensekről.
3. A skill score és XP vizuálisan legyen elkülönítve.
4. Ne legyen flashing vagy agresszív countdown.
5. Adj empty state-et legacy és új felhasználónak.
6. Integráld a reward inbox indikátort.

## Kötelező tesztek és ellenőrzések

- Empty.
- Mid-level.
- Level boundary.
- Unseen reward.
- Offline.
- Dark mode.
- Hungarian.

## Elfogadási feltételek

- [ ] XP nem téveszthető össze skill-lel.
- [ ] Hub gyorsan betölt.
- [ ] Offline működik.
- [ ] Nincs overflow.
- [ ] Explanation elérhető.

## Javasolt commit

```text
feat(gamification): add learning-first gamification hub
```

---

# Kör 24 — Practice Engine és Learn integráció

## Cél

Kösd be a legfontosabb session resultokat canonical eventként a jutalmazási pipeline-ba.

## Elsődlegesen érintett fájlok

```text
lib/features/practice/application/gamification_practice_adapter.dart
lib/features/learn/application/gamification_lesson_adapter.dart
test/features/gamification/integration/practice_reward_flow_test.dart
```

## Feladatok

1. Practice session és block completion után készíts stabil eventet.
2. Lesson best accuracy és star progress maradjon saját domainben.
3. A lesson completion event ne adjon kétszer rewardot route újranyitáskor.
4. Kezeld a cancelled és partial sessiont.
5. A legacy Learn direct streak/practice log hívásokat fokozatosan adapter mögé migráld.
6. Biztosíts dual-write időszakot migration flaggel, dupla számolás nélkül.

## Kötelező tesztek és ellenőrzések

- Valid practice.
- Partial.
- Cancelled.
- Lesson replay.
- Provider invalidation.
- Legacy dual-write.

## Elfogadási feltételek

- [ ] Practice reward end-to-end működik.
- [ ] Lesson stars változatlanok.
- [ ] Nincs dupla streak vagy XP.
- [ ] Feature nem importál gamification data réteget.
- [ ] Migration visszakapcsolható.

## Javasolt commit

```text
feat(gamification): integrate Practice and Learn activity rewards
```

---

# Kör 25 — Song Trainer és Setlist integráció

## Cél

Jutalmazd a dalgyakorlást parent-child deduplicationnel és personal-best mérföldkövekkel.

## Elsődlegesen érintett fájlok

```text
lib/features/songs/application/gamification_song_adapter.dart
test/features/gamification/integration/song_reward_flow_test.dart
```

## Feladatok

1. Adj section, loop, full-song és setlist completion eventet.
2. Kapcsold össze a child eventeket parent session ID-val.
3. Full-song bonus ne duplikálja az összes section base rewardot.
4. Kezeld a speed milestone és clean take eventet.
5. Replay ugyanazon take resulttal ne adjon második rewardot.
6. Importált dalnál privacy-safe song identifier használj.

## Kötelező tesztek és ellenőrzések

- Section + full song.
- A-B loop repeat cap.
- Setlist completion.
- Personal best.
- Same take replay.
- Imported song ID.

## Elfogadási feltételek

- [ ] Nincs reward inflation.
- [ ] Song progress változatlan.
- [ ] Personal best magyarázható.
- [ ] Privacy-safe ID.
- [ ] Offline működik.

## Javasolt commit

```text
feat(gamification): integrate Song Trainer milestones safely
```

---

# Kör 26 — Analysis, Vision, Tutor és Practice Generator integráció

## Cél

Kösd be a későbbi epicek nyilvános eventjeit konzervatív trust szabályokkal.

## Elsődlegesen érintett fájlok

```text
lib/features/analyze/application/gamification_analysis_adapter.dart
lib/features/vision/application/gamification_vision_adapter.dart
lib/features/tutor/application/gamification_tutor_adapter.dart
lib/features/practice_planner/application/gamification_plan_adapter.dart
test/features/gamification/integration/cross_feature_reward_flow_test.dart
```

## Feladatok

1. Analysis event source hash és analyzer version alapján legyen deduplicálható.
2. Vision event csak quality gate után adjon technikai progresszt.
3. Tutor beszélgetés önmagában ne adjon XP-t.
4. Practice plan completion csak completion bonus legyen.
5. Az adapterek csak public contractokat importáljanak.
6. Hiányzó jövőbeli feature esetén compile-time vagy feature flag fallback legyen.

## Kötelező tesztek és ellenőrzések

- Re-analysis dedupe.
- Low-confidence vision.
- Tutor chat no XP.
- Tutor action verified.
- Plan block + plan completion.
- Feature disabled.

## Elfogadási feltételek

- [ ] Trust szabályok érvényesek.
- [ ] Nincs chat farming.
- [ ] Plan reward nem dupláz.
- [ ] Adapter boundaries tiszták.
- [ ] Feature flag működik.

## Javasolt commit

```text
feat(gamification): connect analysis vision tutor and planning evidence
```

---

# Kör 27 — Accessibility, settings és értesítési kontroll

## Cél

Tedd a teljes gamification élményt kikapcsolhatóvá, hozzáférhetővé és nem tolakodóvá.

## Elsődlegesen érintett fájlok

```text
lib/features/gamification/domain/gamification_preferences.dart
lib/features/gamification/presentation/providers/gamification_preferences_provider.dart
lib/features/settings/presentation/gamification_settings_section.dart
test/features/gamification/presentation/gamification_accessibility_test.dart
```

## Feladatok

1. Adj beállítást celebration intensity, haptics, sound, reduced motion és motivational notifications számára.
2. A rendszer core progress számítása maradhat, de a vizuális gamification csökkenthető vagy elrejthető.
3. Értesítés ne legyen kötelező és engedélyért ne járjon XP.
4. Minden achievementnek legyen accessibility audit metadataja.
5. Készíts screen reader és text scale teszteket.
6. Magyar és angol copy kerüljön content review checklistre.

## Kötelező tesztek és ellenőrzések

- Gamification visuals off.
- Reduced motion.
- No sound/haptic.
- Notification denied.
- Text scale 2.0.
- Screen reader semantics.

## Elfogadási feltételek

- [ ] Felhasználó kontrollálja az intenzitást.
- [ ] Permissionért nincs reward.
- [ ] Core progress nem vész el.
- [ ] WCAG-szerű kontraszt ellenőrzött.
- [ ] Nincs layout overflow.

## Javasolt commit

```text
feat(gamification): add accessible user-controlled motivation settings
```

---

# Kör 28 — Ledger sync contract, merge és verified státusz

## Cél

Készíts offline-first, duplikációmentes sync szerződést a későbbi account és Community használathoz.

## Elsődlegesen érintett fájlok

```text
lib/features/gamification/data/sync/gamification_sync_contract.dart
lib/features/gamification/data/sync/ledger_merge_policy.dart
backend/app/gamification/schemas.py
backend/app/gamification/service.py
test/features/gamification/data/ledger_merge_policy_test.dart
backend/tests/test_gamification_ledger.py
```

## Feladatok

1. Definiáld az immutable receipt upload/download contractot.
2. Merge unique ledger ID és source event ID alapján történjen.
3. Különítsd el local unverified és server verified státuszt.
4. Ne használj teljes profile last-write-wins felülírást.
5. Kezeld a policy version eltérést és superseding receiptet.
6. Account disabled esetén semmilyen hálózati kérés ne induljon.

## Kötelező tesztek és ellenőrzések

- Two-device merge.
- Same event different ledger ID.
- Verified supersede.
- Offline old device.
- Account disabled.
- Malformed server receipt.

## Elfogadási feltételek

- [ ] Sync nem dupláz XP-t.
- [ ] Lokális offline működés megmarad.
- [ ] Verified státusz auditálható.
- [ ] Backend nem fogad tetszőleges kliens totalXp értéket.
- [ ] Contract verziózott.

## Javasolt commit

```text
feat(gamification): add ledger-based offline sync contract
```

---

# Kör 29 — Integritás, analytics, balance szimuláció és CI

## Cél

Automatizáld a katalógus-, policy-, integritás- és product guardrail ellenőrzéseket.

## Elsődlegesen érintett fájlok

```text
tool/check_gamification_catalog.dart
tool/simulate_gamification_balance.dart
test/features/gamification/property/gamification_invariants_test.dart
.github/workflows/flutter-quality.yml
```

## Feladatok

1. Készíts achievement és quest catalog validatort.
2. Készíts szimulációt beginner, regular, intensive és repeat-farmer profilra.
3. Ellenőrizd a level curve várható idejét és reward koncentrációt.
4. Adj property-based invariant teszteket.
5. Adj privacy-safe analytics adaptert feature flag mögött.
6. CI blokkolja a duplicate ID-t, missing l10n keyt és negatív rewardot.

## Kötelező tesztek és ellenőrzések

- 10000 random event sequence.
- Ledger merge property.
- XP monotonicity.
- Catalog validation.
- Balance simulation snapshot.
- Analytics redaction.

## Elfogadási feltételek

- [ ] CI védi a katalógust.
- [ ] Nincs negatív vagy irreális reward.
- [ ] Repeat farmer nem dominál.
- [ ] Level curve dokumentált.
- [ ] Analytics nem szivárogtat payloadot.

## Javasolt commit

```text
ci(gamification): enforce catalog integrity and balance guardrails
```

---

# Kör 30 — Teljes migráció, regresszió és Epic lezárás

## Cél

Zárd le az Epicet teljes rendszerellenőrzéssel, dokumentációval és legacy kód kivezetési tervvel.

## Elsődlegesen érintett fájlok

```text
docs/sdd/epic-08-completion-report.md
HANDOFF.md
README.md
```

## Feladatok

1. Futtasd a teljes Flutter, property, architecture és backend tesztcsomagot.
2. Ellenőrizd a legacy practice, streak, daily goal és lesson progress migrációt valós fixture-ökkel.
3. Végezz offline restart, timezone, clock rollback és multi-device merge tesztet.
4. Profilozd a reward engine és Hub teljesítményét.
5. Frissítsd a README gamification, privacy és offline részeit.
6. Dokumentáld az ideiglenes dual-write és legacy adapter kivezetési feltételeit.

## Kötelező tesztek és ellenőrzések

```bash
flutter analyze lib/ test/ tool/
```
```bash
flutter test
```
```bash
flutter test test/property
```
```bash
dart run tool/check_architecture.dart
```
```bash
dart run tool/check_gamification_catalog.dart
```
```bash
cd backend && python -m pytest -q
```

## Elfogadási feltételek

- [ ] Minden CI zöld.
- [ ] Nincs dupla reward.
- [ ] Legacy adatok megmaradnak.
- [ ] Offline flow teljes.
- [ ] Reduced motion QA kész.
- [ ] Completion report elkészült.

## Javasolt commit

```text
docs(gamification): close Epic 8 learning-first motivation platform
```


---

# 28. Epic 8 teljes Definition of Done

Az Epic csak akkor tekinthető késznek, ha minden követelmény teljesül.

## Domain és architektúra

- [ ] Létezik canonical `LearningActivityEvent` hierarchia.
- [ ] Minden jutalmazható esemény stabil event ID-val rendelkezik.
- [ ] A gamification domain nem importál Fluttert.
- [ ] Más feature nem importál gamification data vagy presentation belső fájlt.
- [ ] A reward feldolgozás idempotens.
- [ ] Létezik local outbox és retry.
- [ ] A reward policy determinisztikus és verziózott.
- [ ] Nincs AI-alapú XP számítás.

## XP és level

- [ ] Nincs negatív XP.
- [ ] Ugyanaz az event legfeljebb egyszer jutalmazható.
- [ ] Diminishing-return policy működik.
- [ ] A repeat farm korlátozott.
- [ ] A kezdő is kap effort rewardot.
- [ ] A quality bonus confidence gate-et használ.
- [ ] Minden XP komponens reason code-dal rendelkezik.
- [ ] A level curve monoton és overflow-biztos.
- [ ] XP nem zár el alapvető tanulási tartalmat.

## Achievement

- [ ] A katalógus ID-i egyediek.
- [ ] Minden title és description lokalizált.
- [ ] A tier graph körmentes.
- [ ] Az achievement progress idempotens.
- [ ] Completion nem fordul vissza.
- [ ] Hidden achievement nem szivárog unlock előtt.
- [ ] Accessibility audit metaadat rendelkezésre áll.

## Quest és challenge

- [ ] A napi quest offline generálható.
- [ ] A heti quest nem követel napi tökéletességet.
- [ ] A quest nem írja felül a gyakorlási tervet.
- [ ] Nem követel elérhetetlen feature-t vagy permissiont.
- [ ] Lejárat nem töröl gyakorlási eredményt.
- [ ] Reward automatikusan jóváírt, claim nélkül.
- [ ] A legacy DailyChallenge megmaradt vagy adatvesztés nélkül migrálódott.
- [ ] Replay nem ad dupla challenge rewardot.

## Streak

- [ ] A legacy streak adat megmaradt.
- [ ] Qualified day policy központi.
- [ ] Planned rest támogatott.
- [ ] Freeze nem vásárolható.
- [ ] Grace és recovery flow működik.
- [ ] Nincs büntető XP-vesztés.
- [ ] Clock rollback nem generál új napot.
- [ ] Timezone változás tesztelt.
- [ ] Weekly consistency külön megjeleníthető.

## Mastery

- [ ] Mastery nem XP-ből származik.
- [ ] Több sessionös evidence szükséges.
- [ ] Low-confidence evidence nem old fel badge-et.
- [ ] A badge magyarázható.
- [ ] A badge nem szakmai minősítésként kommunikált.

## UI és accessibility

- [ ] Létezik Gamification Hub.
- [ ] Létezik achievement és quest nézet.
- [ ] Létezik reward inbox.
- [ ] A celebration nem szakítja meg a zenélést.
- [ ] Reduced motion teljes értékű.
- [ ] Haptics és sound kikapcsolható.
- [ ] Gamification intenzitás csökkenthető.
- [ ] Nagy text scale nem okoz overflow-t.
- [ ] Minden fontos elem screen reader kompatibilis.
- [ ] Magyar és angol lokalizáció parity zöld.

## Privacy és etika

- [ ] Raw audio/video nem kerül ledgerbe.
- [ ] Permissionért nincs XP.
- [ ] Account létrehozás nem torzítja a tanulási XP-t.
- [ ] Nincs fizetős XP vagy streak freeze.
- [ ] Nincs loot box vagy véletlen fizetős jutalom.
- [ ] Nincs szégyenítő copy.
- [ ] Analytics payload redacted.
- [ ] Social sharing explicit opt-in marad.

## Persistence és sync

- [ ] Ledger tartós és paginált.
- [ ] Profile rebuild és snapshot parity zöld.
- [ ] Legacy migration idempotens.
- [ ] Offline restart után reward megmarad.
- [ ] Két eszköz ledger merge nem dupláz.
- [ ] Account-disabled állapotban nincs hálózati request.
- [ ] Verified és unverified receipt elkülönül.

## Tesztelés és CI

- [ ] Unit tesztek zöldek.
- [ ] Property-based invariant tesztek zöldek.
- [ ] Widget és golden tesztek zöldek.
- [ ] Accessibility tesztek zöldek.
- [ ] Catalog validator zöld.
- [ ] Balance simulation dokumentált.
- [ ] Architecture guard zöld.
- [ ] Backend contract tesztek zöldek.
- [ ] Completion report elkészült.

---

# 29. Kötelező végső ellenőrző parancsok

```bash
flutter pub get

dart format --output=none --set-exit-if-changed lib test tool

flutter analyze lib/ test/ tool/

flutter test

flutter test test/property

dart run tool/check_architecture.dart

dart run tool/check_gamification_catalog.dart

dart run tool/simulate_gamification_balance.dart
```

Backend, ha a sync contract ebben az Epicben implementálva lett:

```bash
cd backend
python -m ruff check app tests
python -m ruff format --check app tests
python -m pytest -q
```

Manuális eszközteszt:

- új telepítés;
- legacy adattal indulás;
- offline practice és reward;
- app kill reward feldolgozás közben;
- restart és outbox drain;
- két azonos event replay;
- napi quest éjfél előtt és után;
- timezone váltás;
- clock rollback;
- planned rest day;
- streak recovery;
- reduced motion;
- screen reader;
- 2.0 text scale;
- 30 perces hosszabb session;
- repeat-farm próbálkozás;
- account sync két eszközzel.

---

# 30. Az Epic eredménye

A Chapter 9 végére a StrumSight rendelkezik egy közös, tanulásközpontú motivációs platformmal, amely:

- a valódi gyakorlást jutalmazza;
- nem manipulálja a felhasználót;
- idempotens és auditálható;
- külön kezeli az XP-t és a szakmai masteryt;
- megtartja és továbbfejleszti a jelenlegi streaket;
- napi és heti questeket ad;
- achievementeket és mastery badge-eket kezel;
- offline teljesen működik;
- accessibility szempontból kontrollálható;
- készen áll a későbbi Community integrációra;
- nem enged ellenőrizetlen lokális eredményt automatikusan globális versenybe.

A következő fejezet:

```text
Chapter 10 — Epic 9: Community
```
