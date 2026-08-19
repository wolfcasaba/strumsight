# E07-R26 — Review

Brief: docs/rounds/e07-r26-outcome-ingestion-and-revision.md
Diff: `git diff 26cdad92..d3c337e5` (pre-flight commit → implementer commit)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-19
Verdikt: CHANGES REQUIRED

## Összegzés

BLOCKER: 0 · MAJOR: 1 · MINOR: 1 · NOTE: 1

Independens gate-újrafuttatás izolált `/tmp/review-e07-r26` klónban: **MINDEN
GATE ZÖLD** (format, analyze, mindkét célzott teszt 9/9, architecture,
secrets, l10n). `tools/scope-audit.py` (a hiteles eszköz, nem kézi
`git diff --stat`): `OK (26cdad92..d3c337e5b47c, 10 changed path(s), 0
generated/ignored)` — scope-sértés nincs. A zöld gate azonban nem bizonyíték
(`sdd-round-review` skill alapelve) — az alábbi F1 két eldobható próbateszttel
mért, nem a kód olvasásából következtetett lelet.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | A lezárt múlt változatlan marad | ✅ | `revise_practice_plan_test.dart::A1/A2`; `_validateImmutablePast` érték-egyenlőséggel hasonlít (`PracticeDay`/`PracticeBlock` mindkettő felülírja `operator ==`/`hashCode`, ld. `practice_day.dart:151-163`, `practice_block.dart:184-197` — ellenőrizve, NEM referencia-egyenlőség) |
| A2 | A change set csak jövőbeli blokkot érint | ✅ | ugyanott + `_validateFutureTarget` (`revise_practice_plan.dart:153-168`), a `plan_repairer.dart:167,176-184` meglévő `status == completed` mintáját követi |
| A3 | Duplikált eredmény egyszer dolgozódik fel | ✅ | `outcome_ingestion_service_test.dart::A3` — a replay `duplicate` státuszt ad, a review-item VÁLTOZATLAN marad (nem csak egy flag-ellenőrzés: az első hívás ténylegesen 7→14 napra módosítja az intervallumot, a replay nem) |
| A4 | Kis változás automatikus, nagy megerősítést kér | ⚠️ RÉSZBEN | count-alapú ág (1/2/3 változás) tesztelve és zöld; a STRUKTURÁLIS ág (`_isStructuralChange`, brief §5.2 "fókusz váltása") a kódban helyesen működik (saját próbateszttel igazolva), de a kör SAJÁT teszt-suite-jában NULLA lefedettséggel — ld. **F1** |
| A5 | Az elutasított change set auditálható, de nem aktív | ✅ | `revise_practice_plan_test.dart::A5` — `changeSet.changes` hossza megmarad, `isActive=false` |
| A6 | Nem aktuális revízióra hivatkozó eredmény kontrolláltan kezelt | ✅ | `outcome_ingestion_service_test.dart::A6` — `staleRevision` státusz, review-item változatlan |
| A7 | A technikai hiba nem indít adaptációt (ADR 0268) | ✅ | `outcome_ingestion_service_test.dart::A7` + `record_practice_outcome.dart:71` (`canAdapt && adaptationRequest != null` kapu) — a technikai hiba `canAdapt=false`-t ad, az `AdaptationDecider` sosem hívódik |
| A8 | A revízió-szám monoton nő (ADR 0256) | ✅ | `revise_practice_plan_test.dart::A8` — a meglévő `PlanRevision(previous:)` guardot használja, nem saját számlálót |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs.** `tools/scope-audit.py`
eredménye: `OK (26cdad92..d3c337e5b47c, 10 changed path(s), 0
generated/ignored)`. A 10 fájl pontosan a brief `allowed_paths`-ának egy
részhalmaza (nincs `test/fixtures/practice_generator/outcome/` — nem volt rá
szükség).

## Megállapítások

### F1 — MAJOR — Brief §5.2 "fókusz váltása" (structural-change) ág NULLA teszt-lefedettséggel

- **Fájl:** `test/features/practice_generator/outcome/revise_practice_plan_test.dart`
  (hiányzó teszt); az érintett implementáció:
  `lib/features/practice_generator/application/usecase/revise_practice_plan.dart:187-194`
  (`_isStructuralChange`)
