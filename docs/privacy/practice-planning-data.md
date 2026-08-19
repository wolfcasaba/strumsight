# Practice planning data — what we store, for how long, and how to remove it

> This document describes **only** the practice-planning data collected and
> retained on-device by the AI Practice Generator feature. It is part of the
> E07-R29 (Accessibility, localization, privacy and safety hardening) round
> and is binding for the delete-all / export-all flow described in §5.5 and
> §5.7 of `docs/rounds/e07-r29-accessibility-privacy-hardening.md`.
>
> The authoritative source-of-truth for what a learner may request is the
> privacy screen `lib/features/practice_generator/presentation/screens/
> plan_privacy_screen.dart`, whose ARB-localised strings define the
> user-visible scope of each action.

## What data the planner stores

The planner owns three on-device key namespaces, each fully isolated from
each other and from any other feature of the app (ADR 0259 §3, ADR 0267):

| Namespace pattern                                          | Owner                                                      | Purpose                                                                 |
|------------------------------------------------------------|------------------------------------------------------------|-------------------------------------------------------------------------|
| `ss.practice_generator.plan.draft.<draftKey>`              | `LocalPracticePlanRepository`                              | Single wizard-in-progress draft, never promoted until activation        |
| `ss.practice_generator.plan.active_pointer` + `.active.<…>` | `LocalPracticePlanRepository`                              | The currently active plan's pointer + the immutable plan record         |
| `ss.practice_generator.plan.archive.<planId>.revisions.<…>` / `.outcomes.<…>` / `…index` | `LocalPracticePlanRepository`             | Bounded, newest-first history of every plan revision and outcome        |
| `ss.practice_generator.generation_draft`                   | `GenerationDraftRepository`                                | Single resumable wizard draft (separate key namespace)                 |

Evidence derived from those outcomes lives in a fourth, **separate** storage
port — `PracticeEvidenceRepository` (ADR 0260 §5). Evidence carries only
derived measurements and a `sourceOutcomeId` provenance pointer back to the
outcome that produced it. The evidence store is **deliberately expiry-
immutable**: querying past `validUntil` returns nothing without deleting the
record, and no automatic job ever deletes evidence.

## Retention policy

| Datum                                      | Source of truth             | Retention                                                                                      |
|--------------------------------------------|-----------------------------|-----------------------------------------------------------------------------------------------|
| Active plan record                         | Pointer + revision record   | Replaced atomically on each new activation; the prior active record is removed best-effort once the pointer has moved. |
| Wizard drafts                              | `saveDraft` / `clearDraft`  | Replaced on the next save; not auto-evicted.                                                   |
| Archived revisions / outcomes per plan     | Bounded index               | Capped at 50 revisions and 200 outcomes per plan by `PracticePlanHistoryPolicy`; the oldest entries are evicted when the cap is exceeded. |
| Skill evidence                             | `PracticeEvidenceRepository`| Never auto-deleted. Expiry is a **query-time** concern (ADR 0260 §5).                          |

The retention described above is the same on disk whether the planner is
enabled or disabled. No background job, no scheduled task, and no quiet
"housekeeping" code path deletes planner data.

## What "Delete all practice planning data" removes

A user who taps **Delete all practice planning data** triggers a single,
explicit, one-shot operation handled by
`DeletePracticePlanningData` (`application/usecase/
delete_practice_planning_data.dart`). The operation:

1. Removes the **active plan pointer and its revision record**.
2. Removes **every wizard draft key** the local repository has ever written
   (one `remove()` per known key).
3. Reads the **archive revision and outcome indexes for every plan it ever
   recorded** and removes every revision / outcome record they reference.
4. Removes the **archive indexes themselves**.
5. Calls the **narrow, plan-scoped `deleteForPlan(planId)` hook on the
   evidence repository** for every `sourceOutcomeId` previously associated
   with a planner outcome, removing the evidence the planner wrote.

