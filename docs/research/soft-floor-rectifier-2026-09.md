# A soft floor instead of a hard zero (E18-R11) — measured, and NOT shipped

Follow-up to §5 of `docs/research/real-audio-hearing-probe-2026-09.md`, which ended
with two named candidates and this reasoning:

> The costs all trace to **half-wave rectification discarding weak-but-real
> energy**, so the candidates are the differences NOT yet tried: the reference's
> Hamming-weighted kernel in place of our flat box, and **a rectifier with a soft
> floor rather than a hard zero**.

This round took the second candidate. The hypothesis was that a quiet major third
sitting below its local mean is weak-but-real energy, that the hard zero destroys
it, and that flooring the rectifier would keep the third while still suppressing
the phantom partials mean subtraction exists to remove.

**The hypothesis is false, and it is false at the first step.** The quiet third's
bin is never zeroed. It sits *above* its local mean, so the rectifier never
clamps it; what shrinks it is the **subtraction itself**, which removes a larger
relative share from a weak peak than from a loud one. A floor on a clamp that
never fires cannot help, and the full grid below shows exactly that.

Reproduce with:

```bash
REAL_AUDIO_DIR=/path/to/wavs flutter test \
  test/tooling/whitening_spectral_floor_sweep_test.dart
```

## 1. The literature, and why this form rather than the other two

Half-wave rectification after subtracting a spectral estimate is not an exotic
arrangement — it *is* spectral subtraction, and its failure mode has a name.
Berouti, Schwartz & Makhoul (ICASSP 1979, *Enhancement of speech corrupted by
acoustic noise*) identified the hard zero as the source of "musical noise" —
isolated islands of spectral energy that twinkle in and out frame to frame — and
fixed it with a **spectral floor**: hold the output at a small fraction instead of
dropping it to nothing. Their rule, in the power domain,

```
|S|² = P − α·P_N          when P > (α + β)·P_N
     = β·P_N              otherwise
```

with α the over-subtraction factor and β the spectral-flooring parameter,
0 < β ≪ 1. The same idea is carried in the gain domain by essentially every
deployed suppressor as a **minimum gain** `G_min` — "maximum reduction per bin",
commonly −26 dB … −6 dB, i.e. β ≈ 0.05 … 0.5.

Three forms were on the table. The ranking below was decided *before* measuring,
on what each does to the information the NNLS stage needs:

1. **Gain-domain spectral floor, `max(d, β·s[j])` — chosen.** The floor is
   proportional to the bin's own magnitude. It is continuous (a max of two
   continuous functions), monotone, never negative, and scale-free — β is a pure
   ratio with no dependence on the frame's peak. Critically, it **preserves the
   ordering among weak bins**: a quiet-but-real third and an empty bin come out
   different, which is the entire distinction the round was about.
2. **Berouti's literal flat floor, `max(d, β·estimate)`.** Published for exactly
   this pathology, but its floor is constant across a neighbourhood, so every
   sub-mean bin collapses to the *same* value. That is right when the consumer is
   an ear being masked and wrong when the consumer is a least-squares fit that has
   to tell two weak bins apart. It would also hand NNLS a broadband pedestal to
   explain with spurious activations.
3. **Smooth rectifiers** — soft-max `(d + √(d² + ε²))/2`, softplus `T·ln(1 + e^(d/T))`.
   Smoothness for its own sake. Both add an *absolute* pedestal (ε/2, T·ln 2) with
   no scale-free meaning, so the knob would have to be rescaled with the frame
   peak, and both flatten weak bins to a constant like (2). Neither has published
   support for this pathology. Smoothness at the threshold was never the problem;
   the discarded *magnitude* was.

No reference source was read or copied. The Chordino reference is GPL-2+ and this
repo has no GPL-compatible licence; the spectral-floor lineage is a separate one
and is implemented from the published formula.

## 2. The implementation

`whiteningSpectralFloor` (β) on `NnlsChroma`, plumbed through `LivePipeline` the
same way `whiteningMeanCoefficient` is. Default **0.0 = today's hard zero**, and
`max(d, 0)` is that hard zero bit-for-bit, which is asserted rather than asserted
about (`test/features/live/dsp/whitening_spectral_floor_test.dart`). The dial is
unreachable on the shipped divide-only path by construction: it lives inside the
branch that only runs when `whiteningMeanCoefficient > 0`.

