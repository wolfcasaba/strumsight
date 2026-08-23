"""Malware-scan + content-moderation adapter seam (E09-R19, ADR 0412).

Abstract ports for the malware-scan and content-moderation
providers the processing pipeline drives, plus the BENIGN
mock implementations this round ships (no external SDK, no
network I/O — the ``requirements.txt`` has no malware-scan /
content-moderation package, ADR 0412 §D4).

**Triage-only invariant (ADR 0412 §D5, brief §5.1, A7).** The
triage function returns a ``confidence`` and a ``recommendation``
— it NEVER directly transitions the row to ``rejected``. The
ONLY path to ``rejected`` is :func:`resolve_review`, which a
human reviewer calls explicitly. A §6.1 valódi-sértés próba
exercises this: monkeypatching triage to write
``processing_state='rejected'`` directly MUST make the A7
acceptance cell go red.

The module ships three layers:

* :class:`MalwareScanner` ABC + :class:`BenignMockMalwareScanner`
  — the malware-scan port. The benign mock always returns
  ``clean=True``.
* :class:`ModerationProvider` ABC +
  :class:`BenignMockModerationProvider` — the content-moderation
  port. The benign mock always returns ``recommendation='allow'``
  with ``confidence=1.0``.
* :func:`triage` — the function the processing pipeline drives.
  Records the provider + provider-version + confidence on the
  row's audit columns (A6) and moves the row to
  ``processing_state='review'`` (NEVER ``rejected``).
* :func:`resolve_review` — the ONLY path to
  ``processing_state='rejected'`` or back to ``'ready'``. This
  is the human-review gate the §5.1 invariant requires.

The signatures mirror the :class:`ObjectStore` port in
:mod:`community.storage.object_store` — the future wiring round
that swaps the benign mock for a real provider keeps the same
public surface, so callers (the processing pipeline) and tests
stay untouched.
"""

from __future__ import annotations

import abc
from dataclasses import dataclass
from datetime import datetime
from typing import Final

from sqlalchemy.orm import Session

from ..models.media import (
    PROCESSING_STATE_READY,
    PROCESSING_STATE_REJECTED,
    PROCESSING_STATE_REVIEW,
    CommunityMedia,
)
from ..tasks.media_processing import (
    _set_processing_state,
)


class MalwareScanner(abc.ABC):
    """The malware-scan port.

    Mirrors the :class:`ObjectStore` ABC pattern in
    :mod:`community.storage.object_store` — a thin abstract
    surface the processing pipeline depends on, swappable for
    a real provider (ClamAV / VirusTotal / similar) without
    touching callers.
    """

    @abc.abstractmethod
    def scan(self, *, object_key: str, content_type: str) -> "ScanResult":
        """Run the scan and return a result.

        ``object_key`` is the bucket-side key the upload pipeline
        produced (``profile_id / public_id`` shaped). The
        scanner may HEAD the object; this round's benign mock
        does not (it returns ``clean=True`` unconditionally —
        a future wiring round wires the real network call).
        """


class ModerationProvider(abc.ABC):
    """The content-moderation port.

    The provider returns a :class:`ModerationDecision` carrying
    ``confidence`` and ``recommendation`` — it does NOT carry
    the final state. The processing pipeline maps the
    recommendation + confidence to a ``processing_state``
    transition via :func:`triage`, and the HUMAN-review gate
    (:func:`resolve_review`) carries the final verdict. The
    split is the A7 invariant.
    """

    @abc.abstractmethod
    def triage(
        self,
        *,
        object_key: str,
        content_type: str,
        declared_codec: str,
    ) -> "ModerationDecision":
        """Return a triage decision for the object.

        ``declared_codec`` is the client-declared codec the
        Kör 18 upload pipeline captured — the moderation
        provider may use it to short-circuit certain checks.
        """


@dataclass(frozen=True)
class ScanResult:
    """The malware-scan verdict.

    ``scanner_name`` and ``scanner_version`` are the audit
    evidence — the row's ``moderation_provider`` /
    ``moderation_provider_version`` columns record them so a
    future review can correlate the row with the specific
    scanner binary that ran (A6 acceptance cell).
    """

    clean: bool
    scanner_name: str
    scanner_version: str
    notes: str = ""


# Recommendation literals — the moderation provider returns
# ONE of these. The pipeline does NOT treat them as a final
# state; the human-review gate is the only authority on
# ``ready`` vs ``rejected``.
RECOMMENDATION_ALLOW: Final[str] = "allow"
RECOMMENDATION_REVIEW: Final[str] = "review"
RECOMMENDATION_REJECT: Final[str] = "reject"


@dataclass(frozen=True)
class ModerationDecision:
    """The content-moderation triage verdict.

    ``confidence`` is a float in ``[0.0, 1.0]``. The pipeline
    treats the value as AUDIT evidence (recorded on the row)
    and never as a standalone decision basis — the
    recommendation is paired with the confidence, but the
    HUMAN-REVIEW GATE (resolve_review) is the only path to
    ``rejected``. The triage function NEVER writes
    ``processing_state='rejected'`` (A7, §5.1, ADR 0412 D5).
    """

    confidence: float
    recommendation: str  # allow | review | reject
    provider: str
    provider_version: str
    notes: str = ""


