"""Club permission matrix — E09-R24, ADR 0420 §5.2 / §D4 / §D5.

Single source of truth for "may this role perform this action inside
this club". Every role-mutating method in
``services.club_service`` calls into this module — no service-layer
code path may re-derive a permission decision inline.

Design contract (the §5.2 / §D4 invariants — these are the load-bearing
guarantees the §6 acceptance matrix pins):

* **Three roles, no fourth.** The matrix covers ``owner``,
  ``moderator`` and ``member`` — the same wire values as the Kör 5
  ``ClubRole`` enum. A role outside this set is rejected at the
  service layer (``is_allowed_club_role`` in
  ``models/club.py``); this module assumes the input is one of the
  three.

* **Server-side enforcement only.** §5.2 explicitly forbids
  client-side "trust the wire" role checks — a member who knows the
  ``moderator`` role string must not be able to author a moderator
  action. The matrix is the only authority.

* **Ownership transfer is a single named action.** ``TRANSFER_OWNERSHIP``
  is the A1 / A8 / D4 load-bearing operation: a lone owner must
  transfer BEFORE they can leave. The matrix marks it owner-only
  (you cannot transfer ownership you do not have).

* **Role change is moderator+ for member targets, owner-only for
  moderator targets.** The §5.3 invariant: a moderator cannot promote
  themselves to owner by flipping their own row, only the owner can
  touch moderator / owner rows. Demoting a moderator is owner-only.
  Promoting a member is moderator+.

* **Block-side gate is NOT in this module.** The Kör 8
  ``query_filters.is_blocked_pair`` predicate is the safety
  gate; this module only models the role-action matrix. The
  ``club_service`` layer calls BOTH the permission matrix AND the
  block predicate — splitting them keeps the policy unit-testable
  without booting the DB.

This module is deliberately pure (no DB, no FastAPI, no settings). It
takes a role + action + target context and returns a boolean. The
service layer is the only caller.
"""

from __future__ import annotations

from enum import Enum

from ..models.club import (
    CLUB_ROLE_MEMBER,
    CLUB_ROLE_MODERATOR,
    CLUB_ROLE_OWNER,
)


class ClubAction(str, Enum):
    """The set of named actions the permission matrix covers.

    Every mutating service method maps to ONE of these — the matrix
    is a flat dispatch (no chaining). Adding a new action here
    without updating ``may_perform`` is a wiring bug — the matrix
    is closed.
    """

    # Read-side (every member can read).
    LIST_MEMBERS = "list_members"
    FETCH_CLUB = "fetch_club"

    # Membership lifecycle.
    REQUEST_JOIN = "request_join"
    ACCEPT_JOIN_REQUEST = "accept_join_request"  # owner / moderator
    LEAVE_CLUB = "leave_club"

    # Invite lifecycle.
    INVITE_MEMBER = "invite_member"
    CANCEL_INVITE = "cancel_invite"

    # Removal / role mutation.
    REMOVE_MEMBER = "remove_member"
    PROMOTE_TO_MODERATOR = "promote_to_moderator"
    DEMOTE_TO_MEMBER = "demote_to_member"

    # Club settings.
    UPDATE_CLUB = "update_club"  # description / visibility

    # Ownership transfer — A1 / A8 / D4 load-bearing.
    TRANSFER_OWNERSHIP = "transfer_ownership"

    # Archive / delete the whole club — owner-only.
    ARCHIVE_CLUB = "archive_club"


class ClubRoleView(str, Enum):
    """The target row's current role — used for role-change decisions.

    The ``*_TO_MODERATOR`` / ``*_TO_MEMBER`` actions take a target
    role so the matrix can reject self-promotion (a moderator cannot
    promote themselves to owner — the matrix simply has no such
    action; a moderator cannot promote a member to owner — there is
    no ``PROMOTE_TO_OWNER`` action, ``TRANSFER_OWNERSHIP`` is the
    only path).
    """

    OWNER = CLUB_ROLE_OWNER
    MODERATOR = CLUB_ROLE_MODERATOR
    MEMBER = CLUB_ROLE_MEMBER


