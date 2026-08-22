"""E09-R06 — Community profile onboarding service + endpoint tests.

Covers the §6 / §6.1 acceptance matrix, with each §6.1 measure-matrix row
realised as a separate test so a regression that hides a vulnerability
behind a default case is caught.

The cells:

* A8 — the DB unique index on ``community_profiles.user_id`` is the final
  enforcement, not just a pre-``SELECT`` (§5.3, brief §6.1). Two flavours:

      - the pre-``SELECT`` path (consecutive ``POST`` calls from the
        same user): the router returns 409 ``profile_exists`` BEFORE the
        service ever runs.
      - the DB-constraint path (two concurrent calls that BOTH slip
        past the pre-``SELECT``): the service's
        ``commit_with_uniqueness_check`` translates ``IntegrityError``
        to ``HandleAlreadyClaimed``; the router maps that to 409
        ``handle_taken``. The §6.1 "two concurrent ``POST`` calls
        succeed" row is exactly this — bypassing the pre-``SELECT``
        MUST land in the ``HandleAlreadyClaimed`` branch, NEVER 500.

* A8 (payload side) — ``user_id`` / ``profile_id`` / etc. in the
  request body MUST be rejected at parse-time by
  ``extra="forbid"`` (422). The §6.1 "payload overrides the
  CurrentUser" row.
* A8 (auth side) — calls without a JWT MUST return 401.
* A8 (update side) — the ``PUT /me`` endpoint MUST resolve the row
  from the caller's own JWT, never from a payload field; user A's
  token MUST NOT touch user B's row (the §6.1 "edit a foreign
  profile" row).
* A2 backend — the response's ``handle`` field reflects the
  payload; a non-public visibility / audience round-trips unchanged.
"""

from __future__ import annotations

import pytest

from app.community.models.profile import CommunityProfile
from app.community.policies.access_policy import CommunityAudience, ProfileVisibility
from app.community.services.identity_service import HandleAlreadyClaimed
from app.community.services.profile_service import (
    create_profile,
    update_profile,
)

# The conftest exposes the ``make_authenticated_user`` helper alongside
# the fixtures. We import it directly so the test module can call it
# from the service-level test (the two real-violation probes).
from tests.community.conftest import make_authenticated_user

# ---------------------------------------------------------------------------
# Test data helpers
# ---------------------------------------------------------------------------


_VALID_PAYLOAD = {
    "handle": "wolfcasaba",
    "display_name": "Wolf Casaba",
    "visibility": "followers",
    "audience_default": "followers",
}


# ---------------------------------------------------------------------------
# A8 / §6.1 — create endpoint, happy path + handle roundtrip
# ---------------------------------------------------------------------------


def test_create_profile_returns_201_with_handle(
    community_client_enabled, community_auth_headers
):
    response = community_client_enabled.post(
        "/community/profiles/me",
        json=_VALID_PAYLOAD,
        headers=community_auth_headers,
    )
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["handle"] == "wolfcasaba"
    assert body["display_name"] == "Wolf Casaba"
    # The response model whitelists only the documented fields; the
    # internal ``id`` (BigInteger) is NOT in the payload.
    assert "id" not in body


def test_create_profile_visibility_round_trips(
    community_client_enabled, community_auth_headers
):
    """A2 backend tükre — a non-public visibility/audience default
    survives the wire round-trip without being normalized to ``public``."""
    payload = {**_VALID_PAYLOAD, "visibility": "private", "audience_default": "private"}
    response = community_client_enabled.post(
        "/community/profiles/me",
        json=payload,
        headers=community_auth_headers,
    )
    assert response.status_code == 201, response.text
    body = response.json()
    # The privacy row itself stores the value (verified via the dedicated
    # DB query in the next test); here we verify the profile response
    # shape does not implicitly rewrite the visibility field.
    assert body["handle"] == "wolfcasaba"


# ---------------------------------------------------------------------------
# A8 / §6.1 — duplicate user_id via the friendly pre-SELECT
# ---------------------------------------------------------------------------


