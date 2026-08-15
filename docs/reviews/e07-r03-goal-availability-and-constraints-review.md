# E07-R03 — Review

Brief: docs/rounds/e07-r03-goal-availability-and-constraints.md
Diff: `git diff ba834de8...21cbfc9d` (branch `terra/e07-r03-goal-availability-and-constraints`)
Reviewer: Claude (Sonnet 5) · Dátum: 2026-08-15
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 1 · NOTE: 2

Implementer: `terra` (Codex CLI, `gpt-5.6-terra`), egy fordulóban lezárva
(`continuations=0`). A tíz engedélyezett fájl mindegyike a listán belül
maradt (`scope_audit=ok`), a helyi gate független újrafuttatása is 9/9 zöld,
és egy saját, eldobható próbateszttel a review három, a kör saját
tesztjeiben nem lefedett `RequestValidator`-ágat is ellenőrzött — mindhárom
helyesen viselkedett.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Hard korlát megsértése a validátorban HIBA, nem költség | ✅ | `request_validator_test.dart:21` „a hard constraint violation is an error, never a cost (A1)"; a brief §10-ben dokumentált valódi-sértés próba (hard-ág ideiglenesen warning+cost-ra állítva → A1 PIROS lett, `Expected: true, Actual: <false>`, majd visszaállítva) |
| A2 | Ugyanaz a korlát soft-ként MEGSÉRTHETŐ, költséggel | ✅ | `request_validator_test.dart:43` „a soft constraint violation is accepted with a cost (A2)" |
| A3 | `comfort` megadható hard korlátként | ✅ | `learner_constraints_test.dart:6` „comfort can be an explicit hard constraint (A3)" — a `category`/`strength` a kódban is két független mező (`learner_constraints.dart:76-77`) |
| A4 | Napi hard időmaximum nem léphető túl (kerekítés befelé) | ✅ | `weekly_availability_test.dart:43-79` — a kötelező 19/20(határon, inkluzív)/21 perces hármas mind a három cellája lefedve |
| A5 | Helyi dátum alapú elérhetőség; DST nem tolja el | ✅ | `weekly_availability_test.dart:21-35` — 2026-03-29→30 (a valódi EU DST-váltás napja) `LocalDate`-tel, `DateTime` sehol a domainben (grep, lásd Architektúra) |
| A6 | Túl sok primary goal → WARNING, nem hiba | ✅ | `practice_goal_test.dart:65` — 2 primary a default max=1 ellen: `hasErrors=false`, `severity=warning` |
| A7 | Normalizálatlan custom goal nem végrehajtható | ✅ | `practice_goal_test.dart:50` (`isExecutable` szinten) **+** reviewer-próba (lásd lent) a validátor `customGoalNotExecutable` ágán |
| A8 | Goal lifecycle átmenetei kikényszerítettek | ✅ | `practice_goal_test.dart:25` — proposed→active→achieved érvényes, proposed→achieved és achieved→active dob; lásd MINOR-1 a lefedettség mélységéről |
| A9 | Nincs Flutter import, `DateTime.now()` vagy `Random` | ✅ | `grep -rn "package:flutter\|dart:ui\|DateTime\.now()\|Random(" lib/features/practice_generator/domain/{model,service}/*.dart` (a kör 4 érintett lib-fájlján) → 0 találat |

## Scope-audit

```
$ python3 tools/scope-audit.py --repo /tmp/review-e07-r03 --brief docs/rounds/e07-r03-goal-availability-and-constraints.md --base ba834de8
Legacy scope audit OK (ba834de8..21cbfc9d8186, 10 changed path(s), 0 generated/ignored)
```

10 megváltozott útvonal, mind a brief `allowed_paths`-án belül. Engedélyezett
fájlokon kívüli változás: **nincs**.

## Megállapítások

### MINOR-1 — Három `RequestValidator`-ág teszteletlen a kör saját suite-jában