Non-negativity is not a courtesy. The NNLS stage warm-starts at `Dᵀs` and then
applies multiplicative updates `x ← x·(Dᵀs)/(DᵀD·x + ε)`; the dictionary columns
are non-negative, so a negative `_s[j]` would make `Dᵀs` negative and flip an
activation's sign on every iteration. `max(d, β·s)` with β ≥ 0 and s ≥ 0 cannot
produce one. Verified in the code, not taken on trust, and guarded by both the
fixture and the property suite.

Two diagnostics were added, because a marginal result has two very different
explanations that look identical from the decoded labels: the share of bins the
floor **rescued** from the hard zero, and the share still **zeroed** after it.

## 3. The grid

Shipped reference (k = 0, divide only): **quiet third `E`, modelled 7/7, named
1134, sus4+aug 43.6 %, B minor 82 % in key, F minor silent (0 %)**.

The **β = 0 column reproduces E18-R10 exactly** — 1299 / 1472 / 1530 / 1445 named
frames and 44.4 / 37.7 / 35.8 / 36.0 % colour share at k = 0.25 / 0.5 / 0.75 / 1.0,
matching §5 of the probe note digit for digit, as do its key percentages (k = 1.0:
B minor 76 %, F minor 90 %; w = 1.0, k = 0.25: 69 % and 55 %). The harness is the
same harness, literally — the stimuli now live in `test/support/whitening_sweep.dart`,
shared by both sweeps and by the real-audio probe.

### w = 0.7 (the shipped exponent)

| k | β | quiet third | modelled | named | sus4+aug | B minor in key | F minor in key | bins rescued |
|---|---|---|---|---|---|---|---|---|
| 0.25 | 0.00 | `Em` | 7/7 | 1299 | 44.4 % | 85 % | 83 % | 0 % (29.0 % zeroed) |
| 0.25 | 0.02 | `Em` | 7/7 | 1299 | 44.8 % | 82 % | 83 % | 29.0 % |
| 0.25 | 0.05 | `Em` | 7/7 | 1299 | 44.8 % | 82 % | 83 % | 29.0 % |
| 0.25 | 0.10 | `Em` | 7/7 | 1299 | 44.8 % | 82 % | 83 % | 29.0 % |
| 0.25 | 0.20 | `Em` | 7/7 | 1297 | 44.8 % | 82 % | 83 % | 29.0 % |
| 0.50 | 0.00 | `Em` | 7/7 | 1472 | 37.7 % | 72 % | 85 % | 0 % (49.5 % zeroed) |
| 0.50 | 0.02 | `Em` | 7/7 | 1472 | 37.6 % | 72 % | 85 % | 49.5 % |
| 0.50 | 0.05 | `Em` | 7/7 | 1472 | 37.6 % | 72 % | 85 % | 49.5 % |
| 0.50 | 0.10 | `Em` | 7/7 | 1473 | 37.7 % | 71 % | 85 % | 49.5 % |
| 0.50 | 0.20 | `Em` | 7/7 | 1471 | 37.7 % | 73 % | 85 % | 49.5 % |
| 0.75 | 0.00 | `Em` | 7/7 | **1530** | 35.8 % | 71 % | 88 % | 0 % (63.2 % zeroed) |
| 0.75 | 0.02 | `Em` | 7/7 | 1530 | 36.0 % | 71 % | 88 % | 63.2 % |
| 0.75 | 0.05 | `Em` | 7/7 | 1494 | 36.2 % | 71 % | 89 % | 63.2 % |
| 0.75 | 0.10 | `Em` | 7/7 | 1477 | 37.4 % | 71 % | 91 % | 63.2 % |
| 0.75 | 0.20 | `Em` | 7/7 | 1473 | 37.4 % | 73 % | 90 % | 63.2 % |
| 1.00 | 0.00 | `Em` | 7/7 | 1445 | 36.0 % | 76 % | 90 % | 0 % (72.7 % zeroed) |
| 1.00 | 0.02 | `Em` | 7/7 | 1443 | 36.2 % | 76 % | 91 % | 72.7 % |
| 1.00 | 0.05 | `Em` | 7/7 | 1443 | 36.4 % | 74 % | 91 % | 72.7 % |
| 1.00 | 0.10 | `Em` | 7/7 | 1439 | 36.4 % | 74 % | 91 % | 72.7 % |
| 1.00 | 0.20 | `Em` | 7/7 | 1416 | 36.4 % | 74 % | 92 % | 72.7 % |

