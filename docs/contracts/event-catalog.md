# Domain event catalog & schema registry

- **Kör:** E12-R09
- **ADR:** [`0468`](../adr/0468-domain-event-catalog-and-schema-registry.md)
- **Envelope tulajdonos:** `lib/features/gamification/domain/activity/learning_activity_event.dart`
  ([ADR 0329](../adr/0329-canonical-activity-event-contracts.md)), a `sealed class
  LearningActivityEvent` és hat altípusa. A típusok kizárólag a gamification feature
  `public.dart` barreljén keresztül érhetők el ([ADR 0176](../adr/0176-cross-feature-public-barrel-recognition.md)).
- **Ez a katalógus NEM vezet be új envelope-típust** — a meglévő ADR 0329 szerződést
  dokumentálja és teszteli, nem helyettesíti.

Ez a dokumentum a `main @ bbe86b1a` fán MÉRT állapotot írja le. Minden producer/consumer
hivatkozás létező fájlra (ahol értelmes, sorra) mutat — nem az SDD terv másolata
(ADR 0468 D2).

## Az envelope mezői (MINDEN altípuson azonos)

| Mező | Típus | Megjegyzés |
|---|---|---|
| `type` | `String` | Discriminátor: `practice` \| `song` \| `analysis` \| `plan` \| `tutor` \| `vision` |
| `eventId` | `String` | Hívó-adta, stabil idempotencia-kulcs (nem üres/blank) |
| `occurredAt` | `String` | `DateTime.toIso8601String()` — UTC bemenetnél ezredmásodperccel és `Z`-vel |
| `epochDay` | `int` | Naptári nap-index |
| `source` | `String` | `ActivitySource` enum név |
| `trust` | `String` | `EvidenceTrust` enum név |
| `schemaVersion` | `int` | Kötelező, **pontosan** `learningActivityEventSchemaVersion` (jelenleg `1`) |
| `durationMicroseconds` | `int` | `Duration.inMicroseconds`, nem negatív |
| `score` | `double` | `[0, 1]` zárt intervallum |

`ActivitySource` = `{live, analyze, learn, practice, songTrainer, vision, tutor, practicePlan}` ·
`EvidenceTrust` = `{unverified, userConfirmed, deviceObserved, scored, verified}`.

## A katalógus

A "Fogyasztó" oszlop minden sorban ugyanazt a hat, MÉRT fogyasztó-fájlt sorolja fel —
a `LearningActivityEvent.fromJson`/`toJson` a típustól függetlenül ugyanazon a felületen
folyik át; az egyetlen típus-specifikus fogyasztó-ág az `achievement_evaluator.dart:632–639`
`switch`-e.

