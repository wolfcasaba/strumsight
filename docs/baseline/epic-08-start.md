# Epic 8 — Gamification mért kiindulópont

- **Kör:** E08-R01 (Chapter 9, Kör 1)
- **Dátum:** 2026-08-19
- **Mért alap-commit:** `b5317fd52b41aeb10839f9a90c971155f3b35632` (`minimax/e08-r01-gamification-baseline-and-principles`)
- **Szerződés:** [ADR 0328](../adr/0328-measured-gamification-baseline-contract.md)
- **Termékelvek forrása:** [ADR 0289](../adr/0289-mastery-is-evidence-not-xp.md),
  [ADR 0290](../adr/0290-compassionate-streaks-and-idempotent-claims.md)

> Ez a dokumentum NEM normatív. A jutalom- és széria-szabályok elsőbbségi
> forrása továbbra is a 0289 és a 0290. A baseline kizárólag a Kör 8–10
> migrációk kiindulópontja: tároló-kulcsok, JSON-alakok, küszöb-számok,
> feature-függőségek és meglévő teszt-guardok mért leltára, hogy a későbbi
> körök ne találgassanak és ne okozzanak néma adatvesztést.
>
> Minden tényállítás fájl- és sorszám-hivatkozással. A dokumentáció
> (CLAUDE.md, `docs/sdd/`) és a kód eltérése esetén a kód a mérvadó.

---

## 1. Érintett feature-fák és függőségi térkép

### 1.1 Fák (mért)

| Feature | Forrás-fák | Teszt-fák | Sor (összes) |
|---|---|---|---|
| `lib/features/streak/` | 8 db | 5 db | forrás: 700 · teszt: 328 |
| `lib/features/progress/` | 8 db | 5 db | forrás: 1028 · teszt: 419 |
| `lib/features/learn/` | 24 db | 34 db | forrás: 3732 · teszt: 3624 |
| `lib/features/share/` | **9 db** | 7 db | forrás: 1397 · teszt: 809 |
| `lib/features/gamification/` | **nem létezik** — e körben hozandó létre (Kör 2) | — | — |

A `lib/features/share/` kilenc forrás-fájlját a `find lib/features/share
-type f -name '*.dart'` listázza:

- `lib/features/share/public.dart` (13 sor) — a feature barrel: a 4–13.
  sorokban exportálja a `weekly_recap`-ot, a `share_content`-et, a
  `share_service`-t, és a két preview képernyőt (`share_preview_screen.dart`,
  `wrapped_preview_screen.dart`).
- `lib/features/share/share_service.dart` (133 sor) — a `ShareService` osztály
  a 15. sorban; a `capturePng` (20–33.), `shareCard` (37–48.), `shareImage`
  (53–80.), `shareText` (83–95.) és `shareExportFile` (112–132.) metódusokkal.
  Ezek a `share_plus` csomagra épülnek (`share_service.dart:7`), és a teljes
  platform-share életciklust birtokolják (beleértve az ADR 0247 szerinti
  öntörlő temp-file kontraktust is).
- `lib/features/share/share_content.dart` (136 sor) — a `ShareContent` (caption
  + fájlnév) és a `WeeklyRecap` gyártása.
- `lib/features/share/model/weekly_recap.dart` (82 sor) — a `WeeklyRecap`
  immutable adatszerkezete.
- `lib/features/share/screens/{share_preview_screen,strum_reel_screen,wrapped_preview_screen}.dart`
  — három navigálható preview képernyő (összesen 599 sor).
- `lib/features/share/widgets/{strum_card,wrapped_card}.dart` — a két
  megosztható kártya widget (összesen 434 sor).

A forrás-sorok ellenőrizve `wc -l` alapján (lásd §10 handoff, `find ...
-name '*.dart' | xargs wc -l`). A `lib/features/learn/` és a
`test/features/learn/` pontos száma az Explore-ágens mérése: 24 + 34,
összesen 3732 + 3624 sor.

### 1.2 Cross-feature import-térkép (RAG chunk 002 — feature határok)

A feature-ek csak `public.dart` barrel-en vagy közös core modellen át
érintkeznek (AGENTS.md §6). A gamifikáció szempontjából mérvadó élek:

