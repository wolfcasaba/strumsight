# ADR 0271 — Felismerés-helyreállítási program: UNKNOWN > CONFIDENTLY WRONG

**Státusz:** elfogadva (2026-08-15, user-döntés: a második fejlesztési sáv a
Chapter 14 első blokkját viszi). A Chapter 14 program nyitó döntése.
Forrás: [`docs/sdd/14-chapter-14-recognition-ui-recovery.md`](../sdd/14-chapter-14-recognition-ui-recovery.md),
[`docs/research/recognition-recovery-quick-start.md`](../research/recognition-recovery-quick-start.md).
Épít: [ADR 0087](0087-autonomous-round-pipeline.md) (kör-pipeline),
[ADR 0053](0053-ci-full-test-suite.md) (CI a mérce).

> A SDD Kör 01 szövege az `ADR 0213`-at jelölte. Az azóta foglalt
> (`0213-ai-tutor-production-wiring-and-sse-transport.md`); a program ADR-je
> ezért **0271**, a `tools/round-slots.py reserve-adr` foglalása szerint.

## Kontextus — a szállított app magabiztosan téved

A Chapter 14 audit mért adatai a **jelenleg szállított** StrumSightról:

| metrika | érték |
|---|---|
| chord accuracy (82 telefonos felvétel) | **67,1%** |
| onset F1 @50 ms | **67,4%** |
| direction accuracy (true-strum eval eseményeken) | **80,7%** |

És a felület ehhez képest:

- a Live UI **külön chord confidence, uncertainty és signal-quality állapot
  nélkül** mutat látványos chord- és irány-kártyákat;
- a szállított Chord CRNN **nincs bekötve** a Live primary útba;
- a `LiveFrame` túl kevés információt visz a UI-nak ahhoz, hogy a bizonytalanság
  megjeleníthető legyen.

Vagyis az app minden harmadik akkordnál téved, és ezt **nem mondja meg**. Ez
nem pontossági kérdés elsősorban, hanem **igazmondási**: a felhasználó nem tud
különbséget tenni a között, hogy ő játszott rosszul, vagy a rendszer értette
félre.

## Döntés

### 1. A termék alapszabálya: `UNKNOWN > CONFIDENTLY WRONG`

A Live UI **nem mutathat** biztos akkordot vagy pengetésirányt, ha a domain
döntés nem `confirmed`. A bizonytalanság megjelenítése nem opció, hanem
követelmény.

Ez ugyanaz az elv, amit a projekt máshol már négyszer kimondott: az ADR 0251 §2
(üres referencia nem illesztés), 0253 §3 (hiányzó mező nem kitalált érték),
0261 §2 (`unknown` nem gyengeség), 0268 (technikai hiba nem teljesítmény).
**Hiányzó bemenet sosem álcázható sikeres eredménynek.**

### 2. Előbb a mérés, aztán a modellcsere

A legacy DSP marad a baseline. Új felismerési modell **csak** mért A/B
report, grouped evaluation és ADR után aktiválható. A SDD kötelező sorrendje
(R01–R09 mérési alap, R10–R14 truthfulness) nem fordítható meg.

*Miért:* modellcsere mérés nélkül nem javítás, hanem találgatás — és a
jelenlegi 67%-ról nem lehetne megmondani, javult-e.

### 3. Három rollout-kapcsoló, mind OFF

`recognitionRecoveryEnabled`, `recognitionShadowModeEnabled`,
`newLiveStageEnabled` — mindhárom `false` **minden** környezetben, a
`nonProd`-ot is beleértve. A bekapcsolás mért kapuhoz kötött, külön döntés.

### 4. A release-kapu követelménye dokumentált, a CI-bekötése emberi döntés

Az aktiválás feltételeit (evaluation report, model manifest, corpus hash,
checksum, rollback recept) a `docs/eval/recognition-release-guard.md` rögzíti
**mérhetően**, hogy egy későbbi kör gépi ellenőrzést írhasson rá. A
`.github/workflows/**` tényleges módosítása **H-GATEGUARD** — a program körei
jelzik, nem implementálják.

### 5. A Vision nem takarhatja el az audio pontatlanságát

A Chapter 14 kifejezetten tiltja: a Visiont nem szabad az audio hibáinak gyors
elfedésére bekapcsolni. Előbb önálló audio baseline kell.

## Következmények

- Az első blokk (R01–R13) **nem javítja** a pontosságot — mérhetővé teszi, és
  megszünteti az igazmondási hibát. A javulás a R15-től jön.
- A Live UI rövid távon **kevesebbet** fog állítani, mint ma. Ez szándékos:
  a kevesebb, de igaz információ többet ér, mint a sok, de megbízhatatlan.
- A program a második pipeline-sávon fut, az Epic 7 mellett; a
  `tools/round-slots.py` diszjunktság-ellenőrzése garantálja, hogy a két sáv
  ne érjen ugyanahhoz a fájlhoz egyszerre (ADR 0171 §1).

## Mérce

Az `E14-R01` §6.1 mérce-mátrixa, benne a flag-alapértelmezés három kötelező
cellájával (production / gyár-default / **nem-production is `false`**) és a
valódi-sértés próbával: egy flaget `nonProd`-ra állítva az **A2** cellának
pirosnak kell lennie.

A program egészének mércéje a R02 reprodukálható baseline-ja: onnantól minden
állítás corpus-hoz, modellhash-hez és futtatott parancshoz kötött.
