"""Authentication: register, login, and the current-user endpoint."""

import hashlib
import logging

from fastapi import APIRouter, HTTPException, Request, status

from ..client_ip import client_ip_for_throttle
from ..config import Settings
from ..deps import CurrentUser, DbSession
from ..models import User, UserSettings
from ..ratelimit import RateLimiter
from ..schemas import Token, UserCreate, UserLogin, UserOut
from ..security import create_access_token, hash_password, verify_password

router = APIRouter(prefix="/auth", tags=["auth"])

_logger = logging.getLogger(__name__)

# Brute-force throttles, per client IP (round 120). The attempt is counted
# BEFORE the credential check, so a blocked window looks identical for wrong
# and right passwords — a 429 must never confirm a guess.
login_limiter = RateLimiter(max_attempts=10, window_seconds=60)
register_limiter = RateLimiter(max_attempts=5, window_seconds=60)


def _throttle(limiter: RateLimiter, request: Request) -> str:
    """Count this attempt and return the bucket key it was counted under.

    The key is the reverse-proxy-aware client identity (R14): behind Caddy
    every caller shares the container's view of the socket peer, which made
    the login/register budgets global instead of per-client — see
    `app/client_ip.py`. Callers get the key back so a failure can be logged
    against the same bucket the operator sees in a 429.
    """
    settings: Settings = request.app.state.settings
    key = client_ip_for_throttle(request, settings)
    if not limiter.allow(key):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many attempts — try again shortly",
            headers={"Retry-After": str(int(limiter.window_seconds))},
        )
    return key


def _email_fingerprint(email: str) -> str:
    """A short, stable, one-way tag for an e-mail address.

    Operator diagnostics must be correlatable ("the same address failed six
    times") WITHOUT putting an account identifier in the log: the first 12
    hex characters of `sha256(lowercased email)`. It is a fingerprint, not
    an anonymity guarantee — a specific suspected address can always be
    hashed and compared — but the log itself never carries the address, and
    never carries the password in any form.
    """
    return hashlib.sha256(email.strip().lower().encode("utf-8")).hexdigest()[:12]


@router.post("/register", response_model=Token, status_code=status.HTTP_201_CREATED)
def register(payload: UserCreate, db: DbSession, request: Request) -> Token:
    client_key = _throttle(register_limiter, request)
    email = payload.email.lower()
    if db.query(User).filter(User.email == email).first() is not None:
        # Server-side only: the RESPONSE below is unchanged. An operator
        # reading `docker compose logs api` can tell "this address already
        # exists" from a wrong password without the client learning anything.
        _logger.info(
            "auth.register_conflict reason=%s client=%s email_hash=%s",
            "email_exists",
            client_key,
            _email_fingerprint(email),
        )
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with this email already exists",
        )

    user = User(email=email, hashed_password=hash_password(payload.password))
    # Every user gets a default settings profile up front (mirrors the client).
    user.settings = UserSettings()
    db.add(user)
    db.commit()
    db.refresh(user)

    # Auto-login: registering returns a usable token immediately.
    return Token(access_token=create_access_token(user.id))


@router.post("/login", response_model=Token)
def login(payload: UserLogin, db: DbSession, request: Request) -> Token:
    client_key = _throttle(login_limiter, request)
    email = payload.email.lower()
    user = db.query(User).filter(User.email == email).first()
    if user is None or not verify_password(payload.password, user.hashed_password):
        # Operator diagnostics (R14): the reason a login failed is a
        # SERVER-SIDE log record only. The HTTP answer below stays byte-
        # identical for both branches — the uniform 401 is what keeps the
        # registered-address set private, and this record must never weaken
        # it. No e-mail, no password, no password length.
        _logger.info(
            "auth.login_failed reason=%s client=%s email_hash=%s",
            "unknown_email" if user is None else "bad_password",
            client_key,
            _email_fingerprint(email),
        )
        # Same message for both cases — don't leak which emails are registered.
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
        )
    return Token(access_token=create_access_token(user.id))


@router.get("/me", response_model=UserOut)
def me(current_user: CurrentUser) -> User:
    return current_user
