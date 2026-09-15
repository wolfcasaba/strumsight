# String-arrival cue vs the shipped live CRNN — 2026-09-15

Command:

```
GUITARSET_DIR=C:/Users/kcsab/Downloads/recipewis flutter test test/tools/string_arrival_fusion_probe_test.dart
```

- corpus: GuitarSet Rock+Funk comping, `_comp_mic.wav`, **72 files**
- clean sweeps (hexaphonic truth): **3035**
- of those, the live path did NOT hear: **1039** (34.2%) — 953 of them heard as an onset but suppressed by the shipped no-strum gate (P(no-strum) > 0.85), 86 with no onset within ±80 ms at all
- **scored sweeps (CRNN heard): 1996** — every table below is over exactly these
- truth prior — all clean sweeps: 72.9% down (down 2213, up 822); scored sweeps: 81.9% down (down 1635, up 361) — the shipped no-strum gate drops UP-strokes far harder than down-strokes
- runtime: 342s

## Accuracy over the 1996 sweeps the CRNN heard

| rule | accuracy | down | up | players 00-02 | players 03-05 | on cue high tier |
| --- | --- | --- | --- | --- | --- | --- |
| CRNN alone (shipped) | 46.4% (927/1996) | 43.3% (708/1635) | 60.7% (219/361) | 48.0% (437/910) | 45.1% (490/1086) | 56.5% (100/177) |
| cue alone (CRNN on abstain) | 62.3% (1243/1996) | 60.9% (995/1635) | 68.7% (248/361) | 59.1% (538/910) | 64.9% (705/1086) | 97.7% (173/177) |
| F1  cue if conf >= 0.80 | 50.1% (1000/1996) | 47.5% (777/1635) | 61.8% (223/361) | 49.3% (449/910) | 50.7% (551/1086) | 97.7% (173/177) |
| F2  cue if conf >= 0.65 | 62.3% (1243/1996) | 60.9% (995/1635) | 68.7% (248/361) | 59.1% (538/910) | 64.9% (705/1086) | 97.7% (173/177) |
| F3  conf >= 0.80, or any cue when CRNN margin < 0.30 | 50.7% (1012/1996) | 48.1% (786/1635) | 62.6% (226/361) | 49.9% (454/910) | 51.4% (558/1086) | 97.7% (173/177) |
| F4  cue whenever it is not ambiguous | 62.3% (1243/1996) | 60.9% (995/1635) | 68.7% (248/361) | 59.1% (538/910) | 64.9% (705/1086) | 97.7% (173/177) |

## The cue on its own, over the same 1996 sweeps

- coverage (cue not ambiguous): 784 / 1996 = 39.3%
- accuracy on covered: 88.3% (692/784)

| cue tier | n | cue accuracy | CRNN accuracy on the same |
| --- | --- | --- | --- |
| high | 177 | 97.7% | 56.5% (100/177) |
| mid | 607 | 85.5% | — |
| abstain | 1212 | n/a | — |

The `on cue high tier` column of the first table is the CRNN's own accuracy on exactly the sweeps where the cue is confident — the comparison that decides whether handing those sweeps to the cue is an improvement or a regression.