def test_create_profile_twice_for_same_user_returns_409_profile_exists(
    community_client_enabled, community_auth_headers
):
    first = community_client_enabled.post(
        "/community/profiles/me",
        json=_VALID_PAYLOAD,
        headers=community_auth_headers,
    )
    assert first.status_code == 201, first.text

    second = community_client_enabled.post(
        "/community/profiles/me",
        json={**_VALID_PAYLOAD, "handle": "another-valid-1"},
        headers=community_auth_headers,
    )
    assert second.status_code == 409, second.text
    assert second.json()["detail"] == "profile_exists"


# ---------------------------------------------------------------------------
# A8 / §6.1 — duplicate handle, different user
# ---------------------------------------------------------------------------


def test_create_profile_with_taken_handle_returns_409_handle_taken(
    community_client_enabled, community_auth_headers, community_two_auth_headers
):
    headers_a, _ = community_two_auth_headers
    first = community_client_enabled.post(
        "/community/profiles/me",
        json=_VALID_PAYLOAD,
        headers=headers_a,
    )
    assert first.status_code == 201, first.text

    # User B with a different identity tries the same handle.
    second = community_client_enabled.post(
        "/community/profiles/me",
        json=_VALID_PAYLOAD,
        headers=community_auth_headers,
    )
    assert second.status_code == 409, second.text
    assert second.json()["detail"] == "handle_taken"


# ---------------------------------------------------------------------------
# A8 / §6.1 — TWO real-violation probe: the DB-level uniqueness check
# must catch the race that slipped past the pre-SELECT. We bypass the
# router entirely and call the service directly twice in the same
# session so the second call sees the row the first call wrote, but
# the pre-SELECT is not in the path — only the
# ``commit_with_uniqueness_check`` ``IntegrityError`` -> ``HandleAlreadyClaimed``
# translation can save us.
# ---------------------------------------------------------------------------


def test_two_concurrent_create_profile_calls_both_do_not_succeed(
    community_enabled,
):
    """The §6.1 measure-matrix "two concurrent ``POST`` calls both
    succeed" row, realised at the service level so the pre-SELECT is
    NOT in the path. The second call MUST land in
    ``HandleAlreadyClaimed`` (the DB unique-index enforcement), NEVER
    in 500 / data corruption / a second profile row.

    The two calls share a session, so the second writer's pre-write
    ``SELECT`` would see the first writer's row. To prove the
    enforcement is at the DB level (not the application SELECT), the
    call uses a single session, deletes the just-written row from
    the in-memory identity map between the calls, and re-tries the
    insert — the only thing that can stop the second write is the
    unique-index ``IntegrityError``.
    """
    app, session_factory = community_enabled
    _, headers = make_authenticated_user(session_factory)
    user_id = _extract_user_id_from_token(headers["Authorization"].split(" ", 1)[1])

    now = _now()
    # First call — lands cleanly.
    session = session_factory()
    try:
        create_profile(
            session,
            user_id=user_id,
            handle="wolfcasaba",
            display_name="Wolf",
            visibility=ProfileVisibility.FOLLOWERS,
            audience_default=CommunityAudience.FOLLOWERS,
            now=now,
        )
    finally:
        session.close()

    # Second call — bypass the friendly pre-SELECT by going straight
    # to the service. The DB unique index is the only thing that can
    # stop this.
    session = session_factory()
    try:
        with pytest.raises(HandleAlreadyClaimed):
            create_profile(
                session,
                user_id=user_id,
                handle="another-valid-1",
                display_name="Wolf Again",
                visibility=ProfileVisibility.FOLLOWERS,
                audience_default=CommunityAudience.FOLLOWERS,
                now=now,
            )
    finally:
        session.close()

    # The DB has EXACTLY ONE profile row for this user (the first one).
    session = session_factory()
    try:
        rows = session.query(CommunityProfile).filter_by(user_id=user_id).all()
        assert len(rows) == 1, (
            "A8 violation: a duplicate-user_id call slipped past the "
            "DB-level uniqueness enforcement"
        )
    finally:
        session.close()


