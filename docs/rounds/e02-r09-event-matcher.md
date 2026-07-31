# E02-R09 — Event matcher és legacy timing parity

- **Státusz:** READY (kiadható, 2026-07-31)
- **SDD-kör:** [`docs/sdd/03-epic-02-practice-engine.md`](../sdd/03-epic-02-practice-engine.md) **„Kör 9"**
- **Branch:** `codex/e02-r09-event-matcher`
- **Implementer motor:** **Codex** — a user döntése (2026-07-31). Baseline-érzékeny
  matcher, ítéletigényes él-szemantikával ([ADR 0069](../adr/0069-two-engine-implementer-pool.md) §15.6)
- **ADR:** **0075** — [`docs/adr/0075-practice-event-matcher.md`](../adr/0075-practice-event-matcher.md),
  **már megírva az orchestrátor által**. Az implementer **NEM hoz létre és NEM
  módosít `docs/adr/` fájlt**; az ADR a szerződés, ezt implementálod.

## 0.0 Kör-számozási pontosítás (orchestrátor, 2026-07-31)

A `HANDOFF.md` §6 az E02-R09-et „Session controller"-ként írta le. **Ez téves
volt**: az SDD-fejezet szerint a Kör 9 az **event matcher**, a Kör 10 a három
scorer, és a `PracticeSessionController` a **Kör 11**. Az eddigi számozás 1:1
(E02-R08 = „Kör 8 — Observation gateway"). A doc-priority lánc szerint az SDD
fejezet a normatív (AGENTS.md §2: „elavult dokumentumot nem szabad csendben
követni"), ezért ez a kör a matcher. A `HANDOFF.md` javítva.

Következmény: **a `practiceCaptureActiveByStatus` tábla első valódi hívója és az
E02-R07 nyitott `MonotonicPracticeSessionClock.start()` NOTE-ja NEM ebben a
körben zárul** — mindkettő a controller-köré (E02-R11). Ne nyúlj hozzájuk.

## 0. Kör-jelzés — KÖTELEZŐ (AGENTS.md §15.2)

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done    "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélküli kör = bukott kör. `gh`-t NE hívj, ne pusholj, PR-t ne nyiss.
**STOP-klauzula:** listán kívüli fájl, vagy egymásnak / a mért állapotnak
ellentmondó előírás → `stopped` + pontos jelentés. **A §7 a terved.**

## 1. Cél

A `CompiledPracticeTarget` (R06) és a `PracticeObservation`-ök (R08) közé
hiányzik a lépés, ami eldönti: **melyik megfigyelés melyik célesemény**. Ez a kör
egy **pure, determinisztikus, egy-az-egyhez event matchert** hoz létre, ami a
legacy `LessonScorer` párosítási viselkedését **mikroszekundumra megőrzi**,
közben kurzoralapú, tehát nem pásztázza végig a teljes eseménylistát minden
pengetésnél.

A teljes döntés és annak indoklása: **[ADR 0075](../adr/0075-practice-event-matcher.md)**.
Az ADR §2 táblája (P1–P9) a szerződés; ez a brief azt teszi mérhetővé.

Hívó UI és provider **nincs** ebben a körben; a practice flagek OFF-ban maradnak,
a production viselkedés **bitre azonos** marad.

## 2. Jelenlegi állapot (mért tények)

### 2.1 A paritás-referencia: `lib/features/learn/lesson_scorer.dart`

343 sor, mutábilis, `double` másodpercekkel dolgozik. A párosítás magja
(`registerStrum`, 245–290. sor):

```dart
final playedSec = elapsedSec - inputLatencySec;
_Timed? best;
var bestDelta = windowSec + 1e9;
for (final t in _events) {
  if (t.matched) continue;
  final d = (t.time - playedSec).abs();
  if (d <= windowSec && d < bestDelta) { best = t; bestDelta = d; }
}
if (best == null) return null;   // extra strum — állapotot NEM változtat
best.matched = true;             // ELFOGY, akkor is, ha az irány rossz
if (dir == best.event.direction) { /* hit */ } else { /* wrongDirection */ }
```

A kimaradás-zárás (`advance`, 296–310. sor):

```dart
final playedSec = elapsedSec - inputLatencySec;
for (final t in _events) {
  if (t.matched) continue;
  if (t.time + windowSec < playedSec) { t.matched = true; missed++; ... }
}
```

`finalize()` (313–321. sor): minden még nyitott esemény kimaradás.

**Négy mért él, amit ez a kör kipinnel:**

1. **Jogosultság `<=`, zárás szigorú `<`.** Pontosan
   `played == target.time + matchWindow` esetén az esemény **még nyitott ÉS még
   jogosult**. Ez nem elírás a legacyben — ez a viselkedés.
2. **Holtverseny a korábbié.** A `d < bestDelta` szigorú, a lista idő szerint
   növekvő, tehát pontosan félúton lévő pengetésnél a **korábbi** esemény nyer.
3. **A rossz irány is elfogyasztja a célt.** A `matched = true` az irány-ág
   ELŐTT van. Rossz irány ≠ kimaradás, és a cél nem marad nyitva másnak.
4. **Az extra pengetés semmit nem változtat.** Nem tör combót, nem büntet,
   nem zár célt. (`ExtraStrumPolicy.ignore` a `legacyLearnParity`-ben.)

### 2.2 Amire épül (kész, változatlanul használandó)

- `CompiledPracticeTarget` / `CompiledTargetEvent`
  (`lib/features/practice/domain/model/compiled_practice_target.dart`).
  Mezők: `sourceEventId`, `loopIndex`, `position`, **`time`** („Absolute elapsed
  time from session start, **including count-in**"), `barIndex`, `chord`,
  `direction`, `accent`, **`optional`**.
  Az `events` lista **idő szerint NEM CSÖKKENŐ** — mérve:
  `practice_target_compiler.dart:189–195`, `_ensureNondecreasingEventTimes`
  `StateError`-t dob, ha `events[i].time < events[i-1].time`. **Nem szigorúan
  növekvő**, tehát **azonos idejű célesemények lehetségesek** — ezért kell a
  holtverseny-szabályhoz az „azonos időnél a kisebb index" kiegészítés (§5.4).
  A matcher ezt a rendezettséget **előfeltételként** kezelheti (a kurzor erre
  épül); a §8-ban írd le, mi történik, ha egy kézzel épített, rendezetlen
  target érkezik — de **ne** vezess be miatta futásidejű átrendezést.
- `StrumObservation` (`practice_observation.dart`): `at`, `sequence`,
  `direction`, `confidence`.
- `ScoringProfile.legacyLearnParity`: `matchWindow` **280 ms**,
  `perfectWindow` 50 ms, `goodWindow` 120 ms, `extraStrumPolicy` `ignore`.
- `PracticeVerdict` / `TimingGrade` (`practice_verdict.dart`) — **a Kör 10-é**;
  ez a kör NEM állít elő `PracticeVerdict`-et és NEM ad `TimingGrade`-et.
- `lib/features/practice/domain/` **megosztott domain**
  (`tool/check_architecture.dart:229–232`): Flutter/Riverpod/Dio import TILOS.
  Őr: `test/features/practice/domain/domain_purity_test.dart`. A `package:meta`
  megengedett (a szomszédos modellek is használják).

### 2.3 Ami MA nincs

- Nincs event matcher, nincs `domain/service/` alatt semmi a
  `practice_target_compiler.dart`-on kívül.
- A `test/features/practice/domain/` **lapos** (nincs `service/` alkönyvtár) —
  a `practice_target_compiler_test.dart` és a
  `practice_target_legacy_parity_test.dart` is közvetlenül ott van. **Kövesd
  ezt a mintát**, ne hozz létre új alkönyvtárat.
- A `test/property/` hat fájlt tartalmaz, köztük a
  `practice_session_property_test.dart` és a `practice_observation_property_test.dart`
  — a `PROPERTY_SEED` olvasásának mintáját ezekből vedd.

## 3. Scope

**Benne:** egyetlen új domain service (a matcher) + a hozzá tartozó
egység-, paritás- és property-tesztek.

**Kívül (TILOS):**

- **A `lib/features/learn/**` bármilyen módosítása.** A legacy `LessonScorer` a
  paritás **referenciája** — ha hozzányúlsz, megszűnik a mérce. Olvasni szabad,
  tesztből importálni szabad, írni nem.
- `TimingGrade`, pontszám, combo, multiplier, `PracticeVerdict`, `PracticeMetrics`,
  `PracticeAttemptResult` előállítása — **mind a Kör 10-é**.
- `ChordObservation` feldolgozása, akkord-idővonal, chord lag — **Kör 10**.
- Hívó, provider, UI, `PracticeSessionController` — **Kör 11**.
- A `practiceCaptureActiveByStatus` tábla, a session clock, a reducer, a gateway
  bármilyen módosítása — **kész körök, ne nyúlj hozzájuk**.
- Új ADR, `docs/sdd/**`, `HANDOFF.md`, `.github/**`, `pubspec.yaml`, DSP,
  `docs/rag/chunks/**`.
- Feature flag: **nem kell** — ennek a körnek nincs hívója, tehát nincs mit
  kapcsolni. Ne vezess be újat.

## 4. Engedélyezett fájlok

| Útvonal | Új? | Miért |
|---|---|---|
| `lib/features/practice/domain/service/practice_event_matcher.dart` | **ÚJ** | a matcher és a kimeneti típusai |
| `test/features/practice/domain/practice_event_matcher_test.dart` | **ÚJ** | egység- és él-tesztek (a §6 mátrixcellák) |
| `test/features/practice/domain/practice_event_matcher_parity_test.dart` | **ÚJ** | paritás a legacy `LessonScorer`-rel szemben |
| `test/property/practice_event_matcher_property_test.dart` | **ÚJ** | randomizált property gate (`PROPERTY_SEED`) |
| `docs/rounds/e02-r09-event-matcher.md` | — | **CSAK a §8** (handoff) kitöltése |

**Tilos zóna:** minden más. Nevezetesen `lib/features/learn/**`,
`lib/features/practice/` minden más fájlja, `docs/adr/**`, `docs/sdd/**`,
`HANDOFF.md`, `.github/**`, `pubspec.yaml`, `tool/**`, `docs/rag/chunks/**`.

**Új fájl a fenti négyen kívül = scope-sértés** → `stopped`.

## 5. Kötött döntések (az ADR 0075-ből — ezek NEM tárgyalhatók)

1. **A matcher pontozás-mentes.** Céleseményenként előállítja: párosult-e, ha
   igen melyik megfigyeléssel (`sequence`), mikor (latency-korrigált idő), és
   mekkora **előjeles** eltéréssel (`observedAt − targetAt`, **negatív = korai**).
   `TimingGrade`-et NEM ad.
2. **A bemenet `StrumObservation`.** `ChordObservation` nincs a hatókörben.
3. **Latency-korrekció egy helyen:** minden összehasonlítás a
   `played = observation.at − inputLatency` értéken megy, ahogy a legacy.
4. **P1–P9 (ADR 0075 §2) mikroszekundumra kötelező.** Külön kiemelve:
   - jogosultság `|target.time − played| <= matchWindow` (**`<=`**);
   - zárás `target.time + matchWindow < played` (**szigorú `<`**);
   - holtversenynél a **korábbi** cél (azonos időnél a **kisebb index**);
   - a rossz irány is **elfogyasztja** a célt;
   - az extra pengetés **állapotot nem változtat**.
5. **Opcionális cél** (`CompiledTargetEvent.optional == true`): párosítható, de
   ha nyitva marad, **nem kimaradás** — külön feloldás. A legacynek nincs
   megfelelője, ezért paritást nem sérthet.
6. **Kurzoralapú működés.** A nyitott célok növekvő indexű ablakban élnek; a
   kurzor alatt minden cél lezárt. **Nem** teljes lista-pásztázás megfigyelésenként.
7. **`O(célesemény)` memória.** A matcher **nem tárol megfigyeléseket**.
8. **A mérés eszközei — ezeket MEGADOM, hogy a 6. és 7. pont ne csak ígéret
   legyen** (a brief-sablon „a méréshez szükséges eszköz" szabálya):
   a matcher két `@visibleForTesting` számlálót tesz elérhetővé —
   **(a)** hány célesemény-rekordot vizsgált meg összesen a párosítás és a
   zárás során (kumulatív, sosem csökken), és **(b)** hány rekordot tart
   éppen a memóriájában. Ezek a production API részei, `@visibleForTesting`
   annotációval; **NEM opcionálisak és nem cserélhetők fal-óra méréssel**
   (a fal-óra flaky, és CI-n értelmezhetetlen).
9. **A domain pure marad:** semmilyen Flutter/Riverpod/Dio import. A
   `package:meta` megengedett.

## 6. Acceptance criteria

Minden pont mellett ott van, **melyik hibás implementációt fogja pirosra**.

### A1 — Paritás a legacy `LessonScorer`-rel, mikroszekundumra

Paritás-teszt, ami **ugyanazt** a lecke-tartalmat és **ugyanazt** a pengetés-
sorozatot futtatja át a legacy `LessonScorer`-en és az új matcheren, majd
céleseményenként összeveti: párosult-e, melyik pengetés-index párosult hozzá,
és — ahol párosult — az eltérés.

- A legacy `double` másodperceit **mikroszekundumra** kell átváltani; az
  összehasonlítás **egzakt egyenlőség**, tűréssel NEM.
- A korpusz a **teljes szállított lecke-katalógus**: `Lessons.all`
  (**mérve 16 lecke**, `lib/features/learn/model/lesson.dart:321–338`)
  **plusz** a tananyagon kívüli `Lessons.firstWin` (uo. 146. sor) — összesen 17.
  Egyet sem hagyhatsz ki; mindegyik legalább három latency-értékkel (A3).
  *(A katalógus-bejárás mintáját az R05 Lesson-adapter paritás-tesztje mutatja:
  `test/features/practice/data/adapters/lesson_practice_adapter_test.dart`.)*

***Pirosra fogja:*** minden olyan matcher, ami „lényegében ugyanazt" csinálja —
a holtverseny-irányt elrontja, a rossz irányú párosítást nem fogyasztja el, vagy
az él-operátort felcseréli.

**NEM elfogadható gyengítés:** `closeTo` / epszilon-tűrés a paritás-
összehasonlításban; a fixture-halmaz egyetlen leckére szűkítése; „a legacy
lebegőpontos, ezért ±1 µs elfogadható" indoklás. A kerekítést a **konverzió**
oldja meg, nem a tűrés — ha a konverzió nem determinisztikus, az BLOKKOLÓ
lelet, nem tűréssel elfedendő.

### A2 — Él-mátrix a két predikátumra (kötelező cellák)

Egység-teszt, `matchWindow = 280 ms`, egyetlen cél `target.time = T`:

| Cella | `played` | Elvárt |
|---|---|---|
| jogosultság alatta | `T + 279 999 µs` | párosul |
| jogosultság **pontosan** | `T + 280 000 µs` | **párosul** (`<=`) |
| jogosultság fölötte | `T + 280 001 µs` | nem párosul (extra) |
| zárás alatta | óra `T + 279 999 µs` | **nyitva marad** |
| zárás **pontosan** | óra `T + 280 000 µs` | **nyitva marad** (szigorú `<`) |
| zárás fölötte | óra `T + 280 001 µs` | kimaradás |

És a két predikátum **együtt**: az óra `T + 280 000 µs`-ra léptetése után egy
`played = T + 280 000 µs` pengetés **még párosul**.

***Pirosra fogja:*** a „egységesítsük a két operátort" refaktor — bármelyik
irányba. A cellák értékeit `python3 -c`-vel ellenőrizd, ne fejben.

### A3 — Latency-mátrix

`inputLatency ∈ {0 ms, 40 ms, 300 ms}`. A **300 ms szándékosan NAGYOBB a 280 ms-os
match window-nál** — ez a küszöb FÖLÖTTI cella, e nélkül a mátrix nem mátrix.
Mindhárom értékre a legacy paritás egzakt.

***Pirosra fogja:*** a latency-korrekció kihagyása valamelyik útvonalon (párosítás
vs. zárás vs. `finalize`) — ez pontosan az E02-R08-ban mért hibaosztály, ahol a
korrekció csak az egyik ágon futott.

### A4 — Holtverseny

Két cél, `T1 < T2`, egy pengetés **pontosan félúton**
(`played = (T1 + T2) / 2`, egész µs-ra kijövő értékkel). Elvárt: **`T1` párosul.**
Plusz a két szomszédos cella: 1 µs-mal `T1` felé, 1 µs-mal `T2` felé.

***Pirosra fogja:*** `d <= bestDelta` (a későbbi nyerne), vagy stabil rendezés
nélküli „legjobb" keresés.

### A5 — Egy-az-egyhez invariánsok

- Egy megfigyelés **legfeljebb egy** célhoz párosul.
- Egy cél **legfeljebb egyszer** párosul, és lezárás után **soha nem nyílik újra**.
- A feloldott célok száma **monoton nő**.
- `finalize()` után **minden kötelező cél lezárt**, és az opcionálisak közül a
  párosítatlanok **nem kimaradásként** zárulnak.

**NEM elfogadható gyengítés:** ezek property-tesztként is kellenek (A7), nem
csak fix fixture-ön. Egy „a fixture-ben nem fordul elő" indoklás nem zárja le.

### A6 — Skálázás és memória, MÉRVE

Az §5.8 két számlálójával:

- **Kurzor:** 20 000 célesemény **legalább 50 ms-os egymás közti távolsággal**
  (így egy 280 ms-os ablakba legfeljebb ~12 cél esik), 1 000 sorrendben érkező
  pengetés, a zárás a végén `finalize()`-zal → a megvizsgált rekordok kumulatív
  száma **≤ 64 × (pengetések száma + célok száma)**, azaz ≤ 1 344 000.
  Nagyságrendek: egy helyes kurzoros implementáció itt ~26 000 körül van
  (1 000 × ~6 az ablakban + 20 000 egyszeri lezárás), egy teljes pásztázást
  végző ~20 000 000-nál — a küszöb tehát **két nagyságrenddel** a helyes fölött
  és egy nagyságrenddel a hibás alatt van, tehát nem érzékeny a konstansokra.
- **Memória:** 4 célesemény, **100 000** extra pengetés → a megtartott rekordok
  száma **változatlanul 4**.

***Pirosra fogja:*** a legacy full-scan egy az egyben átemelése; és minden olyan
implementáció, ami eltárolja a megfigyeléseket (pl. „később még jól jöhet"
listában).

**NEM elfogadható gyengítés:** a számlálók elhagyása és fal-óra méréssel
helyettesítése; a küszöb utólagos felhúzása a mért értékre. Ha a 64-es konstans
szűknek bizonyul egy helyes implementációra, az `stopped` + jelentés, nem
csendes átírás.

### A7 — Randomizált property gate

`test/property/practice_event_matcher_property_test.dart`, a `PROPERTY_SEED`-et
a többi property-teszt mintája szerint olvasva (hiány → 42). Legalább:

1. nincs kétszeres párosítás és nincs újranyitás **tetszőleges** pengetés-sorozatra;
2. a feloldott célok száma monoton nő;
3. `finalize()` után nincs nyitott kötelező cél;
4. **véletlen extra pengetés-özön** (a célokhoz nem közeli időpontokban) nem
   dob kivételt és nem változtat egyetlen cél feloldását sem;
5. **sorrend-normalizálás:** ugyanaz a pengetés-halmaz **összekevert** sorrendben
   sem okoz kivételt, és nem sért egyetlen fenti invariánst sem.

A küszöbök **%-alapúak vagy invariáns-jellegűek** (nem flaky-k).

### A8 — Domain-tisztaság és architektúra

`tools/round-gate.sh` **architecture** lépése zöld; a
`domain_purity_test.dart` zöld. Az allowlist **nem bővül** — ha bővülnie kellene,
az `stopped`, nem allowlist-szerkesztés.

### A9 — Nulla viselkedésváltozás a production úton

`git diff --stat origin/main...HEAD` → a `lib/` alatt **kizárólag** az egyetlen
új matcher-fájl. `lib/features/learn/` **0 sor**. Hívó nincs, provider nincs.

## 7. Implementációs sorrend (ez a TERVED)

1. Olvasd el: **[ADR 0075](../adr/0075-practice-event-matcher.md)** teljesen,
   `lesson_scorer.dart` 245–321. sor, `compiled_practice_target.dart`,
   `practice_observation.dart`, `scoring_profile.dart`
   (`legacyLearnParity`), és mintaként a `practice_target_legacy_parity_test.dart`.
2. **Előbb a paritás-harness** (A1), a legacy referenciával — a piros teszt
   legyen meg, mielőtt a matcher kész.
3. A matcher váza: konstrukció a `CompiledPracticeTarget` + `ScoringProfile` +
   `inputLatency` hármasból; a kimeneti típus (§5.1) definiálása.
4. A párosítás magja, az ADR 0075 P1–P6 szerint, **kurzorral** (§5.6).
5. A zárás (`advance`) és a `finalize` (P7–P9), az opcionális célok külön
   feloldásával (§5.5).
6. A két `@visibleForTesting` számláló (§5.8).
7. Él-tesztek: A2, A3, A4, A5.
8. Skálázási és memória-teszt: A6.
9. Property-teszt: A7.
10. Záró gate (§9), majd a §8 kitöltése.

## 8. Implementation handoff — az IMPLEMENTER tölti ki

*(Fájlonkénti összefoglaló · a záró gate TÉNYLEGES, teljes kimenete · az A1–A9
pontok teljesülése bizonyítékkal · eltérések és okuk · nem futtatott ellenőrzések
és okuk · follow-upok.)*

## 9. Záró gate — szó szerint ez az egyetlen hívás

```
tools/round-gate.sh test/features/practice/ test/property/practice_event_matcher_property_test.dart
```

Csővezeték nélkül (se `| tail`, se `| head`, se `| grep`, se `&&` láncolás), a
teljes kimenetet a §8-ba. A teljes suite + a randomizált property gate + az APK
a CI-ban fut, a merge előtt, orchestrátor-dispatch-csel (ADR 0053) — `gh`-t NE hívj.

## 10. Review — Claude tölti ki

Link: `docs/reviews/e02-r09-review.md`

Kiemelt figyelem a review-nak: **eldobható próbateszt** a legacy referenciával
szemben az A2/A4 cellákra (ezek az élek csúsztak át korábban zöld gate mellett),
és **valódi-sértés próba** az A6 két számlálójára (ideiglenesen full-scan-re
rontva pirosra kell futnia).