def may_perform(
    *,
    actor_role: str,
    action: ClubAction,
    target_role: str | None = None,
    is_self: bool = False,
) -> bool:
    """Return ``True`` when an actor with ``actor_role`` may perform
    ``action`` against an actor with ``target_role`` (or no target
    when the action is target-less).

    The matrix is exhaustive — every ``ClubAction`` returns a
    boolean. An unknown actor role returns ``False`` (fail-closed).
    The ``is_self`` flag short-circuits the ``leave_club`` and
    ``transfer_ownership`` paths: an owner cannot transfer ownership
    to themselves (the A1 / D4 contract — the new owner must be a
    different profile).
    """
    if actor_role not in _ALLOWED_ROLES:
        return False

    # --- Read-side (every role may read).
    if action in (ClubAction.LIST_MEMBERS, ClubAction.FETCH_CLUB):
        return True

    # --- Owner-only.
    if action in (
        ClubAction.TRANSFER_OWNERSHIP,
        ClubAction.ARCHIVE_CLUB,
        ClubAction.UPDATE_CLUB,
    ):
        if action is ClubAction.TRANSFER_OWNERSHIP and is_self:
            return False
        return actor_role == CLUB_ROLE_OWNER

    # --- Moderator+ (owner OR moderator) may act on a member target.
    if action in (
        ClubAction.REMOVE_MEMBER,
        ClubAction.PROMOTE_TO_MODERATOR,
        ClubAction.DEMOTE_TO_MEMBER,
        ClubAction.INVITE_MEMBER,
        ClubAction.CANCEL_INVITE,
        ClubAction.ACCEPT_JOIN_REQUEST,
    ):
        # Promoting a member is moderator+; demoting a moderator
        # is OWNER-ONLY (the §5.3 invariant — a moderator cannot
        # demote another moderator).
        if action is ClubAction.DEMOTE_TO_MEMBER:
            if actor_role != CLUB_ROLE_OWNER:
                return False
            return target_role in (None, CLUB_ROLE_MODERATOR)
        if actor_role not in (CLUB_ROLE_OWNER, CLUB_ROLE_MODERATOR):
            return False
        # The target must be a member (or no target for invite /
        # accept — those operate on a pending row, not a member row).
        if action is ClubAction.PROMOTE_TO_MODERATOR:
            return target_role in (None, CLUB_ROLE_MEMBER)
        return True

    # --- Membership lifecycle (the actor's own relationship).
    if action is ClubAction.LEAVE_CLUB:
        # Any role may leave (owner included — but the service
        # layer ALSO requires the A1 ownership-transfer step
        # before the owner's row is deleted).
        return True
    if action is ClubAction.REQUEST_JOIN:
        # Caller is not yet a member — anyone (signed-in) may
        # request to join; the service layer applies the visibility
        # gate.
        return True

    # Fail-closed — an unmodelled action returns False.
    return False


def assert_may(
    *,
    actor_role: str,
    action: ClubAction,
    target_role: str | None = None,
    is_self: bool = False,
) -> None:
    """Raise :class:`ClubPermissionDenied` when ``may_perform`` returns
    ``False``. The convenience wrapper the service layer calls.
    """
    if not may_perform(
        actor_role=actor_role,
        action=action,
        target_role=target_role,
        is_self=is_self,
    ):
        raise ClubPermissionDenied(f"role={actor_role!r} may not {action.value}")


class ClubPermissionDenied(Exception):
    """The actor's role is not authorised for the requested action.

    Translated to HTTP 403 by the router layer (a future round —
    the Kör 24 service raises this directly).
    """


# Internal — the matrix is closed; an unknown role returns False.
_ALLOWED_ROLES: frozenset[str] = frozenset(
    {CLUB_ROLE_OWNER, CLUB_ROLE_MODERATOR, CLUB_ROLE_MEMBER}
)


__all__ = [
    "ClubAction",
    "ClubPermissionDenied",
    "ClubRoleView",
    "assert_may",
    "may_perform",
]
