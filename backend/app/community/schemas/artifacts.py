"""Versioned share-artifact schemas (E09-R10, ADR 0404).

This module is the server-side mirror of
``lib/features/community/domain/entities/share_artifact.dart``. Both
sides agree on a closed set of seven ``type`` discriminator values;
each concrete Pydantic model whitelists its own field set with
``extra="forbid"`` so the wire shape cannot drift (A1, A2, A5
measure-matrix).

The four non-goals of this module — see ADR 0404 §D2, brief §5.1:

* No raw audio / video / waveform / landmark fields. Each concrete
  artifact's whitelist excludes them by construction; a regression
  that reintroduced a ``rawAudioPath`` / ``waveformSamples`` field
  would be caught at parse-time by ``extra="forbid"`` on the
  destination model.
* No ``achievement_id`` / ``profile_id`` smuggling — the artifact
  is content-addressed by its source feature, the post identity
  lives on ``CommunityPost`` (Kör 11+).
* No client-aggregated totals. The challenge artifact carries a
  ``ledger_id`` reference into the existing gamification reward
  ledger; the server-side aggregate is computed there, not from the
  artifact.
* No unknown-version acceptance. The ``schema_version`` field is
  validated against ``SHARE_ARTIFACT_SCHEMA_VERSION`` (``=1``) on
  every concrete model; a future bump on the client without a
  matching server change raises ``pydantic.ValidationError``
  (A3 measure-matrix, brief §5.2).

The discriminated union at the bottom of this file is the SINGLE
shape a Kör 11+ post-creation endpoint accepts. The pre-flight
verified that this is the first discriminated union in the backend
(``grep -rln 'Discriminator|discriminator=' backend/app/`` returned
zero hits), so we adopt Pydantic v2's idiomatic
``Annotated[Union[...], Field(discriminator='type')]`` pattern
without any legacy compatibility constraint.
"""

from __future__ import annotations

from datetime import datetime
from typing import Annotated, List, Literal, Optional, Union

from pydantic import BaseModel, ConfigDict, Field, field_validator
from pydantic import ValidationError as PydanticValidationError

# ---------------------------------------------------------------------------
# Wire-level constants — mirror the Dart `shareArtifactSchemaVersion`
# constant in `share_artifact.dart`. Bump both together.
# ---------------------------------------------------------------------------

SHARE_ARTIFACT_SCHEMA_VERSION: int = 1

# Type discriminator literals. The Dart `ShareArtifactType.code`
# constants mirror these.
SHARE_ARTIFACT_TYPE_PRACTICE_SUMMARY: Literal["practiceSummary"] = "practiceSummary"
SHARE_ARTIFACT_TYPE_SONG_RESULT: Literal["songResult"] = "songResult"
SHARE_ARTIFACT_TYPE_ORIGINAL_PROGRESSION: Literal["originalProgression"] = (
    "originalProgression"
)
SHARE_ARTIFACT_TYPE_PLAN_TEMPLATE: Literal["planTemplate"] = "planTemplate"
SHARE_ARTIFACT_TYPE_ANALYSIS_IMPROVEMENT: Literal["analysisImprovement"] = (
    "analysisImprovement"
)
SHARE_ARTIFACT_TYPE_ACHIEVEMENT: Literal["achievement"] = "achievement"
SHARE_ARTIFACT_TYPE_CHALLENGE: Literal["challenge"] = "challenge"


def _validate_schema_version(value: int) -> int:
    """Reject unknown schema versions (A3 measure-matrix, brief §5.2).

    Every concrete artifact model validates ``schema_version`` against
    this function. A client that sends ``schema_version=2`` (or
    ``0``, or a string) raises ``ValueError`` at parse-time — no
    silent best-effort fallback, no "interpret unknown as version 1"
    (the exact §6.1 "ismeretlen schemaVersion csendben az 1-es
    verzióként értelmeződik" failure mode).
    """
    if not isinstance(value, int):
        raise ValueError(
            "schema_version must be an integer, "
            f"got {type(value).__name__}."
        )
    if value != SHARE_ARTIFACT_SCHEMA_VERSION:
        raise ValueError(
            "Unsupported share artifact schemaVersion "
            f"{value!r}; expected {SHARE_ARTIFACT_SCHEMA_VERSION}."
        )
    return value


