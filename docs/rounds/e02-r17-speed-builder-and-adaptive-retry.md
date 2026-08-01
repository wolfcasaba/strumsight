# E02-R17 — Speed Builder, loop és adaptív retry

- **Státusz:** **PLANNING** (pre-flight 2026-08-01, kód újramérve: `main` @ `caca3a9`;
  előre megírva 2026-07-31 `ce8fbce` ellen). **Implementer: MiniMax M3** (pipeline-döntés).
- **SDD-kör:** [`docs/sdd/03-epic-02-practice-engine.md`](../sdd/03-epic-02-practice-engine.md) **„Kör 17"** (+ §18, §19, §16.7)
- **Branch:** `codex/e02-r17-speed-builder`
- **Előfeltétel:** **E02-R11 és E02-R14 merge-ölve** (attempt-lánc + session UI).
- **ADR:** **0083** — `docs/adr/0083-speed-builder-and-adaptive-policy.md`,
  **az orchestrátor írja meg a pre-flightban** a §5 tartalmával.
- **Implementer motor:** a pre-flightban a user dönt. *Ajánlás:* **Codex** — a
  policy-állapotgép élei (streak-nullázás, alsó/felső korlát, „stabil BPM")
  ítéletigényesek.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ)**
> 1. Olvasd újra az R11 controller attempt-kezelését (`attemptIndex`,
>    `RestartAttempt`, `ChangeTempoBeforeAttempt`) — a policy ide illeszkedik.
> 2. Ellenőrizd az R10 aggregátor pass-mezőit (completion / overall / rhythm),
>    mert a step-up küszöb ezekre hivatkozik.
> 3. ADR-szám ütközés ellenőrzése, majd az ADR 0083 megírása.
> 4. Státusz → PLANNING, dátum/sha frissítés, brief commit a kör-branchre.

## 0.0 Pre-flight brief-revízió (2026-08-01, orchestrátor — MÉRT)

A `main` a brief megírása óta mozdult (`ce8fbce` → `caca3a9`, R15/R16 merge).
Az összes hivatkozott enum, mező és sorszám újramérve; egy **materiális
pontosítás** kell, mert az eredeti §5.6 megfogalmazás félrevezető és a kör
legfontosabb hamis-állítás kockázatát érinti.

**MÉRT ELLENTMONDÁS.** A §5.6 azt írja: „a step-up küszöb **a profilból jön**
(SDD §16.7)". Mérve viszont:
- A `ScoringProfile` (`scoring_profile.dart`) `completionThresholdPercent`/
  `overallThresholdPercent` mezői **85 / 70** — ez a **plain** scored-practice
  pass, amely a `PracticeAttemptOutcome.passed`-et adja
  (`practice_score_aggregator.dart:267-270`).
- A `ScoringProfile` **NEM** tartalmaz `0.95 / 0.85 / 0.80` értéket, és **nincs
  külön rhythm-threshold** mezője.
- Az SDD §16.7 a „Speed Builder step-up"-ot **külön blokkban** rögzíti:
  `completion ≥ 0.95 ∧ overall ≥ 0.85 ∧ rhythm ≥ 0.80 (ha alkalmazható)`.

**FELOLDÁS (kötelező, ez felülírja a §5.6 „a profilból jön" megfogalmazását;
a döntés az [ADR 0083](../adr/0083-speed-builder-and-adaptive-policy.md) §3):**

1. A Speed Builder **step-up pass** predikátuma **KÜLÖN** a plain
   `outcome == passed`-tól, és **tilos** onnan levezetni vagy a
   `ScoringProfile`-ból kiolvasni.
