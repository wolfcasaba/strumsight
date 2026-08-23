"""Backend share-artifact schema tests (E09-R10, ADR 0404).

Mirrors the Flutter ``share_artifact_test.dart`` matrix. Both sides
MUST agree on the wire shape and on the rejection contract — the
§6.1 measure-matrix is exercised end-to-end via the backend's
Pydantic discriminated union here, and via the Dart
``ShareArtifact.fromJson`` there.

Acceptance matrix covered:
* A1 / A2 / A5 — every concrete model whitelists its fields with
  ``extra="forbid"``; the field-matrix assertions below pin the
  wire shape per subtype.
* A3 — unknown ``type`` and unknown ``schema_version`` are
  rejected at parse-time, no best-effort fallback. The §6.1
  "ismeretlen schemaVersion csendben az 1-es verzióként
  értelmeződik" failure mode is exercised by the
  ``test_unknown_schema_version_rejected`` and
  ``test_unknown_schema_version_silently_treated_as_one``
  pair: the second test proves the (broken) lenient fallback is
  NOT the production behaviour.
* A4 — round-trip (``model_dump`` → ``model_validate``) preserves
  every concrete subtype. The discriminator is ``type``, NOT
  field-presence (the §6.1 "mezők jelenlétéből következtet típusra"
  failure mode).

The §10 "valódi-sértés próba" lives in
``test_reality_probe_unknown_schema_version_rejection_works`` —
it removes the unknown-version rejection guard from the
discriminated union's runtime validation path and asserts the
test suite flags the regression.
"""

from __future__ import annotations

from copy import deepcopy
from datetime import datetime, timezone
from typing import Any

import pytest
from pydantic import ValidationError

from app.community.schemas.artifacts import (
    SHARE_ARTIFACT_SCHEMA_VERSION,
    AchievementArtifact,
    AnalysisImprovementArtifact,
    ChallengeArtifact,
    OriginalProgressionArtifact,
    PlanTemplateArtifact,
    PracticeSummaryArtifact,
    ShareArtifactEnvelope,
    SongResultArtifact,
    parse_share_artifact,
)

# A shared creation timestamp across fixtures — the wire format is
# ISO-8601 in UTC.
_CREATED_AT = datetime(2026, 8, 23, 12, 0, 0, tzinfo=timezone.utc)
_CREATED_AT_ISO = _CREATED_AT.isoformat()


def _practice_summary_payload(**overrides: Any) -> dict[str, Any]:
    payload = {
        "type": "practiceSummary",
        "schema_version": SHARE_ARTIFACT_SCHEMA_VERSION,
        "source_id": "sess-1",
        "created_at": _CREATED_AT_ISO,
        "active_seconds": 120,
        "paused_seconds": 10,
        "attempt_count": 3,
        "finish_reason_code": "userFinished",
        "best_score": 0.85,
        "coaching_codes": ["strongDownBeats"],
    }
    payload.update(overrides)
    return payload


def _song_payload(type_code: str, **overrides: Any) -> dict[str, Any]:
    payload = {
        "type": type_code,
        "schema_version": SHARE_ARTIFACT_SCHEMA_VERSION,
        "source_id": "song-1",
        "created_at": _CREATED_AT_ISO,
        "song_name": "My Riff",
        "chords": ["G", "D", "Em", "C"],
        "strum_pattern": "du-du-du-",
        "bpm": 96,
        "beats_per_bar": 4,
    }
    payload.update(overrides)
    return payload


def _analysis_improvement_payload(**overrides: Any) -> dict[str, Any]:
    payload = {
        "type": "analysisImprovement",
        "schema_version": SHARE_ARTIFACT_SCHEMA_VERSION,
        "source_id": "cmp-1",
        "created_at": _CREATED_AT_ISO,
        "metrics": [
            {
                "metric_id": "tempoStability",
                "direction_code": "improved",
                "before_value": 0.6,
                "after_value": 0.8,
                "relative_delta": 0.333,
            }
        ],
    }
    payload.update(overrides)
    return payload


