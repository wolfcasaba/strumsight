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

## 0.1 Brief-revízió — a paritás értelmezési tartománya (orchestrátor, 2026-07-31)

**Az implementer helyesen állt meg `stopped` jelzéssel: a hiba a briefben volt.**
Az eredeti §6/A1 „mikroszekundumra egzakt, tűrés nélküli" paritást követelt a
teljes 17 leckés korpuszon, miközben a bemenet a **µs-ra kvantált**
`CompiledPracticeTarget`. **Ez a kettő matematikailag összeegyeztethetetlen** —
nem implementációs hiba, hanem a brief ellentmondása.

### A mért gyökérok (az orchestrátor függetlenül reprodukálta)

A legacy `LessonScorer` **kerekítetlen `double` másodpercekkel** dönt
(`timeOf(e) = (countInBeats + e.beat) * 60.0/bpm`, `lesson_scorer.dart:241`), a
compiled target `time` mezője viszont **egész mikroszekundum** (ADR 0066/0072,
E02-R06 — már mergelt szerződés). Ahol `60/bpm` nem µs-reprezentálható — ami a
lecke-katalógus **döntő többsége** —, a két időalap **legfeljebb 0,5 µs**-ban
eltér, és ez pontosan a döntési határon válik meghatározóvá:

| Cella | Mért érték |
|---|---|
| `first-strums` (70 BPM), 1. cél | legacy `t = 3.4285714285714284 s` → compiled `3 428 571 µs`; `played = 3 148 571 µs`-nál a legacy eltérés **280 000,42857 µs > 280 ms → extra**, a matcheré pontosan **280 000 µs ≤ 280 ms → párosul** |
| `anthem-drive` (98 BPM), célesemény **`[5, 6]`** (beat 3,5 → 4,0), felezőpont **`4 744 898 µs`** | a matcher **egzakt holtversenyt** lát → a **korábbit** választja (P4); a legacy `double` eltérései nem egyenlők (**`153 061,265306`** vs **`153 061,183673 µs`**) → a **későbbit** választja |

> **Számjavítás (orchestrátor, 2026-07-31, R2):** ez a sor korábban a
> `153 061,408 / 153 061,041 µs` értékpárt írta, egy `[beat 0 → 0,5]` párra. **Az
> téves volt** — az `anthem-drive` mintája `[_d, null, _d, _u, null, _u, _d, _u]`,
> tehát a 0 → 0,5 pár **nem is létezik a leckében**; a referenciacellát egyenletes
> nyolcad-rácsból számoltam, nem a lecke tényleges eseménylistájából. Az
> implementer a §0.1 előírása szerint **`stopped`-dal jelezte a számeltérést,
> nem igazította hozzá csendben** — helyesen. A fenti értékek az újramért
> igazak. A jelenség nem egyedi: az `anthem-drive`-ban **négy** szomszédos
> célpár mutatja (`[5,6]`, `[8,9]`, `[13,14]`, `[21,22]`), tehát az A1c-hez
> bármelyik használható — a `[5,6]` a kanonikus.

### A döntés: a µs-kvantált időalap az igazság

A 0075-ös ADR §2b-ként rögzítve. Indoklás:

1. Az egész-tick/egész-µs időalap **mergelt, paritás-tesztelt szerződés**
   (ADR 0066 480 PPQ · ADR 0072 compiled target). Az 1. opció — „a nyers
   `double` az igazság" — két lezárt kört nyitna újra, és a `double`-t
   visszahozná a domainbe.
2. Az eltérés **felülről korlátos és nem felhasználó-látható**: 0,5 µs =
   a 44,1 kHz-es mintaidő **1/45-e**, a milliszekundum 1/2000-e.
3. **A parity-állítást NEM töröljük és NEM lazítjuk tűréssel.** Az
   összehasonlítás egzakt marad; azt a **tartományt** mondjuk ki pontosan, ahol
   a két rendszer egyáltalán összehasonlítható, a kizárt tartományt pedig
   **saját teszt pinneli ki** — nem elfedjük, hanem megnevezzük.

### Amiért ez nem „gyengítés"

A védősáv **levezetett, nem választott**. Ha `|t_legacy_µs − c_µs| ≤ 0,5`
(round-to-nearest), akkor minden célra `|d_legacy − d_matcher| ≤ 0,5 µs`, ezért:

- a **jogosultsági** döntés egyezik, ha `|d_matcher − matchWindow| ≥ 1 µs`;
- az **argmin** (P3/P4) egyezik, ha a két legkisebb matcher-oldali eltérés
  `≥ 2 µs`-ban különbözik (0,5 + 0,5 kerekítés, egészre felfelé);
- a **zárási** döntés egyezik, ha `|played − (target.time + matchWindow)| ≥ 1 µs`.

**Sávon kívül a paritás továbbra is bitre egzakt, tűrés nélkül.**

### Amit a §6 helyébe lép (A1 újrafogalmazva, A1b és A1c ÚJ)

**A1 (módosítva).** Változatlanul a **teljes 17 leckés korpusz × 3 latency**,
egzakt egyenlőség, `closeTo`/epszilon **továbbra is tilos** — de a
megfigyelés-generátor a fenti **védősávot betartja**, és ezt a harness
**állítással ellenőrzi** minden szcenárióra, nem véletlenül kerüli el.
*(A jelenlegi harness 51 szcenárióval, 0 µs eltéréssel zöld — de **véletlenül**,
mert nem érinti az éleket. Ez az implementer saját, helyes megfigyelése volt;
a sávot ezért ki kell mondani és le kell ellenőrizni.)* A harness **jelentse a
kizárt megfigyelések számát** — ha ez nem 0-hoz közeli, az `stopped`.

**A1b (ÚJ, kötelező mérés).** A 17 lecke **minden** eseményére mérd:
`max |legacy timeOf(e)·1e6 − compiled.time.inMicroseconds|`. Az elvárás
**≤ 0,5 µs**. Ez bizonyítja, hogy a két időalap között **kizárólag**
round-to-nearest kerekítés van. Ha nagyobb, az **BLOKKOLÓ** compiler-lelet
(nem tűréssel elfedendő) → `blocked` a mért számmal.

**A1c (ÚJ, a kizárt tartomány kipinnelése).** Reprodukáld **mindkét fenti
mért cellát** (`first-strums` határcella, `anthem-drive` holtverseny-cella), és
állítsd, hogy a matcher a **compiled egész-µs igazságot** követi (párosul,
illetve a korábbit választja) — a legacy `double`-tól **szándékosan** eltérve.
Így a divergencia megnevezett, őrzött viselkedés lesz: aki később „visszaigazítja"
a matchert a `double`-höz, annak ez pirosra fut.

**A2/A4 változatlan** — azok szintetikus, egzaktul µs-reprezentálható célokon
mérnek, ott az élek bitre tesztelhetők. A négy legacy-él kipinnelése tehát
**nem sérül**: az A1 kizárt sávja pontosan az a két cella, amit az A2/A4
szintetikus célon egzaktul mér.

### Ami NEM változik

A §3 scope, a §4 engedélyezett fájllista (**továbbra is négy fájl**, ötödik =
scope-sértés), a §5 kötött döntések, az A5–A9, és a §9 záró gate. A
`lib/features/learn/**` zárva marad.

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

