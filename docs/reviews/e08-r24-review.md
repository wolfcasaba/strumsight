# E08-R24 — Review

Brief: docs/rounds/e08-r24-practice-and-learn-integration.md
ADR: docs/adr/0390-practice-and-learn-gamification-adapter-boundary.md
Diff: `git diff d54a7b4d...2414a373` (branch `minimax/e08-r24-practice-and-learn-integration`)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-22
Verdikt: CHANGES REQUIRED

## Összegzés

BLOCKER: 2 · MAJOR: 0 · MINOR: 0 · NOTE: 1

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Gyakorlási session: esemény → outbox → jogosultság → XP → főkönyv | ✅ | `practice_reward_flow_test.dart` A1 cellák, saját /tmp gate-futás zöld |
| A2 | Lecke-csillagok/legjobb pontosság VÁLTOZATLAN | ✅ | `lesson_progress_repository.dart` a diffben nem szerepel (scope-audit); `test/features/learn` 201~1 zöld |
| A3 | Eredmény-képernyő újranyitása nem ad új jutalmat (PRACTICE) | ✅ | `practice_reward_flow_test.dart` A3 cella |
| A3 | Eredmény-képernyő újranyitása nem ad új jutalmat (LECKE) | ⚠️ igaz, de rossz okból | lásd F1 — a lecke-oldal ezt egy AZONOSÍTÓ-szintű hibával „oldja meg", ami minden jövőbeli ismétlést is elnyel |
| A4 | `practice`/`learn` csak `public.dart`-on át ér gamificationt | ✅ | `architecture_dependency_test.dart` új E08-R24 A4 csoport, 4/4 zöld + saját olvasás a diffen |
| A5 | Megszakított session nem kap jutalmat; részleges az R05 szabálya szerint (PRACTICE) | ✅ | `practice_reward_flow_test.dart` A5 mátrix (cancelled/failed/too-short/partial-alatt/partial-fölött) |
| A5 | ...ugyanez a LECKE oldalon | ❌ | nincs egyetlen teszt sem, ami `GamificationLessonAdapter.recordLesson`-t hívná — lásd F2 |
| A6 | Migrációs kapcsoló hármas állapota (PRACTICE) | ✅ | `practice_reward_flow_test.dart` A6 off/dual/newOnly cellák |
| A6 | ...ugyanez a LECKE oldalon | ❌ | nincs teszt — lásd F2 |
| A7 | Kettős írás mellett nincs dupla XP (PRACTICE) | ✅ | `practice_reward_flow_test.dart` A7 happy-path + §6.1 próba |
| A7 | ...ugyanez a LECKE oldalon | ❌ | nincs teszt — lásd F2 |
| A8 | `test/features/learn` VÁLTOZATLANUL zöld | ✅ | saját /tmp gate-futás: `+201 ~1: All tests passed!` |

## Scope-audit

```
python3 tools/scope-audit.py --repo /tmp/review-e08-r24 --brief docs/rounds/e08-r24-practice-and-learn-integration.md --base d54a7b4d
→ Legacy scope audit OK (d54a7b4dc12e..2414a373ad56, 5 changed path(s), 0 generated/ignored)
```

Engedélyezett fájlokon kívüli változás: **nincs**. Az 5 megváltozott útvonal
pontosan a brief §4 listája (2 új adapter, 2 teszt, a brief maga a §10
handoffhoz) — a `public.dart` nem módosult, mert minden szükséges szimbólum
(ADR 0390 méréseinek megfelelően) már exportálva volt.

## Gate-bizonyíték (saját, izolált `/tmp` klón)

```
git clone --branch minimax/e08-r24-practice-and-learn-integration \
  https://github.com/wolfcasaba/strumsight.git /tmp/review-e08-r24
bash tools/prepare-flutter-generated.sh
tools/round-gate.sh test/features/gamification/integration/practice_reward_flow_test.dart \
  test/core/architecture_dependency_test.dart test/features/learn
→ format/analyze/test×3/architecture/secrets/l10n — MIND ZÖLD
  (test/features/learn: „+201 ~1: All tests passed!")
```

A zöld gate **nem** bizonyíték — lásd F1/F2: a gate zöld volt, mert a hibás
kódút egyetlen teszt által sincs lefedve.

## Megállapítások

### F1 — BLOCKER — A lecke-adapter azonosítója leckénkénti, nem próbálkozásonkénti: minden ismételt lecketeljesítés örökre elnyelődik az elsőn túl

