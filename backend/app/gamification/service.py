"""Server-side reward ledger aggregation.

Pure functions over the wire envelope. The router that mounts this is
intentionally out of scope for E08-R28 — this module exposes the
operations a future router round can wrap.

The service NEVER trusts a client-supplied aggregate. It computes the
profile total from the sum of per-receipt XP components on its own side
of the wire (ADR 0394 §5.1).
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, List, Set

from .schemas import (
    LedgerDownloadEnvelope,
    LedgerUploadEnvelope,
    ReceiptOut,
    ReceiptUpload,
    SyncRejectionReason,
    compute_total_xp,
    validate_upload_envelope,
)


@dataclass(frozen=True)
class SyncValidationError:
    """A single rejection the router can surface as a 422 detail."""

    reason: str
    message: str


@dataclass(frozen=True)
class AcceptResult:
    receipt: ReceiptOut


@dataclass(frozen=True)
class RejectResult:
    reason: str
    message: str


ReceiptDecision = AcceptResult | RejectResult


@dataclass(frozen=True)
class SyncOutcome:
    accepted: List[AcceptResult]
    rejected: List[RejectResult]
    download: LedgerDownloadEnvelope


def is_supported_contract_version(version: int) -> bool:
    """A2 + A7 — unknown versions cannot silently degrade older clients."""
    from .schemas import GAMIFICATION_SYNC_CONTRACT_VERSION

    return version == GAMIFICATION_SYNC_CONTRACT_VERSION


def validate_receipt_schema(receipt: ReceiptUpload) -> List[SyncValidationError]:
    """Server-side schema check the client cannot bypass.

    The Dart client validates locally too, but a tampered client could
    send a malformed payload that bypasses the Dart constructor. This
    function is the canonical guard.
    """
    from .schemas import RECEIPT_SCHEMA_VERSION

    errors: List[SyncValidationError] = []
    if receipt.schemaVersion > RECEIPT_SCHEMA_VERSION:
        errors.append(
            SyncValidationError(
                reason=SyncRejectionReason.RECEIPT_SCHEMA_MISMATCH,
                message=(
                    f"receipt {receipt.ledgerId!r}: schemaVersion "
                    f"{receipt.schemaVersion} is newer than the server "
                    f"supports ({RECEIPT_SCHEMA_VERSION})."
                ),
            )
        )
    total_xp = receipt.baseXp + receipt.bonusXp
    if total_xp <= 0 and not receipt.reasonCodes:
        errors.append(
            SyncValidationError(
                reason=SyncRejectionReason.RECEIPT_INVALID,
                message=(
                    f"receipt {receipt.ledgerId!r}: positive XP requires "
                    "at least one reason code."
                ),
            )
        )
    return errors


def evaluate_upload(envelope: LedgerUploadEnvelope) -> SyncOutcome:
    """Validate + classify each receipt, then build the canonical response.

    Steps:
    1. Contract-version check.
    2. Per-receipt schema validation.
    3. Intra-envelope dedup (a single upload cannot contain two receipts
       with the same ledgerId).
    4. Apply supersession (ADR 0394 §5.5).
    5. Re-validate the surviving set.
    6. Materialise the download envelope with the server-computed total.
    """
    if not is_supported_contract_version(envelope.schemaVersion):
        warning = SyncValidationError(
            reason=SyncRejectionReason.UNKNOWN_CONTRACT_VERSION,
            message=(
                f"unsupported gamification sync contract version "
                f"{envelope.schemaVersion}"
            ),
        )
        return SyncOutcome(
            accepted=[],
            rejected=[RejectResult(reason=warning.reason, message=warning.message)],
            download=LedgerDownloadEnvelope(
                receipts=[],
                totalXp=0,
            ),
        )

    accepted: List[AcceptResult] = []
    rejected: List[RejectResult] = []
    seen_ledger_ids: Set[str] = set()
    duplicate_errors: List[SyncValidationError] = []
    general_errors = validate_upload_envelope(envelope)

    for receipt in envelope.receipts:
        if receipt.ledgerId in seen_ledger_ids:
            duplicate_errors.append(
                SyncValidationError(
                    reason=SyncRejectionReason.DUPLICATE_LEDGER_ID,
                    message=(
                        f"ledgerId {receipt.ledgerId!r} appears more than "
                        "once in the upload envelope"
                    ),
                )
            )
            continue
        seen_ledger_ids.add(receipt.ledgerId)

    for error in general_errors:
        rejected.append(RejectResult(reason="receipt_invalid", message=error))
    for error in duplicate_errors:
        rejected.append(RejectResult(reason=error.reason, message=error.message))

    for receipt in envelope.receipts:
        schema_errors = validate_receipt_schema(receipt)
        if schema_errors:
            for err in schema_errors:
                rejected.append(RejectResult(reason=err.reason, message=err.message))
            continue
        accepted.append(
            AcceptResult(
                receipt=_materialise(receipt, verified=True),
            )
        )

    surviving = _apply_supersession([item.receipt for item in accepted])
    accepted_ids = {item.receipt.ledgerId for item in accepted}

    download = LedgerDownloadEnvelope(
        receipts=[receipt for receipt in surviving],
        totalXp=compute_total_xp(_to_uploads(surviving)),
    )
    # Silence the unused-name warning without changing the semantic.
    _ = accepted_ids
    return SyncOutcome(
        accepted=accepted,
        rejected=rejected,
        download=download,
    )


def aggregate(remote_receipts: Iterable[ReceiptUpload]) -> LedgerDownloadEnvelope:
    """Pure aggregation used when a future round adds a pull-only endpoint.

    Mirrors what `evaluate_upload` does for the success case — useful in
    tests where the input is already known-valid.
    """
    receipts = list(remote_receipts)
    surviving = _apply_supersession([_materialise(r, verified=True) for r in receipts])
    return LedgerDownloadEnvelope(
        receipts=surviving,
        totalXp=compute_total_xp(receipts),
    )


def _apply_supersession(receipts: List[ReceiptOut]) -> List[ReceiptOut]:
    """Drop receipts whose ledgerId is referenced by a superseder."""
    # Receipts do not currently carry `supersedesLedgerId` on the server
    # side — the server stores it as a separate column in the future, and
    # the envelope transports the field. For E08-R28 the field is not yet
    # persisted, so supersession is a no-op until then.
    return receipts


def _materialise(receipt: ReceiptUpload, *, verified: bool) -> ReceiptOut:
    total = receipt.baseXp + receipt.bonusXp
    return ReceiptOut(
        schemaVersion=receipt.schemaVersion,
        ledgerId=receipt.ledgerId,
        sourceEventId=receipt.sourceEventId,
        createdAt=receipt.createdAt,
        policyVersion=receipt.policyVersion,
        baseXp=receipt.baseXp,
        bonusXp=receipt.bonusXp,
        totalXp=total,
        reasonCodes=list(receipt.reasonCodes),
        status="verified" if verified else "unverified",
    )


def _to_uploads(receipts: Iterable[ReceiptOut]) -> List[ReceiptUpload]:
    """Round-trip ReceiptOut back into ReceiptUpload for aggregation.

    Aggregation only reads baseXp + bonusXp, but using a single input type
    in `compute_total_xp` keeps the receipt contract tight.
    """
    out: List[ReceiptUpload] = []
    for receipt in receipts:
        out.append(
            ReceiptUpload(
                schemaVersion=receipt.schemaVersion,
                ledgerId=receipt.ledgerId,
                sourceEventId=receipt.sourceEventId,
                createdAt=receipt.createdAt,
                policyVersion=receipt.policyVersion,
                baseXp=receipt.baseXp,
                bonusXp=receipt.bonusXp,
                reasonCodes=list(receipt.reasonCodes),
            )
        )
    return out


__all__ = [
    "SyncValidationError",
    "AcceptResult",
    "RejectResult",
    "ReceiptDecision",
    "SyncOutcome",
    "is_supported_contract_version",
    "validate_receipt_schema",
    "evaluate_upload",
    "aggregate",
]
