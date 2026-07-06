# StrumSight 🎸

**See what you strum.** An offline, on-device Flutter app that shows the current chord **and the
strum direction (↓ down / ↑ up)** in real time while you play guitar — the one output every other
chord-detection app leaves out.

- **On-device detection** — the mic → DSP pipeline runs entirely on the phone; **no audio ever
  leaves the device**, and the app is fully usable offline.
- **Strum direction as the headline** — down/up per beat, with a confidence ramp.
- **Optional account** — an opt-in login (FastAPI backend, `backend/`) syncs your *settings* across
  devices. It's purely additive: logged out, everything still works and nothing hits the network.
- **Android-first** (iOS later; needs a Mac to build).

> **Status (v0.2.0):** REAL on-device detection in **pure Dart** — microphone → DSP isolate →
> chroma/chord + whitened-spectral-flux onsets + sub-band strum direction + YIN tuner. The DSP
> follows the sourced parameters in the [RAG knowledge base](docs/rag/README.md) and is fully
> unit-tested on synthesized guitar signals. A C++/FFI port remains the optimization path only
> if on-device profiling demands it.

---

## What's in v1

| Surface | State |
|--------|-------|
| 🎤 **Live** mirror — huge current chord, big ↓/↑ arrow, confidence pill, rolling `1 & 2 & 3 & 4` beat counter, listening/level/BPM status | ✅ **real detection** (mic) |
| 🎛️ **Tuner** — note + cents gauge + in-tune indicator | ✅ **real YIN pitch** (mic) |
| ⚙️ **Settings** — theme (persisted), language (en/hu), confidence threshold (persisted), version | ✅ built |
| 🔐 **Account** (optional) — email/password login, settings synced to the cloud (`backend/`) | ✅ opt-in |
| 🎬 **Analyze** (recording → timeline) · 📚 **Library** (saved sessions) | 🔜 v2 (placeholders) |

## Architecture

```
mic (audio_streamer) ──▶ DSP ISOLATE                         ┌─ Live screen
  PCM chunks             LivePipeline                        │   watches
                         ├─ fast  1024/256 : whitened flux ─ onsets → sub-band ↓/↑
                         ├─ slow 4096/1024 : peak-picked chroma → 24-template chord
                         └─ tempo (median IOI) + bar slots → LiveFrame ~15 Hz ──▶ UI
```

The UI only talks to the `StrumEngine`/`TunerEngine` interfaces. `RealStrumEngine` runs the whole
pipeline off the UI isolate; `stop()` releases the microphone. The mocks remain as deterministic
test infrastructure. Every DSP stage is unit-tested on synthesized guitar signals (staggered-string
strums, harmonic-rich triads), and every parameter is documented + sourced in `docs/rag/`.

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