- **Fájl:** `lib/features/learn/application/gamification_lesson_adapter.dart:151` (`stableEventId`), `:181` (felhasználás), és a `LessonGamificationSignal` osztály (`:18-56`) — nincs `sessionId`/`attemptId` mező, csak a statikus `lessonId`.
- **Probléma:** `stableEventId(String lessonId) => 'learn-lesson/$lessonId/v1'` — ez az azonosító KIZÁRÓLAG a lecke KATALÓGUS-azonosítójából (`Lesson.id`, pl. `"lesson-blue-bird"`, `lib/features/learn/model/lesson.dart:62`) származik, tehát UGYANAZ minden egyes alkalommal, amikor BÁRKI BÁRMIKOR teljesíti azt a leckét. Az `ActivityEventIngestor`/`RewardLedgerRepository.appendIfAbsent` a `sourceEventId` szerint dedupol (`ADR 0301`) — a MÁSODIK (és minden további) teljesítés az outbox-drain-ben csendben `supersededByLedger`-ként elvész.
- **Hatás:** egy adott lecke ELSŐ teljesítése után a felhasználó SOHA többé nem kap XP-t ugyanazért a leckéért, akárhányszor gyakorolja újra — akár másnap, akár hónapokkal később. Ez pontosan az ellenkezője annak, amit egy gamifikációs rendszertől elvárunk (ismétlés jutalmazása csökkenő, de nem NULLA hozammal — a meglévő R06 `practiceOccurrenceCount`/`RewardPolicyHistory` mechanizmus PONT erre való, `reward_policy_engine.dart:154`: „the practiceOccurrenceCount-th ON THE DAY" — azaz naponta nullázódó, csökkenő-hozamú számláló, NEM egy örök azonosító-szintű blokk).
- **Ellentmond a briefnek is:** a brief §5.3 kifejezetten úgy fogalmaz: „A lecke-befejezés eseményének azonosítója a **session**-ből származik, nem a képernyő életciklusából" — a brief SAJÁT szövege session-eredetű azonosítót vár el a lecke-oldalon is, nem a statikus katalógus-id-t. Az ADR 0390 4. döntése ugyanezt általánosította mindkét adapterre; a PRACTICE oldal ezt helyesen a `sessionId`-vel oldja meg, a LECKE oldal nem kapott megfelelő (session/attempt-szintű) bemenetet.
- **Mérve, saját eldobható próbateszttel** (nem commitolva, a review után törölve): egy `GamificationLessonAdapter` példányt két, KÜLÖNBÖZŐ napi (`epochDay` 20400 és 20404, 4 nap eltérés) `recordLesson()` hívással futtattam ugyanarra a `lessonId`-ra. Eredmény:
  ```
  day1 accepted=true eventId=learn-lesson/lesson-blue-bird/v1 ledgerCount=1
  day5 accepted=true eventId=learn-lesson/lesson-blue-bird/v1 ledgerCount=1
  ```
  A `day5` hívás `accepted=true`-t jelent (az outbox elfogadta az enqueue-t), de a **ledger végig 1 bejegyzésen marad** — a második teljesítés a drain-ben csendben eldobódik. Ez a defektus éles kód, amit a jelenlegi diff MERGE-re jelöl.
- **Kötelező javítás:** a `LessonGamificationSignal` kapjon egy session/attempt-szintű mezőt (pl. `attemptId` vagy a `learn_screen.dart`/eredmény-képernyő által generált, a képernyő ÉLETCIKLUSÁTÓL független, de a KATALÓGUS-id-től ELTÉRŐ perzisztált azonosító — analóg a practice oldal `sessionId`-jével), és a `stableEventId` ebből (nem a puszta `lessonId`-ból) számoljon. A napon-belüli/nap-közötti csökkenő hozamot a MEGLÉVŐ `practiceOccurrenceCount` mechanizmus kezelje, ne az azonosító-szintű dedup. Mivel a ténylegesen élő hívási pont (a `learn` eredmény-képernyő) ennek a körnek a tiltott zónájában van, az attempt-id forrása ebben a körben is caller-fed maradhat (a teszt-fixture generálja) — csak ne essen vissza a puszta `lessonId`-ra.
- **Ellenőrzés:** a fenti próbateszt (vagy ezzel ekvivalens) kerüljön be a `practice_reward_flow_test.dart`-ba (vagy egy külön lecke-specifikus fájlba, lásd F2) mint állandó regresszió-őr; a javítás után a `day5` hívásnak SAJÁT, `day1`-től ELTÉRŐ `eventId`-t kell termelnie és a ledgernek 2 bejegyzésre kell nőnie.
- **Státusz:** OPEN

### F2 — BLOCKER — A `GamificationLessonAdapter`/`recordLesson` nulla tesztlefedettséggel landol; a §10 handoff burkoltan teljes lefedettséget sugall

- **Fájl:** `test/features/gamification/integration/practice_reward_flow_test.dart` (a fájl SAJÁT fejléc-kommentje, 1-6. sor: „Covers brief §6 acceptance cells A1, A3, A5, A6, A7… The complementary A2/A4/A8 cells live in `test/features/learn/`…" — a LECKE-oldali A1/A3/A5/A6/A7-ről NEM esik szó, mert nincs).
- **Probléma:** `grep -rln "GamificationLessonAdapter\|recordLesson" test/` → **NULLA találat**. A `gamification_lesson_adapter.dart` (267 sor, a brief §8 2. lépése, a kör MÁSODIK legfontosabb célfájlja) egyetlen tesztben sincs példányosítva vagy meghívva. A `practice_reward_flow_test.dart` — a diff EGYETLEN acceptance-tesztfájlja — kizárólag a `GamificationPracticeAdapter`-t importálja és gyakorolja.
- **Hatás:** a brief §1 Célja kifejezetten „a KÉT legfontosabb eredmény-forrást" köti be — a LECKE-oldali A1/A3/A5/A6/A7 minden mérő cellája bizonyítatlan. Ez pontosan az a hibaosztály, amit a review-protokoll „zöld gate NEM bizonyíték" elve céloz: az F1-ben leírt súlyos, valós defektus PONTOSAN azért csúszott át zöld gate-en, mert a kódútvonal, amiben rejtőzik, nulla tesztfedettséggel rendelkezik.
- **Kötelező javítás:** a `practice_reward_flow_test.dart`-hoz (vagy egy testvér `lesson_reward_flow_test.dart`-hoz, ha a diff mérete indokolja) kerüljön egy `GamificationLessonAdapter`-specifikus tesztcsoport, amely UGYANAZT az A1/A3/A5/A6/A7 mátrixot futtatja le, mint a practice oldalon — beleértve az F1 által leírt, nap-közötti ismétlés-cellát is.
- **Ellenőrzés:** az új tesztcsoport a javítás UTÁN zöld; F1 fix nélkül a nap-közötti ismétlés-cella PIROSRA váltana (ez maga a kettő együttes valódi-sértés bizonyítéka).
- **Státusz:** OPEN

### N1 — NOTE — A §6.1 valódi-sértés próba (A7) nem szó szerint az ADR 0390-ben leírt mutáció-módszertant követi, de érvényes

Az A7 „valódi-sértés próba" teszt (`practice_reward_flow_test.dart:228-258`) nem
az adaptert magát rontja el ideiglenesen (ahogy az ADR 0390 Mérce szakasza és a
brief §6.1 szó szerint kéri: „írass XP-t a legacy oldalon… → A7 pirosra vált →
állítsd vissza"), hanem egy „buggy" legacy sink teszt-dublőrt épít, ami
közvetlenül hívja `ledger.appendIfAbsent`-et UGYANAZZAL a `sourceEventId`-vel.
Ez egy érvényes, de GYENGÉBB bizonyíték: azt igazolja, hogy a ledger dedup
elnyeli az ütközést, nem azt, hogy MAGA AZ ADAPTER sosem adna át XP-hordozó
adatot a legacy sink-nek (ezt a `PracticeLegacySink`/`LessonLegacySink`
típusa — `Future<void> Function(PracticeGamificationSignal signal)` — már
FORDÍTÁSI időben kizárja, tehát futásidejű mutáció nem is lenne triviálisan
elvégezhető ugyanazon a felületen). Nem blokkoló — a típusrendszer maga adja a
elsődleges védelmet —, de érdemes a §10 handoffban pontosítani, hogy a próba
ebben a formában futott, nem a szó szerinti brief-recept szerint.

## Javító kör

F1 és F2 ugyanabban a javító körben zárható (ugyanaz a motor, `minimax`,
1 javító kör az eszkalációs küszöb szerint). A javító prompt tartalmazza:
F1 pontos hibaleírását + a mért próba reprodukcióját, F2 kötelező
tesztbővítését, és hogy a javítás után a review-t ÚJRA, saját izolált
`/tmp` klónban futtatom.
