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
    """Tutor capability metadata.

    `provider` / `model` report which adapter the server actually runs, so an
    operator can verify a provider flip from outside the container. Neither is
    a secret; the API key is never exposed on any surface.
    """

    model_config = ConfigDict(extra="forbid")

    enabled: bool
    version: str = "v1"
    streaming: bool = False
    provider: str = "fake"
    model: str = "fake-model"
