# ADR 0390 — Practice és Learn gamification adapter: meglévő esemény-típus, outbox-útvonal, caller-fed kettős írás

- **Státusz:** elfogadva (E08-R24 pre-flight)
- **Dátum:** 2026-08-22
- **Kör:** `E08-R24` — Practice Engine és Learn integráció
- **Kapcsolódó:** [`0329`](0329-canonical-activity-event-contracts.md),
  [`0333`](0333-activity-outbox-reliable-processing.md),
  [`0338`](0338-reward-eligibility-policy-four-gates.md),
  [`0301`](0301-reward-ledger-append-only-idempotency.md),
  [`0353`](0353-caller-fed-compassionate-streak-v2-presentation.md)

> **Számozási megjegyzés:** a kör-brief `0317`-et nevezte meg előre kiosztott
> ADR-számként (2026-08-18-i írás állapota), de `docs/adr/` mára `0389`-ig
> tart — a `0317` egy korábbi, független kör alatt régen elkelt. A kötelező
> `tools/round-slots.py reserve-adr --round E08-R24` futás ezért `0390`-et
> adott; a foglaló mért eredménye az irányadó.

## Kontextus

Az `E08-R02` (`ADR 0329`) már lefektette a kanonikus `LearningActivityEvent`
szerződést hat konkrét típussal (`PracticeActivityEvent`, `SongActivityEvent`,
`AnalysisActivityEvent`, `PlanActivityEvent`, `TutorActivityEvent`,
`VisionActivityEvent`) — **nincs köztük külön "lecke" típus**. A típusokat az
`ActivitySource` mező (nyolc érték, köztük `practice` és `learn`)
különbözteti meg, nem a `type` diszkriminátor. Mérve (pre-flight, `grep -n
"class.*ActivityEvent extends" lib/features/gamification/domain/activity/
learning_activity_event.dart`): a `PracticeActivityEvent` a session-alakú
aktivitás (időtartam + [0,1] pontszám) általános hordozója, és ma **egyetlen
feature sem hoz létre ilyet éles kódból** — a hat típus és a nyolc forrás a
R02 óta kizárólag doménkód, hívó nélkül.

A `RewardLedgerRepository` felé két, EGYMÁSTÓL FÜGGETLEN írási minta létezik
ma a kódban (mérve):

1. **Közvetlen** (`daily_challenge_service.dart:457`) — a hívó maga építi a
   `RewardLedgerEntry`-t rögzített `baseXp`-vel, és azonnal
   `rewardLedger.appendIfAbsent()`-et hív. Nincs R05 jogosultság-kapu, nincs
   R06 XP-policy — a napi challenge saját, egyszerűsített szabálya.
2. **Outbox-alapú** (`ActivityEventIngestor.recordSavedActivity` →
   `ActivityOutboxRepository.enqueue` → később `drain()`) — ez az `ADR 0333`
   mintája: a hívó a session MENTÉSE UTÁN, szinkronnak tűnő hívással
   sorba állítja az (esemény, kész bejegyzés) párt; a tényleges ledger-írás
   később, a drain-ben történik, és egy ledger-hiba SOSE teszi
   sikertelenné a felhasználó menteni kívánt session-jét.

A brief (§6 A1) explicit sorrendet ír elő: *„esemény → outbox → jogosultság →
XP → főkönyv"*. Ez a **2. (outbox-alapú) mintát** jelöli ki, NEM az 1.-et —
de a jogosultság (`DefaultRewardEligibilityPolicy.evaluate`, `ADR 0338`) és
az XP-számítás (`reward_policy_engine.dart`, R06) logikailag MEGELŐZI az
outbox-hívást, mert az `ActivityEventIngestor.recordSavedActivity` bemenete
egy már KÉSZ `RewardLedgerEntry` — az `ActivityOutboxRecord` konstruktora
kikényszeríti, hogy `entry.sourceEventId == event.eventId`. A brief
sorrend-szövege a teljes láncot írja le (a bejegyzés a drain-ben landol a
főkönyvben), nem az egyes hívások időrendjét.

A `practice`/`learn` feature MA (mérve, `grep -rln "features/streak\|features/
progress" lib/features/{practice,learn}/`) **nem** ír session-befejezéskor
sem streaket, sem progresst a saját application-rétegéből: a `practice`
egyetlen találata (`daily_challenge_practice_adapter.dart`) egy
`DailyChallenge`-ot alakít `PracticeDefinition`-né, session-befejezéssel
nincs kapcsolatban; a `learn`-ben nulla találat van az `application/`
szinten (a két UI-screen-találat megjelenítési olvasás, nem írás). A brief §2
„MA közvetlenül hívja" állítása tehát a UI-rétegre igaz, az
application-rétegre nem — ez a kör (a korábbi E08 adapter-körökhöz
hasonlóan, pl. R02) egy **önálló, egyelőre be nem kötött** adaptert épít; a
tényleges élő hívási pont bekötése (`practice_session_controller.dart`, a
`learn` screenek) a jelen brief tiltott zónája, tehát KÉSŐBBI kör dolga.

## Döntés

1. **Nincs új domain-típus.** Mindkét adapter a MEGLÉVŐ
   `PracticeActivityEvent`-et építi (`public.dart`-on át importálva), a
   forrást `ActivitySource.practice` illetve `ActivitySource.learn` értékkel
   jelölve. A `lib/features/gamification/domain/**` (tilos zóna) emiatt NEM
   nyílik — sem az adapter, sem az architektúra-guard bővítés nem igényel új
   eseménytípust.