Steps 1–4 are scoped to keys the planner itself owns (the
`ss.practice_generator.plan.*` and `ss.practice_generator.generation_draft`
namespaces). No other feature's key prefix is ever read or removed by this
use case.

Step 5 is **the only** mutation the evidence store exposes. It is documented
on `PracticeEvidenceRepository.deleteForPlan` as "the **sole** entry point
exposed by ADR 0260 §5 for a user-initiated, plan-scoped delete" and is
**not** callable from any automatic / query-time path. The evidence
immutability rule (ADR 0260 §5) remains true for **all** other call sites —
the reducer, the `query` path, the schema migrator, and the bounded
`allForSkill` accessor — none of them reach this method.

## What "Delete all practice planning data" keeps

The delete operation is **structurally** scoped. It must never reach:

* the learner's profile, sign-in, consent, or account state
* the song library, setlists, or any history owned by another feature
* the live-detection, vision, tutor or settings data
* any `key_value_store` key whose prefix is **not** in the planner's
  documented namespace

The acceptance gate verifies this: writing an unrelated key
(`learning.history.record.1`) before the delete must show the key **still
present** afterwards (test matrix §6.1 third row).

## What "Export planning data" produces

`ExportPracticePlanningData` (`application/usecase/
export_practice_planning_data.dart`) builds a JSON document on-device
covering exactly the same scope as the delete above: the active plan,
every saved draft, every archived revision and outcome, and the evidence
the planner wrote. The export is written to a temporary file in the
app's own cache directory. No network upload is performed by this use
case — the user must share the file themselves. The temporary file is
named `strumsight-planning-export-<timestamp>.json` and is **not**
removed by the export use case; cleanup is the OS's, when the cache is
reclaimed.

The export contains:

* `meta`: an envelope marker, generator version, and a generation timestamp
* `activePlan`: the persisted active plan, if any
* `drafts`: every draft the repository has ever saved
* `archive`: for every plan, its revisions and outcomes
* `evidence`: every `SkillEvidence` the planner wrote, deduped by
  `sourceOutcomeId`

The export deliberately **does not** include the free-text "comfort note"
input the wizard may collect during setup. That text never reaches the
planner's `LearnerConstraint` store on disk (the controller stores it
under the `comfort` category and the planner never persists a constraint
with a free-text `value` — see ADR 0260 §4 + ADR 0265 §3); consequently
nothing for it ever appears in any export either.

## Discomfort / safety flow

A learner can flag discomfort in the wizard or via the post-session
record flow. The flag:

* **never** writes the free-text "comfort note" to logs, telemetry or any
  persistent store (ADR 0260 §4, ADR 0265 §3). The category ("discomfort")
  is recorded; the text is dropped at the `EvidenceAggregator.ingest(
  ..., discomfortNote:)` boundary.
* **never** triggers a difficulty increase. The planner treats discomfort
  as a progression blocker for the affected session.

The privacy screen surfaces a short, plain-language description of this
flow ("If something hurts") so a learner does not have to read this
document to understand the rule.

## Accessibility and localisation

Every string surfaced by the privacy screen, the delete confirm dialog,
the export confirm dialog, the discomfort safety card, and the "done"
toast is ARB-localised in `app_en.arb` and `app_hu.arb` and is verified
by `tool/ci/check_l10n_parity.dart`. The privacy screen itself is a
keyboard-, screen-reader-, and large-text-friendly view (every action is
a labelled `Material` widget with a `Semantics` label; no gesture-only
interaction; status is never communicated by colour alone).

## Why this is not in the main app settings

The privacy screen is wired by the planner feature itself. A learner who
does not have the planner enabled does not have a privacy surface to
visit; their app simply has no planner data to remove. Once the planner
is enabled and at least one plan is saved, the screen becomes the
single, authoritative place to perform a delete or export — *not* the
general settings.

## Change control

Any future addition to the documented policy circle (any new key the
delete/export must touch, or any new evidence the delete/export must
purge) requires an ADR amendment and a brief revision; this document is
**not** the place to silently widen the scope.