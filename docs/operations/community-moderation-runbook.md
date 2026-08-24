# Community Moderation Runbook — E09-R27, ADR 0425

> **Audience:** on-call engineer / future moderator / future admin-UI
> builder. The runbook documents the operational rules the code
> enforces and the documented exceptions that live OUTSIDE the code
> (the §D6 "independent reviewer" rule, the §D8 priority-score
> formula rationale, the §D4 urgent-spam-containment exception).
> Reference: [ADR 0425](../adr/0425-moderation-queue-enforcement-and-appeal.md)
> (the architectural source of truth).

---

## 1. Moderator identity (D1)

The **only** way to become a moderator is to have a row in the
`community_moderators` table (`user_id` FK to `users.id`,
`granted_at`, optional `granted_by_user_id` audit column).

| Action | Path |
|---|---|
| Grant | `INSERT INTO community_moderators (user_id, granted_by_user_id) VALUES (...)` — no admin-UI today; an SQL migration is the only supported path. |
| Revoke | `DELETE FROM community_moderators WHERE user_id = ?`. The user immediately loses access to every `/community/moderation/*` endpoint. Their historical action rows in `community_moderation_actions` remain intact (the audit chain is INSERT-only). |
| Audit | `SELECT * FROM community_moderators ORDER BY granted_at DESC` for the current grant roster. |

**Rules:**

- **No JWT `role` / `scope` claim** — the brief §0.0 D1 forbids
  modifying `security.py` / `deps.py`. A future round that wants to
  add a JWT-level fast path MUST route through the
  `community_moderators` table first; the JWT is an optimization,
  not a replacement.
- **No `User.role` / `CommunityProfile.is_admin` column** — same
  reason. The `community_moderators` table is the single source of
  truth.

## 2. Case lifecycle (D2/D3/D4/D6)

The case moves through the five-value state machine
`visible → limited → pending_review → removed | author_only`. The
`§18.1 Dart enum` mirrors the `MODERATION_CASE_STATES` literal set in
[`models/moderation.py`](../../backend/app/community/models/moderation.py).

### 2.1 Allowed transitions

```
                 ┌──────┐
                 │visible│
                 └──┬───┘
        ┌───────────┴───────────┐
        ▼                       ▼
   ┌─────────┐         ┌─────────────────┐
   │ limited │◄────────│ pending_review  │
   └────┬────┘         └────────┬────────┘
        │  ┌─────────────────────┤
        ▼  ▼                     ▼
  ┌──────────┐           ┌───────────┐
  │  removed │           │author_only│
  └────┬─────┘           └─────┬─────┘
       ▼                        ▲
  ┌──────────┐                  │
  │author_only│◄────────────────┘
  └──────────┘
```

The transition graph is encoded as a `Final` dict in
[`case_service.py::ALLOWED_TRANSITIONS`](../../backend/app/community/moderation/case_service.py).
`removed → visible` is reserved for the appeal-upheld flow; a direct
moderator decision attempting this pair raises
`InvalidStateTransition` (the §6.1 A2 measure-matrix cell).

### 2.2 Automation vs human (D4)

| Source | Destination states |
|---|---|
| **Automation** (`record_automation_signal`) | `{limited, pending_review}` ONLY. The destination is computed from `confidence` (≥ 0.8 → `pending_review`, otherwise `limited`). NO `to_state` parameter. |
| **Human moderator** (`apply_moderator_decision`) | Any state reachable from the current state per `ALLOWED_TRANSITIONS`. The ONLY path to `removed` / `author_only`. |

The Kör 19 `media_moderation.py::triage()` / `resolve_review()`
seam is the upstream analog — the Kör 27 case-level state machine
is the downstream extension.

### 2.3 Urgent spam-containment exception (§5.1 D4)

The brief §5.1 allows a **documented sürgős** exception to the
human-review gate. The use case: a high-confidence provider fires
on a spam wave that requires account suspension within minutes.

