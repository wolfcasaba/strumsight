"""Community profile service — E09-R06, ADR 0400 §2–3.

The single, module-internal authority for the two write operations on
``community_profiles``: explicit onboarding (``create_profile``) and the
display-name-only edit (``update_profile``). The router layer translates
HTTP requests into calls here; the SQLAlchemy commit boundaries live here,
so the §5.3 / A8 invariant ("the DB unique index is the final enforcement,
not just a SELECT") is implemented in one place, not duplicated across
routers.

Why this module is separate from ``identity_service``:

* ``identity_service`` (Kör 3, ADR 0397) owns the handle-related write
  primitives (``assign_handle``, ``commit_with_uniqueness_check``) and the
  ``HandleAlreadyClaimed`` exception. The Community profile has a handle too,
  so this service **imports** those primitives and chains them with the
  ``community_profiles`` row create and the ``community_privacy_settings``
  row create in a single transaction.
* The display-name update is a different lifecycle (no handle, no
  privacy-row write) — kept on the same service so the router's two new
  endpoints share one dependency surface.

The §5.3 ordering inside ``create_profile`` is the load-bearing contract:
the function builds a row, then calls ``assign_handle`` (which writes the
unique-indexed column), then writes the privacy row, and ONLY THEN commits
through ``commit_with_uniqueness_check``. If the unique index on
``community_profiles.user_id`` (ADR 0396 §1, the 1:1 invariant) rejects the
write, the ``commit_with_uniqueness_check`` ``try``/``except IntegrityError``
turns the DB error into ``HandleAlreadyClaimed`` — the §6.1 measure-matrix
"A8" cell. The router additionally performs a pre-``SELECT`` for a
friendly ``ProfileAlreadyExists`` → 409, but the DB-level check is the
ground truth (a regression that drops the pre-SELECT is a UX bug, not a
correctness bug; a regression that drops the ``except IntegrityError`` is
correctness + concurrency).
"""

from __future__ import annotations

from datetime import datetime

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..models.profile import CommunityPrivacySettings, CommunityProfile
from ..policies.access_policy import CommunityAudience, ProfileVisibility
from ..policies.handle_policy import validate
from .identity_service import (
    HandleAlreadyClaimed,
    assign_handle,
    commit_with_uniqueness_check,
)


class ProfileAlreadyExists(Exception):
    """The ``user_id`` already owns a ``CommunityProfile`` row.

    Raised as a friendly pre-``SELECT`` outcome by the router (a clean 409
    before the DB commit). The DB unique index would also reject a second
    ``INSERT``; that path lands here as ``HandleAlreadyClaimed`` via
    ``commit_with_uniqueness_check`` (the §5.3 / A8 measure-matrix cell).
    """


