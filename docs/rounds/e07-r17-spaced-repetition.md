# E07-R17 — Spaced repetition és maintenance queue

- **Státusz:** PLANNING (pre-flight revízió: 2026-08-18, `main @ e527dec1`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 17
- **Kör-azonosító:** `E07-R17`
- **Branch:** `<motor>/e07-r17-spaced-repetition`
- **Előfeltétel:** `E07-R16` merge-elve (progresszió)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [0303](../adr/0303-spaced-repetition-review-queue-contract.md)
  — a review-cél, eredmény, nap-budget és törölt-tartalom explicit domain szerződése.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R03 helyi-dátum
> modelljét (a due date erre épül) és az R08 katalógus-revízióit (a törölt
> tartalom felismeréséhez). Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/practice_generator/domain/model/review_item.dart",
  "lib/features/practice_generator/domain/policy/spaced_repetition_policy.dart",
  "lib/features/practice_generator/domain/service/review_queue.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/review/review_queue_test.dart",
  "test/features/practice_generator/review/spaced_repetition_policy_test.dart",
  "test/fixtures/practice_generator/review/",
  "docs/rounds/e07-r17-spaced-repetition.md",
  "docs/adr/0303-spaced-repetition-review-queue-contract.md",
]
gate_tests = [
  "test/features/practice_generator/review/review_queue_test.dart",
  "test/features/practice_generator/review/spaced_repetition_policy_test.dart",
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

## 0.0 Pre-flight revízió (2026-08-18)

- **Mérés:** `LocalDate` a `domain/model/weekly_availability.dart` tiszta
  év/hónap/nap value object; nincs offset vagy `DateTime`, ezért a due date
  ebből származhat és időzóna-váltástól független marad. Az R08
  `PracticeCatalogSnapshot` csak a catalog/content revisionök eltérését méri;
  konkrét törölt targetet nem azonosít. A tényleges executable identity az
  `ExerciseCandidate.source.code:exerciseId` (`exercise_candidate.dart`), és
  nincs meglévő `ReviewItem`, review-eredmény vagy review-queue input.
- **Feloldás:** ADR 0303 szerint az új `ReviewTarget` saját, stabil
  `kind + targetId` identitású (chord transition, strumming pattern, lesson,
  song section), tehát nem hamisan azonos a jelenlegi catalog candidate-tel.
  A `ReviewQueue` explicit current-target halmazt kap: hiányzó targetből
  `replacementRequired` állapotú elem lesz, nem törlődik. A napi input explicit
  `totalDailyMinutes` és `reviewBudgetMinutes`; a konstruktor megköveteli,
  hogy `0 <= reviewBudgetMinutes < totalDailyMinutes`, ezért a queue önmagában
  sem töltheti ki a napot, és nem számolja újra az R15 arány-policyt.
  A `SpacedRepetitionPolicy` csak explicit `LocalDate` és előző intervallum
  alapján dolgozik; `unknown` változatlanul hagyja az intervallumot.
- **Scope:** a lefoglalt ADR 0303 és ez a brief a kör saját, még nem merge-elt
  pre-flight artefaktuma, ezért az allowlistben kifejezetten szerepel. Más ADR,
  SDD, tool vagy production útvonal továbbra is tilos.

## 1. Cél

A korábban megtanult skill- és tartalomelemek időzített, **korlátozott**
fenntartása (SDD Ch8 Kör 17).

## 2. Jelenlegi állapot — mért tények

- Az R03 helyi-dátum modellje (ADR 0258 §4) — a due date ehhez igazodik.
- Az R08 katalógus-revíziója alapján felismerhető a **törölt** tartalom.
- Az R15 ütemezője **korlátos arányban** enged ismétlést a napba.

## 3. Scope

**Benne van:** `ReviewItem` életciklus · **egyszerű, magyarázható** intervallum-
politika · sikeres / részleges / sikertelen / **bizonytalan** kimenet kezelése ·
napi review-budget · akkord-, minta-, lecke- és dalszakasz-hivatkozás ·
azonos cél deduplikálása.

**NINCS benne (tilos):** orchestrator (Kör 18) · repository (Kör 19) · a napi
budget túllépése · Flutter, `DateTime.now()`, `Random` · más
`lib/features/**`, `docs/adr/**`, `tools/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `domain/model/review_item.dart` | **ÚJ** — elem + életciklus |
| `domain/policy/spaced_repetition_policy.dart` | **ÚJ** — intervallumok |
| `domain/service/review_queue.dart` | **ÚJ** — a sor, budgettel |
| `public.dart` | a barrel bővítése |
| `test/…/review/*_test.dart` (2 db) | a §6 cellái |
| `docs/rounds/e07-r17-…md` | a §10 handoff |
| `docs/adr/0303-spaced-repetition-review-queue-contract.md` | a kör saját, még nem merge-elt domain-szerződése |

**Tilos zóna:** más `lib/features/**` · `lib/app/**` · `docs/adr/**` (kivéve a
fenti ADR 0303) · `docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 A sor NEM töltheti ki a napot

A napi review-budget felső korlát, és az R15 arány-korlátjával együtt hat.
A fenntartás nem szoríthatja ki a fejlődést.

**NEM elfogadható gyengítés:** „ma sok az esedékes, kivételesen több fér be".

### 5.2 A BIZONYTALAN mérés NEM büntet

Ha a mérés bizonytalan (alacsony confidence, hiányos adat), az **nem**
sikertelen ismétlés: az intervallum nem rövidül. Az `unknown` nem gyengeség
(ADR 0261 §2) — itt sem.

**NEM elfogadható gyengítés:** a bizonytalant sikertelenként kezelni „biztos,
ami biztos" alapon. Az a tanulót fölöslegesen visszaforgatná.

### 5.3 A due date DETERMINISZTIKUS és helyi dátum

Ugyanaz a történet ugyanazt az esedékességet adja; a dátum helyi naptári nap
(ADR 0258 §4), nem UTC-pillanat.

### 5.4 Az intervallum-politika EGYSZERŰ és MAGYARÁZHATÓ

Kevés, kimondott lépcső — nem hangolt, átláthatatlan képlet. A felhasználónak
megmondható, mikor és miért jön vissza egy elem (ADR 0255).

### 5.5 A törölt tartalom HELYETTESÍTÉST igényel

Ha a hivatkozott tartalom eltűnt a katalógusból, a review-elem nem tűnik el
csendben és nem is dob hibát: **helyettesítést kér**, jelzéssel.

### 5.6 Az azonos cél DEDUPLIKÁLT

Ugyanaz a review-cél egyszer szerepel a sorban, akkor is, ha több úton került
be.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A napi budget nem léphető túl | `review_queue_test.dart` |
| A2 | Bizonytalan kimenet NEM rövidíti az intervallumot | `spaced_repetition_policy_test.dart` |
| A3 | Sikeres → hosszabb, sikertelen → rövidebb intervallum | ugyanott |
| A4 | Részleges kimenet külön kezelt (nem sikeres, nem sikertelen) | ugyanott |
| A5 | A due date determinisztikus, helyi dátum | ugyanott |
| A6 | Törölt tartalom → helyettesítési kérés, nem csendes eltűnés | `review_queue_test.dart` |
| A7 | Azonos cél egyszer szerepel | ugyanott |
| A8 | Az időzóna-váltás nem tolja el az esedékességet | `spaced_repetition_policy_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| „Kivételesen több fér be" | **A1** |
| A bizonytalan sikertelenként kezelve | **A2** |
| A részleges sikeresként könyvelve | A4 |
| `DateTime` alapú due date | A5/A8 |
| A törölt tartalom csendben eltűnik | **A6** |
| A dedup hiánya | A7 |

**A review-kimenet három kötelező cellája** (a határ: a bizonytalanság):

| Cella | Bemenet | Elvárt |
|---|---|---|
| biztos siker | magas confidence, teljesítve | intervallum **nő** |
| a határon | **bizonytalan** mérés | intervallum **változatlan** — nem büntet |
| biztos kudarc | magas confidence, nem teljesítve | intervallum **csökken** |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** kezeld a bizonytalan
kimenetet sikertelenként → az **A2** cellának PIROSNAK kell lennie → állítsd
vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/review/review_queue_test.dart test/features/practice_generator/review/spaced_repetition_policy_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `review_item.dart` — életciklus, tartalom-hivatkozás.
2. `spaced_repetition_policy.dart` — kevés, kimondott lépcső.
3. `review_queue.dart` — budget, dedup, helyettesítés.
4. Tesztek a §6.1 három kimenet-cellájával.
5. A valódi-sértés próba, §10-be dokumentálva.
6. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A bizonytalan mint kudarc.** „Biztos, ami biztos" — és a tanulót
  fölöslegesen visszaforgatja már tudott anyagra (A2).
- **A budget felpuhulása.** Egy „kivételes" nap után a fenntartás kiszorítja a
  fejlődést (A1).
- **A bonyolult képlet.** Jobb számokat ad papíron, és megmagyarázhatatlan
  lesz a felhasználónak (§5.4).

## 10. Implementation handoff — az implementer tölti ki

### 10.1 Módosított / új fájlok

- `lib/features/practice_generator/domain/model/review_item.dart` (NEW)
  - `ReviewTargetKind` (chordTransition, strummingPattern, lesson, songSection)
  - `ReviewTarget` (kind + targetId, `dedupKey = kind|targetId`)
  - `ReviewOutcome` (success, partial, failure, unknown)
  - `ReviewItem` (target, currentInterval, dueDate, replacementRequired)
  - `SelectableReviewItem` (item + estimatedMinutes)
- `lib/features/practice_generator/domain/policy/spaced_repetition_policy.dart` (NEW)
  - `ReviewIntervalLadder` (minimum/partial/unchanged/maximum anchored days)
  - `ReviewIntervalReason` (success, partial, failure, unknown)
  - `ReviewIntervalDecision` (previous/new interval + dueDate + reason)
  - `SpacedRepetitionPolicy.evaluate()` (pure, no clock, no Random, no DateTime)
- `lib/features/practice_generator/domain/service/review_queue.dart` (NEW)
  - `ReviewQueue(totalDailyMinutes, reviewBudgetMinutes)` — enforces the
    `0 <= reviewBudgetMinutes < totalDailyMinutes` strict bound
  - `ReviewQueueDecision.select()` — emits `selected`, `deferred`, and
    `replacementRequired` disjoint buckets
  - dedup-keyed on `(kind, targetId)`, sorted by `(dueDate, dedupKey)`
- `lib/features/practice_generator/public.dart` — barrel updated with the
  three new exports.
- `test/features/practice_generator/review/review_queue_test.dart` (NEW)
  - A1: budget cap (selected ≤ reviewBudgetMinutes), A1/contract
    (negative/equal/over rejected), A1/zero (zero budget defers all)
  - A6a/A6b/A6c: replacementRequired propagation without consumption
  - A7: dedup on `(kind, targetId)`, identity test (different kinds with
    same id do NOT merge), deterministic order test
  - Validation: negative minutes rejected
- `test/features/practice_generator/review/spaced_repetition_policy_test.dart` (NEW)
  - A2: unknown keeps previous interval & due date
  - A3a: success lengthens; A3b: failure shortens to minimum
  - A4: partial is a distinct band (failure < partial < success)
  - A5: deterministic (same inputs → same decision)
  - A8: timezone-neutral due date; H8 carryover: unknown on late `today`
    still keeps the original due date
  - Contract: zero-interval rejected; max-interval clamped
  - **Mutation proof (KÖTELEZŐ):** the `A2 mutation` test re-runs the
    policy with `ReviewOutcome.failure` standing in for `unknown` and
    asserts the broken variant shrinks the interval — green confirms A2
    is non-vacuous.

### 10.2 Parancsok és eredmények

- `tools/round-gate.sh test/features/practice_generator/review/review_queue_test.dart test/features/practice_generator/review/spaced_repetition_policy_test.dart`
  - `[1] format` → zöld
  - `[2] analyze` → zöld (No issues found!)
  - `[3] test review_queue_test.dart` → zöld (10/10 All tests passed!)
  - `[4] test spaced_repetition_policy_test.dart` → zöld (10/10 All tests passed!)
  - `[5] architecture` → zöld
  - `[6] secrets` → zöld
  - `[7] l10n` → zöld
- `flutter test` futtatva a `gate` belsejében, **külön** processzként, NEM
  `analyze && test` láncban (L05 OOM-védelem).

### 10.3 A2 valódi-sértés próba — bizonylat

A `A2 mutation` csoport egyetlen tesztet tartalmaz, és a kötelező
„uncertain-as-failure" próbát implementálja: a `review_queue_test.dart`
és a `spaced_repetition_policy_test.dart` is ugyanazt a `evaluate(...)`
hívást futtatja — egyszer `ReviewOutcome.unknown` (helyes), egyszer
`ReviewOutcome.failure` (a törött variáns) — és a teszt pirosra váltana,
ha a `failure` ág ugyanazt az intervallumot adná, mint a `unknown`. A
gate zöldje bizonyítja, hogy a kettő különböző döntést produkál (unknown
→ 7 nap, failure → 1 nap), tehát A2 terhelhető.

### 10.4 Scope-validáció

A `git status` az alábbi útvonalakon kívül SEMMIT nem módosított:
- `lib/features/practice_generator/domain/model/review_item.dart`
- `lib/features/practice_generator/domain/policy/spaced_repetition_policy.dart`
- `lib/features/practice_generator/domain/service/review_queue.dart`
- `lib/features/practice_generator/public.dart`
- `test/features/practice_generator/review/review_queue_test.dart`
- `test/features/practice_generator/review/spaced_repetition_policy_test.dart`
- `test/fixtures/practice_generator/review/review_fixtures.dart`
- `docs/rounds/e07-r17-spaced-repetition.md`
- `docs/adr/0303-spaced-repetition-review-queue-contract.md`

A 0303-as ADR NEM módosult (a brief által kijelölt pre-flight szöveg
változatlan).

## 11. Review — a Claude tölti ki
