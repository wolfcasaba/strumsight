
### The fusion is INADMISSIBLE on the scoring path — it would compare the grid to itself (E18-R39, ADR 0562, supersedes ADR 0558 D1/D2)

Looking for the wiring site found `gradeRhythm` in
`lib/features/curriculum/domain/rhythm_grading.dart`, which is already the consumer and
already holds the whole contract: `DetectedStroke {atUs, direction, isConfirmed}`; `startUs`
plus `grid.onsetUs(...)` as the known-phase grid; `RhythmSlotOutcome.unclear` as abstention;
`extraConfirmedStrokes` for a stroke played where the pattern ghosts; and its library comment
states as rule 1 **"Pairing uses TIME only, never direction ... Pair by time, then judge
direction"** -- the same answer-key protection ADR 0557 D4 derived independently.

**The decisive observation.** `gradeRhythm` compares a stroke's direction against the GRID's
expected direction to produce `RhythmSlotOutcome.wrongDirection`, which the code itself calls
"the thing only this app can tell a learner". Fold the metric channel's prescription into
`DetectedStroke.direction` and the grader compares the grid to ITSELF: `wrongDirection`
collapses and the app tells every learner their strumming hand is perfect.

Measured, not feared: in ADR 0558's own table, on pendulum-violating strokes the fused rule
takes accuracy 0.5000 -> 0.2500 at the settled tier. Those violating strokes ARE the
`wrongDirection` cases, so fusion HALVES detection of the single finding the rhythm pillar
exists for. The number was in the table, labelled "harm on the violating subset", and not
connected to the product output.

**ADR 0558 D1 contradicted ADR 0557 D4, and the text claimed they coincided.** D4: the metric
channel "may move the abstention bar; it may never flip the call". D1's tie-break rule: "the
metric call decides below t" -- i.e. it flips. The `c* = 0.000` measurement is real, but it
was taken on direction macro-F1 against truth, a metric that cannot ASK whether the grader
can still detect a pattern violation. L670 in its strongest form: the axis measured was the
one to improve, not the one the failure moves cost onto.

**The arrow use falls too (ADR 0558 D2 superseded).** A fused arrow beside an acoustic-only
grader contradicts itself on exactly the violating strokes: the learner sees the arrow the
pattern asked for, then reads after the bar that they strummed the other way -- ADR 0556 D2's
prohibition, in reverse.

**What the channel was going to add, and already exists:** disagreement as pedagogical output
= `wrongDirection`; abstention = `unclear`; the ghost-slot stroke = `extraConfirmedStrokes`;
answer-key protection = pairing by time only; known-phase grid = `startUs` + `onsetUs`.

**What survives for `StrumMetricChannel`:** it is a measurement instrument (the Dart twin of
`ml/probe_direction_metric.py`, pinned by a parity fixture) and a candidate basis for choosing
which recorded sessions to collect -- sessions where the two channels disagree are where the
scarce pendulum-violating strokes live. Not a learner-facing feature. It stays in the repo,
unwired, with the prohibition in its class doc.

**Consequence:** there is nothing left to wire, so `settledTier` stays DARK -- its only
justification was the D1 fusion. ADR 0558 D3 (my "conservative" rule was worse on the fast
tier) and D4 (the 11->8 stroke bound) stand as measurements.

Not claimed: the settled tier WITHOUT fusion may still help scoring on its own -- the settled
acoustic verdict scores macro-F1 0.6061 against the fast 0.5262, with no grid involved. That
is independent of the fusion and could be a separate round, but its cost (a second model
forward per strum) still needs a profile-build measurement.
