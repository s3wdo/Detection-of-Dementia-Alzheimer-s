"""Sign-in. Accounts are created by an admin (see routers/admin.py); there is no self-registration."""
import threading
import time
import uuid
from collections import defaultdict, deque
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Response
from sqlalchemy import func, select, update

from app.core.config import get_settings
from app.core.deps import CurrentUser, Db
from app.core.errors import ApiError
from app.core.security import (
    create_access_token,
    hash_refresh_token,
    new_refresh_token,
    verify_password,
)
from app.db.models import Admin, Doctor, Patient, RefreshToken, User
from app.schemas.api import LoginIn, ProfileFieldOut, ProfileOut, RefreshIn, TokensOut, UserOut
from app.services.events import audit
from app.services.serialize import user_out

router = APIRouter(tags=["auth"])

_INVALID_LOGIN = ApiError(401, "INVALID_CREDENTIALS", "The email or password is incorrect.")
_INVALID_REFRESH = ApiError(401, "UNAUTHENTICATED", "Your session has ended. Please sign in again.")

# Login attempts per email in the last minute. In memory: enough for one process.
_attempts: dict[str, deque[float]] = defaultdict(deque)
_attempts_lock = threading.Lock()


def _check_rate(email: str) -> None:
    limit = get_settings().login_attempts_per_minute
    now = time.monotonic()
    with _attempts_lock:
        recent = _attempts[email]
        while recent and now - recent[0] > 60:
            recent.popleft()
        if len(recent) >= limit:
            raise ApiError(429, "RATE_LIMITED", "Too many sign-in attempts. Wait a minute and try again.")
        recent.append(now)


def reset_login_attempts() -> None:
    with _attempts_lock:
        _attempts.clear()


def _profiles(db, user: User) -> tuple[Doctor | None, Patient | None]:
    return (
        db.scalar(select(Doctor).where(Doctor.user_id == user.id)),
        db.scalar(select(Patient).where(Patient.user_id == user.id)),
    )


def _user_out(db, user: User) -> UserOut:
    doctor, patient = _profiles(db, user)
    admin_id = None
    if doctor is None and patient is None:
        admin_id = db.scalar(select(Admin.display_id).where(Admin.user_id == user.id))
    return user_out(user, doctor, patient, admin_id)


def _find_user(db, login_name: str) -> User | None:
    """By email, or by display ID (D-1001, P-1024, A-1001)."""
    if "@" in login_name:
        return db.scalar(select(User).where(User.email == login_name))
    display_id = login_name.upper()
    for table in (Doctor, Patient, Admin):
        user = db.scalar(select(User).join(table, table.user_id == User.id).where(func.upper(table.display_id) == display_id))
        if user is not None:
            return user
    return None


def _issue(db, user: User, family_id: uuid.UUID) -> TokensOut:
    settings = get_settings()
    token, token_hash = new_refresh_token()
    db.add(
        RefreshToken(
            user_id=user.id,
            token_hash=token_hash,
            family_id=family_id,
            expires_at=datetime.now(timezone.utc) + timedelta(days=settings.refresh_token_days),
        )
    )
    return TokensOut(
        access_token=create_access_token(user.id, user.role.value),
        refresh_token=token,
        user=_user_out(db, user),
    )


@router.post("/auth/login", response_model=TokensOut)
def login(body: LoginIn, db: Db) -> TokensOut:
    email = body.email.strip().lower()
    _check_rate(email)
    user = _find_user(db, email)
    # Same error whether the account exists or not.
    if user is None or not user.is_active or not verify_password(body.password, user.password_hash):
        raise _INVALID_LOGIN
    tokens = _issue(db, user, family_id=uuid.uuid4())
    audit(db, actor_id=user.id, action="login", entity_type="user", entity_id=user.id)
    db.commit()
    return tokens


@router.post("/auth/refresh", response_model=TokensOut)
def refresh(body: RefreshIn, db: Db) -> TokensOut:
    """Exchanges a refresh token for a new pair. Each refresh token works once."""
    now = datetime.now(timezone.utc)
    stored = db.scalar(
        select(RefreshToken).where(RefreshToken.token_hash == hash_refresh_token(body.refresh_token)).with_for_update()
    )
    if stored is None:
        raise _INVALID_REFRESH
    if stored.revoked_at is not None:
        # A token that was already used is being presented again: assume it was
        # stolen and end every session that descends from the same login.
        db.execute(
            update(RefreshToken)
            .where(RefreshToken.family_id == stored.family_id, RefreshToken.revoked_at.is_(None))
            .values(revoked_at=now)
        )
        db.commit()
        raise _INVALID_REFRESH
    user = db.get(User, stored.user_id)
    if stored.expires_at <= now or user is None or not user.is_active:
        raise _INVALID_REFRESH
    stored.revoked_at = now
    tokens = _issue(db, user, family_id=stored.family_id)
    db.commit()
    return tokens


@router.post("/auth/logout", status_code=204)
def logout(body: RefreshIn, db: Db) -> Response:
    """Ends the session this refresh token belongs to. Always 204."""
    stored = db.scalar(select(RefreshToken).where(RefreshToken.token_hash == hash_refresh_token(body.refresh_token)))
    if stored is not None:
        db.execute(
            update(RefreshToken)
            .where(RefreshToken.family_id == stored.family_id, RefreshToken.revoked_at.is_(None))
            .values(revoked_at=datetime.now(timezone.utc))
        )
        db.commit()
    return Response(status_code=204)


@router.get("/me", response_model=UserOut)
def me(user: CurrentUser, db: Db) -> UserOut:
    return _user_out(db, user)


@router.get("/me/profile", response_model=ProfileOut)
def my_profile(user: CurrentUser, db: Db) -> ProfileOut:
    """Label/value lists for the app's profile detail screens."""
    doctor, patient = _profiles(db, user)

    def fields(*pairs: tuple[str, str]) -> list[ProfileFieldOut]:
        return [ProfileFieldOut(label=label, value=value or "—") for label, value in pairs]

    if doctor is not None:
        return ProfileOut(
            personal=fields(("Full name", user.full_name), ("Email", user.email), ("Phone", doctor.phone)),
            health=fields(
                ("Doctor ID", doctor.display_id),
                ("Specialty", doctor.specialty),
                ("Licence number", doctor.license_no),
                ("Clinic", doctor.clinic),
            ),
        )
    if patient is None:
        admin_id = db.scalar(select(Admin.display_id).where(Admin.user_id == user.id))
        return ProfileOut(
            personal=fields(("Full name", user.full_name), ("Email", user.email)),
            health=fields(("Admin ID", admin_id or "")),
        )
    assigned = patient.doctor
    return ProfileOut(
        personal=fields(
            ("Full name", user.full_name),
            ("Date of birth", patient.date_of_birth.strftime("%d %b %Y")),
            ("Sex", patient.sex.value.capitalize()),
            ("Email", user.email),
            ("Phone", patient.phone),
            ("Emergency contact", patient.emergency_contact),
        ),
        health=fields(
            ("Patient ID", patient.display_id),
            ("Assigned doctor", assigned.user.full_name),
            ("Clinic", assigned.clinic),
        ),
    )
