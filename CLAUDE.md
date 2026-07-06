# Music Theory (mobile)

**Standalone Flutter mobile app.** Separate project — NOT part of RecipeWiser / recipewiser-mobile,
though it reuses their Flutter infrastructure, plugin set, dev-agents and learning systems.

> 📌 **READ [`HANDOFF.md`](HANDOFF.md) FIRST every session** — it is the always-current snapshot of
> what's done / what's next, and MUST be updated after every development round.

> ✅ **App is specified & building:** **StrumSight** — offline on-device guitar chord + strum-direction
> detector. See `HANDOFF.md` for live status, `docs/` for spec/plan, `docs/rag/chunks/` for DSP truth.

---

## Tech Stack

Flutter (Dart SDK `^3.12.2`) · Material 3 · Riverpod 3 (`flutter_riverpod`, hand-written providers, NO codegen)
`go_router` · `supabase_flutter` (backend, currently unconfigured → mock mode) · `dio` (HTTP)
`fl_chart` · `google_fonts` · `flutter_animate` · `lucide_icons_flutter` · media plugins (image_picker,
speech_to_text, audioplayers, flutter_tts, mobile_scanner, webview_flutter)
i18n: `flutter_localizations` + `intl`, ARB files under `lib/l10n/` (en, hu)

> The full plugin set was inherited from recipewiser-mobile so the whole infra is ready day one.
> **Prune** any plugin the music-theory app ends up not needing (e.g. `health`, `mobile_scanner`).

---

## Project Structure (feature-first)

```
music-theory/
├── lib/
│   ├── main.dart              # App boot: ProviderScope + MaterialApp + optional Supabase.init
│   ├── core/                  # Reusable, feature-agnostic
│   │   ├── theme/             # app_theme, app_colors, app_palette, theme_mode_provider
│   │   ├── i18n/              # locale_provider, ai_language
│   │   ├── supabase/          # supabase_config (mock unless --dart-define keys given)
│   │   ├── utils/             # text helpers
│   │   └── widgets/           # generic: app_card, skeleton, gradient_text, brand_heading, brand_slider
│   ├── features/<feature>/    # (empty) — one folder per feature; screens/providers/repositories/models
│   └── l10n/                  # app_en.arb, app_hu.arb (generated app_localizations*.dart are gitignored)
├── .claude/
│   ├── agents/                # flutter-{reviewer,debugger,test-writer,performance,analyze-fixer,devil-advocate} (generic pro Flutter engineering)
│   └── skills/                # learning systems + dev skills (session-learning, self-reflect, TDD, verify-before-done, ...)
├── tools/flutter-rag.mjs      # semantic code search over the Dart tree
├── .github/workflows/         # build-apk.yml (CI → APK artifact)
└── .mcp.json                  # dart + context7 + viking (learning bridge, root=/music-theory)
```

---

## Conventions (inherited from recipewiser-mobile — reusable)

- **State:** Riverpod 3 hand-written providers (`Notifier` / `AsyncNotifier` / `Provider`). NO codegen.
- **Data:** repository-provider pattern. Preview/in-memory repos back the logged-out / mock-mode path.
- **Backend:** an **optional** account layer — a **FastAPI + SQLite + JWT** service in `backend/`
  (chosen round 14; Supabase was NOT used). It handles login + cloud settings sync only; **detection
  stays 100% on-device** and the app is fully usable logged out. Flutter talks to it via Dio (base
  URL from `--dart-define=STRUMSIGHT_API_URL`, default `http://10.0.2.2:8000`); JWT lives in
  `flutter_secure_storage`. Backend run/test: `backend/README.md`. See `lib/features/auth/` +
  `lib/features/settings/providers/settings_sync.dart`.
- **i18n:** every user-facing string goes through ARB → `AppLocalizations`. Code/comments in English.
- **Brand tokens** in `core/theme/` are **placeholders** copied from RecipeWiser — replace once
  the music-theory branding is decided.

## Critical build gotchas (learned the hard way on recipewiser-mobile)

- **Run `flutter analyze` and `flutter test` as SEPARATE calls — never chain `analyze && test`** (OOM on this box).
- **Keep ONE win32 major across the tree** (required for `flutter test` host-compile). This is why
  `flutter_secure_storage` is pinned to **v10** (win32 ^6, matching `wakelock_plus`) — v9 pulls win32 ^5
  and fails version-solve. Check win32 when adding any plugin.
- `lucide_icons_flutter` icon names fail only at compile — verify names.
- **Cloud writes swallowed by `try/catch` → silent no-op / lost edit.** Settings sync must mark state
  synced ONLY after the server confirms, and retry failed pushes (round 17). Verify persistence + offline path.
- Riverpod 3.3.2: `AsyncValue` exposes **`.value` (nullable), not `.valueOrNull`**.

## Verify gate (before "done")

```bash
~/flutter/bin/flutter analyze lib/     # clean
~/flutter/bin/flutter test             # separate call — all green
```

Use the `flutter-*` agents + `verify-before-done` / `session-learning` skills.

## HORIZON conventions (adopted 2026-07-05 — arXiv 2606.28279)

- **Git-notes experience buffer:** after every round/feature commit:
  `git notes add -m "round=<n> verdict=pass|fail tests=<n> lesson=<slug>"` —
  rejected attempts logged too. Notes do NOT push by default:
  `git push origin 'refs/notes/*'` alongside the branch push.
- **Randomized property gate (anti-reward-hacking):** `test/property/` reads
  `PROPERTY_SEED` env — absent → seed 42 (deterministic dev loop); CI runs an
  extra HARD step with `PROPERTY_SEED=${{ github.run_id }}`. Thresholds are
  %-based (non-flaky). New DSP behaviour ⇒ add a randomized property, not only
  fixed fixtures. The FINAL acceptance predicate is the user's real-guitar
  APK test — synthetic green is never "done".
- **DSP tuning:** any retuned parameter goes into `docs/rag/chunks/` (source
  of truth) in the same commit.
