# Vision rollout and rollback runbook

## Preconditions

All Vision flags remain `false` in `FeatureFlags.forEnvironment`; E05-R30 does
not authorize a flag flip. Before any rollout stage, obtain a separate product
decision, a consented fixture corpus, the relevant device-matrix evidence, and
an exact-SHA green CI run. Never upload raw frames, video, or landmark streams.

The false-negative-cue evidence is evaluated locally with:

```bash
python3 ml/vision/evaluate_vision_metrics.py --input /path/to/fixture-summaries.jsonl
```

The inclusive cap is 1% (`0.01`); the benchmark target remains zero. `NO_DATA`
or a rate above the cap is `experimental`, not a reason to relax the cap.

## Rollout ladder

| Stage | Capability | Required evidence | Stop condition |
|---|---|---|---|
| Internal | setup and quality only | consent + representative device rows | permission/lifecycle/privacy failure |
| Lab | hand/pose overlay, explicit consent | model integrity + fixture evaluation + Lab review | false cue or raw-data handling concern |
| Opt-in beta | session summary | all relevant quality/capability gates | rate over cap, thermal or audio regression |
| Limited production | selected supported metrics | multi-device, handedness, lighting and guitar evidence | any metric drops to experimental |
| GA | only separately approved metrics | completed HORIZON acceptance | any unmet release minimum |

Negative feedback is never enabled in shadow mode. In shadow mode, collect only
consented aggregate metrics and keep audio scoring unchanged.

## Rollback

1. Turn the affected Vision flag OFF; keep audio-only flows available.
2. Stop new Vision sessions and release camera ownership through the existing
   lifecycle path; do not retain frames for diagnosis.
3. Revert to the immediately preceding checksummed model asset/manifest entry.
4. Mark the affected metric `experimental`, preserve only aggregate incident
   evidence, and add the failed device row to the manual matrix.
5. Do not re-enable until the same fixture and device evidence passes again.

The current release state is already step 1: all eleven Vision flags are OFF.

## Governance boundary

`test/tooling/vision_model_integrity_test.dart` is the local test-side gate.
Adding the corresponding workflow-side model gate belongs to a separately
authorized governance round because `.github/` and `tool/ci/` are out of this
round's scope.