| Él | Fogyaszt | Forrás | Megjegyzés |
|---|---|---|---|
| Progress ⇄ Streak | `lib/features/progress/screens/progress_screen.dart:8,30` | `import '../../streak/public.dart';` + `StreakLogic.epochDayOf(...)` | a napi gyakorlás-szám és a streak ugyanazt az epoch-napot használja |
| Learn ⇄ Streak | `lib/features/learn/model/lesson.dart:7`, `lib/features/learn/screens/learn_screen.dart:18`, `lib/features/learn/screens/lesson_list_screen.dart:9` | `import '../../streak/public.dart';` | a Learn a Streak `public.dart`-ból a `streak_logic.dart` és `daily_challenge.dart` típusait olvassa (export: `streak/public.dart:5–6`) |
| Learn � Progress | `lib/features/learn/screens/learn_screen.dart:12` | `import '../../progress/public.dart';` | a `PracticeEntry` / `PracticeStats` típusok a progress `public.dart`-ból jönnek (export: `progress/public.dart:5–6`) |
| Learn ⇄ Share | `lib/features/learn/screens/lesson_score_preview_screen.dart:4,20` | `import '../../share/public.dart';` + `ShareService` (alapértelmezett konstruktorparaméter) | a lesson-score preview képernyő a `ShareService`-t a share `public.dart`-ból használja (`share/public.dart:9`) |
| Progress ⇄ Practice (sibling) | `lib/features/progress/model/practice_stats.dart:4` | `import '../../practice/public.dart' hide PracticeSource;` | a V2 aggregátor a Practice feature-en át érhető el |
| Streak provider | `lib/features/streak/providers/streak_provider.dart:3–5` | `import '../streak_logic.dart';` (és NEM a progress publikus contractot) | a streak provider kizárólag a saját feature-én belülről olvassa a logikát; a `progress_screen` az egyetlen fogyasztó, amely a Streak `epochDayOf`-ját használja |

A `lib/features/gamification/` Kör 2-ben létrehozandó feature a fenti négy
feature (streak, progress, learn, share) felett ül, és kizárólag a
`public.dart` barrel-eken át éri el azokat — ez a 0289 §2 (auditálható
bizonyíték) és a 0290 §3 (nincs optimista jóváírás) betartásának
előfeltétele.

---

## 2. Tároló-kulcsok — gamifikáció (aktuális + legacy + wire-alak)

A `lib/core/storage/storage_keys.dart` a mérvadó. A kulcsok teljes
gamifikáció-érintett része:

### 2.1 Aktuális kulcsok (`StorageKeys`)

| Sor | Konstans | Sztring-érték | Funkció |
|---|---|---|---|
| 33 | `lessonProgress` | `ss.learn.lesson_progress` | learn csillag-bemenet (lesson → best accuracy) |
| 34 | `metronomeMuted` | `ss.learn.metronome_muted` | tanulási session-preferencia (booleán) |
| 35 | `practiceSpeed` | `ss.learn.practice_speed` | tanulási BPM (int) |
| 43 | `practiceLog` | `ss.progress.practice_log` | gyakorlás-történet (`List<PracticeEntry>`) |
| 44 | `dailyGoalMinutes` | `ss.progress.daily_goal_minutes` | napi cél (perc, clamp 5–120) |
| 45 | `streak` | `ss.streak.state` | streak állapot (egyetlen objektum) |
| 51 | `practiceHistoryV2` | `ss.practice.history_v2` | V2 history (ADR 0084 §Döntés 1) — külön kulcs, V1-gyel párhuzamosan él |

A `metronomeMuted` és a `practiceSpeed` csak a tanulás belső preferencia,
nem a jutalmakhoz tartozik — a baseline a tanulás feature teljes
kulcskészletét azért sorolja, mert a Kör 8 migráció a learn-t is érintheti
(egységes namespace).

### 2.2 Legacy kulcsok (`LegacyStorageKeys`)

| Sor | Konstans | Sztring-érték | Migráció státusza |
|---|---|---|---|
| 180 | `lessonProgress` | `lesson_progress_v1` | a `lesson_progress_repository.dart:92` `legacyKey`-ként használja → a migrátor egy lépésben átvette |
| 181 | `metronomeMuted` | `metronome_muted_v1` | analóg; a fenti repository-ig nem üt, mert nincs önálló repo (a tanulás metronómot a `metronome.dart:78` kezeli) |
| 182 | `practiceSpeed` | `practice_speed_v1` | analóg |
| 186 | `practiceLog` | `practice_log_v1` | `practice_log_repository.dart:42` `legacyKey`-ként aktív |
| 187 | `dailyGoalMinutes` | `daily_goal_min_v1` | `daily_goal_provider.dart` NEM használ `legacyKey`-t → az átvétel **NEM történt meg** (lásd §10 kockázat) |
| 188 | `streak` | `practice_streak_v1` | `streak_repository.dart:39` `legacyKey`-ként aktív |

A legacy kulcsok törlése TILOS, amíg a `JsonDocumentStore` migrátora nem
regisztrálta az átvételt — ez az AGENTS.md §6 és a `storage_keys.dart:1–8`
dokumentum-kommentben explicit rögzített szabály.

