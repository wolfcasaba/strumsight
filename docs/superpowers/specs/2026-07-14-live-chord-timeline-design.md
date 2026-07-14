# Live Chord Timeline — Design

**Date:** 2026-07-14 · **Round:** 185 · **Status:** approved (user, inline)

## Goal

Replace the current Live "hero" group (big chord + separate ↓/↑ arrow + confidence
pill + top-left chord diagram) with a single, cohesive **horizontal chord timeline**:
the freshly recognized chord shown large (fixed anchor, right side), previously
recognized chords trailing to the left — shrinking, fading, receding — each carrying
its own strum direction. 2026-era motion polish. The moat (↓/↑ strum direction per
chord) stays front-and-center.

Non-goals: no engine/DSP change, no `LiveFrame` model change, no backend, no new
plugin. Detection stays 100% on-device.

## Layout — horizontal filmstrip, right-anchored

```
 status bar …                                   🔥
   Am    F    G      ┌──────────┐   ˑCˑ
   ·     ·   ▁▁      │    C     │        (next ghost, if known)
  (faded, shrinking  │ ◇diagram │
   history cards)    │    ↓     │   HERO
                     │ ▓▓▓▓░ 82%│
                     └──────────┘
              1 & 2 & 3 & 4   (beat counter)
        🎚 Tuner    ⏸ Pause    ⏱ Metronome
```

- **Hero (newest chord):** large card — mini chord diagram + large ↓/↑ arrow +
  confidence ramp (existing shape+colour semantics). Subtle frosted/copper-tinted
  glass surface **only** on this card (surgical 2026 glassmorphism).
- **History:** 3–5 cards to the left, each smaller (scale tier ~1.0 → 0.72 → 0.55 → …)
  + more transparent + slight blur; each shows chord label + its ↓/↑ direction.
- **Next ghost:** if the engine knows `next`, a faint small card at the hero's right edge.
- **Kept as-is:** status bar, 🔥 streak badge, beat counter, action bar, mic banners.
- **Subsumed / removed:** `ChordDisplay`, standalone `StrumArrow` slot, `ConfidencePill`,
  the top-left `ChordDiagram` overlay — their information now lives in the hero card.

## Motion (from competitor research — Chordify/GuitarTuna inverse, Apple-Music recede,
Yousician hit-split)

- **New chord enters:** springs in from the right (`easeOutBack`, ~250 ms), scale + fade.
- **History recede:** on each chord change, prior cards slide left + scale down + fade +
  slight blur — once per transition, not continuous.
- **Recognition flash:** instant copper glow + micro scale-pulse (binary, ~100 ms,
  *decoupled* from the settle-in animation), with `HapticFeedback.lightImpact()` on the
  same frame.
- **Strum arrow flourish:** down-strum nudges downward, up-strum upward (`slideY`, ~150 ms).
- **Beat pulse:** hero pulses subtly on the beat, tied to the existing beat-counter
  active slot / detected BPM.

All motion is state-communicating, spring/ease-out over linear. `flutter_animate` +
`AnimatedSwitcher`/`AnimatedContainer`.

## Architecture — isolated units

| Unit | Responsibility | Testable |
|---|---|---|
| `ChordEvent` (model) | one recognized chord: `{chord, direction?, confidence, seq, timeSec}` | pure |
| `ChordTimelineController` (Notifier) | watches `liveFrameProvider` → ring buffer (max ~6) of **distinct** chords; dedupes consecutive identical chords, updates the latest card's strum direction/confidence | pure logic, no widgets |
| `ChordTimelineCard` (widget) | one card at a given size tier: label + arrow + confidence + (hero only) diagram | widget test |
| `ChordTimeline` (widget) | lays out hero + history + next-ghost, orchestrates animations | widget/golden |
| `LiveScreen` | swap hero group → `ChordTimeline` | rig screenshot |

**Data flow:** `liveFrameProvider` (stream, unchanged) → `chordTimelineProvider`
(history buffer) → `LiveScreen` → `ChordTimeline`. `LiveFrame` stays a pure engine
snapshot; history is assembled in the provider/UI layer.

**Controller logic (the crux):**
- Push a new `ChordEvent` when `frame.current`'s label changes (dedupe consecutive
  identical labels — retuning/re-detecting the same chord must NOT spawn a card).
- While the same chord sounds, update that event's `direction`/`confidence` from the
  latest strum (so the hero's arrow reflects the most recent stroke on that chord).
- Ring buffer capped at ~6; newest last. Ignore null `current` (idle) — don't push.
- Capo is view-time only (`transposed(-capo)`) at render, exactly as today — the buffer
  stores concert-pitch chords.
- Pause: freeze buffer, mark not-listening; do not clear history.

## Edge cases / error handling

- **Empty / idle:** show a soft "Play a chord…" prompt where the hero would be.
- **Mic error / no permission:** existing `MicErrorBanner` / `MicPermissionBanner`
  (unchanged).
- **Rapid chord flicker:** dedupe + the ring buffer bound keep it stable; low-confidence
  detections still render (confidence ramp communicates uncertainty) — do not gate cards
  on a hard confidence threshold here (that lives in the DSP).
- **Landscape / small screens:** the hero + history row must `FittedBox`-scale like the
  current hero does; never overflow.

## Verification

- **Widget test:** drive `chordTimelineProvider` (or mock engine) with a frame sequence →
  assert N cards, newest largest, correct labels + directions, dedupe holds.
- **Property test** (`test/property/`, `PROPERTY_SEED`): buffer invariants — never exceeds
  cap, newest-last ordering, no consecutive duplicate labels, direction updates in place.
- **Rig:** web release build + Playwright screenshot (412×915) of the timeline populated.
- **Final gate:** the user's real-guitar APK test (synthetic green is never "done").

## Rollout

Single round (r185). One commit for the feature + tests, spec committed first. Update
`HANDOFF.md` and `docs/rag/chunks/016b` (animation truth) in the same round.