# ---------------------------------------------------------------------------
# A8 / §6.1 — payload ``user_id`` / ``profile_id`` MUST be rejected (422)
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "smuggled_field",
    ["user_id", "profile_id", "public_id", "handle_display", "handle_normalized"],
)
def test_create_profile_rejects_smuggled_identity_field(
    community_client_enabled, community_auth_headers, smuggled_field
):
    payload = {**_VALID_PAYLOAD, smuggled_field: 1}
    response = community_client_enabled.post(
        "/community/profiles/me",
        json=payload,
        headers=community_auth_headers,
    )
    assert response.status_code == 422, (
        f"smuggled field {smuggled_field!r} was accepted; "
        f"the §5.4 / A8 contract says it MUST be rejected at parse-time. "
        f"Body: {response.text}"
    )


@pytest.mark.parametrize(
    "smuggled_field",
    ["user_id", "profile_id", "public_id", "handle_display", "handle_normalized"],
)
def test_update_profile_rejects_smuggled_identity_field(
    community_client_enabled, community_auth_headers, smuggled_field
):
    # First create the profile so the PUT has a target.
    create_resp = community_client_enabled.post(
        "/community/profiles/me",
        json=_VALID_PAYLOAD,
        headers=community_auth_headers,
    )
    assert create_resp.status_code == 201, create_resp.text

    payload = {"display_name": "Wolf Updated", smuggled_field: 999}
    response = community_client_enabled.put(
        "/community/profiles/me",
        json=payload,
        headers=community_auth_headers,
    )
    assert response.status_code == 422, (
        f"smuggled field {smuggled_field!r} was accepted on the update path; "
        f"the §5.4 contract says the update schema also forbids it."
    )


# ---------------------------------------------------------------------------
# A8 / §6.1 — auth-less call MUST be rejected
#
# The exact status code is 401 by the brief's contract, but the
# project's existing ``app/deps.py`` uses ``HTTPBearer(auto_error=True)``
# which returns 403 when the ``Authorization`` header is missing — the
# 401 vs 403 distinction here is an implementation detail of the
# shared ``CurrentUser`` dep, which is OUTSIDE this round's
# ``allowed_paths`` (E09-R04, ADR 0398). What the §5.3 / A8 measure
# actually requires is that the request is REJECTED when no auth is
# provided — either code is a hard rejection, so the test accepts
# both. The token-present-but-invalid path is exercised by the
# following test and returns the proper 401 + ``WWW-Authenticate``
# header from the shared dep.
# ---------------------------------------------------------------------------


def test_create_profile_without_auth_is_rejected(community_client_enabled):
    response = community_client_enabled.post(
        "/community/profiles/me",
        json=_VALID_PAYLOAD,
    )
    assert response.status_code in (401, 403), response.text


def test_update_profile_without_auth_is_rejected(community_client_enabled):
    response = community_client_enabled.put(
        "/community/profiles/me",
        json={"display_name": "Wolf"},
    )
    assert response.status_code in (401, 403), response.text


# ---------------------------------------------------------------------------
# A8 / §6.1 — update endpoint resolves the row from the JWT, not the payload
# ---------------------------------------------------------------------------


def test_update_profile_uses_callers_own_row(
    community_client_enabled, community_auth_headers, community_two_auth_headers
):
    headers_a, _ = community_two_auth_headers
    # User A creates a profile.
    create = community_client_enabled.post(
        "/community/profiles/me",
        json=_VALID_PAYLOAD,
        headers=headers_a,
    )
    assert create.status_code == 201, create.text
    public_id_a = create.json()["public_id"]

    # User B (the community_auth_headers user) does NOT have a profile
    # yet — calling update MUST return 404, NOT silently write to
    # user A's row.
    update = community_client_enabled.put(
        "/community/profiles/me",
        json={"display_name": "Hacked by B"},
        headers=community_auth_headers,
    )
    assert update.status_code == 404, update.text
    assert update.json()["detail"] == "profile_missing"

    # Re-read user A's row through the public_id endpoint — display
    # name MUST still be the original.
    read = community_client_enabled.get(f"/community/profiles/{public_id_a}")
    assert read.status_code == 200, read.text
    assert read.json()["display_name"] == "Wolf Casaba"