### w = 1.0 (the reference exponent)

| k | β | quiet third | modelled | named | sus4+aug | B minor in key | F minor in key | bins rescued |
|---|---|---|---|---|---|---|---|---|
| 0.25 | 0.00 | **`E`** | 7/7 | 1184 | 28.7 % | 69 % | 55 % | 0 % (29.0 % zeroed) |
| 0.25 | 0.02 | **`E`** | 7/7 | 1182 | 28.8 % | 69 % | 55 % | 29.0 % |
| 0.25 | 0.05 | **`E`** | 7/7 | 1182 | 28.8 % | 69 % | 55 % | 29.0 % |
| 0.25 | 0.10 | **`E`** | 7/7 | 1182 | 28.8 % | 69 % | 55 % | 29.0 % |
| 0.25 | 0.20 | **`E`** | 7/7 | 1182 | 28.8 % | 69 % | 55 % | 29.0 % |
| 0.50 | 0.00 | `Em` | 7/7 | 1238 | 27.1 % | 64 % | 74 % | 0 % (49.5 % zeroed) |
| 0.50 | 0.02 | `Em` | 7/7 | 1235 | 27.2 % | 64 % | 73 % | 49.5 % |
| 0.50 | 0.05 | `Em` | 7/7 | 1232 | 27.2 % | 64 % | 73 % | 49.5 % |
| 0.50 | 0.10 | `Em` | 7/7 | 1230 | 27.5 % | 64 % | 73 % | 49.5 % |
| 0.50 | 0.20 | `Em` | 7/7 | 1135 | 26.3 % | 64 % | silent | 49.5 % |
| 0.75 | 0.00 | `Em` | 7/7 | 1381 | 20.0 % | 64 % | 79 % | 0 % (63.2 % zeroed) |
| 0.75 | 0.02 | `Em` | 7/7 | 1380 | 20.2 % | 64 % | 79 % | 63.2 % |
| 0.75 | 0.05 | `Em` | 7/7 | 1380 | 20.1 % | 64 % | 79 % | 63.2 % |
| 0.75 | 0.10 | `Em` | 7/7 | 1337 | 20.5 % | 64 % | 79 % | 63.2 % |
| 0.75 | 0.20 | `Em` | 7/7 | 1252 | 27.7 % | 63 % | 77 % | 63.2 % |
| 1.00 | 0.00 | `Em` | 7/7 | 1432 | 30.3 % | 69 % | 80 % | 0 % (72.7 % zeroed) |
| 1.00 | 0.02 | `Em` | 7/7 | 1450 | 30.1 % | 69 % | 81 % | 72.7 % |
| 1.00 | 0.05 | `Em` | 7/7 | 1452 | 30.2 % | 69 % | 81 % | 72.7 % |
| 1.00 | 0.10 | `Em` | 7/7 | 1377 | 21.2 % | 68 % | 81 % | 72.7 % |
| 1.00 | 0.20 | `Em` | 7/7 | 1365 | 21.5 % | 67 % | 83 % | 72.7 % |

### Beyond the published range (β > 0.2, w = 0.7)

Run because the published G_min range reaches ≈ 0.5 and because the question
"where *does* the third come back?" deserved an answer rather than an assumption.

