# E07-R15 — Review

Brief: `docs/rounds/e07-r15-weekly-scheduler.md`
Diff: `2ccfeba6..2177a1cd`
Reviewer: Codex / gpt-5.6-terra · Dátum: 2026-08-16
Verdikt: CHANGES REQUIRED

## Összegzés

BLOCKER: 0 · MAJOR: 3 · MINOR: 0 · NOTE: 0

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Nulla elérhetőségű napra nincs kötelező blokk | ✅ | `weekly_scheduler_test.dart` A1 cellák |
| A2 | High-load limit | ✅ | `weekly_scheduler_test.dart` 1/2/3 cellák |
| A3 | Pihenőnap üres | ✅ | `weekly_scheduler_test.dart` A3 cellák |
| A4 | Review-arány korlátos | ✅ | `scheduling_policy_test.dart` A4 cellák |
| A5 | Céldátum előtti light review | ❌ | F1 és F2 |
| A6 | Determinisztikus beosztás | ❌ | F3 |
| A7 | Napi fókusz-limit | ✅ | `weekly_scheduler_test.dart` A7 cellák |
| A8 | Helyi dátumhatárok | ❌ | F2 és F3 |

## Scope-audit

`python3 tools/scope-audit.py --repo /home/ubuntu/ss-minimax-e07-r15 --brief docs/rounds/e07-r15-weekly-scheduler.md --base 2ccfeba6a7ececfc197a77000a362dcac485b0de` → OK; 9 changed path, 0 generated/ignored.

## Megállapítások

### F1 — MAJOR — A song céldátum-távolság előjele fordított

- **Fájl:** `lib/features/practice_generator/domain/service/weekly_scheduler.dart:85-95`
- **Probléma:** Az M3 javítás ugyan már a tényleges céldátumot használja, de `dayDistanceFromTarget()` `date - target` előjelt ad, miközben `SchedulingPolicy.phaseForDayDistance()` dokumentált szerződése `target - day`. Egy jövőbeli cél előtti nap ezért negatív és tévesen `performance` fázisú.
- **Hatás:** A5 sérül: a scheduler a távoli, jövőbeli cél előtt is blokkolhat új anyagot, a taper pedig megfordul.
- **Kötelező javítás:** A scheduler a policynek `songTargetDate - scheduledDate` valódi naptári napkülönbséget adjon. A tesztben a jövőbeli cél előtti, review-windowon kívüli nap legyen `none`/`preparation`, a 1–3 nappal előtti nap `lightReview`, a cél napja pedig `performance`.
- **Státusz:** OPEN

### F2 — MAJOR — A LocalDate-távolság hónap- és évhatáron hibás

- **Fájl:** `lib/features/practice_generator/domain/model/schedule_decision.dart:182-193`
- **Probléma:** A `year * 10000 + month * 100 + day` nem naptári sorszám. Például 2026-01-31 → 2026-02-01 távolsága 70, 2026-12-31 → 2027-01-01 távolsága 8870, nem 1.
- **Hatás:** A5/A8 periodizáció és dátumhatár-szerződés hibás, a 3 vagy 7 napos policy-ablak hónapváltáskor működésképtelen.
- **Kötelező javítás:** Központi, dependency-free, valódi naptári napkülönbség (szökőévvel) szükséges. Adj Jan→Feb és Dec→Jan tesztcellát, amelyek mindkét irányban pontos `±1` eredményt mérnek.
- **Státusz:** FIXED (`afc61a8d`, re-review forrás- és teszt-ellenőrzés)

### F3 — MAJOR — A scheduler nem kronológiai sorrendben járja be a napokat

- **Fájl:** `lib/features/practice_generator/domain/model/schedule_decision.dart:118-126,170-176`; `lib/features/practice_generator/domain/service/weekly_scheduler.dart:87,118`
- **Probléma:** A `WeeklyAvailability.days` bemeneti sorrendét változatlanul átveszi `_weekDates`; a végső output rendezett, de a placement és high-load-run az eredeti sorrendben történik.
- **Hatás:** Ugyanaz a dátumhalmaz más bemeneti sorrendben eltérő napi allokációt és terhelésrotációt adhat, ellentétben A6/A8-cal és a brief rögzített, kronológiai bejárásával.
- **Kötelező javítás:** A request konstruktorban kanonikusan `LocalDate.compareTo` szerint rendezd a hét napjait, majd bizonyítsd nem-rendezett availability bemenettel, hogy a döntés és a high-load-run azonos a rendezett esettel.
- **Státusz:** FIXED (`afc61a8d`, re-review forrás- és teszt-ellenőrzés)

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| scope audit | zöld | ✅ |
| format/analyze/célzott tesztek/architecture | implementer: zöld | ⏳ a review-klón gate futása nem adott terminális összegzést a review megkezdésekor |
| CI (teljes suite + property + APK) | nincs | ❌ még nincs dispatch |

## Merge-döntés

Az első MiniMax-javítás után F1 MAJOR nyitva maradt; az ADR 0087 szerinti következő javítást Codex viszi külön munkapéldányban. Merge továbbra is tilos.
