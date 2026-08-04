# Review — E03-R21 (Trainer UI, loop, Speed Builder, result)

- **Reviewer:** Orchestrator (Claude / Opus 4.8), read-only + gate reproduction
- **Branch:** `codex/e03-r21-trainer-ui-loop-speed-results`
- **Implementer:** MiniMax M3
- **Base commit reviewed:** `d57d3a1`
- **Verdict:** **CHANGES REQUESTED** (acceptance coverage gaps — MAJOR)

## Mért állapot

- `flutter analyze lib/ test/features/song_trainer` → **No issues found** (mérve).
- A 27 R21-teszt (committer, resume, integration lifecycle, screen, result,
  accessibility) **mind zöld** (mérve, batch-futtatás).
- Scope: minden diff a §4 + §0.0 (app_route.dart route-konstansok) listán belül.
  A `_shell.dart` placeholderek eltávolítva, a `song_trainer/public.dart`
  visszaállítva, a router közvetlenül importálja a valódi screen-eket.

## MAJOR leletek (a §6 acceptance-mátrix hiányos lefedése)

Az implementer maga is `stopped`-ot jelzett („acceptance hiányos"); a mérés ezt
megerősíti. A meglévő tesztek zöldek, de a §6 kötelező megkülönböztető mátrix
alábbi cellái NINCSENEK teszttel lefedve:

- **M1 — Left-handed layout.** §6: „Left-handed, landscape, 200% text, reduced
  motion és reader throttling zöld." A `song_trainer_accessibility_test.dart`
  csak 200%/landscape/reduced-motion cellát fed; **left-handed nincs**
  (`grep left-hand` → 0 találat).
- **M2 — Reader throttling.** §5.3 + §6: a screen-reader live feedback throttled.
  Nincs a frekvenciát mérő teszt (a mátrix „reader throttling zöld" cellája
  fedetlen).
- **M3 — A–B / section loop végrehajtás.** §6: „Section és valid A–B loop
  működik; invalid range nem indul; loop attempt elkülönül." Nincs teszt a valid
  A–B loopra, az invalid-range elutasítására, sem a loop-attempt-elkülönülésre
  (külön attempt ID/result). (`grep A-B|abLoop` → 0.)
- **M4 — `paused` fázis-sor.** A §6 mátrix `paused | A–B | rate no | seek
  engedett, speed disabled reason` cellája nincs teszttel (a screen-teszt
  countIn/running/failed cellát fed, paused-ot nem).
- **M5 — Speed Builder „policy fut" ág.** §6: „…különben publikus Speed Builder
  policy fut." Csak a `disabled` ág van tesztelve; a publikus Speed Builder
  policy tényleges futása (a `practice/public.dart` additív exportján át)
  fedetlen.

## Elvárt zárás

A javító kör mind az M1–M5 cellát fedje le valódi, megkülönböztető teszttel (a
brief §6 „legalább egy központi invariánst eldobható mutációval pirosra vált"
elve szerint), a §4+§0.0 fájllistán belül, majd a targeted teszt-batch és az
`analyze` maradjon zöld. A teljes suite + property + APK a CI-n.
