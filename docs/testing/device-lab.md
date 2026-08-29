# Device lab — manual round + machine-readable registry (E12-R13)

- **Kör:** E12-R13 (Chapter 12, Kör 13)
- **Brief:** [`docs/rounds/e12-r13-device-matrix-and-device-lab.md`](../rounds/e12-r13-device-matrix-and-device-lab.md)
- **Machine-readable registry:** [`docs/testing/device-matrix.yaml`](device-matrix.yaml)

## 1. What this is

Six independent manual test documents already live in `docs/manual-testing/`
(analysis-eval-matrix.md, gov-05-shipping-device-run.md,
practice-engine-device-matrix.md, vision-camera-spike-runbook.md,
vision-device-matrix.md, vision-performance-benchmark.md), each with its own
form and none of them machine-readable. This round adds one thing on top,
without touching any of the six:

- `device-matrix.yaml` — which devices exist, which are release-blocking,
  which capability each one covers, and which of the mandatory per-device
  measurements it must run.
- `tool/device_report.py` — reads that registry plus a manual-run results
  file and reports/checks coverage.

This document is the manual round's operating manual: how to run a device
round, what to record where, and — just as important — what this round
deliberately leaves out and why.

## 2. Running a manual device round

1. Pick a device from `device-matrix.yaml`'s `devices:` list.
2. Install the CI-built release APK (never a debug build — the SDD Ch12
   §18.1 methodology and `vision-performance-benchmark.md` §1 both require
   this).
3. Work through the device's `required_suite` list, one measurement at a
   time. Each measurement's procedure and PASS/PARTIAL/FAIL wording already
   exists in the corresponding `docs/manual-testing/` document (§5 below maps
   suite ids to documents) — this file does not duplicate those procedures.
4. Record every result in a **separate** results file (not committed by this
   round — it is produced by the manual round itself), in the shape
   `tool/device_report.py --results` reads:

   ```yaml
   runs:
     pixel_6a:
       install_and_update: pass
       cold_start: pending
       # ... one line per required_suite item
   ```

   A `pending` result is a valid, honest state — "recorded as not yet run"
   — not a placeholder (§4). What is NOT valid is silence: an item with no
   entry at all is a missing mandatory run, and `device_report.py --check`
   fails closed on it (§6).
5. Run `python3 tool/device_report.py --matrix docs/testing/device-matrix.yaml
   --results <your results file> --check` before calling the round done —
   it names every `required_suite` item of every `release_blocking: true`
   device that still has no entry.
6. Run `--report` for a human-readable summary of coverage across every
   device and capability.

## 3. `device-matrix.yaml`'s restricted YAML subset (R3)

`package:yaml` is a **transitive-only** dependency on this tree
(`pubspec.lock:1261`), and `pubspec.yaml` is outside this round's
allowed-files list — so it cannot become a direct dependency here. The gate
(`test/tooling/device_matrix_test.dart`) therefore reads `device-matrix.yaml`
with its own small, indentation-exact parser, the same choice
`test/tooling/repository_policy_test.dart` (ADR 0444 D3) and
`test/tooling/release_manifest_test.dart` (ADR 0447 D5) make for their own
restricted-subset files. **Any edit to `device-matrix.yaml` must stay inside
this grammar**, or the gate turns red with a `FormatException` naming the
exact line:

- top-level scalar keys: `schema_version: <int>`;
- top-level 2-space-indented block lists: `devices:` and `capabilities:`,
  each empty-valued, each element starting `  - id: <value>`;
- inside a `devices:`/`capabilities:` element (exactly 4-space indent): flat
  `key: value` pairs only — no further nesting;
- an inline list on one line: `key: [a, b, c]` (including the empty case
  `key: []`) — used for `required_suite`, capability `devices`, and the
  top-level `required_suite_catalog`;
- `#` line comments and blank lines anywhere.

No anchors/aliases, no multi-line scalars, no flow maps, no tab
indentation. A field or document shape needing any of these is not a parser
gap to route around — it needs staying inside this subset, or a future round
has to widen the parser (and its own tests) deliberately.

## 4. Result fields vs. identifier fields — `pending` is not a placeholder

Two different kinds of "unfilled" exist in this schema, and they are NOT
interchangeable:

