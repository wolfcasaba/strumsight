# E07-R23 — PlanCompiler és Practice Engine végrehajtás

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-18, kód olvasva: `main @ d67d102a`; előre megírva 2026-08-15, kód olvasva akkor: `main @ 19b30557`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 23
- **Kör-azonosító:** `E07-R23`
- **Branch:** `<motor>/e07-r23-plan-compiler-and-execution`
- **Előfeltétel:** `E07-R22` merge-elve (Today képernyő)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0268`](../adr/0268-technical-failure-is-not-skill-failure.md)
  — **MÁR MEGÍRVA, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd meg a Practice Engine
> **tényleges** `public.dart` felületét (definíció-típus, session-eredmény
> alakja), mert a §5 erre épül. Olvasd újra az R08 katalógus-revízióit is.
> Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice_generator/domain/service/plan_compiler.dart",
  "lib/features/practice_generator/application/service/plan_execution_coordinator.dart",
  "lib/features/practice_generator/data/adapter/practice_outcome_adapter.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/execution/plan_compiler_test.dart",
  "test/features/practice_generator/execution/plan_execution_coordinator_test.dart",
  "test/fixtures/practice_generator/execution/",
  "docs/rounds/e07-r23-plan-compiler-and-execution.md",
]
gate_tests = [
  "test/features/practice_generator/execution/plan_compiler_test.dart",
  "test/features/practice_generator/execution/plan_execution_coordinator_test.dart",
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

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Pre-flight mérés és brief-revízió (Claude Opus 5, 2026-08-18, kód olvasva: `main @ d67d102a`)

**1. A `PracticeSessionResult` a Practice Engine-ben KIZÁRÓLAG a `completed` ágon
keletkezik — a `cancelled` és `failed` terminális állapot NEM állít elő
eredményt.** Mérve: ADR 0077 §9 ("Result kizárólag a `completed` ágon készül...
a `cancelled` és a `failed` terminal státusz nem állít elő
`PracticeSessionResult`-ot") és a MA ÉLŐ kód,
`practice_session_controller.dart:245-256` ("Terminal-state cleanup. Per A15,
`PracticeSessionResult` and the `recorder.record()` call are reserved for the
`completed` branch; the `cancelled` and `failed` branches run only the
resource-cleanup half."): az `if (newStatus == completed) { …
_finalizeSession(…); } else if (cancelled) { _cleanupTerminalResources(); }
else if (failed) { _cleanupTerminalResources(); }` elágazás valóban csak a
`completed` ágon épít result objektumot. A result-oldali
`PracticeFinishReason.interrupted` ráadásul EGYETLEN production helyen sem
keletkezik (`grep -rn "PracticeFinishReason\." lib/features/practice
--include=*.dart` → 0 találat `.interrupted`-re; a `_mapFinishReason`
kimerítő switch-e az 5 state-oldali értéket 5 result-oldali értékre képezi,
`interrupted` nélkül — a doc-comment ezt explicit ki is mondja).

**Következmény:** a brief §6.1 3-soros mérce-mátrixa ("technikai hiba" /
"megszakította" / "végigcsinálta") NEM építhető pusztán egy bejövő
`practice.PracticeSessionResult.finishReason` vizsgálatából, mert a
"technikai hiba" és a "megszakította" eset ÉPP AZOKON az ágakon áll elő
(`failed`, `cancelled`), amelyeken a Practice Engine ma egyáltalán NEM
produkál result objektumot. A Practice Engine módosítása ennek a körnek
tiltott zónája (§3) — a feloldás ezért a
`PlanExecutionCoordinator`/`PracticeOutcomeAdapter` BEMENETI szerződésének a
kérdése, nem a Practice Engine-é.

**Feloldás (`allowed_paths` változatlan — mindhárom pont a már engedélyezett
3 új fájlban oldható meg):**

a) A `PracticeOutcome.completionState` normatív forrása **SDD Ch8 §26.2** —
szó szerint hat érték: `completed / partial / skipped / cancelled /
failedTechnical / unavailable` ("A skip önmagában nem performance failure.").
Ez PONTOSÍTJA, nem helyettesíti a §6.1 3-soros mátrixát. Eredet szerinti
csoportosítás (mérve a Practice Engine-en, fent):

| `completionState` | Honnan ered | Van mögötte `PracticeSessionResult`? |
|---|---|---|
| `unavailable` | a blokk indítás ELŐTT elakad (elavult revízió / hiányzó capability, §5.2) | nincs — a coordinator sosem indítja a sessiont |
| `skipped` | a blokkot explicit kihagyják indítás előtt | nincs |
| `failedTechnical` | Practice Engine `failed` terminal állapot (mikrofon/permission/crash) | **nincs** — a coordinatornak ezt a hívótól kapott, `PracticeSessionResult`-tól FÜGGETLEN jelzésként kell fogadnia |
| `cancelled` | Practice Engine `cancelled` terminal állapot (explicit `CancelPractice`), mérhető attempt nélkül | **nincs** — ugyanaz az ok |
| `partial` | a session elérte a `completed` állapotot, de NEM `completedAllTargets`-tel (`userFinished` vagy `timedOut` `finishReason`) — van mérhető attempt-adat | **van** |
| `completed` | `PracticeFinishReason.completedAllTargets` | **van** |

b) Emiatt a coordinátor/adapter bemenete NEM lehet kizárólag
`practice.PracticeSessionResult` — definiáljon saját, hívó-táplált bemeneti
szerződést (pl. a `practice_outcome_adapter.dart`-ban élő union/sealed típus:
egy `PracticeSessionResult`-et hordozó ág ÉS egy attól független,
"nincs result, mert cancel/technical-failure" ág) — ugyanaz a hívó-táplált
minta, mint a Kör 8 katalógus-adapteré (saját Riverpod-függőség és élő
subscription nélkül). A valós Practice Engine `cancelled`/`failed` ágának
ehhez kötése (a ma hiányzó result-termelés pótlása) egy JÖVŐBELI wiring-kör
dolga — ebben a körben a `cancelled`/`failedTechnical` teszt-cellák a
hívó-táplált szerződésen át közvetlenül konstruálnak bemenetet, valós
Practice Engine session nélkül.

c) `PracticeFinishReason.interrupted` a mérés szerint sosem keletkezik éles
kódúton — az adapter kezelje védekező, de nem termelő ágként (ugyanaz a
"stabil kódú, hívatlan érték" minta, mint az R08 katalógus-adapter több
enum-tagja).

**2. Az elavult blokk ellenőrzésének köre helyesen szűk — nincs teendő.** Az
SDD §25.4 nyolc staleness-dimenziót sorol fel, de a Kör 23 saját SDD
feladatlistája kifejezetten csak kettőt ír elő: "Ellenőrizd exercise
revisiont és capabilityt start előtt" — ez pontosan fedi a brief §5.2
szövegét. A többi hat dimenzió (dal/range/tuning → Kör 24 Song Trainer
integráció; plan revízió/blokk-kor/goal → későbbi tervrevíziós kör) NEM
ennek a körnek a hatásköre — az implementer ne próbálja mind a nyolcat
lefedni.

**3. Az új típusok a 3 már engedélyezett fájlban kapnak otthont, NEM új
domain/model fájlban.** Az SDD `PracticeOutcome` (§26.1) és `CompiledPlanStep`
(§25.2) dataclass-alakot ír elő, de az `allowed_paths` nem tartalmaz
`domain/model/practice_outcome.dart`-ot vagy hasonlót. A repo bevett mintáját
követve (kis kísérő típusok a tulajdonos fájlban, pl.
`RepetitionPrescription`/`FallbackReference` az `exercise_prescription.dart`-ban):
a `CompiledPlanStep` a `plan_compiler.dart`-ban, a `PracticeOutcome` +
completion-state/user-feedback típusai a `practice_outcome_adapter.dart`-ban,
a `blockExecutionId` (típusos wrapper, SDD §9.1 mintáját követve) pedig a
`plan_execution_coordinator.dart`-ban (ahol mintázódik) definiálandó — így
elkerülhető egy indokolatlan H3.

**Összegzés:** mindhárom pont a MÁR engedélyezett fájlokon belül oldható fel
— `allowed_paths`/`gate_tests` változatlan.

## 1. Cél

A terv-blokkok validált Practice Engine lépéssé fordítása és az eredmény
visszacsatolása (SDD Ch8 Kör 23).

## 2. Jelenlegi állapot — mért tények

- Az R08 katalógus-pillanatképe **két revíziót** hordoz (ADR 0262 §3) — ebből
  derül ki, ha egy blokk elavult.
- Az R09 receptjei korlátosak, a sikerkritérium mérhető.
- Az ADR 0260 §3: az eredmény-dedup kulcsa a forrás outcome ID-ja.

## 3. Scope

**Benne van:** blokk → végrehajtható lépés fordítása · **revízió- és
capability-ellenőrzés indítás előtt** · a recept konfigjának átadása ·
`blockExecutionId` képzése · a session-eredmény fogadása és normalizálása ·
megszakítás, részleges és **technikai hiba** kezelése.

**NINCS benne (tilos):** a Practice Engine módosítása · a terv revíziójának
írása (Kör 26) · flag `true`-ra állítása · más feature belső importja ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `domain/service/plan_compiler.dart` | **ÚJ** — a fordító |
| `application/service/plan_execution_coordinator.dart` | **ÚJ** — indítás + eredmény |
| `data/adapter/practice_outcome_adapter.dart` | **ÚJ** — eredmény-normalizálás |
| `public.dart` | a barrel bővítése |
| `test/…/execution/*_test.dart` (2 db) | a §6 cellái |
| `docs/rounds/e07-r23-…md` | a §10 handoff |

**Tilos zóna:** más `lib/features/**` tartalma (a `public.dart`-jukon át
olvasható) · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**`.

## 5. Kötött architekturális döntések (ADR 0268)

### 5.1 A TECHNIKAI hiba NEM skill-hiba

Mikrofon-hiba, összeomlás, hiányzó asset, engedély-megtagadás → **nem** a
tanuló teljesítménye. Ilyen eredmény nem csökkentheti a becslést és nem
válthat ki regressziót (ADR 0265 §4).

**NEM elfogadható gyengítés:** „nem sikerült teljesíteni, tehát gyenge".

### 5.2 Az ELAVULT blokk nem indul

Ha a hivatkozott gyakorlat revíziója megváltozott vagy a capability eltűnt, a
blokk **nem indul el** — helyettesítést vagy újratervezést kér.

### 5.3 Az eredmény IDEMPOTENS

Ugyanaz a `blockExecutionId` kétszer visszatérve egyszer könyvelődik
(ADR 0260 §3 folytatása).

### 5.4 A session-konfig MEGFELEL a receptnek

Amit a tervező előírt (időtartam, tempó, ismétlés), az megy át a végrehajtóhoz
— nem „körülbelül". Eltérés esetén hiba, nem csendes igazítás.

### 5.5 A megszakított session RÉSZLEGES, nem sikertelen

A tanuló megszakítása nem kudarc: külön kimenet, ami nem büntet
(az R17 §5.2 „bizonytalan nem büntet" elvének rokona).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Technikai hiba NEM csökkenti a becslést, nem vált ki regressziót | `plan_execution_coordinator_test.dart` |
| A2 | Elavult revíziójú blokk nem indul | `plan_compiler_test.dart` |
| A3 | Hiányzó capability esetén a blokk nem indul | ugyanott |
| A4 | Az eredmény idempotens (kétszeri visszatérés) | `plan_execution_coordinator_test.dart` |
| A5 | A session-konfig pontosan a recept szerinti | `plan_compiler_test.dart` |
| A6 | A megszakított session részleges, nem sikertelen | `plan_execution_coordinator_test.dart` |
| A7 | `blockExecutionId` egyedi és visszakereshető | ugyanott |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A technikai hiba kudarcként könyvelve | **A1** |
| Elavult blokk elindítva | **A2** |
| Az eredmény kétszer könyvelve | A4 |
| „Körülbelüli" session-konfig | A5 |
| A megszakítás kudarcként | A6 |

**Az eredmény-típus három kötelező cellája** (a küszöb: a tanuló teljesítménye):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | **technikai** hiba (mikrofon, összeomlás) | **nem** számít teljesítménynek — a becslés változatlan |
| rajta (a küszöbön) | a tanuló **megszakította** | részleges — nem büntet |
| a küszöb fölött | végigcsinálta, mért eredménnyel | teljes értékű evidence |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** könyveld a technikai
hibát sikertelen teljesítményként → az **A1** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/execution/plan_compiler_test.dart test/features/practice_generator/execution/plan_execution_coordinator_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `plan_compiler.dart` — fordítás + revízió/capability ellenőrzés.
2. `practice_outcome_adapter.dart` — az eredmény-típusok szétválasztása.
3. `plan_execution_coordinator.dart` — indítás, idempotens visszacsatolás.
4. Tesztek a §6.1 három eredmény-cellájával.
5. A valódi-sértés próba, §10-be dokumentálva.
6. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A technikai hiba mint kudarc.** A legkárosabb: a tanuló azért kap
  könnyebb tervet, mert elromlott a mikrofonja (A1).
- **Az elavult blokk.** A katalógus alatta változik, és a tanuló olyat
  gyakorolna, ami már nem az (A2).
- **A „körülbelüli" konfig.** A tervező 60 BPM-et írt elő, a végrehajtó 70-et
  indít — és a mérés értelmetlenné válik (A5).

## 10. Implementation handoff — az implementer tölti ki

### E07-R23 implementation (Codex, 2026-08-18)

- `PlanCompiler` now converts only caller-verified, current exercise facts
  into a `CompiledPlanStep`; a content-revision mismatch or a missing required
  capability yields an explicit `UnavailablePlanStep` with a replan fallback.
  The compiled configuration keeps the prescription's active/rest time, tempo,
  repetition bounds, loop count, and elapsed limit without approximation.
- `PlanExecutionCoordinator` verifies the Practice Engine public
  `PracticeSessionConfig` exactly against that compiled configuration, creates
  a unique `BlockExecutionId` that retains its plan/revision/day/block origin,
  and keeps first-write-wins outcome ingestion in process.
- `PracticeOutcomeAdapter` accepts a `PracticeSessionResult` only on its
  completed-session branch. Cancellation and technical failure instead use
  caller-fed terminal input variants; technical failure and partial outcomes
  cannot contribute skill evidence or request a regression.
- The public barrel now exposes the execution outcome contract. Its older
  serializer-only `PracticeOutcome` is hidden from the public barrel; local
  persistence continues to import that record directly.

#### Acceptance evidence

- A1: technical failure has no skill-evidence or regression disposition.
- A2/A3: stale content revision and a missing required capability both refuse
  launch.
- A4: replaying a `blockExecutionId` returns the original outcome as a
  duplicate.
- A5: every prescribed execution value is retained exactly.
- A6: `PracticeFinishReason.interrupted` normalizes to `partial`, not failure.
- A7: generated IDs differ and expose their plan/revision/day/block origin.

#### Required real-violation test

Temporarily changed `contributesSkillEvidence` so
`failedTechnical` returned `true`, then ran the required gate. Format, analyze
and the compiler test stayed green; A1 failed exactly as intended:
`Expected: false / Actual: <true>` in
`plan_execution_coordinator_test.dart`. The safe completed-only rule was then
restored before the final gate.

The review-required A5 negative cell now passes a `mismatchedSessionConfig()`
whose `loopCount` differs from the compiled prescription. I temporarily removed
the coordinator's exact-match `if` branch and ran the coordinator test: A5
failed exactly as intended, because the call returned `PlanExecutionLaunch`
instead of throwing `ArgumentError`. The branch was restored before the final
gate.

#### Final verification

`tools/round-gate.sh test/features/practice_generator/execution/plan_compiler_test.dart test/features/practice_generator/execution/plan_execution_coordinator_test.dart`
completed after restoration: format, analyze, both focused test files, and
the architecture gate were green.

## 11. Review — a Claude tölti ki