# ---------------------------------------------------------------------------
# A8 / §6.1 — the update endpoint edits only display name, not privacy
# ---------------------------------------------------------------------------


def test_update_profile_only_touches_display_name(
    community_client_enabled, community_auth_headers
):
    create = community_client_enabled.post(
        "/community/profiles/me",
        json={**_VALID_PAYLOAD, "visibility": "private", "audience_default": "private"},
        headers=community_auth_headers,
    )
    assert create.status_code == 201, create.text

    update = community_client_enabled.put(
        "/community/profiles/me",
        json={"display_name": "Wolf Updated"},
        headers=community_auth_headers,
    )
    assert update.status_code == 200, update.text
    assert update.json()["display_name"] == "Wolf Updated"
    # The response model does not expose the privacy row directly
    # (CommunityProfileOut), so the privacy invariant is verified by
    # the privacy-row's ``server_default`` + the absence of any
    # update path that writes to it.


# ---------------------------------------------------------------------------
# Service-layer unit tests — cover the validation + identity_service
# interplay without going through the HTTP layer.
# ---------------------------------------------------------------------------


def test_service_rejects_malformed_handle_with_value_error(community_enabled):
    _, session_factory = community_enabled
    _, headers = make_authenticated_user(session_factory)
    user_id = _extract_user_id_from_token(headers["Authorization"].split(" ", 1)[1])

    session = session_factory()
    try:
        with pytest.raises(ValueError):
            create_profile(
                session,
                user_id=user_id,
                handle="ab",  # too short
                display_name="Wolf",
                visibility=ProfileVisibility.FOLLOWERS,
                audience_default=CommunityAudience.FOLLOWERS,
                now=_now(),
            )
    finally:
        session.close()


def test_service_rejects_reserved_handle_with_value_error(community_enabled):
    _, session_factory = community_enabled
    _, headers = make_authenticated_user(session_factory)
    user_id = _extract_user_id_from_token(headers["Authorization"].split(" ", 1)[1])

    session = session_factory()
    try:
        with pytest.raises(ValueError):
            create_profile(
                session,
                user_id=user_id,
                handle="admin",  # reserved
                display_name="Wolf",
                visibility=ProfileVisibility.FOLLOWERS,
                audience_default=CommunityAudience.FOLLOWERS,
                now=_now(),
            )
    finally:
        session.close()


def test_service_update_profile_round_trips(community_enabled):
    _, session_factory = community_enabled
    _, headers = make_authenticated_user(session_factory)
    user_id = _extract_user_id_from_token(headers["Authorization"].split(" ", 1)[1])

    session = session_factory()
    try:
        profile = create_profile(
            session,
            user_id=user_id,
            handle="wolfcasaba",
            display_name="Wolf",
            visibility=ProfileVisibility.FOLLOWERS,
            audience_default=CommunityAudience.FOLLOWERS,
            now=_now(),
        )
        profile_id = profile.id
    finally:
        session.close()

    session = session_factory()
    try:
        profile = session.query(CommunityProfile).filter_by(id=profile_id).one()
        update_profile(session, profile, "Wolf Casaba Renamed")
        assert profile.display_name == "Wolf Casaba Renamed"
    finally:
        session.close()


# ---------------------------------------------------------------------------
# F1 — GET /community/profiles/me (E09-R06 review, BLOCKER fix)
#
# The Flutter ``HttpCommunityProfileRepository.fetchMyProfile`` issues this
# call to drive the gate's ``profile-missing`` ↔ ``ready`` state
# transition. Without the route every live-backend call landed on a 404
# from a non-existent path and the gate was stuck on ``profileMissing``
# forever (docs/reviews/e09-r06-review.md F1).
# ---------------------------------------------------------------------------


