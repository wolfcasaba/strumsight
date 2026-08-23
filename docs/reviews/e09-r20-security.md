# Security review — E09-R20 (Notification inbox és push abstraction)

- **Reviewer:** security-reviewer (read-only, dedicated high-risk pass)
- **Branch:** `minimax/e09-r20-notification-inbox-and-push-abstraction`
- **HEAD:** `24f40314510ba8f8229af02f49640b9874cbe188`
- **Diff reviewed:** `4e611d1e..24f40314`
- **Round risk:** `high` (ADR 0414 D6 — push-payload redaction + cross-user block visibility)
- **Verdict:** **PASS with 1 MAJOR (latent)** — no CRITICAL, no BLOCKER, no secret/consent/RCE
  finding. One MAJOR read-path A4 gap (reproduced) that is latent only because the service is
  unwired this round; it MUST be closed before `get_unread_count` reaches a client.

## Scope confirmation (service-layer-only, ADR 0414 D2)

Confirmed by `git diff 4e611d1e..24f40314 --stat` + targeted greps:

- No forbidden file touched: `reaction_service.py`, `comment_service.py`, `follow_service.py`,
  `routers/**`, `social_graph.py`, `create_app`/`main.py`, `lib/features/community/domain/**` —
  all absent from the diff.
- No new router file added (`--diff-filter=A | grep router` → none).
- No `include_router` line added anywhere in the diff.
- `query_filters.py::is_blocked_pair` imported, not modified (unchanged, as declared).

The 14 changed files are exactly the `allowed_paths` set. Scope claim holds.

---

## Findings

### MAJOR-1 (latent) — `get_unread_count` does NOT apply the A4 block filter; the unread badge counts a blocked actor's notification that `list_inbox` hides

- **File:** `backend/app/community/notifications/notification_service.py:754-776`
  (`get_unread_count`); contrast with the block filter in `list_inbox`
  `notification_service.py:713-740`.
- **Rule violated:** A4 acceptance criterion ("Blocked actor eseménye rejtett az inboxban" —
  ADR 0414 A4 / ADR 0402 block boundary). The inbox unread count is a client-facing read path
  that returns inbox state; A4 must hold on it, not only on the list view.
