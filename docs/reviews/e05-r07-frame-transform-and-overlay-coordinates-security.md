# E05-R07 — Security & Privacy Review

Brief: `docs/rounds/e05-r07-frame-transform-and-overlay-coordinates.md`
Branch: `codex/e05-r07-frame-transform-and-overlay-coordinates` @ `089953e`
Base: `origin/main` @ `b6408f0`
Reviewer: security-reviewer agent (read-only) · Dátum: 2026-08-06
Trigger: brief `ai-router` block declares `risk = "high"` → dedicated security review
mechanically required (independent of the diff's apparent surface).
Method: isolated clone (`/tmp/security-review-e05r07`), import/danger-grep surface
analysis, and a reproduction harness exercising the real source under both
asserts-on (debug/test) and asserts-off (release/AOT) semantics.

**Verdikt: PASS** — 0 CRITICAL, 0 BLOCKER. 1 MAJOR carried forward (not a block on
this round — see reasoning below), 1 MINOR/NOTE, 2 NOTE.

## Severity table

| # | Severity | File:line | One-line |
|---|---|---|---|
| 1 | MAJOR (carry-forward, not blocking R07) | `camera_coordinate_space.dart:75-76,128-129,144-145,158-161,189-190,224-225`; `camera_transform.dart:46-49,154-165` | Range/positivity/finiteness validation is `assert`-based → compiled out of the shipped release APK; invalid inputs (out-of-range, zero/negative size, NaN/Infinity) survive silently and propagate Infinity/NaN coordinates instead of throwing. |
| 2 | MINOR/NOTE | `camera_transform.dart:15-24,190-201` | Public `.affine` raw-matrix factory + inferred `From`/`To` lets a caller build a semantically nonsensical space-pair transform that still type-checks — nominal typing is necessary but not sufficient. |
| 3 | NOTE | `camera_transform.dart:65-80,100-107` | Inconsistent failure contract: some invalid inputs throw (`inverse()` singular-determinant, `sensorToUpright` crop-bounds), others silently yield NaN/Infinity. Caller-contract concern for a future per-frame consumer; no caller exists yet. |
| 4 | NOTE | brief §10 | Local `round-gate.sh` did not go green locally (out-of-scope missing generated l10n) — environment artifact, already resolved by the orchestrator; merge rests on CI per the round's own §11. |

## MAJOR-1 — why PASS despite a MAJOR-labelled finding

Independently reproduced (both assert modes, real source, not simulated):

```
asserts ON:  [AssertionError] NormalizedPoint(2.0, -1.0) out of range
asserts ON:  [AssertionError] SensorSize(width:0,height:3)
asserts OFF: [NO-THROW] NormalizedPoint(2.0, -1.0) -> constructed x=2.0, y=-1.0
asserts OFF: [NO-THROW] uprightToNormalized zero-width -> apply -> x=Infinity
asserts OFF: [NO-THROW] PreviewRect.contains(PreviewPoint(NaN)) -> false (silently "outside")
```

Not blocking **this round** because: (a) the layer has **zero consumers** in `lib/`
today — verified by grep, nothing imports these three files outside their own
tests — so there is no live path from platform metadata to any leak/persistence;
(b) the brief's own §5 bound decisions do not mandate release-surviving input
validation; (c) it matches the **existing house convention** (`CameraFrame`/
`CameraTimestamp` from E05-R03/R06 validate the same `assert`-only way). It becomes
load-bearing the moment this layer is wired to real camera metadata or any
capture/redaction boundary (ADR 0183) — **carried forward as a mandatory
precondition on R13 (hand landmark), R15 (guitar-coordinate homography), and R24
(overlay widget)**, whichever wires this layer first: enforce non-finite/
out-of-range rejection that survives release builds, plus asserts-off tests.

MINOR/NOTE-2 and NOTE-3 are the same character (real, well-reasoned, but about a
not-yet-existing caller) — carried forward alongside MAJOR-1 to the same future
rounds, not fixed here.

## What was verified clean

- Scope: exactly the 7 declared files, all within `allowed_paths`.
- No dependency/asset/supply-chain change (`pubspec.*` untouched).
- No network/storage/permission/secret/auth/AI-provider surface — the three lib
  files' only imports are `dart:math` + local siblings; danger-grep
  (`dart:io|ffi|http|dio|socket|MethodChannel|SharedPreferences|SecureStorage|
  supabase|Platform.|File(|permission|token|secret|apikey|firebase|sentry|log(|
  print(`) returns empty.
- No secrets in the diff (fixtures are geometric constants).
- Thrown error messages leak no secrets/PII/frame data.
- None of the three files import `camera_frame.dart` (the byte-carrying frame
  type) — the transform layer is pure geometry and structurally cannot touch raw
  sensor bytes, supporting ADR 0178/0183.
- Brief §5.5 honored: no `dynamic`, no `dart:ui`, no `Offset`.

## Recommendation

Merge is **not blocked** by this security review. Carry MAJOR-1 and MINOR/NOTE-2
forward as explicit, tracked preconditions on the first round wiring this layer to
real camera metadata or any capture/redaction/persistence path (R13/R15/R24) — this
review's findings should be linked from that round's brief. Merge on exact-SHA green
CI.