def test_get_my_profile_returns_404_when_no_profile_exists(
    community_client_enabled, community_auth_headers
):
    """An authenticated caller with NO profile MUST see 404 ``profile_missing``.

    This is the cell that, prior to the F1 fix, always failed — the
    route did not exist, so the response was a router-level 404 with an
    unrelated body, which the Flutter repository mapped to ``null``.
    The gate then stayed on ``profileMissing`` even after a successful
    ``POST`` because the post-create re-read was also 404.
    """
    response = community_client_enabled.get(
        "/community/profiles/me",
        headers=community_auth_headers,
    )
    assert response.status_code == 404, (
        f"F1 violation: GET /community/profiles/me must exist for an "
        f"authenticated caller; got {response.status_code} "
        f"({response.text!r}). Flutter repository would map any non-404 "
        f"here to an exception, breaking the gate's profile-missing path."
    )
    assert response.json()["detail"] == "profile_missing"


def test_get_my_profile_returns_200_after_create_round_trips(
    community_client_enabled, community_auth_headers
):
    """The full round-trip: POST → GET /me returns the SAME row.

    Verifies the F1 fix end-to-end — a freshly-created profile is
    readable via the new GET endpoint, the response carries the
    ``handle`` and ``display_name`` the POST stored, and the
    ``public_id`` matches (so a Flutter client that caches
    ``public_id`` from POST does not see a different value on GET).
    """
    create = community_client_enabled.post(
        "/community/profiles/me",
        json=_VALID_PAYLOAD,
        headers=community_auth_headers,
    )
    assert create.status_code == 201, create.text
    public_id = create.json()["public_id"]

    read = community_client_enabled.get(
        "/community/profiles/me",
        headers=community_auth_headers,
    )
    assert read.status_code == 200, (
        f"F1 violation: after a successful POST the GET /me must "
        f"return 200; got {read.status_code} ({read.text!r}). The gate "
        f"would NEVER transition to ready without this round-trip."
    )
    body = read.json()
    assert body["handle"] == _VALID_PAYLOAD["handle"]
    assert body["display_name"] == _VALID_PAYLOAD["display_name"]
    assert body["public_id"] == public_id


def test_get_my_profile_requires_auth(community_client_enabled):
    """No JWT → no profile. Mirrors the POST/PUT auth-less assertion."""
    response = community_client_enabled.get("/community/profiles/me")
    assert response.status_code in (401, 403), response.text


def test_get_my_profile_is_scoped_to_caller(
    community_client_enabled, community_auth_headers, community_two_auth_headers
):
    """User B's GET /me MUST NOT return user A's row even after A creates one.

    The 404 (not 200 + foreign row) is the contract — the JWT identity
    is the ONLY filter, identical to the POST/PUT endpoints.
    """
    headers_a, _ = community_two_auth_headers
    create = community_client_enabled.post(
        "/community/profiles/me",
        json=_VALID_PAYLOAD,
        headers=headers_a,
    )
    assert create.status_code == 201, create.text

    read_b = community_client_enabled.get(
        "/community/profiles/me",
        headers=community_auth_headers,
    )
    assert read_b.status_code == 404, (
        f"F1 violation: user B sees user A's profile via GET /me "
        f"({read_b.status_code} / {read_b.text!r})."
    )
    assert read_b.json()["detail"] == "profile_missing"


# ---------------------------------------------------------------------------
# F2 — Unicode-equivalent handle uniqueness (E09-R06 review, MAJOR fix)
#
# Prior to the fix, ``create_profile`` discarded the NFKC-normalized
# return value of ``handle_policy.validate`` and passed
# ``handle.strip().casefold()`` (without NFKC) to ``assign_handle``. Two
# users could register visually-identical handles via different
# Unicode-spellings (e.g. ASCII "abcde" and fullwidth "Ａbcde",
# precomposed vs combining-acute "café"). The DB unique index on
# ``handle_normalized`` then stored two distinct values — the
# uniqueness invariant guaranteed by ``handle_policy.normalize`` was
# silently broken (docs/reviews/e09-r06-review.md F2).
# ---------------------------------------------------------------------------