> ⚠️ **A §0.1 brief-revízió MÓDOSÍTJA ezt a pontot** (értelmezési tartomány +
> védősáv), és **két új kötelező pontot ad**: **A1b** (a két időalap eltérésének
> mérése, `≤ 0,5 µs`) és **A1c** (a két mért divergencia-cella kipinnelése).
> Az alábbi szöveg a védősávon **kívül** érvényes, változatlanul.

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

### Összefoglaló

Az E02-R09 egy pure, determinisztikus, egy-az-egyhez `PracticeEventMatcher` domain
service-t ad. A matcher a compiled egész-µs időalapot tekinti igazságnak,
latency-korrigált `StrumObservation`-öket párosít, kurzorral zár, az opcionális
célt külön feloldással kezeli, az extrákat csak információként számolja, és nem
állít elő score-t vagy `PracticeVerdict`-et. Production hívó nincs; a legacy
Learn út változatlan.

A `CompiledPracticeTarget.events` nemcsökkenő időrendezése konstrukciós
előfeltétel. A compiler ezt garantálja. Kézzel épített, rendezetlen targetet a
matcher nem rendez át és nem validál futásidőben; a bináris alsó korlát és a
kurzor ilyen szerződéssértő bemeneten jogosult célt átugorhat.

### Fájlonkénti összefoglaló

- `lib/features/practice/domain/service/practice_event_matcher.dart` — új
  immutable eredménytípusok és a kurzoros matcher; P1–P9, opcionális feloldás,
  latency-korrekció, monoton `advance`, idempotens target-`finalize`, live
  unmodifiable eredménynézet, kumulatív vizsgálati és megtartott-rekord
  számlálók.
- `test/features/practice/domain/practice_event_matcher_test.dart` — A2–A6
  determinisztikus cellái: mindkét 280 ms-os predikátum, latency-mátrix,
  holtverseny és ±1 µs szomszédok, azonos idejű célok, rossz irány,
  extra/optional/one-to-one/finalize szemantika, valamint a két A6-mérés.
- `test/features/practice/domain/practice_event_matcher_parity_test.dart` —
  mind a 17 szállított lecke × 3 latency egzakt legacy-paritása; a három
  levezetett védősáv feltételenkénti állítása és kizárásszámláló; A1b teljes
  348 eseményes időalapmérés; A1c `first-strums[0]` és a kanonikus
  `anthem-drive[5,6]` divergencia.
- `test/property/practice_event_matcher_property_test.dart` — seedelt A7
  invariánsok, extra-özön és shuffled input; sikeres match non-vacuity őr,
  hívásonként legfeljebb egy target-feloldás, ismétlődő sequence baseline-ok.
- `docs/rounds/e02-r09-event-matcher.md` — kizárólag ez a §8 handoff.

### Acceptance criteria — bizonyíték

- **A1:** 17 lecke × 3 latency = **51 szcenárió**, összesen 1 017 generált
  observation-hívás. Minden megtartott observationre explicit állítás őrzi:
  eligibility-távolság ≥ 1 µs, két legközelebbi eltérés különbsége ≥ 2 µs,
  closing-távolság ≥ 1 µs. Mért maximum matcher–legacy eredményeltérés:
  **0 µs**; kizárt observation: **0**. A parity minden célra egzakt
  `expect`; `closeTo`/epszilon nincs.
- **A1b:** mind a **348** szállított esemény mérve. Maximum
  `|legacyUs − compiledUs|` = **0,48979591950774193 µs**
  (a tesztkimenetben 12 jegyre: `0.489795919508`), cella
  `anthem-drive[23]`, beat 15,5; elvárás `≤ 0,5 µs`.
- **A1c:** `first-strums[0]`: legacy target
  `3,4285714285714284 s`, compiled `3 428 571 µs`,
  `played=3 148 571 µs`; legacy delta
  `280 000,42857142835 µs` → extra, matcher delta pontosan
  `−280 000 µs` → párosul. `anthem-drive[5,6]`: beat 3,5/4,0,
  compiled `4 591 837 / 4 897 959 µs`, felezőpont
  `4 744 898 µs`; legacy delták
  `153 061,26530612208 / 153 061,18367346944 µs` → index 6,
  matcher `153 061 / 153 061 µs` → korábbi index 5.
- **A2:** `T+279 999 / 280 000 / 280 001 µs` mindhárom eligibility- és
  closing-cellája, plusz az advance utáni pontos határpárosítás kipinnelve.
- **A3:** `inputLatency ∈ {0, 40, 300 ms}` a match és close útvonalon; a
  teszt külön állítja, hogy 300 ms > 280 ms.
- **A4:** egész-µs szintetikus felezőpont, mindkét ±1 µs szomszéd, valamint
  azonos időnél a kisebb listaindex kipinnelve.
- **A5:** egy hívás legfeljebb egy célt old fel; cél nem párosul kétszer és
  nem nyílik újra; resolved count monoton; rossz irány is fogyaszt; extra nem
  változtat targetet; opcionális cél párosítható, kihagyva
  `optionalUnmatched`; `finalize` után minden cél lezárt.
- **A6:** 20 000 target + 1 000 strum után a kumulatív számláló
  **43 000 ≤ 1 344 000**; 4 target + 100 000 extra után a megtartott
  rekordok száma változatlanul **4**.
- **A7:** default `PROPERTY_SEED=42` és külön friss
  `PROPERTY_SEED=731031` mellett is **3/3** property zöld; double-match,
  reopen, monotonitás, finalize, extra-özön és shuffled order mérve.
- **A8:** analyzer: `No issues found!`; a practice suite domain-purity
  tesztje zöld; architecture:
  `Architecture dependencies OK (12 allowlisted deviation(s)).`; allowlist
  nem változott.
- **A9:** a `lib/` alatt kizárólag az új matcher van; nincs
  `lib/features/learn/**` diff, caller, provider vagy feature flag, ezért a
  production út viselkedése változatlan.

### Célzott ellenőrzések a záró gate előtt

- A változtatás előtti parity baseline:
  `/home/ubuntu/flutter/bin/flutter test test/features/practice/domain/practice_event_matcher_parity_test.dart -r expanded`
  → exit 0, **2/2**, `maximumDifferenceUs=0`.
- Az új A1/A1b/A1c első végrehajtása két egzakt double-állításnál piros lett,
  mert a teszt `target·1e6 − playedµs` műveleti sorrendet használta a legacy
  tényleges `(targetSec − playedSec)·1e6` sorrendje helyett. A képlet
  legacy-hű javítása után ugyanaz a célzott parancs → exit 0, **5/5**,
  A1 max 0 µs / excluded 0, A1b max 0,489795919508 µs.
- `/home/ubuntu/flutter/bin/flutter test test/features/practice/domain/practice_event_matcher_test.dart -r expanded`
  → exit 0, **17/17**; A6 `examined=43000`, `retained=4`.
- `PROPERTY_SEED=731031 /home/ubuntu/flutter/bin/flutter test test/property/practice_event_matcher_property_test.dart -r expanded`
  → exit 0, **3/3**.