### 2.3 Wire-alak (JSON) gamifikációnként

#### 2.3.1 Streak (`ss.streak.state`)

- A tároló JSON-burkolat a `json_document_store.dart:11–13` szerint: `{"schemaVersion": 1, "data": …}`. A `schemaVersion` értéke a `json_document_store.dart:19`-ben: `1`.
- A `bodyKey` a streak esetén `'data'` (`streak_repository.dart:41`).
- A belső `data` objektum a `StreakData.toJson` (`streak_data.dart:50–56`) szerint:
  ```json
  {
    "current": <int>,       // az aktuális széria hossza napokban
    "longest": <int>,       // a valaha volt leghosszabb széria
    "last":    <int>,       // az utolsó gyakorlás epoch-napja, -1 ha soha
    "freezes": <int>,       // bankolt freeze-ek száma (0..maxFreezes)
    "total":   <int>        // összes gyakorolt nap
  }
  ```
- A dekóder `StreakData.fromJson` (`streak_data.dart:60–66`) minden kulcsra
  `optionalInt`-et használ `json_validation.dart`-ból — hiányzó kulcs →
  `0`/`-1` default, ami megegyezik a friss `StreakData()` defaultjaival
  (`streak_data.dart:10–16`).

#### 2.3.2 Practice log (`ss.progress.practice_log`)

- A burkolat `JsonCollectionStore` (a bodyKey az alapértelmezett `'items'` a `json_document_store.dart:55` szerint): `{"schemaVersion": 1, "items": [<entry>, …]}`.
- A `maxItems` a repository interface-en: `400` (`practice_log_repository.dart:20`).
- A `RecordOrder.newestLast` (`practice_log_repository.dart:48`) miatt a cap a legrégebbi (head) elemeket vágja (`json_document_store.dart:29–30` komment + `:295–300` `capRecords`).
- A rekord JSON alakja (`practice_entry.dart:46–53`):
  ```json
  {
    "day":  <int>,        // epoch-nap
    "src":  "<string>",   // PracticeSource.name: 'live' | 'analyze' | 'learn'
    "sec":  <int>,        // másodperc
    "str":  <int>,        // strum-ek száma
    "chd":  <int>,        // akkordok száma
    "dir":  <number>|null // 0..1, csak scored Learn run-ból (a kulcs elhagyva ha null)
  }
  ```
- A `fromJson` (`practice_entry.dart:58–71`) a `day`-hez `requireInt`-et használ (hiányzó day → rekord-skip), a többihez `optionalInt`/`optionalDouble`-t. Az ismeretlen `src` érték NEM dob, hanem `PracticeSource.live`-ra esik vissza (`practice_entry.dart:60–66`) — ez egy **mért szándékos kivétel** az „ismeretlen enum = rossz rekord" szabály alól.

#### 2.3.3 Lesson progress (`ss.learn.lesson_progress`)

- A burkolat: `{"schemaVersion": 1, "data": {…}}`, `bodyKey: 'data'` (`lesson_progress_repository.dart:94`).
- A belső `data` egy `Map<String, double>` (lesson id → best accuracy 0..1) — `lesson_progress_repository.dart:13, 41–58`.
- A cap: `maxLessons = 500` (`lesson_progress_repository.dart:19`).
- A dekóder kihagyja a nem-numerikus / NaN / tartományon kívüli értékeket (`lesson_progress_repository.dart:48–56`), és loggolja a kihagyottak számát (`:60–68`). A kihagyás NEM az egész dokumentumot rontja el.

#### 2.3.4 Daily goal (`ss.progress.daily_goal_minutes`)

- Nem dokumentum, hanem nyers `int` preferencia (`daily_goal_provider.dart:20` olvasás, `:27–28` írás).
- A `build()` clamp: `5..120` perc, alapértelmezetten 10 (`daily_goal_provider.dart:11–13, 21`).
- A `presets` lista: `[5, 10, 15, 20, 30, 45, 60]` (`daily_goal_provider.dart:16`) — ez a goal-picker bottom sheet opciókészlete (`progress_screen.dart:159` `_editGoal`).

---

## 3. Streak — a mai szabály számszerűen

A `lib/features/streak/streak_logic.dart` tiszta, óra- és IO-mentes
(osztály-deklaráció: 7. sor). A publikus szimbólumok és a mért értékek:

