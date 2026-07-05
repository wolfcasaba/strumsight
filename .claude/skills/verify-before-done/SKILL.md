---
name: verify-before-done
description: Run before declaring ANY code change "done"/"kész" or handing off in recipewiser-mobile. The explicit verification gate (analyze + tests + build + visual + persistence-proof) — skipping it is the #1 source of agent mistakes. Use after finishing a feature/fix, before "kész"/"done", and before any commit/push.
---

# Verify before done (mobile)

An explicit verification step before claiming completion is worth 2–3× the quality.
Never say "done", "kész", or "green" without running the relevant tier below. Match the tier to
the change; do the higher tiers before a commit/push.

**⚠️ NEVER chain `flutter analyze && flutter test`** — combined memory crosses the OOM line on this
ARM box (exit 143). Run them as TWO SEPARATE Bash calls, each with a generous timeout (≥240s).

## Tier 0 — every edit
Use the Dart MCP analyzer on what you touched (`mcp__dart__analyze_files`) or a scoped
`flutter analyze lib/<path>`. Fix surfaced errors before stacking more edits on a broken file.
Note: bad `lucide_icons_flutter` icon names compile-fail only at `flutter test`, not `analyze`.

## Tier 1 — after a unit of work
```bash
flutter analyze lib/        # run ALONE — must be 0 errors
```

## Tier 2 — UI work (see it yourself, don't trust "it compiles")
Render and actually LOOK (see the `local-visual-verification` memory):
- Golden screenshot the agent can Read (`matchesGoldenFile` + `flutter test --update-goldens …`), OR
- web build + headless Chromium render → Read the PNG.

Check: brand colors (#ED068A→#FE734C via `AppColors`, no off-brand pink/purple), layout intact,
no blank/overflow sections, scraped titles sanitized. Prefer a **real-data** build (anon-key
dart-define) — the mock build hides data-shaped bugs.

## Tier 3 — backend write work (prove it actually persisted)
Every Supabase call is wrapped in `try/catch(_){}` → a wrong table/column name **silently no-ops**
and optimistic UI hides it. So:
1. Verify the EXACT table + column against the prod baseline (NOT mobile code, NOT this doc):
   `awk '/CREATE TABLE.*"<table>"/,/\);/' ~/Recipewiser/supabase/migrations/00000000000000_remote_baseline.sql`
2. Run a real-data build (anon key) and confirm the row actually round-trips — don't trust the UI.

## Tier 4 — before "DONE" / handoff / commit (the full gate)
```bash
flutter analyze lib/        # call 1 — clean
```
```bash
flutter test                # call 2, SEPARATE — green
```
Optionally `flutter build apk` (the mobile deliverable) for release-bound work.
Only after analyze is clean AND tests are green do you state "done" — plainly, with the numbers.

## Honesty rule
If a tier fails, SAY SO with the output. Never claim green on a red gate. If you skipped a tier,
say which. A wrong table name that "passed" because the catch swallowed the 404 is NOT done.
