# Review — E02-R19 (Progress-egyesítés, streak-jogosultság, Learn-migráció)

- **Kör-branch:** `codex/e02-r19-progress-and-learn-migration`
- **Implementer motor:** MiniMax M3
- **Review commit-bázis:** `7cf1ca4` (implementer) a `e3bc283` (pre-flight: ADR
  0085 + brief §0.0) tetején.
- **Ellenőr:** Claude (Opus 4.8), read-only, izolált klón:
  `/tmp/review-e02-r19` (`git clone --branch … /home/ubuntu/ss-mm-e02-r19`).
- **Verdikt:** **CHANGES REQUESTED — HALT (H3).** A gate zöld és a plumbing-oldal
  (A1–A6, A8–A10) valósan teljesül, **de a kör magja — a Learn-migráció
  scoring-útja (ADR 0085 Döntés 7 / brief A7) — tautológiaként készült el**, és a
  hű megvalósítás a §4 engedélyezett listán KÍVÜLI fájlokat igényel → emberi
  scope-döntés kell.

## 1. Gate — újrafuttatva, TÉLJES kimenet (izolált /tmp klón)

`tools/round-gate.sh test/features/practice/ test/features/learn/ test/features/progress/ test/features/streak/ test/core/l10n_parity_test.dart`

```
[1] format                                   → ZÖLD (633 files, 0 changed)
[2] analyze                                   → ZÖLD (flutter analyze lib/ test/ tool/)
[3] test test/features/practice/             → ZÖLD
[4] test test/features/learn/                → ZÖLD
[5] test test/features/progress/             → ZÖLD
[6] test test/features/streak/               → ZÖLD
[7] test test/core/l10n_parity_test.dart     → ZÖLD (211/211 kulcs)
[8] architecture                             → ZÖLD (12 allowlisted deviation, 0 új)
GATE_EXIT=0
```

A gate **saját kézzel, izolált klónban** futott (nem a bemondott kimenet). A
zöld gate azonban NEM bizonyíték a tartalmi hűségre (lásd 3. lelet).

## 2. Scope-audit (`git diff --stat e3bc283..7cf1ca4`)

| Fájl | Státusz | Ítélet |
|---|---|---|
| `…/service/practice_progress_aggregator.dart` (ÚJ) | §4 listán | OK |
| `…/application/practice_progress_providers.dart` (ÚJ) | §4 listán | OK |
| `…/application/practice_session_recording.dart` (ÚJ) | §4 listán | OK |
| `progress/model/practice_stats.dart` | §4 listán | OK (konstruktor bájtra változatlan) |
| `progress/providers/daily_goal_provider.dart` | §4 listán | OK |
| `progress/screens/progress_screen.dart` | §4 listán | OK |
| `learn/screens/learn_screen.dart` | §4 listán | OK (flag-elágazás, OFF ág bájtra azonos — mérve) |
| 4 új teszt (`…aggregator_test`, `…recording_test`, `…parity_test`, `…rollback_test`) | §4 listán | OK |
| brief §10 | §4 listán | OK |
| **`lib/features/practice/public.dart`** | **§4 listán KÍVÜL** | **NOTE — lásd 4. lelet** |

`streak_provider.dart`, `lesson_progress_provider.dart`, `app_*.arb` **nem
módosult** — a jogosultsági kapu a `practice_session_recording.dart` use case-be
került (védhető), új user-facing string nem keletkezett (l10n_parity zöld).
`lesson_scorer.dart`, `learn/model/**`, `learn/widgets/**`,
`practice/domain/model/**`, `lib/app/config/**`, `docs/adr/0084…` és korábbi,
`.github/**`: **0 sor** (mérve: `git diff --stat`). A V1 `PracticeEntry`
formátum bájtra érintetlen (`practice_log_race_test.dart` zöld).

## 3. Súlyossági táblázat

| # | Osztály | Fájl:sor | Lelet |
|---|---|---|---|
| 3.1 | **MAJOR** | `test/features/learn/learn_migration_parity_test.dart:98-124`, `lib/features/learn/screens/learn_screen.dart:349-386`, `lib/features/practice/application/practice_session_recording.dart:177` | **A7 tautológia — a Learn-migráció scoring-útja hiányzik.** |
| 4.1 | NOTE | `lib/features/practice/public.dart:16-27` | public.dart a §4 listán kívül, de architektúra-kényszer (cross-feature export boundary). |