class _BaseShareArtifact(BaseModel):
    """Shared fields for every artifact. The concrete models extend
    this with ``type`` as a ``Literal[...]`` discriminator and their
    own whitelisted field set (``extra="forbid"``)."""

    model_config = ConfigDict(extra="forbid")

    schema_version: int
    source_id: str = Field(..., min_length=1, max_length=128)
    created_at: datetime

    @field_validator("schema_version")
    @classmethod
    def _check_schema_version(cls, value: int) -> int:
        return _validate_schema_version(value)


# ---------------------------------------------------------------------------
# 1) Practice summary
# ---------------------------------------------------------------------------


class PracticeSummaryArtifact(_BaseShareArtifact):
    """Practice session result, minimal field set (ADR 0404 §D1, brief §5.1).

    Carries only the user-visible summary — NO raw per-attempt DSP,
    NO per-attempt score components, NO vision evidence, NO
    per-attempt timing detail. The source feature keeps those; this
    contract only carries what the Community surface shows."""

    model_config = ConfigDict(extra="forbid")

    type: Literal["practiceSummary"] = "practiceSummary"
    active_seconds: int = Field(..., ge=0)
    paused_seconds: int = Field(..., ge=0)
    attempt_count: int = Field(..., ge=1)
    finish_reason_code: str = Field(..., min_length=1, max_length=64)
    best_score: Optional[float] = Field(default=None, ge=0.0, le=1.0)
    coaching_codes: List[str] = Field(default_factory=list)


# ---------------------------------------------------------------------------
# 2) Song result / 3) Original progression / 4) Plan template
# ---------------------------------------------------------------------------


class _SongFieldsMixin(BaseModel):
    """The three Song-derived artifacts share the same wire field
    set — the only difference is the ``type`` discriminator. The
    shared model keeps the whitelist aligned across all three
    concrete classes (ADR 0404 §D1)."""

    model_config = ConfigDict(extra="forbid")

    song_name: str = Field(default="", max_length=128)
    chords: List[str] = Field(default_factory=list)
    # One character per eighth-note slot: `d` (down), `u` (up),
    # `-` (rest). The length is `beats_per_bar * 2`. The Server
    # validates the length match separately (Kör 11+).
    strum_pattern: str = Field(..., min_length=1, max_length=256)
    bpm: int = Field(..., ge=1, le=400)
    beats_per_bar: int = Field(..., ge=1, le=16)


class SongResultArtifact(_SongFieldsMixin, _BaseShareArtifact):
    """A user-authored song, surfaced as a Community share."""

    type: Literal["songResult"] = "songResult"


class OriginalProgressionArtifact(_SongFieldsMixin, _BaseShareArtifact):
    """The 'original progression' angle on a Song. Same wire field
    set as ``SongResultArtifact`` but a distinct discriminator."""

    type: Literal["originalProgression"] = "originalProgression"


class PlanTemplateArtifact(_SongFieldsMixin, _BaseShareArtifact):
    """A 'plan template' built around a Song. Same wire field set,
    distinct discriminator."""

    type: Literal["planTemplate"] = "planTemplate"


# ---------------------------------------------------------------------------
# 5) Analysis improvement
# ---------------------------------------------------------------------------


class MetricImprovement(BaseModel):
    """One metric's before/after movement in an analysis comparison.

    Carries only the verdict (metricId + directionCode) and the
    three numeric deltas. NO waveform, NO landmark, NO raw sample,
    NO comparison's internal session IDs."""

    model_config = ConfigDict(extra="forbid")

    metric_id: str = Field(..., min_length=1, max_length=128)
    direction_code: Literal["improved", "regressed", "unchanged", "inconclusive"]
    before_value: Optional[float] = None
    after_value: Optional[float] = None
    relative_delta: Optional[float] = None


class AnalysisImprovementArtifact(_BaseShareArtifact):
    """One before/after analysis comparison."""

    model_config = ConfigDict(extra="forbid")

    type: Literal["analysisImprovement"] = "analysisImprovement"
    metrics: List[MetricImprovement] = Field(default_factory=list)


# ---------------------------------------------------------------------------
# 6) Achievement
# ---------------------------------------------------------------------------


