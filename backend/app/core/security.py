"""Password hashing and tokens.

Access token: short-lived signed JWT carrying the user id and role.
Refresh token: random opaque string; only its SHA-256 is stored, so it can be
rotated and revoked.
"""
import hashlib
import secrets
import uuid
from datetime import datetime, timedelta, timezone

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError

from app.core.config import get_settings

_hasher = PasswordHasher()
_ALGORITHM = "HS256"


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return _hasher.verify(password_hash, password)
    except (VerifyMismatchError, Exception):
        return False


def create_access_token(user_id: uuid.UUID, role: str, now: datetime | None = None) -> str:
    settings = get_settings()
    now = now or datetime.now(timezone.utc)
    payload = {
        "sub": str(user_id),
        "role": role,
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(minutes=settings.access_token_minutes)).timestamp()),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=_ALGORITHM)


def decode_access_token(token: str) -> dict | None:
    """The token's claims, or None if it is invalid or expired."""
    try:
        return jwt.decode(token, get_settings().jwt_secret, algorithms=[_ALGORITHM])
    except jwt.PyJWTError:
        return None


def new_refresh_token() -> tuple[str, str]:
    """(token to give the client, hash to store)."""
    token = secrets.token_urlsafe(48)
    return token, hash_refresh_token(token)


def hash_refresh_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()