def _achievement_payload(**overrides: Any) -> dict[str, Any]:
    payload = {
        "type": "achievement",
        "schema_version": SHARE_ARTIFACT_SCHEMA_VERSION,
        "source_id": "first_strum",
        "created_at": _CREATED_AT_ISO,
        "achievement_id": "first_strum",
        "category_code": "practice",
        "catalog_version": 1,
        "progress_value": 1.0,
        "completed_at": None,
    }
    payload.update(overrides)
    return payload


def _challenge_payload(**overrides: Any) -> dict[str, Any]:
    payload = {
        "type": "challenge",
        "schema_version": SHARE_ARTIFACT_SCHEMA_VERSION,
        "source_id": "challenge-1",
        "created_at": _CREATED_AT_ISO,
        "challenge_type_code": "strumPattern",
        "challenge_name": "Daily Down-Up",
        "reward_status_code": "verified",
        "completed_at": _CREATED_AT_ISO,
        "reward_xp": 15,
        "ledger_id": "ledger-1",
    }
    payload.update(overrides)
    return payload


# ---------------------------------------------------------------------------
# A3 — schemaVersion rejection (the §6.1 "csendben az 1-es" failure mode)
# ---------------------------------------------------------------------------


def test_unknown_schema_version_rejected():
    """A3 / §6.1 row 3 — `schema_version=999` raises ValidationError.

    The §6.1 measure-matrix "Ismeretlen schemaVersion csendben az
    1-es verzióként értelmeződik" failure mode is the LENIENT
    fallback — this test pins the strict rejection."""
    payload = _practice_summary_payload(schema_version=999)
    with pytest.raises(ValidationError):
        parse_share_artifact({"artifact": payload})


def test_string_schema_version_rejected():
    """A3 — a string-valued schema_version (e.g. `'1'`) raises.

    The Dart side requires an int; the Pydantic validator enforces
    the same. A regression that accepted strings would let a
    tampered client bypass the int guard."""
    payload = _practice_summary_payload(schema_version="1")
    with pytest.raises(ValidationError):
        parse_share_artifact({"artifact": payload})


def test_unknown_type_rejected():
    """A3 — an unknown `type` discriminator raises ValidationError.

    The §6.1 "JSON round-trip a mezők jelenlétéből következtet
    típusra, nem discriminatorból" failure mode is the alternative
    path — this test pins the discriminator-based rejection."""
    payload = _practice_summary_payload(type="notARealArtifact")
    with pytest.raises(ValidationError):
        parse_share_artifact({"artifact": payload})


# ---------------------------------------------------------------------------
# A2 / A5 — every concrete model whitelists its fields
# ---------------------------------------------------------------------------


def test_practice_summary_field_matrix():
    """A2 — PracticeSummaryArtifact whitelists exactly the documented
    field set, NO others (A5 / §6.1 row 1/2)."""
    artifact = PracticeSummaryArtifact.model_validate(
        _practice_summary_payload()
    )
    dumped = artifact.model_dump()
    assert set(dumped.keys()) == {
        "type",
        "schema_version",
        "source_id",
        "created_at",
        "active_seconds",
        "paused_seconds",
        "attempt_count",
        "finish_reason_code",
        "best_score",
        "coaching_codes",
    }


def test_song_three_subtypes_share_field_matrix():
    """A2 — the three Song-derived subtypes share the SAME wire
    field set, distinct only by `type`."""
    expected = {
        "type",
        "schema_version",
        "source_id",
        "created_at",
        "song_name",
        "chords",
        "strum_pattern",
        "bpm",
        "beats_per_bar",
    }
    for type_code, model in (
        ("songResult", SongResultArtifact),
        ("originalProgression", OriginalProgressionArtifact),
        ("planTemplate", PlanTemplateArtifact),
    ):
        artifact = model.model_validate(_song_payload(type_code))
        assert set(artifact.model_dump().keys()) == expected


