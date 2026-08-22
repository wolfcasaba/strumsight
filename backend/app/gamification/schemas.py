"""Gamification ledger wire schemas.

The contract is intentionally small and explicitly forbids a client-side
aggregate `totalXp` field. The server is the only writer of profile
totals (ADR 0394 §5.1).
"""

from __future__ import annotations

from datetime import datetime
from typing import List, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

# Mirrors `gamificationSyncContractVersion` in lib/features/gamification/data/sync/.
GAMIFICATION_SYNC_CONTRACT_VERSION = 1
# Mirrors `rewardLedgerEntrySchemaVersion` in lib/features/gamification/domain/.
RECEIPT_SCHEMA_VERSION = 1

ReasonCode = Literal[
    "baseExperience",
    "qualityBonus",
    "consistencyBonus",
    "achievementUnlocked",
    "questCompleted",
    "dailyCapApplied",
    "repeatLimited",
    "tooShort",
    "cancelled",
    "failed",
    "insufficientTrust",
    "fatalSignalQuality",
]

SyncStatus = Literal["unverified", "verified"]


class ReceiptUpload(BaseModel):
    """One reward receipt, as the client sends it.

    `totalXp` is intentionally absent. The server recomputes it from
    `baseXp + bonusXp` and uses its own sum. Any field labelled `total*`
    or `profile_total*` is forbidden here so a tampered client cannot
    inject an aggregate (ADR 0394 §5.1).
    """

    model_config = ConfigDict(extra="forbid")

    schemaVersion: int = Field(ge=1, le=RECEIPT_SCHEMA_VERSION)
    ledgerId: str = Field(min_length=1, max_length=256)
    sourceEventId: str = Field(min_length=1, max_length=256)
    createdAt: datetime
    policyVersion: int = Field(ge=1)
    baseXp: int = Field(ge=0)
    bonusXp: int = Field(ge=0)
    reasonCodes: List[ReasonCode]

    @field_validator("reasonCodes")
    @classmethod
    def _reason_codes_not_empty_for_positive_xp(cls, value: List[str]) -> List[str]:
        if not value:
            raise ValueError("reasonCodes must list at least one code")
        return value


class LedgerUploadEnvelope(BaseModel):
    """Top-level envelope the client sends."""

    model_config = ConfigDict(extra="forbid")

    schemaVersion: int = Field(ge=1, le=GAMIFICATION_SYNC_CONTRACT_VERSION)
    receipts: List[ReceiptUpload] = Field(max_length=500)

    @field_validator("receipts")
    @classmethod
    def _at_least_one_receipt(cls, value: List[ReceiptUpload]) -> List[ReceiptUpload]:
        # An empty payload is a no-op; the contract rejects it so a buggy
        # client that emits `{"schemaVersion": 1, "receipts": []}` cannot
        # silently pass the unknown-version check.
        if not value:
            raise ValueError("receipts must contain at least one entry")
        return value


class ReceiptOut(BaseModel):
    """Server-canonical view of one receipt."""

    model_config = ConfigDict(from_attributes=True)

    schemaVersion: int
    ledgerId: str
    sourceEventId: str
    createdAt: datetime
    policyVersion: int
    baseXp: int
    bonusXp: int
    # Computed by the server — NEVER accepted from the client. We expose it
    # so the client can read back what the server computed.
    totalXp: int
    reasonCodes: List[ReasonCode]
    status: SyncStatus


class LedgerDownloadEnvelope(BaseModel):
    """Top-level envelope the server returns."""

    model_config = ConfigDict(extra="forbid")

    schemaVersion: int = GAMIFICATION_SYNC_CONTRACT_VERSION
    receipts: List[ReceiptOut]
    # Aggregate counters — server-computed, never read from the client.
    totalXp: int = Field(ge=0)


class SyncRejectionReason:
    """Stable reason codes the server surfaces for sync rejections."""

    UNKNOWN_CONTRACT_VERSION = "unknown_contract_version"
    RECEIPT_SCHEMA_MISMATCH = "receipt_schema_mismatch"
    RECEIPT_INVALID = "receipt_invalid"
    DUPLICATE_LEDGER_ID = "duplicate_ledger_id"


def validate_upload_envelope(envelope: LedgerUploadEnvelope) -> List[str]:
    """Return a list of validation errors. Empty list means OK.

    Used by the service to surface 422s without raising Pydantic-internal
    errors to the HTTP boundary.
    """
    errors: List[str] = []
    seen_ledger_ids = set()
    for index, receipt in enumerate(envelope.receipts):
        if receipt.baseXp + receipt.bonusXp <= 0 and not receipt.reasonCodes:
            errors.append(f"receipts[{index}]: positive XP requires a reason code")
        if receipt.ledgerId in seen_ledger_ids:
            errors.append(
                f"receipts[{index}]: ledgerId {receipt.ledgerId!r} is duplicated"
            )
        seen_ledger_ids.add(receipt.ledgerId)
    return errors


def compute_total_xp(receipts: List[ReceiptUpload]) -> int:
    """Server-side aggregation — sum of baseXp + bonusXp across receipts.

    The function is intentionally pure: the same input always produces the
    same output. Used by the service to materialise the response envelope
    without trusting any caller-supplied aggregate.
    """
    return sum(receipt.baseXp + receipt.bonusXp for receipt in receipts)


__all__ = [
    "GAMIFICATION_SYNC_CONTRACT_VERSION",
    "RECEIPT_SCHEMA_VERSION",
    "ReasonCode",
    "SyncStatus",
    "ReceiptUpload",
    "LedgerUploadEnvelope",
    "ReceiptOut",
    "LedgerDownloadEnvelope",
    "SyncRejectionReason",
    "validate_upload_envelope",
    "compute_total_xp",
]
