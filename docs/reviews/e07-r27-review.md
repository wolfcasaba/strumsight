# E07-R27 — Review

Brief: `docs/rounds/e07-r27-missed-day-and-pause.md`
Diff: `6dff23ee..d55b6639`
Reviewer: Codex / gpt-5.6-terra · Dátum: 2026-08-19
Verdikt: APPROVED (javítás utáni független re-review, `1c5d4562`)

## Összegzés

BLOCKER: 0 · MAJOR: 0 nyitott (2 javítva) · MINOR: 0 · NOTE: 0

Az izolált, commit-pontos `/tmp/review-e07-r27-d55b` klón scope-auditja OK
(`11 changed path(s), 0 generated/ignored`), és a reviewer saját
`tools/round-gate.sh test/features/practice_generator/continuity/missed_day_policy_test.dart test/features/practice_generator/continuity/pause_resume_test.dart`
futtatása zöld volt. Ez nem zárja le az alábbi viselkedési réseket.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Kihagyás nem növeli a következő napi keretet | ❌ | F2: nincs budget bemenet/kimenet vagy állítás |
| A2 | Pihenőnap nem mulasztás | ✅ | policy teszt + `restDay` reason-code kezelés |
| A3 | Szünet alatt nincs lemaradás | ❌ | F1 completed múltat átírja |
| A4 | Folytatás új revízió és korrigált dátumok | ❌ | F1 sérti immutable past szerződést |
| A5 | Hosszú szünet readiness javaslat | ✅ | 21/22 napos tesztek és `pickedMode` |
| A6 | Csak primary mozog | ✅ | secondary-only cella |
| A7 | Időzóna-váltás nem hamis mulasztás | ✅ | `LocalDate`-alapú cella |
| A8 | Nem szégyenítő ARB-copy | ✅ | en/hu ARB assert |

## Scope-audit

Engedélyezett fájlokon kívüli implementációs változás: nincs. A jelen
review-jelentés a scope-audit beépített review-artefaktum mentessége alá esik.

## Megállapítások

### F1 — MAJOR — Resume átírja a completed nap történeti dátumát

- **Fájl:** `lib/features/practice_generator/application/usecase/resume_practice_plan.dart:117–141`
- **Probléma:** a kód minden napra azonos `shift`-et alkalmaz és új
  `PracticeDay`-t épít. Nem különíti el a `PracticeItemStatus.completed`
  múltat, ezért a completed nap local date-je is megváltozik egy új
  revisionben.
- **Hatás:** sérül az ADR 0256 immutable-past szerződése; az auditálható,
  befejezett gyakorlás naptári időpontja utólag átíródik.
- **Mért bizonyíték:** reviewer-oldali eldobható próba egy 2026-08-01-i
  completed nappal, pause=2026-08-03 és resume=2026-08-10 esetén PIROS:
  `Expected LocalDate:<2026-08-01>; Actual LocalDate:<2026-08-10>`.
- **Kötelező javítás:** a completed napokat és blokkokat a korábbi snapshot
  értékével őrizd meg; kizárólag a valóban jövőbeli, nem completed tervrészt
  re-anchoröld. Adj checked-in regressziós tesztet erre a pontos esetre.
- **Ellenőrzés:** a fenti próba a javított kör-tesztben legyen zöld, a
  célzott gate újrafuttatásával.
- **Státusz:** FIXED (`150fc118`), reviewer-próba és checked-in F1 teszt zöld

### F2 — MAJOR — A1 napi-keret invariant nincs modellezve, a teszt csak módot ellenőriz

- **Fájl:** `lib/features/practice_generator/domain/policy/missed_day_policy.dart:104–160, 190–214`; `test/features/practice_generator/continuity/missed_day_policy_test.dart:22–41`
- **Probléma:** `MissedDayInput` kizárólag `today` és `observations` mezőt,
  `MissedDayDecision` kizárólag klasszifikációt/számot/módot tartalmaz. Sem a
  következő napi `Duration`/hard budget, sem bármely változtatási javaslat
  nincs benne. Az A1 teszt ezért csak a `simpleReschedule` enumot vizsgálja;
  egy későbbi, keretet duplázó fogyasztót nem tudna pirosra állítani.
- **Hatás:** a brief elsődleges, „nem backlog” hard invariantja nem
  bizonyított contract, csak leíró komment. A §10-ben állított
  „real violation probe” sem növelt budgetet mér, csupán másik küszöb módot.
- **Kötelező javítás:** a meglévő új policy contractban szerepeljen a
  hívó által átadott következő napi hard keret és a decisionben annak
  explicit, változatlan értéke (vagy vele egyenértékű, típusos
  no-growth contract). A checked-in A1 tesztben a kihagyott idő és a
  következő napi keret különböző érték legyen, majd a kimenet pontosan az
  eredeti hard keretet állítsa; a valódi-sértés próba a kerethez adott
  kihagyott idővel legyen piros.
- **Ellenőrzés:** célzott tesztben a hibás `budget + missedDuration` mutáció
  PIROS, visszaállítva ZÖLD.
- **Státusz:** FIXED (`1f44fe43`), typed-budget és mutációs próba zöld

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ izolált klón |
| analyze | zöld | ✅ izolált klón |
| célzott tesztek | zöld | ✅ izolált klón (13 + 12) |
| architecture / secrets / l10n | zöld | ✅ izolált klón |
| CI (teljes suite + property) | korábbi dispatch elavult | ⏳ végső HEAD-re újradispatch szükséges |
| Router CI | branch-push trigger | ⏳ végső HEAD-re ellenőrizendő |

## Merge-döntés

F1 és F2 lezárva; az ADR 0052 szerinti merge-hez még a végső HEAD exact-SHA
Full Gate és Router CI zöld eredménye kell.
