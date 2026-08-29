# Performance budgets — the machine-readable benchmark harness (E12-R14, ADR 0474)

This document explains `docs/performance/baseline.json` and
`tool/compare_benchmarks.py`. It is the harness's usage note, not a new
measurement — every number in `baseline.json` is copied from an existing
`docs/baseline/**` or `docs/manual-testing/**` document, unchanged, with a
`source` field pointing back at it.

## Why a JSON baseline exists alongside the Markdown ones

`docs/baseline/**` and `docs/manual-testing/vision-performance-benchmark.md`
remain the source of truth and are **not rewritten** by this round. They are
prose, meant for a human reading one epic's story. `docs/performance/
baseline.json` is the same numbers in a shape `tool/compare_benchmarks.py`
can diff mechanically against a fresh run's output — it exists to answer
"did this build regress", not to replace the narrative documents.

## The four value classes (`kind`)

Reading the existing baseline documents surfaced a fact the harness has to
respect rather than flatten: the numbers in `docs/baseline/**` are not all
the same kind of claim.

| `kind` | What it means | Where the round's entries came from |
|---|---|---|
| `measured` | A real run's real output. | `docs/baseline/epic-06-analysis-performance.md:10-14` (2026-08-13, `flutter test --reporter expanded tool/audio_analysis_benchmark.dart`) — the only document on the tree that is an actual measurement. |
| `upperBound` | An assertion about a measurement, not an isolated number. | `docs/baseline/epic-04-performance.md:27-37` — every cell is `< N ms`; the document itself says the test's wall time includes more than the component under test. |
| `derivedContract` | A design boundary, not an observation. | `docs/baseline/epic-03-backing-drift-benchmark.md:16-28` and `docs/baseline/epic-03-pitch-observation-benchmark.md:11-19`. |
| `target` | A production goal and minimum threshold with no measurement behind it yet. | `docs/manual-testing/vision-performance-benchmark.md:37-41` — every "Mért átlag" / "Mért p95" cell in that table is `PENDING`; the `value` recorded here is the minimum-threshold column, not a measurement, and `sampleCount: 0` says so explicitly. |

**`tool/compare_benchmarks.py` only ever compares `measured` ↔ `measured`
pairs.** An `upperBound`, `derivedContract` or `target` record is present in
`baseline.json` for context and provenance, never for a pass/warn/fail
verdict — treating one as measured would fabricate a measurement that never
happened (ADR 0474 D3).

## Device metadata (`deviceId`)

The closed dictionary is the four devices from the Round 13 matrix
(`docs/testing/device-matrix.yaml`: `pixel_6a`, `pixel_7`,
`samsung_galaxy_a54`, `xiaomi_redmi_note_12`) plus `ci_host` for a
measurement taken on the machine running the test suite rather than on a
physical phone. Every record in this round's `baseline.json` uses
`ci_host`, because every source document behind it was produced by a
`flutter test` run on this box (or an equivalent CI runner), not a
device-lab session — no physical-device benchmark exists on the tree yet.
An unrecognised `deviceId` is a parse error in both `benchmark_record.dart`
and `compare_benchmarks.py`, never a silently-accepted new value.

`compare_benchmarks.py` keys its regression comparison on `(metric,
deviceId)`, not on the metric name alone (E12-R14 fix round, F1/F2) — a
measurement is only meaningful against another measurement taken on the
*same* device. One consequence: the five `vision_*` `target` records in
`baseline.json` all carry `deviceId: ci_host` because no physical-device FPS
measurement exists yet (they are `target`, not `measured`, so they are never
compared in the first place — ADR 0474 D3). If a future round adds a real
`measured` FPS record from, say, `pixel_6a`, it will NOT pair with the
`ci_host` targets even after that round promotes them: a `target`'s baseline
entry would need its own `deviceId` update (or a device-specific target
added) once a physical-device measurement exists. Do not invent a device
name to make an old target line up — add the real measurement with its real
`deviceId` instead, and update `baseline.json` accordingly in that round.

## `buildSha` provenance

Each group's `buildSha` is the actual commit that added its source
document (`git log --follow --diff-filter=A`), not an invented value:

| Source document | `buildSha` | Commit |
|---|---|---|
| `docs/baseline/epic-06-analysis-performance.md` | `d325d60` | E06-R28 (#255), 2026-08-13 |
| `docs/baseline/epic-04-performance.md` | `0cf6323` | E04-R24 (#160), 2026-08-06 |
| `docs/baseline/epic-03-backing-drift-benchmark.md` | `27d45d6` | E03-R18 (#119), 2026-08-04 |
| `docs/baseline/epic-03-pitch-observation-benchmark.md` | `4014f73` | E03-R20 (#121), 2026-08-04 |
| `docs/manual-testing/vision-performance-benchmark.md` | `cef864c` | E05-R01 (#162), 2026-08-06 |

`timestamp` is the date the source document itself records, at day
precision — none of the source documents record a finer-grained
measurement time.

## Regression threshold — the mirrored cell triple (ADR 0474 D6/D7)

Warn at **5.0%** regression, fail at **10.0%**, both boundaries **inclusive**
(`>=`, never `>`) and fixed in `tool/compare_benchmarks.py`, not a CLI
argument. Direction is per-metric and has no default: `lowerIsBetter`
regresses on increase, `higherIsBetter` regresses on decrease.

| Direction | Baseline | 4.9% regression → **pass** | 5.0% regression → **warn** | 10.0% regression → **fail** |
|---|---:|---:|---:|---:|
| `lowerIsBetter` (e.g. µs) | `200.0` | `209.8` | `210.0` | `220.0` |
| `higherIsBetter` (e.g. fps) | `30.0` | `28.53` | `28.5` | `27.0` |

An improvement — a `higherIsBetter` metric going up, or a `lowerIsBetter`
metric going down — is always `pass`, regardless of magnitude.

A metric that is `measured` in the baseline but absent from the candidate
report is `unknown`, not silently skipped, and forces a non-zero exit
(ADR 0474 D5): a report that is green because it did not measure something
is worse than a report that is red.

## Usage

```bash
python3 tool/compare_benchmarks.py --baseline docs/performance/baseline.json --candidate <candidate-record-file.json>
```

Both `--baseline` and `--candidate` are full benchmark-record documents
(`{"records": [...]}`) in the schema `tool/benchmarks/benchmark_record.dart`
defines. A fresh CI or device-lab run produces the candidate document; there
is no separate "release report" shape.

## What this round does not do

- It does not add a CI workflow — `.github/workflows/benchmark.yml` (SDD
  Ch12) is a separate, un-started decision; the CI-side `.github/**` is this
  round's forbidden zone.
- It does not retune, adjust, or "fix" any DSP/ML parameter — AGENTS.md §9
  forbids that in this round regardless of what a comparison finds.
- It does not rewrite `docs/baseline/**` or `docs/manual-testing/**` — those
  stay the human-readable source of truth; `baseline.json` only cites them.
