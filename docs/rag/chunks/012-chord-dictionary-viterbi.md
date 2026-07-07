---
id: 012
topic: The next chord-engine port — bass+treble chroma + chord-profile dictionary + Viterbi (Chordino-class), and why it fixes what round 26 could not
tags: [chord, chordino, dictionary, viterbi, hmm, dbn, bass-chroma, whitening, tuning, roadmap]
sources:
  - Mauch & Dixon "Approximate Note Transcription for the Improved Identification of Difficult Chords" (NNLS-Chroma/Chordino), ISMIR 2010
  - isophonics.net/nnls-chroma (Chordino Vamp plugin params)
  - c4dm/nnls-chroma Chordino.cpp (chord.dict + smoothing)
  - musicinformationretrieval.wordpress.com "Chosen Audio Chord Estimation algorithms explained" (Chordino DBN, madmom CNN+CRF)
  - Cho & Bello, BTC "A Bi-directional Transformer for Musical Chord Recognition" arXiv 1907.02698
---

# The next chord engine: chord DICTIONARY + Viterbi

**Why this chunk exists.** Round 26 tried to add 7th/sus/power chords by bolting
extra **note templates** onto the triad matcher. It failed and was reverted:
with note-templates a 7th is a *superset* of its triad (Cmaj7 ⊇ C) so it always
scores high, and — measured — NNLS overtone suppression *removes* the added tone
whenever it coincides with a chord-tone's harmonic (Em7's D = G's 3rd harmonic →
~0; Fsus4's fifth C = F's 3rd harmonic → gone). Templates + hysteresis is the
wrong model for extended chords. The production answer, unchanged since the 2011
MIREX winner, is a **chord-profile dictionary + a sequence model**. This is a
pure-DSP, deterministic, testable port — no ML, no training data, no Mac.

## What Chordino actually does (the reference pipeline)

```
audio → CQT-ish log-freq spectrum (3 bins/semitone)
      → TUNING estimation (global or local) + interp to bin centres
      → SPECTRAL WHITENING  (bin ÷ stddev(neighbours)^w, w≈1.0)
      → NNLS transcription vs harmonic dict (spectral shape 0.7)   ← we HAVE this
      → BASS chroma (12) + TREBLE chroma (12)  = 24-dim feature    ← NEW
      → frame-wise similarity vs CHORD PROFILE DICTIONARY          ← NEW (the fix)
      → DBN / HMM–Viterbi smoothing (+ a no-chord state)           ← NEW (the fix)
      → chord transcription
```

We already implement the middle (NNLS vs a harmonic dictionary, chunk 011). The
**three new stages** are what make extended chords reliable.

### 1. Bass + treble chroma (24-dim), not one 12-bin fold
Our `NnlsChroma` already produces per-note activations over `minMidi..maxMidi`;
today we fold ALL of them into one 12-bin chroma. Instead fold the **low register
separately** (a bass chromagram) from the **mid/upper register** (treble
chromagram) → a 24-dim feature. The bass chroma gives the **root / bass note**,
which disambiguates inversions and slash chords (C/G) and sharpens quality
discrimination. Cheap: it's just two weighted sums of activations we already have.

### 2. Chord-profile dictionary (compare whole chords, not notes)
For each chord (root × quality) store a 24-dim **profile**: expected treble
pitch-class weights (the chord tones) + expected bass weight (root-heavy, with
inversion variants weighting the 3rd/5th in the bass). Score each frame by
similarity (cosine, or a log-likelihood) to every profile. Because the profile
for `Cmaj7` vs `C` differs specifically in the **B weight**, the comparison is
"does the 7th's evidence actually match", not "does a superset score ≥ the
subset". Include a **no-chord profile** (flat) with a small boost (≈0.1) so
silence/noise resolves to N.C. instead of a random chord.

Chordino's DBN vocabulary = **121 chords, 11 categories**: maj, min, dim, aug,
dom7, min7, maj7, maj6, + 1st/2nd inversion of major, + no-chord. Start smaller
(maj, min, dom7, maj7, min7, sus4, N.C.) and grow.

### 3. Viterbi / HMM smoothing (replaces ad-hoc hysteresis)
States = the chord vocabulary + N.C. **Transition model:** high self-transition
probability (chords persist for beats), small uniform switch probability.
**Emission:** the frame-wise similarity turned into a log-probability. Viterbi
finds the optimal chord *path* over time.
- **Analyze (batch):** full Viterbi over the clip — best quality.
- **Live (real-time):** we can't see the future → use **online/token-passing
  Viterbi** with a short look-back, or a self-transition *bonus* added to the
  current best each frame. This is the principled replacement for round-4's
  hand-tuned 3-frame hysteresis + instant-switch threshold.
- The self-transition cost also cures the **maj↔maj7 flicker** for free: a
  challenger must overcome the switch penalty *and persist*, so a one-frame blip
  of extra-tone energy can't rename the chord.

## Honest limits (do not oversell)
Chord profiles do **not** recover a genuinely suppressed tone: if the treble-band
NNLS has erased Em7's D (round-26 measurement), no profile can invent it — and it
would be *correct* to report Em, since the 7th isn't audible in that voicing. To
actually hear weak upper extensions you need **less aggressive suppression on the
treble band** (lower `harmonics`/higher `spectralShape` there) or a **learned
model**. So: the dictionary+Viterbi port makes the chord track *principled,
smooth, inversion-aware, and N.C.-aware*, and gets the common open 7ths (G7, C7,
Am7, Dm7, Cmaj7) that DO carry the tone — but "every jazz voicing" is an ML-era
goal, not this port.

## Params to carry over (concrete)
- log-freq **3 bins/semitone** (have), **spectral shape 0.7** (have),
- **spectral whitening** exponent **≈1.0** applied *before* NNLS (NEW; we only
  whiten the onset path today),
- **tuning estimation** global/local, shift chroma mapping by the detected
  offset (NEW — real guitars drift; also lets the A4 setting be a *prior*, not an
  assumption),
- **no-chord boost ≈0.1**, **Viterbi self-transition** prob (tune on device).

## Where ML fits (later, optional)
SOTA is **CQT → CNN/CRF (madmom, 2016)** or **CQT → bi-directional transformer
(BTC, 2019)**. On-device is proven feasible: a competitor, **Chord AI**
(`com.chordai`), runs an **offline CNN on the phone**; TFLite inference is ~1–13
ms for a 2.56 s input and quantizes ~9× smaller. But it needs a labelled training
set + a Mac-free train/export path, and breaks the pure-Dart offline design.
**Decision:** do the Chordino-class port first (deterministic, testable, fixes
the real gap); revisit ML only after the user's real-guitar test says DSP has
plateaued. **No competitor detects strum DIRECTION (↓/↑) — that stays our moat.**
