"""Password hashing (bcrypt) and JWT access tokens (PyJWT).

bcrypt is used directly rather than via passlib to avoid the well-known
passlib/bcrypt-4.x version-probe breakage.
"""

from datetime import datetime, timedelta, timezone

import bcrypt
import jwt

from .config import BCRYPT_MAX_PASSWORD_BYTES, get_settings

settings = get_settings()


def _password_bytes(password: str) -> bytes:
    return password.encode("utf-8")


def hash_password(password: str) -> str:
    password_bytes = _password_bytes(password)
    if len(password_bytes) > BCRYPT_MAX_PASSWORD_BYTES:
        raise ValueError(
            f"password must not exceed "
            f"{BCRYPT_MAX_PASSWORD_BYTES} UTF-8 bytes"
        )
    return bcrypt.hashpw(password_bytes, bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, hashed: str) -> bool:
    try:
        # Compatibility: accounts created before E01-R13 were hashed after a
        # silent 72-byte truncation. Keep truncation only on verification so
        # those users can still log in; new hashes reject overlong input.
        password_bytes = _password_bytes(password)[:BCRYPT_MAX_PASSWORD_BYTES]
        return bcrypt.checkpw(password_bytes, hashed.encode("utf-8"))
    except (ValueError, TypeError):
        return False


def create_access_token(subject: str | int) -> str:
    """Issue a signed JWT whose `sub` claim is the user id."""
    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(subject),
        "iat": now,
        "exp": now + timedelta(minutes=settings.access_token_expires_minutes),
    }
    return jwt.encode(payload, settings.secret_key, algorithm=settings.algorithm)


def decode_access_token(token: str) -> str | None:
    """Return the `sub` (user id as str) if the token is valid, else None."""
    try:
        payload = jwt.decode(
            token, settings.secret_key, algorithms=[settings.algorithm]
        )
    except jwt.PyJWTError:
        return None
    sub = payload.get("sub")
    return str(sub) if sub is not None else None
