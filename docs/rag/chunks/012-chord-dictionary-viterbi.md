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

> **STATUS: IMPLEMENTED (round 28).** Shipped in `lib/features/live/engine/dsp/`:
> `nnls_chroma.dart` (now also emits a bass+treble 24-dim chroma),
> `chord_dictionary.dart` (profiles + scorer), `viterbi_chord_decoder.dart`
> (online decoder), wired into `live_pipeline.dart` — replacing the template
> matcher + hand-tuned hysteresis on the chord path. The round-26 7th failure is
> fixed end-to-end (G7/A7/B7 detected from synthesized guitar audio; plain triads
> stay triads). Tuned values + what was learned building it are in the
> **"Params — AS BUILT"** section at the bottom. The template matcher is kept
> only as a test reference. NOT yet built: spectral whitening (pre-NNLS) and
> per-frame tuning estimation — still open follow-ups (see end).

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

## Params — AS BUILT (round 28, tuned on synthesized guitar audio)

Mirror of `DspConfig` + `ChordDictionary`/`ViterbiChordDecoder` defaults. These
were tuned against synth signals + a 9-seed randomized property gate; **expect a
real-guitar retune** (that is the final acceptance).

- **Register split (`NnlsChroma`)** — **SUPERSEDED in E18-R07, see the
  "Register windows" section below.** The bass fold is now DEPTH-WEIGHTED, as
  the reference does it; the hard cut described here is the fallback path
  (`referenceRegisterWindows: false`). `trebleMinMidi = 40` (E2) — the treble
  chroma folds the **whole** note range, i.e. the full harmony; `bassMaxMidi =
  52` (E3) — the bass chroma folds only the low sub-register for the root.
  *Learned the hard way:* a HIGH treble floor (first tried C3) drops a guitar
  chord's low root+third out of the harmony (guitar voices in E2–D3), so a G7
  read as **Dm** (treble saw only D+F). Treble = full range fixed it. Bass still
  isolates the root because it's the *lowest* register, not because treble is high.
