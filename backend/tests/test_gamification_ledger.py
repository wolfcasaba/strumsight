"""Gamification ledger: server-side aggregation + wire contract.

A2 — the server never trusts a client-supplied aggregate `totalXp`.
A7 — an unknown contract version is rejected before any receipt is
     ingested, so a tampered client cannot silently degrade the wire.

The HTTP router that mounts this is out of scope for E08-R28, so these
tests target the service module directly. A future router round will
add the HTTP-boundary tests against the same service.
"""

from datetime import datetime, timezone

import pytest
from pydantic import ValidationError

from app.gamification.schemas import (
    GAMIFICATION_SYNC_CONTRACT_VERSION,
    ReceiptUpload,
    LedgerUploadEnvelope,
)
from app.gamification.service import (
    SyncRejectionReason,
    aggregate,
    evaluate_upload,
    is_supported_contract_version,
)


def _receipt(**overrides):
    base = {
        "schemaVersion": 1,
        "ledgerId": "ledger-1",
        "sourceEventId": "event-1",
        "createdAt": datetime(2026, 8, 22, 12, tzinfo=timezone.utc),
        "policyVersion": 1,
        "baseXp": 10,
        "bonusXp": 0,
        "reasonCodes": ["baseExperience"],
    }
    base.update(overrides)
    return ReceiptUpload(**base)


# ---------------------------------------------------------------------------
# A2 — the server REJECTS client-supplied totalXp at the wire boundary.
# ---------------------------------------------------------------------------


def test_a2_request_with_totalXp_field_is_rejected_by_pydantic():
    """`extra='forbid'` means any `totalXp` (or `profile_total_xp`) sent
    by the client raises a validation error. The schema never accepted
    that field — it is not a missing optional, it is not silently
    ignored. (ADR 0394 §5.1)
    """
    body = {
        "schemaVersion": GAMIFICATION_SYNC_CONTRACT_VERSION,
        "receipts": [
            {
                "schemaVersion": 1,
                "ledgerId": "ledger-1",
                "sourceEventId": "event-1",
                "createdAt": "2026-08-22T12:00:00+00:00",
                "policyVersion": 1,
                "baseXp": 10,
                "bonusXp": 0,
                "reasonCodes": ["baseExperience"],
                # Client tries to inflate the aggregate.
                "totalXp": 99999,
            }
        ],
    }
    with pytest.raises(ValidationError):
        LedgerUploadEnvelope.model_validate(body)


def test_a2_profile_totalXp_field_is_rejected_at_the_envelope_level():
    """A second-order attack: the client puts an aggregate at the
    envelope root. `extra='forbid'` on the envelope stops it."""
    body = {
        "schemaVersion": GAMIFICATION_SYNC_CONTRACT_VERSION,
        "receipts": [_receipt().model_dump()],
        "totalXp": 99999,
        "profile_total_xp": 99999,
    }
    with pytest.raises(ValidationError):
        LedgerUploadEnvelope.model_validate(body)


def test_a2_server_computes_total_from_receipts_not_from_request():
    """When the request is clean, the response totalXp comes from the
    server's own sum of baseXp+bonusXp — never from anything the client
    sent."""
    envelope = LedgerUploadEnvelope(
        schemaVersion=GAMIFICATION_SYNC_CONTRACT_VERSION,
        receipts=[
            _receipt(ledgerId="l-1", sourceEventId="e-1", baseXp=10, bonusXp=0),
            _receipt(ledgerId="l-2", sourceEventId="e-2", baseXp=7, bonusXp=3),
            _receipt(ledgerId="l-3", sourceEventId="e-3", baseXp=5, bonusXp=5),
        ],
    )
    outcome = evaluate_upload(envelope)
    assert outcome.download.totalXp == 30
    assert outcome.rejected == []


# ---------------------------------------------------------------------------
# A7 — versioned contract.
# ---------------------------------------------------------------------------


