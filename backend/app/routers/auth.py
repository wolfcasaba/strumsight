"""Authentication: register, login, and the current-user endpoint."""

from fastapi import APIRouter, HTTPException, Request, status

from ..deps import CurrentUser, DbSession
from ..models import User, UserSettings
from ..ratelimit import RateLimiter
from ..schemas import Token, UserCreate, UserLogin, UserOut
from ..security import create_access_token, hash_password, verify_password

router = APIRouter(prefix="/auth", tags=["auth"])

# Brute-force throttles, per client IP (round 120). The attempt is counted
# BEFORE the credential check, so a blocked window looks identical for wrong
# and right passwords — a 429 must never confirm a guess.
login_limiter = RateLimiter(max_attempts=10, window_seconds=60)
register_limiter = RateLimiter(max_attempts=5, window_seconds=60)


def _throttle(limiter: RateLimiter, request: Request) -> None:
    key = request.client.host if request.client else "unknown"
    if not limiter.allow(key):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many attempts — try again shortly",
            headers={"Retry-After": str(int(limiter.window_seconds))},
        )


@router.post("/register", response_model=Token, status_code=status.HTTP_201_CREATED)
def register(payload: UserCreate, db: DbSession, request: Request) -> Token:
    _throttle(register_limiter, request)
    email = payload.email.lower()
    if db.query(User).filter(User.email == email).first() is not None:
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
    _throttle(login_limiter, request)
    email = payload.email.lower()
    user = db.query(User).filter(User.email == email).first()
    if user is None or not verify_password(payload.password, user.hashed_password):
        # Same message for both cases — don't leak which emails are registered.
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
        )
    return Token(access_token=create_access_token(user.id))


@router.get("/me", response_model=UserOut)
def me(current_user: CurrentUser) -> User:
    return current_user
