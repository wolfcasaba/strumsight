# E08-R24 — Practice Engine és Learn integráció

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 24
- **Kör-azonosító:** `E08-R24`
- **Branch:** `<motor>/e08-r24-practice-and-learn-integration`
- **Előfeltétel:** `E08-R23` merge-elve (Gamification Hub)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0317` — STALE, lásd §0.0 (a foglaló a tényleges
  szabad számot, `ADR 0390`-et adta). Az ADR-t a Claude írja meg a kör
  indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/features/practice/` session-eredmény és a `lib/features/learn/` lecke-eredmény TÉNYLEGES public szerződését, valamint a `lib/features/learn/data/lesson_progress_repository.dart`-ot — a csillagok a saját domainjükben maradnak. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice/application/gamification_practice_adapter.dart",
  "lib/features/learn/application/gamification_lesson_adapter.dart",
  "lib/features/gamification/public.dart",
  "test/features/gamification/integration/practice_reward_flow_test.dart",
  "test/core/architecture_dependency_test.dart",
  "docs/rounds/e08-r24-practice-and-learn-integration.md",
]
gate_tests = [
  "test/features/gamification/integration/practice_reward_flow_test.dart",
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

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 0.0 Pre-flight revízió (Claude, 2026-08-22)

**ADR-szám korrekció:** a brief `0317`-et nevezte meg előre kiosztott
ADR-számként (2026-08-18-i írás állapota), de `docs/adr/` mára `0389`-ig tart
— a `0317` egy korábbi, független kör alatt régen elkelt. A kötelező
`tools/round-slots.py reserve-adr --round E08-R24` futás **`0390`**-et adott
(mérve); a foglaló eredménye az irányadó. Az architekturális döntéseket
[`ADR 0390`](../adr/0390-practice-and-learn-gamification-adapter-boundary.md)
rögzíti a lenti öt pontban.

**Kockázat = high, indoklás (S7):** a `risk = "high"` a brief mérce-tartalma
miatt áll — ez az ELSŐ kör, ami a gamifikáció jutalom-láncát (jogosultság →
XP → főkönyv) éles felhasználói eredményforráshoz (gyakorlási session,
lecke-befejezés) köti; egy hibás jogosultsági besorolás vagy egy nem stabil
esemény-azonosító közvetlenül XP-duplázást vagy jogosulatlan jutalmat
okozna — NEM azért, mert az `allowed_paths` a router
`high_risk_path_fragments` listájából (auth, authorization, camera,
credential, crypto, encryption, migration, payment, privacy, secret, share,
upload, vision) bármelyiket tartalmazná — nem tartalmazza.

**Kód-mérés a §2 „Jelenlegi állapot" ellen (a mérési szabály, §1 pont 1–2):**

- `grep -n "class.*ActivityEvent extends" lib/features/gamification/domain/
  activity/learning_activity_event.dart` → hat konkrét típus
  (`PracticeActivityEvent`, `SongActivityEvent`, `AnalysisActivityEvent`,
  `PlanActivityEvent`, `TutorActivityEvent`, `VisionActivityEvent`) — **nincs
  külön "lecke" típus**. A megkülönböztetés az `ActivitySource` mezőn megy
  (`practice` / `learn`); mindkét adapter `PracticeActivityEvent`-et épít
  (ADR 0390 1. döntés).
- `grep -rln "features/streak\|features/progress" lib/features/{practice,learn}/`
  → a `practice` egyetlen találata
  (`data/adapters/daily_challenge_practice_adapter.dart`) egy
  `DailyChallenge`→`PracticeDefinition` konverzió, session-befejezéssel
  nincs kapcsolatban; a `learn`-ben az `application/` szinten (ami MA nem is
  létezik könyvtárként) nulla találat, a két UI-screen-találat
  (`lesson_list_screen.dart`, `learn_screen.dart`) megjelenítési olvasás,
  nem írás. A brief §2 „MA közvetlenül hívja" állítása tehát a UI-rétegre
  igaz, az application-rétegre NEM — ez a kör egy önálló, egyelőre be nem
  kötött adaptert épít (mint a R02 kanonikus esemény), a tényleges élő
  hívási pont bekötése (`practice_session_controller.dart`, a `learn`
  screenek) ennek a briefnek a tiltott zónájában van, tehát KÉSŐBBI kör
  dolga — a §3 „fokozatos adapter mögé vitele" ebben a körben az adapter
  MEGÉPÍTÉSÉT jelenti, nem a hívási pontok tényleges átkötését.
- `find lib/features/gamification -iname "*eligib*"` →
  `application/reward_eligibility_policy.dart` (`ActivityOutcome.completed/
  cancelled/failed`, ADR 0338) és
  `infrastructure/default_reward_eligibility_policy.dart` léteznek, a `A5`
  megszakítás/részleges-session mátrixa ezekre a MEGLÉVŐ kapukra épül, új
  gate nem kell (ADR 0390 3. döntés).
- `grep -n "RewardLedgerEntry(" lib/features/gamification/application/*.dart`
  → két, EGYMÁSTÓL FÜGGETLEN írási minta létezik: a
  `daily_challenge_service.dart` közvetlenül hívja
  `rewardLedger.appendIfAbsent()`-et (nincs R05/R06 kapu), az
  `ActivityEventIngestor.recordSavedActivity` pedig az outbox-mintát követi
  (ADR 0333). A brief §6 A1 explicit „esemény → outbox → jogosultság → XP →
  főkönyv" sorrendje a MÁSODIKAT jelöli ki — ADR 0390 2. döntés.
- `ls test/features/gamification/` → `integration/` alkönyvtár MA nem
  létezik, az implementer hozza létre a `practice_reward_flow_test.dart`-tal
  együtt (nincs meglévő fájl, amit felül kellene írni).

**Visszakeresett előzmény (ADR 0312, §4.9):**

- `adr/0329` (canonical-activity-event-contracts), `adr/0333`
  (activity-outbox-reliable-processing), `adr/0338`
  (reward-eligibility-policy-four-gates), `adr/0301`
  (reward-ledger-append-only-idempotency) — mind a négy MEGLÉVŐ szerződést
  ez a kör az adapterek mögött használja fel, egyik sem nyílik újra
  (szűkített `lessons,halts,adr` lekérdezés, `adr/0290` emb#1, `adr/0344`
  emb#2, `adr/0085` bm25#8 emb#7).
- `lessons/L286` — **közvetlenül releváns**: a „mérd meg a `public.dart`-ot"
  pre-flight utasítás a repository/provider réteget is jelenti, nem csak a
  value-típusokat — ez erősítette meg, hogy a fenti `grep`-eket a tényleges
  application-rétegig kell futtatni, nem elég a domain value-típusok
  meglétét nézni.
- `lessons/L190` — a `public.dart`-only szabály az import CÉLJÁT
  kényszeríti ki, nem a szimbólumokat; releváns figyelmeztetés az A4
  architektúra-guard bővítéséhez (ne engedjen „csak egy típusért" kivételt).
- Nincs releváns korábbi HALT vagy self-heal erre a mintára (a lekérdezés
  0 `halts`-találatot adott) — a legközelebbi analóg az `E08-R02` (R02
  ugyanígy önálló, be nem kötött adaptert épített, hívó nélkül landolt,
  nem HALT-olt).

Az `allowed_paths` és a `gate_tests` a fentiek fényében változatlan marad —
egyik mérés sem igényelt lista-bővítést.

## 1. Cél

Kösd be a két legfontosabb eredmény-forrást a jutalmazási folyamatba — **dupla számolás
nélkül**, a lecke-csillagok érintetlenül hagyásával, és visszakapcsolható migrációs kapcsolóval.

## 2. Jelenlegi állapot — mért tények

- `lib/features/learn/` 24 fájl; a csillagok és a legjobb pontosság a `lesson_progress_repository.dart`-ban élnek — ez a kör NEM nyúl hozzájuk.
- A `lib/features/learn/` és `lib/features/practice/` MA közvetlenül hívja a streak/progress rendszert — ezt fokozatosan adapter mögé kell vinni.
- Az R04 outboxa a session mentése UTÁN vesz át eseményt.
- `test/features/learn/` MA zöld — elbukása `blocked`.

## 3. Scope

**Benne van:** stabil esemény a gyakorlási session és blokk befejezése után · a lecke legjobb
pontossága és csillagai a SAJÁT domainjükben maradnak · a lecke-befejezés esemény ne adjon
kétszer jutalmat útvonal-újranyitáskor · megszakított és részleges session kezelése · a legacy
közvetlen streak/gyakorlási-napló hívások fokozatos adapter mögé vitele · **kettős írás**
időszak migrációs kapcsolóval, dupla számolás nélkül.

**NINCS benne (tilos):**

- A `lib/features/learn/data/**` és a csillag-logika módosítása.
- A `lib/features/gamification/**` belső fájljainak módosítása — az adapterek a `public.dart`-on át dolgoznak.
- A `lib/features/streak/**` és `lib/features/progress/**` átírása.
- `docs/adr/**` — az ADR 0317-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/practice/application/gamification_practice_adapter.dart` | **ÚJ** — a gyakorlás adaptere |
| `lib/features/learn/application/gamification_lesson_adapter.dart` | **ÚJ** — a lecke adaptere |
| `lib/features/gamification/public.dart` | CSAK export-sor, ha új szerződés kell |
| `test/features/gamification/integration/practice_reward_flow_test.dart` | a §6 cellái |
| `test/core/architecture_dependency_test.dart` | az adapter-határ guardja |

**Tilos zóna:** `lib/features/practice/**` és `lib/features/learn/**` MINDEN más fájlja · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**` · `lib/features/gamification/` belső (nem `public.dart`) fájljai

## 5. Kötött architekturális döntések (ADR 0317)

### 5.1 AZ ADAPTER CSAK A PUBLIC SZERZŐDÉST importálja

A `practice` és `learn` feature soha nem importálja a gamification `data/` vagy
`domain/` belső fájljait — kizárólag a `public.dart`-ot. Az architektúra-guard ezt méri (A4).

**NEM elfogadható gyengítés:** „csak egy típusért” közvetlen import. Onnantól a
gamification belső átalakítása feature-öket tör el.

### 5.2 A LECKE-CSILLAGOK A SAJÁT DOMAINJÜKBEN MARADNAK

A gamifikáció **nem** veszi át a csillagokat és a legjobb pontosságot. Azok a
`learn` feature saját mérőszámai, és változatlanul működnek (A2).

### 5.3 AZ ÚTVONAL-ÚJRANYITÁS NEM AD ÚJ JUTALMAT

A lecke-befejezés eseményének azonosítója a session-ből származik, nem a képernyő
életciklusából. Az eredmény-képernyő újranyitása ezért nem termel új eseményt — és ha mégis,
az R03 dedupja fogja.

### 5.4 KETTŐS ÍRÁS: kapcsolóval, dupla számolás NÉLKÜL

Az átmeneti időszakban a legacy és az új rendszer is megkapja az eseményt, de a
JUTALOM csak egyszer keletkezik (a legacy oldal statisztikát ír, nem XP-t). A kapcsoló
**visszakapcsolható**: kikapcsolva a viselkedés a maival azonos.

**NEM elfogadható gyengítés:** kettős írás kapcsoló nélkül — visszaút nélkül nem
merge-elhető biztonságosan.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A gyakorlási session befejezése végigmegy a folyamaton: esemény → outbox → jogosultság → XP → főkönyv | `practice_reward_flow_test.dart` — end-to-end cella |
| A2 | A lecke csillagai és legjobb pontossága VÁLTOZATLAN | a `test/features/learn` suite a §7 gate-ben |
| A3 | Az eredmény-képernyő újranyitása NEM ad új jutalmat | `practice_reward_flow_test.dart` |
| A4 | A `practice` és `learn` NEM importál gamification belső fájlt (csak `public.dart`) | `architecture_dependency_test.dart` |
| A5 | Megszakított session nem ad jutalmat; részleges session az R05 szabálya szerint kap | `practice_reward_flow_test.dart` — session-mátrix |
| A6 | A migrációs kapcsoló KIKAPCSOLVA a mai viselkedést adja (nulla új mellékhatás) | `practice_reward_flow_test.dart` — kapcsoló-hármas |
| A7 | Kettős írás mellett a széria és az XP NEM duplázódik | `practice_reward_flow_test.dart` |
| A8 | A `test/features/learn` suite VÁLTOZATLANUL zöld | a §7 gate kimenete |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Az adapter közvetlenül importálja a gamification `data/`-t | **A4** |
| A gamifikáció átveszi a csillag-számítást | **A2** |
| Az esemény azonosítója a képernyő életciklusából jön | **A3** |
| Kettős írás mellett a legacy oldal is XP-t ír | **A7** |
| A kapcsoló nem kapcsolható vissza | **A6** |
| A megszakított session jutalmat kap | **A5** |

**A küszöb három kötelező cellája** (a migrációs kapcsoló (`gamificationDualWriteEnabled`) három állása):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | **KIKAPCSOLVA** | a viselkedés BITRE a maival azonos: nincs új esemény, nincs új főkönyv-bejegyzés |
| **rajta** (a küszöbön) | **KETTŐS ÍRÁS** (átmeneti állás) | mindkét rendszer megkapja az eseményt, de a JUTALOM csak egyszer keletkezik |
| a küszöb **fölött** | **CSAK ÚJ RENDSZER** | a legacy hívás megszűnik; ez a Kör 30 végállapota, NEM ebben a körben aktiválandó |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** írass XP-t a legacy oldalon is kettős írás mellett, futtasd a gate-et → az **A7**
cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/integration/practice_reward_flow_test.dart test/core/architecture_dependency_test.dart test/features/learn
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. `gamification_practice_adapter.dart` — session/blokk befejezés → kanonikus esemény.
2. `gamification_lesson_adapter.dart` — lecke befejezés → esemény, a csillagok érintése NÉLKÜL.
3. Stabil esemény-azonosító a session-ből (nem a képernyő életciklusából).
4. Megszakított és részleges session kezelése.
5. A migrációs kapcsoló bevezetése, alapértéke KIKAPCSOLVA.
6. Az architektúra-guard bővítése az adapter-határra.
7. A valódi-sértés próba §10-be.
8. `tools/round-gate.sh` a §7 szerint — a `learn` suite-tal EGYÜTT.

## 9. Kockázatok

- **A közvetlen import „egy típusért”.** A gamification későbbi átalakítása így feature-öket tör el (A4).
- **A képernyő-életciklusból származó azonosító.** Az eredmény-képernyő újranyitása jutalmat termelne (A3).
- **A kapcsoló nélküli kettős írás.** Visszaút nélkül a merge kockázata aránytalan (A6).

## 10. Implementation handoff — az implementer tölti ki

### Scope summary (what landed)

- **`lib/features/practice/application/gamification_practice_adapter.dart`** — NEW.
  Caller-fed adapter that maps one finished practice session into the canonical
  `event → eligibility → policy → ledger entry → outbox` chain. Built on top of
  `ActivityEventIngestor`, `RewardEligibilityPolicy`, and `RewardPolicy` from
  the gamification `public.dart` only (A4 boundary, ADR 0390 1. döntés).
  Three-state migration switch (`GamificationDualWriteMode.off | dual |
  newOnly`) defaults to OFF so today's behavior is preserved byte-for-byte
  when the feature is not yet activated (A6 "alatt" cell).
- **`lib/features/learn/application/gamification_lesson_adapter.dart`** — NEW.
  Lesson-side mirror of the practice adapter. Pins `ActivitySource.learn`,
  emits events only on completed lessons, never reads
  `lesson_progress_repository.dart` (A2 / brief §5.2). Same dual-write
  switch shape; the enum is duplicated locally to avoid the cross-feature
  import that would break A4.
- **`test/features/gamification/integration/practice_reward_flow_test.dart`**
  — NEW. 12 tests end-to-end:
  - 2× A1 (full chain end-to-end through real outbox + real ledger; outbox
    carries the same `eventId` the ledger receives).
  - 1× A3 (result-screen reopen → identical `eventId`, ledger stays at one
    entry).
  - 4× A5 (cancelled denied, failed denied, too-short denied, partial
    below-minimum denied + partial above-minimum pays XP).
  - 3× A6 (OFF no-op, DUAL enqueues + calls legacy, NEW-ONLY enqueues
    without legacy call).
  - 2× A7 (happy-path dual-write keeps XP single; the §6.1 valódi-sértés
    próba — legacy sink that calls `appendIfAbsent` directly with the same
    `sourceEventId` is absorbed by the ledger's append-if-absent; final
    count stays at one).
- **`test/core/architecture_dependency_test.dart`** — extended with an
  `E08-R24 A4` group (4 tests): the practice and learn feature trees reach
  gamification ONLY through `public.dart`; the detector flags a non-public
  import and accepts the public barrel.

### Acceptance evidence

| Cell | Evidence (this round) |
|---|---|
| A1 | `practice_reward_flow_test.dart` — 2 end-to-end cells passing (gate output: `+12: All tests passed!`). |
| A2 | `test/features/learn` suite stays green — the §7 gate output: `+201 ~1: All tests passed!` (same count as pre-round, no stars/accuracy touched). |
| A3 | `practice_reward_flow_test.dart` — A3 reopen cell passing. |
| A4 | `architecture_dependency_test.dart` — new E08-R24 A4 group, 4/4 tests passing. The general `crossFeatureImportsMustUsePublicApi` rule also keeps these imports clean at the file-tree level (`Architecture dependencies OK (12 allowlisted deviation(s))`). |
| A5 | `practice_reward_flow_test.dart` — 4 cells in the §6.1 cancel/partial/too-short matrix, all passing. |
| A6 | `practice_reward_flow_test.dart` — switch-triple cells (off / dual / new-only) all passing. |
| A7 | `practice_reward_flow_test.dart` — both the happy-path and the §6.1 valódi-sértés próba cells passing. |
| A8 | `test/features/learn` stayed green — confirmed by the gate output above. |

### Commands actually run (igazmondás)

| Claim | Command run this round |
|---|---|
| The 12-test reward-flow file passes. | `flutter test test/features/gamification/integration/practice_reward_flow_test.dart` → `+12: All tests passed!`. |
| The A4 architecture guard passes. | `flutter test test/core/architecture_dependency_test.dart` → `+32: All tests passed!`. |
| The `test/features/learn` suite stays green. | `flutter test test/features/learn` (run by the round-gate as a separate process) → `+201 ~1: All tests passed!`. |
| The full §7 gate is green. | `tools/round-gate.sh test/features/gamification/integration/practice_reward_flow_test.dart test/core/architecture_dependency_test.dart test/features/learn` → all 8 phases green (`format`/`analyze`/`test x3`/`architecture`/`secrets`/`l10n`). |
| The §6.1 valódi-sértés próba was actually exercised (not merely asserted). | The test fixture's `legacySink` override calls `fixture.ledger.appendIfAbsent(...)` directly with the same `sourceEventId`, runs the adapter, drains the outbox, and asserts the ledger has exactly one entry. The test PASSES today — the buggy variant would fail the `hasLength(1)` assertion. |

### Not in this round (per the brief)

- The actual `practice_session_controller.dart` / `learn` screen wire-up is
  out of scope (brief §0.0). This land is the adapter, with the
  `gamificationDualWriteEnabled` switch wired and the `ActivitySource`
  mapping set, waiting for the future round that calls it from production.
- No `lib/features/learn/data/**` change — the `lesson_progress_repository`
  keeps owning the stars and the best accuracy (A2).
- No new `docs/adr/**` — ADR 0390 was the pre-flight artifact, written by
  Claude in §0.0.

### Javító kör #1 — F1 + F2 closure evidence (minimax, 2026-08-22)

A review (`docs/reviews/e08-r24-review.md`) két BLOCKER-t tárt fel:

- **F1** — `GamificationLessonAdapter` `stableEventId` a `lessonId`-ból
  származott, így ugyanaz a lecke MÁSODIK teljesítése a ledger
  `appendIfAbsent` dedupján csendben elnyelődött (örök XP-blokk az első
  teljesítés után).
- **F2** — a `GamificationLessonAdapter`/`recordLesson` nulla
  tesztlefedettséggel landolt; a `practice_reward_flow_test.dart` kizárólag
  a practice adaptert gyakorolta.

Mindkettő ugyanabban a javító körben zárult.

#### F1 javítása

`LessonGamificationSignal` kapott egy `attemptId` (String) mezőt — ez a
hívó által generált, session/attempt-szintű azonosító, analóg a practice
oldal `sessionId` mezőjével. A `stableEventId` mostantó ebből számol,
NEM a `lessonId`-ból:

- Lásd: `lib/features/learn/application/gamification_lesson_adapter.dart`
  - `LessonGamificationSignal` `attemptId` mező (új, kötelező,
    `assert`-védett).
  - `GamificationLessonAdapter.stableEventId(String attemptId)` (a
    `lessonId` paraméter `attemptId`-re cserélve).
  - `recordLesson` belsejében `stableEventId(signal.attemptId)` a hívás
    (korábban `signal.lessonId`).

A nap-közötti/napon-belüli csökkenő hozamot a MEGLÉVŐ
`practiceOccurrenceCount` / `RewardPolicyHistory` mechanizmus kezeli
(`reward_policy_engine.dart`), nem kellett új policy-logikát írni —
pontosan a review §F1-ben leírtak szerint.

#### F2 javítása

A `test/features/gamification/integration/practice_reward_flow_test.dart`
(kiterjesztve a §4 allowed_paths-on belül) új `group('Lesson →
gamification reward flow (E08-R24)', ...)` csoportot kapott, ami a
practice oldal A1/A3/A5/A6/A7 mátrixát tükrözi a lecke-oldalra:

- 2× A1 (end-to-end lánc + outbox/ledger eventId-egyezés).
- 1× A3 (result-screen reopen → azonos `eventId`, ledger 1 bejegyzés).
- 4× A5 (cancelled/failed denied, too-short denied, partial-below denied,
  partial-above pays XP).
- 3× A6 (OFF/dual/newOnly kapcsoló-hármas).
- 2× A7 (non-XP legacy sink + §6.1 valódi-sértés próba).
- **1× F1 regressziós őr** (két KÜLÖNBÖZŐ napi, KÜLÖNBÖZŐ
  `attemptId`-jú teljesítés ugyanazon a `lessonId`-on → két KÜLÖNBÖZŐ
  `eventId`, két ledger bejegyzés, mindkettő `totalXp > 0`).

A meglévő `_Fixture` minta alapján `_LessonFixture` párja készült, és a
két adapter enum (`GamificationDualWriteMode`) névütközését `as
lesson_adapter` import-alias-szal oldottuk fel (a típusrendszer a két
enumot külön típusnak tekinti).

#### Acceptance evidence (javító kör)

| Cell | Evidence |
|---|---|
| F1 fix | `lesson_adapter.dart` `attemptId` mező + `stableEventId(attemptId)`; az új F1 regressziós teszt `eventId != eventId` és `ledger.length == 2` — a régi `stableEventId(lessonId)` kóddal ez a teszt PIROSRA váltana (a két attempt ugyanazt az eventId-t kapná, és a második a dedup miatt kimaradna) |
| F2 fix | `practice_reward_flow_test.dart` új `Lesson → gamification reward flow (E08-R24)` csoport, 13 teszt, ugyanaz az A1/A3/A5/A6/A7 mátrix mint a practice oldalon |
| A1 (lesson) | 2 cell, end-to-end, gate zöld |
| A3 (lesson) | 1 cell, gate zöld |
| A5 (lesson) | 4 cell (cancelled/failed/too-short/partial-below/partial-above), gate zöld |
| A6 (lesson) | 3 cell (OFF/dual/newOnly), gate zöld |
| A7 (lesson) | 2 cell (happy path + §6.1 valódi-sértés), gate zöld |
| A2, A4, A8 | a korábbi §10 táblázatban már bizonyítva, a javító kör nem érintette |

#### Commands actually run (javító kör)

| Claim | Command run |
|---|---|
| A teljes §7 gate zöld (format / analyze / 3×test / architecture / secrets / l10n) | `tools/round-gate.sh test/features/gamification/integration/practice_reward_flow_test.dart test/core/architecture_dependency_test.dart test/features/learn` → minden fázis zöld (lásd lent a teljes kimenet) |
| A kibővített practice_reward_flow_test suite 25 teszttel fut | `flutter test test/features/gamification/integration/practice_reward_flow_test.dart` → `00:00 +25: All tests passed!` (12 practice + 13 lesson) |
| A `test/features/learn` suite zöld maradt | `flutter test test/features/learn` → `+201 ~1: All tests passed!` (megegyezik a javítás előtti számmal: A2/A8 VÁLTOZATLAN) |
| Az A4 architektúra-guard zöld | `flutter test test/core/architecture_dependency_test.dart` → `+32: All tests passed!` |

A kapu artefaktum teljes, csonkítatlan kimenete a javító kör session-naplójában
(`gate-e08-r24-fix1.log`) megtekinthető — a fenti táblázat minden sora egy-egy
futtatott parancs kimenetére hivatkozik, nem állításra.

#### Miért nem tér vissza az F1 hiba a jövőben (önellenőrzés a `done` előtt)

Az F1 regressziós teszt (a fenti `Lesson` csoport utolsó sora:
`F1 regression: same lessonId, two different attempts on different days
produce TWO distinct eventIds and TWO ledger entries`) KÖZVETLENÜL a régi
implementációra lett írva:

1. Két, KÜLÖNBÖZŐ `attemptId` (`'attempt-day1'`, `'attempt-day5'`).
2. Két, KÜLÖNBÖZŐ `epochDay` (`20400`, `20404`, 4 nap eltéréssel —
   megegyezik a review mért reprodukciójával).
3. UGYANAZ a `lessonId`.

A teszt három állítást tesz, mindhárom a régi kóddal pirosra váltana:

- `first.eventId != second.eventId` — a régi `stableEventId(lessonId)`-vel
  mindkét attempt ugyanazt az `'learn-lesson/lesson-blue-bird/v1'` eventId-t
  kapná.
- `ledger.length == 2` — a régi kóddal a második attempt az outbox-drainben
  a ledger `appendIfAbsent` dedupja miatt elnyelődne.
- `entries.every((e) => e.totalXp > 0)` — a második attempt XP-je a régi
  kódban sosem érne a ledgerbe.

A review ezt a saját izolált klónjában fogja újraellenőrizni.

#### Not in this fix round

- A scope a §4 allowed_paths-on belül maradt: csak a `lesson_adapter.dart`
  és a `practice_reward_flow_test.dart` módosult (a `dart format` post-hook
  egy további commitot hozott létre az import-alias javításáról).
- Nincs új `test/features/gamification/integration/lesson_reward_flow_test.dart`
  — a brief §4 listája nem tartalmazza, a javítás a meglévő fájl
  kiterjesztésével történt (a méret ~700 sor, de a teszt-szervezés
  ugyanazt a mintát követi).
- Nincs `lib/features/gamification/public.dart` módosítás — a javításhoz
  nem kellett új szimbólumot exportálni.

## 11. Review — a Claude tölti ki