- **Chord dictionary (`chord_dictionary.dart`)**: vocabulary = **maj, min, 7,
  maj7, m7, sus4 + N.C.** = 73 states. **Power-5 and sus2 were tried and pulled**:
  a `[root,fifth]` profile has no third to contradict, so it *steals* any triad
  whose third is quiet (exactly round-26's "power chords steal weak-third triads");
  sus2 collides with a neighbour's fifth. Add back only with real-guitar data.
  - Treble profile weights: root 1.0, third 1.0 (0.9 on 7ths), fifth 0.6–0.7,
    seventh 0.9. Bass profile: root 1.0 + fifth 0.3, L2-normalised.
  - `bassWeight 0.35 / trebleWeight 0.65` blended cosine.
  - **No-chord floor `noChordScore = 0.55`** (our realisation of the "no-chord
    boost"): a real chord's blended cosine must clear this or the frame is N.C.
  - **Per-quality Occam bias** (the key discovery): a small similarity handicap
    on 4-note profiles so an extension must be *clearly* present, not win by the
    phantom 7th a third's own 3rd-harmonic leaves behind (a MAJOR third's 3rd
    harmonic = a major 7th above the root; a MINOR third's = a minor 7th). A
    single global penalty can't win — it must be **per quality**: `7 → 0.02`,
    `maj7 → 0.055`, `m7 → 0.055`, triads → 0. Reason: dom7's minor-7th has no
    strong phantom source, so it needs almost none, but maj7/m7 do; too much on
    dom7 and real A7/B7 collapse to the triad. Global scale = `extensionPenalty`.
- **Viterbi decoder (`viterbi_chord_decoder.dart`)**: online token-passing with
  a **self-transition bonus `selfBonus = 0.22`** (in similarity units) — the ONE
  knob that replaced round-4's three hysteresis constants. A rival must beat the
  incumbent's per-frame similarity by more than this **and persist** to flip;
  scores renormalised each frame (subtract max) to stay bounded. This cures the
  maj↔maj7 blip for free. Trade-off observed: the maj7 Occam bias shrinks the
  real-maj7 margin, so switching *into* a sustained maj7 is deliberate (~1 s),
  not instant — acceptable (stability > speed), tune on device.
- **Honest limit, re-confirmed by measurement:** a low-voiced dom7 is detected
  for roots **E2–B2** (the m7 fundamental dominates the root's faint 7th
  harmonic), but for roots **≥ C3 the m7 coincides with the root's own 7th
  harmonic** (C7's B♭ = C's 7th harmonic, D7's C = D's, …) and NNLS suppresses
  it → collapses to the bare triad. That is *correct* if the tone isn't audible;
  hearing weak upper extensions everywhere remains the ML-era goal. The
  randomized dom7 property is therefore gated on the E2–B2 band only.

## Tuning estimation — AS BUILT (round 69)

The "deferred: synth is perfectly in tune" reasoning was WRONG — synth can be
*deliberately* detuned, and doing so exposed two real defects:

1. **A hidden +1/3-semitone dictionary bias.** `_buildDictionary` placed each
   note's centre at bin `n·bps + bps~/2`, but on the `_binFreq` grid
   (`midi = minMidi + j/bps`) the note's exact frequency sits at bin `n·bps`.
   The whole dictionary was systematically 1 bin (33 cents) SHARP. Measured
   symptom: a 35-cent-FLAT C major decoded as **B** (everything slid a
   semitone down) while +35 cents passed. Fixed: `base = n·bps`. All previous
   gates stayed green — the bias had been absorbed by tuned thresholds.
2. **No tuning compensation at all.** Real guitars sit 10–40 cents off.

Implementation (`NnlsChroma`, flag `tuningEstimation = true`):
- Sample the log-freq spectrum on the nominal grid, then estimate the frame's
  sub-semitone offset as the **energy-weighted circular mean** of the 3
  within-semitone bin phases (`θ_j = 2π·(j mod 3)/3`, weights `s_j²`;
  `atan2 → frac ∈ −0.5..0.5` semitone).
- **EMA-smooth** across frames: `tuningSmoothing = 0.2` (first tonal frame
  initialises directly). Exposed as `lastTuningSemitones` (positive = sharp).
- If `|offset| > 0.02` semitone, **resample** the log-freq spectrum at
  `binFreq · 2^(offset/12)` so the detuned partials land back on note
  centres; NNLS and everything downstream is unchanged. Cost: one extra
  interpolation pass over 441 bins per chord frame (FFT dominates).
- Gates: deterministic ±35/−30-cent chord tests + a randomized property
  (uniform ±40-cent detune, random maj/min triads, ≥16/20) — green across
  seeds 42, 7, 123, 2026, 31337.
- The A4 *setting* remains the tuner's reference only; the chord path now
  self-corrects, which also makes non-440 references converge to correct
  nearest-semitone names.

## Spectral whitening — AS BUILT (round 70)

Applied round 69's lesson ("make the synth adversarial") — a colouration probe
found the real failure mode: most timbres (flat, bright, body resonances) were
already handled by NNLS, but a **phone-mic low-shelf roll-off** (fundamentals
×0.15 below 300 Hz) read a C major as **Em** — the notes' own harmonics
outvoted the attenuated fundamentals.

Implementation (`NnlsChroma`, flag `spectralWhitening = true`):
- After sampling (and tuning resample), each log-freq bin is divided by the
  **RMS of its ±`whiteningHalfSemitones` neighbourhood**
  raised to `whiteningExponent`, with an RMS floor of `1e-4·maxS` so true
  silence isn't amplified into structure. O(bins) via prefix sums.
- **Exponent 0.7, NOT Chordino's ≈1.0**: full whitening (w=1.0) erodes the
  ROOT's natural dominance and regressed the 12-bin-chroma property gate
  (Em→G, E→G#m — third/fifth outvoting the root). w=0.7 fixes the thin-mic
  case with zero regression. (Same "partial beats full" shape as
  `spectralShape 0.7`.)
- Gates: deterministic thin-mic/resonance chord tests + a randomized property
  (random shelf 250–350 Hz, ×0.1–0.3, random triads, ≥16/20) — green across
  seeds 42, 7, 123, 2026, 31337.

## Whitening SPAN — the second thing it decides (E18-R06, real guitar)

Round 70 chose the whitening *exponent* on a timbre probe and left the
neighbourhood at a half octave without ever measuring it. The span turns out to
decide something else entirely: **what "loud" is measured against.**

At a WIDE span a bin is normalised against most of an octave, so a quiet tone
stays quiet relative to its loud neighbours. At a NARROW span each local peak is
normalised by its OWN neighbourhood, so the peaks are pulled toward a common
level.

For guitar that decides the chord, because a guitar voicing is not level-flat:
**the fifth is doubled across two or three strings while the third is fretted
exactly once**, so the tone that determines the QUALITY is routinely the
quietest thing in the signal.

MEASURED on the seven labelled reference recordings, through the full
`LivePipeline` (E18-R01 verification, `docs/reviews/e18-r01-emulator-verify-report.md`):

| | ±6 semitones (as built r70) | ±3 semitones (now) |
|---|---|---|
| correct top label | 4/7 | **7/7** |
| `confirmed` (past the presence gate) | 4/7 | **7/7** |
| open E (third G#3 at 0.12 vs fifth B2 at 0.97) | `Bsus4` | `E` |
| open G (`x20033`, no low G2) | `Bm` / `Dsus4` | `G` |
| D major | `D`, but never confirms | `D`, confirms |

`Bsus4` and `Dsus4` are not random errors: both are profiles built wholly on the
true chord's loud root and fifth, with its own third invisible. That is the same
class of failure that got power-5 and sus2 excluded from the vocabulary in round
26 — a `[root, fifth]` profile has no third to contradict, so it steals any
triad whose third is quiet — except **sus4 rooted on the fifth re-creates it**,
because `Xsus4 = {X, X+5, X+7}` with X = the triad's fifth is
`{fifth, root, second}`, and that second is also exactly where the fifth's own
3rd harmonic lands. (Confirmed on the E recording: F#4 = 0.19 while **F#3 =
0.00** — F#4 is 370 Hz, B2's exact 3rd harmonic, with no fundamental of its
own.)

### The span is bounded from BOTH sides — same mechanism, two registers

The narrowing that lifts a quiet third also **erodes the root's natural level
dominance**, and the bass chroma has nothing else with which to name the root.
Round 70 saw the same effect from the exponent side ("full whitening erodes the
ROOT's natural dominance"); it is reachable from the span side too:

| effective half-window | real 7 correct / confirmed | `dsp_property_test.dart`, seeds 42/7/123/2026/31337 |
|---|---|---|
| 7 bins (±2.2, ±2.4) | 7/7 / 7/7 | **FAIL on 4 of 5** |
| 8 bins (±2.5 … ±2.8) | 7/7 / 7/7 | green |
| **9 bins (±3.0)** | **7/7 / 7/7** | **green** |
| 12 bins (±4.0) | 6/7 | green |
| 15–18 bins (±5, ±6) | 4/7 | green |

The property failures at 7 bins are low-voiced dominant 7ths collapsing onto a
**diminished triad built on their own third** — `B7` → `D#dim`, `A#7` → `Ddim`,
i.e. the chord with its root removed, which is precisely what a lost root looks
like. ±3.0 (9 bins) sits two bins above that cliff and inside the real-audio
plateau.

**±3 is also exactly what the reference uses** — read off the source in E18-R07,
and worth recording because it is independent of our measurement:

```c
// NNLSBase.cpp:368
// make hamming window of length 1/2 octave
int hamwinlength = nBPS * 6 + 1;   // = 19 bins = 6 semitones TOTAL, i.e. ±3
```

Our constant had been `whiteningHalfWindow = 18 // ±half octave at 3
bins/semitone` — 18 bins as the HALF window. The reference's "half octave" is
the TOTAL window; reading it as a half-window and doubling it is the whole bug.

**The lower bound was lifted afterwards** by depth-weighted register windows
(E18-R07, section below): low dom7s survive ±1.5 once the root is named by
REGISTER rather than by loudness. The span still stays at ±3 — the reference's
own value, and narrower than that would be overfitting on this evidence.

The round-70 envelope gates (thin mic, body resonance) hold across the ENTIRE
sweep, so the span was never the knob that fixed the thin mic — the exponent
was — and the span is free to be chosen on the two criteria above.

### Process notes worth keeping

- The constant used to be stored as a BIN COUNT (`whiteningHalfWindow = 18`,
  "half octave at 3 bins/semitone"), which silently couples it to
  `binsPerSemitone`. That produced a wrong diagnosis first: a
  `binsPerSemitone: 5` experiment took the set 5/7 → 7/7 and looked like a
  resolution win, when it was only narrowing the span to ±3.6 semitones. The
  control — bins 5 with the span HELD at ±6 (30 bins) — scored 5/7, so
  resolution contributes nothing. It is stored in semitones now.
- **The synthetic model did not reproduce the failure at first**, and that was
  informative rather than a dead end: a flat 1/h harmonic series decoded the
  open E correctly at every span. The reproduction needed the real *level*
  asymmetry — the third swept down against a doubled fifth — which is what
  identified the mechanism.
- **The synthetic harness is a non-monotone probe of the span, so it carries
  only ONE of the shipped cases.** Measured recovery floor (quietest third still
  correct): open E 0.12 at ±6 → 0.08 at ±3; open G 0.30 at ±6 → 0.30 at ±3 (and
  correct at NO third level at ±4); open Am 0.12 at ±6 → 0.22 at ±3. An open G
  that works at 0.30 on both sides of a span where it works nowhere is a signal
  sitting on a decision boundary, not a smooth measure. `spectral_whitening_test.dart`
  therefore keeps exactly one audio-free reproduction (open E at a 0.08 third:
  not `E` at ±6, `E` at ±3) and otherwise asserts non-regression. The evidence
  for the improvement is the real recordings.
- **Measured cost:** the synthetic open Am loses the 0.12–0.16 band to `Esus4` —
  a profile on its own fifth, the same failure class this change fixes elsewhere.
  Open Em and open Dm are correct at every third level on BOTH spans, so this is
  not a systematic minor-chord regression, but all seven real recordings are
  MAJOR — minors are unverified on real audio.
- **Not measurable here:** the 82-recording / 11 767-event `ml/data/klangio`
  baseline (chord accuracy 0.6707 at app commit 5ceed22d,
  `evaluation/recognition/baseline_manifest.json`) lives outside the repo, so
  that number is UNVERIFIED for the new span and must be re-run before any
  release claim.

### Exposed, not caused, by this change

The bass chroma folds everything at/below `bassMaxMidi` **without weighting by
depth**, so it says "these pitch classes are low", never "C is lower than E".
For the one fully symmetric chord quality (augmented: `{C,E,G#}` is Caug, Eaug
AND G#aug) the root therefore rests on analysis accidents — the old `Caug`
fixture voiced C3-E3-G#3 and was decided by **C 0.72 vs E 0.69**. The fixture
now voices each rotation with its root alone in the bass window and passes
across ±1…±6.

**Follow-up:** depth-weighted bass chroma. It would give the augmented root a
firm basis and also open a principled route to inversions / slash chords — an
inversion-aware bass scorer was measured offline during this round (open G:
`Bm` 0.7921 → `G` 0.8291, the other six winners unchanged) but is NOT shipped,
because the span fix made it unnecessary and bundling it would have been scope
creep.

## Register windows — the reference WEIGHTS, it does not cut (E18-R07)

Read off the reference source this round (`Chordino.cpp:412-413`,
`chromamethods.h`): the semitone spectrum is MULTIPLIED by smooth
raised-cosine register windows before folding to 12 bins. Semitone index 0 is
MIDI 21 (A0). `basswindow` is a hump over MIDI 21–57 (A0–A3) peaking near
MIDI 39 (E♭2, ~78 Hz) and reaching zero at A3; `treblewindow` spans the whole
range peaking near MIDI 62 (D4).

On guitar notes the bass window reads **E2 0.995, G2 0.944, B2 0.625, C3 0.542,
D3 0.375, E3 0.222, G3 0.056** — i.e. **E2 counts ~4.5× what E3 counts**. Our
fold used a hard `midi <= bassMaxMidi` cut that weighted all of them equally,
so the bass chroma could say "these pitch classes are low" but never "C is
lower than E". Two measured consequences, both fixed by adopting the weighting:

| | hard cut | depth-weighted |
|---|---|---|
| seven labelled recordings (offline scorer) | 7/7 correct, latch 6/7 | **7/7, latch 7/7** |
| same through the full `LivePipeline` | 7/7 | **7/7** |
| `Caug` close voicing C3-E3-G#3 | `Eaug` (bass C 0.68 / E 0.73) | **`Caug`** (bass **C 0.87 / E 0.47**) |
| low dom7 E2–B2 at a ±2 semitone whitening span | **6/8** (`A#`→`Ddim`, `B`→`D#dim`) | **8/8** |
| the same at ±1.5 | 8/8 | 8/8 |

The augmented case is the clean demonstration: `{C,E,G#}` is equally Caug, Eaug
and G#aug, so only the bass can name the root, and a 0.05 chroma difference was
doing it. The dom7 row is the important one — it is the LOWER bound that
constrained the whitening span in ADR 0540, and depth weighting lifts it,
because the root is now named by REGISTER rather than by loudness.

The span nevertheless stays at ±3 (ADR 0541 D4): that is the reference's own
value, and going below it on this round's evidence would be overfitting.

NOT adopted, deliberately: the reference's **treble** window peaks at D4 and
tapers at both ends, ours stays flat over E2–E6. Separate measurement, separate
round.

**Licence boundary:** the reference is **GPL-2+** and StrumSight is a private
app. Its code and tabulated constants are NOT copied — the published method (a
raised cosine over a stated semitone span) is reimplemented, and the reference
table was used only to CHECK the shape (the Hann form reproduces
`treblewindow` to 5e-07 and `basswindow` to 2e-02). Full comparison, including
three further divergences we have NOT taken (mean subtraction + half-wave
rectification in the whitening, the Hamming kernel, the analysis range):
`docs/research/chordino-reference-parameters-2026-09.md`.

## Batch Viterbi — AS BUILT (round 71). The chunk-012 pipeline is COMPLETE.

`ViterbiChordDecoder.decodeBatch(bass[], treble[])` — full-sequence Viterbi
with backtrace, used by Analyze (`ClipAnalyzer._chordPass`, a second pass over
the clip: NNLS chroma per hop → batch decode → merge into segments, boundaries
stamped at window centres; strums/tempo keep streaming through LivePipeline).
- Same transition model as online (uniform switch ⇒ one shared backpointer per
  frame + a per-state "stayed" bit is the whole trellis; O(T·N) time, ties
  favour staying). Per-frame renormalisation keeps long clips bounded.
- Measured win: a fast C·G·Am·F clip (0.8 s each) gave **7 segments** online —
  0.1 s transients (Am7, Fsus4) and a WRONG final label (Csus4) — vs the
  clean **4** from the global path (evidence after a frame vetoes detours).
- No-chord frames sustain the open segment when merging (timeline = spans).
- **Fixture lesson:** the old `fMajorFreqs` test voicing was F–C–F — a
  THIRDLESS power chord mislabelled F major; with no third, F vs Csus4 is
  genuinely undecidable (and power-5 is deliberately out of vocab). Synth
  chord fixtures must be real root-third-fifth triads.

## Vocabulary growth — dim/aug AS BUILT (round 78)

Added `dim [0,3,6]` and `aug [0,4,8]` (vocab now 8 qualities × 12 roots + N.C.
= **97 states**). The round-28 worry was stealing: they differ from m/maj only
in the FIFTH — the lightest, most-omitted tone. Design that made it safe:
- The altered fifth carries **0.9 weight** in the dim/aug profiles (it IS the
  distinguishing evidence; the normal 0.7 fifth weight would under-use it).
- A small **0.02 rarity bias** keeps ambiguous frames on the common triads.
- Measured pre-add misreadings: Bdim→Dm (shared D+F), Caug→E (shared E+G#).
- **Aug is pitch-class symmetric** (Caug=Eaug=G#aug): only the BASS register
  disambiguates the root; the randomized gate accepts any enharmonic root.
- Gates: deterministic Bdim/Caug + no-steal (Am/C stay themselves) + a
  randomized dim/aug property (≥16/20) + ALL prior gates unchanged — green
  across seeds 42/7/123/2026/31337 (+555/999 for the pre-add suite).

## Still open (NOT built in rounds 28/69–78)
- Grow the vocabulary further (6, 9, add9, inversions/slash) once the base is
  validated on a real guitar. Power-5/sus2 stay OUT (round-26/28 stealing).

## Expected-chord prior: additív bias → TIE-BREAK — AS BUILT (E14-R30, ADR 0593)

Round 137 added an **additive** expected-target prior:
`_delta[s] = sim[s] + (s == expected ? 0.05 : 0)`, applied EVERY frame inside
the trellis. Additive means **accumulating**: a long enough lesson could hold
the target label against audio evidence that had already overtaken it. The
only thing keeping it out of Free Play was a screen-level
`setExpectedChord(null)` convention.

**As built now:**
- `RecognitionMode { free, guided }` (`domain/recognition/recognition_mode.dart`)
  is a CONSTRUCTION-time property of the engine (`LivePipeline({mode})`,
  `RealStrumEngine({mode})`), default `free` (fail-closed).
- The only carrier is `ExpectedChordHint`, whose constructor is private and
  whose factory `ExpectedChordHint.forMode(mode, label)` returns **null** in
  free mode. `ViterbiChordDecoder.setExpected` takes that type, not a `String`
  — so in free mode there is no hint VALUE to apply, and the isolation is
  structural rather than conventional.
- **The hint never enters the trellis.** The recursion is bit-identical to a
  hint-free decoder. At READ-OUT the expected state may take over the report
  only if the frame is a genuine tie within
  `expectedTieBreakBand = 0.05` on BOTH the accumulated path score
  (`best - delta[expected]`) AND the frame's raw similarity
  (`sim[best] - sim[expected]`), and **never** against the no-chord state.
- The 0.05 value is CARRIED OVER from the deleted `expectedPrior` — the
  mechanism changed, the tuning did not.

**Honest consequence (measured by derivation, not by ear):** because the hint
is outside the trellis, a SETTLED trellis puts every follower at least
`selfBonus = 0.22` behind the leader (`gap = simLead − simFollower +
selfBonus`), far outside the 0.05 band. So the tie-break can only fire at the
start of a sequence and around a switch, where the paths really are on top of
each other. The prior is therefore **much weaker** than round 137's. Verified
tie case: with a uniform `{0,4,8}` bass+treble observation the three augmented
roots score IDENTICALLY (0.8228 each; next competitor 0.6692), and the hint
picks among exactly those three. Whether the weaker prior helps or hurts real
lesson accuracy is **UNKNOWN — not measured**.

## Onset-aligned chord TRANSITION above the stabilizer — AS BUILT (E14-R28, ADR 0594)

The decoder has been onset-aware since round 138 (`noteOnset()` scales the
self-bonus by `chordOnsetBonusScale = 0.25` for `chordOnsetBoostFrames = 2`
chord frames — "the chord changes ON the strum"). The label-stability gate
above it (`RecognitionStabilizer`, ADR 0518) did not share that premise: N
agreeing frames confirmed a displacement whenever they arrived.

Now a displacement ALSO has to land on an onset-aligned frame. The window is
**derived, not tuned**:

```
onsetAlignmentWindowSec = chordOnsetBoostSeconds        // 2 × 4096 / 44100 ≈ 0.186 s
                        + minAgreeFrames × frameEmitSeconds   // 0.066 s per emitted frame
free   = 0.186 + 3 × 0.066 = 0.384 s
guided = 0.186 + 5 × 0.066 = 0.516 s
```

The first term is the decoder's own onset-boost window; the second is the time
the gate needs to accumulate its ADR 0518 agreement (without it the window
would close before the displacement it exists to admit). `chordOnsetBoostFrames`
and `chordOnsetBonusScale` moved from the decoder's private constants into
`DspConfig` (values unchanged) so both layers read the SAME numbers.

The gate reads a NEW `LiveFrame.onsetTimeSec` (fed by
`StrumAnalyzer.lastOnsetSec`, stamped BEFORE direction classification), not
`latestStrumTime` — the latter only advances for a strum whose direction was
confirmed, so an onset the model abstained on would otherwise hold the chord
hostage.

Escape hatches, so the gate can never freeze a label: a frame with no sample
clock (`engineTimeSec < 0` or `onsetTimeSec < 0`) falls back to plain ADR
0518 agreement, and an onset older than `LiveFrame.strumHoldSec` (2 s) counts
as expired evidence and re-opens the gate. `RecognitionStabilizer.onsetHeldFrames`
counts what the gate actually cost, so transition latency is measurable.

## Chord-latch diagnostics (H3 / L2) — MEASURABLE, NOT FIXED (E14-R28, ADR 0594 D5)

The HANDOFF's H3 ("the chord latch does not engage on a Karplus–Strong
signal") names `confidence = winSim * (0.5 + 2 * margin)`: on two near-tied
templates `margin ≈ 0` → `conf ≈ 0.5 · winSim`, below `chordConfRise = 0.54`.
That was a HYPOTHESIS — nothing exposed the per-frame values.

`LivePipeline.chordLatchDiagnostics` (`ChordLatchDiagnostics`) now exposes,
per chord frame: `tonalness`, `tonalGatePassed`, `winnerLabel`,
`winnerIsNoChord`, `winSim`, `secondSim`, `margin`, `rawConfidence`,
`noChordScore`, `winSimOverNoChordFloor`, `chordConfEma`, `chordConfRise`,
`chordConfRelease`, `emaOverRise`, `belowReleaseFrames`, `chordLatched`,
`expectedTieBreakApplied`, `mode` — built ON READ from scalars the frame path
already keeps, so the real-time loop pays nothing.

`test/features/live/chord_latch_diagnostics_report_test.dart` prints these as
CSV for a deterministic Karplus–Strong chord (new
`test/support/synth.dart::karplusStrongNote/Chord/StrumPattern`, own LCG, no
`Random`) alongside the harmonic-sum reference, and **asserts no threshold at
all**. `chordConfRise`, `chordNoChordScore` and the margin formula are
UNCHANGED: the numbers come first, the retune only after them.
