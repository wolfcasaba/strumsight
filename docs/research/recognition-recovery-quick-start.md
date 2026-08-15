# StrumSight Recognition Recovery — Quick Start for Codex

## Miért indul ez a program?

A feltöltött kód és a repository saját valós-audio baseline-ja szerint:

- chord accuracy: **67,069%** 82 telefonos felvételen;
- onset F1 @50 ms: **67,391%**;
- a shipped 3-class strum modell direction accuracy-ja a true-strum eval eseményeken: **80,676%**;
- a Live UI külön chord confidence, uncertainty és signal-quality állapot nélkül mutat látványos chord/arrow kártyákat;
- a szállított Chord CRNN nincs bekötve a Live primary útba;
- a Chapter 13 UI/UX specifikáció nincs a feltöltött repositoryban.

## Első Codex blokk

Egymás után, külön branch/PR-ben:

1. **R01** Recovery kickoff és feature freeze
2. **R02** Reprodukálható baseline
3. **R03** Model activation telemetry
4. **R04** RecognitionFrame V2
5. **R05** Signal Quality Analyzer
6. **R06** Accuracy Lab capture
7. **R07** Annotation tool
8. **R08** Grouped evaluation harness
9. **R09** Quality dashboard és fail-closed gate
10. **R10** Direction abstention
11. **R11** Chord uncertainty
12. **R12** Provisional/confirmed stabilizer
13. **R13** Live UI truthfulness hotfix

## Másolandó Codex prompt

```text
Olvasd el az AGENTS.md, HANDOFF.md és
StrumSight_SDD_Chapter_14_Recognition_UI_Recovery.md fájlokat.

Kizárólag a Chapter 14 aktuálisan megadott körét hajtsd végre.
Ne kezdd el a következő kört.

Kötelező:
- először auditáld a meglévő implementációt és teszteket;
- reprodukáld a problémát teszttel vagy mérési fixture-rel;
- ne hangolj thresholdot a test seten;
- ne módosíts shipping DSP/ML konstansokat A/B report és ADR nélkül;
- a modell bizonytalansága esetén abstainelj, ne adj kötelező választ;
- futtasd külön a format, analyze, test, architecture és releváns evaluation kapukat;
- a le nem futtatott ellenőrzést ne állítsd sikeresnek;
- frissítsd a HANDOFF.md fájlt teljes mérési evidenciával.

A kör végén add meg:
1. módosított fájlok;
2. végrehajtott követelmények;
3. futtatott parancsok és eredmények;
4. baseline vs új mérés;
5. nyitott kockázatok;
6. rollback mód;
7. pontos következő kör, de ne implementáld.
```

## Legfontosabb product szabály

```text
UNKNOWN > CONFIDENTLY WRONG
```

A Live UI nem mutathat biztos down/up nyilat vagy akkordot, ha a domain decision nem `confirmed`.
