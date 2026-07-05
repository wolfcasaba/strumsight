---
id: 007
topic: Tempo (BPM) estimation from inter-onset intervals
tags: [bpm, tempo, inter-onset, interval, median, beat]
sources:
  - https://www.audiolabs-erlangen.de/resources/MIR/FMP/C6/C6S1_PeakPicking.html
---

# BPM from inter-onset intervals (IOI)

Keep the last **8 onsets** (7 IOIs). BPM = `60 / medianIOI`, folded into the
**60–200 BPM** range by doubling/halving (an eighth-note strum pattern yields
IOIs at 2× the beat rate — folding maps both to the same tempo).

- Median, not mean — one missed onset creates a 2× outlier IOI.
- Smooth the reported value: `bpm = 0.8*prev + 0.2*new`; round for display.
- <3 IOIs → report 0 ("—" in the UI); after 2 s without onsets, decay to 0.
- Beat-phase (which slot of "1 & 2 &…" we're in) v1: slot = nearest eighth
  since the first onset of the current bar window; full beat-tracking is v2.
