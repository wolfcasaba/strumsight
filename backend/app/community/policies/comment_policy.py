r"""Comment ownership / moderation policy — E09-R16, ADR 0407 §D2.

This module is the SINGLE source of truth for "may this caller delete
this comment?" — the comment-side equivalent of the Kör 4
``CommunityAccessPolicy``. The policy is deliberately pure: no DB, no
FastAPI, no settings import — the inputs are the four identifiers a
caller has already resolved and an explicit ``is_moderator: bool`` flag.

**Why ``is_moderator`` is an explicit parameter, NOT a DB-mező**
(ADR 0407 §D2). The brief §0.0 D2 records the measured gap:
``grep -n "role\|moderator\|is_staff\|is_admin" backend/app/models.py
backend/app/community/models/profile.py`` returns 0 matches — there is
NO live moderator / admin / staff column on either ``User`` or
``CommunityProfile``. Adding one (or a separate ``moderators`` table)
would touch the Kör 2 ``models/profile.py`` (a domain tilos zóna in
this round) AND would preempt the Kör 26/27 admin-auth architecture
decision, which is out of scope for E09-R16.

The cleaner seam — and the one the brief §6.1 A5 measure-matrix
explicitly exercises — is an explicit, caller-supplied boolean. The
Kör 26/27 admin-auth round can then wire it from any source (DB
column, separate table, JWT claim) without changing this function's
signature. The §6.1 A5 test calls ``can_delete(is_moderator=True)``
directly with a pinned set of identifiers, the same way
``CommunityAccessPolicy``'s tests pin a synthetic
``RelationshipContext`` — a pure-function policy with caller-supplied
inputs is the precedent.

**Authorization matrix (the §6 A5 contract):**

| Actor vs comment                       | Verdict |
|----------------------------------------|---------|
| Comment author deletes own comment     | ✅      |
| Post owner deletes any comment on post | ✅      |
| Moderator deletes any comment          | ✅ (via the explicit ``is_moderator=True`` parameter) |
| Anyone else                            | ❌      |

The function is intentionally bool-typed (not a tri-state enum) —
delete either succeeds or fails. The Kör 11 ``PostNotFound`` /
``CommentNotFound`` exceptions are the upstream visibility gate; if
this function says ``True`` AND the row exists AND is not
soft-deleted, the caller proceeds.
"""

from __future__ import annotations


def can_delete(
    *,
    actor_profile_id: int,
    comment_author_profile_id: int,
    post_owner_profile_id: int,
    is_moderator: bool = False,
) -> bool:
    """Return ``True`` when the actor may delete the comment.

    The matrix is the §6 A5 acceptance cell. Three paths grant
    delete authority:

    * ``actor_profile_id == comment_author_profile_id`` — the author
      deletes their own comment.
    * ``actor_profile_id == post_owner_profile_id`` — the post owner
      moderates the discussion under their post.
    * ``is_moderator is True`` — the Kör 26/27 admin-auth round wires
      this from a real source (DB column, table, or JWT claim); this
      round's ``comment_service`` always passes ``is_moderator=False``
      because no admin-auth surface exists yet (the brief §3
      explicit exclusion).

    All four inputs are required keyword arguments — the policy
    never reads from the request body, the JWT, or the DB. The
    caller is responsible for resolving them; this keeps the
    function pure and the A5 measure-matrix pin-able (the §6.1
    valódi-sértés próba calls this function directly with each
    combination of identifiers and asserts the verdict matches the
    matrix).
    """
    if is_moderator:
        return True
    if actor_profile_id == comment_author_profile_id:
        return True
    if actor_profile_id == post_owner_profile_id:
        return True
    return False


__all__ = ["can_delete"]
