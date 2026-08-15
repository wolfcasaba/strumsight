# E99-R11 — Review

Brief: `docs/rounds/e99-r11-gov-30c-3-progress-phase-decoupling.md`
Diff: `d4341eb..39068df`
Reviewer: Terra (független a `sonnet-impl` implementertől) · Dátum: 2026-08-15
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

Az opcionális, stage-id alapú fázistérkép a régi pozicionális utat és a
kilences sapkát változatlanul hagyja, míg a teljes 18-stage kompozíció csak
térképpel megengedett. A `publish()` őr pontosan a szükséges mértékben lazult:
egyenlő fázis elfogadott, visszalépés továbbra is hiba.

## Acceptance criteria

| # | Teljesült | Bizonyíték |
|---|---|---|
| A1 | ✅ | térkép nélküli cap-tesztek érintetlenek; a konstruktorban a pozicionális cap megmaradt |
| A2, A8 | ✅ | `full_pipeline_composition_test.dart`: valódi PCM-en 18 stage, rögzített provenance és fázissorozat |
| A3–A5 | ✅ | `analysis_stage_phases_test.dart`: hiányzó/regresszív térkép elutasítása és 18 kulcs halmazegyezése |
| A6 | ✅ | izolált mutáció: az őr eltávolítása után a célteszt `Expected failed, Actual complete` hibával piros volt |
| A7 | ✅ | izolált mutáció: `<` → `<=` után A7 `Expected complete, Actual failed` hibával piros volt |
| A9–A10 | ✅ | scope-audit és diff: sem `application/**`, sem `domain/analysis_progress.dart` nem változott |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e99-r11.hOcz1T --brief
docs/rounds/e99-r11-gov-30c-3-progress-phase-decoupling.md --base d4341eb`
eredménye: **OK**, 6 módosított útvonal, 0 listán kívüli és 0 generált/ignorált.

## Gate-bizonyíték

- Izolált, originről klónozott példány: a `tools/round-gate.sh` format és
  analyze lépése zöld (`1490 files, 0 changed`; `No issues found`), majd a
  három célteszt közvetlen újrafuttatása **21/21 passed**.
- A két valódi-sértés próba után a review-klón visszaállított, `git diff
  --check` tiszta.

## Megállapítások

### F1 — MAJOR — a kapott fázistérkép nincs védetten másolva

- **Fájl:** `lib/features/audio_analysis/engine/analysis_pipeline.dart:64`
- **Probléma:** a privát `_stagePhases` a hívó `Map`-referenciáját tartja. A
  konstrukció UTÁNI külső mutáció megkerüli a konstruktor-validációt; a
  security review reprodukáló próbája egy validált második fázist
  `preprocessing`-re írt át és a futás hibásan bukott el.
- **Kötelező javítás:** konstrukciókor defenzív immutable másolat, továbbá
  regressziós teszt, amely bizonyítja, hogy a hívó későbbi map-módosítása nem
  változtatja a pipeline futását.
- **Státusz:** FIXED (`39068df`) — `Map.unmodifiable` snapshot készül a
  konstrukciókor. Friss, originről klónozott review-ban a három célteszt
  **22/22 passed**; köztük az F1 regressziós cella.

## Merge-döntés

Az F1 MAJOR lezárva, nincs nyitott BLOCKER vagy MAJOR. A high-risk security
review újrafuttatása és az exact-SHA CI még külön merge-feltétel.