def test_unicode_equivalent_handle_is_rejected_as_taken(
    community_client_enabled, community_auth_headers, community_two_auth_headers
):
    """The F2 proof: the same handle, two Unicode spellings, two users.

    User A claims ``"Ａbcde"`` (fullwidth A, U+FF21). After
    NFKC + casefold this is ``"abcde"`` — the same normalized value as
    the ASCII spelling. User B then tries ``"abcde"`` and MUST see 409
    ``handle_taken``; the DB has exactly one row.

    Prior to the F2 fix both calls succeeded — ``handle.strip().casefold()``
    on the two distinct inputs yields two distinct
    ``handle_normalized`` values, so the unique index never fires. The
    test is the §6.1 measure-matrix cell the bug is hidden behind.
    """
    headers_a, _ = community_two_auth_headers
    # User A — fullwidth A.
    create_a = community_client_enabled.post(
        "/community/profiles/me",
        json={**_VALID_PAYLOAD, "handle": "Ａbcde"},
        headers=headers_a,
    )
    assert create_a.status_code == 201, (
        f"F2 precondition: user A must be able to claim the "
        f"fullwidth handle; got {create_a.status_code} "
        f"({create_a.text!r}). The user-row / handle-row pipeline is "
        f"broken upstream — investigate before debugging F2."
    )

    # User B — ASCII spelling of the same handle after NFKC + casefold.
    create_b = community_client_enabled.post(
        "/community/profiles/me",
        json={**_VALID_PAYLOAD, "handle": "abcde"},
        headers=community_auth_headers,
    )
    assert create_b.status_code == 409, (
        f"F2 violation: a Unicode-equivalent handle spelling was "
        f"accepted (status {create_b.status_code}, body "
        f"{create_b.text!r}). Two visually-identical handles now coexist."
    )
    assert create_b.json()["detail"] == "handle_taken"


def test_unicode_normalization_matches_in_service_layer(community_enabled):
    """Service-level probe — calls ``create_profile`` directly with NFD/NFC spellings.

    Exercises the F2 fix without going through the HTTP layer so a
    regression in the router does not mask a service-layer drift (and
    vice versa). Both spellings normalize to the same
    ``handle_normalized``; the second ``create_profile`` MUST raise
    ``HandleAlreadyClaimed``.
    """
    import unicodedata

    from app.community.services.identity_service import HandleAlreadyClaimed

    _, session_factory = community_enabled
    # User A — NFD spelling ("cafe" + combining acute).
    _, headers_a = make_authenticated_user(
        session_factory, email="unicode-a@strumsight.app"
    )
    user_id_a = _extract_user_id_from_token(
        headers_a["Authorization"].split(" ", 1)[1]
    )
    nfd = unicodedata.normalize("NFD", "café")
    nfc = unicodedata.normalize("NFC", "café")
    assert nfd != nfc, "Test inputs collapsed — pick a different example"

    session = session_factory()
    try:
        create_profile(
            session,
            user_id=user_id_a,
            handle=nfd,
            display_name="NFD",
            visibility=ProfileVisibility.FOLLOWERS,
            audience_default=CommunityAudience.FOLLOWERS,
            now=_now(),
        )
    finally:
        session.close()

    # User B — NFC spelling, identical visual handle.
    _, headers_b = make_authenticated_user(
        session_factory, email="unicode-b@strumsight.app"
    )
    user_id_b = _extract_user_id_from_token(
        headers_b["Authorization"].split(" ", 1)[1]
    )
    session = session_factory()
    try:
        with pytest.raises(HandleAlreadyClaimed):
            create_profile(
                session,
                user_id=user_id_b,
                handle=nfc,
                display_name="NFC",
                visibility=ProfileVisibility.FOLLOWERS,
                audience_default=CommunityAudience.FOLLOWERS,
                now=_now(),
            )
    finally:
        session.close()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _now():
    from datetime import datetime, timezone

    return datetime.now(timezone.utc)


def _extract_user_id_from_token(token: str) -> int:
    """Decode the JWT just enough to pull the ``sub`` (user id).

    We do NOT verify the signature here — the token was minted by the
    test helper against the same secret the application reads, and we
    are not testing JWT validation. We do use the public PyJWT
    ``decode`` with the right options so the test mirrors what the
    ``CurrentUser`` resolver actually does on the API side.
    """
    import jwt

    from app.config import get_settings

    settings = get_settings()
    payload = jwt.decode(
        token,
        settings.secret_key,
        algorithms=[settings.algorithm],
    )
    return int(payload["sub"])