# ---------------------------------------------------------------------------
# Benign mock implementations — the only adapters this round ships.
# ---------------------------------------------------------------------------


class BenignMockMalwareScanner(MalwareScanner):
    """A malware scanner that always reports ``clean=True``.

    The mock records every call so a future test can assert
    that the pipeline actually invoked the scanner; today it
    ships no real I/O because there is no malware-scan SDK in
    the ``requirements.txt`` (ADR 0412 §D4).
    """

    SCANNER_NAME: Final[str] = "benign-mock-malware-scanner"
    SCANNER_VERSION: Final[str] = "0.0.0-kor19"

    def __init__(self) -> None:
        self.calls: list[tuple[str, str]] = []

    def scan(self, *, object_key: str, content_type: str) -> ScanResult:
        self.calls.append((object_key, content_type))
        return ScanResult(
            clean=True,
            scanner_name=self.SCANNER_NAME,
            scanner_version=self.SCANNER_VERSION,
            notes="benign mock — always clean",
        )


class BenignMockModerationProvider(ModerationProvider):
    """A moderation provider that always returns ``allow``.

    Same rationale as :class:`BenignMockMalwareScanner` —
    no external SDK, no network I/O. The provider records
    every call so a future test can assert invocation.
    """

    PROVIDER_NAME: Final[str] = "benign-mock-moderation-provider"
    PROVIDER_VERSION: Final[str] = "0.0.0-kor19"

    def __init__(self) -> None:
        self.calls: list[tuple[str, str, str]] = []

    def triage(
        self,
        *,
        object_key: str,
        content_type: str,
        declared_codec: str,
    ) -> ModerationDecision:
        self.calls.append((object_key, content_type, declared_codec))
        return ModerationDecision(
            confidence=1.0,
            recommendation=RECOMMENDATION_ALLOW,
            provider=self.PROVIDER_NAME,
            provider_version=self.PROVIDER_VERSION,
            notes="benign mock — always allow",
        )


# ---------------------------------------------------------------------------
# Triage / review-gate — the A6 / A7 seam.
# ---------------------------------------------------------------------------


class TriageError(Exception):
    """Raised when the moderation pipeline cannot continue."""


def triage(
    db: Session,
    row: CommunityMedia,
    *,
    provider: ModerationProvider,
    now: datetime,
    object_key: str,
    declared_codec: str,
) -> CommunityMedia:
    """Drive the triage against ``row``, persist the audit fields,
    and move the row to ``processing_state='review'``.

    NEVER transitions to ``rejected`` (A7 invariant, §5.1). The
    A6 acceptance cell verifies the provider + provider-version
    + confidence + moderation_at are written.
    """
    if row.processing_state != PROCESSING_STATE_REVIEW:
        raise TriageError(f"triage called from processing_state={row.processing_state}")
    decision = provider.triage(
        object_key=object_key,
        content_type=row.content_type,
        declared_codec=declared_codec,
    )
    row.moderation_confidence = float(decision.confidence)
    row.moderation_provider = decision.provider
    row.moderation_provider_version = decision.provider_version
    row.moderated_at = now
    row.updated_at = now
    db.flush()
    return row


def resolve_review(
    db: Session,
    row: CommunityMedia,
    *,
    decision: str,
    reviewer_id: int | str,
    now: datetime,
) -> CommunityMedia:
    """The ONLY path to ``processing_state='rejected'``.

    A reviewer (human) calls this function explicitly with a
    ``decision`` literal (``"approved"`` → ``ready``,
    ``"rejected"`` → ``rejected``) and a ``reviewer_id``
    captured for audit. The triage function above NEVER calls
    this on its own — that is the §5.1 / A7 invariant
    (ADR 0412 §D5).

    ``reviewer_id`` accepts either an int (internal ``id``) or
    a str (some out-of-band identifier, e.g. an external
    moderator's auth token) — the column type on the row is
    ``String(length=64)`` and the type is the audit's choice.
    """
    if row.processing_state != PROCESSING_STATE_REVIEW:
        raise TriageError(
            f"resolve_review called from processing_state={row.processing_state}"
        )
    if decision not in {"approved", "rejected"}:
        raise TriageError(f"resolve_review bad decision: {decision!r}")
    new_state = (
        PROCESSING_STATE_READY if decision == "approved" else PROCESSING_STATE_REJECTED
    )
    row.moderation_decision = decision
    row.moderation_provider = row.moderation_provider or "human-review-gate"
    # The reviewer gate ALWAYS stamps the version with the
    # reviewer's identity (the A6 audit cell checks for
    # ``reviewer:<id>`` after a resolve). Triage's earlier
    # provider-version is the triage binary; the gate's stamp
    # is the human-reviewer — two distinct audit events.
    row.moderation_provider_version = f"reviewer:{reviewer_id}"
    return _set_processing_state(db, row, new_state=new_state, now=now)


__all__ = [
    "BenignMockMalwareScanner",
    "BenignMockModerationProvider",
    "MalwareScanner",
    "ModerationDecision",
    "ModerationProvider",
    "RECOMMENDATION_ALLOW",
    "RECOMMENDATION_REJECT",
    "RECOMMENDATION_REVIEW",
    "ScanResult",
    "TriageError",
    "resolve_review",
    "triage",
]