def create_profile(
    db: Session,
    *,
    user_id: int,
    handle: str,
    display_name: str,
    visibility: ProfileVisibility,
    audience_default: CommunityAudience,
    now: datetime,
) -> CommunityProfile:
    """Create a community profile for ``user_id`` in a single transaction.

    The function:

    1. Normalizes + validates the handle via ``handle_policy.validate``
       (raises ``ValueError`` on rejection — the router maps this to 400).
    2. Inserts the ``community_profiles`` row, flushing to obtain the
       autoincrement ``id`` (the handle-write needs it). The flush is
       the FIRST place the ``community_profiles.user_id`` unique index
       can fire — this is the §5.3 / A8 measure-matrix "two concurrent
       creates, both succeed" race. Any ``IntegrityError`` at this
       step is translated to ``HandleAlreadyClaimed`` so the router's
       409 mapping is consistent.
    3. Calls ``assign_handle`` to populate the unique-indexed handle
       columns (raises ``HandleAlreadyClaimed`` on a handle conflict).
    4. Inserts the ``community_privacy_settings`` row in the same
       transaction.
    5. Commits through ``commit_with_uniqueness_check`` so any
       last-second DB-level uniqueness error is the final enforcement
       layer (the §5.3 belt-and-braces on top of the pre-``SELECT`` in
       the router).

    The privacy default is the **caller's choice**, not a hard-coded
    ``"followers"`` — the brief §5.2 / ADR 0400 §2 contract: the
    onboarding UI picks it and the service stores what it was told.
    The DB column has a ``server_default="followers"`` for rows that
    bypass this code path (a future round, perhaps), so a
    no-``visibility`` write would still get the safe default; the
    current callers always pass an explicit value.
    """
    # Step 1 — handle format. ``validate`` raises ``ValueError`` on a
    # malformed, reserved or blocked input; the router converts that
    # to a 400. Normalization is applied here so the
    # ``assign_handle`` argument is the canonical form.
    normalized = validate(handle)

    profile = CommunityProfile(
        user_id=user_id,
        display_name=display_name.strip(),
    )

    # Step 2 — INSERT + flush. The flush is what actually fires the
    # ``user_id`` unique-index check on this row; an
    # ``IntegrityError`` here is the A8 measure-matrix "two concurrent
    # creates, both succeed" race. The router's friendly pre-SELECT
    # is the FIRST line of defense (it converts 99% of the cases to a
    # clean 409 ``profile_exists``), but the DB-level flush check is
    # the second, race-proof line — the §5.3 / A8 contract.
    try:
        db.add(profile)
        db.flush()  # profile.id is now assigned — required by assign_handle.
    except IntegrityError as exc:
        # The user_id unique index rejected the INSERT. Roll back the
        # pending write and translate to the same exception family
        # the router already maps to 409 ``handle_taken`` (the router
        # is expected to call ``create_profile`` AFTER its own
        # pre-SELECT; a flush-time ``IntegrityError`` is the
        # concurrent-INSERT path the pre-SELECT cannot catch).
        db.rollback()
        raise HandleAlreadyClaimed(str(exc)) from exc

    # Step 3 — handle. The unique index on ``handle_normalized`` is the
    # enforcement; ``assign_handle`` raises ``HandleAlreadyClaimed`` on
    # conflict. We MUST hand it the policy-normalized form (NFKC + casefold
    # + strip), not a freshly-computed ``handle.strip().casefold()`` —
    # the latter is missing the NFKC step, so two Unicode-equivalent
    # inputs (``"abcde"`` and fullwidth ``"Ａbcde"``, or NFD- vs
    # NFC-spelled ``"café"``) would store distinct ``handle_normalized``
    # values and the uniqueness invariant
    # (``handle_policy.normalize`` doc-comment) would be silently
    # broken. Fixed in the E09-R06 review's fix round (F2 MAJOR).
    assign_handle(db, profile.id, handle.strip(), normalized)

    # Step 4 — privacy row. Same transaction; a failure here rolls back
    # the profile + handle writes too.
    db.add(
        CommunityPrivacySettings(
            profile_id=profile.id,
            visibility=visibility.value,
            audience_default=audience_default.value,
            updated_at=now,
        )
    )

    # Step 5 — commit. ``commit_with_uniqueness_check`` translates a
    # ``handle_normalized`` unique-index rejection to
    # ``HandleAlreadyClaimed`` so the §5.3 enforcement is at one
    # chokepoint.
    commit_with_uniqueness_check(db)

    db.refresh(profile)
    return profile


def update_profile(
    db: Session,
    profile: CommunityProfile,
    display_name: str,
) -> CommunityProfile:
    """Update the display name on an existing community profile.

    Privacy changes are a separate endpoint (Kör 4's ``privacy.py``) and
    are NOT touched here — the ADR 0400 §3 contract.

    The commit is a plain ``db.commit()``: there is no
    ``handle_normalized`` write in this path, and ``user_id`` is
    immutable, so the unique indexes cannot fire. A regression that
    later adds a unique-indexed column here MUST re-evaluate this
    decision (wrap the commit in ``commit_with_uniqueness_check`` or
    its equivalent).
    """
    profile.display_name = display_name.strip()
    db.add(profile)
    db.commit()
    db.refresh(profile)
    return profile


__all__ = [
    "ProfileAlreadyExists",
    "create_profile",
    "update_profile",
]