| Szimbólum | Sor | Érték / viselkedés |
|---|---|---|
| `freezeEveryNDays` | 11 | `7` — minden 7. gyakorolt nap után jár egy freeze |
| `maxFreezes` | 14 | `3` — ennyi lehet bankolva egyszerre |
| `epochDayOf(DateTime)` | 18–20 | helyi éjfélből számít (`DateTime(d.year, d.month, d.day)` a `DateTime` UTC nélküli konstruktora, ezért **local time**); az eredmény `millisecondsSinceEpoch ~/ Duration.millisecondsPerDay`. A dokumentum-komment a 16. sorban: "local-midnight epoch day … local time" |
| `applyPractice(prev, today)` | 32–63 | `today <= prev.lastPracticeDay` → no-op (33. sor); `gap == 1` → `current+1` (41–42); `gap == 2 && freezes > 0` → `current+1`, `freezes-1` (43–45); különben `current = 1` (46–48). A freeze-jutalom a 30. sor kommentje + 52–54: `totalDays % freezeEveryNDays == 0 && freezes < maxFreezes` → `freezes+1` |
| `practicedToday(d, today)` | 66–67 | `d.lastPracticeDay == today` |
| `atRisk(d, today)` | 72–75 | van élő széria, ma még nem gyakorolt, és az utolsó gyakorlás pontosan tegnap volt |
| `isBroken(d, today)` | 79–82 | van élő széria, ma még nem gyakorolt, és a gap > 1 nap |

**A `gap == 2` szabály alkalmazási útja**: az `applyPractice` 43. sora
(`} else if (gap == 2 && freezes > 0) {`). A teszt `streak_logic_test.dart:47`
(`'a banked freeze covers exactly one missed day'`) és `:61` (`'a two-day gap
(gap of 3) is too big for a single freeze → reset'`) ezt a pontos viselkedést
őrzi.

**A freeze akkumuláció feltétele** (`streak_logic.dart:30–31, 52–54`): a
`totalDays` (nem a `current`) `freezeEveryNDays`-szel osztva adja meg, mikor
jár új freeze — azaz akkor is, ha a széria közben volt freeze-veszteség
vagy restart.

---

## 4. Daily Challenge — determinisztikus származtatás

A `lib/features/streak/daily_challenge.dart` (63 sor) a napi kihívást
kizárólag az epoch-napból származtatja, szerver és hálózat nincs:

| Elem | Sor | Érték / képlet |
|---|---|---|
| Seed | 47 | `math.Random(epochDay & 0x7fffffff)` — a `& 0x7fffffff` a `Random` nem-negatív seed-követelménye miatt kell (a 32. sor kommentje: "Non-negative, day-stable seed") |
| Hossz | 48 | `const [4, 6, 8][rng.nextInt(3)]` — három lehetséges hossz: 4 / 6 / 8 |
| Név | 55–56 | `_names[(epochDay % _names.length + _names.length) % _names.length]` — a kettős modulo a negatív epochDay elleni védelem |
| Névlista | 28–41 | 12 elem: `'Campfire'`, `'Backbeat Bounce'`, `'Island Groove'`, `'Folk Shuffle'`, `'Pop Punk Push'`, `'Country Roll'`, `'Reggae Skank'`, `'Ballad Sway'`, `'Funk Chop'`, `'Train Beat'`, `'Waltz Lilt'`, `'Anthem Drive'` |
| On-beat | 51 | `i.isEven` — minden páros index down |
| Off-beat | 52 | `!onBeat && rng.nextDouble() < 0.7` — az off-beatek ~70%-a up |

A `daily_challenge_test.dart:6` (`'is deterministic — same day yields the
same pattern and name'`) és `:21` (`'length is always one of 4/6/8 and
on-beats are down-strokes'`) ezt a determinizmust és a hossz-korlátot őrzi.

A `DailyChallenge` providerén át a `StreakScreen` `DailyChallenge.forDay(today)`
hívással kéri le a napit (`streak_screen.dart:32`), és a gomb `🔥` címkéje a
`StreakBadge`-ben (`streak_badge.dart:18`) a `streakProvider`-re figyel.

---

## 5. Learn — lesson-star küszöbök

A `lib/features/learn/lesson_scorer.dart` **nem** tartalmazza a star-küszöböket
— csak a `passThreshold = 0.7` (`lesson_scorer.dart:164`) található itt.
A 0289 §1-ből levezetett 70/80/90%-os star-lépcső a **`model/lesson_progress.dart`**-ban
él (a fájl neve és a brief §0.0 szerinti hivatkozás pontos):

| Sor | Szimbólum | Érték / viselkedés |
|---|---|---|
| 8 | `passThreshold` | `0.7` — megegyezik a `LessonScorer.passThreshold` értékével (a 6–7. sor kommentje szerint) |
| 11 | `stars(double accuracy)` függvény | belső if-lánc |
| 12 | `if (accuracy >= 0.9) return 3;` | 3 csillag ≥ 90% |
| 13 | `if (accuracy >= 0.8) return 2;` | 2 csillag ≥ 80% |
| 14 | `if (accuracy >= passThreshold) return 1;` | 1 csillag ≥ 70% (passz-küszöb) |
| 15 | `return 0;` | különben 0 |
| 18 | `isPassed(double accuracy)` | `accuracy >= passThreshold` (0.7) |

