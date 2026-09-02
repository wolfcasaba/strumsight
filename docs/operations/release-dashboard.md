# Release dashboard — input schema

- **Status:** schema only — this round does not build the dashboard UI or
  wire a data source into it (E12-R19, ADR 0484 §0.1). It defines the shape
  any future dashboard implementation (or a manual release-readiness review)
  must read.
- **Threshold source of truth:** `docs/operations/slo.yaml`. This document
  does **not** repeat any objective/threshold — doing so would create two
  places D3's "`unknown` is never green" rule would have to be kept in sync
  (ADR 0484, "Következmények").

## Metric row

One row per `(slo_id, cohort)` pair, refreshed per window (the window is
declared per-SLO in `slo.yaml`):

| Field | Type | Meaning |
|---|---|---|
| `slo_id` | string | Must match a `slos[].id` in `docs/operations/slo.yaml` exactly. |
| `cohort` | cohort filter (below) | Which slice of sessions/builds this row measures. |
| `verdict` | one of `slo.yaml`'s `verdict_values` | `success`, `degraded`, `breach` or `unknown`. |
| `measured_value` | string or absent | The measured number, formatted per the SLO's `objective` unit. Absent when `verdict = unknown`. |
| `sample_size` | integer or absent | How many sessions/builds/clips fed the measurement. Absent when `verdict = unknown`. |
| `window_start` / `window_end` | timestamp | The measurement window's bounds. |

## Cohort filter

A row is scoped by exactly one cohort dimension at a time — the dashboard
does not silently intersect dimensions, since an intersection with a small
sample would misleadingly look as confident as the unfiltered row:

| Dimension | Example values |
|---|---|
| `all` | The unfiltered fleet. |
| `platform` | `android`, `ios`. |
| `app_version` | A `pubspec.yaml` version string. |
| `build_mode` | `debug`, `profile`, `release`. |

## `unknown` handling (ADR 0484 D3 — the rule this round ports from ADR 0474 D5)

- A missing measurement is reported as its own row with `verdict: unknown`,
  `measured_value` and `sample_size` absent — it is never dropped from the
  summary, and it is never coerced into `success`, `degraded` or `breach`.
- `unknown` is a **blocking** verdict (`slo.yaml`'s `blocking_verdicts`):
  a release with any `required: true` SLO in `unknown` state is not
  release-ready, on equal footing with a `breach`.
- Every SLO declared in `slo.yaml` is `required: true` — the release
  aggregate must produce exactly one row per declared SLO (per cohort in
  scope for that release), never fewer. A dashboard implementation that
  simply omits an SLO it has no data for is the exact failure mode this rule
  exists to catch (measured previously at [L549](../LESSONS.md#l549): a
  metric's mere *presence* was checked, never its *reported* verdict).

## Release-readiness roll-up

A release is ready only if every row for the release's scope has
`verdict in success_verdicts` (today: `verdict == success`). Any row with
`verdict in blocking_verdicts` (`degraded`, `breach`, or `unknown`) blocks
the release — the roll-up has no partial-credit or majority-vote path.
