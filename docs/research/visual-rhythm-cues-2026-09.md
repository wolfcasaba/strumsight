# Visual cues for rhythm and chord learning: what the evidence supports (2026-09)

Research behind `SsStrumPendulum` and the curriculum's rhythm UI. The user's brief
was explicit: look at how competitors show notes, find what helps learning
through visual cues, colour and animation, and convey the down/up direction
*realistically* ("valósághűen").

Three questions turned out to have answers that **contradicted the obvious
design**, so each is recorded with what it changed.

## 1. The animation profile: the prettier curve is the one that lost

The intuitive choice for a strumming hand is a pendulum — sinusoidal motion,
because that is what a relaxed arm does. Measurement disagrees.

A bouncing-ball synchronization study compared motion profiles: constant
velocity, **rectified sinusoid** (what the earlier Iversen and Hove studies
used), **gravity-simulated / uniformly varying velocity**, and a **sinusoidal**
control. The gravity profile's synchronization "was not poorer than
synchronization to the auditory tone sequence" — it reached auditory-metronome
accuracy, which visual metronomes normally fail to do — and against the
sinusoidal control, gravity plus movement smoothness "significantly improved
tapping stability" (p = 0.028).

**What changed:** `SsStrumPendulum.travelAt` implements **constant acceleration**
(`1 − (2u−1)²`), not a sine. Maximum speed falls exactly at the strings, zero at
the turnaround. A test samples the second derivative to pin that the acceleration
really is uniform, so a later "let's smooth this out" edit fails a cell rather
than quietly reverting to the profile that measured worse.

### The anticipation consequence

The same literature reports **negative mean asynchrony**: people tap *before* the
visual event, consistently. Trained musicians less so than non-musicians, but the
direction holds.

**What changed:** a flash at the moment of the stroke cannot be the primary cue —
there is nothing to anticipate in an instantaneous event. The pick therefore
spends a visible half-cycle *accelerating toward* the strings before every
strike, and the strike glow is decoration on top of that, not the signal itself.

### What is NOT claimed

In the measured study the ball produced **one** event per cycle, at a hard
reversal (the floor). A strumming hand produces **two** — down and up — with its
turnarounds *clear of* the strings rather than at them. Whether the profile's
advantage transfers to that shape is **open**. It is a reasoned transfer, not a
measurement, and the component's doc comment says so.

## 2. Colour coding: it works, and it is a trap

Colour-coded notation has real evidence behind it. Figurenotes — colour plus
shape, with stickers on the instrument matching the page — shows "a relatively
high level of discriminability and iconicity when compared to other notation
systems" under multilevel Bayesian models, and lowers cognitive load for
beginners.

But every source that endorses it also warns about the same failure: colour
becomes a crutch. Too many such aids "cause [learners] to become dependent on an
artificial system of musical symbols and designs rather than help the user to
learn how to read … actual musical notation". The consensus remedy is that the
colour must be **designed to be removed** — Figurenotes introduces standard
rhythmic notation *with* coloured noteheads and then takes the colour away.

**What changed, and the line this draws.** For a beginner guitar app the
dependency risk is not hypothetical: a learner who can only read our arrows has
learned our app, not the guitar. So:

- **The notation we show is the standard notation.** `↓` / `↑` for down and up,
  matching the dominant tab convention, and consistent with the classical `⊓` /
  `V` marks, whose logic is that *the open end points the way you strum*. What a
  learner reads here transfers to real tab.
- **Colour never carries musical meaning.** It carries the *app's confidence* —
  whether the recogniser confirmed what it heard. That has no counterpart in
  notation, so removing every colour loses no musical information. Direction is
  carried by **shape**: the pick's tip leads its travel, and `SsStrumGlyph`
  already encodes confidence in shape as well as tint.
- **Shape survives reduced motion.** Under reduced motion the pick parks on the
  strings but still points the way the hand is going, so the information is
  preserved while the travel is removed (ADR 0274 §5.1).

## 3. Red/green feedback merges for common colour blindness

The grading palette was chosen before this research and survives it, but the
reason is worth recording. Red-and-green "traffic light" feedback is the classic
accessibility failure: under the most common colour-vision deficiency both can
read as the same yellowish tone. The Okabe–Ito safe palette's most reliable
hues are blue and orange.

