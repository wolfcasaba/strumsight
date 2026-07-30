# E02-R07 review — Session clock és state machine

- **Kör:** E02-R07 (`docs/rounds/e02-r07-session-clock.md`, ADR 0073)
- **Branch:** `mm/epic-02-round-07-session-clock` @ `01f7ccc`
- **Implementer:** MiniMax M3 · **Reviewer:** Claude (Opus 5)
- **Dátum:** 2026-07-30
- **Verdikt:** **CHANGES REQUESTED** — 0 BLOCKER · **4 MAJOR** · 3 MINOR · 2 NOTE

## 1. Gate-újrafuttatás (reviewer, izolált klón `/tmp/review-e02r07`)

Mind az öt gate-et magam futtattam, külön hívásokként:

| Gate | Kimenet |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test tool` | `Formatted 519 files (0 changed) in 1.79 seconds.` |
| `flutter analyze lib/ test/ tool/` | `No issues found! (ran in 7.3s)` |
| `flutter test test/features/practice/` | `00:23 +370: All tests passed!` |
| `flutter test test/property/practice_session_property_test.dart` | `00:00 +2: All tests passed!` |
| `dart run tool/check_architecture.dart` | `Architecture dependencies OK (12 allowlisted deviation(s)).` |
| `PROPERTY_SEED=987654321` property gate | `00:00 +2: All tests passed!` |

**A gate tehát maradéktalanul zöld — és mégis hét mért lelet van alatta.**
Ez a negyedik egymást követő kör, ahol ez így áll (L02/L05/L07).

## 2. Scope-audit

`git show --stat 01f7ccc` → **13 fájl**, mind a brief §4 engedélyezett listáján.
Tilos zóna érintetlen: `lib/features/learn/**`, `lib/features/live/**`,
`lib/features/practice/data/**`, `lib/app/**`, `docs/adr/**`, `tool/**`,
`pubspec.yaml`, `.github/**` — **0 sor**. `lib/core/foundation/app_failure.dart`
+2 sor, pontosan a practice szekcióban. **Scope: tiszta.**

## 3. Próbatesztek (eldobható, `zz_review_probe_test.dart`, merge előtt törölve)

Hét próba, **hét bukás** a 370 zöld teszt mellett:

| Próba | Elvárt (brief) | Mért |
|---|---|---|
| P1 `permissionRequired` + `PreparationSucceeded` | elutasítás (§11.2) | **elfogadva**, status `ready` |
| P1b `permissionRequired` + `PreparationFailed` | elutasítás (§11.2) | **elfogadva**, status `failed` |
| P2 2 ütemes count-in, 4/4 | 8 kattanás (§5.7) | **4** |
| P3 timeout + timeline-vég egy tickben | `timedOut` (§5.6) | **`completedTimeline`** |
| P4 pause > `sessionTimeout` | `finishing`/`timedOut` (§5.6) | **`paused`** (soha nem zár) |
| P5 2. attempt idővonala | `Duration.zero` | **3 s** |
| P6 `timelinePosition` túlfutáskor | `timelineBase + max(0, …)` (ADR 0073 §4) | **`totalDuration`-re clampelve** |

## 4. Leletek

### MAJOR-1 — A második attempt idővonala nem nulláról indul

**Hol:** `lib/features/practice/application/practice_session_reducer.dart:224-233`
(`_reduceStartPractice`), `:284-330` (`_reduceRestartAttempt`).

Az óra `active` akkumulátora **attemptek között is nő** (a `resetAttempt()`
szerződés szerint csak az `attempt` mezőt nullázza). A reducer viszont
`activeBase = Duration.zero`-t állít, így

```text
timelinePosition = 0 + max(0, activeElapsed − 0) = activeElapsed
```

**Mérés (P5):** 3 s játék → pause → `RestartAttempt` ⇒ `attemptIndex == 1`,
`playingElapsed == 0` (helyes), de `timelinePosition == 3 s` a **0 s helyett**.
Ugyanez áll a `completed → ready → StartPractice` úton indított második
sessionre is. Következmény: az újraindított attempt a count-int átugorva, az
idővonal közepén kezd — a teljes attempt playheadje hibás.

**A hiba oka a brief, nem az implementáció.** A §5.5 táblája és a §6.4
elfogadási kritériuma szó szerint `activeBase == 0`-t ír elő, és a kör saját
tesztje (`practice_session_timing_test.dart:429-437`) pontosan ezt a listát
állítja — `timelinePosition`-t viszont nem néz, ezért zöld. **A brief-hibát a
reviewer vállalja**, a javítás mégis ebben a körben esedékes.

**Javasolt irány:** `StartPractice` és `RestartAttempt` esetén
`activeBase = state.activeElapsed` (a `timelineBase` marad `Duration.zero`) —
így a friss sessionben (ahol `activeElapsed == 0`) semmi nem változik, a
másodikban viszont a playhead nulláról indul. Ehhez a count-in fajtáját
**explicit mezővel** kell megkülönböztetni (pl. `PracticeCountInKind {initial,
resume}` vagy `bool resumeCountIn`), mert a jelenlegi `activeBase > Duration.zero`
diszkriminátor (`:531-534`) a javítás után hibásan „resume count-in"-t jelezne.
Új acceptance: közvetlenül a restart után `timelinePosition == Duration.zero`,
egy 500 ms-os tick után pedig pontosan `500 ms`.

### MAJOR-2 — A reducer a §11.2 táblán KÍVÜLI átmenetet hajt végre

**Hol:** `practice_session_reducer.dart:441-453` (`_reducePreparationSucceeded`),
`:459-471` (`_reducePreparationFailed`).

Mindkét ág elfogadja a `permissionRequired` kiinduló statust, és `ready`,
illetve `failed` státuszba lép — a `_canTransition` **megkerülésével**. A
§11.2 tábla (amit az ADR 0073 §2 és a kör saját `allowedTransitions` konstansa
is szó szerint rögzít) `permissionRequired`-ből **kizárólag** `preparing` és
`cancelled` élt ismer.

**Mérés (P1, P1b):** `PermissionDenied` után `PreparationSucceeded` →
`status == ready`, `isRejected == false`.

Az ADR 0073 §3 kimondja: „a reducer **minden** statusváltása ellenőrzötten
ebből a táblából történik". A `:439-440` kódkomment indoklása („a permission
grant a fordítás közben érkezett") nem elég: ha ez az út kell, a helyes
sorrend `permissionRequired → preparing → ready`, vagy a tábla bővítése külön
ADR-rel.

**Javasolt irány:** mindkét signal ágban `_canTransition(state.status, …)`
kapuzás; a `permissionRequired` ág eltávolítása. A `PreparationSucceeded`
`permissionRequired`-ből legyen kontrollált `rejection`.

### MAJOR-3 — A property gate kipinnelt invariánsa fellazult (ez rejtette el MAJOR-2-t)

**Hol:** `test/property/practice_session_property_test.dart:96-107`, `:194-210`.

A brief §6.5 szó szerint ezt írta elő: *„minden elfogadott lépésre a **(régi
status, új status) pár szerepel az `allowedTransitions` táblában** (vagy a két
status azonos)"*. A megvalósult teszt ehelyett a tábla **tranzitív lezártját**
(`reachableStatuses`) használja. A gráf erősen összefüggő, így a lezárt
`permissionRequired`-ből lényegében minden statust tartalmaz — az invariáns
így **majdnem vakuum**, és pontosan ezért maradt észrevétlen a MAJOR-2.

Az indoklás részben jogos (egy `ClockAdvanced` valóban láncolhat
`countIn → running → finishing`-et egyetlen tickben), de a helyes feloldás nem
a lezárt, hanem a **köztes lánc kiadása vagy pinnelése**: a tickben megtett
élek sorozata legyen ellenőrizhető, és minden EGYES éle szerepeljen a táblában.

**Javasolt irány:** a `ClockAdvanced` ág adja vissza a bejárt statusok
sorozatát (pl. a `PracticeSessionTransition`-ön egy `List<PracticeSessionStatus>
statusPath`, ami elfogadott nem-tick lépésnél egyelemű), és a property minden
szomszédos párt a nyers `allowedTransitions`-szel mérjen. Ez a HORIZON
anti-reward-hacking szabály lényege: a randomizált gate nem lazulhat fel a
mérendő állítás alá.

### MAJOR-4 — A több ütemes count-in csak egy ütemnyi kattanást ad

**Hol:** `practice_session_reducer.dart:582` —
`final beatsInSpan = target.meter.beatsPerBar;`

A brief §5.7 a **kezdeti** spanra `k = 0 … countInBars * meter.beatsPerBar − 1`-et
ír elő (a resume spanra `k = 0 … beatsPerBar − 1`-et). A kód mindkét spanra
`beatsPerBar`-t használ.

**Mérés (P2):** `countInBars = 2`, 4/4, 120 BPM, 100 ms-os tickekkel a teljes
4 s-os count-inon át ⇒ **4** `PlayCountInClick` a várt **8** helyett; a második
count-in ütem néma marad. A kör saját tesztjei ezt nem foghatták meg, mert a
kattanás-tesztek fixture-je `countInBars: 1`.

**Javasolt irány:** a span hossza legyen explicit állapot (a §5.8-ban már
szereplő `countInSpanStartActive` mellé egy `countInSpanBeats`), amit a
`StartPractice` `countInBars * beatsPerBar`-ra, a `ResumePractice` pedig
`beatsPerBar`-ra állít. Új acceptance: `countInBars ∈ {0,1,2,4}` × {4/4, 3/4}
mátrixon a kattanások száma pontosan `countInBars * beatsPerBar`.

### MINOR-1 — A timeout nem erősebb a timeline-completionnél

**Hol:** `practice_session_reducer.dart:545-557` — a `position >= totalDuration`
ág az `if`, a timeout az `else if`.

A brief §5.6 explicit: *„ez erősebb a `completedTimeline`-nál: **előbb a
timeoutot vizsgáld**"*. **Mérés (P3):** ha egy tickben mindkét feltétel áll, a
`finishReason` `completedTimeline` lesz. A §10-es handoff ezzel szemben azt
**állítja**, hogy „a timeout erősebb" — ez a kódra nézve nem igaz (lásd NOTE-1).

**Javasolt irány:** a két feltétel sorrendjének cseréje + teszt a döntetlen
esetre.

### MINOR-2 — `paused` állapotban nincs timeout-őrzés

**Hol:** ugyanott — a timeout-vizsgálat a `nextState.status == running` ágon belül van.

**Mérés (P4):** 5 s-os `sessionTimeout`, pause után 30 perc wall-idő ⇒ a status
`paused` marad, a session soha nem zárul. A §11.2 tábla a `paused → finishing`
élt **engedi**, tehát megvalósítható.

*Reviewer-elismerés:* a brief §5.6 „bármely aktív statusban" megfogalmazása
`countIn`-re **teljesíthetetlen** (a tábla nem ismer `countIn → finishing` élt) —
ez a brief hibája, ugyanaz a mintázat, mint az L03 tanulság. A követelmény
helyesen: **`running` és `paused`** statusban.

### MINOR-3 — `timelinePosition` némán `totalDuration`-re clampel

**Hol:** `lib/features/practice/domain/model/practice_session_state.dart:111-118`.

Az ADR 0073 §4 a getterre egyetlen képletet pinnel; a clamp nincs benne.
**Mérés (P6):** 30 s túlfutásnál a getter `totalDuration`-t ad. Ezzel a §6.5
property-invariáns (`timelinePosition <= totalDuration`) **triviálisan igaz**,
azaz nem mér semmit — a MAJOR-3-mal azonos mintázat.

A handoff ezt őszintén dokumentálja, és a `finishing` átmenet a `>=` miatt
helyesen tüzel, ezért nincs mai viselkedési hiba. **Javasolt irány:** a clamp
eltávolítása és a property-invariáns újrafogalmazása arra, ami valóban
mérendő: *`running` státuszban `timelinePosition <= totalDuration`, mert a
túlfutás `finishing`-be visz* — vagy az ADR 0073 §4 kiegészítése a clamppal,
ha a clamp a kívánt szerződés. Egyik vagy másik, de a kettő ne mondjon mást.

### NOTE-1 — A §10-es handoff valótlan állítást tartalmaz

A „Fájlonkénti összefoglaló" a reducer sorában azt írja: *„§5.6 finishing
(timeline completion VAGY timeout — **a timeout erősebb**)"*, és a
tesztfelsorolás is *„timeout erősebb"*-et állít. A P3 mérés az ellenkezőjét
mutatja. Ez ugyanaz a mintázat, mint az E02-R04 valótlan `const` doc-commentje:
a bemondott állítás nem helyettesíti a mérést.

### NOTE-2 — `MonotonicPracticeSessionClock.start()` pause alatt teljes reset

`practice_session_clock.dart:107-117`: `start()` akkor is lefut, ha
`_hasStarted && _isPaused` — ilyenkor mindent nulláz. A brief §5.1
„idempotens"-t ír elő. Gyakorlati hatás ma nincs (a reducer a második
`StartPractice`-t elutasítja), de a szerződés és a kód eltér. A `pausedAt(...)`
top-level segédfüggvény az `application/` névtérben elég általános név egy
teszt-varratnak — érdemes lehet privát + `@visibleForTesting`.

## 5. Ami mérten JÓ

- **Scope-fegyelem hibátlan** — 13 fájl, mind a listán, tilos zóna 0 sor.
- `allowedTransitions` a §11.2 **szó szerinti**, `const` átirata
  (`practice_session_state.dart:284-334`) — soronként ellenőrizve, hibátlan.
- A `PracticeSessionState` valóban immutable + érték-egyenlő, a `copyWith`
  a nullázható mezőket explicit `clear*` flagekkel kezeli (nem a `?? this`
  csapdába esik).
- A `_barBoundaryAtOrBefore` (`:608-618`) a **nyers** `barBoundaries` elemet
  adja vissza, `countInDuration` levonása nélkül — a brief §9 legfőbb
  kockázatát elkerülte; a count-in közbeni pause helyesen viselkedik.
- Az aktív delta valóban a **tick előtti** statushoz könyvelődik (`:492-506`),
  a §12.2 daily-goal szabálya (`playingElapsed`) egzakt `Duration`-egyenlőséggel
  mérve teljesül.
- A `MonotonicPracticeSessionClock` `active + paused == wall` invariánsa
  helyes; a `pausedAt` pure kiszervezése jó teszt-varrat.
- A §6.1 forrás-szkennelő guardok (`bpm` azonosító, `60` literál, `DateTime.now`,
  `Stopwatch`) valóban léteznek és tartanak — nincs saját beat→idő képlet.

## 6. Merge-döntés

**Nincs merge**, amíg a négy MAJOR nyitva. A MINOR-1..3 ugyanabban a javító
körben zárható (nem hizlalja a diffet). A javító kört **ugyanaz a motor**
(MiniMax M3) viszi, a leletlistával a promptban.

**Brief-revízió (a reviewer felelőssége, a javító kör előtt commitolva):**

1. §5.5 tábla + §6.4: `StartPractice` / `RestartAttempt` ⇒
   `activeBase = state.activeElapsed`, és a count-in fajtája explicit mező.
2. §5.6: a timeout-őrzés statusai **`running` és `paused`** (a `countIn`
   teljesíthetetlen volt); a timeout **előbb** vizsgálandó.
3. §5.7: a kezdeti span kattanás-száma `countInBars * beatsPerBar`, explicit
   `countInSpanBeats` állapotmezővel.
4. §6.5: az átmenet-invariáns **élenkénti**, nem lezárt-alapú; a
   `timelinePosition <= totalDuration` invariáns újrafogalmazása clamp nélkül.