- Egy első, bare `flutter test …` baseline-kísérlet exit 127-tel nem indult,
  mert a Flutter nincs a shell `PATH`-jában; a dokumentált
  `/home/ubuntu/flutter/bin/flutter` binárissal újrafuttatva zöld lett.

### Záró gate — teljes, csonkítatlan kimenet

Parancs (egyetlen hívás, csővezeték nélkül), exit code **0**:

```text
═══ [1] format
    $ /home/ubuntu/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool

Formatted 532 files (0 changed) in 1.85 seconds.

    → [1] format: ZÖLD

═══ [2] analyze
    $ /home/ubuntu/flutter/bin/flutter analyze lib/ test/ tool/

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (105.0.0 available)
  analyzer 12.1.0 (14.1.0 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  flutter_local_notifications 22.0.1 (22.2.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.1.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.2 available)
  hooks 2.0.2 (2.1.0 available)
  intl 0.20.2 (0.20.3 available)
  jni 1.0.0 (1.0.2 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  record_use 0.6.0 (1.0.0 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.27 available)
  synchronized 3.4.1 (3.4.1+1 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.1 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
32 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Analyzing 3 items...
No issues found! (ran in 2.8s)

    → [2] analyze: ZÖLD

═══ [3] test test/features/practice/
    $ /home/ubuntu/flutter/bin/flutter test test/features/practice/

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (105.0.0 available)
  analyzer 12.1.0 (14.1.0 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  flutter_local_notifications 22.0.1 (22.2.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.1.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.2 available)
  hooks 2.0.2 (2.1.0 available)
  intl 0.20.2 (0.20.3 available)
  jni 1.0.0 (1.0.2 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  record_use 0.6.0 (1.0.0 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.27 available)
  synchronized 3.4.1 (3.4.1+1 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.1 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
32 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/meter_test.dart
00:00 +0: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/meter_test.dart: Meter validation accepts 4/4, 3/4, and supported 6/8 meter
00:00 +1: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/meter_test.dart: Meter validation rejects beats-per-bar values outside 1 through 16
00:00 +2: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/meter_test.dart: Meter validation rejects unsupported beat units
00:00 +3: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/meter_test.dart: Meter validation aggregates independent field failures
00:00 +4: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/meter_test.dart: Meter tick arithmetic computes exact ticks per bar for supported meters
00:00 +5: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/meter_test.dart: Meter tick arithmetic fails fast symmetrically for every invalid input field
00:00 +6: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/meter_test.dart: Meter value semantics uses both fields as its value identity
00:00 +7: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_value_equality_test.dart: Practice value equality helpers compares lists structurally and hashes equal lists equally
00:00 +8: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_value_equality_test.dart: Practice value equality helpers compares maps structurally independent of insertion order
00:00 +9: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation accepts a complete valid definition
00:00 +10: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation aggregates definition fields and nested Tempo failures
00:00 +11: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation rejects a non-positive total duration
00:00 +12: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation requires a non-empty target list only for scored modes
00:00 +13: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation reports decreasing positions as unsorted
00:00 +14: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation reports duplicate event IDs independently of positions
00:00 +15: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation reports duplicate positions without treating them as unsorted
00:00 +16: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation rejects positions at and beyond the exclusive totalBeats bound
00:00 +17: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation passes nested event failures through unchanged
00:00 +18: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation enforces exact mode-to-weight-key compatibility
00:00 +19: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation displayTitle accepts null and non-blank text, rejects blank
00:00 +20: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition value semantics deeply compares lists and supports Set and Map keys
00:00 +21: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter forward conversion uses one final microsecond rounding step
00:01 +22: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter forward conversion exposes exact quarter-beat and meter-aware bar durations
00:01 +23: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter inverse conversion round-trips every 32-tick grid point over 64 quarter beats
00:01 +24: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter inverse conversion rejects negative elapsed time
00:01 +25: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter validation guards every conversion member rejects an invalid tempo
00:01 +26: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter validation guards every conversion member rejects an invalid meter
00:01 +27: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/domain_purity_test.dart: practice domain has no ambient IO, nondeterminism, or app imports
00:01 +28: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/domain_purity_test.dart: purity scan ignores forbidden spellings in comments and strings
00:01 +29: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/domain_purity_test.dart: purity scan recognizes root l10n and Riverpod imports
00:01 +30: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/domain_purity_test.dart: purity scan inspects executable string interpolation bodies
00:01 +31: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_test.dart: canonical practice chord labels accepts null and sharp-spelled major or minor labels
00:01 +32: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_test.dart: canonical practice chord labels rejects empty, no-chord, flat, extended, lowercase, and padded labels
00:01 +33: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation accepts scored events and a marker without scored attributes
00:01 +34: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation reports an empty ID with the pinned code literal
00:01 +35: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation rejects a zero duration with the pinned code literal
00:01 +36: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation requires a scored attribute on a non-marker event
00:01 +37: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation forbids scored attributes on marker events
00:01 +38: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation aggregates independent event failures
00:01 +39: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_test.dart: PracticeEvent value semantics supports structural equality, hashing, Set, and Map keys
00:02 +40: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/beat_position_test.dart: BeatPosition subdivisions uses 480 ticks per quarter-note beat
00:02 +41: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/beat_position_test.dart: BeatPosition subdivisions represents supported fractions with exact integer equality
00:02 +42: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge converts the current half-beat grid without deviation
00:02 +43: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge round-trips every supported deterministic subdivision position
00:02 +44: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge rounds one third of a beat to the nearest exact triplet tick
00:02 +45: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge rejects non-finite legacy input explicitly
00:02 +46: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/beat_position_test.dart: BeatPosition invariants rejects negative data-driven positions in every runtime path
00:02 +47: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/beat_position_test.dart: BeatPosition invariants keeps the const constructor guarded in checked builds
00:02 +48: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/beat_position_test.dart: BeatPosition value operations sorts deterministically and compareTo agrees with equality
00:02 +49: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/beat_position_test.dart: BeatPosition value operations adds and subtracts positions exactly
00:02 +50: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/beat_position_test.dart: BeatPosition value operations has a deterministic diagnostic representation
00:02 +51: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/tempo_test.dart: Tempo validation accepts the closed 30.0 through 300.0 BPM boundaries
00:02 +52: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/tempo_test.dart: Tempo validation reports finite values outside the range without clamping
00:02 +53: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/tempo_test.dart: Tempo validation reports NaN and infinities as not finite
00:02 +54: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/tempo_test.dart: Tempo value semantics uses BPM as its value identity
00:03 +55: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_validation_test.dart: PracticeValidationCode defines the complete stable code set
00:03 +56: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_validation_test.dart: PracticeValidationCode pins target compiler validation and failure codes
00:03 +57: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_validation_test.dart: PracticeValidationCode pins the five pre-existing codes at their producing boundaries
00:03 +58: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_validation_test.dart: PracticeValidationFailure has value semantics
00:03 +59: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_validation_test.dart: PracticeValidationFailure has a deterministic diagnostic representation
00:03 +60: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/compiled_practice_target_test.dart: Compiled practice target value models scalar models compare structurally and hash equal values equally
00:03 +61: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/compiled_practice_target_test.dart: Compiled practice target value models aggregate compares every list and scalar structurally
00:03 +62: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/compiled_practice_target_test.dart: Compiled practice target value models aggregate stores unmodifiable snapshots of every list
00:03 +63: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation accepts all closed range boundaries
00:03 +64: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation reports empty IDs and an invalid snapshot version
00:03 +65: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects count-in values outside zero through four
00:03 +66: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects loop counts outside one through 32
00:03 +67: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects input latency outside zero through 500 milliseconds
00:03 +68: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects visual latency outside zero through 500 milliseconds
00:03 +69: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation requires a strictly positive session timeout
00:03 +70: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation passes nested Tempo failures through unchanged
00:03 +71: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation aggregates at least three independent failures
00:03 +72: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig value semantics compares all fields and copyWith preserves or changes explicitly
00:04 +73: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation accepts a valid attempt and aggregates nested values
00:04 +74: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation rejects a negative attempt index
00:04 +75: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation rejects duplicate verdict target IDs
00:04 +76: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation compares the verdict list and all other fields structurally
00:04 +77: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation accepts a valid session with canonical coaching codes
00:04 +78: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation rejects an empty session ID and attempt list
00:04 +79: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation requires attempt indexes to be strictly increasing
00:04 +80: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation continues nested validation after an attempt ordering failure
00:04 +81: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation rejects negative active and paused durations
00:04 +82: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation rejects an unknown coaching-summary code
00:04 +83: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation aggregates attempt and highest-stable-tempo failures
00:04 +84: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation compares attempt and coaching lists structurally
00:04 +85: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts finalAttempt selects the greatest index independent of list order
00:04 +86: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts bestAttempt selects the greatest available overall score
00:04 +87: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts bestAttempt breaks score ties with the smaller index
00:04 +88: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts derived getters return null when no attempt is comparable
00:04 +89: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation accepts available score boundaries and explicit unavailable states
00:04 +90: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation reports non-finite values without a duplicate range failure
00:04 +91: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation rejects finite values outside zero through one
00:04 +92: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation requires an insufficient-data reason code
00:04 +93: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation accepts a valid metric set including signed timing bias
00:04 +94: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation passes nested metric failures through unchanged
00:04 +95: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects negative total target count
00:04 +96: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects resolved targets greater than total targets
00:04 +97: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects negative max combo and score points
00:04 +98: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects a negative mean absolute offset
00:04 +99: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_metrics_test.dart: Practice metric value semantics compares every MetricValue subtype by structure and subtype
00:04 +100: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_metrics_test.dart: Practice metric value semantics compares PracticeMetrics structurally
00:05 +101: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_enums_test.dart: PracticeMode stable codes pins every code, round-trips, and rejects unknown codes
00:05 +102: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_enums_test.dart: PracticeMode stable codes exposes the exact scored dimensions for each mode
00:05 +103: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_enums_test.dart: PracticeSource stable codes pins every code, round-trips, and rejects unknown codes
00:05 +104: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_enums_test.dart: PracticeDifficulty stable codes pins every code, round-trips, and rejects unknown codes
00:05 +105: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_enums_test.dart: PracticeScoreDimension stable codes pins every code, round-trips, and rejects unknown codes
00:05 +106: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_enums_test.dart: ExtraStrumPolicy stable codes pins every code, round-trips, and rejects unknown codes
00:05 +107: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_enums_test.dart: TimingGrade stable codes pins every code, round-trips, and rejects unknown codes
00:05 +108: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_enums_test.dart: PracticeAttemptOutcome stable codes pins every code, round-trips, and rejects unknown codes
00:05 +109: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_enums_test.dart: PracticeFinishReason stable codes pins every code, round-trips, and rejects unknown codes
00:06 +110: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation accepts a valid weighted profile and an empty weight map
00:06 +111: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation accepts closed threshold endpoints and equal positive windows
00:06 +112: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation pins the legacy Learn parity profile literals
00:06 +113: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation validates the four built-in non-strum profiles and pins literals
00:06 +114: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation built-in non-strum profile weights exactly match their mode scored dimensions
00:06 +115: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation reports an empty identifier with the pinned code literal
00:06 +116: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects zero and negative windows
00:06 +117: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects perfect greater than good and good greater than match
00:06 +118: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects weight sums of 99 and 101
00:06 +119: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects a negative weight independently of the exact sum
00:06 +120: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects thresholds outside the closed zero to 100 range
00:06 +121: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation aggregates independent failures in one call
00:06 +122: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile value semantics compares the weight map structurally and hashes it by value
00:13 +123: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target legacy baseline parity ten frozen scenarios match finish and every event within 1 us
00:13 +124: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target shipped-lesson parity pins all 17 lesson IDs in the measured order
00:13 +125: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target shipped-lesson parity all valid 50, 75 and 100 percent tempos match within 1 us
00:13 +126: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target shipped-lesson parity first-waltz explicitly measures the three-beat count-in edge
00:13 +127: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target shipped-lesson parity eighth-drive explicitly measures its closest-to-end event
00:13 +128: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target corpus invariants whole-bar rounding is a no-op for every pinned shipped ID
00:13 +129: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target corpus invariants eventless Analyze import keeps one positive 4/4 bar
00:13 +130: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation accepts closed confidence boundaries for both observation types
00:13 +131: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation rejects a negative timestamp
00:13 +132: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation rejects a negative strum sequence
00:13 +133: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation reports non-finite confidence without a duplicate range failure
00:13 +134: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation rejects finite confidence outside zero through one
00:13 +135: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation uses the canonical chord-label contract including null
00:13 +136: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_observation_test.dart: PracticeObservation value semantics compares each concrete subtype structurally
00:14 +137: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure rounds a partial 4/4 definition up to a complete final bar
00:14 +138: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure uses three quarter beats per 3/4 count-in and bar step
00:14 +139: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure pins two count-in bars and repeated-pass bar boundaries
00:14 +140: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure gives a downbeat event and its bar boundary the same time at 90 BPM
00:14 +141: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure computes total duration from all absolute ticks at 90 BPM
00:14 +142: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure compiles the final in-range tick instead of dropping it
00:14 +143: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure uses effective tempo at 50 and 75 percent without accumulation
00:14 +144: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure excludes markers while preserving a one-event target
00:14 +145: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure projects target metadata and every scored event field
00:14 +146: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure a marker-only scored definition compiles without scored events
00:14 +147: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops repeats every source event with absolute positions and loop indexes
00:14 +148: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops selects one source bar and rebases it before repeating
00:14 +149: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops accepts the rounded final partial bar as a whole-bar loop
00:14 +150: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops computes barIndex from ticksPerBar for multi-bar passes
00:14 +151: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops rejects invalid loop range Instance of 'PracticeLoopRange' without clamping
00:14 +152: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops rejects invalid loop range Instance of 'PracticeLoopRange' without clamping
00:14 +153: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops rejects invalid loop range Instance of 'PracticeLoopRange' without clamping
00:14 +154: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments matches the pinned legacy pre-roll and merges repeated labels
00:14 +155: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments uses the named 120-tick lookahead for a one-beat chord change
00:14 +156: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments returns no segments when no compiled event carries a chord
00:14 +157: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments extends one chord across the complete session timeline
00:14 +158: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments carries chord changes across a repeated loop boundary
00:14 +159: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order definition validation wins and rejects zero totalBeats
00:14 +160: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order config validation wins before definition ID mismatch
00:14 +161: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order definition ID mismatch wins before variation mismatch
00:14 +162: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order rejects a non-matching Easy variation explicitly
00:14 +163: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order variation mismatch wins before an invalid loop range
00:14 +164: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order accepts a matching non-null Easy variation ID
00:14 +165: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler empty and deterministic outputs compiles positive-length Free Practice without target events
00:14 +166: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler empty and deterministic outputs returns equal, hash-equal targets with nondecreasing event times
00:15 +167: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation accepts matched and unmatched consistent verdicts at score bounds
00:15 +168: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation reports an empty target event ID
00:15 +169: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation reports non-finite event score without a duplicate range failure
00:15 +170: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation rejects finite event scores outside zero through one
00:15 +171: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation rejects unmatched verdicts with observed time or matched grades
00:15 +172: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation accepts and pins all five canonical coaching codes
00:15 +173: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation rejects an unknown coaching code
00:15 +174: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict value semantics compares all scalar, enum, and nullable fields
00:16 +175: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity pins the complete 16 lesson catalog plus first-win
00:16 +176: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity keeps every compiled event within 0.5 us of legacy time
A1b measuredEvents=348 maximumTimebaseDifferenceUs=0.489795919508 cell=anthem-drive[23]
00:16 +177: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity pins the first-strums compiled eligibility divergence
00:16 +178: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity pins the anthem-drive [5, 6] compiled midpoint divergence
00:16 +179: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity matches every target exactly across all 51 latency scenarios
A1 parity scenarios=51 maximumDifferenceUs=0 excludedObservations=0
00:16 +180: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher eligibility and close boundaries pins all six cells around the 280 ms boundary
00:16 +181: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher eligibility and close boundaries exact boundary stays open and eligible after advance
00:16 +182: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher latency correction pins matching and closing for 0, 40 and 300 ms latency
00:16 +183: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher tie breaking midpoint and neighboring microseconds choose the pinned target
00:16 +184: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher tie breaking equal-time targets choose the smaller list index
00:16 +185: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution a wrong direction consumes the target before a correct retry
00:16 +186: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution an out-of-window extra leaves every target resolution unchanged
00:16 +187: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution one observation resolves at most one of two eligible targets
00:16 +188: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution a restarted gateway sequence can match a later target
00:16 +189: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution resolved count is monotonic and terminal results never reopen
00:16 +190: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution finalize separates required misses from unmatched optional targets
00:16 +191: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution an optional target remains matchable before its window closes
00:16 +192: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution finalize is idempotent
00:17 +193: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution signed offsets keep early negative and late positive
00:17 +194: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution an empty target is safe to match, advance, and finalize
00:17 +195: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher measured scaling 20k targets and 1k strums stay below the cursor threshold
A6 cursor examined=43000 threshold=1344000
00:17 +196: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher measured scaling 100k extras do not grow retained records beyond four targets
A6 memory retained=4 threshold=4
00:17 +197: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState initial state is idle and empty
00:17 +198: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState value equality: same fields → equal
00:17 +199: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState value equality: any field change → not equal
00:17 +200: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState copyWith: explicit overrides win; cleared fields go to null
00:17 +201: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState timelinePosition: formula holds for all five anchor combinations
00:17 +202: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState isActive: true for countIn/running/paused/finishing only
00:17 +203: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) idle → preparing
00:17 +204: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) preparing → permissionRequired | ready | failed
00:17 +205: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) permissionRequired → preparing | cancelled
00:17 +206: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) ready → countIn | cancelled
00:17 +207: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) countIn → running | paused | cancelled | failed
00:17 +208: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) running → paused | finishing | cancelled | failed
00:17 +209: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) paused → countIn | running | finishing | cancelled
00:17 +210: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) finishing → completed | failed
00:17 +211: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) completed → ready | idle
00:17 +212: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) cancelled → ready | idle
00:17 +213: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) failed → preparing | idle
00:17 +214: /home/ubuntu/ss-codex-e02-r09/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) every status has a transition entry
00:18 +215: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog contains exactly ten definitions in pinned ID order
00:18 +216: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog every definition validates with no failures
00:18 +217: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog definition IDs are globally unique
00:18 +218: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog all() returns the same order on repeated calls
00:18 +219: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog byId returns the pinned definition and null for unknown IDs
00:18 +220: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog byMode returns only definitions of the requested mode
00:18 +221: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog byDifficulty returns only definitions of the requested difficulty
00:18 +222: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog firstWaltz is 3/4 with twelve total beats on the quarter grid
00:18 +223: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog titleKey and descriptionKey follow the practiceCatalog regex
00:18 +224: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog free-practice template has no events and an open scoring profile
00:18 +225: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog strumPattern events carry no chord and chordChanges events do
00:18 +226: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog data layer purity source forbids ambient IO, randomness, framework, and l10n imports
00:18 +227: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog PracticeDefinition integrity event IDs are unique within every definition
00:18 +228: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog per-definition immutability events list rejects add() for every catalog definition
00:18 +229: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog per-definition immutability skillTags list rejects add() for every catalog definition
00:18 +230: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog chord-change bar grouping builtin.gToDChanges.v1 holds G for the first bar, D for the second
00:18 +231: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog chord-change bar grouping builtin.emToCChanges.v1 holds Em for the first bar, C for the second
00:18 +232: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 4/4 single-bar 8-slot pattern, 1 chord
00:18 +233: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 4/4 four-bar 8-slot pattern with up-strokes
00:18 +234: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 4/4 eight-bar full-eighth pattern
00:18 +235: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 3/4 six-slot pattern over four bars
00:18 +236: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events mixed rests pattern still expands correctly
00:18 +237: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events empty/whitespace name falls back to null displayTitle
00:18 +238: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — definition surface IDs, source, mode, profile match the ADR contract
00:18 +239: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects empty chords
00:18 +240: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects pattern length that does not fit the meter
00:18 +241: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects a pattern with only null slots
00:18 +242: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects bpm above the Tempo ceiling (400)
00:18 +243: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects bpm below the Tempo floor (10)
00:18 +244: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes none of the failure paths throws
00:18 +245: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/song_practice_adapter_test.dart: song_practice_adapter source guard forbidden to call Song.toLesson() — source-level scan
00:19 +246: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog catalog baseline: 16 curriculum + first-win
00:19 +247: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=first-strums matches every event slot exactly
00:19 +248: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=two-chord-change matches every event slot exactly
00:19 +249: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=eighth-drive matches every event slot exactly
00:19 +250: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=fifties-doo-wop matches every event slot exactly
00:19 +251: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=two-finger-frame matches every event slot exactly
00:19 +252: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=first-waltz matches every event slot exactly
00:19 +253: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=down-up-groove matches every event slot exactly
00:19 +254: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=folk-pattern matches every event slot exactly
00:19 +255: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=barre-groove matches every event slot exactly
00:19 +256: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=anthem-drive matches every event slot exactly
00:19 +257: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=rising-minor matches every event slot exactly
00:19 +258: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=waltz-time matches every event slot exactly
00:19 +259: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=reggae-skank matches every event slot exactly
00:19 +260: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=funk-chop matches every event slot exactly
00:19 +261: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=blues-shuffle matches every event slot exactly
00:19 +262: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=push-and-pull matches every event slot exactly
00:19 +263: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=first-win matches every event slot exactly
00:19 +264: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=first-strums easy variant mirrors simplified events
00:19 +265: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=two-chord-change easy variant mirrors simplified events
00:19 +266: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=eighth-drive easy variant mirrors simplified events
00:19 +267: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=fifties-doo-wop easy variant mirrors simplified events
00:19 +268: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=two-finger-frame easy variant mirrors simplified events
00:19 +269: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=first-waltz easy variant mirrors simplified events
00:19 +270: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=down-up-groove easy variant mirrors simplified events
00:19 +271: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=folk-pattern easy variant mirrors simplified events
00:19 +272: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=barre-groove easy variant mirrors simplified events
00:19 +273: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=anthem-drive easy variant mirrors simplified events
00:19 +274: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=rising-minor easy variant mirrors simplified events
00:19 +275: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=waltz-time easy variant mirrors simplified events
00:19 +276: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=reggae-skank easy variant mirrors simplified events
00:19 +277: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=funk-chop easy variant mirrors simplified events
00:19 +278: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=blues-shuffle easy variant mirrors simplified events
00:19 +279: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=push-and-pull easy variant mirrors simplified events
00:19 +280: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=first-win easy variant mirrors simplified events
00:19 +281: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency chord labels match legacyPracticeChordLabel for every event
00:19 +282: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency twoFingerFrame chords normalize to Em / C in order
00:19 +283: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency bluesShuffle chords normalize to A / D
00:19 +284: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency every chord in every lesson definition is canonical
00:19 +285: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency displayTitle carries the lesson name and falls back to null
00:19 +286: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — controlled failure modes returns Failure for empty events list
00:19 +287: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — controlled failure modes displayTitle trims whitespace and becomes null for empty name
00:19 +288: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — difficulty mapping preserves beginner, intermediate and advanced tiers
00:20 +289: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — determinism the same epoch day produces structurally equal definitions
00:20 +290: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — determinism consecutive epoch days produce different definitions
00:20 +291: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — determinism definition ID encodes the epoch day
00:20 +292: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling pattern longer than 8 slots is truncated to 8 events
00:20 +293: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling pattern shorter than 8 slots is preserved as-is
00:20 +294: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling every event has a null chord (strum-only)
00:20 +295: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling event positions are eighth-note slots starting at zero
00:20 +296: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — definition surface source, mode, keys, difficulty, profile match ADR contract
00:20 +297: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — definition surface custom bpm is honored when in range
00:20 +298: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes empty pattern is rejected
00:20 +299: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes bpm out of range is rejected
00:20 +300: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes non-finite bpm is rejected
00:20 +301: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes none of the failure paths throws
00:20 +302: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — displayTitle trims whitespace and falls back to null for empty names
00:21 +303: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for null input
00:21 +304: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for empty and whitespace-only labels
00:21 +305: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel passes canonical labels through unchanged
00:21 +306: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel reduces 7th / minor variants to their parent majmin
00:21 +307: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel rewrites flat roots to their sharp enharmonic
00:21 +308: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel drops the slash-bass of a slash chord
00:21 +309: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for unparseable roots
00:21 +310: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for empty after slash-bass removal
00:21 +311: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel trims surrounding whitespace before parsing
00:21 +312: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel every non-null output is canonical
00:21 +313: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — non-empty clip three strums with two chord lanes produce deterministic ticks
00:22 +314: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — non-empty clip preserves 3/4 meter on the resulting definition
00:22 +315: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — non-empty clip unordered strums come out sorted
00:22 +316: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=0 falls back to 90 BPM
00:22 +317: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=400 falls back to 90 BPM
00:22 +318: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=NaN falls back to 90 BPM
00:22 +319: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=80 is preserved
00:22 +320: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — tick collision forward-push two strums 0.0005s apart push the second onto the next tick
00:22 +321: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — empty strum list falls back to freePractice + open scoring + no events
00:22 +322: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — empty strum list all-non-finite strums are dropped, triggering empty-branch
00:22 +323: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — controlled failure modes blank sourceId is rejected
00:22 +324: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — controlled failure modes out-of-range beatsPerBar is rejected
00:22 +325: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — in-loop timeline grow totalBeats grows by one bar when rounding lands on the bound
00:22 +326: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — t0 normalization non-zero t0 normalizes times, and last tick at bound-1 keeps totalBeats at 4.0
00:22 +327: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — definition surface source, difficulty, keys, tags match ADR contract
00:22 +328: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 1: (-1,-1), timelineNow=0 → at=0, no log
00:22 +329: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 1: (-1,-1), timelineNow=10s → at=10s, no log
00:22 +330: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 2: (-1,0.5), timelineNow=0 → at=0, no log
00:22 +331: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 2: (-1,0.5), timelineNow=10s → at=10s, no log
00:22 +332: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 3: (1.0,-1), timelineNow=0 → at=0, no log
00:22 +333: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 3: (1.0,-1), timelineNow=10s → at=10s, no log
00:22 +334: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 4: (1.0,1.0), timelineNow=0 → at=0, no log
00:22 +335: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 4: (1.0,1.0), timelineNow=10s → at=10s, no log
00:22 +336: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 5: (1.0,1.10), timelineNow=0 → at=0, no log
00:22 +337: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 5: (1.0,1.10), timelineNow=10s → at=10s, no log
00:22 +338: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 6: (1.0,0.90), timelineNow=0 → at=0 (clamp), no log
00:22 +339: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 6: (1.0,0.90), timelineNow=10s → at=9.9s, no log
00:22 +340: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 7: (1.0,0.5001), timelineNow=0 → at=0 (clamp), no log
00:22 +341: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 7: (1.0,0.5001), timelineNow=10s → at=9.5001s, no log
00:22 +342: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 8: (1.0,0.50), timelineNow=0 → at=0 (lag nem levont), 1 warning
00:22 +343: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 8: (1.0,0.50), timelineNow=10s → at=10s (lag nem levont), 1 warning
00:22 +344: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 9: (1.0,0.4999), timelineNow=0 → at=0 (lag nem levont), 1 warning
00:22 +345: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 9: (1.0,0.4999), timelineNow=10s → at=10s (lag nem levont), 1 warning
00:22 +346: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.0 below threshold → no observation
00:22 +347: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.5499 below threshold → no observation
00:22 +348: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.55 exactly at threshold → observation emitted
00:22 +349: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.5501 above threshold → observation emitted
00:22 +350: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=1.0 maximum → observation emitted
00:22 +351: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix below-threshold strum advances dedup so the same seq does not re-emit
00:22 +352: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2b a lag hatóköre és a fajtánkénti padló (R2) de-jitter túléli a chord observationt (R0 PRÓBA-A)
00:22 +353: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2b a lag hatóköre és a fajtánkénti padló (R2) chord change-point nem kap idegen lagot (R0 PRÓBA-B, 300 ms)
00:22 +354: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2b a lag hatóköre és a fajtánkénti padló (R2) chord change-point nem kap idegen lagot (R2, 600 ms, határ fölött)
00:22 +355: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám változatlan timelineNow mellett a nagy lagú frame után a lag nélküli frame at-ja nem kisebb
00:22 +356: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám strumSeq 5→9 ugrás → observation sequence 0,1
00:22 +357: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám két küszöb feletti strum között egy küszöb alatti → sequence 0,1
00:23 +358: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám start → 3 strum → stop → start → 1 strum: utolsó sequence=0, at nem a régi lastEmittedAt-ra clampelve
00:23 +359: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix ugyanaz a label 10 frame-en belül → pontosan 1 ChordObservation
00:23 +360: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix label-váltás C → G → új observation
00:23 +361: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix akkord → nincs akkord → label:null observation is kiadódik
00:23 +362: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix nem kanonikus label a detektorból (Em7, G/B, H) → redukció, observation validate() üres
00:23 +363: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix változatlan label, de eltelt chordStableDuration → újramintavétel
00:23 +364: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix a Live úton a confidence mindig 1.0, és chordMinConfidence=0.99 SEM szűr chordot
00:23 +365: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus start ×2 → mindkettő Success, engine.startCalls == 1
00:23 +366: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus stop ×2 → mindkettő Success, engine.stopCalls == 1
00:23 +367: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus dispose után start/stop → Failure (gateway disposed)
00:23 +368: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus setExpectedChord → engine.expectedChordCalls utolsó eleme a label; stop után az utolsó elem null
00:23 +369: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus setExpectedChord a start előtt → sikeres start után az engine megkapja a labelt
00:23 +370: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés megtagadott engedély → Failure(PermissionFailure), engine.startCalls==0
00:23 +371: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés request() után granted → engine.startCalls==1
00:23 +372: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés érvénytelen config → Failure(configurationInvalid), engine.startCalls==0
00:23 +373: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés engine stream AudioFailure(audioSessionBusy) → stream hiba ugyanaz, engine.stopCalls==1, stream nem zárul be, újabb start sikerül
00:23 +374: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés engine stream StateError → AudioFailure(practiceObservationStreamFailed)
00:23 +375: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés a hiba után beküldött frame NEM ad observationt
00:23 +376: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.8 log-fegyelem 200 érvényes, observationt adó frame feldolgozása után a logger a start/stop páron kívül nem kap bejegyzést
00:23 +377: /home/ubuntu/ss-codex-e02-r09/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.8 log-fegyelem tíz, tartományon kívüli lagú frame ugyanabban a másodpercben → 1 warning
00:23 +378: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_observation_activation_test.dart: maps every practice session status to its capture decision
00:23 +379: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_observation_activation_test.dart: policy keys cover exactly the session status enum
00:23 +380: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_observation_activation_test.dart: paused disables capture and closes the chunk 014 pause gap
00:24 +381: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_catalog_controller_test.dart: practiceCatalogProvider returns the full built-in catalog in declaration order
00:24 +382: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_catalog_controller_test.dart: practiceCatalogProvider is backed by the BuiltinPracticeCatalog by default
00:24 +383: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_catalog_controller_test.dart: practiceCatalogProvider rewires when practiceCatalogRepositoryProvider is overridden
00:25 +384: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_timing_test.dart: pause / resume bookkeeping pause does not advance activeElapsed or playingElapsed
00:25 +385: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_timing_test.dart: pause / resume bookkeeping playingElapsed advances only while status == running
00:25 +386: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_timing_test.dart: daily goal — countInBars=2, 4/4, 120 BPM (§6.4) 4 beats playing + 10s pause + 2 bars resume = exact playingElapsed
00:25 +387: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_timing_test.dart: countInBars == 0 countIn → running happens immediately at active=0
00:25 +388: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_timing_test.dart: resume-anchor (§5.5, §0.1) pause at countInDuration + 2.5 bars → resume anchors at the 2nd musical bar boundary
00:25 +389: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_timing_test.dart: resume-anchor (§5.5, §0.1) pause EXACTLY on a bar boundary → anchor is that boundary
00:25 +390: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_timing_test.dart: resume-anchor (§5.5, §0.1) pause 1µs after a bar boundary → anchor is the SAME boundary
00:25 +391: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_timing_test.dart: 3/4 meter (§0.1) resume count-in is 3 beats long, not 4
00:25 +392: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_timing_test.dart: 3/4 meter (§0.1) count-in click effects: initial count-in emits meter.beatsPerBar clicks
00:25 +393: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_timing_test.dart: RestartAttempt (§0.1) full second attempt: timelineBase=0, activeBase==activeElapsed, playingElapsed=0, wallElapsed continues
00:25 +394: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_timing_test.dart: session timeout (§5.6, §6.4) wallElapsed > sessionTimeout → finishing + timedOut
00:25 +395: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_timing_test.dart: session timeout (§5.6, §6.4) timeout wins over completedTimeline when both conditions met
00:25 +396: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_timing_test.dart: 0.5 practice speed (§0.1) halving effectiveTempo halves the bar boundaries — playingElapsed matches real time, not timeline time
00:25 +397: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_timing_test.dart: count-in click batching (§5.7) a single big ClockAdvanced spanning the whole count-in emits all click effects in order, no duplicates
00:25 +398: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_timing_test.dart: pause during count-in (§0.1) a single PausePractice during count-in freezes countInElapsed
00:25 +399: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_timing_test.dart: double pause/resume in same bar (§0.1) two consecutive pause/resume cycles preserve the timeline
00:25 +400: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_timing_test.dart: §6.1 purity guardrails (file-content checks) reducer does not define its own beat-to-time formula (no `bpm` or `60` literal)
00:26 +401: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_review_probes_test.dart: P1: permissionRequired + PreparationSucceeded is rejected
00:26 +402: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_review_probes_test.dart: P1b: permissionRequired + PreparationFailed is rejected
00:26 +403: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_review_probes_test.dart: P2: 2-bar initial count-in (4/4, 120 BPM) emits 8 clicks
00:26 +404: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_review_probes_test.dart: P3: timeout beats completedTimeline when both conditions hold
00:26 +405: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_review_probes_test.dart: P4: paused past sessionTimeout → finishing + timedOut
00:26 +406: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_review_probes_test.dart: P5: second attempt timelinePosition starts at Duration.zero
00:26 +407: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_review_probes_test.dart: P6: timelinePosition can exceed totalDuration, status is no longer running
00:26 +408: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_review_probes_test.dart: R1 MAJOR-3: statusPath walks every adjacent edge through allowedTransitions
00:26 +409: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_review_probes_test.dart: StartPractice sets countInSpanBeats = countInBars * beatsPerBar (R1 MAJOR-4)
00:26 +410: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig uses the brief defaults
00:26 +411: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig has value equality
00:26 +412: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig validates every confidence and duration boundary
00:26 +413: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig invalid config is represented by configuration.invalid
00:26 +414: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway keeps start and stop idempotent
00:26 +415: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway records expected chord and exposes a controllable stream
00:26 +416: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway returns the injected start result
00:26 +417: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway rejects operations after dispose
00:27 +418: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_reducer_test.dart: happy path: idle → preparing → ready → countIn → running → finishing → completed
00:27 +419: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_reducer_test.dart: permission path: preparing → permissionRequired → preparing → ready
00:27 +420: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_reducer_test.dart: pause/resume: the resume count-in actually runs
00:27 +421: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_reducer_test.dart: pause during count-in is accepted
00:27 +422: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_reducer_test.dart: cancel before start: ready → cancelled
00:27 +423: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_reducer_test.dart: cancel during running: running → cancelled
00:27 +424: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_reducer_test.dart: failure and retry: preparing → failed → preparing
00:27 +425: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_reducer_test.dart: double start: the second StartPractice is rejected; state unchanged
00:27 +426: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_reducer_test.dart: double finish: the second FinishPractice is rejected
00:27 +427: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_reducer_test.dart: restart attempt: paused → countIn, attemptIndex +1, attemptElapsed 0
00:27 +428: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_reducer_test.dart: background interruption: PausePractice(PauseCause.interruption) preserves the cause on the state
00:27 +429: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_reducer_test.dart: exhaustive transition matrix every (status, input) pair matches the pinned table
00:27 +430: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_reducer_test.dart: exhaustive transition matrix rejected transitions return the input state by value
00:27 +431: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_reducer_test.dart: exhaustive transition matrix reducer never throws on any (status, input) pair
00:27 +432: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_reducer_test.dart: rejection carries from / input / code; never throws
00:27 +433: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_reducer_test.dart: StartPractice is rejected when target is null
00:27 +434: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_reducer_test.dart: ChangeTempoBeforeAttempt updates config.effectiveTempo and invalidates target
00:27 +435: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_reducer_test.dart: §6.1 source-purity guardrails reducer does not define its own beat-to-time formula (no bare `bpm` identifier, no `60` literal in arithmetic)
00:27 +436: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_reducer_test.dart: §6.1 source-purity guardrails reducer source does not contain DateTime.now, Stopwatch, Random, print
00:27 +437: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_reducer_test.dart: §6.1 source-purity guardrails reducer / command / effect files do not import Flutter or Riverpod
00:27 +438: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock now() before any start() returns zero in every field
00:27 +439: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock start() places the clock in a fresh session state
00:27 +440: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock start() is idempotent: repeated start() does not throw or distort
00:27 +441: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock active + paused == wall invariant holds after pause and resume
00:27 +442: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock pause() while paused is a no-op (state-machine fields unchanged)
00:27 +443: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock resume() while running is a no-op (state-machine fields unchanged)
00:27 +444: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock resetAttempt() zeros attempt; paused unchanged; wall/active unchanged
00:27 +445: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock start() while paused restarts the session fresh
00:27 +446: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock now() before any start() returns zero in every field
00:27 +447: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() places the clock in a fresh session state
00:27 +448: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() is idempotent: repeated start() does not throw or distort
00:27 +449: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock active + paused == wall invariant holds after pause and resume
00:27 +450: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock pause() while paused is a no-op (state-machine fields unchanged)
00:27 +451: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resume() while running is a no-op (state-machine fields unchanged)
00:27 +452: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resetAttempt() zeros attempt; paused unchanged; wall/active unchanged
00:27 +453: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() while paused restarts the session fresh
00:27 +454: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock advance() grows wall by the delta while running
00:27 +455: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock advance() while paused grows wall AND paused; active stays put
00:27 +456: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock advance() after resume resumes active growth from the resume point
00:27 +457: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resetAttempt() after an active session only zeros attempt
00:27 +458: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() after pause resets the clock fully
00:27 +459: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock pause() before start() is a no-op (no fields change)
00:27 +460: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resetAttempt() before start() is a no-op
00:27 +461: /home/ubuntu/ss-codex-e02-r09/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock active + paused == wall invariant holds across 200 random steps
00:28 +462: All tests passed!

    → [3] test test/features/practice/: ZÖLD

═══ [4] test test/property/practice_event_matcher_property_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/property/practice_event_matcher_property_test.dart

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (105.0.0 available)
  analyzer 12.1.0 (14.1.0 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  flutter_local_notifications 22.0.1 (22.2.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.1.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.2 available)
  hooks 2.0.2 (2.1.0 available)
  intl 0.20.2 (0.20.3 available)
  jni 1.0.0 (1.0.2 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  record_use 0.6.0 (1.0.0 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.27 available)
  synchronized 3.4.1 (3.4.1+1 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.1 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
32 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-codex-e02-r09/test/property/practice_event_matcher_property_test.dart
PROPERTY_SEED=42
00:00 +0: PracticeEventMatcher randomized invariants no double match, reopen, or resolved-count regression
00:00 +1: PracticeEventMatcher randomized invariants random extra-strum floods leave every target resolution unchanged
00:00 +2: PracticeEventMatcher randomized invariants the same observation set stays safe when shuffled
00:00 +3: All tests passed!

    → [4] test test/property/practice_event_matcher_property_test.dart: ZÖLD

═══ [5] architecture
    $ /home/ubuntu/flutter/bin/dart run tool/check_architecture.dart

Running build hooks...Running build hooks...Architecture dependencies OK (12 allowlisted deviation(s)).

    → [5] architecture: ZÖLD

═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/features/practice/                               zöld
    test test/property/practice_event_matcher_property_test.dart zöld
    architecture                                               zöld

MINDEN GATE ZÖLD. A teljes suite + randomizált property gate + APK a CI-ban
fut (ADR 0053) — azt az orchestrátor indítja, te ne hívj gh-t.
```

### Eltérések, nem futtatott ellenőrzések, kockázatok és follow-upok

- Az elfogadott brief/ADR viselkedésétől nincs eltérés. Az explicit
  `git push origin HEAD` a folytató user-utasításból következik; `gh`-t az
  implementer nem hív.
- Lokálisan nem futott teljes `flutter test`, teljes randomizált CI property
  gate vagy release APK: ezeket ADR 0053 szerint az orchestrátor dispatch-eli
  a branchre. Android SDK ezen a boxon nincs.
- NOTE E02-R11-hez: `finalize()` target-feloldásra idempotens, de utána egy
  `registerStrum()` extraként növeli az `extraStrumCount`-ot. A controller
  finish után állítsa le az observation-fogyasztást, vagy dokumentálja ezt a
  terminális hívási szerződést.
- Shuffled delivery nem dob és nem nyit újra célt, de eltérő assignmentet
  adhat, mint a rendezett stream; ez az ADR 0075 §3 szerinti viselkedés.
  Legacy-paritás rendezett bemenetre értendő.
- Pontos következő SDD-kör: **E02-R10 — Timing, direction és chord scorer**.

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
