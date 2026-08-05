"""Pydantic contracts for the tutor proxy (ADR 0131).

Extra fields are forbidden — the schema is an allowlist, not a passthrough.
"""

from pydantic import BaseModel, ConfigDict


class TurnMessage(BaseModel):
    """A single message in the conversation history."""

    model_config = ConfigDict(extra="forbid")

    role: str
    content: str


class TutorTurnRequest(BaseModel):
    """Request to process a tutor turn."""

    model_config = ConfigDict(extra="forbid")

    message: str
    history: list[TurnMessage] = []
    context: str = ""


class TutorTurnResponse(BaseModel):
    """Response from a tutor turn."""

    model_config = ConfigDict(extra="forbid")

    reply: str


class TutorCapabilityResponse(BaseModel):
    """Tutor capability metadata."""

    model_config = ConfigDict(extra="forbid")

    enabled: bool
    version: str = "v1"
    streaming: bool = False
