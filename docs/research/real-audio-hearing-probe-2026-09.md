# What the engine hears in real recordings (2026-09)

First measurement of this project's recogniser against real, third-party guitar
audio outside its own corpus. Ten stock loops supplied by the user; the
recordings are **not** committed — a licence that permits use does not permit
redistribution inside a repository — so only the measurement is written down.
Reproduce with:

```bash
REAL_AUDIO_DIR=/path/to/wavs flutter test \
  test/tooling/real_audio_hearing_probe_test.dart
```

## What could honestly be measured

Stock loops carry only the ground truth in their filename:

- **Tempo.** Three files state "120 bpm". That is real, checkable ground truth on
  real audio — the first this project has had for tempo outside its own corpus.
- **Key.** Two state a key ("b-minor", "f-minor"). A key is not a chord: a sample
  in B minor plays a progression, so "did it output Bm" is the wrong question.
  The right one is whether the reported chords belong to that key.

Everything else is an observation, not a grade. Most of these are produced loops
— layered guitars, effects, sometimes a full band — while the app's target is one
guitar into a phone microphone.

## 1. Tempo: two of three on the labelled pulse, within 1%

| file | labelled | engine | error |
|---|---|---|---|
| midwest-emo b-minor | 120 | 118.7 | **1.0 %** |
| dark-guitar-intro | 120 | 119.3 | **0.6 %** |
| midwest-emo f-minor | 120 | 134.5 | 12.0 % (not a metrical level either) |

Half- and double-time are named rather than counted as errors, because they are
musically correct readings of the same pulse — the repo's own tempo metric treats
metrical levels the same way. The third file is off by an amount that is not a
metrical relationship, and it is the same file that fails everything else below.

## 2. Key: 82% of named frames in key

On the B minor sample the decoder reported `Gmaj7`, `Dmaj7`, `G`, `D` — all
diatonic to B minor (VI, III with their sevenths) — and **82 %** of all named
frames were in key.

**A correction to this measurement, not to the engine.** The first version of
this probe scored 42 %, because its in-key set listed triads only and therefore
counted a correctly named `Gmaj7` as out of key. The measurement was wrong, not
the recogniser. The set now includes the diatonic sevenths.

## 3. The silent file, explained by the engine itself

The F minor sample produced **zero** confirmed chords across 12.7 s. That looked
like the worst result in the set, and it is the most reassuring one:

```
decisions: rejected:95  uncertain:86  confirmed:0
rejects:   lowConfidence:86  signalQuality:84  noChord:11
```

The engine does not fabricate a chord. It says, in typed reasons, that it is not
confident and that the signal is not good enough. Two hypotheses were tested and
**rejected** before accepting that:

- *Is it just single notes?* No. A chromagram puts both files at a median of 3
  strong pitch classes at once; the F minor file is if anything MORE polyphonic
  (61 % of frames with ≥3 against 53 %).
- *Is it detuned?* No. Median deviation from equal temperament is +4.3 cents,
  against +0.5 for the file that decodes well.

So the silence is a sensitivity limit on heavily produced material, surfaced
honestly, not a lie. For the curriculum this is the designed behaviour: the
learner would see the level meter, and no false claim would be made.

## 4. Two things to carry forward

**`signalQuality` rejections are common on real produced audio** — 17, 58, 75 and
84 frames across four files, on material whose peak level is 0.69-0.86. If a
learner's guitar through a phone microphone lands in the same region, they will
meet the "I cannot hear you well" state often. Worth measuring on a real
microphone before tuning anything.

**`sus4` and `aug` are over-represented.** `Dsus4` dominates two files (62 and 52
frames), and `Daug` takes 76 frames in a third where `D`, `Dsus4` and `D7` follow
behind. Those qualities are uncommon in real music, and a triad whose third is
weak reads as a sus4 exactly this way. This is a HYPOTHESIS, not a finding —
there is no chord ground truth for these files. But it points at the already
identified, still unshipped whitening follow-up: the reference's mean subtraction
plus half-wave rectification, whose purpose is suppressing phantom partials.

## 5. The whitening follow-up, measured and NOT shipped

The `sus4`/`aug` hypothesis above was the standing reason to try the reference's
whitening arithmetic: subtract the local mean and half-wave rectify
(`Chordino.cpp:333-345`) instead of only dividing by the local level. It was
implemented, swept, and **left switched off**. The measurement is the deliverable.

The implementation is a dial, not a switch — `whiteningMeanCoefficient`, 0 = today,
1 = the reference — because the first A/B showed the answer was not binary.

### What it buys

| | named frames (10 files) | mean sus4+aug share |
|---|---|---|
| k = 0 (shipped) | 1134 | 43.6 % |
| k = 0.5 | 1472 | 37.7 % |
| k = 0.75 | **1530** | **35.8 %** |
| k = 1.0 | 1445 | 36.0 % |

And the headline case: the F minor file that named **nothing at all** across
12.7 s went to **112 confirmed frames, 90 % of them in the labelled key**,
naming the tonic `Fm7` among them. On modelled chords with exact ground truth it
stayed 7/7 at every value.

