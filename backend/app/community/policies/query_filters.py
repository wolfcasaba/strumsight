"""Shared DB-backed read-path filters for the Community module (E09-R08,
ADR 0402 §D2 / §D4).

This module owns the read-path helpers that depend on the
``community_blocks`` table:

* :func:`is_blocked_pair` — single-pair predicate (the §D4 pure-helper
  that a future club feature — Kör 24 — calls to compute the
  placeholder-display). The same function is the §D2 building block
  used by ``routers/social_graph.py::get_followers`` /
  ``get_following`` to gate the response.

* :func:`exclude_blocked_from_public_ids` — page-level filter that
  drops any blocked row from a list of public_ids, used by the
  same two routers. Keeping it here means a future endpoint that
  also wants to filter a profile-id list by the viewer's block set
  reuses this single function instead of re-implementing the join
  (the §9 "elfelejtett endpoint" risk in brief §9).

* :func:`list_block_pairs_for_viewer` — internal helper that the
  page-filter uses to materialise the viewer's blocked profile
  ids in one query (so a 50-row page costs one block-table read,
  not 50).

The module is deliberately DB-coupled (it imports the ORM model).
It is the bridge between the §D2 read-path policy (a pure function
over ``RelationshipContext``) and the schema-only service layer —
the alternative — duplicating the block lookup in every router —
is the measured footgun the §D2 brief calls out.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterable

from sqlalchemy import and_, or_, select
from sqlalchemy.orm import Session

from ..models.profile import CommunityProfile
from ..models.safety_relationships import CommunityBlock


def is_blocked_pair(
    db: Session,
    *,
    profile_id_a: int,
    profile_id_b: int,
) -> bool:
    """``True`` if ``profile_id_a`` and ``profile_id_b`` are connected
    by a block edge in EITHER direction.

    The block relation is directional — ``a`` can block ``b`` without
    ``b`` blocking ``a`` — but for every read-path policy the brief
    treats the symmetric predicate as "mutually invisible". That is
    the §D2 invariant: the two directions collapse to a single bool
    because the access_policy then takes the same branch regardless
    of who initiated the block.

    Self-pairs (a == b) are always treated as non-blocked — there
    is no row possible (the DB CHECK forbids it). The helper still
    takes the constant-time ``False`` path rather than a query.
    """
    if profile_id_a == profile_id_b:
        return False
    row = db.execute(
        select(CommunityBlock.id)
        .where(
            or_(
                and_(
                    CommunityBlock.blocker_profile_id == profile_id_a,
                    CommunityBlock.blocked_profile_id == profile_id_b,
                ),
                and_(
                    CommunityBlock.blocker_profile_id == profile_id_b,
                    CommunityBlock.blocked_profile_id == profile_id_a,
                ),
            )
        )
        .limit(1)
    ).first()
    return row is not None


def list_block_pairs_for_viewer(
    db: Session,
    *,
    viewer_profile_id: int,
) -> set[int]:
    """Return the set of internal profile ids the viewer is connected
    to by a block edge in EITHER direction.

    Used by the page-level filter :func:`exclude_blocked_from_public_ids`
    so a 50-row page costs one block-table read. The set carries
    internal bigints (the model's PK); the page filter translates
    back to public_ids via the ``community_profiles`` table when
    needed.
    """
    stmt = select(
        CommunityBlock.blocker_profile_id, CommunityBlock.blocked_profile_id
    ).where(
        or_(
            CommunityBlock.blocker_profile_id == viewer_profile_id,
            CommunityBlock.blocked_profile_id == viewer_profile_id,
        )
    )
    rows = db.execute(stmt).all()
    out: set[int] = set()
    for blocker_id, blocked_id in rows:
        out.add(blocker_id)
        out.add(blocked_id)
    out.discard(viewer_profile_id)
    return out


def resolve_profile_ids(
    db: Session,
    *,
    public_ids: Iterable[uuid.UUID],
) -> dict[uuid.UUID, int]:
    """Translate a list of public_ids to internal profile ids.

    The block-side query operates on internal ids (the PK), while
    the router-side response carries public_ids (the public
    surface). The helper bridges the two — a single
    ``community_profiles`` SELECT keyed on the public_id column.
    Unknown public_ids are silently dropped; they are the caller's
    problem (a foreign-key mismatch would have failed earlier).
    """
    public_id_list = list(public_ids)
    if not public_id_list:
        return {}
    rows = db.execute(
        select(CommunityProfile.public_id, CommunityProfile.id).where(
            CommunityProfile.public_id.in_(public_id_list)
        )
    ).all()
    return {row[0]: row[1] for row in rows}


def filter_public_ids_against_viewer_blocks(
    db: Session,
    *,
    viewer_profile_id: int,
    public_ids: Iterable[uuid.UUID],
) -> list[uuid.UUID]:
    """Drop any public_id from ``public_ids`` whose owner is in a
    block relationship with ``viewer_profile_id`` (either direction).

    Used by the ``get_followers`` / ``get_following`` routers to
    honour the §D2 block-filter invariant without re-implementing
    the join. A future read endpoint that has access to a JWT-
    resolved viewer and a list of profile public_ids (e.g. search,
    feed, member listing) MUST call this helper instead of
    hand-rolling the block join — that is the §9
    "elfelejtett endpoint" risk the A5 acceptance cell pins.
    """
    public_id_list = list(public_ids)
    if not public_id_list:
        return []
    blocked_internal = list_block_pairs_for_viewer(
        db, viewer_profile_id=viewer_profile_id
    )
    if not blocked_internal:
        return public_id_list
    public_to_internal = resolve_profile_ids(
        db, public_ids=public_id_list
    )
    blocked_public_ids = {
        public_id
        for public_id, internal_id in public_to_internal.items()
        if internal_id in blocked_internal
    }
    return [pid for pid in public_id_list if pid not in blocked_public_ids]


__all__ = [
    "filter_public_ids_against_viewer_blocks",
    "is_blocked_pair",
    "list_block_pairs_for_viewer",
    "resolve_profile_ids",
]