- **Probléma:** a brief §5.2 explicit követelménye: "nagy változás (a hét
  szerkezete, **a fókusz váltása**) csak a tanuló jóváhagyásával" — a §6.1
  mérce-mátrix "a küszöb fölött" cellája is ezt a MINŐSÉGI (nem csak
  darabszám-) esetet írja elő. Az implementáció ezt egy külön,
  `_isStructuralChange` ág formájában helyesen megvalósította (`type ==
  added/removed/moved`, vagy `before`/`after` tartalmazza
  `primaryFocusSkillIds`/`timeBudgetMicros` kulcsot). **DE** a kör saját
  három "változás-nagyság" tesztje (`A4 below/at/above threshold`)
  KIZÁRÓLAG a darabszám-ágat (`changes.length >= 2`) gyakorolja — mindhárom
  teszt ugyanazt a `durationChange()` fixture-t ismétli 1/2/3-szor. A
  `_isStructuralChange` ág emiatt a kör commitolt suite-jában **0%**
  lefedettségű: egy jövőbeli refaktor (pl. a kulcsnév elgépelése, egy
  `type`-ág elhagyása) semmilyen tesztet nem buktatna pirosra.
- **Mérve, eldobható próbateszttel** (`/tmp/review-e07-r26`, NEM commitolva,
  törölve a review után): egyetlen, `primaryFocusSkillIds`-t érintő,
  NEM-strukturális darabszámú (1 elemű) change-lista átadva a
  `RevisePracticePlan.call()`-nak → **ma helyesen** `requiresUserConfirmation
  == true`, `isActive == false` (a `python3 -c`-szerű reprodukció: a
  fixture-lista hossza 1, tehát a count-ág `1 >= 2` hamis — a `true`
  KIZÁRÓLAG a strukturális ágból jöhetett). A viselkedés tehát MA helyes — a
  hiba nem funkcionális bug, hanem a `AGENTS.md`/`09-review-report.md`
  súlyossági táblájának saját MAJOR-definíciója szerinti **"hiányzó teszt a
  viselkedésváltozásra"**.
- **Hatás:** a brief egyik legkonkrétabb, névvel nevezett acceptance-elve
  ("fókusz váltása mindig megerősítést kér") gépi őr nélkül marad — egy
  jövőbeli, akár ugyanebben az epicben történő refaktor észrevétlenül
  eltörhetné, és csak éles használatban (a tanuló csendben elveszíti a
  megerősítési lehetőséget egy fókuszváltásnál) derülne ki.
- **Kötelező javítás:** egyetlen új teszt
  `revise_practice_plan_test.dart`-ban: egyetlen, `primaryFocusSkillIds`
  (vagy `timeBudgetMicros`) kulcsot érintő `PlanChange` — KÜLÖN a meglévő
  `durationChange()`-től, hossz=1 listában —, és `expect(result.
  requiresUserConfirmation, isTrue)` + `expect(result.isActive, isFalse)`.
  Legalább egy `PlanChangeType.added`/`removed`/`moved` cella is javasolt,
  de a kulcs-alapú ág a minimális kötelező.
- **Ellenőrzés:** az új teszt PIROS legyen, ha valaki ideiglenesen kiveszi a
  `primaryFocusSkillIds`/`timeBudgetMicros` ágat a `_isStructuralChange`-ből
  (valódi-sértés próba, a §10 handoffban dokumentálva) — utána visszaállítva
  ZÖLD.
- **Státusz:** OPEN

### F2 — MINOR — `PlanChange.target` új szűk formátuma nem fedi a MEGLÉVŐ termelői konvenciókat

- **Fájl:** `lib/features/practice_generator/application/usecase/revise_practice_plan.dart:197-214`
  (`_PlanChangeTarget.parse`)
- **Probléma:** a `revise_practice_plan.dart` a `PlanChange.target`-et
  szigorúan `day:<dayId>` vagy `day:<dayId>:block:<blockId>` alakban várja.
  A `PlanChange` viszont MEGLÉVŐ, közös domain-típus, amit MÁS termelők MÁR
  MA is MÁS alakban töltenek ki: `plan_repairer.dart:203`
  (`'block:${id}'`), `active_plan_controller.dart:79,120` (`'block:${id}'`),
  `active_plan_controller.dart:94` (`'plan:${id}'`),
  `time_budget_allocator.dart:465` (`'timeBudget'`, prefix nélkül).