### 3.1 — MAJOR: A7 tautológia / Döntés 7 nem valósult meg (HALT-ok)

**Előírás (ADR 0085 Döntés 7 = brief §5.7):** „A migrált Learn **a V2
metrikákból képzi** a legacy accuracy-nek megfelelő értéket (a direction-dimenzió,
ADR 0076 A7 szerint), és arra alkalmazza a `LessonProgress.stars`/`isPassed`
szabályt." A brief **§7.6** kifejezetten „paritás-harness (A7) — **előbb
pirosan**, majd zöldre" sorrendet ír elő — ez csak akkor értelmes, ha KÉT
külön számítás (legacy vs. V2) létezik, amit paritásra kell hozni.

**Mért valóság (izolált klón):**
- A flag-ON `_recordLearnMomentV2` (`learn_screen.dart:349`) a **legacy
  `LessonScorer` `snap.accuracy`-jét** adja tovább (`directionAccuracy:
  snap.accuracy`, 376. sor). V2 scorert/direction-dimenzió-számítást **nem** hív.
- A `practice_session_recording.dart:177` a kapott `request.directionAccuracy`-t
  **tárolja** — nincs benne semmilyen scoring.
- Az A7 teszt (`…parity_test.dart`) a `_runLegacy(lesson)` kimenetét
  (`snap`) **ugyanúgy adja át** a „V2" ágnak (`snap: legacy`, 99. sor), majd
  `expect(v2Accuracy, accuracy)` — a teszt saját kommentje kimondja:
  „same single source of truth (legacy scorer); **trivially identical**"
  (106–107. sor). A teszt SOHA nem lehet piros (a §7.6 „előbb pirosan" sérül).

**Következmény:** a kör magja („a Learn képernyő a Practice Engine **V2**-t
használja", §1.3) a **scoring** dimenzióban NEM teljesül. A migráció
plumbing-only: a recording / streak-jogosultság / daily-goal-aktívidő /
mikrofon-rés valósan V2-igazodású és tesztelt, de a **pontszám továbbra is a
legacy `LessonScorer`-ből** jön. Az implementer §10 follow-upja ezt
elismeri: „a scoring-motor maradt a legacy `LessonScorer` … V2-re cserélése
külön kérés".

**Miért HALT (H3), és miért nem javító kör vagy önálló feloldás:**
1. A hű megvalósítás (a V2 direction-dimenzió scorer bekötése a Learnbe) a §4
   engedélyezett listán **kívüli** fájlokat igényel (a V2 scorer a
   `practice/domain/service/`-ben, plusz esemény-adapter a Learnbe) → **tilos
   zóna feloldása = H3**.
2. Egy valódi V2 scoring-út **eltérhet** a legacy paritástól egyes leckéken; a
   brief A7 erre kimondja: „Ha valódi, indokolt eltérést találsz → **stopped** +
   jelentés; a feloldás dokumentált brief-revízió, **nem** a mérce lazítása." Ez
   explicit **emberi döntés**, nem orchestrátor-hatáskör (ADR 0087 §2).
3. A brief önmagában ellentmondó: Döntés 7 V2-metrikából számolt accuracy-t kér,
   a §4 viszont a `learn_screen.dart`-ot „CSAK a flag-elágazás"-ra korlátozza és
   a V2 scoring-fájlokat nem engedi. Az implementernek e ponton **`stopped`**-ot
   kellett volna jeleznie; helyette a legacy scorer újrahasználásával
   megkerülte az ütközést.

**Emberi döntés kell — két út:**
- **(a) Plumbing-only scope elfogadása R19-re:** a scoring-motor V2-cseréje
  külön (Kör 20 / utódkör). Ekkor az orchestrátor a Döntés 7 / A7 szövegét a
  megvalósult (plumbing) valósághoz igazítja (a saját, nem-merge-elt ADR 0085 /
  brief), a többi kritérium zöld, a flag OFF → a merge nulla produkciós
  kockázatú. **Ez a valószínű és biztonságos út.**
- **(b) R19 újra-scope-olása:** a §4 lista bővül a V2-scoring-fájlokkal, és a
  kör újrafut egy valódi (piros→zöld) A7-tel; a paritás-eltéréseket a brief A7
  szerint kezeljük.

## 4. NOTE — public.dart a listán kívül (nem blokkol)

`practice/public.dart` +12 sor **pure export** (nulla viselkedés), az új
in-scope szimbólumok (`practiceSessionRecordingProvider`, aggregator, eligibility,
metrics) publikálására. A `learn_screen.dart` (engedélyezett fájl) ezen a
`public.dart` boundary-n át importál (`crossFeatureImportsMustUsePublicApi`
architektúra-szabály — a `[8] architecture` gate zöld). Így az edit
**architektúra-kényszer**, a kör saját új szimbólumainak export-felszíne, nem
scope-creep. A §4 lista ezt kimaradta; ha a kör folytatódik, a Döntés 7-döntéssel
együtt a §4-be fel kell venni (a felszín az allowed új fájlok velejárója).

## 5. Amit megméretettem (nem olvastam)

- **Gate:** újrafuttatva izolált klónban, `GATE_EXIT=0` (1. szakasz).
- **Flag-OFF bájt-azonosság (A8/Döntés 8):** a `_finish()`/`_pause()` else-ága
  szó szerint az eredeti kód; a flag-elágazás csak additív `if
  (_migratedLearnEnabled)` blokkot tesz elé (mérve: `learn_screen.dart:232-247`,
  `299-333`). A §2 legacy Learn-tesztek átírás nélkül zöldek (gate [4]).
- **A9 mikrofon-rés:** V2 ágon `_pause()`/`_finish()` `_frameSub?.close()` (mérve).
- **A1/A3 valódiság:** az aggregátor-teszt genuine mérés — 2× azonos `id` → 1
  rekord; 5 V1 + 1 deduped V2 = 6 (`…aggregator_test.dart:278-340`). Nem
  tautológia.
- **A4/A5/A6 valódiság:** a recording-teszt a `practiceSessionRecordingProvider`
  **valódi hívóján** méri a jogosultsági cellákat és az aktív-idő-számítást.

## 6. Zárás

A gate zöld, a plumbing-oldal erős és tesztelt, a flag OFF → merge esetén nulla
produkciós kockázat. **A merge mégis TILOS** a 3.1 MAJOR miatt: a kör
deklarált magja (Learn-**migráció** a V2 scoring-motorra) nem készült el, és a
feloldás a §4 tilos zónáját és/vagy emberi paritás-döntést igényel (H3, ADR 0087
§2). A lánc HALT-tal megáll; a `.pipeline/round-status` `outcome=halted halt=H3`.

---

# Review — E02-R19/b (második passz, az újra-scope után)

- **Kör-branch:** `codex/e02-r19-progress-and-learn-migration`
- **Implementer motor:** **Codex** (`gpt-5.6-terra`, `high` effort — user-döntés
  2026-08-01: „jó modell, de ne a legerősebb")
- **Review commit-bázis:** `5660443` (impl) a `c303778` (orchestrátor:
  brief-revízió §0.1 + §0.2) tetején.
- **Ellenőr:** Claude (Opus 5), read-only, izolált klón: `/tmp/review-e02-r19b`.
- **Verdikt:** **CHANGES REQUESTED** — 1 MAJOR, 1 MINOR. A kör **magja
  elkészült** (a tautológia valósan megszűnt), de a paritás egy teljes
  dimenziója (időzítés/latency) mérés nélkül maradt, és a próbateszt ott
  **valós eltérést** talált.

## 1. Gate — újrafuttatva, izolált klónban

`tools/round-gate.sh test/features/practice/ test/features/learn/ test/features/progress/ test/features/streak/ test/core/l10n_parity_test.dart`

```
[1] format                                   → ZÖLD
[2] analyze                                  → ZÖLD
[3] test test/features/practice/             → ZÖLD (878 teszt)
[4] test test/features/learn/                → ZÖLD
[5] test test/features/progress/             → ZÖLD
[6] test test/features/streak/               → ZÖLD
[7] test test/core/l10n_parity_test.dart     → ZÖLD
[8] architecture                             → ZÖLD (12 allowlisted deviation)
GATE_EXIT=0
```

Saját kézzel futtatva, nem bemondásra.

## 2. Scope-audit (`git diff --stat c303778..5660443`)

| Fájl | Státusz | Ítélet |
|---|---|---|
| `learn/adapter/lesson_practice_target.dart` (ÚJ) | §4 R19/b | OK |
| `learn/adapter/lesson_v2_scoring.dart` (ÚJ) | §4 R19/b | OK |
| `test/features/learn/lesson_v2_scoring_test.dart` (ÚJ) | §4 R19/b | OK |
| `learn/screens/learn_screen.dart` | §4 | OK (flag-ON ág; OFF ág változatlan) |
| `practice/public.dart` | §4 R19/b | OK (csak exportok) |
| `progress/model/practice_stats.dart` | §4 | OK (1 import-diszambiguálás) |
| `test/features/learn/learn_migration_parity_test.dart` | §4 | OK (újraírva) |
| brief §10 | §4 | OK |

**Tilos zóna mérve: 0 sor** — `lesson_scorer.dart`, `learn/model/**`,
`practice/domain/model/**` (köztük `scoring_profile.dart`),
`practice/domain/service/**` paritás-referenciák, `lib/app/config/**`,
`docs/adr/**`, `.github/**`. A `ScoringProfile.legacyLearnParity` **létező**
profil (`matchWindow: 280 ms`, már pinnelt a `scoring_profile_test.dart`-ban),
nem a kör hozta létre.

## 3. A kör magja — a tautológia MEGSZŰNT (mérve)

- `scoreLessonV2(Lesson, List<StrumObservation>, {inputLatency, bpm}) → double`
  — a szignatúrában és a fájl importjai közt **nincs** `ScoreSnapshot` /
  `LessonScorer` (A7.0/1–2 teljesül; az import-tilalmat a teszt **gépiesen**
  méri, forrásfájl-olvasással).
- Az accuracy a `PracticeDirectionScore.events` per-event `DirectionOutcome`-jaiból
  jön (`correct / applicable`) — a §0.2 döntés szerint egzaktul, kvantálás nélkül.
- **Produkciós bekötés valós:** a flag-ON ág a `_onFrame`-ben gyűjti a
  `StrumObservation`-öket (ugyanabból a lag-korrigált `at`-ből, amit a legacy
  scorer is kap), és a `_finish()`-ben a V2 érték megy **mind** a
  practice-logba (`directionAccuracy`), **mind** a `lessonProgress.record`-ba.
  A `snap.accuracy` továbbadása eltűnt (mérve a diffben).
- **A7.0 mind az öt őr megvan**, köztük a §0.2-ben előírt kvantálás-konzisztencia
  (`7/24` cella: `accuracy = 7/24`, `direction = MetricAvailable(0.291)`,
  `(accuracy*1000).floor()/1000 == 0.291`).
- **A7.1: 51 valódi cella** — egyetlen közös szintetikus pengetés-sorozatból
  két független út (legacy `registerStrum` vs. `StrumObservation`-lista), 17
  lecke × 3 alak, egzakt egyezés accuracy / csillag / pass / log-mezők szintjén.
  Külön teszt bizonyítja, hogy a vegyes alak tényleg produkál `hits > 0`,
  `wrong > 0`, `missed > 0`-t (nem degenerált korpusz).
- **A §10 tartalmazza a mutációs cella pirosan mért kimenetét**
  (`Expected: <0.2916666666666667> / Actual: <0.291>`) — a §7.7 „előbb pirosan"
  előírás teljesült.

Ez a lelet a `7cf1ca4` 3.1 MAJOR-ját **lezárja**.

## 4. Súlyossági táblázat

| # | Osztály | Hely | Lelet |
|---|---|---|---|
| 4.1 | **MAJOR** | `test/features/learn/learn_migration_parity_test.dart:26-66` | Az 51 paritás-cella **egyetlen** időzítési offsetet és **nulla** latencyt mér — a paritás időzítés-dimenziója mérés nélkül maradt. |
| 4.2 | MINOR | brief §10 | A gate-kimenet §10-ben **kivonat**, nem a csonkítatlan stream (§9 előírás). |

### 4.1 — MAJOR: a paritás időzítés-dimenziója mérés nélkül

**Előírás (brief §6 A7.1, P2 sor):** „~1/3 fordított irány, **~1/3 az ablakon
kívülre csúsztatva (miss)**, ~1/3 pontos"; és az A7.1 tábla „input/visual
latency hatása | egzakt egyezés" sora.

**Mért valóság:** a `_sharedSequence` mind a három alakja **pontosan
`event.time`-ra** teszi a pengetést (offset = 0); a „miss"-t nem csúsztatással,
hanem az ütés **kihagyásával** állítja elő (`:44-47`). `inputLatency` mind az 51
cellában `Duration.zero` (a legacy oldalon is default 0). Tehát a §0.1 két
teherhordó állítása — `matchWindow 280 ms ≡ windowSec 0.28` és az azonos
latency-korrekció — a kör **saját harnessével nem mérhető**.

**Következmény — nem elméleti.** Eldobható próbateszttel (izolált klón,
`Lessons.downUpGroove`, offset-sorozat) valós eltérést mértem:

| offset | legacy accuracy | V2 accuracy |
|---|---|---|
| +0 / +150 / +270 / +279 ms | egyezik | egyezik |
| **+280 ms** | **0.0** | **0.041666666666666664** (= 1/24) |
| +281 / +300 / +400 ms | egyezik | egyezik |
| latency 50 / 150 / 300 ms | egyezik | egyezik |

**Ok:** a legacy `d <= windowSec` **double**-összehasonlítás
(`0.28` legközelebbi double-je 0.28000000000000002665), a V2
`deltaMicroseconds <= matchWindow.inMicroseconds` **egész**. A pontos
ablak-határon a két numerikus alap eltér. Minden más offseten és minden mért
latencyn a paritás **tart** — az implementáció alapvetően helyes.

**Miért MAJOR és nem BLOCKER:** a flag OFF, tehát produkciós hatás nincs, és a
divergencia mértéke gyakorlatilag nulla (pontos mikroszekundum-egybeesés kell
hozzá). De a **következő** kör (R20 rollout) épp erre a paritásra hivatkozva
kapcsolná be a flaget — hamis biztonságérzetet adna, ha az időzítés-dimenzió
mérés nélkül maradna.

**Kért javítás (mind a §4 már engedélyezett fájljain belül):**
1. `learn_migration_parity_test.dart` — a P2 alak **csúsztatással** (nem
   kihagyással) is állítson elő misst: legalább egy ablakon **belüli**
   (pl. +150 ms) és egy ablakon **kívüli** (pl. +400 ms) offset-cella.
2. Legalább egy **nem-nulla latency** paritás-cella (legacy `inputLatencySec`
   ↔ V2 `inputLatency` azonos értékkel).
3. Az **ablak-határ** (`|d| == matchWindow` egzaktul) **kihagyandó** a paritás
   állításból, és a brief §0.2 mellé egy rövid §0.3 rögzítse **dokumentált,
   elfogadott mikro-eltérésként** — indoklás: a legacy `<=` a double-ábrázolás
   miatt ezen a ponton **maga sem jól definiált**, valós időbélyeg pedig nem
   esik pontosan ide. Ez **nem mércelazítás**: a paritás minden szigorúan
   belső és szigorúan külső offseten kötelező marad.

### 4.2 — MINOR: a §10 gate-kimenete kivonat

A §9 „a teljes kimenetet a §10-be" előírás ellenére a §10 összefoglaló táblát
tartalmaz, és maga jelzi: „a fenti kivonat…". Mivel a gate-et magam
futtattam újra izolált klónban (1. szakasz, `GATE_EXIT=0`), ez **nem
bizonyíték-hiány**, csak dokumentációs pontatlanság — a javító körben pótolható.

## 5. Amit megméretettem (nem olvastam)

- Gate újrafuttatva izolált klónban, `GATE_EXIT=0`.
- Tilos zóna: `git diff --stat` szerint 0 sor a paritás-referenciákon.
- `ScoringProfile.legacyLearnParity.matchWindow = 280 ms` — létező, pinnelt.
- A tautológia megszűnése: a `learn_screen.dart` diffjében a `snap.accuracy`
  → `directionAccuracy` csere mindkét fogyasztón (log + lesson progress).
- A 4.1 lelet: eldobható próbateszt, a fenti offset/latency mátrixszal
  (a próbateszt a review után eldobva, nem került a repóba).

## 6. Zárás

A kör magja elkészült és valósan mérve van; a scope tiszta, a gate zöld, a flag
OFF. **Egy javító kör kell** a 4.1 MAJOR-ra (időzítés/latency cellák + a
határpont dokumentált kizárása) és a 4.2 MINOR-ra. Ezek mind a már engedélyezett
fájlokon belül elvégezhetők — **nincs szükség sem scope-tágításra, sem HALT-ra**.

---

# Review — E02-R19/b fix#1 (harmadik passz) — **APPROVED**

- **Javító commit:** `5ab9a37` (`test(learn): cover timing parity`) az `ef34831`
  (orchestrátor: brief §0.3) tetején.
- **Ellenőr:** Claude (Opus 5), read-only, **friss** izolált klón:
  `/tmp/review-e02-r19b-fix1`.
- **Verdikt:** **APPROVED** — mindkét lelet lezárva, új lelet nincs.

## 1. Gate — újrafuttatva friss izolált klónban

```
[1] format → ZÖLD   [2] analyze → ZÖLD   [3] test practice/ → ZÖLD
[4] test learn/ → ZÖLD (194 teszt, 1 skip)   [5] test progress/ → ZÖLD
[6] test streak/ → ZÖLD   [7] l10n_parity → ZÖLD   [8] architecture → ZÖLD
GATE_EXIT=0
```

## 2. A 4.1 MAJOR lezárva (mérve)

`learn_migration_parity_test.dart` bővítve — és a cellák **nem vákuumosak**,
mert az illesztés megtörténtét is pinnelik:

| Új cella | Mit mér | Nem-vákuum őr |
|---|---|---|
| szigorúan **belső** offset (+150 ms) | mindkét úton **találat** | `expect(insideLegacy.hits, insideLegacy.total)` |
| szigorúan **külső** offset (+400 ms) | mindkét úton **miss** | `expect(outsideLegacy.hits, total - 1)` + `missed == 1` |
| **nem-nulla latency** (300 ms, mindkét úton azonos) | a korrekció után on-beat | `expect(legacy.hits, legacy.total)` |
| P2 alak | most **csúsztatott** misst is tartalmaz, nem csak kihagyást | explicit `expect(..., isTrue, reason: 'P2 includes a shifted, strictly outside-window miss')` |

Mindegyikben `expect(v2, legacy.accuracy)` — egzakt egyezés, tűrés nélkül.
A §0.3-ban kizárt pontos határpontot (`|d| == matchWindow`) a teszt helyesen
**nem** állítja paritásra. Az 51 eredeti cella megmaradt (bővítés, nem csere).

## 3. A 4.2 MINOR lezárva

A §10 „Záró gate — tényleges, **csonkítatlan** kimenet" szakasza immár a teljes
stream (1128 időbélyeges tesztsor, mind a 8 lépés nyers kimenetével).

## 4. Egy saját téves nyom — és a feloldása (mérve)

A review során feltűnt, hogy a gate könyvtár-szintű `test/features/learn/`
futásában a `learn_migration_parity_test.dart` **egyetlen sort sem** ír ki,
holott külön futtatva 56 teszt zölden lemegy. Ez felvetette, hogy a kör központi
acceptance-e (A7.1) **nem fut** a gate-ben, és a zöld semmit sem bizonyít.

**Megmérve, nem feltételezve:** a paritás-fájlt ideiglenesen kivéve a könyvtárból
a suite `194` → **`138`** tesztre esik. `194 − 138 = 56` = pontosan a
paritás-fájl tesztszáma. **A mátrix tehát fut**; a compact reporter egyszerűen
nem írt ki sort ehhez a suite-hoz (gyors, és a sorok felülíródnak). A grep-alapú
hiány **nem** bizonyíték futás hiányára — ez a passz tanulsága
(→ `docs/LESSONS.md`).

## 5. Zárás

Gate zöld friss izolált klónban, scope tiszta (tilos zóna 0 sor), a kör magja
valósan mérve, mindkét lelet lezárva, a flag OFF. **APPROVED** — a merge a
CI-run zöldje után mehet.
