# ADR 0369 — Külső referencia-modell: pinelt reprodukció, HÁROM külön licenc-ítélet és fail-closed artefaktum-őr

- **Státusz:** elfogadva
- **Dátum:** 2026-09-05
- **Kör:** `E14-R17` (Chapter 14, Kör 17 — „Klangio ISMIR 2025 referencia
  reprodukció és licence audit")
- **Kapcsolódó:** [`0473`](0473-release-fixture-corpus-manifest.md) (fa-bejárás,
  tartalom-checksum, **fail-closed licenc**: „ismeretlen licenc = megállás, nem
  »unknown«"), [`0447`](0447-release-manifest-provenance-and-sbom.md) (release
  manifest, provenance, SBOM), [`0063`](0063-generated-ml-manifest-and-backend-ci.md)
  (generált ML asset manifest + checksum-gate a `flutter test`-en át),
  [`0509`](0509-grouped-recognition-evaluation-and-leakage-protection.md)
  (csoportosított kiértékelés, szivárgás-védelem),
  [L530](../LESSONS.md#l530) (a generált artefaktum a generáló gép abszolút
  útvonalát vitte magával, zöld gate mellett),
  [L546](../LESSONS.md#l546) (az implementer a falszifikációs cellát
  megfordította — a licenc-hiány NEM válhat „valid" értékké)

## Kontextus — mért tények

A pre-flight **hálózatról mérte** a hivatkozott publikációt és a hozzá tartozó
hivatalos repót (2026-09-05, `main @ 39680e1e`; forrás:
`docs/research/recognition-research-sources.md`, `docs/rag/chunks/015`).

**A publikáció.** S. Murgul, J. Schimper, M. Heizmann: *Joint Transcription of
Acoustic Guitar Strumming Directions and Chords*, ISMIR 2025
([arXiv 2508.07973](https://arxiv.org/abs/2508.07973)).

**A hivatalos repó.** `Klangio/guitar-strumming-transcription` (GitHub API,
`/repos/...`):

| Mért mező | Érték |
|---|---|
| Alapértelmezett ág | `main` |
| Pinelhető commit | `929e403f3256b055c1eea27064ae39f36905359e` (2025-09-21T14:31:50Z, „initial commit") |
| Repo-szintű `license.spdx_id` | `Apache-2.0` |
| Repó mérete | ~789 MB (`size = 789248` KB) |
| Utolsó push | 2025-09-21T14:49:58Z |

**A fa három, egymástól FÜGGETLEN artefaktum-osztálya** (`git/trees/<sha>?recursive=1`,
`truncated=false`, 358 bejegyzés):

1. **Kód** — `klangio/modules/strumming_crnn/` (9 `.py`: `model.py`, `lit.py`,
   `data.py`, `utilities.py`, `infer_utils.py`, `augmentation.py`, `config.py`,
   `constants.py`, `__init__.py`) + `scripts/` (3 `.ipynb` +
   `scripts/train_phone.py`) + `requirements.txt` + `pylintrc`.
2. **Checkpoint** — `checkpoints/wc/step=19000-f1=0.8225.ckpt`. A fában **134
   bájt**, mert **Git-LFS pointer** (`.gitattributes`: `*.ckpt filter=lfs`). A
   pointer mért tartalma:
   `oid sha256:80297850d7d2150093d5ae2bcb090466566ad24fa835a5c1e67f16ca38a3ea44`,
   `size 134344202` — a valódi súly tehát **134 344 202 bájt** (≈128 MiB).
3. **Adat** — `dataset/klangio-gst-mm-2025/`, **330 blob**, összesen
   **913 163 829 bájt** (≈871 MiB) a fában (nem LFS): `*_phone.wav`,
   `*_line.wav`, `*.csv` (mozgásadat), `*.strums` (annotáció).

**A licenc-nyilatkozat mért terjedelme.** A `LICENSE` a teljes Apache-2.0
szöveg. A `README.md` „License" szakasza szó szerint:

> Copyright © 2025 Klangio GmbH
> This **software** is licensed under the **Apache License, Version 2.0**.

Tehát a nyilatkozat **a szoftverre** szól. **A checkpointhoz és az
adathalmazhoz a repóban NINCS külön licenc-nyilatkozat** — sem a `README.md`
„Pretrained Checkpoint" / „Dataset" szakaszában, sem a `dataset/` vagy a
`checkpoints/` alatt. A README a `Citation` szakaszban idézési kötelezettséget
ír elő („If you use this code, data, or models in your research…"), ami
**kutatási** használatra utaló megfogalmazás, nem termék-engedély.

**A reprodukció mai alakja.** A repó `README.md`-je szerint a kiértékelés
`scripts/evaluate.ipynb` **notebook**, az inferencia `scripts/inference.ipynb`.
Egyparancsos futtatás nincs.

**A research környezet mért állapota ezen a boxon.** A `requirements.txt`
`torch`, `lightning`, `note-seq`, `torchlibrosa`, `librosa==0.10.1`,
`hydra-core`, `wandb` függőségeket ír elő. A boxon egyetlen ML-venv van,
`/home/ubuntu/tf-venv` — `tensorflow 2.21.0` + `keras 3.15.0`, **`torch` nincs
benne** (`pip list` mérve); a rendszer-Pythonban sincs (`ModuleNotFoundError:
No module named 'tensorflow'`, torch ugyanígy). A teljes reprodukció tehát a
PyTorch-lánc telepítését, a 134 MB-os LFS-checkpoint és a ~871 MB-os
adathalmaz letöltését igényli — egyik sem áll rendelkezésre ma.

## Döntés

**D1 — Három KÜLÖN licenc-ítélet, és a hiány nem „megengedő".** A manifest a
kódra, a checkpointra és az adathalmazra **külön-külön** kötelező mezőt tart
(`code`, `checkpoint`, `dataset`), és minden mező kötelezően hordoz `spdx`,
`source` és `evidence` (a nyilatkozat pontos helye) hármast. Egy hiányzó vagy
üres mező **típusos hiba**, nem alapértelmezés.

**NEM elfogadható gyengítés** (ADR 0473 D4 mintája, [L546](../LESSONS.md#l546)):
a repo-szintű `Apache-2.0` „lefelé öröklése" a súlyra és az adatra, vagy a
hiány `"unknown"` / `"n/a"` sztringgel való kitöltése. Az `"unknown"` **nem
érvényes licenc**: nem üres, tehát egy naiv „nem üres → rendben" ellenőrzés
átengedné — pontosan ezt a fordítást tiltja ez a pont.

**D2 — A mért ítélet: termék-felhasználásra NO-GO.**

| Artefaktum | Mért licenc | Ítélet |
|---|---|---|
| Kód (`klangio/modules/**`, `scripts/**`) | `Apache-2.0`, kimondva a `LICENSE`-ben és a README-ben („This **software**…") | megengedő — kutatási reprodukcióra használható |
| Checkpoint (`checkpoints/wc/step=19000-f1=0.8225.ckpt`) | **NEM NYILATKOZOTT** | **blokkoló** |
| Adathalmaz (`dataset/klangio-gst-mm-2025/**`) | **NEM NYILATKOZOTT** | **blokkoló** |

A kör §5.1-es szerződése szerint (a brief köti, ez az ADR megerősíti): ha a kód,
a checkpoint VAGY az adat licence tiltja — vagy **nem engedélyezi kimondottan** —
a termékfelhasználást, **semmilyen artefaktum nem kerül a repóba**, és az
eredmény **no-go**. „Csak kísérletnek betesszük" nem elfogadható. A kétség nem
engedély: a nyilatkozat hiánya a szerzői jog alapfeltevése szerint
**fenntartott jog**, nem szabad felhasználás.

**D3 — Nulla külső artefaktum a fában, a reprodukció a repón KÍVÜL fut.** A
reprodukciós script a klónt, az LFS-checkpointot és az adathalmazt egy
**repón kívüli** munkakönyvtárba tölti (kötelező CLI-argumentum vagy
környezeti változó), és soha nem ír a repó fájába. A manifest a `sha256`
checksummal azonosít, nem a bemásolt bájtokkal. Mért indok
([L530](../LESSONS.md#l530)): egy „generált" artefaktum 155 sorban vitte
magával a generáló gép abszolút `/home/ubuntu/...` útvonalát, teljesen zöld
gate mellett — a repóba kerülő külső bájt ugyanez a hibaosztály, csak jogi
következménnyel.

**D4 — A két mérés soha nem keveredik.** A hivatalos fixture eredménye és a
StrumSight held-out eredménye **külön tábla**, mindkettő **külön korpusz-hash**
mezővel. Egyetlen összevont sor, közös átlag vagy „a paper szerint …, nálunk …"
egybefésült cella tiltott — ez a szerződés akkor is köt, ha az egyik tábla
minden sora `NEM MÉRT`.

**D5 — Fail-closed gépi őr, ami a FÁT járja.** A licenc-őr teszt
(`test/tooling/reference_model_licence_guard_test.dart`) nem a manifest
listájából indul, hanem a repó fájából (ADR 0473 D1 mintája): minden
referencia-eredetűnek felismert artefaktumhoz `approved` audit-bejegyzést
követel, és bejegyzés nélkül **PIROS**. Az őr **nem korlátozódhat** az
`assets/` alfára — egy `ml/`, `tool/`, `test/fixtures/` vagy gyökér alatt
elhelyezett külső súly ugyanúgy találat kell legyen.

**D6 — Ami nem futott, az `NEM MÉRT` — becsülni tilos.** A report minden nem
futtatott számot szó szerint `NEM MÉRT` értékkel jelöl, mellé írja a **hiány
mért okát** és a **reprodukáló parancsot**. A go/no-go javaslat kizárólag
MÉRT tényekre hivatkozhat; ebben a körben ezek: a fenti három licenc-státusz és
a checkpoint mért mérete (**134 344 202 bájt**), ami a mobil memória-költség
**alsó korlátja** — a StrumSight ma szállított súlyaihoz mérve is beszédes.
Becsült latency- vagy pontosság-szám a reportban **tiltott**.

## Következmények

- A kör **infrastruktúrát és jogi ítéletet** szállít, nem teljesítmény-számot:
  pinelt manifest + egyparancsos reprodukciós script + README + fail-closed
  licenc-őr + a két mérést szétválasztó report. A D2 ítélet önmagában
  eldönti a Chapter 14 §5.1 termék-kérdését: **a Klangio checkpoint nem
  köthető be**, tehát az irány folytatása a **saját** joint modell (Kör 18,
  streaming joint onset + direction prototype), nem az átvétel.
- A `lib/**` és az `assets/**` érintetlen: a körnek nincs futásidejű hatása,
  regressziós kockázata nulla.
- Ha a Klangio később kimondott licencet ad a súlyra és/vagy az adatra, a
  döntés újranyitható: a manifest mezői és az őr készen állnak, csak az
  `approved` audit-bejegyzés hiányzik — új ADR írja felül ezt a D2-t.
- Az őr a jövőben MINDEN külső referencia-artefaktumra köt, nem csak erre az
  egyre: a rés, amit bezár, „auditálatlan külső súly némán a fába kerül".
