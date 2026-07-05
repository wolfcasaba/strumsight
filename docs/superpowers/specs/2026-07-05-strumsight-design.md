# StrumSight — Design Spec

**Status:** approved-for-planning · **Date:** 2026-07-05 · **Repo:** music-theory (Flutter) → publishes as `strumsight`

> **One line:** An offline, on-device Flutter app that shows the **current chord and the strum direction (↓/↑)** in real time while you play guitar — the one thing every chord-detection app leaves out.

---

## 1. Problem & differentiator

Chord-detection apps (Chordify, Chord ai, Moises) all recognise **chords**, but:

- None expose **strum direction (down/up)** as a first-class output.
- They are cloud-based, subscription-gated, and carry real-time **latency** pain.
- Chord ai is ~90% accurate and **standard-tuning only**; Moises is unreliable for complex harmony.

**StrumSight's wedge:** strum direction as the headline output, computed **100% on-device** (no network, no latency from round-trips, no data leaves the phone), Android-first.

This is a genuine market gap confirmed by research (2026): direction detection + offline + on-device is unoccupied.

## 2. Audience & scope

- **Primary user:** an intermediate guitarist practising **their own** playing — wants to *see* what they strummed, glanceably, hands on the instrument.
- **Tone:** dense pro-UI, minimal hand-holding, fast. (An optional beginner/help layer is a future concern, not v1.)
- **Platform:** Android-first (Oracle ARM box can build Android; iOS needs a Mac later — out of scope for v1).

## 3. Architecture (settled — see the technology research in the repo history)

One shared **C++ DSP core** with two input sources; Flutter UI over Dart FFI.

```
Input ── mic stream (real-time)     ─┐
     └─ MP4/audio file (analyze)  ──┐│
                                   ↓↓
   OS-native decode (MediaCodec / AVAssetReader → PCM)  [file mode only]
                                   ↓
   ⚙️ Shared C++ DSP core
      • onset detection (aubio)
      • CQT → chroma → 24 maj/min template match  → chord
      • sub-band onset-order heuristic (bass-first = ↓, treble-first = ↑) → direction
                                   ↓
   Dart FFI ─→ Flutter UI
```

- **Real-time mode:** small causal windows, no look-ahead, target **< 50 ms** latency (Oboe capture on Android).
- **File mode:** larger windows + look-ahead → higher accuracy; used for algorithm validation and unit tests against ground truth.
- **No FFmpeg** — OS-native decoders handle AAC/M4A/MP4. (FFmpegKit was retired/archived in 2025; a community fork exists but is unnecessary for our own AAC recordings.)

**Prune** inherited plugins the app doesn't need (`health`, `mobile_scanner`, `webview_flutter`, `flutter_tts`, etc.) — keep the tree lean. Keep the load-bearing `device_info_plus` override note in CLAUDE.md in mind while pruning.

## 4. UX / UI design

Visual mockup: `docs/superpowers/specs/strumsight-mockup.html` (Live hero + Analyze + design language).

### 4.1 Information architecture
Bottom nav, one-handed thumb zone. **Live is the default landing screen.**

| Tab | Purpose | v1? |
|-----|---------|-----|
| 🎤 **Live** | The mirror — real-time chord + ↓↑ + confidence + beat counter | **v1** |
| 🎬 **Analyze** | File/MP4 → scrollable chord+strum timeline, loop, slow-down | v2 |
| 📚 **Library** | Saved sessions, 100% offline (Isar/SQLite) | v2 |
| ⚙️ Settings | Confidence threshold, capo/transpose, tuning ref | v1 (minimal) |

### 4.2 Live "mirror" screen (the hero — readable at ~1 m, hands on guitar)
- **Center, huge:** current chord (e.g. `C`); next chord ghosted above.
- **Big ↓↑ arrow** animating on each onset, coloured by the **confidence ramp**, and reinforced by **shape** (filled = high, outline = low) so it is not colour-only (colourblind-safe).
- **Rolling beat counter** `1 & 2 & 3 & 4` showing the last bar's strum marks, using standard notation: ↓ down, ↑ up, `>` accent, `x` mute.
- **Top status (small):** listening indicator, input-level meter, detected BPM, tuning reference.
- **Bottom (thumb zone):** Tuner shortcut · large **Record** toggle (capture session) · Freeze/pause.
- **Landscape** supported (phone propped up).

