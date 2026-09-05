# Hard-negative taxonomy and capture list (E14-R15)

This is the reading guide for the hard-negative taxonomy and the two
event-kind-scoped false-visible-event rates this round adds to the E14-R08
report (`lib/features/live/domain/evaluation/recognition_metrics.dart`,
ADR 0521). It does not repeat the report's own architecture — see
`docs/eval/recognition-dashboard.md` and
`docs/adr/0521-scoped-false-visible-event-rates-and-hard-negative-taxonomy.md`
for that.

## Why a hard-negative taxonomy

`ml/negatives.py`'s measured root cause is the reason this taxonomy exists:
confidence alone does not separate a real strum from a non-guitar sound —
the model is often just as confident on a false onset as on a true one.
Fixing that on the training side is `ml/negatives.py`'s job (out of this
round's scope). This round gives the **product** side two things: a fixed
list of the non-guitar sound sources most likely to trigger a false
onset/strum/chord, and a machine-checkable rate for how often the app
actually shows the user a wrong event of each visible kind.

## The taxonomy (`evaluation/recognition/negative_taxonomy.json`)

`evaluation/recognition/negative_taxonomy.json` names eleven categories
(schemaVersion `"1"`) — at least ten is the ADR 0521 D7 floor, checked at
parse time by
`NegativeTaxonomyParser` (`lib/features/live/domain/evaluation/negative_taxonomy.dart`):

| Category id | What it is |
|---|---|
| `speech` | Human speech/conversation near the microphone |
| `tapping` | Percussive taps on the guitar body, not a strum |
| `deskKnock` | A knuckle/object knock on the table or nearby surface |
| `pickClick` | The pick clicking without a full strum across the strings |
| `stringNoise` | String squeak/rattle from hand movement, not an intended strum |
| `fretSqueak` | Fretting-hand slide squeak between chord shapes |
| `metronome` | Audible click-track/metronome ticking |
| `backgroundMusic` | Recorded/streamed music playing in the room |
| `tv` | Television dialogue or soundtrack bleed |
| `fan` | Fan/HVAC white noise, including its on/off edges |
| `phoneHandling` | Picking up, moving or vibrating a phone near the mic |

Every category carries a `description` explaining the specific acoustic
confusion it causes — see the JSON file itself for the full text.

**Unknown category ids are a typed failure, not a catch-all.** A capture
segment naming a category the taxonomy does not have throws
`NegativeTaxonomyException(kind: unknownCategory)` — there is no `other`
bucket a mislabelled segment can silently fall into.

## The capture-segment sample (`evaluation/recognition/fixtures/negative_taxonomy_sample.json`)

This is the CI fixture: an annotation-only list of capture *segments*, each
naming one taxonomy category, a `[startMs, endMs)` interval, and a
`sourceRef` pointing at where the underlying recording actually lives.
**No raw audio is in this file or anywhere else in the repository** (ADR
0249, ADR 0521 D8) — `sourceRef` is an external pointer (e.g. an entry in a
capture log kept outside the repo), never a path the repo resolves.
`NegativeTaxonomyParser.parseSample` validates every segment's `categoryId`
against a `NegativeTaxonomy` before returning, so a fixture referencing a
category that does not exist fails the same typed way a hand-built one
would.

## The external, manual 60-minute capture workflow

The SDD Ch14 §8 target of "at least 60 minutes of hard-negative material"
is **not** met by adding audio to this repository — that would violate the
ADR 0249 boundary this round reaffirms (ADR 0521 D8). Recording real hard
negatives is a manual, repo-external workflow:

1. **Consent gate.** Any recording of speech, TV audio, or other
   identifiable sound must go through the `E14-R06` consent gate before
   capture starts. This round does not change that gate.
2. **Capture, tagged live.** For each of the eleven categories above,
   record at least a few minutes with a phone or the app's own capture
   path, in a real room (not a synthetic/clean studio clip) — the whole
   point is to catch what a naive confidence threshold misses in ordinary
   conditions.
3. **Segment and label.** Cut the raw capture into segments and label each
   with one taxonomy category id, matching the shape
   `NegativeTaxonomySample` models (`id`, `categoryId`, `startMs`, `endMs`,
   `sourceRef`). Keep the raw audio on the capture owner's device/box —
   only the segment metadata (with a `sourceRef` back to that external
   material) is ever candidate content for this repository, following the
   `evaluation/recognition/fixtures/negative_taxonomy_sample.json` shape.
4. **Feed the metric, not the repo.** Run the labelled segments through the
   app/engine as `RecognitionCase.detectedEvents` (see
   `recognition_metrics.dart`) to measure
   `falseVisibleDirectionEventsPerMinute` and
   `falseVisibleChordEventsPerMinute` against real hard-negative material.
   The manifest that would carry those cases (with `sourceId`/group-key
   provenance) is out of this round's scope — see the round brief's §0.0
   "kivett munka" list.

## The two new scoped rates

`falseVisibleEventsPerMinute` (E14-R08, ADR 0509) is event-kind-agnostic:
it counts every accepted-but-wrong detection, whatever kind it is. This
round partitions that same count, in the same `computeRecognitionMetrics`
pass, over the same `correctAccepted` set and the same `durationMinutes`
denominator (ADR 0521 D1):

- `falseVisibleDirectionEventsPerMinute` — accepted strum detections that
  are not correct, per minute.
- `falseVisibleChordEventsPerMinute` — accepted chord detections that are
  not correct, per minute.

Because `onset`/`strum`/`chord` is `RecognitionEventKind`'s full partition,
the two scoped counts plus the (unexposed) onset-kind false-visible count
always sum to exactly `falseVisibleEventsPerMinute.eventCount` — see
`test/features/live/evaluation/recognition_metrics_test.dart` for the
closed-partition and anti-alias cells that prove this mechanically. Both
rates are named in `recognitionMetricExtractors`
(`lib/features/live/domain/evaluation/recognition_release_gate.dart`), so
they render in all three dashboard formats (JSON, Markdown, HTML) — but
**the shipped `recognition_release_gate.json` threshold file is
unchanged**: the Ch14 §7.2 "false visible arrow hard-negative" line still
gates on the agnostic rate. Rewiring it to the direction-scoped rate is a
separate, reviewed decision (ADR 0511 D9) — out of this round.