**Not implemented in code this round.** The `record_automation_signal`
function's destination set is structurally `{limited, pending_review}`
— there is no code path today that bypasses the human gate.

**Operational rule:** if a future round adds the urgent path
(plausibly via a `urgent` boolean on `record_automation_signal` with
an additional moderator co-sign recorded in the same action's
`reason` field), the change MUST keep the §6.1 measure-matrix A4
cell firing: even with the urgent flag, automation alone MUST NOT
write `removed` / `author_only`. The audit row's
`actor_type="automation"` row may carry a moderator's user-id in
`actor_user_id` only if the moderator manually approved the
automation's recommendation; that is a future-round design choice
and is NOT this round's scope.

## 3. Appeal flow (D6)

| Step | Caller | Endpoint |
|---|---|---|
| Submit appeal | Any logged-in user | `POST /community/moderation/cases/{public_id}/appeals` |
| Resolve appeal | Moderator only | `POST /community/moderation/cases/{public_id}/appeals/resolve` |

**Rules:**

- **One appeal per case.** A second submission returns 409. The
  `appeal_state` column carries `NULL` (no appeal) →
  `"submitted"` → `"resolved"`.
- **Verdict is `upheld` or `overturned`.** `upheld` reverts the case
  to `visible` and reopens it (`is_open=True`). `overturned` keeps
  the case in its current state and just marks the appeal resolved.
- **Independent reviewer rule (D6):** the resolver's `users.id` is
  recorded on every appeal-resolved action row. The audit chain
  supports a future round that enforces "resolver ≠ original
  moderator" at the code level — today the rule is an OPERATIONAL
  rule (the runbook + the moderation queue's audit-trail review).
  The first line of enforcement is the moderator team's manual
  review process.

## 4. Priority-score formula (D8)

The `priority_score` column on `community_moderation_cases` is the
queue-read ordering key. The formula has THREE documented inputs,
NO fourth:

```
priority_score = (
    report_count
        * PRIORITY_WEIGHT_REPORT_COUNT        (5)
  + automation_confidence
        * PRIORITY_WEIGHT_AUTOMATION_CONFIDENCE (40)
  + account_history_count
        * PRIORITY_WEIGHT_ACCOUNT_HISTORY     (20)
)
```

| Input | Source | Documented value-set |
|---|---|---|
| `report_count` | Count of `community_reports` rows for `(target_type, target_id)` | `0..∞` |
| `automation_confidence` | Most recent `record_automation_signal` `confidence` for this case | `[0.0, 1.0]` (or `None` when no automation signal yet) |
| `account_history` | Count of CLOSED cases (`state in {removed, author_only}`) owned by the target's profile | `0..∞` (or `0` when target type has no profile resolution, e.g. media) |

**Tuning rationale:**

- The 5x report-count weight is intentionally low — a single
  reporter spamming 100 reports on one target should not push the
  target to the top of the queue. Multiple distinct categories
  raise the score (the §6 A2 dedup-key invariant prevents a single
  reporter from inflating the count).
- The 40x automation-confidence weight reflects the provider's
  audit signal — high-confidence automation routes to
  `pending_review` (the human gate), and the priority lifts the
  case to the top of the moderator's queue.
- The 20x account-history weight is the "repeat offender" signal —
  a profile with multiple prior enforcement actions sees new
  reports lifted to the top.

**NEM elfogadható:** a future round that adds a fourth input (e.g.
"reporter-account-credibility") without updating ADR 0425 §D8 is a
brief violation — re-issue the ADR or stop.

## 5. Reporter identity (§5.1 retaliation-risk, ADR 0422 D2)

The case row has **NO reporter FK** (the brief §5.1 invariant from
ADR 0422 — the moderator's queue view NEVER joins the reporter
identity). The `community_moderation_actions` rows carry the
actor's `users.id` (a MODERATOR's id for `moderator_decision` /
`appeal_*` actions, NULL for `automation_signal` actions).

