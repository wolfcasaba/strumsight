# Recognition release guard — E14-R01

## Status

The shipped recognition path remains on the legacy DSP baseline. The recovery
program does not activate a replacement model or change user-visible Live
behavior in E14-R01. Its governing rule is **`UNKNOWN > CONFIDENTLY WRONG`**:
an unverified recognition result must not be presented as certain.

The measured baseline draws on two separate sources — a future evaluation
report must cite the correct one per metric, not a single blended corpus:
the 82-recording phone-guitar corpus documented in
[`real-audio-dsp-baseline.md`](real-audio-dsp-baseline.md) gives chord
accuracy **67.1%** and onset F1 at 50 ms **67.4%**. Direction accuracy
**80.7%** is a separate measurement — the live 3-class CRNN's held-out eval
fold on true-strum events (`docs/handoff-archive.md` round 175; see also
[ADR 0271](../adr/0271-recognition-recovery-program.md)) — and is not part of
the 82-recording corpus. Those measurements are the release comparison point,
not an activation approval for a new model.

## Activation contract

A new recognition model, a recognition shadow path, or a new Live recognition
stage is **blocked from activation** until all of the following versioned,
reviewable artefacts are present and mutually consistent:

| Required artefact | Required evidence | Activation is blocked when |
|---|---|---|
| Evaluation report | A reproducible report compares the candidate with the legacy DSP baseline, includes grouped evaluation results, records the measured command and states regressions. | The report is absent, cannot be reproduced, does not compare the baseline, or reports an unresolved regression. |
| Baseline manifest | `evaluation/recognition/baseline_manifest.json` records the corpus SHA-256, model SHA-256, app commit, configuration, and measurement command. This file is defined by E14-R02. | The manifest is absent, a required field is missing, or an evaluated input does not match it. |
| Candidate model manifest | A model manifest identifies the candidate model, export version, licence, and SHA-256 checksum. | The manifest is absent, its checksum is missing, or the checksum differs from the activated asset. |
| Corpus identity | The evaluation report and baseline manifest identify the same corpus hash and split/grouping definition used for the decision. | The corpus hash or split/grouping is absent or differs between artefacts. |
| Rollback recipe | A tested, documented rollback names the prior legacy-DSP configuration, the disabling action, the owner, and the verification step. | The recipe is absent, does not restore the prior configuration, or lacks a verification step. |

The checks above are conjunctive: satisfying one artefact never compensates for
another missing artefact. A later, separately approved CI/workflow change may
enforce these checks mechanically; E14-R01 only documents the contract and
does not modify `.github/**`.

## Rollout discipline

All three recovery feature flags remain `false` in production, lab, and
development until a separate decision accepts the complete activation package:

- `recognitionRecoveryEnabled`
- `recognitionShadowModeEnabled`
- `newLiveStageEnabled`

The legacy DSP remains the baseline until that decision. Neither a model asset,
a flag change, nor a UI claim may bypass the activation contract.

## Decision record requirements

The approval that enables any recovery flag must cite the exact evaluation
report, baseline manifest, candidate model manifest/checksum, corpus hash and
rollback recipe. It must also name the app commit and configuration evaluated.
If an artefact changes after approval, the activation package is invalidated
and must be reviewed again.