2. **A1 lánc: jogosultság + XP a bejegyzés ELŐTT, az outbox a belépési
   pont.** Mindkét adapter ugyanazt a három lépést hajtja végre, MIELŐTT az
   `ActivityEventIngestor.recordSavedActivity`-t hívja: (a)
   `DefaultRewardEligibilityPolicy.evaluate()` az `ActivityOutcome`
   (`completed`/`cancelled`/`failed`) alapján dönt a kapukról; (b) elutasított
   aktivitásra a lánc itt megáll — nincs esemény-enqueue, nincs XP; (c)
   elfogadott aktivitásra a `reward_policy_engine.dart` számítja az
   `ExperiencePoints`-ot, amiből a `RewardLedgerEntry` épül. A napi-challenge
   közvetlen mintáját (1. pont fent) ez a kör NEM követi és NEM módosítja —
   a két minta tudatosan egymás mellett él, amíg egy jövőbeli kör
   egységesíteni nem dönt.

3. **Megszakítás vs. részleges session — MEGLÉVŐ R05 kapuk, nincs új
   szabály.** A teljesen megszakított (érdemi haladás nélkül elhagyott)
   session `ActivityOutcome.cancelled`-ként megy a jogosultsági döntésbe —
   ez a meglévő policy szerint elutasított. A RÉSZLEGES (néhány célt elért,
   de nem az egészet teljesítő) session `ActivityOutcome.completed`, a
   TÉNYLEGESEN mért `validDuration`/`quality`-val — az R05
   `minValidDurationBySource`/`fatalSignalQualityThreshold` kapuk ezt a mai
   szabály szerint engedik át vagy utasítják el. Ez a kör nem vezet be új
   kaput a „részleges" fogalmára — a helyes `ActivityOutcome`/mért-érték
   besorolás az adapter egyetlen felelőssége itt.

4. **Stabil esemény-azonosító — a session saját perzisztált azonosítójából,
   nem a képernyő életciklusából.** Az `eventId` az adapter bemeneteként
   kapott, a session MENTÉSEKOR már létező azonosítóból (session-id +
   session-szintű determinisztikus szuffix) származik. Az eredmény-képernyő
   újranyitása ugyanazt az `eventId`-t termeli — a
   `RewardLedgerRepository.appendIfAbsent`/`hasProcessedEvent` (`ADR 0301`)
   ezt akkor is elnyeli, ha az adapter mégis kétszer hívódna, de az elsődleges
   védelem az azonosító STABILITÁSA, nem a ledger-oldali dedup.

5. **Kettős írás: caller-fed kapcsoló, éles bekötés nélkül (ADR 0353
   mintája).** Mivel a tényleges `practice`/`learn` hívási pontok
   (`practice_session_controller.dart`, a `learn` screenek) ennek a
   briefnek a tiltott zónájában vannak, a `gamificationDualWriteEnabled`
   háromállású kapcsoló és a „legacy statisztikát ír, nem XP-t" ág az
   adapter **paramétereként/caller-fed bemeneteként** modellezett — a
   `practice_reward_flow_test.dart` a hármas mátrixot (alatt/rajta/fölött)
   egy teszt-dupla „legacy sink" hívással méri, valódi
   `practice_session_controller.dart`-bekötés NÉLKÜL. A „fölött" állapot
   (csak-új-rendszer, legacy hívás megszűnik) implementálható a
   kapcsolóban, de éles alapértékként/aktiválva NEM kerül be — ez a Kör 30
   végállapota (brief §6.1).

## Következmények

Az adapterek ELSŐ ÉLES HÍVÓJA nélkül landolnak — ugyanaz a minta, mint az
`E08-R02` kanonikus eseményszerződése. Egy jövőbeli kör köti be a
`practice_session_controller.dart`/`learn` screen tényleges hívását és a
valódi legacy-write callbacket; eddig a `gamificationDualWriteEnabled`
kapcsoló egy tesztelt, de nem éles-hívott felület. Ez nem e kör rése — a
brief `allowed_paths`-a szándékosan zárja ki a controller/screen fájlokat,
és a §0.0 brief-revízió ezt dokumentálja.

A napi-challenge (`daily_challenge_service.dart`) közvetlen ledger-írási
mintája és az itt bevezetett outbox-alapú minta tudatosan egymás mellett
marad — nem regresszió, hanem két, egymástól független, korábban jóváhagyott
útvonal (`ADR 0301` vs. `ADR 0333`) egyidejű léte, amíg egy jövőbeli
egységesítő kör (ha lesz) dönt.

## Mérce

Az E08-R24 brief §6/§6.1 cellái (A1–A8): a teljes esemény→outbox→jogosultság→
XP→főkönyv lánc (`practice_reward_flow_test.dart` end-to-end cella); a
lecke-csillagok érintetlensége (`test/features/learn` suite, A2); a
képernyő-újranyitás nem termel új jutalmat (A3, a 4. döntés stabil
azonosítója); az adapter-határ (`architecture_dependency_test.dart`, A4, a
2. döntés `public.dart`-only importja); a megszakítás/részleges-session
mátrix (A5, a 3. döntés `ActivityOutcome`-besorolása); a kapcsoló-hármas
(A6, az 5. döntés caller-fed felülete); a kettős írás alatt sincs dupla XP
(A7). A §6.1 kötelező valódi-sértés próba (írass XP-t a legacy oldalon is
kettős írás mellett → az A7 cellának pirosra kell váltania → állítsd vissza)
az 5. döntés gépi őre.
