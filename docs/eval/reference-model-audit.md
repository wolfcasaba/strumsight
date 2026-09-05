# Reference-model reproduction and licence audit — Klangio ISMIR 2025

- **Round:** `E14-R17` ([brief](../rounds/e14-r17-reference-model-repro-and-licence-audit.md), [ADR 0369](../adr/0369-reference-model-repro-and-licence-audit.md))
- **Subject:** S. Murgul, J. Schimper, M. Heizmann — *Joint Transcription of
  Acoustic Guitar Strumming Directions and Chords*, ISMIR 2025
  ([arXiv:2508.07973](https://arxiv.org/abs/2508.07973)); repository
  `Klangio/guitar-strumming-transcription`, pinned commit
  `929e403f3256b055c1eea27064ae39f36905359e`.
- **Machine record:** [`ml/reference/reference_manifest.json`](../../ml/reference/reference_manifest.json).
- **Measured 2026-09-05** (pre-flight, hálózatról: GitHub API + `raw.githubusercontent.com`).

This report is **infrastructure and a legal judgment, not a performance
number** (ADR 0369 D6). The checkpoint is measurably reachable (public
Git-LFS object) and the licence audit is conclusive without running
anything — but no PyTorch runtime exists on this box, so neither evaluation
below actually ran this round. Every unrun cell is the literal string
**`NEM MÉRT`**, next to its measured reason and the exact reproduction
command. No cell in this report contains an estimated or extrapolated
number (ADR 0369 D6 — becslés tiltott).

## 1. Hivatalos fixture (Klangio scripts/evaluate.ipynb)

The upstream paper's own evaluation split, as the reference repository
reports it.

| Metric | Value | Korpusz-hash |
|---|---|---|
| F1 (any-direction) | NEM MÉRT | NEM MÉRT |
| F1 (up-strum) | NEM MÉRT | NEM MÉRT |

**Miért NEM MÉRT:** a reprodukció `torch`/`lightning`/`note-seq`/
`torchlibrosa`/`librosa==0.10.1`/`hydra-core`/`wandb` függőségeket igényel
(`ml/reference/reference_manifest.json` → `requirements`); ezek egyike sem
importálható ezen a boxon sem az egyetlen ML-venvből (`/home/ubuntu/tf-venv`
— TensorFlow 2.21.0/Keras 3.15.0, NEM PyTorch), sem a rendszer-Pythonból
(mérve 2026-09-05, lásd `ml/reference/README.md`). Az upstream kiértékelés
ma is csak notebook (`scripts/evaluate.ipynb`), aminek a cella-kimenet
szerződését a pre-flight nem tudta elolvasni (nincs PyTorch a mérő gépen).

**Reprodukáló parancs** (miután a fenti függőségek telepítve vannak egy
PyTorch-képes gépen):

```bash
python3 ml/reference/run_reference_eval.py \
  --manifest ml/reference/reference_manifest.json \
  --workdir /tmp/klangio-repro
```

## 2. StrumSight held-out (E14-R08 grouped harness)

A pinelt checkpoint kiértékelése a StrumSight saját, csoportosított
(felvétel-szintű) held-out felosztásán — összevetve azzal, amit a
`ml/model_card.json` a StrumSight SAJÁT tanított modelljére mér ugyanezen a
korpuszon.

| Metric | Value | Korpusz-hash |
|---|---|---|
| Direction accuracy | NEM MÉRT | NEM MÉRT |
| F1 (up-strum) | NEM MÉRT | NEM MÉRT |

**Miért NEM MÉRT:** ugyanaz a hiányzó PyTorch/Lightning futtatókörnyezet, plusz
a checkpoint az upstream `klangio/modules/strumming_crnn` modellosztályaival
tölthető csak be — ez a betöltés maga is a hiányzó függőségektől függ.

**Reprodukáló parancs:** ugyanaz, mint fent — a script mindkét mérést egy
futásban állítja elő, de KÜLÖN struktúrában (`official_fixture` /
`strumsight_held_out`), soha nem egy közös táblában vagy átlagban (ADR 0369
D4).

## 3. Licenc-audit — HÁROM külön ítélet (ADR 0369 D1/D2)

| Artefaktum | Forrás | Mért licenc | Bizonyíték | Ítélet |
|---|---|---|---|---|
| Kód (`klangio/modules/strumming_crnn/`, `scripts/`) | `LICENSE` + `README.md` | `Apache-2.0` | README „License" szakasz szó szerint: „Copyright © 2025 Klangio GmbH — This **software** is licensed under the Apache License, Version 2.0." | megengedő — kutatási reprodukcióra használható |
| Checkpoint (`checkpoints/wc/step=19000-f1=0.8225.ckpt`, sha256 `80297850d7d2150093d5ae2bcb090466566ad24fa835a5c1e67f16ca38a3ea44`, **134 344 202 bájt**) | — | **NEM NYILATKOZOTT** | A README „License" szakasza kifejezetten „software"-re szűkíti a grantot; a „Pretrained Checkpoint" szakaszban nincs licenc-mondat, a `checkpoints/` alatt nincs LICENSE-fájl | **blokkoló** |
| Adathalmaz (`dataset/klangio-gst-mm-2025/`, 330 blob, 913 163 829 bájt) | — | **NEM NYILATKOZOTT** | A README „License" szakasza kifejezetten „software"-re szűkíti a grantot; a „Dataset" szakaszban nincs licenc-mondat, a `dataset/` alatt nincs LICENSE-fájl | **blokkoló** |

A `Citation` szakasz kutatási idézési kötelezettséget ír elő („If you use this
code, data, or models in your research…"), ami **nem** termék-engedély.

**NEM elfogadható gyengítés** (amit ez a tábla explicit KIZÁR): a repo-szintű
`Apache-2.0` lefelé öröklése a checkpointra/adatra, vagy a hiány
`"unknown"`/`"n/a"` sztringgel való kitöltése. A gépi manifest (`spdx: null` +
`verdict: "blocking"`) és a `test/tooling/reference_model_licence_guard_test.dart`
ezt a szigort tartja gépi kényszerként — lásd §5.

## 4. Go/no-go javaslat

**NO-GO a termék-felhasználásra.**

A javaslat kizárólag MÉRT tényekre hivatkozik (ADR 0369 D6 — becsült
latency/pontosság szám tiltott ebben a reportban):

1. **A checkpoint és az adathalmaz licence NEM NYILATKOZOTT, mindkettő
   blokkoló** (§3). A kétség nem engedély: a nyilatkozat hiánya a szerzői jog
   alapfeltevése szerint fenntartott jog, nem szabad felhasználás.
2. A checkpoint **mért mérete 134 344 202 bájt** (≈128 MiB) — ez a mobil
   memória-költség **alsó korlátja**, ha ez a súly valaha bekötésre kerülne.
   Nem kerül bekötésre: a fenti NO-GO ezt tárgytalanná teszi, de a szám a
   StrumSight ma szállított súlyaihoz (`assets/ml/*.bin`, tipikusan néhány
   száz KB–néhány MB) mérve is beszédes.
3. A latency-cella `NEM MÉRT` — nincs mért szám, amire a javaslat
   hivatkozhatna, és becsülni tilos.

**Következmény a Chapter 14 §5.1 irányra:** a Klangio checkpoint nem köthető
be, tehát a joint onset+direction+chord irány folytatása a StrumSight
**saját** modellje (a következő kör, streaming joint onset + direction
prototípus), nem az átvétel. Ha a Klangio a jövőben kimondott licencet ad a
súlyra és/vagy az adatra, a döntés új ADR-rel újranyitható — a manifest mezői
és az őr (`audit_registry`) készen állnak, csak egy `approved` bejegyzés
hiányzik.

## 5. §7.1 — Falszifikációs cella

A licenc-őr teszt (`test/tooling/reference_model_licence_guard_test.dart`,
csoport B) minden felismert lokációban (`assets/`, `ml/`, `tool/`,
`test/fixtures/`, gyökér) bizonyítja a PIROS→ZÖLD párt egy **ideiglenes,
szintetikus git-repóban** (nem az ambiens fán, L118):

1. Tiszta fa (nincs referencia-eredetű artefaktum) → **ZÖLD**
   (`clean.isClean == true`).
2. Egy auditálatlan `.ckpt`/`.pt`/`.pth` fájl trackelése az adott lokáción
   (pl. `weights.ckpt` a gyökérben, `tool/cache/weights.pt`,
   `test/fixtures/model.pth`) → **PIROS**, és a lelet `path` mezője pontosan
   az elhelyezett fájlra mutat.
3. A fájl `git rm` eltávolítása (`_untrack`, a teszt maga hozza létre és
   törli, `addTearDown` a teljes temp-repóra) → **ZÖLD** újra.

Ugyanez a mintázat fut a dataset-jelre (`klangio-gst-mm-2025` néven ellátott
könyvtár, akárhol beágyazva) és fordítva: egy `audit_registry`-ben
`"status": "approved"` bejegyzéssel rendelkező, sha256-ra egyező fájl **ZÖLD**
marad — ez a menekülőút ma üresen áll, mert a §4 ítélete NO-GO.

## 6. A két mérés soha nem keveredik (ADR 0369 D4)

A §1 és §2 táblája szándékosan **különálló**: egyik sem hivatkozik a másik
korpusz-hash-ére, és egyikük sorai sem nevezik meg mindkét mérést egyszerre.
A `test/tooling/reference_model_licence_guard_test.dart` C csoportja ezt a
szerkezetet gépi cellaként is méri (külön fejléc + saját korpusz-hash mindkét
táblánál; egy összevont sor pirosra váltaná).