| Type | Séma-verzió | Producer (mért fájl:sor) | Fogyasztó (mért fájl:sor) | Idempotencia-kulcs | Owner Chapter | Kompatibilitási szabály |
|---|---|---|---|---|---|---|
| `practice` | 1 | `lib/features/practice/application/gamification_practice_adapter.dart:226`, `lib/features/learn/application/gamification_lesson_adapter.dart:201`, `lib/features/gamification/data/migration/legacy_practice_adapter.dart:65` | `lib/features/gamification/application/activity_event_ingestor.dart:53`, `lib/features/gamification/application/achievement_evaluator.dart:634`, `lib/features/gamification/application/streak_service.dart:56`, `lib/features/gamification/infrastructure/default_streak_policy.dart:55`, `lib/features/gamification/data/activity_outbox_repository.dart:31`, `lib/features/gamification/data/local_activity_outbox_repository.dart:219` | `eventId` | Chapter 3 (Practice Engine) | additív mező tolerált; ismeretlen `type` vagy hiányzó/eltérő `schemaVersion` = kontrollált hiba |
| `song` | 1 | `lib/features/songs/application/gamification_song_adapter.dart:362`, `lib/features/songs/application/gamification_song_adapter.dart:423` | `lib/features/gamification/application/activity_event_ingestor.dart:53`, `lib/features/gamification/application/achievement_evaluator.dart:635`, `lib/features/gamification/application/streak_service.dart:56`, `lib/features/gamification/infrastructure/default_streak_policy.dart:55`, `lib/features/gamification/data/activity_outbox_repository.dart:31`, `lib/features/gamification/data/local_activity_outbox_repository.dart:219` | `eventId` | Chapter 4 (Song Trainer) | additív mező tolerált; ismeretlen `type` vagy hiányzó/eltérő `schemaVersion` = kontrollált hiba |
| `analysis` | 1 | `lib/features/analyze/application/gamification_analysis_adapter.dart:223` | `lib/features/gamification/application/activity_event_ingestor.dart:53`, `lib/features/gamification/application/achievement_evaluator.dart:636`, `lib/features/gamification/application/streak_service.dart:56`, `lib/features/gamification/infrastructure/default_streak_policy.dart:55`, `lib/features/gamification/data/activity_outbox_repository.dart:31`, `lib/features/gamification/data/local_activity_outbox_repository.dart:219` | `eventId` | Chapter 7 (Audio Analysis 2.0) | additív mező tolerált; ismeretlen `type` vagy hiányzó/eltérő `schemaVersion` = kontrollált hiba |
| `plan` | 1 | `lib/features/practice_generator/application/gamification_plan_adapter.dart:231` | `lib/features/gamification/application/activity_event_ingestor.dart:53`, `lib/features/gamification/application/achievement_evaluator.dart:637`, `lib/features/gamification/application/streak_service.dart:56`, `lib/features/gamification/infrastructure/default_streak_policy.dart:55`, `lib/features/gamification/data/activity_outbox_repository.dart:31`, `lib/features/gamification/data/local_activity_outbox_repository.dart:219` | `eventId` | Chapter 8 (AI Practice Generator) | additív mező tolerált; ismeretlen `type` vagy hiányzó/eltérő `schemaVersion` = kontrollált hiba |
| `tutor` | 1 | NO PRODUCER (mért) — `lib/features/ai_tutor/application/gamification_tutor_adapter.dart:164–170` kifejezetten kimondja: a tutor-session `PracticeActivityEvent`-ként jutalmazódik, `TutorActivityEvent`-et szándékosan nem épít fel (§5.1, chat-farming elkerülése, ADR 0289) | `lib/features/gamification/application/activity_event_ingestor.dart:53`, `lib/features/gamification/application/achievement_evaluator.dart:638`, `lib/features/gamification/application/streak_service.dart:56`, `lib/features/gamification/infrastructure/default_streak_policy.dart:55`, `lib/features/gamification/data/activity_outbox_repository.dart:31`, `lib/features/gamification/data/local_activity_outbox_repository.dart:219` | `eventId` | Chapter 5 (AI Guitar Teacher) | a típus él a szerződésben (dekódolható/kódolható), de a fán jelenleg nincs termelője — a katalógus ezt mondja ki, nem egy kitalált utat |
| `vision` | 1 | `lib/features/vision/application/gamification_vision_adapter.dart:238`, `lib/features/vision/application/gamification_vision_adapter.dart:281` | `lib/features/gamification/application/activity_event_ingestor.dart:53`, `lib/features/gamification/application/achievement_evaluator.dart:639`, `lib/features/gamification/application/streak_service.dart:56`, `lib/features/gamification/infrastructure/default_streak_policy.dart:55`, `lib/features/gamification/data/activity_outbox_repository.dart:31`, `lib/features/gamification/data/local_activity_outbox_repository.dart:219` | `eventId` | Chapter 6 (Computer Vision) | additív mező tolerált; ismeretlen `type` vagy hiányzó/eltérő `schemaVersion` = kontrollált hiba |

## Idempotencia (ADR 0333)

Az idempotencia-kulcs minden típusnál az `eventId`. Az `activity_event_ingestor.dart:61`
kikényszeríti, hogy a ledger-bejegyzés `sourceEventId`-je egyezzen az esemény `eventId`-jével;
a `local_reward_ledger_repository.dart:77` append-if-absent szűrése ugyanerre a mezőre fut.
Egy adott `eventId` kétszeri feldolgozása így nem duplikál jutalmat.

## Séma-kompatibilitás (ADR 0468 D4, D5)

A támogatott séma-verzió `V = learningActivityEventSchemaVersion = 1`
(`learning_activity_event.dart:5`). A határ **mindkét irányban zár**:

| Eset | Viselkedés | Forrás |
|---|---|---|
| Ismeretlen, EXTRA JSON-mező | Tolerált — a dekódoló csak a nevesített kulcsokat olvassa, a többit eldobja | `_DecodedEvent.fromJson` |
| Hiányzó `schemaVersion` | Kontrollált hiba (`ArgumentError`), NEM csendes `1` default | `_requireInt` |
| `schemaVersion < V` (pl. `0`) | Kontrollált hiba, NEM best-effort olvasás | `_validateEventFields` |
| `schemaVersion == V` (`1`) | Dekódolható, mezőazonos | `_validateEventFields` |
| `schemaVersion > V` (pl. `2`) | Kontrollált hiba, NEM csendes elfogadás | `_validateEventFields` |
| Ismeretlen `type` | Kontrollált hiba | `LearningActivityEvent.fromJson` switch default ága |

Precedens: [ADR 0215](../adr/0215-analysis-document-versioning.md) 2. pont — ismeretlen VAGY
alacsonyabb verzió kontrollált hiba, nem best-effort olvasás.

## Fixture-ök

`test/fixtures/events/*.json` — altípusonként egy, BYTE-szinten kanonikus alakban: az adott
esemény `toJson()`-je termeli ugyanezt a mezőhalmazt (ADR 0468 D5). A gépi ellenőrzés:
`test/core/events/event_schema_compatibility_test.dart`.

## Amit ez a katalógus NEM dönt el

- A `lib/features/community/application/outbox/community_outbox.dart` (460 sor) egy külön,
  community-oldali szerződés — nem tárgya ennek a katalógusnak (ADR 0468).
- Nem vezet be új esemény-altípust vagy envelope-verziót.