A `LessonProgress` NEM adattípus, hanem statikus segédosztály (`lesson_progress.dart:3` `class LessonProgress` + `LessonProgress._();` privát konstruktor a 4. sorban) — a tényleges perzisztencia `Map<lessonId, bestAccuracy>` a `LessonProgressController`-ben (`lesson_progress_provider.dart:19`).

A csillag-szám **nem** kerül tárolásra sehol (a `storage_keys.dart`-ban nincs
"star" kulcs, a perzisztált adat csak a best accuracy); a `LessonProgressController.stars()`
(`lesson_progress_provider.dart:30`) származtatja minden lekérdezéskor.

---

## 6. Practice log — bounded collection és race-guardok

A `practice_log_repository.dart:20` szerint a cap `400` bejegyzés. A
két fő race- és adatvesztés-őr:

### 6.1 Szinkron kezdeti betöltés (az r149 adatvesztés ellen)

`practice_log_provider.dart:16–26`:

```dart
/// The r149 data-loss bug (an entry recorded before the async load finished
/// overwrote the on-disk history with just itself) is structurally gone in
/// E01-R07: the log is read synchronously in [build], so there is no window
/// between "empty default" and "loaded history" to write into.
@override
List<PracticeEntry> build() => _repo.load();
```

A teszt őre: `test/features/progress/practice_log_race_test.dart:29` —
`'an immediate record MERGES with the stored history'`. A teszt a `:40–44`
sorokon az in-memory state-et, a `:46–57` sorokon a lemezre írt dokumentumot
ellenőrzi.

### 6.2 In-memory-first írás (write-failure ellen)

`practice_log_provider.dart:28–35`:

```dart
Future<void> record(PracticeEntry entry) async {
  final next = [...state, entry];
  // Bound the document — drop the oldest once over the cap.
  state = next.length > _cap ? next.sublist(next.length - _cap) : next;
  await _repo.save(state);
}
```

Az állapot a lemezre írás ELŐTT frissül — az `await` failure esetén is a
session teljes history-ja megmarad a memóriában. Az alatta lévő
`JsonDocumentStore.write` (`json_document_store.dart:103–129`) elnyeli a
`StorageException`-t és `storage.document.write_failed`-et loggol.

### 6.3 Rekord-szintű karantén

`json_document_store.dart:199–246` (a `JsonCollectionStore.read`):
rekordonként dekódol try/catch-csel; a rossz rekordok a
`storage.document.record_skipped` eseménnyel kerülnek loggolásra
(`:217–225, :228–232`). A teljes dokumentum parse-hibája `_markCorrupt`
(`:158–166`) által a `<key>.corrupt` kvótába kerül (`:106–113`).

---

## 7. Streak provider — idempotens napi beváltás

A `streak_provider.dart:23–30` (`recordPracticeToday`) és a
`streak_logic.dart:32–63` (`applyPractice`) együtt biztosítják, hogy:

- **ugyanazon a napon többször hívott `recordPracticeToday`** → az `applyPractice`
  33. során a `today <= prev.lastPracticeDay` ágra fut, és visszaadja a
  `prev`-et (a streak-controller `bool` visszatérési értéke `false`);
- **a freeze bankolása a `totalDays % freezeEveryNDays == 0` feltételhez
  kötött** (`streak_logic.dart:52`), és sosem lépi át a `maxFreezes`
  korlátot (ugyanott a `&& freezes < maxFreezes`);
- **a streak provider** NEM kommunikál a főkönyvvel — ez a 0290 §3
  ("nincs optimista jóváírás") előfeltétele. A Kör 8 migrációja során
  ezért a streak-controller egy use-case hívással kell összekötendő, nem
  pedig a UI-ból közvetlenül jutalmazandó.

A teszt-őr: `streak_provider_test.dart:13` (`'records practice once per day
and advances across days'`) és `:32` (`'streak persists across a fresh
controller'`) a szerializáció és a nap-átlépés viselkedését őrzi.

---

## 8. Meglévő teszt-guard leltár

A `test/features/streak/` és `test/features/progress/` fájljai a mért
guard-típus szerint:

### 8.1 Streak (5 fájl)

