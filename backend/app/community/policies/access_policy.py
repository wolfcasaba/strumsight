"""Profile + content access policy — E09-R04, ADR 0398.

This module is the SINGLE source of truth for "can this viewer see this
profile / this piece of content?" — every read path (profile GET, post GET,
feed GET, comment GET) will route through here in Kör 11/13+. The §5.1
invariant ("a privacy policy SZERVEROLDALI, a kliens UI-elrejtés nem
biztonsági határ") is what makes this module load-bearing: a future router
that answers from a cached/cloned copy without consulting this module would
be the §6.1 IDOR regression the matrix names.

**Evaluation order is the security contract.** A blocked viewer always sees
``SUMMARY`` (private-as-if) regardless of the profile's actual visibility
(ADR 0398 §3, brief §5.2, A2). The order is *not* negotiable — moving the
block check after the audience check would expose a race-window where the
public profile leaks to a blocked viewer. The §6.1 valódi-sértés próba is
realised by swapping the order and watching A2 go red.

The module is deliberately pure: no DB, no FastAPI, no settings import. The
``RelationshipContext`` is a synthetic, caller-constructed param object (the
follow/block/club data is Kör 7/8/24 — none of that exists yet), so the
policy tests can pin every cell of the matrix without booting the API. The
field names ``blocked``, ``is_follower``, ``viewer_is_owner``,
``is_club_member`` are part of a *forward contract*: the Kör 8 brief already
quotes ``RelationshipContext.blocked`` by name, so a rename here is not a
local change — it would break a downstream brief that is already locked in.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum


class ProfileVisibility(str, Enum):
    """Profile-level visibility setting (the privacy row's ``visibility`` column)."""

    PUBLIC = "public"
    FOLLOWERS = "followers"
    PRIVATE = "private"


class CommunityAudience(str, Enum):
    """Per-content audience setting (post / comment / feed item)."""

    PUBLIC = "public"
    FOLLOWERS = "followers"
    PRIVATE = "private"


class ProfileAccessLevel(str, Enum):
    """The three levels of access the policy returns.

    ``NONE`` is reserved for a future "profile deleted / moderated" state
    (Kör 27/28) — this round never returns it; blocked + private both
    return ``SUMMARY`` (ADR 0398 §4).
    """

    NONE = "none"
    SUMMARY = "summary"
    FULL = "full"


@dataclass(frozen=True)
class RelationshipContext:
    """Synthetic, caller-constructed relationship description.

    The follow/block/club data lives in tables that don't exist yet (Kör 7
    / 8 / 24), so the future callers — those round's services — will
    populate this dataclass from their own queries and hand it to the
    policy. The policy itself never touches the DB; this is the seam that
    keeps the unit tests pin-able (a fixed dataclass trivially enumerates
    the matrix) and the seam that keeps the future code free to change
    the data source without touching the policy.

    Field-name stability is part of the contract: Kör 8 brief §2 reads
    ``RelationshipContext.blocked`` *by name* from this round. Renaming
    (e.g. ``is_blocked``) is not a local decision.
    """

    viewer_is_owner: bool = False
    blocked: bool = False
    is_follower: bool = False
    is_club_member: bool = False


def relationship_context_from_block_flag(
    *,
    blocked: bool,
    viewer_is_owner: bool = False,
    is_follower: bool = False,
    is_club_member: bool = False,
) -> RelationshipContext:
    """Build a ``RelationshipContext`` from the live block predicate.

    E09-R08 wires the ``RelationshipContext.blocked`` field to the
    actual ``community_blocks`` table via
    ``query_filters.is_blocked_pair``. The routers call the DB helper
    first, then feed the resulting ``bool`` into this builder — the
    policy stays DB-free (ADR 0398 invariant, re-affirmed in ADR 0402
    §D2) while the field still carries live data.
    """
    return RelationshipContext(
        viewer_is_owner=viewer_is_owner,
        blocked=blocked,
        is_follower=is_follower,
        is_club_member=is_club_member,
    )


class CommunityAccessPolicy:
    """The single read-path policy.

    No state, no DB: just a pure function over
    ``(visibility|audience, relationship)``. The two ``evaluate_*`` methods
    exist as separate entry points because the A4 cell names
    followers-only *content* (not profile) — the same matrix shape, but a
    different input axis (the audience field on the post, not the
    visibility field on the profile).

    Future read routers will hold one of these (or a thin wrapper) and
    call the matching method for their resource type. This round ships no
    live router integration (the ``build_community_router`` factory
    doesn't see this module yet — that's a Kör 5+ task per ADR 0396 §3).
    """

    def evaluate_profile_access(
        self,
        visibility: ProfileVisibility,
        relationship: RelationshipContext,
    ) -> ProfileAccessLevel:
        """Return the access level a viewer has on a profile.

        Evaluation order (do NOT reorder):

        1. ``viewer_is_owner`` → ``FULL`` (the owner always sees everything
           of their own, including the privacy settings row).
        2. ``blocked`` → ``SUMMARY`` (the §5.2 invariant: a blocked viewer
           sees the profile AS IF it were private, even when the
           visibility is PUBLIC).
        3. ``visibility == PUBLIC`` → ``FULL``.
        4. ``visibility == FOLLOWERS`` → ``FULL`` if ``is_follower``,
           else ``SUMMARY``.
        5. ``visibility == PRIVATE`` → ``SUMMARY`` (this branch is the
           default for the remaining private case).

        The order matters because step 2 short-circuits before steps 3
        and 4. Reordering (audience-check first) would let a blocked
        viewer of a public profile briefly see ``FULL`` — the §6.1
        valódi-sértés próba flips this and asserts A2 goes red.
        """
        if relationship.viewer_is_owner:
            return ProfileAccessLevel.FULL
        if relationship.blocked:
            return ProfileAccessLevel.SUMMARY
        if visibility is ProfileVisibility.PUBLIC:
            return ProfileAccessLevel.FULL
        if visibility is ProfileVisibility.FOLLOWERS:
            return (
                ProfileAccessLevel.FULL
                if relationship.is_follower
                else ProfileAccessLevel.SUMMARY
            )
        # PRIVATE — the only visibility left.
        return ProfileAccessLevel.SUMMARY

    def evaluate_content_access(
        self,
        audience: CommunityAudience,
        relationship: RelationshipContext,
    ) -> bool:
        """Return whether a viewer may see a single piece of content.

        Same evaluation order as ``evaluate_profile_access``:

        1. ``viewer_is_owner`` → ``True`` (the owner always sees their
           own content).
        2. ``blocked`` → ``False`` (the §5.2 invariant again — a blocked
           viewer sees nothing of the owner's content).
        3. ``audience == PUBLIC`` → ``True``.
        4. ``audience == FOLLOWERS`` → ``is_follower``.
        5. ``audience == PRIVATE`` → ``False``.

        The function is intentionally bool-typed (not ``ProfileAccessLevel``)
        because posts/comments have no "summary" tier — either the viewer
        sees the body or they don't. The §6.1 measure-matrix on the A2 row
        reads through ``evaluate_profile_access`` (which has the summary
        tier); the content variant here exists to exercise the same
        ordering on the same inputs, so a future regression that swaps
        the order on ONE of the two methods but not the other would be
        caught by a paired test (see ``test_content_evaluate_uses_same_order``
        in ``test_access_policy.py``).
        """
        if relationship.viewer_is_owner:
            return True
        if relationship.blocked:
            return False
        if audience is CommunityAudience.PUBLIC:
            return True
        if audience is CommunityAudience.FOLLOWERS:
            return relationship.is_follower
        # PRIVATE — the only audience left.
        return False


__all__ = [
    "CommunityAccessPolicy",
    "CommunityAudience",
    "ProfileAccessLevel",
    "ProfileVisibility",
    "RelationshipContext",
    "relationship_context_from_block_flag",
]