**What this confirms, and what it adds:**

- The grading states stay **green / amber / grey**, with **no red at all** — red
  is reserved for actual errors, and a wrong strum direction is not an error, it
  is the thing being taught.
- The app's brand is copper/orange, which is on the safe side of that palette.
- **Colour alone is never sufficient**, so every state also carries a word or a
  shape: "szól, tisztán" next to a green chord lane, a dashed outline for
  unconfirmed, and the pick's own geometry for direction.

## 4. Competitor survey

| app | how notes are shown | what it cannot show |
|---|---|---|
| Yousician | a ball arcing between notes over a virtual fretboard; the arc's length encodes the gap to the next note | **direction** — the same arc serves a downstroke and an upstroke |
| Rocksmith / Rocksmith+ | a 3D note highway approaching the player, with `D`/`U` letters on strummed sections | direction only as a letter to read, not as motion; depth cues are weak on a phone |
| Fender Play, Ultimate Guitar | static `↓`/`↑` arrow rows under the chord name | no timing cue at all beyond the count |

**What was taken:** the arrow convention, and the marker-approaches-a-target
shape that every rhythm game uses.

**What was rejected:** the approaching 3D highway (depth perception on a small
screen, and it pulls the eye away from the hand), and score-loss feedback — this
curriculum has no "miss", because a mission cannot fail.

**What was added, because nothing surveyed has it:** the axis is turned ninety
degrees. The marker crosses a horizontal band of strings, and its *direction of
travel is the content*, rather than a letter printed next to a timing cue.

## Sources

Motion, timing and anticipation:

- [Synchronization to a bouncing ball with a realistic motion trajectory](https://pmc.ncbi.nlm.nih.gov/articles/PMC4493690/)
- [Rhythmic tapping to a moving beat: motion kinematics overrules natural gravity](https://pmc.ncbi.nlm.nih.gov/articles/PMC10517406/)
- [Moving stimuli facilitate synchronization but not temporal perception](https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2016.01798/full)
- [Visual enhancement of auditory beat perception across auditory interference levels](https://www.sciencedirect.com/science/article/abs/pii/S0278262614000864)

Colour and shape notation:

- [Kivijärvi — Applicability of an applied music notation system: a case study of Figurenotes](https://journals.sagepub.com/doi/full/10.1177/0255761419845475)
- [Figurenotes — progression, and removing the colour](https://figurenotes.org/progression/)
- [Kuo & Chuang — A proposal of a color music notation system for music beginners](https://journals.sagepub.com/doi/10.1177/0255761413489082)
- [A research on the design and use of coloured notes](https://files.eric.ed.gov/fulltext/EJ1368833.pdf)
- [Colourful Keys — how colour coding music can help struggling readers (and where it stops)](https://colourfulkeys.ie/colour-coding-music/)

Accessibility:

- [Smashing Magazine — a practical guide to designing for colourblind people](https://www.smashingmagazine.com/2024/02/designing-for-colorblindness/)
- [Nichols — Coloring for colorblindness (Okabe–Ito)](https://davidmathlogic.com/colorblind/)

Notation conventions and competitors:

- [Riffhard — how to read guitar strumming notation](https://www.riffhard.com/how-to-read-guitar-strumming-notation/)
- [Dummies — the ups and downs of strumming a guitar](https://www.dummies.com/article/academics-the-arts/music/instruments/guitar/the-ups-and-downs-of-strumming-a-guitar-197991/)
- [TapSmart — Yousician review](https://www.tapsmart.com/apps/review-yousician-guitar-gamifies-learning-chords-and-riffs/)
- [Ubisoft — how to read guitar tabs (Rocksmith)](https://www.ubisoft.com/en-us/game/rocksmith/plus/news-updates/1V6XdxTnzklbTyNPylnpw7/how-to-read-guitar-tabs)
- [Game Developer — coding to the beat: under the hood of a rhythm game](https://www.gamedeveloper.com/audio/coding-to-the-beat---under-the-hood-of-a-rhythm-game-in-unity)