def test_a7_unsupported_contract_version_short_circuits_everything():
    envelope = LedgerUploadEnvelope(
        schemaVersion=GAMIFICATION_SYNC_CONTRACT_VERSION,
        receipts=[_receipt()],
    )
    # Sanity: the supported version passes.
    assert is_supported_contract_version(envelope.schemaVersion)

    # Unknown version: the service refuses the whole envelope. Construct
    # the envelope via model_construct so pydantic's `le=1` constraint
    # does not pre-empt the service-level check — that check is what the
    # HTTP boundary relies on once the wire JSON has been decoded.
    unknown = LedgerUploadEnvelope.model_construct(
        schemaVersion=999,
        receipts=[_receipt()],
    )
    outcome = evaluate_upload(unknown)
    assert outcome.accepted == []
    assert outcome.download.totalXp == 0
    assert outcome.rejected, "expected at least one rejection"
    assert (
        outcome.rejected[0].reason
        == SyncRejectionReason.UNKNOWN_CONTRACT_VERSION
    )


def test_a7_unknown_receipt_schema_version_is_rejected():
    # Same trick: bypass pydantic's `le=1` so the service-level check is
    # what gates the receipt.
    receipt = ReceiptUpload.model_construct(
        schemaVersion=999,
        ledgerId="future-1",
        sourceEventId="e-1",
        createdAt=datetime(2026, 8, 22, 12, tzinfo=timezone.utc),
        policyVersion=1,
        baseXp=10,
        bonusXp=0,
        reasonCodes=["baseExperience"],
    )
    envelope = LedgerUploadEnvelope.model_construct(
        schemaVersion=GAMIFICATION_SYNC_CONTRACT_VERSION,
        receipts=[receipt],
    )
    outcome = evaluate_upload(envelope)
    assert any(
        r.reason == SyncRejectionReason.RECEIPT_SCHEMA_MISMATCH
        for r in outcome.rejected
    )
    # The unknown-schema receipt must NOT have polluted the download.
    assert all(
        r.ledgerId != "future-1" for r in outcome.download.receipts
    )


# ---------------------------------------------------------------------------
# Idempotency and aggregation correctness.
# ---------------------------------------------------------------------------


def test_idempotent_sync_keeps_total_xp_unchanged():
    envelope = LedgerUploadEnvelope(
        schemaVersion=GAMIFICATION_SYNC_CONTRACT_VERSION,
        receipts=[_receipt(ledgerId="l-1", sourceEventId="e-1", baseXp=10)],
    )
    first = evaluate_upload(envelope)
    second = evaluate_upload(envelope)
    assert first.download.totalXp == second.download.totalXp == 10
    assert len(first.download.receipts) == 1
    assert len(second.download.receipts) == 1


def test_zero_xp_receipt_with_no_reason_code_is_rejected():
    """A receipt claiming 0 XP and listing no reason is meaningless and
    rejected — guards against lazy uploads. Bypass pydantic's `min_length`
    on reasonCodes so the service-level check is what fires."""
    receipt = ReceiptUpload.model_construct(
        schemaVersion=1,
        ledgerId="l-empty",
        sourceEventId="e-empty",
        createdAt=datetime(2026, 8, 22, 12, tzinfo=timezone.utc),
        policyVersion=1,
        baseXp=0,
        bonusXp=0,
        reasonCodes=[],
    )
    envelope = LedgerUploadEnvelope(
        schemaVersion=GAMIFICATION_SYNC_CONTRACT_VERSION,
        receipts=[receipt],
    )
    outcome = evaluate_upload(envelope)
    assert any(r.reason for r in outcome.rejected)
    assert all(r.ledgerId != "l-empty" for r in outcome.download.receipts)


def test_duplicate_ledger_id_in_one_envelope_is_rejected():
    envelope = LedgerUploadEnvelope(
        schemaVersion=GAMIFICATION_SYNC_CONTRACT_VERSION,
        receipts=[
            _receipt(ledgerId="dup", sourceEventId="e-1"),
            _receipt(ledgerId="dup", sourceEventId="e-2"),
        ],
    )
    outcome = evaluate_upload(envelope)
    assert any(
        r.reason == SyncRejectionReason.DUPLICATE_LEDGER_ID
        for r in outcome.rejected
    )


def test_aggregate_helper_matches_evaluate_upload_output():
    """The pure `aggregate` helper must produce the same totals as the
    full `evaluate_upload` for a clean input — the helpers are designed
    to agree on the wire."""
    receipts = [
        _receipt(ledgerId="l-1", sourceEventId="e-1", baseXp=10),
        _receipt(ledgerId="l-2", sourceEventId="e-2", baseXp=15),
    ]
    out = aggregate(receipts)
    assert out.totalXp == 25
    assert len(out.receipts) == 2
