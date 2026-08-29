# ADR 0471 — Screen reachability is MEASURED, and retirement is a proposal, not an execution

- **Status:** Accepted
- **Date:** 2026-08-28
- **Round:** `E15-R03` (Chapter 15 — UI activation and completion, round 3)
- **Supersedes:** nothing. **Superseded by:** nothing.
- **Related:** [ADR 0065](0065-practice-engine-v2-parallel-rollout.md) (V2 engines run
  BESIDE the legacy engine behind availability flags),
  [ADR 0466](0466-app-runtime-theme-is-the-design-system-theme.md),
  [ADR 0467](0467-adaptive-shell-is-the-non-production-default.md),
  [L449](../LESSONS.md#l449), [L409](../LESSONS.md#l409),
  [L190](../LESSONS.md#l190) / [L193](../LESSONS.md#l193) (barrel `public.dart`
  symbol gap), [L20](../LESSONS.md#l20).

## Context

Chapter 15 has to migrate the remaining legacy screens to the design system.
The MEASURED baseline on `main @ fc880063` is:

```bash
find lib/features -name '*_screen.dart' | wc -l                  # 96
for f in $(find lib/features -name '*_screen.dart' | sort); do
  grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"
done                                                              # 43 migrated / 53 legacy
```

Migrating 53 screens is expensive, and a measurable part of the legacy set is a
**superseded parallel layer** — `library/` ↔ `library_v2/`, `songs/` ↔
`song_trainer/`, `progress/` ↔ `progress_v2/`, `analyze/` ↔ `audio_analysis/`.
Migrating a screen the user can never open is pure waste. But the inverse
inference is exactly as wrong, and we have measured it twice:

- **L449** — `StatefulShellRoute.indexedStack` keeps visited branches ALIVE.
  "The router does not name it" is not proof of death, and "it is off-screen"
  is not proof of being disposed.
- **L409** — an E08-R30 brief assumed six existing gamification screens were
  merely "not yet routed"; the pre-flight `grep` for their CONSTRUCTOR calls
  returned zero outside their own files. Screen existence and screen
  instantiation are different measurements.
- **L190/L193** — a feature's `public.dart` barrel re-exports screens. A
  reachability checker that matches only IMPORT PATHS is blind through the
  barrel. Measured on this round's own baseline: `lib/app/routing/app_router.dart`
  imports 46 screen files directly but ALSO imports 3 feature barrels
  (`vision/public.dart` among them), and `vision/public.dart` re-exports three
  screens. A basename-only checker reports those three as unreachable — a false
  positive that, acted on, would delete a live user path.

So Chapter 15 needs a machine, repeatable answer to "which screens can the user
actually get to", produced BEFORE the migration rounds spend their budget.

## Decision

### D1 — Reachability is measured by a committed tool, not asserted in prose

`tool/check_screen_reachability.dart` renders, for every one of the 96
`*_screen.dart` sources under `lib/features/`, a verdict with the SOURCE
LOCATION that produced it. The tool is a library class over a repository
`Directory` (the `tool/ui_inventory.dart` shape) plus a thin `main()` with
`--format table|json`, so `test/tooling/screen_reachability_test.dart` can pin
its cells without shelling out.

### D2 — A screen is reachable if EITHER the router or another source names it

The checker measures both channels:

1. **Declarative** — the screen is named by `lib/app/routing/**` (`app_router.dart`,
   `adaptive_shell_routes.dart`, `route_guards.dart`).
2. **Imperative** — the screen's class is constructed anywhere else in `lib/`
   (`Navigator.push`, `context.go` destination builders, `showModalBottomSheet`
   / `showDialog` builders, or any other construction site).

**Not an acceptable weakening:** concluding "the router does not reference it,
therefore it is dead" (L449's failure class).

### D3 — Matching is by CLASS NAME, not by import path

Because the router reaches three features through their `public.dart` barrels
(measured above), path-based matching under-reports reachability. The checker
resolves the screen's declared `class …Screen` and searches for that symbol.
Import-path matching MAY be reported as a secondary signal, but it never alone
decides a screen is unreachable.

**Not an acceptable weakening:** a checker whose only evidence is
`basename(path)` appearing in a router file.

### D4 — Flag-gated is a REPORTED dimension, not silently "reachable"

Routes exist behind runtime feature flags (measured: `app_router.dart:561`
registers the Vision setup route only under `visionEnabled &&
visionSetupEnabled`). A flag-gated route is reachable code with a closed door.
The plan records the gate rather than pretending either that the screen is live
or that it is dead.

### D5 — Retirement is a PROPOSAL; this round deletes nothing

`docs/ui/retirement-plan.md` is a decision table (`migrate` / `retire` /
`keep`), not an execution. Removing a screen or a route destroys a user path
and is its own reviewed round. This round's `allowed_paths` therefore contains
no `lib/**` file at all.

**Not an acceptable weakening:** deleting anything on an "it is dead anyway"
basis.

### D6 — Every REACHABLE legacy screen gets a named owner round

The plan may not leave a reachable-but-unmigrated screen ownerless. Each such
screen carries a named E15 round (`E15-R04` … `E15-R11`). "Later" without a
round identifier is a plan hole, and `screen_reachability_test.dart` fails on
it.

### D7 — The static limit is stated, not hidden

Static analysis cannot see reflective or data-driven navigation. The tool and
`retirement-plan.md` say so explicitly; a `retire` verdict is a proposal for
human/round review, never an automatic authorisation.

## Consequences

- The E15 migration rounds spend their budget on screens the user can actually
  reach, with the measurement — not a guess — as the input.
- One more committed tool + gate test to maintain; `tool/ui_inventory.dart`'s
  exact 96 count stays the anchor, and this round does not move it.
- A `retire` verdict does not, by itself, permit deletion. That stays a
  separate, reviewed round — which is the point of D5.