- **Fájl:** `lib/features/practice_generator/domain/service/request_validator.dart:154` (`unavailableDayScheduled`), `:174-183` (`softMaximumExceeded` + a lineáris `excessMinutes * softExcessMinuteCost` költségszámítás), `:112` (`customGoalNotExecutable`, a validátoron KERESZTÜL — a `practice_goal_test.dart` csak a `PracticeGoal.isExecutable` gettert méri közvetlenül, a validátor saját ágát nem).
- **Probléma:** a négy célzott tesztfájl egyike sem hoz létre `ConstraintStrength.soft` napi maximumot, nem ütemez percet elérhetetlen/hiányzó napra, és nem ad át validátornak nem-végrehajtható custom goal-t — pedig az SDD Ch8 Kör 3 „Kötelező tesztek" listája külön nevesíti az „availability edge cases" és „constraint conflict" kategóriákat a DST-fixture-ön túl.
- **Hatás:** ma nulla — a `practice_generator` flagek OFF-on, nincs hívó. A kockázat egy KÉSŐBBI kör (Kör 4/11/12), amely ténylegesen hívni kezdi a validátort: egy itt megbúvó regresszió csak ott derülne ki, nehezebben diagnosztizálhatóan.
- **Mérve, nem csak olvasva:** a reviewer egy eldobható próbateszttel (négy eset: unavailable-day, hiányzó nap, soft-maximum lineáris költség, validátoron-át-menő customGoalNotExecutable) mind a négy állítást lefuttatta a friss `/tmp` klónban — **mind a négy zöld volt**, tehát a jelenlegi implementáció HELYES, csak a kör saját teszt-bizonyítéka hiányos rá. A próbateszt nem került a diffbe, törölve.
- **Kötelező javítás:** egy jövőbeli körben (vagy egy kis follow-up javító körben, ha a driver úgy dönt) pótolni ezt a három ágat a négy meglévő tesztfájl valamelyikében, ugyanazzal a mintával, mint a próbateszt.
- **Ellenőrzés:** az új tesztek lefussanak és a validátor kódját mutálva (pl. `softMaximumExceeded` ág törlése) PIROSRA váltsanak.
- **Státusz:** OPEN (nem blokkoló — a brief A1-A9 listája szó szerint nem követeli meg, és a viselkedés bizonyítottan helyes).

### NOTE-1 — `PracticeGoal` lifecycle-mátrix részleges

`practice_goal_test.dart:25` a hat státusz (`proposed/active/paused/achieved/
abandoned/superseded`) gráfjából csak 2 érvényes és 2 érvénytelen átmenetet
mér; a `canTransitionTo` (`practice_goal.dart:204-219`) teljes gráfját nem.
Az SDD §11.5 csak a hat státusznevet írja elő, konkrét gráfot nem — az
implementáció belsőleg konzisztens és ésszerű (lineáris előrehaladás
paus/resume-mal és három kilépő állapottal). A brief A8 sora sem ír elő
mátrixot (szemben A4-gyel, ahol igen). Jövőbeli hardening-lehetőség, nem
hiba.

### NOTE-2 — A `done` jelzés `dirty_files=1`-gyel érkezett, egy záró commit követte

A `.codex-round-status` a `done` jelzés pillanatában `dirty_files=1`-et
mutatott; egy további commit (`21cbfc9d`, „record e07-r03 handoff") a §10
kitöltését vitte fel UTÁNA. A végállapot tiszta (`git status --short` a
munkapéldányban üres) és a `scope_audit`/`gate_shape` mindkettő `ok` — nincs
elveszett munka —, de ez eltér az implementer-preambulum §3 kötött záró
sorrendjétől (gate → commit → jelzés, ebben a sorrendben, a jelzés az
UTOLSÓ lépés). Megfigyelés, nem blokkoló.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (implementer, §10) | Ellenőrizve (reviewer, saját `/tmp` klón) |
|---|---|---|
| format | 1508 fájl, 0 módosítás | ✅ azonos |
| analyze | No issues found | ✅ azonos |
| request_validator_test.dart | 2 passed | ✅ azonos |
| weekly_availability_test.dart | 4 passed | ✅ azonos |
| practice_goal_test.dart | 5 passed | ✅ azonos |
| learner_constraints_test.dart | 5 passed | ✅ azonos |
| architecture | OK (12 allowlisted deviation) | ✅ azonos |
| secrets | OK, 0 finding | ✅ azonos (2567 fájl — a saját klón mérete tér el a fájlszámban, a `0 finding` egyezik) |
| l10n | OK, en→hu, 1276 üzenet | ✅ azonos |
| CI — Router CI | — | ✅ [31899847845](https://github.com/wolfcasaba/strumsight/actions/runs/31899847845) success, headSha `21cbfc9d` |
| CI — Full Gate (no APK) | — | run [31899858594](https://github.com/wolfcasaba/strumsight/actions/runs/31899858594), headSha `21cbfc9d` — folyamatban a review lezárásakor, a merge előtt ellenőrizve |

Dedikált biztonsági review **nem kötelező** — `risk = "normal"` és a diff
egyik fájlja sem illeszkedik a `.ai/router.toml` `high_risk_path_fragments`
mintáira (`auth|authorization|credential|crypto|encryption|migration|
payment|secret`, mérve grep-pel a 10 megváltozott útvonalon).

## Merge-döntés

Az ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge.
A fenti tábla szerint ez teljesül (a Full Gate CI-futás lezárását a merge
előtt külön ellenőrizni kell). **APPROVED, mehet a merge** a CI zöld
lezárása után.
