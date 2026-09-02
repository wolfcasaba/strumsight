# Rollout decision — séma

**Kör:** `E12-R32` (Chapter 12, Kör 32). Ez a dokumentum a lépcsőzött publikus
rollout (1% → 5% → 20%) **döntési sémája** — nem a döntés maga, és nem is
állít rollout-százalékot (§0.0 EMBERI KAPU). A tényleges, lépcsőnkénti
adatokat (megfigyelt óraszám, mért verdikt, döntéshozó, rollback-cél) a
[`staged-rollout-log.md`](staged-rollout-log.md) hordozza; azt a naplót
ez a séma ellen ellenőrzi a
[`tool/release/verify_rollout_decision.py`](../../tool/release/verify_rollout_decision.py).

Amit ez a dokumentum **nem** ismétel meg:

- a kötelező mutató-halmazt és a blokkoló verdikteket —
  forrásuk [`docs/operations/slo.yaml`](../operations/slo.yaml) (ADR 0484 D3);
- a lépcsőnkénti csomag kilenc szakaszát (build/commit, active flags,
  migration version, model version, known issues, dashboard snapshot,
  support readiness, rollback target, döntéshozó) —
  forrásuk [`rollout-packet-template.md`](rollout-packet-template.md), amit
  minden lépcső előtt egy másolatban kell kitölteni.

## Emberi kapu

<!-- human-gate:begin -->
A rollout-százalék állítása EMBERI művelet. Egyetlen lépcső sem indítható
automatikusan: a store/console-műveletet minden lépcsőnél egy ember hajtja
végre, a `staged-rollout-log.md` adott lépcsőjének kitöltött, `approved`
döntése alapján. „Ha N órán át nincs hiba, automatikusan lépjünk" jellegű
szabály NEM elfogadható gyengítés (§5.1) — a döntés minden lépcsőnél explicit.
A kill switch ([`kill-switches.md`](kill-switches.md) §3) és a rollback
(`rollback_target` mező) útja szintén emberi beavatkozást igényel a MA mért
mechanizmussal (build-idejű `dart-define` vagy forráskód-módosítás) — nincs
éles, automatikus remote-flag csatorna vagy aláírás-ellenőrzés a fán (ADR
0446 D3).
<!-- human-gate:end -->

## Lépcsők

A `step` a naplóban és a mutató-megfigyelésekben erre a táblára hivatkozik.
A `min_observation_hours` határ **INKLUZÍV** — egy lépcső pontosan a
határértéken (`observed_hours == min_observation_hours`) jóváhagyható.

<!-- rollout-steps:begin -->
| step | rollout_percent | min_observation_hours |
|---|---|---|
| `stage-1` | 1 | 24 |
| `stage-5` | 5 | 48 |
| `stage-20` | 20 | 72 |
<!-- rollout-steps:end -->

## Ellenőrzési szabályok (`verify_rollout_decision.py`)

Kilépőkód-szemantika fagyott a `docs/release/contract-freeze.md` 4. sora
szerint: `0 = ok`, `1 = validációs találat`, `2 = használati/formátumhiba` —
negyedik kód nincs. A csupasz hívás (kapcsolók nélkül) a valós fára mutató
alapértelmezésekkel MINDEN alábbi szabályt lefuttatja.

| # | Szabály | Kód |
|---|---|---|
| R1 | hiányzó/üres marker-blokk, alakra nem illő sor, hiányzó fájl | `2` |
| R2 | üres cella bármely sorban; ismeretlen `decision`/`step`/`verdict`/`metric`; egy deklarált lépcsőhöz nem pontosan egy döntés-sor; ismétlődő `(step, metric, cohort)`; `measured_value` és `verdict = unknown` összhangja | `1` |
| R3 | `source` ∉ {`machine`, `manual`} | `1` |
| R4 | a `cohort` cella nem pontosan egy ismert dimenzió (`all` / `platform:<érték>` / `app_version:<érték>` / `build_mode:<érték>`) | `1` |
| R5 | `approved` döntés, miközben a `blockers.md`-ben van nyitott P0/P1 sor | `1` |
| R6 | `approved` döntés `observed_hours < min_observation_hours` mellett (a fenti tábla szolgáltatja a küszöböt, a határ INKLUZÍV) | `1` |
| R7 | `approved` lépcső, amelynek van `slo.yaml` `blocking_verdicts`-beli verdiktű megfigyelés-sora, VAGY hiányzik egy `slo.yaml`-beli kötelező (`required: true`) mutató sora | `1` |
| R8 | `approved` döntés üres vagy `TBD`/`<…>` alakú `decision_maker` vagy `rollback_target` cellával | `1` |

Az `approved`-hoz kötött szabályok (R5–R8) szándékosan NEM futnak `pending`,
`held` vagy `rolled_back` döntésű sorokra — a napló váza így marad zöld
anélkül, hogy a mérce lazulna: egy ténylegesen `approved`-ra váltott sor
MINDEN szabályt kiállni köteles.
