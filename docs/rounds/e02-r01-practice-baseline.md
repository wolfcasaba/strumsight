# E02-R01 — Practice baseline, ADR-ek és rollout-guardok

Státusz: PLANNING (kód olvasva: `main` @ `90c0996`, 2026-07-30)
SDD: `docs/sdd/03-epic-02-practice-engine.md` § „Kör 1 — Practice baseline, ADR és feature flag"
Branch: `codex/epic-02-round-01-practice-baseline`
Brief szerzője: Claude · Implementáció: Codex
**Előfeltétel: Epic 1 lezárva (E01-R16 / PR #21 merge-ölve).** Ez az Epic 2 NYITÓ köre.

## 1. Cél

Az Epic 2 nem üres lapon indul: a StrumSightnak MA van működő, valódi gitáron
elfogadott play-along útja (`LearnScreen` + `LessonScorer`), és az Epic 2 ezt
fogja körönként kiváltani. Ez a kör három dolgot rögzít, **egyetlen sor
production-viselkedésváltozás nélkül**:

1. **rollout-guard** — három availability flag az Epic 1 config-rendszerében,
   fail-closed függőségi validációval, hogy a V2 motor a későbbi körökben
   biztonságosan, kikapcsolt production mellett épülhessen;
2. **parity-alap** — a MAI scorer viselkedésének befagyasztott, gépi
   fixture-készlete, amihez a V2 scorer (E02-R09/R10) mérhető lesz;
3. **baseline-jelentés** — a kiinduló állapot mért leírása (konstansok, séma,
   felelősségek, tesztlefedettség, ismert rések), hogy az Epic minden későbbi
   köre tudja, mihez képest változik valami.

A kör kimenete nem működő funkció, hanem **mérce**. Ha az Epic 2 közepén valaki
azt kérdezi, hogy „ez most jobb vagy rosszabb lett, mint a régi?", ennek a
körnek a fixture-készlete adja a választ.

## 2. Jelenlegi állapot

Mért tények, `main` @ `90c0996` (2026-07-30) olvasása alapján.

### 2.1 Config és feature flagek

- `lib/app/config/feature_flags.dart:10-66` — ma **három** flag:
  `accountEnabled`, `diagnosticsEnabled`, `labModeAvailable`. A
  `FeatureFlags.forEnvironment` (`:26-36`) származtatja a per-környezet
  alapokat (`nonProd` ⇒ diagnostics + lab ON, production ⇒ OFF), a
  `usesNetwork` getter (`:49`) `accountEnabled || diagnosticsEnabled`.
  A doc-comment expliciten rögzíti, hogy a diagnosztikához **szándékosan
  nincs** production-ba erőltető define.
- `lib/app/config/app_config.dart:100-163` — `AppConfig.resolve` egy
  `problems` listát tölt (`:108`) és MINDEN sértett szabályt jelent, nem az
  elsőnél dob (`:153`). Ma három szabályblokk: hálózati URL-validáció
  (`:111-134`), production diagnostics-token (`:136-144`), production Lab
  (`:146-151`).
- **Közvetlen `const FeatureFlags(...)` hívóhelyek — 7 db, mind tesztben:**
  `test/app/app_config_test.dart:116,131,146,161,185`,
  `test/app/app_bootstrap_test.dart:203`,
  `test/features/diagnostics/diagnostics_providers_test.dart:24`.
  ⇒ **kötelezően default-tal ellátott opcionális mezők**, különben mind a hét
  helyen kompilációs hiba keletkezik, és a kör diffje a flagek helyett a
  tesztek átírásáról fog szólni.
- `FeatureFlags.forEnvironment` hívóhelyek: `app_config.dart:179` (a
  teszt-default provider), `app_bootstrap.dart:49`, plusz három teszt.

### 2.2 A mai scorer — a befagyasztandó viselkedés

`lib/features/learn/lesson_scorer.dart` (344 sor, pure Dart, se clock, se IO):

| Konstans | Érték | Hely |
|---|---|---|
| match window (±) | `0.28 s` | `:79` |
| perfect window (±) | `0.05 s` | `:80` |
| good window (±) | `0.12 s` | `:81` |
| count-in (default) | `4` beat | `:78` — a képernyő felülírja, lásd 2.4 |
| chord-lag tolerancia | `0.37 s` | `:117` (`_chordLagSec`) |
| pontok perfect/good/off-beat | `100 / 70 / 40` | `:137-139` |
| combo-szorzó tierek | 5 ⇒ ×2, 10 ⇒ ×3, 20 ⇒ ×4 | `:142-148` |
| pass-küszöb | `accuracy >= 0.7` | `:164,169` |
| Easy-javaslat | `failStreak >= 4` | `:160-161` |

Viselkedési tények:

- **Extra strum nem büntet:** ha nincs nyitott event a `windowSec`-en belül,
  `registerStrum` `null`-t ad, a combo és a pontszám érintetlen (`:261`).
- **Egy observation ⇒ egy event:** a legközelebbi, még nyitott eventhez
  párosít, majd `matched = true` (`:253-262`). Holtverseny esetén a
  ciklus SORRENDJE dönt (a korábbi event nyer, mert `d < bestDelta` szigorú).
- **A miss-zárás a KORRIGÁLT órán fut:** `advance()` a
  `elapsedSec - inputLatencySec` időt használja (`:296-311`), ezért egy
  ütemre játszott, mikrofon-késéssel érkező strum eventje annyival tovább
  marad nyitva.
- **A chord másodlagos számláló:** `chordHits/chordTotal`, a strum-verdictet
  soha nem gátolja; egy slot akkor jó, ha a célakkord szólt az ütéskor VAGY
  `_chordLagSec` múlva (`:228-231`). Csak change-pointokat tárol (`:199-204`).
- **`finalize()`** minden nyitott eventet missre zár és minden akkordot
  kiértékel (`:314-322`).

### 2.3 A mai tartalommodell

`lib/features/learn/model/lesson.dart` (415 sor):

- `LessonEvent.beat` **`double`** (`:20`), nyolcad-felbontás: a pattern-expander
  `bar * beatsPerBar + slot * 0.5` pozíciókat ad (`:93`), a pattern hossza
  kötelezően `beatsPerBar * 2` (assert, `:81-85`) — vagyis a mai modellbe a
  `8 slot/bar` feltevés bele van égetve (SDD Ch3 §9.3 tiltja a jövőre).
- `Lesson.simplified` (Easy-vágás) **`double` egyenlőségre épít**:
  `e.beat % 1.0 == 0` (`:109`) — pontosan az a minta, amit az ADR 0066
  tick-modellje kivált.
- **16 tantervi lecke** (`:321-338`) + a tantervben kívüli `firstWin` (`:146`).
  Ebből **kettő 3/4** (`firstWaltz:205`, `waltzTime:268`), a többi 4/4.
- Külső források: `Lessons.fromAnalyze` (`:361-390`) és
  `Lessons.fromDailyChallenge` (`:401-414`).

`lib/features/learn/lesson_timing.dart` (86 sor, pure): `playhead` (`:15`),
`countInNumber` (`:30`), `isFinished` = `playhead >= totalBeats + beatsPerBar`
(egy bar ring-out, `:37`), `beatsCrossed` (`:46`) a metronómhoz.

### 2.4 A képernyő felelősségei (SDD Ch3 §3.2 listája — MÉRVE, MIND IGAZ)

`lib/features/learn/screens/learn_screen.dart` — **839 sor**, egyetlen
`StatefulWidget`, amely egyszerre birtokolja: `Ticker` (`:49`), `Metronome`
(`:50`), backing playback, scorer-lifecycle (`:76,218,248`), frame-subscription
(`:224`), expected-chord hint (`:115-123`), haptika (`:188`), burst-animáció,
progress+streak mentés (`:284,312`), navigáció, dinamikus nehézség (`:595`),
UI-state.

Két, a baseline szempontjából fontos mért részlet:

- **A count-in egy bar:** `_countInBeats => _lesson.beatsPerBar` (`:47`) —
  tehát 4/4-nél 4, 3/4-nél 3, NEM a scorer `countInBeats = 4` defaultja.
  A fixture-öknek ezt kell használniuk, különben nem a valódi utat mérik.
- **A frame de-jitter a KÉPERNYŐN van, nem a scorerben** (`:169-182`): a
  `frame.engineTimeSec - frame.latestStrumTime` lag levonása, `lag > 0 &&
  lag < 0.5` korláttal. A scorer csak a már korrigált időbélyeget kapja.
- **`_pause()` (`:232-237`) NEM zárja a mikrofon-subscriptiont, és az
  `_onFrame` (`:163-206`) nem néz `_playing` flaget** — szünet alatt érkező
  strum tehát MA is pontozódik, a befagyott `_elapsedSec` időbélyegen, és az
  `observeChord` is fut. Ez pontosan az a rés, amit az SDD Ch3 §6.1 („pause
  alatt ne pontozzon és ne számoljon aktív időt") előír megszüntetni.
- `_restart()` (`:239-271`) friss scorert épít, `_prevPlayhead`-et
  `-countInBeats`-re állítja, törli a burstöket és a multiplier-emléket.

### 2.5 Perzisztencia (V1)

- `lib/features/progress/model/practice_entry.dart` — a V1 séma:
  `day` (epoch day), `src` (`live|analyze|learn`, `:7`), `sec`, `str`, `chd`,
  opcionális `dir` (0..1 direction-accuracy). Ismeretlen `src` szándékosan
  `live`-ra esik vissza a rekord eldobása helyett (`:63-66`).
- `lib/features/progress/data/practice_log_repository.dart` — cap
  **400 bejegyzés** (`:20`), `RecordOrder.newestLast` (`:48`), a verziózott
  `JsonCollectionStore`-on (ADR 0054).
- `lib/features/learn/providers/practice_speed_provider.dart` — a practice-speed
  opciók **`[0.5, 0.75, 1.0]`**, default `1.0` (`:12-13`); off-grid értéket soha
  nem perzisztál.

### 2.6 Tesztlefedettség és ami már kész

- Meglévő tesztfájlok: `test/features/learn` **28**, `test/features/progress`
  **5**, `test/features/streak` **5**, `test/features/metronome` **3**.
  A körhöz közvetlenül kapcsolódók: `lesson_scorer_test.dart`,
  `scorer_latency_test.dart`, `live_scoring_jitter_test.dart`,
  `lesson_timing_test.dart`, `waltz_count_in_test.dart`,
  `visual_offset_test.dart`, `dynamic_difficulty_test.dart`,
  `expected_chord_hint_test.dart`, `lesson_from_analyze_test.dart`.
- **Már kész, NEM e kör dolga:** az SDD Kör 1 §1.1 első tétele
  (`docs/sdd/03-epic-02-practice-engine.md`) létezik.
- **Nincs `lib/features/practice/`** — a mai `practice_*` fájlnevek a
  Progress és a Learn feature-höz tartoznak.
- `docs/baseline/` ma egyetlen fájlt tartalmaz (`epic-01-start.md`), az a
  szerkezeti minta a kör jelentéséhez.
- **ADR-számozás:** az SDD Kör 1 §1.1 a `0005/0006/0007` neveket javasolja, de a
  repóban `0001–0004` és `0050–0064` foglalt. Az Epic-2 sorozat **0065**-tel
  folytatódik; a három ADR-t **Claude már megírta és e brieffel együtt
  commitolja** (lásd §5).

## 3. Scope

**Benne (Codex):**

- **§3.1 Feature flagek.** Három új availability flag a `FeatureFlags`-ben
  (`practiceEngineV2Enabled`, `migratedLearnEnabled`,
  `practiceDetailedHistoryEnabled`), per-környezet defaultokkal a
  `forEnvironment`-ben, plusz két fail-closed függőségi szabály az
  `AppConfig.resolve`-ban. Részletek és kötött értékek: §5.
- **§3.2 Baseline fixture-készlet.** A mai `LessonScorer` viselkedésének
  befagyasztása: (a) megosztott, újrahasznosítható forgatókönyv-definíciók
  test-support kódban, (b) egy **generált, majd befagyasztott** JSON golden,
  (c) egy replay-teszt, amely a forgatókönyveket lefuttatja a mai scoreren és
  bitre a goldenhez hasonlítja.
- **§3.3 Baseline-jelentés.** `docs/baseline/epic-02-practice-start.md` az SDD
  Kör 1 §1.4 tartalmi listájával (lecke-szám, scoring-konstansok, speed-opciók,
  progress-séma, log-cap, képernyő-felelősségek, kapcsolódó tesztek, ismert
  valódi-eszközös viselkedés + ismert rések).

**Kívül (ebben a körben TILOS):**

- **Bármilyen production viselkedésváltozás.** `lib/features/learn/**`,
  `lib/features/progress/**`, `lib/features/streak/**` egyetlen sora sem
  módosulhat. Ha a baseline felvétele hibát talál: **MEGÁLLÁS és jelentés**
  (ADR 0067 §6), nem javítás.
- `lib/features/practice/**` — nincs V2 kód ebben a körben (az R02-vel indul).
- Meglévő teszt átírása, gyengítése vagy törlése. Ha egy meglévő teszt pirosra
  vált: **MEGÁLLÁS és jelentés.**
- DSP/ML paraméter, modell-bináris, `docs/rag/chunks/` (AGENTS.md §9).
- Új package, code generation (SDD Ch3 §26/8–9).
- `docs/adr/**` — a három ADR Claude-oldalon már megírva (§5).
- `HANDOFF.md`, `README.md`, `.github/**`, `backend/**`, `ml/**` — Claude-oldal
  ill. scope-on kívül.
- Új route, UI, ARB-kulcs — a Practice Hub az R12 köre.

## 4. Engedélyezett fájlok

Csak az alábbi útvonalak módosíthatók. Bármi más → **MEGÁLLÁS és jelentés**.

| Útvonal | Miért |
|---|---|
| `lib/app/config/feature_flags.dart` | §3.1 — a három új availability flag + `forEnvironment` defaultok |
| `lib/app/config/app_config.dart` | §3.1 — a két fail-closed függőségi szabály a `resolve()` `problems` listájába |
| `test/app/app_config_test.dart` | §3.1 — az új szabályok tesztjei (a meglévő állítások NEM gyengíthetők) |
| `test/support/practice_baseline_scenarios.dart` | ÚJ — §3.2 (a) megosztott forgatókönyv-definíciók |
| `test/fixtures/practice/legacy_scorer_baseline.json` | ÚJ — §3.2 (b) a befagyasztott golden |
| `test/features/learn/legacy_scorer_baseline_test.dart` | ÚJ — §3.2 (c) replay + freeze teszt |
| `docs/baseline/epic-02-practice-start.md` | ÚJ — §3.3 a baseline-jelentés |
| `docs/rounds/e02-r01-practice-baseline.md` | **kizárólag a 10. szekció** |

Ha a golden generálásához egyszeri segédszkript kell, az legyen a
baseline-teszt fájlján BELÜL egy `dart test --name` -nel futtatható,
kikommentelt/`skip`-elt generátor-eset — **ne** kerüljön új fájl a `tool/`-ba
(a `tool/` a `check_architecture.dart` területe, és a §12 gate futtatja).

**Tilos zóna:** minden más — kiemelten `lib/features/**` (MIND),
`lib/core/**`, `docs/adr/**`, `HANDOFF.md`, `README.md`, `.github/**`,
`tool/**`, `backend/**`, `ml/**`, és minden meglévő tesztfájl a fenti egy
kivétellel.

## 5. Kötött architekturális döntések

Ezeket a kör NEM tervezheti újra. Az ADR-eket Claude megírta és e brieffel
együtt commitolja — **a Codex ne hozzon létre `docs/adr/` fájlt**:

- [ADR 0065](../adr/0065-practice-engine-v2-parallel-rollout.md) — párhuzamos V2 + flagek
- [ADR 0066](../adr/0066-practice-tick-time-model.md) — 480 PPQ tick időmodell (R02-ben valósul meg)
- [ADR 0067](../adr/0067-practice-gradual-learn-migration.md) — fokozatos Learn-migráció, parity-szerződés

Ebből a körre kötelezően érvényes:

1. **A három flag opcionális, default-tal ellátott konstruktor-paraméter.**
   A hét meglévő `const FeatureFlags(...)` hívóhely (§2.1) érintetlenül
   fordul. Az `==`/`hashCode`/`toString` bővül a három mezővel.
2. **Kötött defaultok a `forEnvironment`-ben:**

   | Flag | dev / lab | production |
   |---|---|---|
   | `practiceEngineV2Enabled` | `true` | `false` |
   | `migratedLearnEnabled` | `false` | `false` |
   | `practiceDetailedHistoryEnabled` | `true` | `false` |

   A `migratedLearnEnabled` MINDEN környezetben `false` — a bekapcsolása az
   ADR 0067 §4 négy feltételéhez kötött, külön döntés.
3. **Nincs új `--dart-define`** ebben a körben (ADR 0065 §3 indoklása).
4. **Két fail-closed függőségi szabály** az `AppConfig.resolve`-ban, a meglévő
   `problems`-mintát követve (nem az elsőnél dobva, hanem a listába gyűjtve):
   `migratedLearnEnabled ⇒ practiceEngineV2Enabled` és
   `practiceDetailedHistoryEnabled ⇒ practiceEngineV2Enabled`.
   A hibaüzenet mondja meg, melyik flag hiányzik — ne csak azt, hogy „invalid".
5. **A `usesNetwork` NEM változik.** Mindhárom practice-flag bekapcsolva sem
   tehet igazzá hálózati igényt (ADR 0001, SDD Ch3 §23) — ezt teszt állítja.
6. **A golden RÖGZÍT, nem előír.** A JSON a mai kódból generálódik, majd
   befagy. Ha egy forgatókönyv meglepő eredményt ad, az a jelentésbe kerül
   (§10) és a baseline-jelentés „ismert rés" szakaszába — **a scorer nem
   módosul, és a golden nem lesz „szebbre" írva**.
7. **A tudottan hibás viselkedést NEM fagyasztjuk goldenbe.** A §2.4 pause-rése
   (szünet alatt is pontoz) a baseline-jelentésben ismert résként dokumentálandó,
   a záró körre hivatkozva — de NEM kaphat zöld assertiont, mert akkor a
   későbbi javítás teszt-átírásnak látszana (ADR 0067 §5).
8. **A forgatókönyvek a VALÓDI utat mérik:** count-in = `lesson.beatsPerBar`
   (§2.4), nem a scorer 4-es defaultja; a de-jitter a képernyő dolga, ezért a
   forgatókönyv már korrigált időbélyeget ad a scorernek, és ezt a tény a
   jelentésben szerepel (a de-jitter szabályt a meglévő
   `live_scoring_jitter_test.dart` fedi).

### 5.1 A kötelező forgatókönyv-készlet (SDD Kör 1 §1.3)

Legalább az alábbi, **determinisztikus** (fix lecke, fix BPM, fix offsetek,
semmi random, semmi wall-clock) esetek, mindegyik nevesített ID-val:

| ID | Tartalom |
|---|---|
| `p44_basic_all_perfect` | 4/4 negyedes downstroke-lecke, minden ütés a célidőn |
| `p44_all_late` | ugyanaz, minden ütés a `good` sávon KÍVÜL, de a match windowon belül késve |
| `p44_timing_tiers` | eseményenként külön offset, amely mind a négy sávot érinti: perfect (≤50 ms), good (≤120 ms), early/late (≤280 ms) és missed (>280 ms) — a határértékeken is |
| `p44_wrong_direction` | jó időben, rossz irányban játszott ütések (combo-nullázás + `expectedDirection`) |
| `p44_extra_strums` | a célok között extra ütések (nem büntetnek, a combo nem szakad) |
| `p44_chord_lag` | a célakkord csak az ütés UTÁN, a 370 ms-os lag-ablakon belül válik felismerhetővé |
| `p44_input_latency` | `inputLatencySec = 0.08`, minden detektálás ennyivel későn érkezik ⇒ perfect marad |
| `p44_dejittered` | a képernyő de-jitter korrekciója UTÁNI időbélyegek (a korrekció maga a képernyőn van, §5/8) |
| `p34_waltz` | `firstWaltz` (3/4), count-in = 3 beat, vegyes találatok |

A golden minden forgatókönyvre rögzítse a végállapotot: `hits`, `wrong`,
`missed`, `combo`, `maxCombo`, `total`, `perfect`, `score`, `multiplier`,
`chordHits`, `chordTotal`, `accuracy`, `passed`, `failStreak`, valamint az
eseményenkénti verdict-sorozatot (event-index → `HitResult` + `Timing`), mert
az összesített szám önmagában két különböző hibát egyformán mutatna.

## 6. Acceptance criteria

- [ ] `FeatureFlags` a három új mezővel; **a hét meglévő
      `const FeatureFlags(...)` hívóhely változatlanul fordul** (a diffben nem
      szerepelnek).
- [ ] A §5/2 default-tábla mindhárom környezetre teszttel bizonyítva
      (development, lab, production).
- [ ] Mindkét függőségi szabály **valódi-sértés próbával** bizonyítva: a
      megsértő konfigra `AppConfig.resolve` `ConfigurationException`-t dob, a
      `problems` üzenete megnevezi a hiányzó flaget; a szabályos konfig átmegy.
- [ ] Teszt állítja, hogy mindhárom practice-flag ON mellett
      `usesNetwork == false`, és hogy az `AppConfig.resolve` ilyenkor NEM
      követel URL-t (offline-garancia, §5/5).
- [ ] `test/fixtures/practice/legacy_scorer_baseline.json` létezik, tartalmazza
      a §5.1 mind a kilenc forgatókönyvét, és a replay-teszt zöld.
- [ ] A golden bizonyítottan **érzékeny**: egy ideiglenesen elrontott
      forgatókönyv-offset (pl. +10 ms) pirosra viszi a replay-tesztet — a
      kimenet a §10-ben dokumentálva, majd visszavonva.
- [ ] A forgatókönyv-definíciók a `test/support/`-ban élnek és a leckétől
      függetlenül újrahasználhatók (a V2 scorer későbbi körben ugyanezt a
      listát fogja replayelni) — a fájl doc-commentje ezt kimondja.
- [ ] **`git diff --stat` a §4 listán kívül semmit nem érint**, és
      `lib/features/**` egyáltalán nem szerepel benne.
- [ ] A meglévő tesztek zöldek maradnak: `test/features/learn`,
      `test/features/progress`, `test/features/streak`,
      `test/features/metronome`, `test/app` (§7).
- [ ] `docs/baseline/epic-02-practice-start.md` tartalmazza az SDD Kör 1 §1.4
      minden tételét, a §2 minden számát **fájl:sor hivatkozással**, és külön
      „ismert rések" szakaszt (benne a §2.4 pause-rés).

## 7. Kötelező ellenőrzések

Külön parancsokként (`AGENTS.md` §12 — **soha ne láncold `&&`-del**, és
`analyze` + `test` soha nem egy hívásban):

```bash
~/flutter/bin/flutter pub get
```
```bash
~/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool
```
```bash
~/flutter/bin/flutter analyze lib/ test/ tool/
```
```bash
~/flutter/bin/flutter test test/app
```
```bash
~/flutter/bin/flutter test test/features/learn
```
```bash
~/flutter/bin/flutter test test/features/progress
```
```bash
~/flutter/bin/flutter test test/features/streak
```
```bash
~/flutter/bin/flutter test test/features/metronome
```
```bash
~/flutter/bin/dart run tool/check_architecture.dart
```

A teljes suite + randomizált property gate + APK a CI-ban
([ADR 0052](../adr/0052-ci-apk-automerge-session-per-round.md) /
[ADR 0053](../adr/0053-ci-full-test-suite.md)). **A `gh` hívás,
a CI-dispatch, a PR és a merge Claude-oldal** (ADR 0064) — a Codex ne
futtasson `gh`-t.

## 8. Implementációs sorrend

1. Flagek: `feature_flags.dart` (opcionális mezők + `forEnvironment` defaultok
   + `==`/`hashCode`/`toString`), majd `app_config.dart` két új szabálya.
   Tesztek `test/app/app_config_test.dart`-ban, köztük a valódi-sértés próba és
   az offline (`usesNetwork == false`) állítás. → `flutter test test/app` zöld.
2. Forgatókönyv-definíciók (`test/support/practice_baseline_scenarios.dart`):
   pure adatszerkezet — lecke, BPM, count-in, `inputLatencySec`, a strum-
   események (idő + irány) és a chord-observationök listája. Semmi Flutter,
   semmi random, semmi `DateTime.now()`.
3. Replay-teszt, GENERÁTOR módban: futtatja a forgatókönyveket, kiírja a JSON-t.
   A kiírt fájl átnézése (a számok józansági ellenőrzése a §2.2 konstansokkal),
   **majd befagyasztás** — innentől a teszt csak összehasonlít.
4. Érzékenység-próba: egy offset ideiglenes elrontása ⇒ piros; visszaállítás ⇒ zöld.
   A kimenet a §10-be.
5. Baseline-jelentés megírása (a §2 mért adataiból + ami a fixture-készítés
   közben derült ki).
6. `format` → `analyze` → a §7 célzott tesztek → `check_architecture` — külön
   hívásokként; a §10 kitöltése a TÉNYLEGES kimenetekkel.
7. Kör-jelzés: `tools/codex-signal.sh done|stopped|blocked` (AGENTS.md §15.2).

## 9. Kockázatok

- **A flag-bővítés hét hívóhelyet érint.** Ha a mezők kötelezőként kerülnek be,
  a kör diffje azonnal átcsúszik hat tesztfájlra, amelyekből öt a §4 tiltott
  zónájában van. A default-os megoldás (§5/1) nem stílus-preferencia, hanem
  a scope megtartásának feltétele.
- **A golden „megszépítésének" csábítása.** A mai scorer szándékosan
  aszimmetrikus döntéseket hoz (extra strum nem büntet; a chord csak
  másodlagos; holtversenynél a korábbi event nyer). Ha egy szám furcsán néz ki,
  az akkor is a baseline — a javítás külön kör, külön ADR (ADR 0067 §3).
- **Meglévő teszt eltörése.** A `test/app/app_config_test.dart` bővül; a
  `test/features/**` tesztek NEM módosíthatók. Ha egy közülük pirosra vált, az
  azt jelenti, hogy a flag-változás mégis viselkedést érintett ⇒ megállás.
- **A de-jitter és a pause a képernyőn van, nem a scorerben.** Aki ezt nem
  méri fel, olyan fixture-t ír, amely nem a valódi utat rögzíti. A §5/8 és a
  §2.4 ezért mért, sorszámozott hivatkozás.
- **Determinizmus.** A forgatókönyvek nem használhatnak wall-clockot,
  randomot, `Ticker`-t. A JSON kulcsrendezése is legyen determinisztikus,
  különben a golden diffje minden futáson zajos lesz.
- **Nagy dokumentumdiff.** A baseline-jelentés hosszú lesz; a review-ban a
  mérce az, hogy minden állítása visszakereshető `fájl:sor` hivatkozás — a
  „kb. ennyi lecke van" típusú mondat MAJOR.

## 10. Implementation handoff — a Codex tölti ki

_(üres — a Codex tölti ki: fájlonkénti összefoglaló, futtatott parancsok a
TÉNYLEGES kimenettel, az érzékenység-próba piros/zöld kimenete, eltérések a
tervtől és okuk, nem futtatott ellenőrzések és okuk, follow-up leletek.)_

## 11. Review — a Claude tölti ki

Link: `docs/reviews/e02-r01-review.md`
