# Staged rollout log — 1% → 5% → 20%

**Séma:** [`rollout-decision.md`](rollout-decision.md). **Kötelező
mutató-halmaz és blokkoló verdiktek forrása:**
[`docs/operations/slo.yaml`](../operations/slo.yaml). **Ellenőrző:**
[`tool/release/verify_rollout_decision.py`](../../tool/release/verify_rollout_decision.py).

A váz minden sora kitöltésre vár: minden döntés `pending`, minden verdikt
`unknown`, minden `measured_value` `n/a`. A kitöltendő szöveges cellák
(`window_start`, `window_end`, `observed_hours`, `decision_maker`,
`rollback_target`) értéke a `TBD` literál — a `pending` döntéshez kötött
sorokon ez zölden marad, mert az `approved`-hoz kötött szabályok (R5–R8) csak
egy ténylegesen `approved`-ra váltott sorra futnak (§0.0.2).

Minden megfigyelés-sor `source`-a MA `manual`: nincs éles telemetria-csatorna
egyik `slo.yaml`-mutatóhoz sem staged-rollout cohort-bontásban — a
`crash_free_sessions` és a `tutor_turn_success_rate` `source:` mezője ezt
explicit kimondja (`slo.yaml`), a másik három mutató (`chord_detection_latency_p95`,
`tuner_pitch_accuracy`, `offline_egress_free`) forrása is fejlesztés-idejű
benchmark/teszt-eszköz, nem éles, per-cohort rollout-monitoring. A megfigyelés
forrása ezért ma a store-konzol, a felhasználói visszajelzés és a
diagnosztikai bundle (brief §2) — amíg ez nem változik, `machine` forrás
kitalált automatizmus lenne (§0 STOP-protokoll).

## Kill-switch előfeltétel (EMBERI, §0.0.1 P1)

Nincs valódi hálózati remote-flag csatorna vagy aláírás-ellenőrzés
([`kill-switches.md`](kill-switches.md) §3) — a lépcsőnkénti kill-switch út
MA build-idejű `dart-define` vagy forráskód-módosítás, amit egy embernek kell
elvégeznie és újra-buildelnie/deploy-olnia. Ez a sor NEM automatizmus, csak a
MÉRT útvonal jelölése minden lépcső előtti előfeltételként:

| step | kill-switch előfeltétel (MÉRT mechanizmus) | forrás |
|---|---|---|
| `stage-1` | a lépcsőben aktív flag(ek) kill-switch útja: `dart-define` vagy forráskód-módosítás, ember hajtja végre | `kill-switches.md` §2 |
| `stage-5` | a lépcsőben aktív flag(ek) kill-switch útja: `dart-define` vagy forráskód-módosítás, ember hajtja végre | `kill-switches.md` §2 |
| `stage-20` | a lépcsőben aktív flag(ek) kill-switch útja: `dart-define` vagy forráskód-módosítás, ember hajtja végre | `kill-switches.md` §2 |

## Döntések

<!-- rollout-decisions:begin -->
| step | window_start | window_end | observed_hours | decision | decision_maker | rollback_target |
|---|---|---|---|---|---|---|
| `stage-1` | TBD | TBD | TBD | `pending` | TBD | TBD |
| `stage-5` | TBD | TBD | TBD | `pending` | TBD | TBD |
| `stage-20` | TBD | TBD | TBD | `pending` | TBD | TBD |
<!-- rollout-decisions:end -->

## Megfigyelések

<!-- rollout-observations:begin -->
| step | metric | cohort | source | verdict | measured_value |
|---|---|---|---|---|---|
| `stage-1` | `chord_detection_latency_p95` | `all` | `manual` | `unknown` | n/a |
| `stage-1` | `tuner_pitch_accuracy` | `all` | `manual` | `unknown` | n/a |
| `stage-1` | `offline_egress_free` | `all` | `manual` | `unknown` | n/a |
| `stage-1` | `crash_free_sessions` | `all` | `manual` | `unknown` | n/a |
| `stage-1` | `tutor_turn_success_rate` | `all` | `manual` | `unknown` | n/a |
| `stage-5` | `chord_detection_latency_p95` | `all` | `manual` | `unknown` | n/a |
| `stage-5` | `tuner_pitch_accuracy` | `all` | `manual` | `unknown` | n/a |
| `stage-5` | `offline_egress_free` | `all` | `manual` | `unknown` | n/a |
| `stage-5` | `crash_free_sessions` | `all` | `manual` | `unknown` | n/a |
| `stage-5` | `tutor_turn_success_rate` | `all` | `manual` | `unknown` | n/a |
| `stage-20` | `chord_detection_latency_p95` | `all` | `manual` | `unknown` | n/a |
| `stage-20` | `tuner_pitch_accuracy` | `all` | `manual` | `unknown` | n/a |
| `stage-20` | `offline_egress_free` | `all` | `manual` | `unknown` | n/a |
| `stage-20` | `crash_free_sessions` | `all` | `manual` | `unknown` | n/a |
| `stage-20` | `tutor_turn_success_rate` | `all` | `manual` | `unknown` | n/a |
<!-- rollout-observations:end -->