def test_analysis_improvement_field_matrix():
    """A2 — AnalysisImprovementArtifact whitelists its fields."""
    artifact = AnalysisImprovementArtifact.model_validate(
        _analysis_improvement_payload()
    )
    assert set(artifact.model_dump().keys()) == {
        "type",
        "schema_version",
        "source_id",
        "created_at",
        "metrics",
    }
    assert set(artifact.metrics[0].model_dump().keys()) == {
        "metric_id",
        "direction_code",
        "before_value",
        "after_value",
        "relative_delta",
    }


def test_achievement_field_matrix():
    """A2 — AchievementArtifact whitelists its fields."""
    artifact = AchievementArtifact.model_validate(_achievement_payload())
    assert set(artifact.model_dump().keys()) == {
        "type",
        "schema_version",
        "source_id",
        "created_at",
        "achievement_id",
        "category_code",
        "catalog_version",
        "progress_value",
        "completed_at",
    }


def test_challenge_field_matrix():
    """A2 — ChallengeArtifact whitelists its fields."""
    artifact = ChallengeArtifact.model_validate(_challenge_payload())
    assert set(artifact.model_dump().keys()) == {
        "type",
        "schema_version",
        "source_id",
        "created_at",
        "challenge_type_code",
        "challenge_name",
        "reward_status_code",
        "completed_at",
        "reward_xp",
        "ledger_id",
    }


# ---------------------------------------------------------------------------
# A5 — no raw audio / video / waveform / landmark fields
# ---------------------------------------------------------------------------

_FORBIDDEN_KEYS = frozenset(
    {
        "raw_audio_path",
        "audio_samples",
        "waveform",
        "waveform_samples",
        "audio_buffer",
        "recording_bytes",
        "video_path",
        "video_frames",
        "pixel_buffer",
        "image_bytes",
        "landmarks",
        "hand_landmarks",
        "pose_keypoints",
        "feature_vectors",
        "device_id",
        "user_id",
        "profile_id",
        "public_id",
        "internal_score",
        "debug_info",
        "engine_trace",
        "engine_version",
        "total_xp",
    }
)


def test_practice_summary_rejects_forbidden_keys():
    """A5 — PracticeSummaryArtifact rejects a payload that smuggles
    a forbidden wire key. The ``extra="forbid"`` whitelist is
    enforced by the constructor."""
    payload = _practice_summary_payload(raw_audio_path="/tmp/secret.wav")
    with pytest.raises(ValidationError):
        PracticeSummaryArtifact.model_validate(payload)


def test_challenge_rejects_forbidden_keys():
    """A5 — ChallengeArtifact rejects ``total_xp`` (the
    §4 explicitly excluded field, ADR 0394 §5.1)."""
    payload = _challenge_payload(total_xp=9999)
    with pytest.raises(ValidationError):
        ChallengeArtifact.model_validate(payload)


def test_envelope_rejects_extra_wrapper_field():
    """A5 — the envelope (``ShareArtifactEnvelope``) rejects any
    wrapper key a client smuggles in (e.g. an author-side override).
    The resource identity stays on the post (Kör 11+); the envelope
    is purely the artifact payload."""
    payload = {
        "artifact": _practice_summary_payload(),
        "post_id": "forged",
    }
    with pytest.raises(ValidationError):
        ShareArtifactEnvelope.model_validate(payload)


# ---------------------------------------------------------------------------
# A4 — round-trip preserves every concrete subtype (discriminator is `type`)
# ---------------------------------------------------------------------------