- **Mérve, eldobható próbateszttel:** egy `plan_repairer.dart`-stílusú
  (`target: 'block:block.1'`) `PlanChange`-t adva a `RevisePracticePlan.
  call()`-nak → **nem kontrollált elutasítás, hanem elkapatlan
  `ArgumentError`**: `ArgumentError: Invalid argument (target): must be
  day:<dayId> or day:<dayId>:block:<blockId>: "block:block.1"`
  (`_PlanChangeTarget.parse`, `revise_practice_plan.dart:206-210`).
- **Hatás:** MA nincs élő hívó (a brief §0.0/2. pontja szerint egyik új fájl
  sem kap valódi bekötést), tehát ez a kör egyetlen acceptance-pontját sem
  sérti. Egy JÖVŐBELI wiring-kör viszont könnyen belefuthat: ha egy
  `time_budget_allocator`/`plan_repairer`-stílusú `PlanChange`-t közvetlenül
  a `revise_practice_plan.dart`-nak adna, elkapatlan kivétellel állna le,
  nem egy kontrollált `stopped`/rejected eredménnyel.
- **Kötelező javítás:** NEM ebben a körben — a brief `allowed_paths`-a nem
  ad hozzáférést a termelő fájlokhoz (`plan_repairer.dart`,
  `active_plan_controller.dart`, `time_budget_allocator.dart` egyike sincs a
  listán), és egy VALÓDI unifikáció (pl. `block:<id>` felbontása a napok
  közti kereséssel) új tervezői döntés, nem "körön belüli" javítás. Javasolt
  irány a következő wiring-körnek: VAGY a `_PlanChangeTarget`
  doc-commentjében explicit rögzíteni, hogy ez a `revise_practice_plan.dart`
  SAJÁT, szűk cél-formátuma (a hívó felelőssége a fordítás), VAGY a parsert
  bővíteni a három meglévő alakra.
- **Ellenőrzés:** follow-up brief §0.0-jában mérje ki és hivatkozza ezt a
  leletet (F2), hogy ne vesszen el.
- **Státusz:** OPEN (follow-up, nem blokkolja EZT a merge-et — nincs élő
  hívó, ld. fent)

### F3 — NOTE — `plan_change_review_screen.dart` nyers belső értékeket jelenít meg a tanulónak

- **Fájl:** `lib/features/practice_generator/presentation/screens/plan_change_review_screen.dart:90,93,96,98`
- **Probléma:** a `change.target` (pl. `day:day.1:block:block.1`), a
  before/after `Map` nyers kulcs-érték párjai (pl.
  `estimatedElapsedMicros: 420000000`, mikroszekundumban, nem percben) és a
  `PlanChangeReason.code` (pl. `systemAdaptation`) közvetlenül, lokalizálás
  és humanizálás nélkül jelenik meg.
- **Hatás:** a screennek jelenleg nulla production hívója van (nincs
  bekötve), tehát ez ma nem éri el a felhasználót. UX-kockázat egy jövőbeli
  aktiválás előtt.
- **Kötelező javítás:** nincs, ez a kör scope-ján kívül esik (a brief nem ír
  elő humanizált diff-nézetet). Javasolt egy jövőbeli design/wiring körnek.
- **Státusz:** OPEN (nem blokkoló)

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (implementer) | Ellenőrizve (reviewer, izolált klón) |
|---|---|---|
| format | zöld | ✅ zöld |
| analyze | `No issues found!` | ✅ `No issues found! (ran in 5.0s)` |
| `outcome_ingestion_service_test.dart` | zöld | ✅ 3/3 (`A3`, `A6`, `A7`) |
| `revise_practice_plan_test.dart` | zöld | ✅ 6/6 (`A1/A2`, `A4×3`, `A5`, `A8`) |
| architecture | zöld | ✅ `12 allowlisted deviation(s)` — előzetes, e kör NEM módosította |
| secrets | (nem jelentve külön) | ✅ `0 finding(s)` |
| l10n | (nem jelentve külön) | ✅ `en → hu, 1366 message(s)` parity |
| scope-audit | (implementer: `scope_audit=ok`, 10 fájl) | ✅ `tools/scope-audit.py`: `OK`, 10 changed path(s) |
| CI (teljes suite + property + APK) | — | még nem dispatch-elve (a review után) |

## Merge-döntés

**Merge TILOS, amíg F1 nyitva van** (MAJOR). F2/F3 nem blokkol. Javító kör
indul ugyanazon a motoron (`codex`), az F1 leletlistával; a javítás után a
gate-eket ismételten, izolált klónban futtatom, és ezt a jelentést frissítem.
