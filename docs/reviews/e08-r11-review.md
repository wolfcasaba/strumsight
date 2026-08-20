# E08-R11 — Review

Brief: `docs/rounds/e08-r11-qualified-day-planned-rest-and-recovery.md`  
Diff: `cca0c4d3..84b149c6`  
Reviewer: Codex Sol (`gpt-5.6-sol`) · Dátum: 2026-08-20  
Verdikt: **CHANGES REQUIRED**

## Összegzés

BLOCKER: 0 · MAJOR: 1 · MINOR: 0 · NOTE: 0

Az implementer scope-ja tiszta, a friss izolált reviewer-klónban futó pontos
kör-gate 6/6 zöld. A zöld UTC-központú tesztmátrix mögött azonban egy
időzónafüggő planned-rest hiba maradt: a Practice Generator `LocalDate`
értékéből UTC epoch-nap készül, miközben a shipping streak helyi éjfél-alapú
epoch-napot használ.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | `119/120/121s` inkluzív küszöb | ✅ | célzott teszt, 3 cella |
| A2 | planned rest nem tör és nem költ freeze-t | ❌ | F1: pozitív UTC-offseten a nap nem ismerhető fel |
| A3 | azonos napi idempotencia | ✅ | öt külön event ugyanarra a napra |
| A4 | clock rollback identity no-op | ✅ | célzott teszt + typed reason |
| A5 | weekly consistency külön projekció | ✅ | duplikátumos, broken daily-state-től független fixture |
| A6 | typed reason matrix | ✅ | qualified/recovery/rest/grace/freeze/broken/already/anomaly/insufficient |
| A7 | nincs negatív XP / ledger dependency | ✅ | source-audit + tiszta, IO-mentes service |
| A8 | egyetlen konfiguráció | ✅ | módosított `2s/1s` config-cella |
| A9 | explicit recovery `59/60/61s` | ✅ | négy határcella |
| A10 | publikus Practice Generator contract | ✅ | `WeeklyScheduleDecision` fixture és import-audit |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e08-r11-mnrT96 --brief
docs/rounds/e08-r11-qualified-day-planned-rest-and-recovery.md --base
cca0c4d3...` → **OK**, 5 módosított útvonal, 0 generated/ignored.

Az implementer jelzésében szereplő `dirty_files=1` után a tényleges tracked
munkafa tiszta volt. A `gate_shape=VIOLATION` valós: az implementer a formázást
és a gate-et `&&`-del egy shellhívásba tette, ezért ezt a gate-bizonyítékot a
review nem fogadta el. A reviewer a pontos artefaktumot önálló parancsként
újrafuttatta.

## Megállapítások

### F1 — MAJOR — A planned-rest epoch-nap UTC-ben készül, a shipping streak helyi éjfélben

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
- **Kötelező javítás:** a plan `LocalDate` konverzióját a shipping
  local-midnight epoch-bázissal egyeztesd, és a fenti időzónás cellát add az
  állandó `streak_service_test.dart`-hoz. A domain/legacy fájlt ne módosítsd.
- **Ellenőrzés:** a célzott teszt UTC-ben és
  `TZ=Europe/Budapest` alatt is zöld; a teljes kör-gate ismét zöld.
- **Státusz:** OPEN

## Valódi-sértés próbák

- **Időzóna:** a fenti eldobható Budapest-cella a shipping/local kontra UTC
  eltérést pirosra vitte.
- **Qualified threshold:** a javítás utáni re-review-ban függetlenül meg kell
  ismételni a `qualifies(any event)` mutációt; az A1 `119s` cellának pirosnak
  kell lennie, majd visszaállítás után a kör-gate-nek zöldnek.

## Gate-bizonyíték ellenőrzése

| Gate | Eredmény | Ellenőrizve |
|---|---|---|
| format | 1723 fájl, 0 változás | ✅ |
| analyze | no issues | ✅ |
| célzott teszt | 11/11 pass | ✅ |
| architecture | OK, 12 allowlisted deviation | ✅ |
| secrets | 3062 fájl, 0 finding | ✅ |
| l10n | 1405 üzenet parity | ✅ |
| teljes CI + property | még nincs dispatch | ⏳ |

## Merge-döntés

F1 MAJOR nyitott, ezért az ADR 0052 szerint merge tilos. Ugyanaz a Terra motor
kap egy javítókört, majd friss izolált re-review és exact-SHA CI szükséges.