| Fájl | Sor | Guard-típus | Kulcs-tesztek |
|---|---|---|---|
| `daily_challenge_test.dart` | 49 | logic (determinism) | `:6` determinisztikus, `:14` napok különböznek, `:21` hossz 4/6/8, `:36` negatív epochDay, `:42` glyphs |
| `skill_reframe_test.dart` | 86 | UI / reframe-nyelv | `:42` skill stats + trend, `:75` skill szekció elrejtése üres állapotban |
| `streak_logic_test.dart` | 100 | logic | `:8` első gyakorlás, `:16` egymás utáni napok, `:25` same-day no-op, `:32` clock-back, `:38` reset freeze nélkül, `:47` freeze fedez, `:61` 2-napos gap, `:72` maxFreezes cap, `:81` atRisk/isBroken/practicedToday, `:90` epochDayOf 1 apart |
| `streak_provider_test.dart` | 45 | provider / idempotency / persistence | `:13` egyszer/nap, `:32` persist across fresh container |
| `streak_screen_test.dart` | 48 | UI | `:14` streak + challenge kártya |

A streak feature **NEM** tartalmaz explicit `race / a11y / screen-size` guardot —
a meglévő őr kizárólag logika + idempotencia. A Kör 8 migrációjának
fel kell tárnia, hogy az a11y/screen-size guard a streak képernyőn is
hiányzik-e (a `streak_screen.dart` 330 soros, görgethető).

### 8.2 Progress (5 fájl)

| Fájl | Sor | Guard-típus | Kulcs-tesztek |
|---|---|---|---|
| `daily_goal_provider_test.dart` | 42 | provider / clamp | `:20` default 10, `:24` clamp 5..120, `:35` persist |
| `practice_log_race_test.dart` | 59 | **race** | `:29` cold-start immediate record MERGE — a r149 adatvesztés őre |
| `practice_stats_test.dart` | 120 | logic | `:22` totals, `:34` negatív clamp, `:43` avg accuracy null ha nincs scored, `:57` secondsForDay, `:69` sessionsFrom, `:80` lastDays zero-fill, `:104` JSON round-trip, `:116` unknown source → live fallback |
| `progress_screen_test.dart` | 155 | UI + **screen-size** | `:42` empty state, `:51` populated, `:91–95, :100–104, :148–152` `scrollUntilVisible` — görgetéssel elérhető tartalom |
| `weekly_bars_a11y_test.dart` | 43 | **a11y** | `:20` minden bar egy Semantics node-ot kap (a 127-es kör javítása) |

A három explicit guard típus (race, a11y, screen-size) **mind** a progress
feature-ben van. A streak feature-ből ezek hiányoznak — ez az §10 kockázatok
rovatban kerül rögzítésre.

### 8.3 Learn (34 fájl, 3624 sor) és Share (7 fájl, 809 sor)

A learn feature teszt-fák száma 34 (a forrás 24) — az arány (~1.4×) jelzi,
hogy ez a feature a leginkább tesztelt. A share feature tesztjei (7 fájl:
`reel_meter`, `share_content`, `share_preview`, `share_service`, `strum_card`,
`strum_reel`, `wrapped`) a gamification szempontjából a `Wrapped`-szerű
megosztási képernyők őrei.

### 8.4 ADR-fedettség a tesztekben

A táblázat „Státusz” oszlopa kizárólag a megnevezett teszt **közvetlen
assertionjeit** tekinti lefedettnek. A „kapcsolódó, de nem elégséges” azt
jelenti, hogy a teszt a szomszédos viselkedést őrzi (pl. a11y, race), de
NEM méri az adott ADR-pontot közvetlenül — ezért a lefedettség hamis
zöldítését kerüljük el.