2. A step-up pass a `PracticeAttemptResult.metrics`-ből számol, `MetricValue`
   típusokkal (`practice_metrics.dart`):
   - `completion` **`MetricAvailable`** ∧ `value ≥ 0.95`, **és**
   - `overall` **`MetricAvailable`** ∧ `value ≥ 0.85`, **és**
   - `rhythm`: **`MetricAvailable`** → `value ≥ 0.80` kötelező;
     **`MetricNotApplicable`** → a feltétel **kimarad** (ez az „ha alkalmazható");
     **`MetricInsufficientData`** → **nem** step-up pass.
   - `completion` vagy `overall` nem `MetricAvailable` → **nem** step-up pass.
3. A `0.95 / 0.85 / 0.80` konstansok **EGY** helyen élnek a Speed Builder
   domainben (nevesített konstans a policyben/engine-ben), a SDD §16.7 forrással
   — nem a `ScoringProfile`-ban, nem három widgetben.
4. Az A2–A6 táblák „pass/fail" címkéi ezt a **step-up pass** fogalmat jelentik;
   a tesztek olyan `PracticeAttemptResult`-okat állítanak elő, amelyek metrikái
   a 0.95/0.85/0.80 határ két oldalán vannak.

Ez a felülírás a kör **még nem merge-elt** artefaktumát érinti (ADR 0087 §2
autonómia); nem nyúl merge-elt ADR-hez, lezárt körhöz vagy tilos zónához.

## 0. Kör-jelzés — KÖTELEZŐ (AGENTS.md §15.2)

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done    "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélküli kör = bukott kör. `gh`-t NE hívj, ne pusholj, PR-t ne nyiss.
**STOP-klauzula:** listán kívüli fájl, vagy ellentmondó előírás → `stopped`.
**A §7 a terved.**

## 1. Cél

A **tempóépítés**: több attemptes, determinisztikus workflow, amely a
teljesítmény alapján lépteti a BPM-et — és az **adaptív javaslat**, amely
attempt UTÁN, a felhasználó elfogadásával változtat a nehézségen.

A kör tétje a **determinizmus és a kiszámíthatóság**: a felhasználó soha nem
találkozhat azzal, hogy a tempó vagy a cél menet közben, magától megváltozott.

## 2. Jelenlegi állapot (mért tények, `main` @ `ce8fbce`)

- **Nincs Speed Builder semmilyen formában** (mérve: `grep -rni "speedbuilder\|speed_builder" lib/`
  → 0 találat). Az SDD §8.1 `speed_builder_policy.dart`-ot ír elő a
  `domain/model/` alatt — ez a fájl **nem létezik**.
- **Van viszont attempt-fogalom:** `PracticeAttemptResult` (98 sor,
  `index`, `tempo`, `metrics`, `verdicts`, `outcome`), és a session
  `attemptIndex` mezője + a `RestartAttempt` / `ChangeTempoBeforeAttempt`
  parancsok (R07).
- **`Tempo`** (R02): **30–300 BPM zárt tartomány**, clamp nélküli, lista-szintű
  validációval. A Speed Builder egyetlen BPM-értéke sem eshet ezen kívül.
- **Loop:** a `PracticeSessionConfig` és a compiled target (R06) **már kezeli**
  a loopot (loop-rebase, `loopIndex` a cél-eseményeken). Ez a kör a **loop-
  számlálót** és annak megjelenítését adja hozzá, nem a loop-mechanikát.
- **Legacy adaptív jel:** a `LessonScorer.failStreak` + `suggestsEasier`
  (`suggestEasyAfter = 4`, 154–161. sor) — a legacy Learn **attempt közben**
  ajánl Easy módot. A V2 ezt **nem** másolja: SDD §18.1 szerint aktív attempt
  közben nem változtatunk.
- **Legacy „practice speed":** `practiceSpeedProvider`
  (`lib/features/learn/providers/practice_speed_provider.dart`) — a Learn
  lassítója; a V2-ben ennek megfelelője a Speed Builder és a config-BPM.

## 3. Scope

**Benne:** a `SpeedBuilderPolicy` modell + validáció, a determinisztikus
policy-állapotgép, a „legmagasabb stabil BPM" definíciója, az adaptív javaslat-
policy, a loop-számláló, és a session-UI progress-blokkja.

**Kívül (ebben a körben TILOS):**

- A Result-képernyő Speed Builder összegzése (Kör 18) — az **adatot** ez a kör
  állítja elő, a megjelenítést a session-UI-ban.
- Coaching-mondatok (Kör 18), progress/streak (Kör 19).
- A scorerek, a matcher, a compiler, a reducer **viselkedésének** módosítása.
- `lib/features/learn/**` (a legacy `failStreak` marad, ahogy van).
- Új ADR, `docs/sdd/**`, `HANDOFF.md`, `.github/**`, DSP.

## 4. Engedélyezett fájlok

| Útvonal | Új? | Miért |
|---|---|---|
| `lib/features/practice/domain/model/speed_builder_policy.dart` | **ÚJ** | konfiguráció + validáció (SDD §8.1 szerinti hely) |
| `lib/features/practice/domain/model/speed_builder_state.dart` | **ÚJ** | immutable állapot (aktuális BPM, streakek, attempt-történet, stabil BPM) |
| `lib/features/practice/domain/service/speed_builder_engine.dart` | **ÚJ** | pure állapotgép: `(state, attemptResult) → state` |
| `lib/features/practice/domain/service/adaptive_practice_policy.dart` | **ÚJ** | pure javaslat-policy (SDD §18.3 interfész) |
| `lib/features/practice/presentation/widgets/speed_builder_progress.dart` | **ÚJ** | progress-blokk a session-UI-ban |
| `lib/features/practice/presentation/widgets/adaptive_suggestion_banner.dart` | **ÚJ** | javaslat-banner elfogadás/elutasítás úttal |
| `lib/features/practice/presentation/screens/practice_session_screen.dart` | — | **CSAK** a két widget becsatolása |
| `lib/l10n/app_en.arb` · `lib/l10n/app_hu.arb` | — | új kulcsok mindkét nyelven |
| `test/features/practice/domain/speed_builder_policy_test.dart` | **ÚJ** | A1 validációs mátrix |
| `test/features/practice/domain/speed_builder_engine_test.dart` | **ÚJ** | A2–A6 |
| `test/features/practice/domain/adaptive_practice_policy_test.dart` | **ÚJ** | A7 |
| `test/features/practice/presentation/speed_builder_progress_test.dart` | **ÚJ** | A8–A9 |
| `test/property/speed_builder_property_test.dart` | **ÚJ** | A10 |
| `docs/rounds/e02-r17-speed-builder-and-adaptive-retry.md` | — | **CSAK a §10** |

**Tilos zóna:** minden más, nevezetesen `lib/features/practice/application/**`
(a controller bekötése **nem** ebben a körben történik, lásd §5.8),
`data/**`, `lib/features/learn/**`, `docs/adr/**`.

**Új fájl a listán kívül = scope-sértés** → `stopped`.

## 5. Kötött döntések (ADR 0083 — NEM tárgyalhatók)

1. **A policy pure és determinisztikus.** `(state, attemptResult) → state`;
   nincs benne óra, random, IO vagy Riverpod. Azonos bemenet-sorozatra azonos
   kimenet, minden futásban.
2. **Konfiguráció és validáció** (SDD §19.1):
   `startBpm` pozitív és `Tempo`-érvényes; `targetBpm >= startBpm` és
   `Tempo`-érvényes; `stepBpm` **1..20** (zárt); `maxAttempts` **1..100**
   (zárt); `requiredConsecutivePasses >= 1`; `reduceAfterConsecutiveFails >= 1`.
   A validáció **stabil kódokat** ad (`PracticeValidationFailure`), a meglévő
   R03-as mintát követve.
3. **Léptetési szabályok** (SDD §19.2):
   - pass → `successStreak++`, `failStreak = 0`;
   - `successStreak >= requiredConsecutivePasses` → BPM `+= stepBpm`, és a
     `successStreak` **nullázódik**;
   - fail → `failStreak++`, `successStreak = 0`;
   - `failStreak >= reduceAfterConsecutiveFails` → BPM `−= stepBpm`, és a
     `failStreak` **nullázódik**;
   - a BPM **soha nem megy** `startBpm` alá és `targetBpm` fölé (mindkettő
     zárt korlát);
   - `targetBpm`-en elért `requiredConsecutivePasses` → **completed**;
   - `maxAttempts` elérése vagy user-finish → a session lezárul.
4. **BPM csak attempt-határon változik.** A policy kimenete a **következő**
   attempt tempója; futó attempt tempóját semmi nem módosíthatja.
5. **„Legmagasabb stabil BPM"** (SDD §19.3): az a legnagyobb tempó, amelyen a
   felhasználó **teljesítette a step-up pass-politikát**, azaz **legalább
   `requiredConsecutivePasses` egymást követő** passt ért el azon a tempón.
   **Egyetlen szerencsés attempt nem számít stabilnak** — ez az invariáns, nem
   opció.
6. **A step-up küszöb a profilból jön** (SDD §16.7), nem szétszórt konstansból:
   `completion >= 0.95` **és** `overall >= 0.85` **és** — ha alkalmazható —
   `rhythm >= 0.80`. A „ha alkalmazható" azt jelenti: **nem elérhető** rhythm
   dimenzió esetén a feltétel **kimarad**, nem bukik el.
7. **Adaptáció csak attempt UTÁN és csak elfogadással.** A policy **javaslatot**
   ad; a változás **kizárólag** a felhasználó explicit elfogadására történik
   (vagy előre bekapcsolt auto-policyvel). Attempt közbeni csendes változtatás
   TILOS.
8. **A controller bekötése NEM ebben a körben van.** A policy és az állapot
   pure; a `PracticeSessionController`-be kötést az **E02-R18** vagy egy
   dedikált javító kör végzi el, hogy ez a kör tisztán mérhető maradjon.
   A session-UI a widgetjeit **injektált** állapottal rendereli.
9. **A javaslat-prioritás rögzített** (SDD §18.2 sorrendje szerint), és
   holtversenynél determinisztikus: azonos erősségű javaslatnál a **listasorrend**
   dönt, nem a `Map` iteráció.

## 6. Acceptance criteria

### A1 — Validációs mátrix (három cella minden határon)

| Mező | alatta | **rajta** | fölötte |
|---|---|---|---|
| `stepBpm` | **0 → hiba** | **1 → OK** | 20 → OK, **21 → hiba** |
| `maxAttempts` | **0 → hiba** | **1 → OK** | 100 → OK, **101 → hiba** |
| `startBpm` | 29 → hiba | **30 → OK** | 300 → OK, 301 → hiba |
| `targetBpm` vs `startBpm` | `target < start` → hiba | **`target == start` → OK** | `target > start` → OK |

Minden hiba **stabil kóddal**; a validáció **minden** független problémát
visszaad (nem az elsőnél áll meg) — ez az R03 óta a ház szabálya.

### A2 — Két pass → step-up

`start = 80`, `target = 120`, `step = 10`, `requiredConsecutivePasses = 2`:

| Attempt | Eredmény | BPM a következő attemptre | `successStreak` |
|---|---|---|---|
| 1 | pass | 80 | 1 |
| 2 | pass | **90** | **0** |
| 3 | pass | 90 | 1 |
| 4 | fail | 90 | 0 |
| 5 | pass | 90 | 1 |

***Pirosra fogja:*** a step-up utáni streak-nullázás elmaradása (minden további
pass újabb lépést adna).

### A3 — Fail-streak és step-down, alsó korláttal

`start = 80`, `reduceAfterConsecutiveFails = 2`:

| Attempt | Eredmény | BPM |
|---|---|---|
| 1 (BPM 90) | fail | 90 |
| 2 (BPM 90) | fail | **80** |
| 3 (BPM 80) | fail | 80 |
| 4 (BPM 80) | fail | **80** (nem megy `startBpm` alá) |

Plusz felső korlát: `target = 120`-on két pass → a BPM **120 marad**, nem 130.

### A4 — Target completion

`target`-en elért `requiredConsecutivePasses` egymást követő pass → az állapot
**completed**, és **nincs** további BPM-emelés. Egy pass a targeten (kettő
kellene) → **nem** completed.

### A5 — Max attempt és user-finish

- `maxAttempts = 3`: a harmadik attempt után az állapot lezárt, és a negyedik
  eredmény **nem** változtatja meg (idempotens, nem dob).
- User-finish bármikor: az addigi attempt-történet **megmarad**, a stabil BPM
  a §5.5 szerint számolódik.

### A6 — „Legmagasabb stabil BPM" mátrix

`requiredConsecutivePasses = 2`:

| Attempt-sorozat (BPM/eredmény) | Elvárt stabil BPM |
|---|---|
| 80 pass, 80 pass, 90 pass, 90 fail | **80** |
| 80 pass, 80 pass, 90 pass, 90 pass | **90** |
| 80 pass, 90 pass (egy-egy) | **nincs** (`null` / `InsufficientData`) |
| 80 pass, 80 fail, 80 pass, 80 pass | **80** |

***Pirosra fogja:*** a „legmagasabb BPM, amin volt egy pass" definíció — ez a
kör legfontosabb hamis-állítás kockázata.

### A7 — Adaptív javaslat: prioritás és determinizmus

- Ugyanarra a bemenetre **mindig ugyanaz** a javaslat (kétszer lefuttatva).
- Prioritás-mátrix legalább négy cellával: nincs elég jel → alacsony
  completion → domináns early/late bias → direction-hiba. A magasabb prioritású
  ok jelenlétében a policy **azt** adja vissza.
- **Aktív attempt közben a policy nem hívható** — ha mégis (hibás integráció),
  a szerződés szerint `null`-t ad, nem javaslatot (a hívó oldali védelem az
  R18/bekötés dolga, de a policy maga nem javasolhat futó attemptre).

### A8 — Progress-blokk (session UI)

A widget mutatja: aktuális BPM · target BPM · sikeres attempt-streak ·
következő lépés · attempt-szám · legmagasabb stabil BPM (ha nincs: lokalizált
„még nincs" szöveg, **nem** 0 BPM).

### A9 — A javaslat sosem hat magától

A banner **elfogadás** akciója pontosan **egy** parancsot ad ki (fake
hívásnapló); az **elutasítás** **nullát**; a banner megjelenése önmagában
**nullát**.

***Pirosra fogja:*** az „auto-apply" implementáció — ez a felhasználó alól
húzná ki a tempót.

### A10 — Randomizált property gate

`test/property/speed_builder_property_test.dart`, `PROPERTY_SEED` (hiány → 42),
véletlen pass/fail sorozatokra:

1. a BPM **mindig** `[startBpm, targetBpm]` intervallumban van;
2. a BPM két egymást követő állapot között **legfeljebb egy** `stepBpm`-mel
   változik;
3. a stabil BPM **soha nem nagyobb** a valaha elért legnagyobb BPM-nél;
4. az attempt-történet hossza **soha nem lép túl** `maxAttempts`-en;
5. az állapotgép **soha nem dob** kivételt, tetszőleges (akár érvénytelen
   sorrendű) eredmény-sorozatra sem.

### A11 — Domain-tisztaság és scope

`domain_purity_test.dart` zöld; architecture gate zöld; `git diff --stat` a §4
listáján belül; `application/`, `data/`, `lib/features/learn/` **0 sor**.

## 7. Implementációs sorrend (ez a TERVED)

1. Olvasd el: ADR 0083, `practice_attempt_result.dart`, `tempo.dart`,
   `practice_validation.dart` (kód-minta), az R10 aggregátor pass-mezői.
2. `speed_builder_policy.dart` + A1 mátrix.
3. `speed_builder_state.dart` (immutable, value-equal).
4. `speed_builder_engine.dart` — A2, A3, A4, A5 sorrendben.
5. Stabil BPM (§5.5) + A6.
6. `adaptive_practice_policy.dart` + A7.
7. Widgetek (A8, A9), ARB mindkét nyelven.
8. Property (A10).
9. Záró gate (§9), majd a §10 kitöltése.

## 8. Kockázatok

- **A „stabil BPM" félreértése.** A legkönnyebb (és leghamisabb) definíció a
  „legmagasabb BPM egy passzal". Az A6 harmadik cellája pontosan ezt buktatja.
- **Streak-nullázás elfelejtése** lépés után — az A2 második sora méri.
- **Attempt közbeni tempóváltás.** A legacy Learn `failStreak`-je futás közben
  ajánl; a V2-ben ez tilos. Ne másold át a mintát.
- **A controller bekötésének csábítása.** Az `application/` tilos zóna ebben a
  körben; a bekötés külön lépés, hogy a policy tisztán mérhető maradjon.
- **A step-up küszöb szétszórása.** A `0.95 / 0.85 / 0.80` **egy** helyen él
  (policy/profil), nem három widgetben.

## 9. Záró gate — szó szerint ez az egyetlen hívás

```
tools/round-gate.sh test/features/practice/ test/property/speed_builder_property_test.dart test/core/l10n_parity_test.dart
```

Csővezeték nélkül, a teljes kimenetet a §10-be. A teljes suite + property gate +
APK a CI-ban fut (ADR 0053) — `gh`-t NE hívj.

## 10. Implementation handoff — az IMPLEMENTER tölti ki

### Fájlonkénti összefoglaló

- `speed_builder_policy.dart`: immutable policy, 30–300 BPM/1–20 step/1–100 attempt és pozitív streak-küszöb validáció, stabil Speed Builder hibakódokkal és aggregált hibajegyzékkel.
- `speed_builder_state.dart`: immutable, value-equal állapot, lezárási státuszok, unmodifiable attempt-történet; itt élnek a presentation által is fogyasztható adaptív suggestion value-modellek.
- `speed_builder_engine.dart`: pure állapotgép; a step-up pass kizárólag a metrikákból számolódik az egyetlen nevesített `0.95/0.85/0.80` konstanshelyről; streak reset, zárt BPM-korlátok, target completion, max-attempt/user-finish és stabil-BPM újraszámítás.
- `adaptive_practice_policy.dart`: pure, fix listasorrendű prioritás; aktív attemptre `null`; a pozitív/next-difficulty ág is a szigorú step-up predikátumot használja, nem a plain outcome-ot.
- `speed_builder_progress.dart`: injektált állapotból current/target/next BPM, streak, attempt, loop és nullable highest-stable megjelenítés.
- `adaptive_suggestion_banner.dart`: explicit Apply/Dismiss; rendereléskor nincs mellékhatás vagy auto-apply.
- `practice_session_screen.dart`: kizárólag opcionális, injektált Speed Builder/suggestion argumentumok és a két widget becsatolása; controller/provider bekötés nem történt.
- `app_en.arb`, `app_hu.arb`: paritásos Speed Builder és adaptív banner kulcsok.
- Öt engedélyezett tesztfájl: A1–A10 determinisztikus mátrixok, widget fake-hívásnapló és `PROPERTY_SEED` randomized gate.

### A1–A11 evidencia

- **A1:** a policy-teszt lefedi a brief határait, target-tartományt, nem véges értékeket, mindkét pozitív streak-küszöböt és az egy hívásban visszaadott hét független hibakódot.
- **A2:** két step-up pass után 80→90 BPM és `successStreak == 0`; a plain `outcome == passed` gyenge metrikákkal bizonyítottan nem léptet.
- **A3:** két fail után 90→80, `failStreak == 0`, további fail sem visz start alá; targeten nincs túllépés.
- **A4:** targeten egy pass nem zár, a teljes egymást követő streak `completed`, BPM a targeten marad.
- **A5:** harmadik/max attempt után ugyanaz az állapotpéldány tér vissza további resultnál; user-finish megőrzi a historyt és historyból újraszámolja a stabil BPM-et.
- **A6:** a brief négy kötelező cellája és egy fail utáni újraépített streak-cella bizonyítja, hogy egyetlen lucky pass nem stabil BPM.
- **A7:** azonos input kétszer azonos suggestion; fix prioritás (insufficient → low completion → timing bias → direction); aktív attempt `null`; plain pass nem vált ki step-up suggestiont.
- **A8:** widget-teszt lefedi current/target/next BPM, streak, attempt, loop és stable BPM jelen/nincs ágát; a hiány lokalizált `Not yet`, nem `0 BPM`.
- **A9:** fake parancsnapló: render = 0, dismiss = 0, apply = pontosan 1.
- **A10:** seed logolva (`PROPERTY_SEED`, default 42); 100 random policy × 140 result lépés mellett no-throw, BPM-korlát, legfeljebb egy step, history-cap, stabil≤elfogadott max és azonos transition determinisztikusság.
- **A11:** architecture/domain-purity gate zöld; végső scope-auditban `application/`, `data/`, `lib/features/learn/` 0 sor.

### Eltérések és follow-up

- A gate első két próbája kizárólag a formatter által jelzett 8 fájl miatt állt meg; célzott `dart format` után egy analyzer-only `unnecessary_import` került eltávolításra. Az alábbi a végső, változtatás nélküli, teljes zöld gate-kimenet.
- A controller/runtime bekötés, a suggestion tényleges parancsleképezése és a result-summary szándékosan **E02-R18** follow-up (ADR 0083 §9, brief §5.8).
- Full suite + random property + APK a CI/orchestrátor feladata; implementer `gh`-t nem hívott.

### Végső gate — teljes, csonkítatlan kimenet

```text

═══ [1] format
    $ /home/ubuntu/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool

Formatted 609 files (0 changed) in 2.21 seconds.

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
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.0 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.5.0 available)
  permission_handler_html 0.1.3+5 (0.1.4+0 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
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
  vector_math 2.2.0 (2.4.2 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
38 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Analyzing 3 items...
No issues found! (ran in 3.0s)

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
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.0 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.5.0 available)
  permission_handler_html 0.1.3+5 (0.1.4+0 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
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
  vector_math 2.2.0 (2.4.2 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
38 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/meter_test.dart
00:00 +0: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/meter_test.dart: Meter validation accepts 4/4, 3/4, and supported 6/8 meter
00:00 +1: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/meter_test.dart: Meter validation rejects beats-per-bar values outside 1 through 16
00:00 +2: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/meter_test.dart: Meter validation rejects unsupported beat units
00:00 +3: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/meter_test.dart: Meter validation aggregates independent field failures
00:00 +4: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/meter_test.dart: Meter tick arithmetic computes exact ticks per bar for supported meters
00:00 +5: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/meter_test.dart: Meter tick arithmetic fails fast symmetrically for every invalid input field
00:00 +6: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/meter_test.dart: Meter value semantics uses both fields as its value identity
00:00 +7: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_value_equality_test.dart: Practice value equality helpers compares lists structurally and hashes equal lists equally
00:00 +8: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_value_equality_test.dart: Practice value equality helpers compares maps structurally independent of insertion order
00:00 +9: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation accepts a complete valid definition
00:00 +10: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation aggregates definition fields and nested Tempo failures
00:00 +11: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation rejects a non-positive total duration
00:00 +12: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation requires a non-empty target list only for scored modes
00:00 +13: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation reports decreasing positions as unsorted
00:00 +14: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation reports duplicate event IDs independently of positions
00:00 +15: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation reports duplicate positions without treating them as unsorted
00:00 +16: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation rejects positions at and beyond the exclusive totalBeats bound
00:00 +17: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation passes nested event failures through unchanged
00:00 +18: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation enforces exact mode-to-weight-key compatibility
00:00 +19: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation displayTitle accepts null and non-blank text, rejects blank
00:00 +20: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition value semantics deeply compares lists and supports Set and Map keys
00:00 +21: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter forward conversion uses one final microsecond rounding step
00:01 +22: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter forward conversion exposes exact quarter-beat and meter-aware bar durations
00:01 +23: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter inverse conversion round-trips every 32-tick grid point over 64 quarter beats
00:01 +24: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter inverse conversion rejects negative elapsed time
00:01 +25: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter validation guards every conversion member rejects an invalid tempo
00:01 +26: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter validation guards every conversion member rejects an invalid meter
00:01 +27: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/domain_purity_test.dart: practice domain has no ambient IO, nondeterminism, or app imports
00:01 +28: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/domain_purity_test.dart: purity scan ignores forbidden spellings in comments and strings
00:01 +29: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/domain_purity_test.dart: purity scan recognizes root l10n and Riverpod imports
00:01 +30: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/domain_purity_test.dart: purity scan inspects executable string interpolation bodies
00:01 +31: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_test.dart: canonical practice chord labels accepts null and sharp-spelled major or minor labels
00:01 +32: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_test.dart: canonical practice chord labels rejects empty, no-chord, flat, extended, lowercase, and padded labels
00:01 +33: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation accepts scored events and a marker without scored attributes
00:01 +34: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation reports an empty ID with the pinned code literal
00:01 +35: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation rejects a zero duration with the pinned code literal
00:01 +36: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation requires a scored attribute on a non-marker event
00:01 +37: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation forbids scored attributes on marker events
00:01 +38: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation aggregates independent event failures
00:01 +39: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_test.dart: PracticeEvent value semantics supports structural equality, hashing, Set, and Map keys
00:02 +40: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/beat_position_test.dart: BeatPosition subdivisions uses 480 ticks per quarter-note beat
00:02 +41: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/beat_position_test.dart: BeatPosition subdivisions represents supported fractions with exact integer equality
00:02 +42: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge converts the current half-beat grid without deviation
00:02 +43: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge round-trips every supported deterministic subdivision position
00:02 +44: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge rounds one third of a beat to the nearest exact triplet tick
00:02 +45: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge rejects non-finite legacy input explicitly
00:02 +46: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/beat_position_test.dart: BeatPosition invariants rejects negative data-driven positions in every runtime path
00:02 +47: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/beat_position_test.dart: BeatPosition invariants keeps the const constructor guarded in checked builds
00:02 +48: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/beat_position_test.dart: BeatPosition value operations sorts deterministically and compareTo agrees with equality
00:02 +49: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/beat_position_test.dart: BeatPosition value operations adds and subtracts positions exactly
00:02 +50: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/beat_position_test.dart: BeatPosition value operations has a deterministic diagnostic representation
00:02 +51: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/tempo_test.dart: Tempo validation accepts the closed 30.0 through 300.0 BPM boundaries
00:02 +52: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/tempo_test.dart: Tempo validation reports finite values outside the range without clamping
00:02 +53: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/tempo_test.dart: Tempo validation reports NaN and infinities as not finite
00:02 +54: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/tempo_test.dart: Tempo value semantics uses BPM as its value identity
00:02 +55: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_validation_test.dart: PracticeValidationCode defines the complete stable code set
00:02 +56: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_validation_test.dart: PracticeValidationCode pins target compiler validation and failure codes
00:02 +57: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_validation_test.dart: PracticeValidationCode pins the five pre-existing codes at their producing boundaries
00:02 +58: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_validation_test.dart: PracticeValidationFailure has value semantics
00:02 +59: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_validation_test.dart: PracticeValidationFailure has a deterministic diagnostic representation
00:03 +60: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/free_practice_summarizer_test.dart: FreePracticeSummarizer A3 — strum counts and down/up ratios counts strums and direction split
00:03 +61: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/free_practice_summarizer_test.dart: FreePracticeSummarizer A3 — strum counts and down/up ratios zero strums => InsufficientData for the ratio
00:03 +62: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/free_practice_summarizer_test.dart: FreePracticeSummarizer A3 — strum counts and down/up ratios direction-less definition => NotApplicable for the ratio
00:03 +63: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/free_practice_summarizer_test.dart: FreePracticeSummarizer A4 — tempo stability (MAD-style, requires ≥ 4 strums) three strums => InsufficientData
00:03 +64: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/free_practice_summarizer_test.dart: FreePracticeSummarizer A4 — tempo stability (MAD-style, requires ≥ 4 strums) 4 evenly-spaced strums => deviation = 0
00:03 +65: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/free_practice_summarizer_test.dart: FreePracticeSummarizer A4 — tempo stability (MAD-style, requires ≥ 4 strums) 12 evenly-spaced strums => deviation = 0
00:03 +66: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/free_practice_summarizer_test.dart: FreePracticeSummarizer A4 — tempo stability (MAD-style, requires ≥ 4 strums) 12 strums with one 1500 ms gap: median-absolute deviation stays small
00:03 +67: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/free_practice_summarizer_test.dart: FreePracticeSummarizer A4 — tempo stability (MAD-style, requires ≥ 4 strums) mixed intervals: median-absolute deviation computes the right value
00:03 +68: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/free_practice_summarizer_test.dart: FreePracticeSummarizer A5 — chord timeline segments G (4s) → null (1s) → C (3s) yields three segments
00:03 +69: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/free_practice_summarizer_test.dart: FreePracticeSummarizer A2 — Free Practice summary never produces a score strumCount and activeDuration are surfaced as facts only
00:03 +70: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/free_practice_summarizer_test.dart: FreePracticeSummarizer A9 — segment durations sum to ≤ activeDuration
00:04 +71: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/compiled_practice_target_test.dart: Compiled practice target value models scalar models compare structurally and hash equal values equally
00:04 +72: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/compiled_practice_target_test.dart: Compiled practice target value models aggregate compares every list and scalar structurally
00:04 +73: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/compiled_practice_target_test.dart: Compiled practice target value models aggregate stores unmodifiable snapshots of every list
00:05 +74: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation accepts all closed range boundaries
00:05 +75: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation reports empty IDs and an invalid snapshot version
00:05 +76: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects count-in values outside zero through four
00:05 +77: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects loop counts outside one through 32
00:05 +78: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects input latency outside zero through 500 milliseconds
00:05 +79: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects visual latency outside zero through 500 milliseconds
00:05 +80: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation requires a strictly positive session timeout
00:05 +81: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation passes nested Tempo failures through unchanged
00:05 +82: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation aggregates at least three independent failures
00:05 +83: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig value semantics compares all fields and copyWith preserves or changes explicitly
00:05 +84: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/adaptive_practice_policy_test.dart: AdaptivePracticePolicy A7 same input returns the same suggestion
00:05 +85: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/adaptive_practice_policy_test.dart: AdaptivePracticePolicy A7 fixed list priority selects insufficient signal first
00:05 +86: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/adaptive_practice_policy_test.dart: AdaptivePracticePolicy A7 low completion outranks timing bias and direction error
00:05 +87: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/adaptive_practice_policy_test.dart: AdaptivePracticePolicy A7 dominant timing bias outranks direction error
00:05 +88: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/adaptive_practice_policy_test.dart: AdaptivePracticePolicy A7 direction error is suggested when higher priorities are absent
00:05 +89: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/adaptive_practice_policy_test.dart: AdaptivePracticePolicy A7 plain passed outcome alone does not trigger a step-up suggestion
00:05 +90: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/adaptive_practice_policy_test.dart: AdaptivePracticePolicy A7 active attempt always returns null
00:06 +91: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/speed_builder_policy_test.dart: SpeedBuilderPolicy A1 step BPM accepts the closed 1 to 20 range
00:06 +92: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/speed_builder_policy_test.dart: SpeedBuilderPolicy A1 max attempts accepts the closed 1 to 100 range
00:06 +93: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/speed_builder_policy_test.dart: SpeedBuilderPolicy A1 start BPM follows the Tempo closed range
00:06 +94: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/speed_builder_policy_test.dart: SpeedBuilderPolicy A1 target BPM may equal or exceed start but not precede it
00:06 +95: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/speed_builder_policy_test.dart: SpeedBuilderPolicy A1 target BPM follows the Tempo closed range
00:06 +96: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/speed_builder_policy_test.dart: SpeedBuilderPolicy A1 rejects non-finite tempo and step values
00:06 +97: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/speed_builder_policy_test.dart: SpeedBuilderPolicy A1 consecutive-pass and fail thresholds must be positive
00:06 +98: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/speed_builder_policy_test.dart: SpeedBuilderPolicy A1 returns every independent validation failure
00:07 +99: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/speed_builder_engine_test.dart: SpeedBuilderEngine A2 — two step-up passes advance once and reset streak
00:08 +100: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/speed_builder_engine_test.dart: SpeedBuilderEngine step-up pass uses metrics rather than plain passed outcome
00:08 +101: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/speed_builder_engine_test.dart: SpeedBuilderEngine insufficient or unavailable required metrics cannot step up
00:08 +102: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/speed_builder_engine_test.dart: SpeedBuilderEngine A3 — two fails step down but never below start
00:08 +103: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/speed_builder_engine_test.dart: SpeedBuilderEngine A3/A4 — target bound is closed and completion needs full streak
00:08 +104: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/speed_builder_engine_test.dart: SpeedBuilderEngine A5 — max attempts closes idempotently
00:08 +105: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/speed_builder_engine_test.dart: SpeedBuilderEngine A5 — user finish preserves history and stable BPM
00:08 +106: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/speed_builder_engine_test.dart: SpeedBuilderEngine finish derives stable BPM from preserved history
00:08 +107: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/speed_builder_engine_test.dart: SpeedBuilderEngine A6 — highest stable BPM requires consecutive passes per tempo
00:08 +108: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer outcome matrix recognises the first stable target chord with signed delay
00:08 +109: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer outcome matrix reports a stable wrong chord separately
00:08 +110: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer outcome matrix keeps explicit null labels as no detection
00:08 +111: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer outcome matrix reports a target chord that never reaches stability
00:08 +112: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer outcome matrix 179999 microseconds of stability remains unstable
00:08 +113: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer outcome matrix 180001 microseconds of stability is correct
00:08 +114: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer outcome matrix separates an empty window and a window without a strum
00:08 +115: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer meter boundaries 3/4 change on a bar boundary produces correct statistics
00:08 +116: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer meter boundaries 4/4 change on a bar boundary produces correct statistics
00:08 +117: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer delay and aggregation preserves early, on-time, late, and missing delay
00:08 +118: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer delay and aggregation uses a median only after three measured changes
00:08 +119: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer delay and aggregation treats direction as part of a chord pair
00:08 +120: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer delay and aggregation slowest pair tie-break is canonical and input-order independent
00:09 +121: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation accepts a valid attempt and aggregates nested values
00:09 +122: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation rejects a negative attempt index
00:09 +123: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation rejects duplicate verdict target IDs
00:09 +124: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation compares the verdict list and all other fields structurally
00:09 +125: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation accepts a valid session with canonical coaching codes
00:09 +126: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation rejects an empty session ID and attempt list
00:09 +127: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation requires attempt indexes to be strictly increasing
00:09 +128: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation continues nested validation after an attempt ordering failure
00:09 +129: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation rejects negative active and paused durations
00:09 +130: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation rejects an unknown coaching-summary code
00:09 +131: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation aggregates attempt and highest-stable-tempo failures
00:09 +132: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation compares attempt and coaching lists structurally
00:09 +133: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts finalAttempt selects the greatest index independent of list order
00:09 +134: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts bestAttempt selects the greatest available overall score
00:09 +135: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts bestAttempt breaks score ties with the smaller index
00:09 +136: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts derived getters return null when no attempt is comparable
00:09 +137: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation accepts available score boundaries and explicit unavailable states
00:09 +138: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation reports non-finite values without a duplicate range failure
00:09 +139: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation rejects finite values outside zero through one
00:09 +140: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation requires an insufficient-data reason code
00:10 +141: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation accepts a valid metric set including signed timing bias
00:10 +142: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation passes nested metric failures through unchanged
00:10 +143: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects negative total target count
00:10 +144: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects resolved targets greater than total targets
00:10 +145: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects negative max combo and score points
00:10 +146: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects a negative mean absolute offset
00:10 +147: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_metrics_test.dart: Practice metric value semantics compares every MetricValue subtype by structure and subtype
00:10 +148: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_metrics_test.dart: Practice metric value semantics compares PracticeMetrics structurally
00:10 +149: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window -120001 us is outside the chord window
00:10 +150: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window -120000 us is inside the chord window
00:10 +151: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window -119999 us is inside the chord window
00:10 +152: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window 419999 us is inside the chord window
00:10 +153: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window 420000 us is inside the chord window
00:10 +154: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window 420001 us is outside the chord window
00:10 +155: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches stable expected label is correct
00:10 +156: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches stable different label is wrong
00:10 +157: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches only null labels are noDetection, not wrong or insufficient
00:10 +158: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches an empty target window is insufficient data
00:10 +159: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches a label below the stability threshold is insufficient data
00:10 +160: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches a target without an expected chord is not applicable
00:10 +161: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation the longest stable segment wins even when it is the wrong chord
00:10 +162: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation nonconsecutive runs of the same label are not merged
00:10 +163: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation unordered observations produce the same deterministic result
00:10 +164: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation available outcomes use one integer truncating division
00:10 +165: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation samples outside every window report insufficient samples
00:10 +166: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation unmatched optional chord target does not dilute the metric
00:10 +167: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation the event-score view rejects mutation
00:10 +168: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_enums_test.dart: PracticeMode stable codes pins every code, round-trips, and rejects unknown codes
00:10 +169: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_enums_test.dart: PracticeMode stable codes exposes the exact scored dimensions for each mode
00:10 +170: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_enums_test.dart: PracticeSource stable codes pins every code, round-trips, and rejects unknown codes
00:10 +171: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_enums_test.dart: PracticeDifficulty stable codes pins every code, round-trips, and rejects unknown codes
00:10 +172: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_enums_test.dart: PracticeScoreDimension stable codes pins every code, round-trips, and rejects unknown codes
00:10 +173: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_enums_test.dart: ExtraStrumPolicy stable codes pins every code, round-trips, and rejects unknown codes
00:10 +174: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_enums_test.dart: TimingGrade stable codes pins every code, round-trips, and rejects unknown codes
00:10 +175: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_enums_test.dart: PracticeAttemptOutcome stable codes pins every code, round-trips, and rejects unknown codes
00:11 +176: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_enums_test.dart: PracticeFinishReason stable codes pins every code, round-trips, and rejects unknown codes
00:11 +177: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 0 us is exactly 1000 per mille
00:11 +178: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 0 us is exactly 1000 per mille
00:11 +179: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 49999 us is exactly 1000 per mille
00:11 +180: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 49999 us is exactly 1000 per mille
00:11 +181: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 50000 us is exactly 1000 per mille
00:11 +182: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 50000 us is exactly 1000 per mille
00:11 +183: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 50001 us is exactly 800 per mille
00:11 +184: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 50001 us is exactly 800 per mille
00:11 +185: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 119999 us is exactly 800 per mille
00:11 +186: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 119999 us is exactly 800 per mille
00:11 +187: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 120000 us is exactly 800 per mille
00:11 +188: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 120000 us is exactly 800 per mille
00:11 +189: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 120001 us is exactly 800 per mille
00:11 +190: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 120001 us is exactly 800 per mille
00:11 +191: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 200000 us is exactly 575 per mille
00:11 +192: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 200000 us is exactly 575 per mille
00:11 +193: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 279999 us is exactly 351 per mille
00:11 +194: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 279999 us is exactly 351 per mille
00:11 +195: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 280000 us is exactly 350 per mille
00:11 +196: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 280000 us is exactly 350 per mille
00:11 +197: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix an unmatched required target is a zero-score miss
00:11 +198: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation uses integer accumulation and one truncating mean division
00:11 +199: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation signed timing bias truncates toward zero in integer microseconds
00:11 +200: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation open unmatched optional target does not dilute the rhythm dimension
00:11 +201: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation finalized unmatched optional target does not dilute the rhythm dimension
00:11 +202: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation an empty target has no applicable rhythm metric
00:11 +203: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation the event-score view rejects mutation
00:11 +204: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation accepts a valid weighted profile and an empty weight map
00:11 +205: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation accepts closed threshold endpoints and equal positive windows
00:11 +206: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation pins the legacy Learn parity profile literals
00:11 +207: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation validates the four built-in non-strum profiles and pins literals
00:11 +208: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation built-in non-strum profile weights exactly match their mode scored dimensions
00:11 +209: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation reports an empty identifier with the pinned code literal
00:11 +210: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects zero and negative windows
00:11 +211: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects perfect greater than good and good greater than match
00:11 +212: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects weight sums of 99 and 101
00:11 +213: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects a negative weight independently of the exact sum
00:11 +214: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects thresholds outside the closed zero to 100 range
00:11 +215: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation aggregates independent failures in one call
00:11 +216: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile value semantics compares the weight map structurally and hashes it by value
00:13 +217: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target legacy baseline parity ten frozen scenarios match finish and every event within 1 us
00:13 +218: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target shipped-lesson parity pins all 17 lesson IDs in the measured order
00:13 +219: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target shipped-lesson parity all valid 50, 75 and 100 percent tempos match within 1 us
00:13 +220: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target shipped-lesson parity first-waltz explicitly measures the three-beat count-in edge
00:13 +221: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target shipped-lesson parity eighth-drive explicitly measures its closest-to-end event
00:13 +222: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target corpus invariants whole-bar rounding is a no-op for every pinned shipped ID
00:13 +223: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target corpus invariants eventless Analyze import keeps one positive 4/4 bar
00:13 +224: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_eligibility_test.dart: A6 — PracticeSessionEligibility threshold matrix activeDuration threshold (20s) 19999 ms → false
00:13 +225: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_eligibility_test.dart: A6 — PracticeSessionEligibility threshold matrix activeDuration threshold (20s) 20000 ms → true
00:13 +226: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_eligibility_test.dart: A6 — PracticeSessionEligibility threshold matrix activeDuration threshold (20s) 20001 ms → true
00:13 +227: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_eligibility_test.dart: A6 — PracticeSessionEligibility threshold matrix resolvedRequiredTargets threshold (4) 3 targets → false
00:13 +228: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_eligibility_test.dart: A6 — PracticeSessionEligibility threshold matrix resolvedRequiredTargets threshold (4) 4 targets → true
00:13 +229: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_eligibility_test.dart: A6 — PracticeSessionEligibility threshold matrix resolvedRequiredTargets threshold (4) 5 targets → true
00:13 +230: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_eligibility_test.dart: A6 — PracticeSessionEligibility threshold matrix freePracticeStrums threshold (8) 7 strums → false
00:13 +231: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_eligibility_test.dart: A6 — PracticeSessionEligibility threshold matrix freePracticeStrums threshold (8) 8 strums → true
00:13 +232: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_eligibility_test.dart: A6 — PracticeSessionEligibility threshold matrix freePracticeStrums threshold (8) 9 strums → true
00:13 +233: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_eligibility_test.dart: A6 — PracticeSessionEligibility threshold matrix all three below thresholds → false
00:13 +234: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_eligibility_test.dart: A6 — PracticeSessionEligibility threshold matrix first-win: short active duration but enough targets → true
00:13 +235: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_eligibility_test.dart: A6 — PracticeSessionEligibility threshold matrix at least one threshold met → true
00:14 +236: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/chord_pair_stats_test.dart: ChordPair is immutable and value equal
00:14 +237: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/chord_pair_stats_test.dart: stats expose immutable counts and measured delays
00:14 +238: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/chord_pair_stats_test.dart: invalid stats report validation failures
00:14 +239: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation accepts closed confidence boundaries for both observation types
00:14 +240: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation rejects a negative timestamp
00:14 +241: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation rejects a negative strum sequence
00:14 +242: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation reports non-finite confidence without a duplicate range failure
00:14 +243: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation rejects finite confidence outside zero through one
00:14 +244: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation uses the canonical chord-label contract including null
00:14 +245: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_observation_test.dart: PracticeObservation value semantics compares each concrete subtype structurally
00:15 +246: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure rounds a partial 4/4 definition up to a complete final bar
00:15 +247: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure uses three quarter beats per 3/4 count-in and bar step
00:15 +248: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure pins two count-in bars and repeated-pass bar boundaries
00:15 +249: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure gives a downbeat event and its bar boundary the same time at 90 BPM
00:15 +250: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure computes total duration from all absolute ticks at 90 BPM
00:15 +251: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure compiles the final in-range tick instead of dropping it
00:15 +252: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure uses effective tempo at 50 and 75 percent without accumulation
00:15 +253: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure excludes markers while preserving a one-event target
00:15 +254: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure projects target metadata and every scored event field
00:15 +255: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure a marker-only scored definition compiles without scored events
00:15 +256: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops repeats every source event with absolute positions and loop indexes
00:15 +257: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops selects one source bar and rebases it before repeating
00:15 +258: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops accepts the rounded final partial bar as a whole-bar loop
00:15 +259: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops computes barIndex from ticksPerBar for multi-bar passes
00:15 +260: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops rejects invalid loop range Instance of 'PracticeLoopRange' without clamping
00:15 +261: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops rejects invalid loop range Instance of 'PracticeLoopRange' without clamping
00:15 +262: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops rejects invalid loop range Instance of 'PracticeLoopRange' without clamping
00:15 +263: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments matches the pinned legacy pre-roll and merges repeated labels
00:15 +264: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments uses the named 120-tick lookahead for a one-beat chord change
00:15 +265: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments returns no segments when no compiled event carries a chord
00:15 +266: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments extends one chord across the complete session timeline
00:15 +267: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments carries chord changes across a repeated loop boundary
00:15 +268: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order definition validation wins and rejects zero totalBeats
00:15 +269: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order config validation wins before definition ID mismatch
00:15 +270: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order definition ID mismatch wins before variation mismatch
00:15 +271: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order rejects a non-matching Easy variation explicitly
00:15 +272: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order variation mismatch wins before an invalid loop range
00:15 +273: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order accepts a matching non-null Easy variation ID
00:15 +274: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler empty and deterministic outputs compiles positive-length Free Practice without target events
00:15 +275: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler empty and deterministic outputs returns equal, hash-equal targets with nondecreasing event times
00:16 +276: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A4 available-dimension weighting does not fill an unavailable chord dimension with zero
00:16 +277: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A4 available-dimension weighting pins every integer overall table cell
00:16 +278: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A4 available-dimension weighting free practice has no overall score
00:16 +279: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 16 of 20 resolved and 699 overall
00:16 +280: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 16 of 20 resolved and 700 overall
00:16 +281: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 17 of 20 resolved and 699 overall
00:16 +282: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 17 of 20 resolved and 700 overall
00:16 +283: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 18 of 20 resolved and 699 overall
00:16 +284: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 18 of 20 resolved and 700 overall
00:16 +285: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate zero resolved targets is incomplete rather than failed
00:16 +286: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate unmatched optional target is excluded from completion counters
00:16 +287: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate matched optional target is excluded from completion counters
00:16 +288: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_score_aggregator_test.dart: A6 increments combo before the fifth-hit multiplier
00:16 +289: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_score_aggregator_test.dart: A6 combo resets and optional isolation a wrong direction resets before the next clean hit
00:16 +290: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_score_aggregator_test.dart: A6 combo resets and optional isolation a miss resets before the next clean hit
00:16 +291: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_score_aggregator_test.dart: A6 combo resets and optional isolation matched down optional target neither increments nor resets combo
00:16 +292: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_score_aggregator_test.dart: A6 combo resets and optional isolation matched up optional target neither increments nor resets combo
00:16 +293: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_score_aggregator_test.dart: A8 every verdict and the complete attempt result are valid
00:16 +294: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation accepts matched and unmatched consistent verdicts at score bounds
00:16 +295: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation reports an empty target event ID
00:16 +296: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation reports non-finite event score without a duplicate range failure
00:16 +297: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation rejects finite event scores outside zero through one
00:16 +298: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation rejects unmatched verdicts with observed time or matched grades
00:16 +299: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation accepts and pins all five canonical coaching codes
00:16 +300: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation rejects an unknown coaching code
00:16 +301: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict value semantics compares all scalar, enum, and nullable fields
00:17 +302: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity pins the complete 16 lesson catalog plus first-win
00:17 +303: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity keeps every compiled event within 0.5 us of legacy time
A1b measuredEvents=348 maximumTimebaseDifferenceUs=0.489795919508 cell=anthem-drive[23]
00:17 +304: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity pins the first-strums compiled eligibility divergence
00:17 +305: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity pins the anthem-drive [5, 6] compiled midpoint divergence
00:17 +306: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity matches every target exactly across all 51 latency scenarios
A1 parity scenarios=51 maximumDifferenceUs=0 excludedObservations=0
00:17 +307: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher eligibility and close boundaries pins all six cells around the 280 ms boundary
00:17 +308: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher eligibility and close boundaries exact boundary stays open and eligible after advance
00:17 +309: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher latency correction pins matching and closing for 0, 40 and 300 ms latency
00:17 +310: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher tie breaking midpoint and neighboring microseconds choose the pinned target
00:17 +311: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher tie breaking equal-time targets choose the smaller list index
00:17 +312: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution a wrong direction consumes the target before a correct retry
00:17 +313: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution an out-of-window extra leaves every target resolution unchanged
00:17 +314: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution one observation resolves at most one of two eligible targets
00:17 +315: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution a restarted gateway sequence can match a later target
00:17 +316: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution resolved count is monotonic and terminal results never reopen
00:17 +317: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution finalize separates required misses from unmatched optional targets
00:17 +318: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution an optional target remains matchable before its window closes
00:17 +319: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution finalize is idempotent
00:17 +320: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution signed offsets keep early negative and late positive
00:17 +321: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution an empty target is safe to match, advance, and finalize
00:17 +322: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics separate matchers produce equal results and hash codes
00:17 +323: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics targetIndex alone contributes to equality
00:17 +324: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics target alone contributes to equality
00:17 +325: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics resolution alone contributes to equality
00:17 +326: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics matched observation sequence alone contributes to equality
00:17 +327: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics observedAt and timingOffset together contribute to equality
00:17 +328: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics results rejects mutation
00:17 +329: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher measured scaling 20k targets and 1k strums stay below the cursor threshold
A6 cursor examined=43000 threshold=1344000
00:18 +330: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher measured scaling 100k extras do not grow retained records beyond four targets
A6 memory retained=4 threshold=4
00:19 +331: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeMetricReasonCode pins the complete stable code set
00:19 +332: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix matched equal direction is correct and worth 1000 per mille
00:19 +333: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix matched different direction is wrong and worth zero
00:19 +334: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix unmatched directional target is wrong when signal existed
00:19 +335: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix target without direction is not applicable when matched
00:19 +336: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix target without direction is not applicable when unmatched
00:19 +337: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix directional targets with zero strum signal are insufficient data
00:19 +338: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation fails fast when a matched sequence has no observation mapping
00:19 +339: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation uses integer accumulation and one truncating division
00:19 +340: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation open unmatched optional direction target does not dilute the metric
00:19 +341: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation finalized unmatched optional direction target does not dilute the metric
00:19 +342: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation target-index pairing supports restarted observation sequences
00:19 +343: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation fails fast when a target mapping carries the wrong sequence
00:19 +344: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation the event-score view rejects mutation
00:19 +345: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity pins the complete 16 lesson catalog plus first-win
00:19 +346: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity measures the compiled timebase guard at at most 0.5 us
A7b measuredEvents=348 maximumTimebaseDifferenceUs=0.489795919508 cell=anthem-drive[23]
00:19 +347: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity matches score, combo, counters and direction across 51 scenarios
A7 parity scenarios=51 excludedGuardBandEvents=0
00:19 +348: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity pins 18 representative extrema divergence cells
A7c representativeDivergenceCells=18
00:19 +349: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity discovers and pins every actual boundary divergence cell
A7c exhaustiveDivergenceCells=3213 fingerprint=375672841
00:20 +350: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState initial state is idle and empty
00:20 +351: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState value equality: same fields → equal
00:20 +352: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState value equality: any field change → not equal
00:20 +353: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState copyWith: explicit overrides win; cleared fields go to null
00:20 +354: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState timelinePosition: formula holds for all five anchor combinations
00:20 +355: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState isActive: true for countIn/running/paused/finishing only
00:20 +356: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) idle → preparing
00:20 +357: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) preparing → permissionRequired | ready | failed
00:20 +358: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) permissionRequired → preparing | cancelled
00:20 +359: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) ready → countIn | cancelled
00:20 +360: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) countIn → running | paused | cancelled | failed
00:20 +361: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) running → paused | finishing | cancelled | failed
00:20 +362: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) paused → countIn | running | finishing | cancelled
00:20 +363: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) finishing → completed | failed
00:20 +364: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) completed → ready | idle
00:20 +365: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) cancelled → ready | idle
00:20 +366: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) failed → preparing | idle
00:20 +367: /home/ubuntu/ss-mm-e02-r17/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) every status has a transition entry
00:21 +368: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_lifecycle_test.dart: A6 — app-lifecycle forward matrix countIn + background → exactly 1 PausePractice(interruption)
00:22 +369: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_lifecycle_test.dart: A6 — app-lifecycle forward matrix countIn + background → exactly 1 PausePractice(interruption)
00:22 +370: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_lifecycle_test.dart: A6 — app-lifecycle forward matrix countIn + background → exactly 1 PausePractice(interruption)
00:22 +371: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_lifecycle_test.dart: A6 — app-lifecycle forward matrix countIn + background → exactly 1 PausePractice(interruption)
00:22 +372: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_lifecycle_test.dart: A6 — app-lifecycle forward matrix countIn + background → exactly 1 PausePractice(interruption)
00:22 +373: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_lifecycle_test.dart: A6 — app-lifecycle forward matrix countIn + background → exactly 1 PausePractice(interruption)
00:23 +374: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_highway_test.dart: A2 — rest and same-direction neighbours are distinct markers two consecutive down strokes build two markers
00:23 +375: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_highway_test.dart: A2 — rest and same-direction neighbours are distinct markers two consecutive down strokes build two markers
00:23 +376: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_highway_test.dart: A2 — rest and same-direction neighbours are distinct markers two consecutive down strokes build two markers
00:23 +377: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_highway_test.dart: A2 — rest and same-direction neighbours are distinct markers two consecutive down strokes build two markers
00:23 +378: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_highway_test.dart: A2 — rest and same-direction neighbours are distinct markers two consecutive down strokes build two markers
00:23 +379: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_highway_test.dart: A2 — rest and same-direction neighbours are distinct markers two consecutive down strokes build two markers
00:23 +380: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_highway_test.dart: A2 — rest and same-direction neighbours are distinct markers two consecutive down strokes build two markers
00:23 +381: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_lifecycle_test.dart: A7 — leak guards five mount/unmount cycles → 0 lingering listeners
00:23 +382: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_lifecycle_test.dart: A7 — leak guards five mount/unmount cycles → 0 lingering listeners
00:23 +383: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_lifecycle_test.dart: A7 — leak guards five mount/unmount cycles → 0 lingering listeners
00:23 +384: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_lifecycle_test.dart: A7 — leak guards five mount/unmount cycles → 0 lingering listeners
00:23 +385: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_lifecycle_test.dart: A7 — leak guards five mount/unmount cycles → 0 lingering listeners
00:23 +386: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_lifecycle_test.dart: A7 — leak guards five mount/unmount cycles → 0 lingering listeners
00:23 +387: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_lifecycle_test.dart: A7 — leak guards five mount/unmount cycles → 0 lingering listeners
00:23 +388: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_lifecycle_test.dart: A7 — leak guards five mount/unmount cycles → 0 lingering listeners
00:23 +389: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_lifecycle_test.dart: A7 — leak guards five mount/unmount cycles → 0 lingering listeners
00:23 +390: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_lifecycle_test.dart: A7 — leak guards five mount/unmount cycles → 0 lingering listeners
00:23 +391: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_lifecycle_test.dart: A8 — a11y / i18n / layout controls have 48×48 dp hit area and one semantics node each
00:23 +392: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_lifecycle_test.dart: A8 — a11y / i18n / layout countIn shows the remaining-beats number, even with reduced motion
00:23 +393: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_lifecycle_test.dart: A8 — a11y / i18n / layout English + Hungarian locales both render without throwing
00:24 +394: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_lifecycle_test.dart: A8 — a11y / i18n / layout no raw status enum name leaks to the user-facing surface
00:24 +395: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_highway_import_guard_test.dart: all six files exist on disk
00:24 +396: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_highway_import_guard_test.dart: no Learn-internal symbols are referenced
00:24 +397: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_highway_import_guard_test.dart: no Practice domain service/ import
00:24 +398: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_highway_import_guard_test.dart: no scoring / matcher in the widget layer
00:24 +399: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_highway_scaling_test.dart: 2 000 events, 4 s visibility → examined ≤ 64 and built markers ≤ 64
00:25 +400: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/speed_builder_progress_test.dart: A8 — progress shows BPM, streak, attempts, loop, and no stable BPM
00:26 +401: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_highway_scaling_test.dart: playhead advances 100 steps → cumulative examined ≤ 100 × 64 and the marker count stays bounded each step
00:26 +402: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_highway_scaling_test.dart: playhead advances 100 steps → cumulative examined ≤ 100 × 64 and the marker count stays bounded each step
00:26 +403: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_highway_scaling_test.dart: playhead advances 100 steps → cumulative examined ≤ 100 × 64 and the marker count stays bounded each step
00:26 +404: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_highway_scaling_test.dart: playhead advances 100 steps → cumulative examined ≤ 100 × 64 and the marker count stays bounded each step
00:28 +405: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_highway_scaling_test.dart: playhead advances 100 steps → cumulative examined ≤ 100 × 64 and the marker count stays bounded each step
00:28 +406: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_highway_scaling_test.dart: playhead advances 100 steps → cumulative examined ≤ 100 × 64 and the marker count stays bounded each step
00:28 +407: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_highway_scaling_test.dart: playhead advances 100 steps → cumulative examined ≤ 100 × 64 and the marker count stays bounded each step
00:28 +408: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/rhythm_only_view_test.dart: A1 — Available renders the available copy
00:28 +409: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_highway_scaling_test.dart: 2 000 events, playhead at the end → examined ≤ 64 and built markers ≤ 64
00:28 +410: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/rhythm_only_view_test.dart: A1 — NotApplicable renders the not-applicable copy
00:28 +411: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/rhythm_only_view_test.dart: A8 — fits without overflow at Size(320.0, 568.0)
00:28 +412: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/rhythm_only_view_test.dart: A8 — fits without overflow at Size(915.0, 412.0)
00:29 +413: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_hub_screen_test.dart: A1: fixture covers all five modes and totals to 6 cards
00:29 +414: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_hub_screen_test.dart: A1: hub renders a card per catalog definition with displayTitle
00:31 +415: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_hub_screen_test.dart: A1: hub renders a card per catalog definition with displayTitle
00:31 +416: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/chord_change_view_test.dart: renders no detection and insufficient signal as distinct neutral states
00:31 +417: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_hub_screen_test.dart: A1: empty catalog shows the localized empty state
00:31 +418: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/chord_change_view_test.dart: marks lossy detector-label mapping in the breakdown
00:31 +419: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_hub_screen_test.dart: A2: filtering by strumPattern leaves only strum-pattern cards
00:31 +420: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_hub_screen_test.dart: A2: filtering by strumPattern leaves only strum-pattern cards
00:31 +421: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_hub_screen_test.dart: A2: filtering by strumPattern leaves only strum-pattern cards
00:31 +422: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_hub_screen_test.dart: A2: filtering by chordChanges leaves only the chord-change card
00:32 +423: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_hub_screen_test.dart: A2: filtering by freePractice shows the lone free-practice card
00:32 +424: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_hub_screen_test.dart: A3: Continue/Recent blocks are absent — no placeholder data
00:32 +425: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_hub_screen_test.dart: A3: empty catalog hides the Quick Start entry, not just disables it
00:32 +426: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/free_practice_view_test.dart: A7 — null summary shows the explicit "no strums" copy
00:32 +427: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/free_practice_view_test.dart: A7 — null summary shows the explicit "no strums" copy
00:32 +428: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/free_practice_view_test.dart: A7 — null summary shows the explicit "no strums" copy
00:32 +429: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/free_practice_view_test.dart: A7 — null summary shows the explicit "no strums" copy
00:33 +430: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/free_practice_view_test.dart: A7 — empty summary shows the explicit "no strums" copy
00:33 +431: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/free_practice_view_test.dart: A7 — populated summary renders facts but no score
00:33 +432: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/free_practice_view_test.dart: A7 — direction NotApplicable renders the localized copy
00:33 +433: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/free_practice_view_test.dart: A7 — InsufficientData directions render the localized copy
00:33 +434: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/free_practice_view_test.dart: A8 — fits without overflow at Size(320.0, 568.0)
00:33 +435: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/free_practice_view_test.dart: A8 — fits without overflow at Size(915.0, 412.0)
00:34 +436: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_presentation_guard_test.dart: presentation screens exist on disk
00:34 +437: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:34 +438: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:34 +439: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:34 +440: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:34 +441: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:34 +442: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:34 +443: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:34 +444: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:34 +445: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:34 +446: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:36 +447: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix preparing shows the progress indicator
00:36 +448: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix preparing shows the progress indicator
00:36 +449: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice/setup?id=<unknown> shows the localized error
00:36 +450: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix permissionRequired shows the CORE MicPermissionBanner
00:36 +451: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix permissionRequired shows the CORE MicPermissionBanner
00:36 +452: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_routing_test.dart: A7: flag OFF, /practice falls back to live (existing onException)
00:37 +453: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_routing_test.dart: A7: flag OFF, /practice falls back to live (existing onException)
00:37 +454: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix countIn shows the remaining beats overlay
00:37 +455: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_routing_test.dart: A7: flag OFF, /practice/setup also falls back to live
00:37 +456: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_routing_test.dart: A7: flag OFF, /practice/setup also falls back to live
00:37 +457: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix paused shows the pause label and Resume
00:37 +458: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix finishing shows progress AND disables the Exit button
00:37 +459: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix failed renders the in-screen error panel with Retry
00:37 +460: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_screen_test.dart: A1b — remaining three statuses + null host idle renders the neutral state message
00:37 +461: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_screen_test.dart: A1b — remaining three statuses + null host completed renders the complete state + an exit path
00:37 +462: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_screen_test.dart: A1b — remaining three statuses + null host cancelled renders the cancelled state + exit path
00:37 +463: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_screen_test.dart: A1b — remaining three statuses + null host null host renders the unavailable state — no exception
00:37 +464: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_screen_test.dart: A2 — no business-logic symbols in the new presentation files all six files exist on disk
00:37 +465: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_screen_test.dart: A2 — no business-logic symbols in the new presentation files no Ticker / Stopwatch / DateTime.now( / LessonScorer / StrumEngine / Metronome( in the new presentation files
00:37 +466: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_screen_test.dart: A2 — no business-logic symbols in the new presentation files no `domain/service/` import in the new presentation files
00:37 +467: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_screen_test.dart: A2 — no business-logic symbols in the new presentation files no flutter_riverpod legacy import remains under lib
00:37 +468: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_screen_test.dart: A3 — effect single-fire matrix one PlayHaptic + three rebuilds → 1 haptic call
00:37 +469: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_screen_test.dart: A3 — effect single-fire matrix one NavigateToResult + three rebuilds → 1 navigation call
00:38 +470: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_screen_test.dart: A3 — effect single-fire matrix two distinct PlayCountInClick → 2 count-in click calls
00:38 +471: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:38 +472: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:38 +473: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:38 +474: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:38 +475: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:38 +476: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:38 +477: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:38 +478: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:38 +479: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:39 +480: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:39 +481: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:39 +482: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix countIn: confirmation rejected → 0 commands, screen stays
00:39 +483: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix countIn: confirmation rejected → 0 commands, screen stays
00:39 +484: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/chord_progression_view_test.dart: four ChordOutcome values render with pairwise distinct signals
00:39 +485: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/chord_progression_view_test.dart: four ChordOutcome values render with pairwise distinct signals
00:39 +486: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/chord_progression_view_test.dart: four ChordOutcome values render with pairwise distinct signals
00:39 +487: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/chord_progression_view_test.dart: four ChordOutcome values render with pairwise distinct signals
00:39 +488: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix failed: no confirmation, 0 commands
00:39 +489: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/chord_progression_view_test.dart: upcoming-bar is the chord at the next bar boundary, not the next segment (two-chord-one-bar scenario)
00:39 +490: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix two rapid Exit taps in countIn → 1 CancelPractice (M1 single-fire gate)
00:39 +491: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix two rapid Exit taps in countIn → 1 CancelPractice (M1 single-fire gate)
00:39 +492: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix two rapid Exit taps in countIn → 1 CancelPractice (M1 single-fire gate)
00:39 +493: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/chord_progression_view_test.dart: chord progression view fits without overflow at Size(915.0, 412.0)
00:39 +494: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_session_screen_test.dart: A5 — NavigateToResult duplicate guard two NavigateToResult effects → 1 navigation call
00:39 +495: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/chord_progression_view_test.dart: chord progression view tolerates 200% textScale
00:40 +496: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: A4 controller matrix — domain-derived limits only BPM 29 invalid, 30 valid, 300 valid, 301 invalid
00:40 +497: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: A4 controller matrix — domain-derived limits only count-in bars -1 / 0 / 2 / 4 / 5 — only 0..4 are valid
00:40 +498: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: A4 controller matrix — domain-derived limits only loop count 0 / 1 / 32 / 33 — only 1..32 are valid
00:40 +499: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: A4 controller matrix — domain-derived limits only default config is seeded from the definition
00:40 +500: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility Free Practice hides the scoring profile row
00:41 +501: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility Free Practice hides the scoring profile row
00:42 +502: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility Free Practice hides the scoring profile row
00:42 +503: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility Free Practice hides the scoring profile row
00:42 +504: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility Free Practice hides the scoring profile row
00:42 +505: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility Rhythm-only hides the chord-hint control
00:42 +506: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility strumPattern shows the scoring profile row
00:42 +507: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: A6 Start command shape start() sends exactly one PreparePractice with the UI fields
00:42 +508: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: A6 Start command shape Start button is disabled when config is invalid
00:42 +509: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: unknown id shows the localized error state
00:42 +510: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: unknown id shows the localized error state
00:42 +511: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog every definition validates with no failures
00:42 +512: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: missing id shows the localized error state
00:42 +513: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: missing id shows the localized error state
00:43 +514: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: missing id shows the localized error state
00:43 +515: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: missing id shows the localized error state
00:43 +516: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: missing id shows the localized error state
00:43 +517: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: missing id shows the localized error state
00:43 +518: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: missing id shows the localized error state
00:43 +519: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: missing id shows the localized error state
00:43 +520: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: missing id shows the localized error state
00:43 +521: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: missing id shows the localized error state
00:43 +522: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog data layer purity source forbids ambient IO, randomness, framework, and l10n imports
00:43 +523: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: the meter readout renders the definition meter (3/4, 6/8, 4/4)
00:43 +524: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: the meter readout renders the definition meter (3/4, 6/8, 4/4)
00:43 +525: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: the meter readout renders the definition meter (3/4, 6/8, 4/4)
00:43 +526: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: the meter readout renders the definition meter (3/4, 6/8, 4/4)
00:43 +527: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: the meter readout renders the definition meter (3/4, 6/8, 4/4)
00:43 +528: /home/ubuntu/ss-mm-e02-r17/test/features/practice/presentation/practice_setup_screen_test.dart: the meter readout renders the definition meter (3/4, 6/8, 4/4)
00:43 +529: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 4/4 single-bar 8-slot pattern, 1 chord
00:43 +530: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 4/4 four-bar 8-slot pattern with up-strokes
00:43 +531: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 4/4 eight-bar full-eighth pattern
00:43 +532: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 3/4 six-slot pattern over four bars
00:43 +533: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events mixed rests pattern still expands correctly
00:43 +534: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events empty/whitespace name falls back to null displayTitle
00:43 +535: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — definition surface IDs, source, mode, profile match the ADR contract
00:43 +536: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects empty chords
00:43 +537: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects pattern length that does not fit the meter
00:43 +538: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects a pattern with only null slots
00:43 +539: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects bpm above the Tempo ceiling (400)
00:43 +540: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects bpm below the Tempo floor (10)
00:43 +541: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes none of the failure paths throws
00:43 +542: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/song_practice_adapter_test.dart: song_practice_adapter source guard forbidden to call Song.toLesson() — source-level scan
00:44 +543: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog catalog baseline: 16 curriculum + first-win
00:44 +544: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=first-strums matches every event slot exactly
00:44 +545: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=two-chord-change matches every event slot exactly
00:44 +546: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=eighth-drive matches every event slot exactly
00:44 +547: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=fifties-doo-wop matches every event slot exactly
00:44 +548: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=two-finger-frame matches every event slot exactly
00:44 +549: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=first-waltz matches every event slot exactly
00:44 +550: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=down-up-groove matches every event slot exactly
00:44 +551: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=folk-pattern matches every event slot exactly
00:44 +552: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=barre-groove matches every event slot exactly
00:44 +553: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=anthem-drive matches every event slot exactly
00:44 +554: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=rising-minor matches every event slot exactly
00:44 +555: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=waltz-time matches every event slot exactly
00:44 +556: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=reggae-skank matches every event slot exactly
00:44 +557: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=funk-chop matches every event slot exactly
00:44 +558: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=blues-shuffle matches every event slot exactly
00:44 +559: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=push-and-pull matches every event slot exactly
00:44 +560: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=first-win matches every event slot exactly
00:44 +561: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=first-strums easy variant mirrors simplified events
00:44 +562: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=two-chord-change easy variant mirrors simplified events
00:44 +563: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=eighth-drive easy variant mirrors simplified events
00:44 +564: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=fifties-doo-wop easy variant mirrors simplified events
00:44 +565: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=two-finger-frame easy variant mirrors simplified events
00:44 +566: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=first-waltz easy variant mirrors simplified events
00:44 +567: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=down-up-groove easy variant mirrors simplified events
00:44 +568: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=folk-pattern easy variant mirrors simplified events
00:44 +569: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=barre-groove easy variant mirrors simplified events
00:44 +570: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=anthem-drive easy variant mirrors simplified events
00:44 +571: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=rising-minor easy variant mirrors simplified events
00:44 +572: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=waltz-time easy variant mirrors simplified events
00:44 +573: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=reggae-skank easy variant mirrors simplified events
00:44 +574: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=funk-chop easy variant mirrors simplified events
00:44 +575: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=blues-shuffle easy variant mirrors simplified events
00:44 +576: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=push-and-pull easy variant mirrors simplified events
00:44 +577: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=first-win easy variant mirrors simplified events
00:44 +578: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency chord labels match legacyPracticeChordLabel for every event
00:44 +579: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency twoFingerFrame chords normalize to Em / C in order
00:44 +580: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency bluesShuffle chords normalize to A / D
00:44 +581: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency every chord in every lesson definition is canonical
00:44 +582: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency displayTitle carries the lesson name and falls back to null
00:44 +583: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — controlled failure modes returns Failure for empty events list
00:44 +584: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — controlled failure modes displayTitle trims whitespace and becomes null for empty name
00:44 +585: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — difficulty mapping preserves beginner, intermediate and advanced tiers
00:44 +586: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — determinism the same epoch day produces structurally equal definitions
00:44 +587: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — determinism consecutive epoch days produce different definitions
00:44 +588: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — determinism definition ID encodes the epoch day
00:44 +589: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling pattern longer than 8 slots is truncated to 8 events
00:44 +590: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling pattern shorter than 8 slots is preserved as-is
00:44 +591: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling every event has a null chord (strum-only)
00:44 +592: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling event positions are eighth-note slots starting at zero
00:44 +593: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — definition surface source, mode, keys, difficulty, profile match ADR contract
00:44 +594: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — definition surface custom bpm is honored when in range
00:44 +595: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes empty pattern is rejected
00:44 +596: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes bpm out of range is rejected
00:44 +597: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes non-finite bpm is rejected
00:44 +598: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes none of the failure paths throws
00:44 +599: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — displayTitle trims whitespace and falls back to null for empty names
00:45 +600: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for null input
00:45 +601: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for empty and whitespace-only labels
00:45 +602: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel passes canonical labels through unchanged
00:45 +603: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel reduces 7th / minor variants to their parent majmin
00:45 +604: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel rewrites flat roots to their sharp enharmonic
00:45 +605: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel drops the slash-bass of a slash chord
00:45 +606: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for unparseable roots
00:45 +607: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for empty after slash-bass removal
00:45 +608: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel trims surrounding whitespace before parsing
00:45 +609: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel every non-null output is canonical
00:45 +610: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — non-empty clip three strums with two chord lanes produce deterministic ticks
00:45 +611: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — non-empty clip preserves 3/4 meter on the resulting definition
00:45 +612: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — non-empty clip unordered strums come out sorted
00:45 +613: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=0 falls back to 90 BPM
00:45 +614: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=400 falls back to 90 BPM
00:45 +615: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=NaN falls back to 90 BPM
00:45 +616: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=80 is preserved
00:45 +617: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — tick collision forward-push two strums 0.0005s apart push the second onto the next tick
00:45 +618: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — empty strum list falls back to freePractice + open scoring + no events
00:45 +619: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — empty strum list all-non-finite strums are dropped, triggering empty-branch
00:45 +620: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — controlled failure modes blank sourceId is rejected
00:45 +621: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — controlled failure modes out-of-range beatsPerBar is rejected
00:45 +622: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — in-loop timeline grow totalBeats grows by one bar when rounding lands on the bound
00:45 +623: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — t0 normalization non-zero t0 normalizes times, and last tick at bound-1 keeps totalBeats at 4.0
00:45 +624: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — definition surface source, difficulty, keys, tags match ADR contract
00:46 +625: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 1: (-1,-1), timelineNow=0 → at=0, no log
00:46 +626: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 1: (-1,-1), timelineNow=10s → at=10s, no log
00:46 +627: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 2: (-1,0.5), timelineNow=0 → at=0, no log
00:46 +628: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 2: (-1,0.5), timelineNow=10s → at=10s, no log
00:46 +629: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 3: (1.0,-1), timelineNow=0 → at=0, no log
00:46 +630: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 3: (1.0,-1), timelineNow=10s → at=10s, no log
00:46 +631: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 4: (1.0,1.0), timelineNow=0 → at=0, no log
00:46 +632: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 4: (1.0,1.0), timelineNow=10s → at=10s, no log
00:46 +633: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 5: (1.0,1.10), timelineNow=0 → at=0, no log
00:46 +634: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 5: (1.0,1.10), timelineNow=10s → at=10s, no log
00:46 +635: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 6: (1.0,0.90), timelineNow=0 → at=0 (clamp), no log
00:46 +636: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 6: (1.0,0.90), timelineNow=10s → at=9.9s, no log
00:46 +637: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 7: (1.0,0.5001), timelineNow=0 → at=0 (clamp), no log
00:46 +638: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 7: (1.0,0.5001), timelineNow=10s → at=9.5001s, no log
00:46 +639: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 8: (1.0,0.50), timelineNow=0 → at=0 (lag nem levont), 1 warning
00:46 +640: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 8: (1.0,0.50), timelineNow=10s → at=10s (lag nem levont), 1 warning
00:46 +641: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 9: (1.0,0.4999), timelineNow=0 → at=0 (lag nem levont), 1 warning
00:46 +642: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 9: (1.0,0.4999), timelineNow=10s → at=10s (lag nem levont), 1 warning
00:46 +643: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.0 below threshold → no observation
00:46 +644: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.5499 below threshold → no observation
00:46 +645: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.55 exactly at threshold → observation emitted
00:46 +646: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.5501 above threshold → observation emitted
00:46 +647: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=1.0 maximum → observation emitted
00:46 +648: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix below-threshold strum advances dedup so the same seq does not re-emit
00:46 +649: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2b a lag hatóköre és a fajtánkénti padló (R2) de-jitter túléli a chord observationt (R0 PRÓBA-A)
00:46 +650: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2b a lag hatóköre és a fajtánkénti padló (R2) chord change-point nem kap idegen lagot (R0 PRÓBA-B, 300 ms)
00:46 +651: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2b a lag hatóköre és a fajtánkénti padló (R2) chord change-point nem kap idegen lagot (R2, 600 ms, határ fölött)
00:46 +652: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám változatlan timelineNow mellett a nagy lagú frame után a lag nélküli frame at-ja nem kisebb
00:46 +653: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám strumSeq 5→9 ugrás → observation sequence 0,1
00:46 +654: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám két küszöb feletti strum között egy küszöb alatti → sequence 0,1
00:46 +655: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám start → 3 strum → stop → start → 1 strum: utolsó sequence=0, at nem a régi lastEmittedAt-ra clampelve
00:46 +656: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix ugyanaz a label 10 frame-en belül → pontosan 1 ChordObservation
00:46 +657: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix label-váltás C → G → új observation
00:46 +658: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix akkord → nincs akkord → label:null observation is kiadódik
00:46 +659: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix nem kanonikus label a detektorból (Em7, G/B, H) → redukció, observation validate() üres
00:46 +660: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix változatlan label, de eltelt chordStableDuration → újramintavétel
00:46 +661: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix a Live úton a confidence mindig 1.0, és chordMinConfidence=0.99 SEM szűr chordot
00:46 +662: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus start ×2 → mindkettő Success, engine.startCalls == 1
00:46 +663: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus stop ×2 → mindkettő Success, engine.stopCalls == 1
00:46 +664: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus dispose után start/stop → Failure (gateway disposed)
00:46 +665: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus setExpectedChord → engine.expectedChordCalls utolsó eleme a label; stop után az utolsó elem null
00:46 +666: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus setExpectedChord a start előtt → sikeres start után az engine megkapja a labelt
00:46 +667: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés megtagadott engedély → Failure(PermissionFailure), engine.startCalls==0
00:46 +668: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés request() után granted → engine.startCalls==1
00:46 +669: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés érvénytelen config → Failure(configurationInvalid), engine.startCalls==0
00:46 +670: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés engine stream AudioFailure(audioSessionBusy) → stream hiba ugyanaz, engine.stopCalls==1, stream nem zárul be, újabb start sikerül
00:46 +671: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés engine stream StateError → AudioFailure(practiceObservationStreamFailed)
00:46 +672: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés a hiba után beküldött frame NEM ad observationt
00:46 +673: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.8 log-fegyelem 200 érvényes, observationt adó frame feldolgozása után a logger a start/stop páron kívül nem kap bejegyzést
00:46 +674: /home/ubuntu/ss-mm-e02-r17/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.8 log-fegyelem tíz, tartományon kívüli lagú frame ugyanabban a másodpercben → 1 warning
00:47 +675: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_integration_test.dart: perfect session: result is non-null, scorePoints > 0, navigateToResult fired exactly once
00:47 +676: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_integration_test.dart: wrong direction: matched strum with wrong direction → directionOutcome == wrong
00:47 +677: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_integration_test.dart: chord failure: matched strum with wrong chord → chordOutcome == wrong
00:47 +678: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_integration_test.dart: pause/resume: playingElapsed freezes, pausedElapsed grows, resume reaches running
00:47 +679: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_integration_test.dart: restart: from paused → countIn with attemptIndex + 1
00:47 +680: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_integration_test.dart: cancel: user cancel → result == null, recorder.recordCalls == 0
00:47 +681: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_integration_test.dart: stream failure: observation stream error → ShowRecoverableError, session stays running
00:47 +682: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_integration_test.dart: no signal: many unmatched strums → direction+rhythm MetricInsufficientData(noSignal)
00:47 +683: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_integration_test.dart: complete cleanup: FinishPractice → finished → full resource teardown (gateway dispose, tick stop, recorder called once)
00:47 +684: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_integration_test.dart: expected chord sequence: gateway.setExpectedChord called with each segment chord in order, then null on finish
00:48 +685: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_observation_activation_test.dart: maps every practice session status to its capture decision
00:48 +686: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_observation_activation_test.dart: policy keys cover exactly the session status enum
00:48 +687: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_observation_activation_test.dart: paused disables capture and closes the chunk 014 pause gap
00:48 +688: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_catalog_controller_test.dart: practiceCatalogProvider returns the full built-in catalog in declaration order
00:48 +689: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_catalog_controller_test.dart: practiceCatalogProvider is backed by the BuiltinPracticeCatalog by default
00:48 +690: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_catalog_controller_test.dart: practiceCatalogProvider rewires when practiceCatalogRepositoryProvider is overridden
00:49 +691: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_timing_test.dart: pause / resume bookkeeping pause does not advance activeElapsed or playingElapsed
00:49 +692: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_timing_test.dart: pause / resume bookkeeping playingElapsed advances only while status == running
00:49 +693: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_timing_test.dart: daily goal — countInBars=2, 4/4, 120 BPM (§6.4) 4 beats playing + 10s pause + 2 bars resume = exact playingElapsed
00:49 +694: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_timing_test.dart: countInBars == 0 countIn → running happens immediately at active=0
00:49 +695: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_timing_test.dart: resume-anchor (§5.5, §0.1) pause at countInDuration + 2.5 bars → resume anchors at the 2nd musical bar boundary
00:49 +696: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_timing_test.dart: resume-anchor (§5.5, §0.1) pause EXACTLY on a bar boundary → anchor is that boundary
00:49 +697: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_timing_test.dart: resume-anchor (§5.5, §0.1) pause 1µs after a bar boundary → anchor is the SAME boundary
00:49 +698: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_timing_test.dart: 3/4 meter (§0.1) resume count-in is 3 beats long, not 4
00:49 +699: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_timing_test.dart: 3/4 meter (§0.1) count-in click effects: initial count-in emits meter.beatsPerBar clicks
00:49 +700: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_timing_test.dart: RestartAttempt (§0.1) full second attempt: timelineBase=0, activeBase==activeElapsed, playingElapsed=0, wallElapsed continues
00:49 +701: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_timing_test.dart: session timeout (§5.6, §6.4) wallElapsed > sessionTimeout → finishing + timedOut
00:49 +702: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_timing_test.dart: session timeout (§5.6, §6.4) timeout wins over completedTimeline when both conditions met
00:49 +703: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_timing_test.dart: 0.5 practice speed (§0.1) halving effectiveTempo halves the bar boundaries — playingElapsed matches real time, not timeline time
00:49 +704: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_timing_test.dart: count-in click batching (§5.7) a single big ClockAdvanced spanning the whole count-in emits all click effects in order, no duplicates
00:49 +705: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_timing_test.dart: pause during count-in (§0.1) a single PausePractice during count-in freezes countInElapsed
00:49 +706: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_timing_test.dart: double pause/resume in same bar (§0.1) two consecutive pause/resume cycles preserve the timeline
00:49 +707: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_timing_test.dart: §6.1 purity guardrails (file-content checks) reducer does not define its own beat-to-time formula (no `bpm` or `60` literal)
00:50 +708: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_review_probes_test.dart: P1: permissionRequired + PreparationSucceeded is rejected
00:50 +709: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_review_probes_test.dart: P1b: permissionRequired + PreparationFailed is rejected
00:50 +710: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_review_probes_test.dart: P2: 2-bar initial count-in (4/4, 120 BPM) emits 8 clicks
00:50 +711: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_review_probes_test.dart: P3: timeout beats completedTimeline when both conditions hold
00:50 +712: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_review_probes_test.dart: P4: paused past sessionTimeout → finishing + timedOut
00:50 +713: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_review_probes_test.dart: P5: second attempt timelinePosition starts at Duration.zero
00:50 +714: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_review_probes_test.dart: P6: timelinePosition can exceed totalDuration, status is no longer running
00:50 +715: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_review_probes_test.dart: R1 MAJOR-3: statusPath walks every adjacent edge through allowedTransitions
00:50 +716: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_review_probes_test.dart: StartPractice sets countInSpanBeats = countInBars * beatsPerBar (R1 MAJOR-4)
00:51 +717: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A1 — status stream emits every transition idle → preparing → ready on PreparePractice + Succeeded
00:51 +718: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A1 — status stream emits every transition FinishPractice + tick crosses finishing → completed
00:51 +719: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A2 — capture-activation matrix startCalls == 1 when entering countIn
00:51 +720: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A2 — capture-activation matrix countIn → running keeps startCalls unchanged
00:51 +721: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A2 — capture-activation matrix running → paused stops the gateway exactly once
00:51 +722: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A2 — capture-activation matrix paused → countIn (resume) restarts the gateway (startCalls == 2)
00:51 +723: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A3 — finish single-flight multiple FinishPractice calls produce exactly one record()
00:51 +724: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A3 — finish single-flight finishReason maps to userFinished on FinishPractice
00:51 +725: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A4 — cleanup matrix completed: disposeCalls == 1, recordCalls == 1
00:51 +726: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A4 — cleanup matrix cancelled (a) user CancelPractice: disposeCalls == 1, recordCalls == 0
00:51 +727: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A4 — cleanup matrix cancelled (b) gateway-start Failure: cancelled, recordCalls == 0
00:51 +728: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A4 — cleanup matrix failed (compileTarget Failure) — preparing → failed, recordCalls == 0
00:51 +729: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A5 — error matrix permission denied during preparing → permissionRequired
00:51 +730: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A5 — error matrix compileTarget Failure → preparing → failed (reducer-origin effect)
00:51 +731: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A5 — error matrix gateway.start() Failure → cancelled, recorder NOT called
00:51 +732: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics running → paused: strum during pause does not change liveScore
00:51 +733: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics playingElapsed freezes during paused; pausedElapsed grows
00:51 +734: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics resume continues the timeline from the bar-boundary anchor (no jump)
00:51 +735: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 4/4 × countInBars=0: pause/resume cycle completes
00:51 +736: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 4/4 × countInBars=1: pause/resume cycle completes
00:51 +737: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 4/4 × countInBars=2: pause/resume cycle completes
00:51 +738: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 3/4 × countInBars=0: pause/resume cycle completes
00:51 +739: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 3/4 × countInBars=1: pause/resume cycle completes
00:51 +740: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 3/4 × countInBars=2: pause/resume cycle completes
00:51 +741: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A8 — single observation-config source gateway receives exactly the controller-provided config
00:51 +742: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A8 — single observation-config source 400ms chordStableDuration: 250ms-stable chord run → MetricInsufficientData(chordUnstable)
00:51 +743: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A8 — single observation-config source 180ms chordStableDuration: same 250ms run → MetricAvailable
00:51 +744: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A13 — noSignal pinned (current behaviour, NOT a fix) many unmatched strums → direction+rhythm MetricInsufficientData (noSignal); scorePoints == 0 (no matches, but signal was registered)
00:51 +745: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A14 — scoring pass discipline 100 ticks in running with no observation → liveScore unchanged
00:51 +746: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A14 — scoring pass discipline a ChordObservation alone → liveScore unchanged
00:51 +747: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A14 — scoring pass discipline a StrumObservation → liveScore changes (new aggregation)
00:51 +748: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A14 — scoring pass discipline FinishPractice alone does not change liveScore (the final pass updates `result`, not `liveScore`)
00:51 +749: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A15 — finishReason mapping cancelled by user → result == null
00:51 +750: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A15 — finishReason mapping cancelled by gateway failure → result == null
00:51 +751: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A15 — finishReason mapping failed → result == null
00:51 +752: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A16 — finishing is observable FinishPractice + tick crosses through finishing
00:51 +753: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A17 — failed is reachable ONLY from preparing (pin) PreparationFailed from countIn is rejected by the reducer
00:51 +754: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A17 — failed is reachable ONLY from preparing (pin) PreparationFailed from paused is rejected by the reducer
00:51 +755: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A17 — failed is reachable ONLY from preparing (pin) gateway-start failure → cancelled, recorder NOT called (R14 contract)
00:51 +756: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_controller_test.dart: A9 — controller layer-purity guard no forbidden symbol appears in the controller source (ADR 0077 §10 / R10d / R13)
00:52 +757: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig uses the brief defaults
00:52 +758: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig has value equality
00:52 +759: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig validates every confidence and duration boundary
00:52 +760: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig invalid config is represented by configuration.invalid
00:52 +761: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway keeps start and stop idempotent
00:52 +762: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway records expected chord and exposes a controllable stream
00:52 +763: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway returns the injected start result
00:52 +764: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway rejects operations after dispose
00:52 +765: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_reducer_test.dart: happy path: idle → preparing → ready → countIn → running → finishing → completed
00:52 +766: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_reducer_test.dart: permission path: preparing → permissionRequired → preparing → ready
00:52 +767: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_reducer_test.dart: pause/resume: the resume count-in actually runs
00:52 +768: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_reducer_test.dart: pause during count-in is accepted
00:52 +769: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_reducer_test.dart: cancel before start: ready → cancelled
00:52 +770: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_reducer_test.dart: cancel during running: running → cancelled
00:52 +771: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_reducer_test.dart: failure and retry: preparing → failed → preparing
00:52 +772: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_reducer_test.dart: double start: the second StartPractice is rejected; state unchanged
00:52 +773: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_reducer_test.dart: double finish: the second FinishPractice is rejected
00:52 +774: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_reducer_test.dart: restart attempt: paused → countIn, attemptIndex +1, attemptElapsed 0
00:52 +775: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_reducer_test.dart: background interruption: PausePractice(PauseCause.interruption) preserves the cause on the state
00:52 +776: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_reducer_test.dart: exhaustive transition matrix every (status, input) pair matches the pinned table
00:52 +777: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_reducer_test.dart: exhaustive transition matrix rejected transitions return the input state by value
00:52 +778: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_reducer_test.dart: exhaustive transition matrix reducer never throws on any (status, input) pair
00:52 +779: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_reducer_test.dart: rejection carries from / input / code; never throws
00:52 +780: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_reducer_test.dart: StartPractice is rejected when target is null
00:52 +781: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_reducer_test.dart: ChangeTempoBeforeAttempt updates config.effectiveTempo and invalidates target
00:52 +782: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_reducer_test.dart: §6.1 source-purity guardrails reducer does not define its own beat-to-time formula (no bare `bpm` identifier, no `60` literal in arithmetic)
00:52 +783: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_reducer_test.dart: §6.1 source-purity guardrails reducer source does not contain DateTime.now, Stopwatch, Random, print
00:52 +784: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_reducer_test.dart: §6.1 source-purity guardrails reducer / command / effect files do not import Flutter or Riverpod
00:53 +785: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock now() before any start() returns zero in every field
00:53 +786: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock start() places the clock in a fresh session state
00:53 +787: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock start() is idempotent: repeated start() does not throw or distort
00:53 +788: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock active + paused == wall invariant holds after pause and resume
00:53 +789: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock pause() while paused is a no-op (state-machine fields unchanged)
00:53 +790: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock resume() while running is a no-op (state-machine fields unchanged)
00:53 +791: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock resetAttempt() zeros attempt; paused unchanged; wall/active unchanged
00:53 +792: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock start() while paused is a no-op (no fields reset)
00:53 +793: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock now() before any start() returns zero in every field
00:53 +794: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() places the clock in a fresh session state
00:53 +795: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() is idempotent: repeated start() does not throw or distort
00:53 +796: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock active + paused == wall invariant holds after pause and resume
00:53 +797: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock pause() while paused is a no-op (state-machine fields unchanged)
00:53 +798: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resume() while running is a no-op (state-machine fields unchanged)
00:53 +799: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resetAttempt() zeros attempt; paused unchanged; wall/active unchanged
00:53 +800: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() while paused is a no-op (no fields reset)
00:53 +801: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock advance() grows wall by the delta while running
00:53 +802: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock advance() while paused grows wall AND paused; active stays put
00:53 +803: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock advance() after resume resumes active growth from the resume point
00:53 +804: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resetAttempt() after an active session only zeros attempt
00:53 +805: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() after pause is a no-op (clock stays paused, fields intact)
00:53 +806: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock pause() before start() is a no-op (no fields change)
00:53 +807: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resetAttempt() before start() is a no-op
00:53 +808: /home/ubuntu/ss-mm-e02-r17/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock active + paused == wall invariant holds across 200 random steps
00:53 +809: All tests passed!

    → [3] test test/features/practice/: ZÖLD

═══ [4] test test/property/speed_builder_property_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/property/speed_builder_property_test.dart

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
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.0 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.5.0 available)
  permission_handler_html 0.1.3+5 (0.1.4+0 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
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
  vector_math 2.2.0 (2.4.2 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
38 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-mm-e02-r17/test/property/speed_builder_property_test.dart
PROPERTY_SEED=42
00:00 +0: A10 — randomized Speed Builder invariants
00:00 +1: All tests passed!

    → [4] test test/property/speed_builder_property_test.dart: ZÖLD

═══ [5] test test/core/l10n_parity_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/core/l10n_parity_test.dart

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
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.0 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.5.0 available)
  permission_handler_html 0.1.3+5 (0.1.4+0 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
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
  vector_math 2.2.0 (2.4.2 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
38 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-mm-e02-r17/test/core/l10n_parity_test.dart
00:00 +0: (setUpAll)
00:00 +0: en and hu define exactly the same keys
00:00 +1: no locale has an empty translation
00:00 +2: hu uses the same placeholders as en
00:00 +3: (tearDownAll)
00:00 +3: All tests passed!

    → [5] test test/core/l10n_parity_test.dart: ZÖLD

═══ [6] architecture
    $ /home/ubuntu/flutter/bin/dart run tool/check_architecture.dart

Running build hooks...Running build hooks...Architecture dependencies OK (12 allowlisted deviation(s)).

    → [6] architecture: ZÖLD

═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/features/practice/                               zöld
    test test/property/speed_builder_property_test.dart        zöld
    test test/core/l10n_parity_test.dart                       zöld
    architecture                                               zöld

MINDEN GATE ZÖLD. A teljes suite + randomizált property gate + APK a CI-ban
fut (ADR 0053) — azt az orchestrátor indítja, te ne hívj gh-t.

```

## 11. Review — Claude tölti ki

Link: `docs/reviews/e02-r17-review.md`

Kiemelt figyelem: az A6 négy cellája (stabil BPM), az A2/A3 streak-nullázása,
és **valódi-sértés próba** az A9-re (auto-apply beszúrása → pirosnak kell lennie).
