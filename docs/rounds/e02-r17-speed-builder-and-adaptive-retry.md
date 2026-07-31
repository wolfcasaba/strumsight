# E02-R17 — Speed Builder, loop és adaptív retry

- **Státusz:** **PREPARED** (előre megírva 2026-07-31, kód olvasva: `main` @ `ce8fbce`)
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

*(Fájlonkénti összefoglaló · a záró gate TÉNYLEGES, teljes kimenete · az A1–A11
pontok teljesülése bizonyítékkal · eltérések és okuk · follow-upok.)*

## 11. Review — Claude tölti ki

Link: `docs/reviews/e02-r17-review.md`

Kiemelt figyelem: az A6 négy cellája (stabil BPM), az A2/A3 streak-nullázása,
és **valódi-sértés próba** az A9-re (auto-apply beszúrása → pirosnak kell lennie).