| ADR | Döntés | Létező mérő teszt | Státusz |
|---|---|---|---|
| 0289 §1 | elsajátítottság mért, nem XP | — | **GAP** — a `streak_logic_test` és a `practice_stats_test` kizárólag a streak-math és a stat-aggregáció tényét őrzi; egyik sem assertálja, hogy a felület NEM jelenít meg XP-t, és nincs UI-szintű „nincs XP-szám” assertion |
| 0289 §2 | bizonyíték auditálható | `weekly_bars_a11y_test:20–42` | **kapcsolódó, de nem elégséges** — a teszt a11y semantics-labelt ellenőriz, nem az ADR által megkívánt konkrét session-evidence (egy megnyitható practice-session, ami méri a mastery-állítást). Az a11y és az auditálhatóság két különböző követelmény |
| 0289 §3 | hiányzó adat ≠ 0 | `practice_stats_test:43–55` (`averageDirectionAccuracy` null, ha nincs scored) | **lefedett** — közvetlenül assertálja, hogy scored run nélkül az accuracy `null`, nem `0.0` |
| 0289 §4 | trend ≥ 5 adatpont kell | — | **GAP** |
| 0289 §5 | verzió-váltás látható | — | **GAP** |
| 0289 §6 | előfeltételek tisztelete | — | **GAP** |
| 0290 §1 | nincs büntető széria-nyelv | `skill_reframe_test:75–85` (a skill-szekció elrejtése üres állapotban) | **kapcsolódó, de nem elégséges** — a teszt az UI-elrejtést őrzi („zeros would demotivate”), de nem a 0290 §1 szóhasználati tilalmát (büntető / bűntudatkeltő nyelv); a tényleges nyelvi leltár (string-assertion a streak-szövegekre) hiányzik |
| 0290 §2 | idempotens, UI nem számol | `streak_provider_test:13–30` | **kapcsolódó, de nem elégséges** — a teszt a streak-provider same-day no-op-ját és a nap-átlépését őrzi (idempotencia-rész), de NEM bizonyítja, hogy a jutalom-számítás a UI-ból kitiltott (ehhez külön provider-/widget-szintű assert kellene, ami a jutalom-számot kizárólag a use-case-re korlátozza) |
| 0290 §3 | nincs optimista jóváírás | `practice_log_race_test:29–58` | **kapcsolódó, de nem elégséges** — a teszt a cold-start race-t őrzi (immediate record MERGE), nem a 0290 §3 szerinti „a jutalom-egyenleg CSAK a főkönyv megerősítése után frissülhet" konkrét tilalmát. Az optimista UI-t külön widget-szintű assert kellene |
| 0290 §4 | jutalom forrása auditálható | — | **GAP** — a `weekly_bars_a11y_test` a11y semantics, nem jutalom-audit |
| 0290 §5 | nincs fizetős megőrzés | — | **GAP** (nincs UI- vagy provider-szintű assert; a Kör 8-ban beépítendő) |
| 0290 §6 | érthető, teljesíthető feltétel | — | **GAP** |
| 0290 §7 | csökkentett mozgás alternatíva | — | **GAP** |

A **GAP**- és **kapcsolódó, de nem elégséges** sorok együtt a Kör 8–10
migráció **kötelező** follow-up tesztjei; ezen a körön (docs-only) nem
pótolhatók. A 0289 §1 (mastery ≠ XP) és a 0290 §4 (jutalom-audit) külön
kiemelendő: a meglévő a11y/logika tesztek a fenti értelemben NEM
bizonyítják a tényleges termékhatárt, ezért a Kör 8-ban dedikált
widget-tesztek beépítendők (a `flutter-test-writer` ügynök a
`weekly_bars_a11y_test.dart` mintára kaphat feladatot).

---

## 9. Dark-pattern tiltólista (ADR 0289 / 0290 alapján)

Minden tiltás az ADR-ek valamelyik konkrét döntésére hivatkozik. A
Kör 8–10 migráció minden egyes új UI-javaslata és provider-változtatása
ezzel a listával szembesítendő.

### 9.1 Az elsajátítottság forrása (ADR 0289)

| # | Tiltás | ADR-szakasz |
|---|---|---|
| D1 | XP megjelenítése elsajátítottságként | 0289 §1, §"Amit ez a döntés TILT" |
| D2 | Bizonyíték nélküli (vagy sehova nem vezető) elsajátítottsági állítás | 0289 §2, §TILT |
| D3 | Trend kirajzolása < 5 adatpontból (a határ inkluzív) | 0289 §4 |
| D4 | Mérőszám-verzió váltásának megjelenítése javulásként | 0289 §5 |
| D5 | Ajánlás, amihez a képesség-előfeltétel hiányzik | 0289 §6 |
| D6 | A hiányzó adat nullázása (a 0286 §1 alkalmazása) | 0289 §3 |

### 9.2 A széria és a jutalom (ADR 0290)

| # | Tiltás | ADR-szakasz |
|---|---|---|
| D7 | Büntető vagy bűntudatkeltő széria-nyelv | 0290 §1 |
| D8 | Optimista jóváírás a főkönyv megerősítése előtt | 0290 §3 |
| D9 | Jutalom UI-oldali kiszámítása (nem a főkönyv use-case-én át) | 0290 §2 |
| D10 | Fizetős széria-megőrzés (pay-to-preserve) | 0290 §5 |
| D11 | Rejtett vagy teljesíthetetlen eredmény-kritérium | 0290 §6 |
| D12 | Ünneplés kizárólag animációval, csökkentett mozgás alternatíva nélkül | 0290 §7 |
| D13 | Veszteség-nyelv a széria képernyőn | 0290 §"Amit ez a döntés TILT" |

### 9.3 Auditálhatóság és perzisztencia (származtatott)