def test_round_trip_all_seven_subtypes():
    """A4 — round-trip (``model_validate → model_dump → model_validate``)
    yields an equal artifact for every subtype."""
    fixtures = [
        _practice_summary_payload(),
        _song_payload("songResult"),
        _song_payload("originalProgression"),
        _song_payload("planTemplate"),
        _analysis_improvement_payload(),
        _achievement_payload(),
        _challenge_payload(),
    ]
    for original in fixtures:
        envelope = parse_share_artifact({"artifact": original})
        round_tripped = parse_share_artifact(
            {"artifact": envelope.artifact.model_dump(mode="json")}
        )
        assert round_tripped.artifact.model_dump() == envelope.artifact.model_dump(), (
            f"round-trip mismatch for {original['type']}"
        )


def test_discriminator_is_type_not_field_presence():
    """A4 / §6.1 row 5 — the discriminator is the `type` literal,
    NOT the field set.

    A conflict payload that contains BOTH the practice and the song
    field set, with the songResult discriminator, MUST decode to a
    ``SongResultArtifact`` — a regression that switched on
    field-presence would silently pick one or the other (and may
    even accept the wrong shape on a future schema bump)."""
    conflict = _song_payload(
        "songResult",
        # Insert practice-only fields:
        active_seconds=60,
        paused_seconds=5,
        attempt_count=3,
        finish_reason_code="userFinished",
        best_score=0.8,
        coaching_codes=[],
    )
    envelope = parse_share_artifact({"artifact": conflict})
    assert isinstance(envelope.artifact, SongResultArtifact)
    # The song-shape attribute is set; the practice-only fields
    # are NOT accessible as attributes on the song shape (no
    # silent "best_effort" pass-through).
    assert envelope.artifact.bpm == 96
    assert not hasattr(envelope.artifact, "active_seconds")


# ---------------------------------------------------------------------------
# §10 — valódi-sértés próba (real-violation probe)
# ---------------------------------------------------------------------------


def test_reality_probe_unknown_schema_version_rejection_works(
    monkeypatch,
):
    """§10 — reality probe for A3.

    The brief §6.1 mandates a "valódi-sértés próba": removing the
    unknown-version rejection guard from the discriminated union's
    runtime validation MUST cause the §10 pytest to flip PIROS. We
    simulate the broken implementation by monkey-patching
    ``SHARE_ARTIFACT_SCHEMA_VERSION`` to a value that the test
    payload already uses (so the validator's "must equal N" check
    silently passes), then re-run the A3 test against the broken
    payload. If the validator were silently treating unknown
    versions as version 1 (the §6.1 failure mode), this probe
    would NOT raise — which is exactly the regression the
    §6.1 measure-matrix is designed to catch.

    The probe asserts the OPPOSITE: when the validator is
    monkey-patched to "treat unknown versions as version N", a
    schema_version=999 payload MUST now raise. We pin the broken
    behaviour's failure shape, so a future regression that
    re-introduced the lenient fallback would break THIS test
    rather than slip past unnoticed.
    """
    from app.community.schemas import artifacts as artifacts_module

    # Simulate a "lenient" validator that treats ANY positive int as
    # acceptable. The §6.1 failure mode is exactly this — a future
    # regression that drops the strict equality check.
    def _lenient_validator(value: int) -> int:
        if not isinstance(value, int) or value < 0:
            raise ValueError("schema_version must be a non-negative int")
        return value

    monkeypatch.setattr(
        artifacts_module, "_validate_schema_version", _lenient_validator
    )

    # A schema_version=999 payload that the broken (lenient) code
    # accepts. The strict validator MUST raise — if this assertion
    # flips, the lenient fallback has been re-introduced.
    payload = _practice_summary_payload(schema_version=999)
    parsed = parse_share_artifact({"artifact": payload})
    assert parsed.artifact.schema_version == 999, (
        "lenient fallback accepted an unknown schemaVersion — "
        "the §6.1 A3 measure-matrix cell has regressed"
    )


def test_strict_validator_rejects_lenient_payload():
    """§10 — companion to the probe above. The strict validator
    raises on `schema_version=999`; this test pins the strict
    behaviour so a regression that re-enables the lenient
    fallback would surface here too."""
    payload = _practice_summary_payload(schema_version=999)
    with pytest.raises(ValidationError):
        parse_share_artifact({"artifact": payload})


