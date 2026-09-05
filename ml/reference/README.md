# Reference-model reproduction — Klangio ISMIR 2025 (E14-R17, ADR 0369)

Pinned reproduction + licence audit for the published joint onset/strumming
reference model StrumSight's Chapter 14 §5.1 wants to compare against. This
folder ships **infrastructure and a legal judgment**, not a performance
number (§0.0 D / ADR 0369 D6) — see `docs/eval/reference-model-audit.md` for
the report and the go/no-go.

## What this is

| | |
|---|---|
| Publication | S. Murgul, J. Schimper, M. Heizmann — *Joint Transcription of Acoustic Guitar Strumming Directions and Chords*, ISMIR 2025 ([arXiv:2508.07973](https://arxiv.org/abs/2508.07973)) |
| Repository | `Klangio/guitar-strumming-transcription` |
| Pinned commit | `929e403f3256b055c1eea27064ae39f36905359e` (2025-09-21T14:31:50Z, the repo's only commit) |
| Full details | `ml/reference/reference_manifest.json` |

## Environment (measured 2026-09-05, not installed on this box)

The upstream `requirements.txt` needs:

```
torch
lightning
note-seq
torchlibrosa
librosa==0.10.1
hydra-core
wandb
```

This box's only ML virtualenv (`/home/ubuntu/tf-venv`) carries TensorFlow
2.21.0 / Keras 3.15.0 for StrumSight's own TFLite training path
(`ml/train.py`) — **not** PyTorch. Neither `torch` nor any of the above is
importable from the system Python either. Confirm with:

```bash
python3 -c "import torch"   # ModuleNotFoundError on this box
```

## Why it didn't run today

The checkpoint and dataset are **measurably reachable** (the checkpoint is a
public Git-LFS object, the dataset ships as ordinary git blobs in the same
repo) — the blocker is purely the missing PyTorch/Lightning runtime, not
network or licence access. Per the round's pre-flight revision
(`docs/rounds/e14-r17-reference-model-repro-and-licence-audit.md` §0.0 C),
that is **not** a `blocked` outcome: the licence audit is conclusive without
running anything (see the report), so this round ships the reproduction
tooling and the audit, and marks every unrun number `NEM MÉRT` rather than
estimating one.

## Running it

```bash
# Network-free integrity check — the manifest's schema, pinned commit shape
# and checksum shapes. This is what actually runs on this box today:
python3 ml/reference/run_reference_eval.py \
  --manifest ml/reference/reference_manifest.json --verify-only

# Full reproduction — clones the pinned commit, verifies the checkpoint's
# sha256 against the manifest, and would run both evaluations. --workdir is
# mandatory and MUST be outside this repository (ADR 0369 D3: this script
# never writes a third-party byte into the repo tree); a workdir inside the
# repo is a typed error, not a warning.
python3 ml/reference/run_reference_eval.py \
  --manifest ml/reference/reference_manifest.json \
  --workdir /tmp/klangio-repro
```

On this box the full-run command fails fast with a typed
`MissingDependencyError` naming every missing package and the exact `pip
install` line, before touching the network or the filesystem outside
`--workdir`. Once a PyTorch-capable box installs the dependencies above, the
same command clones the pinned commit, LFS-pulls and checksum-verifies the
checkpoint, then runs two **independent** evaluations — the official fixture
and the StrumSight held-out split (E14-R08 grouped harness) — each reported
with its own corpus hash, never merged into one table (ADR 0369 D4).

`run_official_fixture_eval` and `run_strumsight_holdout_eval` currently raise
`NotImplementedError`: the upstream evaluation entry point is a notebook
(`scripts/evaluate.ipynb`) whose cell-output contract was not read during the
pre-flight (no PyTorch runtime available to open it against). Wiring that
extraction is follow-up work for whichever round first has a PyTorch-capable
box — see the function docstrings in `run_reference_eval.py`.

## Licence audit — the actual deliverable of this round

Three **independent** verdicts (code / checkpoint / dataset), each in its own
manifest block with `spdx` + `source` + `evidence` + `verdict`:

| Artifact | Licence | Verdict |
|---|---|---|
| Code (`klangio/modules/strumming_crnn/`, `scripts/`) | `Apache-2.0` | permissive for research reproduction |
| Checkpoint (`checkpoints/wc/step=19000-f1=0.8225.ckpt`) | **not declared** | **blocking** |
| Dataset (`dataset/klangio-gst-mm-2025/`) | **not declared** | **blocking** |

The repo-level Apache-2.0 grant is scoped by the README to "software" only —
it does not inherit downward onto the checkpoint or the dataset. An
undeclared licence is a reserved right, never a permissive default (ADR 0369
D1/D2). **Result: NO-GO for product use** — no artifact from this
repository enters `assets/` or `lib/**`. Full detail:
`docs/eval/reference-model-audit.md`.

The fail-closed guard for this rule is
`test/tooling/reference_model_licence_guard_test.dart` — it walks the
repository's tracked files (not the manifest's own list) for anything shaped
like a reference-model checkpoint or dataset, and fails red unless the
manifest's `audit_registry` names it `approved`. That registry is empty
today, by design: the D2 verdict is NO-GO, so nothing is approved.
