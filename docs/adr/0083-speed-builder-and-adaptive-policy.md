# ADR 0083 — Speed Builder és adaptív retry: determinisztikus, pure policy

**Státusz:** elfogadva (E02-R17 pre-flight, 2026-08-01).
Épít az [ADR 0072](0072-practice-time-layer.md) (`CompiledPracticeTarget`,
`Tempo`, loop-réteg), [ADR 0076](0076-practice-scoring.md) (`PracticeVerdict`,
`PracticeMetrics`, `MetricValue`), [ADR 0077](0077-practice-session-controller.md)
(`PracticeSessionController`, attempt-lánc: `attemptIndex`, `RestartAttempt`,
`ChangeTempoBeforeAttempt`) és [ADR 0082](0082-free-practice-honest-summary.md)
(mért-alapú, hamis-állítás nélküli összegzés) döntéseire.
Kör: [`docs/rounds/e02-r17-speed-builder-and-adaptive-retry.md`](../rounds/e02-r17-speed-builder-and-adaptive-retry.md).
SDD: [`docs/sdd/03-epic-02-practice-engine.md`](../sdd/03-epic-02-practice-engine.md)
§16.7, §18, §19 („Kör 17").

## Kontextus

A tempóépítés (Speed Builder) több attemptes workflow, amely a teljesítmény
alapján lépteti a BPM-et; az adaptív retry attempt UTÁN, a felhasználó
elfogadásával változtat a nehézségen. A kör tétje a **determinizmus**: a
felhasználó soha nem találkozhat azzal, hogy a tempó vagy a cél menet közben,
magától megváltozott.

A döntéseket mért kód rögzíti (`main` @ `caca3a9`, pre-flight mérés 2026-08-01):

1. **Nincs Speed Builder semmilyen formában** (`grep -rni "speedbuilder\|speed_builder" lib/`
   → 0 találat). A `speed_builder_policy.dart` (SDD §8.1) nem létezik.
2. **`Tempo`** (`tempo.dart:10-11`): `minimumBpm = 30.0`, `maximumBpm = 300.0`,
   zárt tartomány, **clamp nélkül**, `validate()` stabil kóddal
   (`tempoBpmOutOfRange`).
3. **`PracticeAttemptResult`** (`practice_attempt_result.dart:34`): `index`,
   `tempo`, `metrics`, `verdicts`, `outcome`. **`PracticeAttemptOutcome`**
   (`:10`): `passed`, `failed`, `incomplete`, `notScored`.
4. **`PracticeMetrics`** (`practice_metrics.dart:97`) per-dimenzió mezői
   `MetricValue` típusúak: `completion`, `rhythm`, `direction`, `chord`,
   `overall`. A `MetricValue` sealed altípusai (`:7-93`):
   `MetricAvailable(double value ∈ [0,1])`, `MetricNotApplicable()`,
   `MetricInsufficientData(reasonCode)`.
5. **Mért kulcs-megkülönböztetés (a kör legfontosabb hamis-állítás kockázata):**
   a **plain scored-practice pass** és a **Speed Builder step-up pass** KÉT
   KÜLÖN küszöb.
   - A plain pass a `_outcome()`-ban dől el
     (`practice_score_aggregator.dart:267-270`):
     `completion ≥ completionThresholdPercent` **és** `overall ≥ overallThresholdPercent`.
     A profilokban (`scoring_profile.dart`) ezek **85 / 70** — ez adja a
     `PracticeAttemptOutcome.passed`-et.
   - A `ScoringProfile` **NEM** tartalmaz `0.95 / 0.85 / 0.80` értékeket, és
     **nincs** külön rhythm-threshold mezője. A step-up küszöb tehát **nem
     olvasható ki a `ScoringProfile`-ból**, és **nem azonos** az
     `outcome == passed`-del.
6. **SDD §16.7** a step-up küszöböt külön blokkban rögzíti:
   `completion ≥ 0.95` **és** `overall ≥ 0.85` **és** `rhythm ≥ 0.80, ha
   alkalmazható` — „policy értékek, nem szétszórt konstansok".
7. **Attempt-lánc** (`practice_session_controller.dart`, R07): `attemptIndex`,
   `RestartAttempt`, `ChangeTempoBeforeAttempt` — a policy ide illeszkedik, de
   a controller **bekötése NEM ebben a körben** (SDD §18/§19 tiszta-mérhetőség).

## Döntés (NEM tárgyalható — a kör kötött szabályai)

1. **A policy pure és determinisztikus.** `(state, attemptResult) → state`;
   nincs benne óra, random, IO vagy Riverpod. Azonos bemenet-sorozatra azonos
   kimenet, minden futásban.

2. **Konfiguráció és validáció** (SDD §19.1): `startBpm` pozitív és
   `Tempo`-érvényes; `targetBpm ≥ startBpm` és `Tempo`-érvényes; `stepBpm`
   **1..20** (zárt); `maxAttempts` **1..100** (zárt);
   `requiredConsecutivePasses ≥ 1`; `reduceAfterConsecutiveFails ≥ 1`.
   A validáció **stabil kódokat** ad (`PracticeValidationFailure`), a R03-as
   mintát követve, és **minden** független problémát visszaad (nem az elsőnél
   áll meg).

3. **A step-up pass predikátum a metrikákból számol, a `ScoringProfile`-tól
   FÜGGETLENÜL** (mért döntés, §5. és §6. pont): egy attempt a Speed Builder
   értelmében akkor „passzol" (step-up jelölt), ha
   - `completion` **`MetricAvailable`** és `value ≥ 0.95`, **és**
   - `overall` **`MetricAvailable`** és `value ≥ 0.85`, **és**
   - `rhythm` esetén: ha `rhythm` **`MetricAvailable`** → `value ≥ 0.80`
     kötelező; ha `rhythm` **`MetricNotApplicable`** → a feltétel **kimarad**
     (nem bukik el); egyéb (`MetricInsufficientData`) → **nem** step-up pass.
   - Ha `completion` vagy `overall` **nem** `MetricAvailable` → **nem** step-up
     pass.
   Ez a predikátum **nem** egyenlő az `attemptResult.outcome == passed`-del, és
   **tilos** onnan levezetni. A `0.95 / 0.85 / 0.80` konstansok **EGY** helyen
   élnek a Speed Builder domainben (nevesített konstansként), nem három
   widgetben és nem a `ScoringProfile`-ban.

4. **Léptetési szabályok** (SDD §19.2), a §3. step-up-pass fogalmával:
   - step-up pass → `successStreak++`, `failStreak = 0`;
   - `successStreak ≥ requiredConsecutivePasses` → BPM `+= stepBpm`, és a
     `successStreak` **nullázódik**;
   - nem step-up pass (fail/incomplete/notScored) → `failStreak++`,
     `successStreak = 0`;
   - `failStreak ≥ reduceAfterConsecutiveFails` → BPM `−= stepBpm`, és a
     `failStreak` **nullázódik**;
   - a BPM **soha nem megy** `startBpm` alá és `targetBpm` fölé (mindkettő
     zárt korlát; a `Tempo` 30–300 tartomány ezen felül is tartandó);
   - `targetBpm`-en elért `requiredConsecutivePasses` egymást követő step-up
     pass → **completed**, nincs további emelés;
   - `maxAttempts` elérése vagy user-finish → a session lezárul (idempotens: a
     lezárás után érkező eredmény nem változtat és nem dob).

5. **BPM csak attempt-határon változik.** A policy kimenete a **következő**
   attempt tempója; futó attempt tempóját semmi nem módosíthatja.

6. **„Legmagasabb stabil BPM"** (SDD §19.3): az a legnagyobb tempó, amelyen a
   felhasználó **legalább `requiredConsecutivePasses` egymást követő step-up
   passt** ért el azon a tempón. **Egyetlen szerencsés attempt nem stabil** —
   ez invariáns, nem opció. Ha ilyen nincs: `null` / `InsufficientData`
   (a session UI lokalizált „még nincs" szöveget mutat, **nem** 0 BPM-et).

7. **Adaptáció csak attempt UTÁN és csak elfogadással.** A policy
   **javaslatot** ad; a változás **kizárólag** a felhasználó explicit
   elfogadására (vagy előre bekapcsolt auto-policyval) történik. Attempt
   közbeni csendes változtatás TILOS. A `AdaptivePracticePolicy.evaluate`
   (SDD §18.3) pure: `{current, history, config} → AdaptiveSuggestion?`; aktív
   attemptre **`null`** a szerződés (nem javaslat).

8. **A javaslat-prioritás rögzített** (SDD §18.2/§17.3 sorrendje):
   nincs elég jel → alacsony completion → domináns early/late bias →
   direction-hiba → chord-hiba → konkrét chord-pair → tempó túl magas → pozitív
   megerősítés → következő nehézség. Holtversenynél a **listasorrend** dönt,
   **nem** a `Map` iteráció.

9. **A controller bekötése NEM ebben a körben.** A policy és az állapot pure; a
   `PracticeSessionController`-be kötést az **E02-R18** vagy dedikált javító kör
   végzi. A session-UI a widgetjeit **injektált** állapottal rendereli.

## Következmények

- A step-up küszöb (0.95/0.85/0.80) és a plain pass (0.85/0.70) szándékosan
  eltér; a step-up szigorúbb. Aki az `outcome == passed`-re épít, elrontja a
  léptetést — az A6 stabil-BPM mátrix (§6) és az A2 streak-nullázás ezt fogja
  pirosra.
- A `rhythm` „ha alkalmazható" feltétele mérten a `MetricNotApplicable`
  sentinellel dől el (Rhythm-only és Free Practice profilok mérték ki a
  metrika-alkalmazhatóságot, ADR 0082) — nem heurisztika.
- A pure, controller-mentes policy tisztán property-testelhető (A10): a BPM
  mindig `[startBpm, targetBpm]`-ben, lépésenként legfeljebb egy `stepBpm`, a
  stabil BPM sosem nagyobb a valaha elért maximumnál, az attempt-történet sosem
  lépi túl `maxAttempts`-et, és az állapotgép sosem dob.
- A controller-bekötés hiánya tudatos adósság: E02-R18 hatóköre.
