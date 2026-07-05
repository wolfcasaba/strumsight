# StrumSight 🎸

**See what you strum.** An offline, on-device Flutter app that shows the current chord **and the
strum direction (↓ down / ↑ up)** in real time while you play guitar — the one output every other
chord-detection app leaves out.

- **100% offline / on-device** — no backend, no network at runtime, no data leaves the phone.
- **Strum direction as the headline** — down/up per beat, with a confidence ramp.
- **Android-first** (iOS later; needs a Mac to build).

> **Status:** v1 infrastructure + UI, driven by a **mock detection engine**. The real detector
> (a C++ DSP core — aubio onset + CQT-chroma chord match + sub-band direction — over Dart FFI)
> drops in behind the existing `StrumEngine` interface with **zero UI changes**. See the
> [design spec](docs/superpowers/specs/2026-07-05-strumsight-design.md) and the
> [Phase 1 validation plan](docs/superpowers/plans/2026-07-05-strumsight-phase1-validation.md).

---

## What's in v1

| Surface | State |
|--------|-------|
| 🎤 **Live** mirror — huge current chord, next ghosted, big ↓/↑ arrow, confidence pill, rolling `1 & 2 & 3 & 4` beat counter, listening/level/BPM status | ✅ built (mock engine) |
| 🎛️ **Tuner** — note + cents gauge + in-tune indicator | ✅ built (mock engine) |
| ⚙️ **Settings** — theme (persisted), language (en/hu), confidence threshold (persisted), version | ✅ built |
| 🎬 **Analyze** (recording → timeline) · 📚 **Library** (saved sessions) | 🔜 v2 (placeholders) |

## Architecture

```
Live screen ─ watches ─▶ liveFrameProvider (StreamProvider)
                              │
                              ▼
                        StrumEngine  (abstract interface)
                        ├── MockStrumEngine   ← v1: deterministic frames
                        └── FfiStrumEngine     ← later: C++ DSP core (mic / MediaCodec → PCM)
```

The UI only ever talks to `StrumEngine` / `TunerEngine`. Swapping the mock for the FFI engine is a
one-line change in `lib/features/*/providers/`. Everything is unit- and widget-tested against the
mock, so the whole app is verifiable today.

**Design language:** dark-first Material 3, warm-neutral palette + **copper** brand accent, a
**separate semantic confidence ramp** (high `#3ED598` / mid `#F2B33D` / low `#6E7480`) that is
always reinforced by arrow *shape* (filled = high, outline = low) so meaning never depends on colour
alone. Tokens live in `lib/core/theme/` (`AppColors`, `AppPalette`).

## Project layout

```
lib/
├── app/                     # router + bottom-nav shell
├── core/theme · i18n · widgets
├── features/
│   ├── live/     model · engine · providers · widgets · screens
│   ├── tuner/    model · engine · providers · widgets · screens
│   ├── analyze/  (v2 placeholder) · library/ (v2 placeholder)
│   └── settings/ providers · screens
└── l10n/         app_en.arb · app_hu.arb
```

## Run

```bash
~/flutter/bin/flutter pub get
~/flutter/bin/flutter run          # boots to the Live tab (mock detection)
```

## Verify gate (run as SEPARATE calls — chaining OOMs this box)

```bash
~/flutter/bin/flutter analyze lib/     # clean
~/flutter/bin/flutter test             # all green
```

## Roadmap

1. **Phase 1** — validate the chord + strum-direction algorithm in Python on real clips (go/no-go).
2. **Phase 2** — port the validated algorithm to a C++ DSP core with unit tests.
3. **Phase 3** — native audio (Oboe mic capture, MediaCodec file decode) + JNI/FFI bridge.
4. **Phase 4** — wire the FFI engine into this Live UI (drop-in).
5. **v2** — Analyze (recording → timeline), Library (offline saved sessions), optional TFLite
   direction model.

Payments/monetization are intentionally out of scope.
