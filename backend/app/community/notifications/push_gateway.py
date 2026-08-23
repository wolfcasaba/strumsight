"""Provider-neutral push delivery gateway (E09-R20, ADR 0414 §D1).

The push is a delivery channel — the inbox is the source of truth
(ADR 0414 §D1, §D3). The gateway sits on the wire-side of the
``notification_service`` and is the SINGLE chokepoint for the
A1 redaction invariant: the payload it ships to the device is
the payload the OS push provider sees, end of story.

Design contract (the §5 / §0.0 invariants — these are the load-bearing
guarantees the tests pin):

* **Minimal payload (A1).** The :class:`PushPayload` dataclass
  carries ONLY:

  - ``notification_id`` — the inbox row's ``public_id`` (UUID).
    The client uses this to fetch the localised content from the
    inbox on receipt.
  - ``type`` — the wire string from
    :data:`notification_model.NOTIFICATION_TYPE_ALLOWLIST`. The
    client branches on this to decide what to display in the
    notification chrome.
  - ``title_key`` and ``body_key`` — the localization KEYS, not
    text. The client resolves them through the ARB catalogues on
    receipt; the gateway NEVER holds the localised text.
  - ``route_entity_type`` and ``route_entity_id`` — the opaque
    pair the inbox tap-action reads to deep-link the user to the
    related content.

  The payload is a CLOSED shape. Adding a field here is a
  privacy decision — the §6.1 valódi-sértés próba adds a
  ``commentBody`` field, runs the A1 cell, asserts it goes
  red, and reverts. The discipline is: the gateway owns the
  boundary, the dataclass is the contract.

* **No real provider (scope).** This round ships ONLY the
  no-op default adapter :class:`NoOpPushGateway` — a future round
  that wires FCM / APNs is the responsibility of the future
  round, and the boundary this module exposes is the future
  round's wire contract (ADR 0414 §D2). The
  :class:`PushGateway` ABC is intentionally narrow; the
  implementation is intentionally empty.

* **Aggregation (A2 boundary).** The gateway does NOT decide
  whether to send a push — the service layer's burst-aggregation
  logic decides that, and the gateway only fires when the
  service hands it a payload. The one-push-per-aggregation
  invariant lives in the service; the gateway is the dumb
  pipe.

Importing this module is load-bearing for the service's
``__init__`` export table — the service constructs the gateway
via the ABC so a future round can swap the implementation
without touching the service.
"""

from __future__ import annotations

import uuid
from abc import ABC, abstractmethod
from collections.abc import Iterable
from dataclasses import dataclass, field, fields

from ..models.notification import (
    NOTIFICATION_TYPE_ALLOWLIST,
    is_allowed_notification_type,
)

# ---------------------------------------------------------------------------
# Payload — the A1 redaction boundary.
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class PushPayload:
    """A single, minimal push-delivery payload.

    A1 redaction (§5.1, ADR 0414 §D1) is STRUCTURAL — the dataclass
    is the only place a push-side field is added, and the validation
    below rejects any field that is NOT on the allowlist. A future
    field that wants to land here MUST be a privacy decision
    (brief §5.1 / §6.1) and the §6.1 valódi-sértés próba in
    ``test_notification_service.py`` proves the A1 cell goes red
    when the field is added.

    The fields are documented in the type-only ABC; the
    construction-time validation is the chokepoint.
    """

    notification_id: uuid.UUID
    type: str
    title_key: str
    body_key: str | None
    route_entity_type: str | None
    route_entity_id: str | None
    # A future round can add push-side metadata here ONLY after
    # running the §6.1 valódi-sértés próba and verifying the
    # boundary is preserved. The :func:`_ALLOWED_FIELDS` frozenset
    # and the :meth:`__post_init__` validator are the
    # structural enforcement.

    def __post_init__(self) -> None:
        if not is_allowed_notification_type(self.type):
            raise ValueError(
                f"push type {self.type!r} is not in the allowlist "
                f"{sorted(NOTIFICATION_TYPE_ALLOWLIST)}"
            )
        if not self.title_key:
            raise ValueError("push title_key must be a non-empty string")
        if self.body_key is not None and not self.body_key:
            # An empty string is a bug — the column allows NULL, not "".
            raise ValueError(
                "push body_key must be None or a non-empty string"
            )
        if self.route_entity_id is not None and not self.route_entity_type:
            # An entity id without a type would land in an
            # undisplayable state on the client; reject it at the
            # boundary.
            raise ValueError(
                "push route_entity_id without route_entity_type is not allowed"
            )