| k | β | quiet third | named | sus4+aug | B minor | F minor |
|---|---|---|---|---|---|---|
| 0.25 | 0.60 | `Em` | 1297 | 44.9 % | 82 % | 85 % |
| 0.25 | 0.80 | `Em` | 1135 | 43.8 % | 82 % | silent |
| 0.25 | 0.90 | **`E`** | 1132 | 43.8 % | 82 % | silent |
| 0.25 | 0.95 | **`E`** | 1079 | 33.6 % | 82 % | silent |
| 0.50 | 0.30 | `Em` | 1466 | 37.9 % | 73 % | 85 % |
| 0.50 | 0.50 | `Em` | 1302 | 44.7 % | 85 % | 85 % |
| 0.50 | 0.70 | `Em` | 1097 | 35.2 % | 82 % | 91 % |
| 0.50 | 1.00 | **`E`** | 949 | 23.0 % | silent | silent |
| 0.75 | 0.30 | `Em` | 1397 | 36.1 % | 78 % | 87 % |
| 0.75 | 0.50 | `Em` | 1105 | 34.4 % | 85 % | 93 % |
| 0.75 | 0.70 | `Em` | 1067 | 33.9 % | 82 % | **100 %** |
| 0.75 | 0.80 | `Em` | 946 | 21.6 % | silent | silent |
| 0.75 | 0.90 | **`E`** | 946 | 21.1 % | silent | silent |
| 0.75 | 1.00 | **`E`** | 947 | 21.4 % | silent | silent |

The quiet third returns only at **β ≥ 0.90**, an order of magnitude above the
literature's range — and by then real audio is *below* shipped on named frames
(1132 vs 1134 at k = 0.25; 946 at k = 0.75) with the F minor file silent again. At
w = 1.0 the same cliff sits at β = 1.00, where named frames fall to 801 and 681.

That is not the floor working. At β ≈ 1 the rule `max(d, β·s)` returns `β·s` for
*almost every* bin, including loud ones, because `d = s − k·mean < β·s` whenever
`k·mean > (1 − β)·s`. The contrast operator collapses back into a plain
divide-by-σ. The third recovers because the mean subtraction has been switched
off globally, not because anything was rescued.

## 4. Why it cannot work — the mechanism, measured

The decoded label cannot distinguish "the third's bin was deleted" from "the
third's bin survived but is too light to outvote the doubled fifth". A seam was
added to read the bin itself (`debugWhitenedRelativeAt`), and it settles the round.
G#3's whitened weight, as a share of the frame's largest whitened bin, on the same
open-E stimulus (w = 0.7):

| k | β = 0 | 0.02 | 0.05 | 0.20 | 0.50 | 0.90 | 1.00 |
|---|---|---|---|---|---|---|---|
| 0.00 (shipped) | 8.566 % → `E` | 8.566 % | 8.566 % | 8.566 % | 8.566 % | 8.566 % | 8.566 % |
| 0.25 | 7.088 % → `Em` | 7.088 % | 7.088 % | 7.088 % | 7.088 % | 7.829 % → `E` | 8.539 % → `E` |
| 0.50 | 5.539 % → `Em` | 5.539 % | 5.539 % | 5.539 % | 5.539 % | 7.921 % → `E` | 8.477 % → `E` |
| 0.75 | 3.937 % → `Em` | 3.937 % | 3.937 % | 3.937 % | 4.494 % | 7.986 % → `E` | 8.384 % → `E` |
| 1.00 | 2.300 % → `Em` | 2.300 % | 2.300 % | 2.453 % | 4.462 % | 8.032 % → `E` | 8.267 % → `E` |

Three things are readable here and each one closes a door:

- **The third is never zero.** Not at any k, not even at the full reference value
  where it is down to 2.3 % of peak. The bin is above its own local mean, so the
  half-wave rectifier never touches it. The premise of this round — that the hard
  zero discards the third — is simply not what happens.
- **Across the whole published β range the weight does not move by one digit.**
  The floor is not weak here; it is *inapplicable*. It can only change bins the
  clamp fired on, and this is not one of them.
- **What actually kills the third is the subtraction.** 8.57 % → 7.09 % → 5.54 %
  → 3.94 % → 2.30 % as k rises. Subtracting `k·mean` is a fixed absolute amount
  within a neighbourhood, so it takes a far larger *relative* share from a weak
  peak than from a loud one. Mean subtraction is a contrast operator, and a quiet
  third is exactly the low-contrast feature it is designed to suppress. The
  decision boundary sits between 7.09 % (`Em`) and 7.83 % (`E`).

And the floor is not doing nothing to the spectrum generally — at k = 0.75, β as
small as 0.02 **rescues 63.2 % of all bins** (the zeroed share goes to 0.0 %), and
the decoded output barely moves: 1530 → 1530 named frames, 35.8 % → 36.0 % colour.
That is the informative negative: the floor rewrites most of the spectrum and the
decoder does not care, because the bins it rewrites are the ones that carried no
evidence in the first place. The hard zero was not throwing away anything the
decoder was using.

