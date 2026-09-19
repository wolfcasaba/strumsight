# ADR 0543 — Chapter 14 production gate és a nyomonkövetési zárás: a kapu-tábla a MÉRT állapotot mondja ki, nem a kívánt állapotot

- **Státusz:** Elfogadva
- **Kör:** `E14-R42` (Chapter 14 — Recognition Accuracy & Useful UI Recovery,
  Kör 42 — a fejezet ZÁRÓ köre, dokumentum-oldal)
- **Dátum:** 2026-09-09
- **Implementer motor:** Claude (Opus 5), PKG-D csomag-ügynök
- **Kapcsolódó:**
  [ADR 0511](0511-recognition-release-gate-and-single-source-report.md)
  (fail-closed release-kapu: hiányzó metrika = FAIL, nem „nincs adat = PASS"),
  [ADR 0443](0443-sdd-index-machine-checkable-contract.md) (az SDD-index
  gépi szerződés: a körszámot a checker méri, a státusz-oszlop prózáját nem),
  [ADR 0354](0354-recognition-baseline-manifest-and-evidence-index.md)
  (a baseline manifest a mért számok egyetlen forrása),
  [ADR 0542](0542-opt-in-beta-telemetry-consent-and-recognition-rollout-flags.md)
  (a kiadási létra fokai, amikhez a kapu-sorok kötődnek),
  [ADR 0271](0271-recognition-recovery-program.md) §9 (UNKNOWN > CONFIDENTLY
  WRONG)

## Kontextus — a két MÉRT, hamis állítás, amit ez a kör javít

### 1. `docs/sdd/00-index.md` Chapter 14 sora elavult volt

A 28. sor státusza: *„nyitva (1/42 done, 18 prepared nem futtatva; R20–R42
briefjei meg sem íródtak)"*.

**Mérve ugyanezen a fán:** `ls docs/rounds | grep -c '^e14-'` → **19** brief;
`docs/execution/pipeline-queue.tsv` az `E14-R01…R19` sorokat mind `done`
állapotban tartja; a `docs/reviews/` 22 `e14*` reviewt hordoz; a HANDOFF
2026-09-05-i bejegyzései PR-ral és squash-SHA-val zárják a sávot. Az „1/42
done" tehát **18 körrel** téved, a „briefjei meg sem íródtak" pedig a
0–19 tartományra egyszerűen hamis.

### 2. A nyomonkövetési mátrixban NULLA `E14-R*` sor volt

`grep -c '^| E14-R' docs/execution/06-requirements-traceability-matrix.md`
→ **0**. A Ch14 §13 DoD „traceability friss" pontja emiatt nem teljesült.

## Döntések

### D1 — A production gate dokumentum a MÉRT állapotot sorolja, kapu-soronként

`docs/release/ch14-production-gate.md` minden Ch14 §7 metrika-sorhoz négy
oszlopot ad: **küszöb**, **mért érték vagy `nincs mérve`**, **verdikt**, és a
**tulajdonos workflow** (ami azt a számot elő tudja állítani). A „nincs
mérve" cella soha nem üres és soha nem `0` — az ADR 0511 fail-closed elve
szerint a hiányzó metrika **FAIL**, nem semleges.

**NEM elfogadható gyengítés:** összesített „X/Y kapu zöld" fejléc a soronkénti
bizonyíték helyett. A két bukó szám (onset F1@50 ms 0,674 vs. 0,82; chord
accuracy 0,671 vs. 0,80) így elveszne egy százalékban.

### D2 — Az emberi döntési sorok külön szekcióban, nevesítve

A rollout-százalék, az `adaptiveShellEnabled` production GA-flipje, a privacy
review aláírása, a rollback-gyakorlat és a valós gitáros APK-teszt **nem
metrika**, hanem emberi kapu. Ezek külön táblában állnak, „ki dönt / mi a
bemenete / ma nyitott" oszlopokkal, hogy egy zöld gépi kapu se olvassa
magát jóváhagyásnak.

### D3 — A visszamenőleges nyomonkövetési sorok a MEGLÉVŐ sorformátumot követik

Az `E14-R01…R19` sorok a mátrix „Fejlesztési körök" táblájának formátumában
kerülnek be (`ID | Chapter/kör | SDD forrás | Elvárt bizonyíték | Issue | PR |
Státusz`), a valós ADR-számmal — **nem** a `pipeline-queue.tsv` ADR-oszlopával,
ami az egész E14 sávra elavult (mérve: R12 sor `0364`, valós `0518`; R15 sor
`0367`, valós `0521`). Az ADR-számok a `docs/adr/**` fájlok kör-hivatkozásából
vannak mérve.

Ahol egy szám nem mérhető ezen a shallow klónon (az `E14-R01` PR-azonosítója),
ott `_TBD_` áll az indoklással — **nem** kitalált PR-szám.

### D4 — A jelen hullám körei `In progress` státusszal kerülnek be, nem `Done`-ként

Az `E14-R23/24/33/40/41/42` sorok most jönnek létre, és a státuszuk kimondja,
mi készült el (zászló-felület, consent, dokumentum) és mi nem (fogyasztó,
mérés, emberi aláírás). Egy `Done` ezekre a sorokra ma hamis lenne.

### D5 — Az SDD-index státusz-oszlopa prózában javul, a körszám nem változik

A `tool/check_sdd_index.dart` a fejezet-fájl kör-fejléceiből méri a `42`-t
(ADR 0443 D1); a státusz-oszlop prózáját nem méri. A javítás tehát csak a
prózát írja át, a `42`-höz nem nyúl — a checker zöld marad.

## Ami MÉRVE VAN és ami NEM

| Állítás | Státusz |
|---|---|
| 19 `e14-r*` brief van a fán, a queue mind `done` | **mérve** (`ls`, `grep` a `pipeline-queue.tsv`-n) |
| Az onset F1@50 ms = 0,674 és a chord accuracy = 0,671 | **mérve** (`evaluation/recognition/baseline_manifest.json`, `appCommit 5ceed22d`) |
| A `direction` / `noChord` / `latency` / `calibration` blokk nincs mérve | **mérve** (a manifest `status: not-measured` mezői) |
| A §7.1 korpusz-követelmény (8 gitáros / 6 telefon / 4 gitár / 4 szoba) | **NEM TELJESÜL** — a baseline 82 Klangio-felvétel, nem telefon-mikrofonos diverzitás |
| Bármely §7.2/§7.4 kapu PASS-a | **NEM MÉRT vagy MÉRTEN BUKÓ** |
| „Nincs nyitott P0/P1" | **NEM MÉRT** — a Kör 40 field study nem futott |
| A rollback-gyakorlat | **NEM FUTOTT** ebben a körben (a `tool/release/verify_rollback.py` a kör tilos zónája) |

## Következmények

- A Chapter 14 **nem zárható le** ezzel a körrel: a kör a lezárás
  DOKUMENTUMÁT szállítja, és kimondja, hogy a PASS nincs meg.
- A `docs/release/ch14-production-gate.md` a hivatkozási pont minden későbbi
  „mehet-e a rollout?" kérdésre; a benne álló sorok forrása a baseline
  manifest és a release-kapu JSON, nem ez a dokumentum.
- A nyomonkövetési mátrix E14 sávja mostantól létezik; a jelen hullám
  köreinek státuszát a hullám zárásakor kell `Done`-ra emelni, mért
  bizonyítékkal.