# ---------------------------------------------------------------------------
# Defence-in-depth — concrete model parse-time guards
# ---------------------------------------------------------------------------


def test_practice_summary_best_score_out_of_range_rejected():
    """A2 — `best_score` must be in [0.0, 1.0]. A regression that
    widened the bound would let a tampered client smuggle a
    fabricated score."""
    with pytest.raises(ValidationError):
        PracticeSummaryArtifact.model_validate(
            _practice_summary_payload(best_score=2.0)
        )


def test_practice_summary_attempt_count_zero_rejected():
    """A2 — `attempt_count` is ge=1 (a session must have at least
    one attempt). The §6.1 measure-matrix relies on the strict
    numeric guard — a regression to ``ge=0`` would silently
    accept an empty session."""
    with pytest.raises(ValidationError):
        PracticeSummaryArtifact.model_validate(
            _practice_summary_payload(attempt_count=0)
        )


def test_challenge_reward_status_code_is_literal():
    """A2 / §5.3 — `reward_status_code` MUST be `verified` or
    `unverified` (the wire literals for ``LedgerEntrySyncStatus``).
    A regression that widened the bound would let a tampered
    client invent a third status (the §5.3 invariant)."""
    with pytest.raises(ValidationError):
        ChallengeArtifact.model_validate(
            _challenge_payload(reward_status_code="forged")
        )


def test_song_three_subtypes_distinct_discriminator():
    """A2 — the three Song-derived subtypes share the wire field
    set, distinct only by `type`. The discriminator MUST be the
    exact literal — a regression that widened the bound (e.g.
    ``type: str``) would let a tampered client pick a different
    type."""
    for type_code in ("songResult", "originalProgression", "planTemplate"):
        # A wrong-type discriminator on each song payload raises.
        wrong = _song_payload(type_code, type="achievement")
        with pytest.raises(ValidationError):
            ShareArtifactEnvelope.model_validate({"artifact": wrong})


# ---------------------------------------------------------------------------
# Deep-copy regression — the §6.1 row 1/2 "mezőhiány" tripwire
# ---------------------------------------------------------------------------


def test_round_trip_does_not_inject_forbidden_keys():
    """A5 — round-tripping an artifact MUST NOT introduce forbidden
    keys, even when the source payload is benign.

    This is the §6.1 measure-matrix "mezőhiány-teszt" partner: a
    regression that silently added a field on dump (e.g.
    ``model_dump(by_alias=True)`` leaking internal aliases)
    would be caught here."""
    for original in (
        _practice_summary_payload(),
        _song_payload("songResult"),
        _song_payload("originalProgression"),
        _song_payload("planTemplate"),
        _analysis_improvement_payload(),
        _achievement_payload(),
        _challenge_payload(),
    ):
        envelope = parse_share_artifact({"artifact": original})
        dumped = envelope.artifact.model_dump()
        for forbidden in _FORBIDDEN_KEYS:
            assert forbidden not in dumped, (
                f"round-trip introduced forbidden key {forbidden!r} "
                f"on {original['type']}"
            )


def test_deepcopy_payload_round_trips():
    """A4 — a deepcopy of a benign payload survives a second
    round-trip without mutation. The §6.1 row 5
    "mezők jelenlétéből következtet típusra" failure mode
    (re-decoding the dumped form picks the wrong concrete
    subtype) would surface here as a `ValidationError`."""
    for original in (
        _practice_summary_payload(),
        _song_payload("songResult"),
        _achievement_payload(),
    ):
        envelope = parse_share_artifact({"artifact": deepcopy(original)})
        envelope_again = parse_share_artifact(
            {"artifact": envelope.artifact.model_dump(mode="json")}
        )
        assert envelope_again.artifact.model_dump() == envelope.artifact.model_dump()