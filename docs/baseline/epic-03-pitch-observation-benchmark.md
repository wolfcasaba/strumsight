# Epic 03 pitch-observation benchmark

The executable source of this table is
`tool/benchmarks/song_trainer_pitch_benchmark.dart`, which reads
`test/fixtures/audio/song_trainer/pitch_fixture_manifest.json`.

## Derived boundaries

| Boundary | Inclusive value | Fixture rows |
|---|---:|---|
| Exact pitch error | 12 cents | `clean-a2` |
| Near pitch error | 35 cents | `high-e4`, `vibrato` |
| Off-pitch error | 70 cents | `chromatic-riff` |
| Correct onset window | -80 ms to +80 ms | `early-below-window`, `onset-window-lower-boundary`, `late-above-window` |
| Target association window | 150 ms | `early-below-window` |
| Duration coverage | 0.60 | `short-note`, `coverage-boundary` |
| Coverage observation hold | 60 ms | `coverage-boundary` |
| Supported observation latency | 100 ms | `clean-e2`, `latency-above-maximum` |
| RMS gate | 0.014 | `transition-noise`, `speech`, `silence` |
| Clarity gate | 0.85 | `transition-noise`, `speech` |
| Stability window | 2 observations | `vibrato`, `transition-noise` |

## Scope of this evidence

The manifest is a deterministic observation replay: every row pins a fixture
identifier, raw observation timestamp, latency-compensated timestamp and
expected grade. It includes the SDD §22.9 categories, but does not contain raw
audio and does not report device latency. A real Android-device microphone and
guitar measurement remains required before a production latency claim.
