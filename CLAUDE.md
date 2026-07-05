# Music Theory (mobile)

**Standalone Flutter mobile app.** Separate project — NOT part of RecipeWiser / recipewiser-mobile,
though it reuses their Flutter infrastructure, plugin set, dev-agents and learning systems.

> ⏳ **App not yet specified.** The feature set arrives later. Until then this repo is
> infrastructure-only: a booting app with theme + i18n + (optional) backend wiring and a
> placeholder home screen. Do NOT invent features before the spec.

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
│   ├── agents/                # music-theory-{reviewer,debugger,test-writer,performance,analyze-fixer,devil-advocate}
│   └── skills/                # learning systems + dev skills (session-learning, self-reflect, TDD, verify-before-done, ...)
├── tools/flutter-rag.mjs      # semantic code search over the Dart tree
├── .github/workflows/         # build-apk.yml (CI → APK artifact)
└── .mcp.json                  # dart + context7 + viking (learning bridge, root=/music-theory)
```

---

## Conventions (inherited from recipewiser-mobile — reusable)

- **State:** Riverpod 3 hand-written providers (`Notifier` / `AsyncNotifier` / `Provider`). NO codegen.
- **Data:** repository-provider pattern. Preview/in-memory repos back the logged-out / mock-mode path.
- **Backend:** `supabase_flutter`. Currently NO backend is configured — a **separate** one will be
  chosen with the spec (do not reuse RecipeWiser's project). Keys come via `--dart-define`, never committed.
- **i18n:** every user-facing string goes through ARB → `AppLocalizations`. Code/comments in English.
- **Brand tokens** in `core/theme/` are **placeholders** copied from RecipeWiser — replace once
  the music-theory branding is decided.

## Critical build gotchas (learned the hard way on recipewiser-mobile)

- **Run `flutter analyze` and `flutter test` as SEPARATE calls — never chain `analyze && test`** (OOM on this box).
- `health` forces the `device_info_plus` win32 major; `dependency_overrides` pins `device_info_plus: ^13`
  to keep ONE win32 major across the tree (required for `flutter test` host-compile). Don't remove without testing.
- `lucide_icons_flutter` icon names fail only at compile — verify names.
- Backend writes to a wrong table/column get swallowed by `try/catch` → silent no-op. Verify persistence.

## Verify gate (before "done")

```bash
~/flutter/bin/flutter analyze lib/     # clean
~/flutter/bin/flutter test             # separate call — all green
```

Use the `music-theory-*` agents + `verify-before-done` / `session-learning` skills as on recipewiser-mobile.