- **Identifier/provenance fields** (`id`, `name`, `os`, `api_level`,
  `ram_gb`, `abi`, `soc`, `release_blocking`, `provenance`) describe a real,
  measured device. A placeholder here — `unknown`, `n/a`, `tbd`, `?`, an
  empty value, or even the literal `pending` — is **always** a defect: it is
  the [E12-R12 measured lesson](../LESSONS.md#l546) where an "unknown"
  licence placeholder slipped through a checker that only looked for empty
  strings. `test/tooling/device_matrix_test.dart`'s A1 group walks this
  exact placeholder list against every one of the nine fields.
- **Result fields** (`camera_result`, `audio_result`, `vision_tier`, and
  every entry a `--results` file records for a `required_suite` item)
  describe a measurement outcome, and `pending` is the honest, valid state
  for "recorded, not yet run" — every one of the six `docs/manual-testing/`
  documents is 100% `PENDING` today (§2, no fabricated number replaces a
  real device run). What `device_report.py --check` rejects is not
  `pending` — it is a mandatory run with **no entry at all**.

## 5. Suite-id → document mapping

Every `required_suite` id in `device-matrix.yaml` traces to SDD Ch12 §18.2
(`docs/sdd/12-release-roadmap-final-integration.md:1091-1105`), and its
procedure lives in whichever `docs/manual-testing/` document already covers
that surface:

| `required_suite` id | Procedure lives in |
|---|---|
| `install_and_update`, `cold_start`, `background_resume`, `battery_saver`, `airplane_mode`, `low_storage`, `text_scale_200`, `screen_reader_path` | [`gov-05-shipping-device-run.md`](../manual-testing/gov-05-shipping-device-run.md) |
| `live_start_latency`, `mic_release`, `practice_soak_20min` | [`practice-engine-device-matrix.md`](../manual-testing/practice-engine-device-matrix.md), [`analysis-eval-matrix.md`](../manual-testing/analysis-eval-matrix.md) |
| `analyze_memory_peak` | [`analysis-eval-matrix.md`](../manual-testing/analysis-eval-matrix.md) (EVAL-07/EVAL-27) |
| `camera_preview_and_thermal` | [`vision-device-matrix.md`](../manual-testing/vision-device-matrix.md), [`vision-performance-benchmark.md`](../manual-testing/vision-performance-benchmark.md), [`vision-camera-spike-runbook.md`](../manual-testing/vision-camera-spike-runbook.md) |

`local_ai_load_ttft` is in the SDD §18.2 dictionary ("ha támogatott" — "if
supported") but is **not** in any device's `required_suite` today: Offline
AI is `not_ga_scope` (R6 — Epic 10 stands `hold`,
`docs/execution/pipeline-queue.tsv:634-638`, no device tier is measured
yet). Adding it to a device's `required_suite` is the job of the round that
lands the Epic 10 device-tier measurement, not this one.

## 6. Devices — measured, not invented

`device-matrix.yaml` carries exactly the four devices measured in
`vision-device-matrix.md`:160-163 (cross-checked against
`vision-performance-benchmark.md`:117-120 for RAM):

| Device | Role | Source |
|---|---|---|
| Pixel 6a | `release_blocking: true` — the measured, named primary test device (R5) | `vision-device-matrix.md:160` |
| Pixel 7 | `release_blocking: true` | `vision-device-matrix.md:161` |
| Samsung Galaxy A54 | `release_blocking: false` (recommended) | `vision-device-matrix.md:162` |
| Xiaomi Redmi Note 12 | `release_blocking: false` (recommended) | `vision-device-matrix.md:163` |

**Deliberately excluded:** `vision-device-matrix.md`:164-165 also lists a
Samsung Galaxy S23 and a Pixel 4a as "Opcionális", but neither row has a
measured RAM/SoC entry in `vision-performance-benchmark.md` (which only
measures the four devices above). Inventing a plausible RAM/SoC value for
either would be exactly the "látszat-lefedettség" (fake coverage) risk this
round's brief calls out — a later round can add them once a real
measurement exists.

**ABI.** All four devices carry `abi: arm64-v8a`. This is a measured
derivation, not an assumption: `android/app/build.gradle.kts:102` sets only
`ndkVersion = flutter.ndkVersion` — there is no `abiFilters` restriction
anywhere in that file — and all four SoCs above (Google Tensor / Tensor G2,
Exynos 1380, Snapdragon 685) are 64-bit ARM parts.

## 7. Capabilities — GA scope is a closed list (R6)

`device-matrix.yaml`'s `capabilities:` block carries exactly fourteen
entries, matching SDD Ch12 §5.1/§5.4 (GA) and §5.2 (preview):

- **`ga_scope: true`, eleven entries** — `onboarding`, `live_and_tuner`,
  `practice_engine`, `song_trainer_local`, `audio_analysis_core`,
  `progress_goals_streak`, `storage_migration`, `offline_operation`,
  `localization_en_hu`, `accessibility_minimum`,
  `session_lifecycle_stability`. Each one is covered by all four devices
  above, so each has at least one `release_blocking: true` device
  (§5.1 of the round brief: this is a hard invariant — a capability may
  never be moved to `ga_scope: false` just to route around a coverage gap).
- **`ga_scope: false`, three entries** — `computer_vision` (Ch12 §5.2:
  "Computer Vision opt-in preview"), `ai_tutor` (Ch12 §5.2, preview),
  `offline_ai` (Ch12 §5.2 + the Epic 10 `hold` status, §5 above). None of
  the three missing from a device's coverage makes that device globally
  unsupported (Ch12 §18.3, §4 above) — `offline_ai` currently covers zero
  devices, which is correct: no device tier is measured for it yet, and
  that absence must never read as "device N cannot run StrumSight".

## 8. What this round did NOT run

- No real device executed any `required_suite` item — every
  `docs/manual-testing/` row is still `PENDING` (§2). This round ships the
  registry and the checker, not a measurement.
- `tool/device_report.py --check` against the real matrix, with no
  `--results` file, therefore exits non-zero today (§10 of the round brief
  shows the literal output) — that is the correct, honest state, not a bug.
