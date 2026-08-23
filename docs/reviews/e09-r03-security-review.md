# E09-R03 — Security/Privacy Review (risk="high")

Brief: `docs/rounds/e09-r03-public-identity-and-handle-policy.md`
Scope: `backend/app/community/{policies/handle_policy.py, services/identity_service.py,
models/handle_history.py, routers/handles.py}`, `backend/alembic/versions/e09_r03_0003_community_handle.py`
Branch/HEAD: `minimax/e09-r03-public-identity-and-handle-policy` @ `9ad6cb3a`
Reviewer: `security-reviewer` subagent (dispatched by Claude Sonnet 5 orchestrátor) · Dátum: 2026-08-22
Method: direct source read + two throwaway probe tests against a live app instance (removed after use)

## Load-bearing context

The handles router is **not wired into the running app** this round.
`build_community_router()` (`app/community/__init__.py:66`) returns only
`profile.router`; `app/main.py` is untouched. `handles.router` is imported and
mounted **only** by the test fixture. Every finding below describes latent
behaviour of code that will go live once a future round mounts the router —
it is flagged now because the round's own docstrings and §10 handoff assert
these controls already hold.

## Summary

MAJOR: 1 (F1) · MINOR: 2 (F2, and a cooldown TOCTOU tracked as F4b) · NOTE: 3.
**F1 and F2 fixed and independently re-verified in the round's javító kör
(`6d354812`)** — see `e09-r03-review.md` for the closure evidence (both
fixes reverted-and-reproduced red by the reviewer, then confirmed green).
F4b remains a documented, non-blocking follow-up.

## MAJOR

### F1 — Availability rate limiter keyed on spoofable `X-Forwarded-For`

See `e09-r03-review.md` F1 for the full writeup and required fix. Summary:
`_client_key` (`handles.py:92-107`) trusts a client-supplied header with no
trusted-proxy configuration; reproduced 60/60 requests bypassing the 30/min
limiter by rotating the header value. Impact is bounded today because the
router is unwired, but the fix belongs in this round (same file, in
`allowed_paths`) since a future wiring round would otherwise inherit it
silently.

## MINOR

### F2 — Duplicate-handle claim/change returns 500 instead of the documented 409

See `e09-r03-review.md` F2. Root cause: `assign_handle`/`change_handle`
(`identity_service.py:184-210`, `:262-291`) translate `IntegrityError` to
`HandleAlreadyClaimed` internally, but the router only wraps
`commit_with_uniqueness_check` in `except HandleAlreadyClaimed` — not the
`assign_handle`/`change_handle` call itself, where SQLite actually raises on
`UPDATE`. No data leaks (generic 500 body), but the "single chokepoint"
design claim in the docstrings is false for the common duplicate-claim path.

### F4b — Cooldown check is an app-level TOCTOU with no DB-level guard

`identity_service.py:237-251` reads the last `changed_at` then later writes,
with no unique/locking enforcement in between (unlike the handle-uniqueness
path, which correctly relies on the DB index). Two concurrent `change_handle`
calls at the exact cooldown-expiry moment can both pass the check. Bounded
impact: a one-time 2× overshoot at each cooldown boundary, not sustained
rapid churn — the next change is blocked for another 14 days from whichever
write lands. The `_change_limiter` secondary bound is itself defeated by F1.
Tracked as a follow-up (not required to block this round); document the
concurrency guarantee or add a conditional-UPDATE guard in a later round.

## NOTE

- **N1 — No authorization on `claim`/`change`.** `profile_id` comes from the
  request body with no ownership check (`handles.py:247-249`, `:295-297`).
  Acceptable now (router unwired, auth deferred to Kör 6 per the brief), but
  the wiring round MUST bind mutations to the authenticated principal before
  mounting the router, or handle hijack becomes trivial.
- **N2 — `GET /{handle}` resolver is unauthenticated and unrate-limited by
  design.** Correctly returns only `{handle, public_id, redirect?}` — no
  internal id, email, or display name (`_public_id_for`, `:205-219`). Noted
  because it makes F1's rate limit largely moot for existence enumeration
  regardless — handle existence is intentionally public.
- **N3 — `PublicIdGenerator`/`_secrets_uuid4` are unused this round.** The
  live `public_id` column default is still Kör 2's `uuid.uuid4()`
  (`os.urandom`-backed, non-guessable, independent of the internal id) — §5.2
  is satisfied by that existing default, not by the new injectable generator,
  which is exercised only by its own unit test and never wired to a write
  path. Harmless; flagged so a later round doesn't assume the new generator
  is load-bearing today.

## Explicitly checked and CLEAR

- **§5.2 non-guessable public UUID** — `uuid.uuid4()` column default,
  `os.urandom`-backed, `test_public_id_not_derived_from_internal_id` passes.
- **§5.1 DB-level uniqueness** — unique index on the *normalized* column
  (migration `:69-74`); `test_unique_index_is_on_normalized_not_display`
  confirms the index sits on `handle_normalized`, not `handle_display`.
- **SQL injection** — every `text()` call uses bound `:params`; no
  string-formatted user input reaches SQL anywhere in the four files.
- **PII in responses** — availability/resolve/claim/change responses never
  leak an existing owner's internal id, email, or display name.
- **Timing side-channel on availability** — the only observable timing split
  (reserved/blocked/invalid vs. taken/available) discloses nothing the
  response body doesn't already reveal verbatim.
- **Migration safety** — FK-safe downgrade order; nullable handle columns +
  unique index coexist correctly with pre-existing NULL rows from Kör 2
  (NULLs are distinct under SQLite's unique-index semantics).
- **Reserved/blocked catalogues** — built-in `frozenset`s, not user-editable;
  `merge_reserved` never mutates the module default.
- **No new dependencies, logging/analytics sinks, or raw audio/camera/token
  paths touched.** Rate limiter is stdlib-only, honestly documented as
  process-local (single-instance).

**Verdict:** No BLOCKER (no proven secret leak, no consent bypass, no path
traversal/RCE, no AGENTS.md §5 product-boundary breach). One MAJOR (F1) and
two MINOR (F2, F4b) — F1+F2 required in the javító kör (see
`e09-r03-review.md`); F4b tracked as a non-blocking follow-up. The DB-level
identity/uniqueness core is sound.