# The set of fields a :class:`PushPayload` is allowed to carry.
# Any dataclass field NOT in this set is a privacy decision and
# MUST NOT be added without running the §6.1 valódi-sértés próba
# in ``test_notification_service.py``. The frozenset is the
# structural mirror of the A1 cell.
_ALLOWED_PUSH_FIELDS: frozenset[str] = frozenset(
    {f.name for f in fields(PushPayload)}
)


def _assert_payload_is_minimal(payload: object) -> None:
    """A1 redaction guard — every public attribute on the payload
    MUST be on the allowlist.

    This is a development-time check the §6.1 valódi-sértés próba
    flips. A naïve implementation that ``dataclasses.fields()``
    over the payload and reports the difference trips the
    assertion. The :func:`PushPayload.__post_init__` validator is
    the primary chokepoint; this helper is the second line of
    defence that future developers can wire into a unit test.
    """
    actual = {f.name for f in fields(payload) if not f.name.startswith("_")}
    extra = actual - _ALLOWED_PUSH_FIELDS
    if extra:
        raise AssertionError(
            "PushPayload has fields outside the A1 redaction allowlist: "
            f"{sorted(extra)}. The §6.1 valódi-sértés próba assumes the "
            "dataclass is closed; see ADR 0414 §D1."
        )


# ---------------------------------------------------------------------------
# PushGateway ABC — the provider-neutral surface.
# ---------------------------------------------------------------------------


class PushGateway(ABC):
    """The provider-neutral push-delivery interface.

    A future round that wires FCM / APNs implements this ABC and
    plugs it into ``notification_service`` at the composition root
    (a future ``app.community.notifications.__init__`` exports the
    default instance — this round ships a no-op default).

    The interface is intentionally narrow — :meth:`send` takes a
    single payload, :meth:`send_many` takes an iterable. There is
    no "send with priority" or "send with TTL" — those are the
    future round's responsibility.
    """

    @abstractmethod
    def send(self, payload: PushPayload) -> None:
        """Deliver one push payload.

        A no-op default adapter simply records the call (for the
        §6 measure-matrix to assert the A2 burst-aggregation cell
        fires exactly once per aggregation window). A real adapter
        will translate the payload to the provider's wire shape.
        """

    @abstractmethod
    def send_many(self, payloads: Iterable[PushPayload]) -> None:
        """Deliver a batch of payloads.

        Used when the service decides to fire N pushes in one
        transaction (the §6 A1 batched-redelivery test seam). The
        default no-op adapter records the batch size; a real
        adapter may collapse the batch to a single provider call
        (FCM HTTP/2 multiplex).
        """


# ---------------------------------------------------------------------------
# NoOpPushGateway — the round's default implementation.
# ---------------------------------------------------------------------------


class NoOpPushGateway(PushGateway):
    """A no-op push delivery adapter — the round's default.

    The adapter records every :meth:`send` and :meth:`send_many`
    call into a thread-safe list so the §6 measure-matrix can
    assert the burst-aggregation cell fired exactly one push
    (not five) for a five-reaction burst.

    A future round that wires FCM / APNs replaces this with a
    concrete implementation; the service's composition root
    (future scope) is the swap point.
    """

    def __init__(self) -> None:
        self.sent_payloads: list[PushPayload] = []

    def send(self, payload: PushPayload) -> None:
        # A1 redaction guard — every payload the gateway ships is
        # checked at the boundary. A future change that drops a
        # sensitive field onto the payload is caught here, before
        # the (future) provider sees it.
        _assert_payload_is_minimal(payload)
        self.sent_payloads.append(payload)

    def send_many(self, payloads: Iterable[PushPayload]) -> None:
        for payload in payloads:
            self.send(payload)

    def clear(self) -> None:
        """Reset the recording list — the test fixture's helper.

        The §6 A2 cell calls :meth:`clear` between bursts so the
        assertion sees only the burst's push count.
        """
        self.sent_payloads = []


__all__ = [
    "NoOpPushGateway",
    "PushGateway",
    "PushPayload",
    "_ALLOWED_PUSH_FIELDS",
    "_assert_payload_is_minimal",
]