| # | Tiltás | ADR-szakasz |
|---|---|---|
| D14 | Az elsajátítottsági / jutalom-állítás, ami mögött nincs konkrét, megnyitható session | 0289 §2 |
| D15 | A jutalom-egyenleg és a főkönyv közötti csendes eltérés (az írási hiba elnyelése) | 0290 §3 |
| D16 | Freeze-ek vagy bármely jutalom-elem regressziója gyakorlatlan napokon | 0290 §1 |

A D1–D16 sorszámozás a Kör 8 review-sablonjába emelendő át (javaslat: a
`docs/reviews/e08-rNN-review.md` checklist része legyen).

---

## 10. Kockázatok és follow-up a Kör 8-on belül

1. **`dailyGoalMinutes` legacy migrációja hiányzik.** A `daily_goal_provider.dart`
   a `StorageKeys.dailyGoalMinutes`-et olvassa/írja, de nem állít be
   `legacyKey`-t. A `LegacyStorageKeys.dailyGoalMinutes = 'daily_goal_min_v1'`
   (`storage_keys.dart:187`) így sosem olvasható — aki a `daily_goal_min_v1`
   kulcs alatt tárolta a beállítást a V1 előtt, annak a default 10 percre
   ugrik vissza. Ez néma adatvesztés, bár az adat nem kritikus (újra beállítható).
   **Javaslat:** a Kör 8 egyik korai köreiben a `DailyGoalController.build()`
   bővítendő egy `legacyKey`-s fallback olvasással. A `JsonDocumentStore`
   itt NEM használható (a daily_goal nem dokumentum, hanem `int` preferencia),
   ezért manuális olvasás kell a `Preferences`-ből.

2. **Streak feature-ből hiányoznak az a11y/screen-size/race guardok.** A
   `streak_screen.dart` 330 soros, görgethető; a `streak_badge.dart` a
   navigációra reagál. A Kör 8-ban beépítendő legalább egy `scrollUntilVisible`
   (`progress_screen_test:91–95` mintára) és egy `Semantics`-ellenőrzés a
   `weekly_bars_a11y_test:20` mintájára.

3. **A 0289 §4 / 0290 §5–7 GAP.** A trend-küszöb (≥5 adatpont), a
   pay-to-preserve tiltás, az érthető kritérium és a reduced-motion
   alternatíva mögött nincs mérő teszt. Ezek a Kör 8-ban a feature-ök
   bevezetésével együtt kötelezően pótlandók (a `flutter-test-writer` ügynök
   mintát kap a `weekly_bars_a11y_test.dart` és a `practice_log_race_test.dart`
   fájlokból).

4. **`lesson_progress_v1` legacy migráció formája.** A
   `lesson_progress_repository.dart:92` a `legacyKey`-t a `JsonDocumentStore`
   konstruktorba adja — ez feltételezi, hogy a V1 dokumentum pontosan ugyanazt
   az `{"schemaVersion": 1, "data": {…}}` envelope-ot használta. A
   tényleges V1-alak NEM mért — ez a Kör 8 első lépésének egyik
   feltárandó feladata (a V1-ből jövő felhasználók tartalmának megőrzése
   a 0289 §2 (auditálhatóság) szerint kötelező).

5. **`skill_reframe_test` és a 0290 §1 kapcsolata** — a
   `skill_reframe_test.dart:75–85` teszteli, hogy a skill-szekció elrejti
   magát, ha nincs valódi gyakorlás. Ez a 0290 §1 ("a széria vége
   tényközlés, nem ítélet") egyetlen mérő őre a jelenlegi teszt-készletben —
   a Kör 8-ban bővíteni kell (pl. a streak-screen üres-állapotának
   szövegezésére).

---

## 11. A mérés határvonala — ami ebben a körben NEM készül

- **Nincs alkalmazáskód-módosítás** — ez a §6 A6 kitétel és a `lib/` lista
  tilalma. A baseline a jelenlegi kódot írja le, nem változtatja.
- **Nincs új tároló-kulcs bevezetése** — ez a Kör 2 (`lib/features/gamification/`
  létrehozása) és a Kör 8+ migráció feladata.
- **Nincs freeze-szabály korrekció** — a `gap == 2` szabály
  (`streak_logic.dart:43`) egy ismert adósság, de a javítás a Kör 10/11
  dolga. Ezen a körön csak le van írva.
- **Nincs UI-szövegezés vagy vizuális változtatás** — a streak → skill
  reframe a `skill_reframe_test.dart:75` óta mért, de a baseline nem ír
  új szöveget.
- **Nincs CI- vagy workflow-módosítás** — ez kizárólag az orchestrátorra
  tartozik.