### 4.3 Analyze screen (v2)
File pick or in-app record → native decode → same core with look-ahead → scrollable **beat-cell timeline** (chord + per-beat strum grid), playhead synced to playback. Transport: play/pause, **A–B loop**, 0.5–1× speed, capo/transpose, save.

### 4.4 Library (v2)
Saved live captures + analysed files, offline; preview = chord-progression strip; rename/delete/reopen.

### 4.5 Design tokens (replace the RecipeWiser placeholders in `core/theme/`)
Dark-first (performance/stage world). Warm-neutral family + copper brand accent; confidence is a **separate semantic ramp**, never the accent.

| Token | Hex | Role |
|-------|-----|------|
| ground | `#111013` | app background (warm near-black) |
| surface / elevated | `#191719` / `#22201F` | cards, cells |
| ink / muted / faint | `#E9E5DE` / `#948D82` / `#5E574F` | text (off-white, astigmatism-safe) |
| **copper** | `#D98A46` | brand: active tab, record ring, focus |
| confidence · high | `#3ED598` | ≥ threshold |
| confidence · mid | `#F2B33D` | borderline |
| confidence · low | `#6E7480` | unsure (grey, *not* red — low ≠ error) |

- **Type:** geometric sans for the big chord glyph; **mono** for gear-style readouts (BPM, beat counter, timecode, confidence %) — grounds it in the instrument/tuner world; tabular numerals for the counter.
- **Interaction:** 44pt+ touch targets, primary actions bottom-anchored, low-stimulus/glanceable, respect `prefers-reduced-motion`.

## 5. v1 (MVP) scope & build order

**Shipped surface (v1):** Live mirror screen + Tuner + minimal Settings. **No** Analyze, **no** Library persistence.

**Build order** (de-risks the hard DSP before the UI):
1. **Phase 1 — Python validation** (on the Oracle dev box, *validation only*): record 5–10 clean guitar clips, hand-label ↓/↑ ground truth; librosa CQT chroma + 24 templates → chord; onset detection; sub-band direction heuristic; **measure direction accuracy on own clips.** Go/no-go gate. If real-time direction accuracy is too low, fall back to shipping Analyze (look-ahead) first.
2. **Phase 2 — C++ core** in **file mode first**: aubio onset/tempo, CQT+chroma+templates, sub-band direction detector; ring buffer + causal path; **unit tests against Phase-1 ground truth** (regression guard).
3. **Phase 3 — Native audio + FFI**: Oboe mic capture; JNI/NDK bridge; Dart FFI binding.
4. **Phase 4 — Live UI**: wire the core to the Live mirror screen; Tuner; Settings; theme tokens.

## 6. Non-goals (YAGNI for v1)
iOS build · file/MP4 Analyze mode · Library persistence · beginner tutorial layer · non-standard tunings · jazz/extended chords (24 maj/min templates only) · TFLite direction model (a possible v2 upgrade if the heuristic underperforms) · any backend/Supabase (app is fully offline — Supabase stays in mock mode / can be pruned).

## 7. Verify gate (before "done")
Per CLAUDE.md — run as **separate** calls (OOM if chained):
- `~/flutter/bin/flutter analyze lib/` → clean
- `~/flutter/bin/flutter test` → green
- C++ core: unit tests pass against Phase-1 ground truth.
- Manual: Live screen reads a real strum on a physical Android device (real-data verification, not just a simulator).

## 8. Key risks
- **Up-strum accuracy** is the known weak point of the sub-band heuristic — the metric to watch in Phase 1.
- **Real-time latency** vs accuracy trade-off — causal windows cost accuracy; measure early.
- **On-device CQT cost** on mid-range Android — profile frame time.
