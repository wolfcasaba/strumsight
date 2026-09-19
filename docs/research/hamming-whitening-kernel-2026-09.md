# The Hamming whitening kernel, measured (E18-R10)

> **LICENCE — a hard boundary.** The reference implementation (`c4dm/nnls-chroma`)
> is **GPL-2+**; StrumSight is a private app (`publish_to: 'none'`) with no
> GPL-compatible licence. This round implements the *published method* — a
> normalised Hamming-weighted running mean and running standard deviation — from
> the textbook window definition `0.54 - 0.46*cos(2*pi*i/(N-1))`, derived in our
> own code. **No reference source, comment or tabulated constant was copied into
> this repository.** The reference arithmetic was read only as the prose already
> carried by `docs/research/chordino-reference-parameters-2026-09.md` §4. See
> `test/tooling/reference_model_licence_guard_test.dart`.

## What was tried, and why it was plausible

`docs/research/real-audio-hearing-probe-2026-09.md` §5 ended E18-R09 with a
measured negative result: the reference's **mean subtraction + half-wave
rectification** (`whiteningMeanCoefficient`, 0 = ours, 1 = the reference) helps
hard real audio a great deal, and at k ≥ 0.15 it loses a **quiet major third** —
an open E whose third sits at 0.08 of the peak reads as `Em`. Major-for-minor is
the worst error this app can make, because E/Em and A/Am are the chords the
beginner course teaches. The dial shipped at 0.

That write-up named this round's hypothesis itself:

