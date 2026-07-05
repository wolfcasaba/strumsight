# StrumSight DSP RAG knowledge base

Implementation-grade knowledge chunks for the REAL on-device detection engine.
Every DSP chunk in `chunks/` is a self-contained, sourced technical note with
concrete parameters (sample rates, window/hop sizes, thresholds) that the Dart
implementation in `lib/features/*/engine/dsp/` must follow.

## Search

```bash
node tools/dsp-rag.mjs "onset threshold median"      # ranked chunk hits
node tools/dsp-rag.mjs --list                        # list all chunks
```

## Chunk map

| id | topic | feeds |
|----|-------|-------|
| 001 | Mic capture → PCM stream (audio_streamer, permissions) | R10 real engines |
| 002 | FFT / STFT / windowing (fftea) | R7 |
| 003 | Chromagram from FFT bins | R7 chroma |
| 004 | Chord templates + matching + hysteresis | R7 chord |
| 005 | Onset detection: spectral flux + adaptive threshold | R8 onset |
| 006 | Strum direction (↓/↑): state of the art + our heuristic | R8 direction |
| 007 | Tempo/BPM from inter-onset intervals | R8 |
| 008 | YIN pitch detection for the tuner | R9 |
| 009 | Dart package selection + licences | R7–R10 |
| 010 | Real-time architecture: isolate, ring buffer, latency budget | R7–R10 |

Update rule: when a parameter is tuned on real audio, update the chunk with the
measured value AND the reason — the chunks are the single source of truth.
