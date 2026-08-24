# Security Review — E09-R26 (User report + immediate safety flow)

Reviewer: security-reviewer (READ-ONLY). HEAD `eb6d3868`, base `b93fbdc0`.
Verdict: **PASS** — 0 BLOCKER, 0 CRITICAL, 0 MAJOR, 1 MINOR, 2 NOTE.

## Scope verified
- `build_sanitized_response` (report_service.py:265-296), `ReportSubmissionResult`
  (130-146), router response + exception handlers (reports.py:118-208), ORM
  (report.py), migration, Flutter sheet, ARB, backend tests.
- Router is NOT mounted in production (`build_community_router` returns only
  `profile.router`, __init__.py:66); endpoint-level findings are latent.

## §5.1 reporter-identity invariant — HELD (structural + mutation-proven)
`build_sanitized_response` returns a literal 6-key dict (report_public_id,
target_type, target_id, category, created_at, deduplicated); the router returns
that dict verbatim with no `jsonable_encoder` of the ORM row. `reporter_profile_id`
appears only as an internal FK, in the rate-limit dict, and inside `dedup_key`
(never serialized). Reporter identity is derived server-side from the JWT
(`current_user.id` → `_caller_profile_public_id`), never from the payload. The
four exception messages (`str(exc)`) carry no reporter identity: category-echo,
fixed rate string, "reporter profile not found", "caller has no community
profile". No logging sinks in any of the three modules. A1 tests (5) pass,
including a real-violation probe that patches the shape and goes red.

## §5.3/D7 self-harm copy — HELD
Exactly one ARB key `reportSheetSelfHarmHelper` is referenced once
(report_content_sheet.dart:254). EN/HU text is non-diagnostic, contains no
method detail, points to emergency services, and states it is not a substitute
for emergency help. No per-callsite variation.

## Findings

### MINOR (latent, unwired) — `extra_metadata` uncapped before truncation
report_service.py:390 / reports.py:160-168. The router coerces keys to `str` but
applies NO size/key-count cap; `submit_report` runs `json.dumps(extra_metadata)`
on the full untrusted dict, THEN truncates to 2048. A caller (copyright/privacy
category) can send a multi-MB `extra_metadata` object, forcing a large transient
encode. The service docstring (line 388-389) claims "The router enforces the same
cap at the request boundary" — that cap does not exist. Latent (router unmounted;
Flutter sheet sends no extra_metadata). Direction: cap payload byte-size / depth
/ key-count at the request boundary before `json.dumps`, or correct the docstring.

### NOTE — truncated metadata stored possibly-invalid but inert
`json.dumps(...)[:2048]` can slice mid-token, yielding invalid JSON. Confirmed
NEVER `json.loads`-ed in this round (grep: no reader). Forward risk only when
Kör 27 parses `extra_metadata_json`; that consumer must fail-closed on malformed
JSON.

### NOTE — dedup_key docstring format mismatch
report.py:139 and migration:12 describe the dedup key as
`f"{reporter_public_id}:..."`; the code uses the internal `reporter.id`
(report_service.py:174). No security impact (never exposed); cosmetic.

## Items confirmed NOT findings
- Rate limiter keyed on JWT-resolved `reporter.id`, unspoofable by client
  (in-process limitation is documented, out of scope).
- Raw `text()` in `_caller_profile_public_id` is parameterized (`:uid`) — no SQLi.
- No IDOR: report submission returns no target data; reporter from JWT only.
- Migration UNIQUE/FK/index set is sound; CASCADE on reporter delete.