> "The costs all trace to half-wave rectification discarding weak-but-real
> energy, so the candidates are the differences NOT yet tried: the reference's
> **Hamming-weighted kernel** in place of our flat box (a weighted mean treats a
> distant neighbour as less relevant, which is exactly what a hard box gets wrong
> at a peak's edge) …"

The mechanism, stated before measuring: our whitening normalises each
log-frequency bin against a **flat box** over ±3 semitones (9 bins either side,
19 taps at 3 bins per semitone). A box counts the bin three semitones away
exactly as much as the bin next door. At the **edge of a loud peak** that drags
the local mean up with energy that is musically elsewhere — and the edge of a
loud peak is precisely where a guitar's quiet third lives, because the fifth is
doubled across two or three strings while the third is fretted exactly once. A
Hamming-weighted mean discounts the distant neighbour (the furthest tap counts
12.5× less than the centre), so the mean in a peak's skirt is lower and a quiet
third should survive a subtraction that a box kills.

## Method

`whiteningHammingKernel` (default `false` — today's shipped flat box), covering
**both** whitening paths:

- the plain running-RMS divide (`whiteningMeanCoefficient == 0`), and
- the mean-subtracting local-contrast form (`> 0`), where it weights both the
  running mean and the running standard deviation.

Both paths, deliberately: the kernel is a statement about what "local" means, and
applying it to only one path would make the two paths disagree about the same
question. Measuring it on both also turned out to matter — the kernel changes the
divide-only path's behaviour on its own, at k = 0 (see "what it buys").

**Edges are re-normalised by the in-bounds weight sum**, not zero-padded. Zero
padding would let the taps hanging off the end of the axis count as *measured
silence*, so the first and last 9 bins would report a local level pulled toward
zero and come out of whitening several times too loud — a fabricated peak at each
end of the log-frequency axis, which is where the guitar's lowest fundamental
(E2, bin 0) sits. Dividing by the weight that is actually in bounds says "there
is less evidence here", which is the truth, and it is the reference's convention
for the same operator. `spectral_whitening_test.dart` and `dsp_property_test.dart`
both pin it: the weights sum to 1 at every bin including the edges, and a
constant spectrum whitens constant everywhere.

Prefix sums do not work for a weighted kernel, so the Hamming form is a direct
convolution. The in-bounds weight *sum* stays O(1) from a running prefix of the
weights themselves.

Exponent `whiteningExponent` was plumbed through `LivePipeline` the same way, so
the exponent and the kernel could be swept on the same axis — E18-R09 found the
two interacting (with the box kernel only w = 1.0 preserved the third at k > 0).

## Measurement 1 — the quiet third, the blocker

`test/tooling/whitening_mean_coefficient_sweep_test.dart`, the `CLIFF` test. The
open-E voicing and the direct `NnlsChroma` + `ViterbiChordDecoder` path are the
shipped fixture's own, so this is the same number that guards shipped behaviour.
Decoded label at each mean coefficient:

```
kernel=box  w=0.7
  third     0.00   0.05   0.10   0.15   0.20   0.25   0.35   0.50   0.75   1.00
  0.08       E      E      E     Em     Em     Em     Em     Em     Em     Em
  0.12       E      E      E      E      E      E      E      E     Em     Em
  0.20       E      E      E      E      E      E      E      E      E      E
kernel=box  w=1.0
  0.08       E      E      E      E      E      E     Em     Em     Em     Em
  0.12       E      E      E      E      E      E      E      E      E     Em
  0.20       E      E      E      E      E      E      E      E      E      E
kernel=hamming  w=0.7
  0.08       E      E      E      E      E      E      E      E      E      E
  0.12       E      E      E      E      E      E      E      E      E      E
  0.20       E      E      E      E      E      E      E      E      E      E
kernel=hamming  w=1.0
  0.08       E      E      E      E      E      E      E      E      E      E
  0.12       E      E      E      E      E      E      E      E      E      E
  0.20       E      E      E      E      E      E      E      E      E      E
```

**The cliff was located, not assumed.** With the Hamming kernel there is no
cliff anywhere in k ∈ [0, 1] at any of the three third levels, so the axis was
pushed down in *third level* until it broke:

```
                       k=0.00  k=0.25  k=0.50  k=0.75  k=1.00
box      third 0.08        E      Em      Em      Em      Em
box      third 0.04       Em      Em      Em      Em      Em
hamming  third 0.08         E       E       E       E       E
hamming  third 0.04         E       E       E       E      Em
hamming  third 0.02        Em      Em      Em      Em      Em
```

So the quiet-third cliff with the Hamming kernel sits **between a third level of
0.04 and 0.02 for k ≤ 0.75, and between 0.08 and 0.04 at k = 1.0** — against the
box kernel's floor of 0.08 at k = 0 and 0.12 at k ≥ 0.15. The weighted kernel
roughly **halves the third level the engine needs** in order to name a major
chord correctly, and it does so *at k = 0 too*, i.e. the kernel buys something
before any mean is subtracted at all.

**It is not a major bias.** The obvious way to "pass" this measurement wrongly is
to tilt the engine toward major thirds, so the inverse was measured on the same
grid: an open Em stays `Em` at every third down to 0.04 and every k up to 1.0, an
open Am never reads `A`, a genuine `Dsus4` stays `Dsus4` and a genuine `A7` stays
`A7`. `dsp_property_test.dart` re-checks this on randomized triads with quiet
thirds at the full k = 1.0 and holds parallel-swap errors at **zero** on seeds 42,
7, 123, 2026 and 31337.

## Measurement 2 and 3 — modelled chords and real recordings

Seven modelled chords (Karplus-Strong from the app's own `ChordShapes`) with
exact ground truth, through the real `LivePipeline`; ten third-party stock guitar
loops (not in the repo — only these measurements are written down). `named` is
confirmed named frames summed over the ten files; `sus4+aug` is the mean
per-file share of named frames with those qualities; `Bm`/`Fm` are the share of
named frames IN KEY for the two files whose filename states a key, with the
in-key/named counts, because a rounded percentage can hide a regression and a
higher share of fewer frames is not obviously better.

| kernel | w | k | quiet 3rd | modelled | named | sus4+aug | B minor in key | F minor in key |
|---|---|---|---|---|---|---|---|---|
| box | 0.70 | 0.00 **(shipped)** | **E** | 7/7 | 1134 | 43.6 % | 81.8 % [45/55] | **silent** |
| box | 0.70 | 0.25 | `Em` | 7/7 | 1299 | 44.4 % | 85.5 % [47/55] | 83.3 % [135/162] |
| box | 0.70 | 0.50 | `Em` | 7/7 | 1472 | 37.7 % | 72.0 % [72/100] | 84.6 % [137/162] |
| box | 0.70 | 0.75 | `Em` | 7/7 | 1530 | 35.8 % | 71.3 % [72/101] | 87.7 % [136/155] |
| box | 0.70 | 1.00 | `Em` | 7/7 | 1445 | 36.0 % | 75.8 % [50/66] | 90.2 % [101/112] |
| box | 1.00 | 0.00 | **E** | 7/7 | 995 | 25.9 % | 69.2 % [63/91] | silent |
| box | 1.00 | 0.25 | **E** | 7/7 | 1184 | 28.7 % | 69.1 % [65/94] | 54.7 % [35/64] |
| box | 1.00 | 0.50 | `Em` | 7/7 | 1238 | 27.1 % | 64.0 % [64/100] | 74.0 % [74/100] |
| box | 1.00 | 0.75 | `Em` | 7/7 | 1381 | 20.0 % | 64.4 % [65/101] | 79.0 % [83/105] |
| box | 1.00 | 1.00 | `Em` | 7/7 | 1432 | 30.3 % | 68.6 % [70/102] | 80.3 % [49/61] |
| hamming | 0.70 | 0.00 | **E** | 7/7 | 1064 | 33.8 % | 83.7 % [41/49] | silent |
| hamming | 0.70 | 0.05 | **E** | 7/7 | 1127 | 34.6 % | 83.7 % [41/49] | 93.3 % [56/60] |
| hamming | 0.70 | 0.10 | **E** | 7/7 | 1131 | 34.5 % | 83.7 % [41/49] | 93.3 % [56/60] |
| hamming | 0.70 | 0.15 | **E** | 7/7 | 1135 | 34.5 % | 84.3 % [43/51] | 93.3 % [56/60] |
| hamming | 0.70 | **0.20** | **E** | 7/7 | **1207** | 43.1 % | **86.3 % [44/51]** | **93.3 % [56/60]** |
| hamming | 0.70 | 0.25 | **E** | 7/7 | 1218 | 42.9 % | 81.8 % [45/55] | 93.3 % [56/60] |
| hamming | 0.70 | 0.30 | **E** | 7/7 | 1224 | 42.7 % | 81.8 % [45/55] | 88.7 % [55/62] |
| hamming | 0.70 | 0.35 | **E** | 7/7 | 1317 | 43.0 % | 81.8 % [45/55] | 87.7 % [135/154] |
| hamming | 0.70 | 0.40 | **E** | 7/7 | 1318 | 42.9 % | 81.8 % [45/55] | 87.7 % [136/155] |
| hamming | 0.70 | 0.50 | **E** | 7/7 | 1383 | 40.1 % | 73.5 % [75/102] | 87.9 % [138/157] |
| hamming | 0.70 | 0.60 | **E** | 7/7 | 1468 | 36.0 % | 74.5 % [79/106] | 86.1 % [130/151] |
| hamming | 0.70 | 0.75 | **E** | 7/7 | 1541 | 35.2 % | 75.2 % [82/109] | 84.5 % [131/155] |
| hamming | 0.70 | 1.00 | **E** | 7/7 | 1509 | 35.7 % | 77.1 % [84/109] | 93.7 % [119/127] |
| hamming | 1.00 | 0.00 | **E** | 7/7 | 859 | 23.8 % | silent | silent |
| hamming | 1.00 | 0.25 | **E** | 7/7 | 1012 | 25.5 % | 70.7 % [53/75] | silent |
| hamming | 1.00 | 0.50 | **E** | 7/7 | 1101 | 24.3 % | 75.3 % [70/93] | 70.0 % [7/10] |
| hamming | 1.00 | 0.75 | **E** | 7/7 | 1305 | 23.4 % | 70.6 % [77/109] | 77.8 % [112/144] |
| hamming | 1.00 | 1.00 | **E** | 7/7 | 1535 | 31.1 % | 72.5 % [79/109] | 84.7 % [122/144] |

Modelled chords stayed **7/7 at every one of the 28 grid points**.

### Per-frame cost — measured, because this is the live audio path

`test/tooling/whitening_kernel_benchmark_test.dart`. 147 log-frequency bins, 19
taps; the frame budget is one `nnlsHop` of wall clock (4096 samples at 44.1 kHz
= **92 880 µs**), and whitening is one stage inside it.

| path | kernel | µs/frame | share of the frame budget |
|---|---|---|---|
| divide-only | box | 8.89 | 0.010 % |
| divide-only | Hamming | 21.09 | 0.023 % |
| mean-subtract (k = 0.2) | box | 4.89 | 0.005 % |
| mean-subtract (k = 0.2) | Hamming | 16.67 | 0.018 % |

The Hamming kernel costs **~2.4× the box** (+12 µs/frame worst case) and
consumes **0.023 % of the frame budget**. It is not a real-time concern. (The
mean-subtracting path is *cheaper* than divide-only because half-wave
rectification zeroes many bins and skips their `pow`.) These are host JIT numbers
— see "what this does not establish".

## What it buys

1. **The E18-R09 blocker is gone.** The quiet third survives the full reference
   mean subtraction. The cliff moves from k = 0.15 (box) to nowhere in [0, 1]
   (Hamming), and in third-level terms from 0.08 to 0.04.
2. **The F minor file is heard.** Silent across 12.7 s at shipped; 60 named
   frames at hamming/k ≥ 0.05, **93 % of them in the labelled key**, naming the
   tonic `Fm7` (20 frames) — and unlike the box's version of this win, it costs
   no major-for-minor error.
3. **B minor in key improves** rather than degrading: 86.3 % at hamming/k = 0.20
   against 81.8 % shipped.
4. **More named frames**: 1207 vs 1134 at k = 0.20 (+6.4 %), up to 1541 at
   k = 0.75.
5. **The kernel helps on its own, at k = 0.** It also lifts the lower bound ADR
   0540 put on the whitening span: at a ±2 semitone span the depth-blind bass
   fold loses low dominant 7ths to a diminished triad on their own third with
   the box kernel, and with the Hamming kernel it loses **none**. Same mechanism
   as the quiet third — a weighted kernel does not equalise peak levels as hard,
   so the root keeps its dominance.

## What it costs

1. **The `sus4`/`aug` over-reporting is NOT fixed.** At the best candidate it
   moves 43.6 % → 43.1 %, half a point. That was the hypothesis that started
   this whole line of work in the probe doc, and the kernel does not address it.
2. **The apparent big sus4 win at k ≤ 0.15 is an artefact, and was caught.** The
   33.8–34.6 % figures look like a 9-point improvement; the per-file probe shows
   why — `electric-guitar-phrase` (71 named frames at shipped, dominated by
   `Dsus4:62`) **goes silent** at k ≤ 0.15 and returns at k = 0.20. The share
   improved because the sus4-heavy file stopped being heard, not because the
   engine stopped over-reporting sus4. The total `named` column hides it
   (1135 ≈ 1134) because other files gained in the same step.
3. **Two existing DSP assertions flip at the candidate setting**, and both are
   the "what changed" half of a historical claim rather than an accuracy
   regression:
   - `register_windows_test.dart` — "depth weighting holds the root when the
     whitening span is narrowed" asserts `blindLosses > 0`, i.e. that the
     depth-blind fold *must still* lose a low dominant 7th at a ±2 span. With
     the Hamming kernel it loses none, so the contrast the test documents no
     longer reproduces. Caused by the **kernel alone**, verified at k = 0.
   - `spectral_whitening_test.dart` — "the SHIPPED kernel is the flat box", which
     fails by construction if the default changes.

   Everything else is green at the candidate setting: `test/features/live/`
   (499 of 501 passing, those 2 failing), `test/property/dsp_property_test.dart`,
   `test/features/analyze/`, `live_chord_wav_probe_test.dart`,
   `real_audio_dsp_baseline_test.dart`.
4. **Thin margins on two of the four real-audio criteria.** At k = 0.20 the
   sus4+aug gain is 0.5 points, and B minor's share rises while its *named* count
   falls (51 vs 55, 44 in-key vs 45) — the share improved partly by dropping
   out-of-key frames rather than by naming more in-key ones. On 51 frames that is
   a small sample.
5. **w = 1.0 is worse on this axis, again.** The Hamming kernel at w = 1.0 names
   fewer frames and silences the B minor file entirely at k = 0. The exponent
   question from E18-R09 is answered negatively for the Hamming kernel too:
   w = 0.7 stays the better value.

## Verdict

**The hypothesis is confirmed on its own terms, and the win condition as written
is not strictly met.**

Confirmed: the Hamming kernel does move the quiet-third cliff, for the reason
predicted, and it does so enough to keep the E18-R09 real-audio gains without the
major-for-minor error. That is the first setting in this campaign where the
F minor file is heard *and* the quiet third survives.

Not strictly met: the win condition required the full DSP suite to pass at the
candidate setting, and two assertions flip there (§"what it costs" 3). Neither is
a quality regression — both are fixtures asserting that an OLD failure mode still
reproduces, and the kernel fixes those failure modes too — but rewriting a test
to make a change green is exactly the move this repo does not make casually, and
the honest statement is that the gate is not met as specified.

**So the defaults stay at today's shipped behaviour** (`whiteningHammingKernel:
false`, `whiteningMeanCoefficient: 0.0`), the flag and the harness stay in the
tree, and the shipping decision is the maintainer's, not this round's. What it
would take to flip the default is specific and small: rewrite those two contrast
assertions to state the new truth (the Hamming kernel removes the ±2-span root
erosion; the default kernel is Hamming), and accept that the `sus4`/`aug`
question is still open.

The candidate setting, if it is ever taken, is **`whiteningHammingKernel: true`,
`whiteningMeanCoefficient: 0.20`, `whiteningExponent: 0.70`**.

## What this does not establish

- **No per-chord ground truth on real audio.** The ten loops carry only key and
  tempo in their filenames, so none of the real-audio numbers is a chord-accuracy
  figure. `named`, `sus4+aug` and the in-key shares are behavioural indicators,
  not accuracy.
- **The cost numbers are host JIT wall clock.** On-device AOT ARM per-frame cost
  was **not measured**; the ratio (~2.4×) and the order of magnitude (tens of
  microseconds against a 92.9 ms budget) are what carries, not the absolute
  figures.
- **No real-guitar A/B.** ADR 0539 D4 / E18-R05 remains open, and so does the
  82-recording corpus baseline, which lives outside the repo. Every "quiet third"
  result here is a synthetic voicing at reference-recording levels.
- **The `sus4`/`aug` hypothesis is still untested as such**, because there is no
  chord ground truth for the files it was raised on.
- **Only one whitening span was swept.** ±3 semitones throughout; the kernel
  change plausibly shifts the span's optimum (finding 5 above is evidence that
  it does) and that was not explored.
- **The soft-floor rectifier** — the other candidate named in the probe doc §5 —
  is a separate round (E18-R11) and is not measured here.