### What it costs, and why that ends it

At k ≥ 0.15 the shipped quiet-third fixture flips: an open E whose major third
sits at 0.08 of the peak reads as **`Em`**. That fixture is not decoration — it
guards the E18-R01 result that took the seven reference recordings from 4/7 to
7/7, and **major-for-minor is the worst error this app can make**, because E/Em
and A/Am are chords the beginner course teaches. A learner playing E correctly
would be told they played Em.

The cliff was located precisely rather than assumed:

```
third level          0.08   0.12   0.20
k <= 0.10             E      E      E
k = 0.15 .. 0.25     Em      E      E
k = 0.75 .. 1.0      Em     Em      E
```

A two-dimensional sweep over the exponent found exactly one combination that
keeps the quiet third while subtracting any mean at all — **w = 1.0, k = 0.25**,
the reference's own exponent — and the whole DSP suite passes there. But on real
audio it is worse than both alternatives: B minor in-key falls from 82 % to 69 %,
and one file that named 71 frames goes silent.

| setting | B minor in key | F minor in key | quiet third |
|---|---|---|---|
| w 0.7, k 0 (shipped) | **82 %** | 0 % (silent) | **E** |
| w 0.7, k 1.0 | 76 % | **90 %** | `Em` |
| w 1.0, k 0.25 | 69 % | 55 % | **E** |

**No setting dominates.** Each buys one thing by selling another, and the thing
sold at the only settings that help hard material is the one error class this app
cannot afford. So the dial ships at 0, the code and the sweep stay in the tree,
and this is written down as a measured negative result rather than a forgotten
idea.

### What would change the answer

Not another sweep of these two numbers. The costs all trace to half-wave
rectification discarding weak-but-real energy, so the candidates are the
differences NOT yet tried: the reference's **Hamming-weighted kernel** in place
of our flat box (a weighted mean treats a distant neighbour as less relevant,
which is exactly what a hard box gets wrong at a peak's edge), and a rectifier
with a soft floor rather than a hard zero. Both are separate rounds, and both
need this same three-criteria harness.

**UPDATE (E18-R11).** The soft-floor candidate was built, swept over a 2-D grid and
**rejected** — see `docs/research/soft-floor-rectifier-2026-09.md`. It also
corrects the attribution above: the quiet third's bin is *never* zeroed (it sits
above its local mean, so the rectifier never clamps it), so half-wave
rectification is not the mechanism behind that cost. The **subtraction** is — it
takes a larger relative share from a weak peak than from a loud one. That makes
the Hamming-kernel candidate the better-aimed of the two, because a weighted mean
changes *what the local mean is*.

## What this does not establish

No file here has per-chord ground truth, so nothing above is a chord-accuracy
number. The real-guitar A/B (ADR 0539 D4 / E18-R05) remains open, and so does the
82-recording corpus baseline, which lives outside the repo.

## Full output

```
farran_ez-indie-guitar-loop-sample
  13.3s | frames 190 | strums 52 (3.9/s) | peak 0.78
  chords: Gm7:70 Fsus4:47 A#sus4:29 A#:15
  decisions: confirmed:163 rejected:27 | rejects: signalQuality:17 noChord:10

midwest-emo b-minor 120bpm
  9.0s | frames 129 | strums 37 (4.1/s) | peak 0.81
  TEMPO labelled 120 | engine 118.7 | 1.0% (on the labelled pulse)
  KEY B minor: 82% of named frames in key
  chords: Gmaj7:12 Dmaj7:10 G:10 D:9
  decisions: rejected:73 confirmed:55 uncertain:1

midwest-emo f-minor 120bpm
  12.7s | frames 181 | strums 39 (3.1/s) | peak 0.86
  TEMPO labelled 120 | engine 134.5 | 12.0%
  chords: (none named)
  decisions: rejected:95 uncertain:86 | rejects: lowConfidence:86 signalQuality:84

dark-guitar-intro 120bpm
  16.1s | frames 230 | strums 56 (3.5/s) | peak 0.81
  TEMPO labelled 120 | engine 119.3 | 0.6% (on the labelled pulse)
  chords: Daug:76 D:47 Dsus4:44 D7:14

electric-guitar-phrase
  10.9s | frames 156 | strums 13 (1.2/s) | peak 0.86
  chords: Dsus4:62 D:8 Gmaj7:1

guitar-103460
  9.3s | frames 134 | strums 28 (3.0/s) | peak 0.69
  chords: Dsus4:52

emotional-guitar-loop
  22.6s | frames 324 | strums 41 (1.8/s) | peak 0.97
  chords: C:94 A#:77 Am:51 Dm:50

juice-wrld-type-guitar-loop
  7.3s | frames 104 | strums 16 (2.2/s) | peak 0.70
  chords: D:26 C:23 Cmaj7:19 Em:17

nirvana-type-guitar-loop
  16.0s | frames 230 | strums 62 (3.9/s) | peak 0.86
  chords: E:52 G:49 A:30 Bsus4:25

heavy-metal
  14.1s | frames 202 | strums 51 (3.6/s) | peak 0.80
  chords: G#sus4:24
```