## 5. Verdict

**The win condition does not hold.** It required, at one setting: quiet third `E`,
modelled 7/7, the DSP suite green, *and* real audio beating shipped on all four of
more named frames, lower sus4+aug share, B minor ≥ 82 %, F minor > 0 %. No cell in
the grid does it, and the closest candidates fail for orthogonal reasons:

| candidate | quiet third | named vs 1134 | sus4+aug vs 43.6 % | B minor vs 82 % | F minor vs 0 % |
|---|---|---|---|---|---|
| w 0.7, k 0.75, β 0.10 | **`Em`** ✗ | 1477 ✓ | 37.4 % ✓ | **71 %** ✗ | 91 % ✓ |
| w 0.7, k 0.75, β 0.70 | **`Em`** ✗ | **1067** ✗ | 33.9 % ✓ | 82 % ✓ | 100 % ✓ |
| w 0.7, k 0.25, β 0.90 | `E` ✓ | **1132** ✗ | **43.8 %** ✗ | 82 % ✓ | **silent** ✗ |
| w 1.0, k 0.25, β 0.05 | `E` ✓ | 1182 ✓ | 28.8 % ✓ | **69 %** ✗ | 55 % ✓ |

The last row is the interesting near-miss, and it is the same near-miss E18-R10
already found without a floor: `w = 1.0, k = 0.25` keeps the third and helps three
of the four real-audio numbers, but drops B minor from 82 % to 69 %. **The floor
changes it by nothing at all** — 1184 → 1182 named frames across β = 0 … 0.20. If
that setting is ever shipped it will be on its own merits from E18-R10, not
because of this round.

So **the default stays at `whiteningSpectralFloor = 0.0`**, which is today's hard
zero bit-for-bit, and `whiteningMeanCoefficient` stays at 0. The dial, the sweep
and this note stay in the tree: the measurement is the deliverable.

## 6. What this changes about the remaining candidate

§5 of the probe note attributed *all* of the reference whitening's costs to
half-wave rectification. That attribution is now **measured to be wrong**, at least
for the quiet third, which is the blocking cost. The rectifier is not the
mechanism; the subtraction is. That matters for the sibling round (E18-R10's
Hamming-weighted kernel, running separately), because a weighted kernel changes
**what the local mean is** — it down-weights distant neighbours, so a peak's own
skirt contributes less to the mean it is measured against. That is an intervention
on the mechanism this round identified, rather than on the one §5 guessed at. It
is the better-aimed of the two candidates, and this round is the reason we can say
so.

What would *also* follow from the mechanism, and has not been tried: making the
subtraction **relative rather than absolute** — subtracting a share of the bin's
own magnitude, or dividing by the mean instead of subtracting it — so a weak peak
is not taxed harder than a loud one. That is a different operator, not a floor on
this one, and it needs its own round.

## 7. What this does not establish

- No file in the real-audio set has per-chord ground truth, so no number here is a
  chord-accuracy figure. The two key percentages and the named-frame counts are
  what the material supports.
- The ten recordings are produced loops — layered guitars, effects, sometimes a
  full band — while the app targets one guitar into a phone microphone. The
  real-guitar A/B (ADR 0539 D4 / E18-R05) is still open, and so is the 82-recording
  corpus baseline.
- The quiet-third criterion rests on a synthetic voicing with the levels of one
  real reference recording, not on audio. ADR 0540 already records how far that
  stimulus reaches.
- **Unmeasured:** Berouti's literal flat floor (`max(d, β·k·mean)`) was ranked
  second on reasoning and never implemented. Given that the third's bin is never
  clamped at all, no floor of any shape can move it, so the ranking was not worth
  spending a measurement to confirm — but it is an argument, not a measurement,
  and it is recorded as one.
- **Unmeasured:** the smooth rectifiers (soft-max, softplus), for the same reason.
- **Unmeasured:** β between 0.20 and 0.30, and between 0.80 and 0.90, at w = 1.0.
  The cliff was located at w = 0.7 and spot-checked at w = 1.0.