class AchievementArtifact(_BaseShareArtifact):
    """Achievement unlock shared as a Community artifact.

    The artifact references the catalog id and the user's progress
    — NO hidden tier prerequisites, NO localization keys (the server
    resolves keys independently)."""

    model_config = ConfigDict(extra="forbid")

    type: Literal["achievement"] = "achievement"
    achievement_id: str = Field(..., min_length=1, max_length=128)
    category_code: str = Field(..., min_length=1, max_length=64)
    catalog_version: int = Field(..., ge=1)
    progress_value: float = Field(..., ge=0.0)
    completed_at: Optional[datetime] = None


# ---------------------------------------------------------------------------
# 7) Challenge
# ---------------------------------------------------------------------------


class ChallengeArtifact(_BaseShareArtifact):
    """Daily challenge shared as a Community artifact.

    The ``reward_status_code`` field maps the existing gamification
    ``LedgerEntrySyncStatus`` (E08-R28, ADR 0394 §5.3) onto the
    Community surface — ``"verified"`` requires a server-confirmed
    reward ledger entry, ``"unverified"`` means the receipt is in
    flight or unattributed. The Community domain never sees a
    ``verified`` artifact without a matching ``ledger_id`` (ADR 0404
    §D4, brief §5.3)."""

    model_config = ConfigDict(extra="forbid")

    type: Literal["challenge"] = "challenge"
    challenge_type_code: Literal[
        "strumPattern", "chordChange", "rhythm", "songSection", "timing"
    ]
    challenge_name: str = Field(default="", max_length=128)
    reward_status_code: Literal["verified", "unverified"]
    completed_at: Optional[datetime] = None
    reward_xp: Optional[int] = Field(default=None, ge=0)
    ledger_id: Optional[str] = Field(default=None, max_length=128)


# ---------------------------------------------------------------------------
# Discriminated union — the single shape a post-creation endpoint
# accepts. Pydantic v2's `Field(discriminator='type')` pattern.
# ---------------------------------------------------------------------------

# The Pydantic v2 idiom: ``Annotated[Union[...], Field(discriminator=...)]``
# selects the concrete class from the wire `type` literal. An
# unknown `type` raises ``ValidationError`` (A3 measure-matrix,
# brief §5.2). The model-level ``extra="forbid"`` on each concrete
# class adds the A2 / A5 enforcement (unknown fields rejected).
ShareArtifactUnion = Annotated[
    Union[
        PracticeSummaryArtifact,
        SongResultArtifact,
        OriginalProgressionArtifact,
        PlanTemplateArtifact,
        AnalysisImprovementArtifact,
        AchievementArtifact,
        ChallengeArtifact,
    ],
    Field(discriminator="type"),
]


class ShareArtifactEnvelope(BaseModel):
    """Top-level envelope wrapping a single artifact. Kör 11+
    post-creation endpoints accept this shape; Kör 13 read paths
    return the same wrapper.

    ``extra="forbid"`` rejects any wrapper field a client smuggled
    in (e.g. an author-side override) — the resource identity stays
    on the post, the envelope is purely the artifact payload."""

    model_config = ConfigDict(extra="forbid")

    artifact: ShareArtifactUnion


def parse_share_artifact(payload: object) -> ShareArtifactEnvelope:
    """Parse and validate a raw wire payload.

    Raises ``pydantic.ValidationError`` on:
    * unknown ``type`` discriminator,
    * unknown or manipulated ``schema_version``,
    * missing required field,
    * extra unknown field (the ``extra="forbid"`` whitelist).

    Returns a ``ShareArtifactEnvelope`` whose ``artifact`` field is
    the concrete subtype. There is no best-effort fallback — the
    A3 measure-matrix cell is enforced here (brief §5.2, §6.1).
    """
    return ShareArtifactEnvelope.model_validate(payload)


# Re-export Pydantic's ValidationError so Kör 11+ routers can
# `except` on a single name without importing pydantic directly.
ValidationError = PydanticValidationError


__all__ = [
    "AchievementArtifact",
    "AnalysisImprovementArtifact",
    "ChallengeArtifact",
    "MetricImprovement",
    "OriginalProgressionArtifact",
    "PlanTemplateArtifact",
    "PracticeSummaryArtifact",
    "SHARE_ARTIFACT_SCHEMA_VERSION",
    "ShareArtifactEnvelope",
    "ShareArtifactUnion",
    "SongResultArtifact",
    "ValidationError",
    "parse_share_artifact",
]