# E08-R11 — Review

Brief: `docs/rounds/e08-r11-qualified-day-planned-rest-and-recovery.md`
Diff: `cca0c4d3..0df3c6f8`
Reviewer: Codex Sol (`gpt-5.6-sol`) · Dátum: 2026-08-20
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 nyitott (1 lezárt) · MINOR: 0 · NOTE: 0

Az implementer scope-ja tiszta. Az első review időzónafüggő planned-rest hibát
talált, amelyet a Terra javított; a friss re-review klónban a Budapest-próba
12/12, a pontos kör-gate 6/6 zöld, a threshold-mutáció piros, visszaállítás
után pedig a célteszt ismét 12/12 zöld.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | `119/120/121s` inkluzív küszöb | ✅ | célzott teszt, 3 cella |
| A2 | planned rest nem tör és nem költ freeze-t | ✅ | F1 fix + Budapest-időzónás állandó cella |
| A3 | azonos napi idempotencia | ✅ | öt külön event ugyanarra a napra |
| A4 | clock rollback identity no-op | ✅ | célzott teszt + typed reason |
| A5 | weekly consistency külön projekció | ✅ | duplikátumos, broken daily-state-től független fixture |
| A6 | typed reason matrix | ✅ | qualified/recovery/rest/grace/freeze/broken/already/anomaly/insufficient |
| A7 | nincs negatív XP / ledger dependency | ✅ | source-audit + tiszta, IO-mentes service |
| A8 | egyetlen konfiguráció | ✅ | módosított `2s/1s` config-cella |
| A9 | explicit recovery `59/60/61s` | ✅ | négy határcella |
| A10 | publikus Practice Generator contract | ✅ | `WeeklyScheduleDecision` fixture és import-audit |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e08-r11-fix1-SWZ61d --brief
docs/rounds/e08-r11-qualified-day-planned-rest-and-recovery.md --base
cca0c4d3...` → **OK**, 7 módosított útvonal, 2 generated/ignored (a két
kötelező review-jelentés).

Az implementer jelzésében szereplő `dirty_files=1` után a tényleges tracked
munkafa tiszta volt. A `gate_shape=VIOLATION` valós: az implementer a formázást
és a gate-et `&&`-del egy shellhívásba tette, ezért ezt a gate-bizonyítékot a
review nem fogadta el. A reviewer a pontos artefaktumot önálló parancsként
újrafuttatta.

## Megállapítások

### F1 — MAJOR — A planned-rest epoch-nap UTC-ben készült, a shipping streak helyi éjfélben

- **Fájl:** `lib/features/gamification/infrastructure/default_streak_policy.dart:76`
- **Probléma:** `_epochDayFor` `DateTime.utc(...)`-t használ. A shipping
  `StreakLogic.epochDayOf` (`lib/features/streak/streak_logic.dart:18`) ezzel
  szemben `DateTime(year, month, day)` helyi éjfélből számol. Pozitív
  UTC-offseten ugyanaz a naptári dátum ezért eltérő egész epoch-napot ad.
- **Mért reprodukció:** eldobható
  `streak_service_timezone_probe_test.dart`, futtatva:
  `TZ=Europe/Budapest flutter test
  test/features/gamification/application/streak_service_timezone_probe_test.dart`.
  Várt: `plannedRest`; mért: `grace` (exit 1). A fixture pontosan a shipping
  helyi-éjféli képletével képezte a request `epochDay` értékét.
- **Hatás:** Budapesthez hasonló pozitív offsetes készüléken a terv szerinti
  pihenőnap nem kap védett reason code-ot; a következő qualified nap gapje
  freeze-t költhet vagy broken ágra kerülhet.
- **Javítás:** `0df3c6f8` a konverziót a shipping
  `DateTime(year, month, day)` helyi-éjféli képletre állította, és állandó
  regressziós cellát adott hozzá; domain/legacy fájl nem változott.
- **Ellenőrzés:** friss `/tmp/review-e08-r11-fix1-SWZ61d` klónban
  `TZ=Europe/Budapest flutter test .../streak_service_test.dart` → 12/12;
  exact kör-gate → 6/6 zöld.
- **Státusz:** FIXED (`0df3c6f8`)

## Valódi-sértés próbák

- **Időzóna:** a fenti eldobható Budapest-cella a shipping/local kontra UTC
  eltérést pirosra vitte.
- **Qualified threshold:** a re-review-ban `return activity.duration >=
  minimum` → `return true` mutáció az A1 `119s`, a config és az A9 `59s`
  cellát is pirosra vitte. Visszaállítás után 12/12 zöld, a reviewer-klón
  tiszta.

## Gate-bizonyíték ellenőrzése

| Gate | Eredmény | Ellenőrizve |
|---|---|---|
| format | 1723 fájl, 0 változás | ✅ |
| analyze | no issues | ✅ |
| célzott teszt | 12/12 pass UTC és Europe/Budapest | ✅ |
| architecture | OK, 12 allowlisted deviation | ✅ |
| secrets | 3062 fájl, 0 finding | ✅ |
| l10n | 1405 üzenet parity | ✅ |
| teljes CI + property | még nincs dispatch | ⏳ |

## Merge-döntés

Nincs nyitott BLOCKER/MAJOR. A correctness és security review APPROVED; merge
csak az exact-SHA teljes CI + property kapu és freshness-ellenőrzés után.