**Operational rule:** a moderator who reads a case detail MUST NOT
look up the reporter through any side-channel (the `community_reports`
table is internal-only; the Kör 26 sanitization helper strips the
reporter from any wire response). The retaliation-risk invariant
depends on the moderator's discipline.

## 6. Audit immutability (D5)

`community_moderation_actions` rows are INSERT-only. There is NO
`update_action` / `delete_action` function in
[`case_service.py`](../../backend/app/community/moderation/case_service.py)
— the absence is structural, not just policy.

**Operational rule:** if a moderation decision needs to be
corrected (e.g. a typo in `reason`), do NOT UPDATE the existing row.
INSERT a new action row of `action_type="moderator_decision"` (or
the appropriate type) with a `reason` that explains the correction
and references the original `public_id`. The audit chain remains
complete — both the original and the correction are visible.

## 7. Visibility (§18.1 / D7)

The [`content_visibility_for_state`](../../backend/app/community/moderation/case_service.py)
helper maps a case's state to one of four visibility levels. This
helper is **not wired into the feed / post / comment routers this
round** (deferred-wiring pattern, ADR 0410 / 0412 precedent). A
future wiring round:

1. Reads the case's current state via
   `get_or_create_case(target_type, target_id)` for the target.
2. Calls `content_visibility_for_state(case.state, viewer_is_author=...)`
   on each request that surfaces the target.
3. Filters the response per the returned visibility level.

The §18.1 Dart enum has five values (`visible`, `limited`,
`pendingReview`, `removed`, `authorOnly`); the Python string set
is `MODERATION_CASE_STATES` in
[`models/moderation.py`](../../backend/app/community/models/moderation.py).

## 8. Endpoint reference

| Method | Path | Auth | Body | Response |
|---|---|---|---|---|
| GET | `/community/moderation/cases` | Moderator | — | `{cases: [...], count: N}` (priority-ordered) |
| GET | `/community/moderation/cases/{public_id}` | Moderator | — | `{case: {...}, actions: [...]}` (no reporter PII) |
| POST | `/community/moderation/cases/{public_id}/decisions` | Moderator | `{to_state, reason}` | `{...case summary...}` |
| POST | `/community/moderation/cases/{public_id}/appeals` | Any logged-in user | `{reason}` | `{...case summary...}` (409 on duplicate) |
| POST | `/community/moderation/cases/{public_id}/appeals/resolve` | Moderator | `{verdict, reason}` | `{...case summary...}` |
| POST | `/community/moderation/cases/{public_id}/automation-signals` | Moderator (defence-in-depth; automation NEVER holds a JWT) | `{confidence, provider, provider_version}` | `{...case summary...}` |

All endpoints return 403 to a non-moderator JWT user. The
reporter-identity PII guard (A7) is structural — the wire shape
dataclasses carry no reporter field.

## 9. Future-round hooks

| Future round | Hook this round ships |
|---|---|
| Admin UI for moderator grant/revoke | `community_moderators` table + `granted_by_user_id` audit column |
| Moderator-grant `comment_policy.py::can_delete(is_moderator=...)` (Kör 16 ADR 0407 §D2) | `is_moderator(db, user_id)` function — drop-in replacement for the current hard-coded `False` |
| Wire `content_visibility_for_state` into feed / post / comment routers | The helper is PURE today; the call sites are deferred |
| Resolve-appeal "resolver ≠ original moderator" code-level enforcement | The audit chain already records both user-ids; only the assert is missing |
| Account-suspension / cross-domain admin actions | The `community_moderators` table is the source of truth; the next round's surface reads it via `is_moderator` |

## 10. Change log

- **E09-R27 (this round)** — initial queue, enforcement, appeal.
  ADR 0425. Implementation in [`backend/app/community/moderation/`](../../backend/app/community/moderation)
  and [`backend/app/community/routers/moderation.py`](../../backend/app/community/routers/moderation.py).