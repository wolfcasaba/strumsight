# E06-R07 — Review

Brief: `docs/rounds/e06-r07-signal-quality-stage.md`  
Diff: `10e2d495..a2000848`  
Reviewer: Codex/Terra fallback, isolated `/tmp/review-e06-r07-repair` clone  
Dátum: 2026-08-11  
Verdikt: APPROVED

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1

A kezdeti független security review két MAJOR és egy MINOR leletét az
`a2000848` javító commit lezárta. A javítás után új, izolált klónból futott a
teljes helyi kör-gate és a célzott regressziós teszt. Két eldobható mutáció is
elvárt módon piros lett, majd a review-munkafa tisztán visszaállt.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Determinisztikus peak/RMS, clipping, silence, noise-floor és tonalness jelentés | ✅ | `signal_quality_math.dart`, `signal_quality_stage_test.dart` fixture-mátrix |
| 2 | Minden jelentett szám véges és a contract tartományában van | ✅ | `analysis_signal_quality_property_test.dart`, seeded 60 PCM-eset |
| 3 | Nem véges PCM nem eredményez mérési jelentést | ✅ | `signal_quality_stage.dart:28-34`; F2 property 30 NaN/+∞/−∞ esettel |
| 4 | Cancellation megfigyelhető a feldolgozás közben | ✅ | `signal_quality_math.dart` frame-hook; F1 mid-frame teszt |
| 5 | Legfeljebb egy progressz-esemény, terminális eredményemittálás nélkül | ✅ | `signal_quality_stage_test.dart` event-sink assertion |
| 6 | ADR- és képletevidence rendelkezésre áll | ✅ | ADR 0223; `docs/rag/chunks/019-signal-quality-metrics.md` |

## Scope-audit

`python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e06-r07 --brief docs/rounds/e06-r07-signal-quality-stage.md --base 10e2d495`
eredménye: **OK**, 10 változott, engedélyezett útvonal, 0 generált/ignorált
fájl. A wrapper jelzett `scope_audit=ok`-t is.

## Megállapítások

### F1 — MAJOR — Cancellation hiányzott a frame-feldolgozás alatt

- **Státusz:** FIXED (`a2000848`)
- **Ellenőrzés:** a `onFrame` callback eltávolításával a F1 célzott teszt
  Success-t kapott a várt `AnalysisCancelledException` helyett, tehát piros
  lett; a helyreállított kóddal zöld.

### F2 — MAJOR — A közvetlen stage-hívás nem véges PCM-et elfogadott

- **Státusz:** FIXED (`a2000848`)
- **Ellenőrzés:** a non-finite guard eldobható kikapcsolásával a seeded
  property teszt Success-t kapott a várt typed `audioNonFiniteSample` failure
  helyett, tehát piros lett; a helyreállított kóddal zöld.

### F3 — MINOR — A terminális esemény tiltását a teszt nem figyelte

- **Státusz:** FIXED (`a2000848`)
- **Ellenőrzés:** a teszt most eseményeket gyűjt, pontosan egy phase-progress
  eseményt és nulla `AnalysisRunResultEvent`-et vár.

### N1 — NOTE — A wrapper gate-shape jelzése fals pozitív volt

Az implementer jelzése `gate_shape=VIOLATION`, de a logban lévő tényleges
gate-invokáció pontosan `tools/round-gate.sh test/features/audio_analysis
test/property test/features/analyze`, csővezeték vagy `&&` nélkül. A scanner a
promptban/review-adatban szereplő szöveget is vizsgálta. A friss, izolált
review-gate a tényleges artefaktum és zöld; a jelzés nem scope-sértés.

## Gate-bizonyíték ellenőrzése

| Gate | Ellenőrzött eredmény |
|---|---|
| format | ✅ `dart format --output=none --set-exit-if-changed lib test tool` |
| analyze | ✅ `flutter analyze lib/ test/ tool/` |
| célzott tesztek | ✅ audio analysis, property, analyze; külön F1/F2 tesztek is zöldek |
| architecture / secrets / l10n | ✅ |
| CI | Függőben: az exact review-commit SHA-ra dispatchelendő |

## Merge-döntés

Nincs nyitott BLOCKER vagy MAJOR. A merge csak az exact-SHA CI és Router CI
zöld eredménye után engedélyezett.