- **Failure scenario (reproduced):** recipient blocks `actor_a`; `actor_a` triggers a
  notification (a row is created — `create_notification` intentionally does not pre-check the
  block, service.py:340-342). On read:
  - `list_inbox(...)` → `0` rows (A4 filter drops the blocked actor's row — correct).
  - `get_unread_count(...)` → `1` (counts `WHERE recipient AND is_read = False`, no block filter).

  Reproduced in the isolated clone with a throwaway test reusing the round's own fixtures
  (`_make_recipient` / `_make_two_actors` / `_make_block_pair`): observed
  `list_inbox rows=0  unread_count=1`. The throwaway test was deleted after the run; the tree is
  clean.
- **Why it matters:** the block boundary exists precisely to deny a blocked user the ability to
  reach the recipient. Here a blocked user's reaction/comment still ticks the recipient's unread
  badge up while the inbox shows nothing — a badge-desync and a low-grade harassment/leak vector
  (the recipient learns "a blocked person did something" from the count). The round's §10 handoff
  self-reports A4 as PASS on the strength of the `list_inbox`-only test
  (`test_a4_blocked_actor_notification_hidden_from_inbox`, test file:746-830); no test exercises
  `get_unread_count` against a blocked actor (grep confirms `get_unread_count` appears only in the
  A3 race tests and the `__all__` export test).
- **Why "latent":** ADR 0414 D2 — this round ships the service unwired (no live router, not in
  `create_app()`), so no client calls `get_unread_count` yet. Not user-reachable today, but the
  defect is in the code as written and the acceptance claim is overstated.
- **Suggested direction:** apply the same `is_blocked_pair` predicate (or a materialised block-set
  subquery) to `get_unread_count` so the count equals the count of A4-visible unread rows, and add
  a measure-matrix cell that pins `unread_count == visible_unread` under a block edge. Same review
  needed for any future "unread by category" aggregate.

### NOTE-1 (forward) — A1 push redaction is enforced on payload SHAPE, not on payload VALUES; `title_key`/`body_key` are free-form strings copied verbatim from the caller

- **File:** `backend/app/community/notifications/push_gateway.py:129-147`
  (`_assert_payload_is_minimal`) + `PushPayload.__post_init__` (push_gateway.py:101-118);
  construction at `notification_service.py:460-467` (`body_key=new_row.body_key`,
  `title_key=new_row.title_key`).
- **Observation:** the A1 guard is genuinely strong on structure — `PushPayload` is a frozen,
  closed dataclass, `__post_init__` validates the `type` allowlist and rejects an entity id without
  a type, and `_assert_payload_is_minimal` rejects any field name outside `_ALLOWED_PUSH_FIELDS`.
  The §6.1 valódi-sértés próba (adding a `commentBody` field → A1 red) exercises exactly this
  field-name boundary. However, the guard is **field-name based**: `body_key`/`title_key` are
  `String` columns (model.py:182-183) carrying arbitrary text, copied verbatim into the payload.
- **Failure scenario (future, not this round):** when a later round wires
  `reaction_service`/`comment_service` to `create_notification`, if that caller passes raw comment
  text as `body_key=comment.body` (the "nicer preview" temptation the brief §5.1 explicitly warns
  against), the raw text ships in the push and **neither** `__post_init__` **nor**
  `_assert_payload_is_minimal` catches it — the field name is still `body_key`. This is the classic
  key-vs-value redaction gap.
- **Why NOTE (not MAJOR) this round:** there is no production caller — the service is unwired and
  the only caller is the test, which passes literal keys (`"k1"`, `None`). No leak is producible on
  this branch. This is a forward guard-rail for the wiring round.
- **Suggested direction:** at the gateway boundary, constrain `title_key`/`body_key` to
  catalogue-key shape (e.g. allowlist prefix `community…` / `^[A-Za-z0-9_.]+$` charset, reject
  whitespace/`@`/length > N) rather than only checking the field name — so a raw-text value is
  rejected regardless of which field it lands in.

### NOTE-2 — `get_related_content_id` keeps `entity_id` for non-`post` entity types

- **File:** `backend/app/community/notifications/notification_service.py:799-804`.
- The A5 freshness check only covers `entity_type == 'post'`; other types fall through returning
  `entity_id` unsuppressed. Documented and acceptable this round (only `post` is wired); flag for
  the Kör 21/24 challenge/club rounds to add their own freshness branch, else a deleted
  challenge/club could yield a broken deep-link (A5 class).

### NOTE-3 — `set_preference` fails open on unknown category, closed on unknown level

- **File:** `backend/app/community/notifications/notification_service.py:850-876`.
- `level` is allowlist-validated (`{"inApp","push","disabled"}`, raises on miss — fail-closed).
  `category` is accepted silently for any string (fail-open, documented). Preference store is a
  process-local dict (non-persistent, documented A6/future-round scope). No security impact (no
  cross-user key — keyed by `(recipient.id, category)`); noted for the persistence round.

---

## Verified clean (evidence)

- **A1 payload shape:** `PushPayload` is the single payload constructor; `create_notification`
  (service.py:460-467) is the only site that builds one; `send_many` is unused. No payload-like
  object crosses the gateway elsewhere. The A1 test asserts `commentBody` and `actor-a@s.test` are
  absent from `str(payload.__dict__)` for its inputs (test file:344).
- **IDOR guards present on every path returning/mutating a specific row:**
  `mark_read` checks `notification.recipient_profile_id != recipient.id → return False`
  (service.py:519-523); `mark_all_read_up_to` checks
  `up_to.recipient_profile_id != recipient.id → return 0` (service.py:600-601) and its bulk UPDATE
  filters on `recipient_profile_id == recipient.id` (service.py:611); `list_inbox` and
  `get_unread_count` scope every query by the JWT-resolved recipient. A blocked/foreign
  `notification_public_id` alone cannot read or mutate another recipient's row.
- **Migration** `e09_r20_0014_community_notification.py`: strictly additive, single new table, no
  backfill/`server_default` that copies data, no PII in any indexed column (indexes cover
  `public_id`, `recipient_profile_id`, `is_read`, `entity_type`, `entity_id`, `created_at` — all
  ids/flags/timestamps). `entity_id` capped `String(64)`, `dedup_key` `String(128)`.
- **Model** `notification.py`: no free-text content column — only localization KEYS, ids, flags,
  timestamps. No logging in the model or migration.
- **Flutter logging** (`notification_controller.dart:224-465`): all `_logger.warning/error` calls
  use a fixed event code (`community.notifications.*.failure`) plus fields limited to `pageSize`,
  opaque ids (`notificationId.value`, `upToId.value` — UUIDs), `category` (wire string), and
  `level.name` (enum). No raw notification title/body is logged. Consistent with the existing
  app-wide `AppLogger` pattern; no new leak introduced.
- **Screen** `community_notifications_screen.dart:229-279`: renders `titleKey`/`bodyKey` by
  resolving them against the generated ARB catalogue via a fixed `switch`, falling back to the raw
  KEY string (not raw content) on an unknown key, through markup-inert `Text()`. No raw-content or
  token handling.
- **Cursor** `_decode_cursor` (service.py:234-242): fail-safe — any malformed/tampered cursor is
  caught and returns `None`, list restarts from top; no crash, no injection (SQLAlchemy
  parametrised).
- **Secret semantics:** the only credential-shaped literal in the diff is
  `hash_password("test-password")` in the test fixture `_make_*` helper (test file:169) with
  `@s.test` fake emails — a genuinely fake fixture, not a real secret; no key/token/password in any
  production file.

---

## Summary

| Severity | Count | Item |
|---|---|---|
| CRITICAL | 0 | — |
| BLOCKER | 0 | — |
| MAJOR | 1 | MAJOR-1: `get_unread_count` skips the A4 block filter (reproduced; latent-unwired) |
| MINOR | 0 | — |
| NOTE | 3 | key-vs-value A1 forward gap; non-`post` A5 freshness; `set_preference` category fail-open |

No non-negotiable product boundary (raw audio/camera, logged-out network, secret-in-log/commit,
offline degradation, false-confidence) is breached. The single MAJOR is a real, measured A4
read-path gap that is currently latent because the service is unwired (ADR 0414 D2); it should be
fixed and pinned with a test before the count path is exposed to any client, and the round's §10
"A4 PASS" claim should be scoped to `list_inbox` only until then.
