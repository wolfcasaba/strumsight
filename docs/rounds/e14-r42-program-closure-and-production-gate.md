# E14-R42 — Program-zárás és production gate: a kapu-tábla és a nyomonkövetés MÉRT állapotra igazítása

- **Kör-azonosító:** `E14-R42` (Chapter 14, Kör 42 — a fejezet ZÁRÓ köre)
- **ADR:** [0543](../adr/0543-ch14-production-gate-and-traceability-closure.md)
  (foglalva: `python3 tools/round-slots.py reserve-adr --round E14-R42`)
- **Dátum:** 2026-09-09
- **Implementer:** Claude (Opus 5), PKG-D
- **Terv:** [`epic-14-completion-plan.md`](epic-14-completion-plan.md) §2 R42

## 1. Cél

A Chapter 14 lezárásának DOKUMENTUMÁT szállítani — és közben kijavítani a
terv által mérten megtalált **két hamis állítást**. A kör **nem** mondja ki,
hogy a fejezet kész: a production gate tábla verdiktje `NOT PASSING`.

## 2. Mért állapot — a két javítandó defekt

### D1: `docs/sdd/00-index.md` 28. sora elavult

Állítás: *„nyitva (1/42 done, 18 prepared nem futtatva; R20–R42 briefjei meg
sem íródtak)"*.

Mérve ugyanezen a fán:
- `ls docs/rounds | grep -c '^e14-'` → **19**
- `grep -P '^E14-R' docs/execution/pipeline-queue.tsv` → 19 sor, mind `done`
- `ls docs/reviews | grep -c '^e14'` → **22**
- HANDOFF 2026-09-05: PR + squash-SHA az R02…R19 körökre

Az „1/42 done" tehát 18 körrel téved; a „briefjei meg sem íródtak" az
R01–R19 tartományra hamis (az R20–R42 tartományra viszont IGAZ maradt —
a javított próza ezt megtartja).

### D2: nulla `E14-R*` sor a nyomonkövetési mátrixban

`grep -c '^| E14-R' docs/execution/06-requirements-traceability-matrix.md`
→ **0**. A Ch14 §13 DoD „traceability friss" pontja emiatt nem teljesült.

### A kapu-oldal mért számai

`evaluation/recognition/baseline_manifest.json` (app commit `5ceed22d`):
onset F1@50 ms **0,674** (kapu 0,82); chord accuracy **0,671** (kapu 0,80);
a leggyengébb per-label recall **`C#-major` = 0,000** (kapu 0,55); a
`direction`, `noChord`, `latency`, `calibration` blokk **`not-measured`**.

## 3. Scope

**Benne:** `docs/release/ch14-production-gate.md` (soronkénti Ch14 §7 tábla
mért értékkel, verdikttel és tulajdonos workflow-val + emberi döntési sorok);
a `00-index.md` 28. sorának prózája; az `E14-R01…R19` és a jelen hullám
sorainak felvitele a mátrixba; README-említés; kockázat-nyilvántartás sorai.

**Kívül:** bármely kapu PASS-a; a rollback-gyakorlat (`tool/release/**` tilos
zóna); a HANDOFF (csak orchestrátor); a `pipeline-queue.tsv` (csak
orchestrátor — a javasolt sorok a jelentésben).

## 4. Fájlok

**Új:** `docs/release/ch14-production-gate.md`, `docs/adr/0543-*.md`.
**Módosított:** `docs/sdd/00-index.md` (28. sor státusz-prózája),
`docs/execution/06-requirements-traceability-matrix.md` (E14 sáv),
`docs/execution/07-risk-register.md`, `README.md`.

## 5. Nem elfogadható gyengítések

- Összesített „X/Y kapu zöld" fejléc a soronkénti bizonyíték helyett — a két
  bukó szám elveszne egy százalékban.
- „Nincs adat" semleges cellaként — az ADR 0511 fail-closed elve szerint a
  hiányzó metrika **FAIL**.
- A jelen hullám köreinek `Done` státusza a mátrixban — a fogyasztók, a
  mérések és az emberi aláírások hiányoznak.
- Kitalált PR-azonosító ott, ahol a shallow klónon nem mérhető (`E14-R01`).

## 6. Elfogadási feltételek

| # | Feltétel | Státusz |
|---|---|---|
| A1 | A `00-index.md` Ch14 sora a mért állapotot mondja | **DOKUMENTUM** (a `check_sdd_index.dart` a `42` körszámot méri, a prózát nem — a checker zöld marad) |
| A2 | A mátrix hordozza az `E14-R01…R19` sorokat, valós ADR-számmal | **DOKUMENTUM** — `grep -c '^| E14-R'` > 0 |
| A3 | A jelen hullám sorai `In progress` státusszal, kimondva mi hiányzik | **DOKUMENTUM** |
| A4 | Minden Ch14 §7 metrika-sor státusza (mért / nem mért) és tulajdonos workflow-ja megvan | **DOKUMENTUM** — `ch14-production-gate.md` §1–2 |
| A5 | Az emberi döntési sorok külön táblában, nevesítve (`adaptiveShellEnabled` GA is) | **DOKUMENTUM** — §4 |
| A6 | „Minden release gate PASS és bizonyítékkal linkelt" | **NEEDS-MEASUREMENT** — mértén BUKÓ vagy nem mért; a tábla verdiktje `NOT PASSING` |
| A7 | Rollback-gyakorlat, „nincs nyitott P0/P1" | **NEEDS-MEASUREMENT** — emberi kapu, a Kör 40 study sem futott |

## 10. Handoff

- **Orchestrátor:** a `docs/execution/pipeline-queue.tsv` sorait ez a kör NEM
  írja; a javasolt sorok a PKG-D jelentésében vannak. A HANDOFF-bejegyzés
  szintén az orchestrátoré.
- **PKG-B:** a `ch14-production-gate.md` §1–2 táblája a
  `baseline_manifest.json` VIEW-ja. Új mérés után előbb a manifest frissül,
  és csak utána ez a fájl — soha fordítva.
- **A fejezet nem zárható le** ezzel a körrel. A záró aktus a felhasználó
  valós gitáros APK-tesztje (`build-apk.yml`), ami a §4 tábla utolsó sora.
