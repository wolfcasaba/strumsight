"""Tutor proxy endpoints (ADR 0131).

The provider secret stays on the server — the client only sees the
redacted response. Errors are normalized to provider-neutral HTTP errors.
"""

from fastapi import APIRouter, HTTPException, status

from ..deps import CurrentUser
from .provider_gateway import ProviderError, ProviderTimeoutError
from .schemas import TutorCapabilityResponse, TutorTurnRequest, TutorTurnResponse
from .service import RequestTooLargeError, TutorService
from .usage import RateLimitExceeded, UsageLimitExceeded

router = APIRouter(prefix="/tutor", tags=["tutor"])

# The service is injected via app.state — set by main.py when mounting.
_service: TutorService | None = None


def set_service(service: TutorService) -> None:
    """Inject the tutor service (called by main.py)."""
    global _service  # noqa: PLW0603
    _service = service


def get_service() -> TutorService:
    """Return the injected service or raise if not configured."""
    if _service is None:
        raise RuntimeError("Tutor service not configured")
    return _service


@router.get("/capability", response_model=TutorCapabilityResponse)
def capability() -> TutorCapabilityResponse:
    """Return tutor capability metadata."""
    return TutorCapabilityResponse(enabled=True, version="v1", streaming=False)


@router.post("/turn", response_model=TutorTurnResponse)
async def turn(
    request: TutorTurnRequest, current_user: CurrentUser
) -> TutorTurnResponse:
    """Process a tutor turn. The provider secret stays on the server."""
    service = get_service()
    user_id = str(current_user.id)

    try:
        return await service.turn(user_id, request)
    except RequestTooLargeError as exc:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=str(exc),
        ) from exc
    except RateLimitExceeded as exc:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Rate limit exceeded — try again shortly",
        ) from exc
    except UsageLimitExceeded as exc:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Daily usage limit exceeded",
        ) from exc
    except ProviderTimeoutError as exc:
        raise HTTPException(
            status_code=status.HTTP_504_GATEWAY_TIMEOUT,
            detail="The AI service is temporarily unavailable",
        ) from exc
    except ProviderError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="The AI service returned an error",
        ) from exc
