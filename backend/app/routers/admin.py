"""Account management, for admins only.

An admin creates every account (admin, doctor or patient), each with its own
display ID, and assigns each patient to one doctor. Admins have no access to
scans, results, notes or messages: those routes need a doctor or patient.
"""
from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError

from app.core.deps import CurrentUser, Db, as_uuid
from app.core.errors import ApiError, not_found
from app.core.security import hash_password
from app.db.models import Admin, Doctor, Patient, Role, Sex, User
from app.schemas.api import AdminUserIn, AdminUserOut, AssignDoctorIn
from app.services.events import audit

router = APIRouter(prefix="/admin", tags=["admin"])

_PREFIX = {Admin: "A", Doctor: "D", Patient: "P"}


def current_admin(user: CurrentUser) -> User:
    if user.role != Role.admin:
        raise ApiError(403, "FORBIDDEN", "This action is for administrators.")
    return user


CurrentAdmin = Annotated[User, Depends(current_admin)]


def next_display_id(db, table) -> str:
    """The next free ID for the role: D-1003 after D-1002. Starts at 1001."""
    numbers = [int(v[2:]) for v in db.scalars(select(table.display_id)) if v[2:].isdigit()]
    return f"{_PREFIX[table]}-{max(numbers, default=1000) + 1}"


def _doctor_by_display_id(db, display_id: str | None) -> Doctor:
    doctor = None
    if display_id:
        doctor = db.scalar(select(Doctor).where(func.upper(Doctor.display_id) == display_id.strip().upper()))
    if doctor is None or not doctor.user.is_active:
        raise ApiError(422, "VALIDATION_ERROR", "Choose an existing doctor ID for this patient.")
    return doctor


def _rows(db, only_user_id=None) -> list[AdminUserOut]:
    counts = dict(db.execute(select(Patient.doctor_id, func.count()).group_by(Patient.doctor_id)).all())
    users = select(User).order_by(User.created_at)
    if only_user_id is not None:
        users = users.where(User.id == only_user_id)
    doctors = {d.user_id: d for d in db.scalars(select(Doctor))}
    patients = {p.user_id: p for p in db.scalars(select(Patient))}
    admins = dict(db.execute(select(Admin.user_id, Admin.display_id)).all())
    out = []
    for user in db.scalars(users):
        row = AdminUserOut(
            id=user.id,
            display_id=admins.get(user.id, ""),
            role=user.role.value,
            full_name=user.full_name,
            email=user.email,
            is_active=user.is_active,
        )
        if user.id in doctors:
            row.display_id = doctors[user.id].display_id
            row.patient_count = counts.get(doctors[user.id].id, 0)
        elif user.id in patients:
            patient = patients[user.id]
            row.display_id = patient.display_id
            row.doctor_display_id = patient.doctor.display_id
            row.doctor_name = patient.doctor.user.full_name
        out.append(row)
    return out


@router.get("/users", response_model=list[AdminUserOut])
def list_users(admin: CurrentAdmin, db: Db) -> list[AdminUserOut]:
    return _rows(db)


@router.post("/users", response_model=AdminUserOut, status_code=201)
def create_user(body: AdminUserIn, admin: CurrentAdmin, db: Db) -> AdminUserOut:
    email = body.email.strip().lower()
    if db.scalar(select(User.id).where(User.email == email)) is not None:
        raise ApiError(409, "CONFLICT", "An account with this email already exists.")
    role = Role(body.role)
    user = User(email=email, password_hash=hash_password(body.password), role=role, full_name=body.full_name.strip())
    db.add(user)
    try:
        db.flush()
        if role == Role.doctor:
            db.add(Doctor(user_id=user.id, display_id=next_display_id(db, Doctor), specialty=body.specialty.strip()))
        elif role == Role.patient:
            if body.date_of_birth is None or body.sex is None:
                raise ApiError(422, "VALIDATION_ERROR", "A patient needs a date of birth and sex.")
            db.add(
                Patient(
                    user_id=user.id,
                    display_id=next_display_id(db, Patient),
                    doctor_id=_doctor_by_display_id(db, body.doctor_display_id).id,
                    date_of_birth=body.date_of_birth,
                    sex=Sex(body.sex),
                )
            )
        else:
            db.add(Admin(user_id=user.id, display_id=next_display_id(db, Admin)))
        db.flush()
    except IntegrityError:
        db.rollback()
        raise ApiError(409, "CONFLICT", "The account could not be created. Try again.")
    except ApiError:
        db.rollback()
        raise
    audit(db, actor_id=admin.id, action="create_user", entity_type="user", entity_id=user.id)
    db.commit()
    return _rows(db, user.id)[0]


@router.patch("/users/{user_id}/doctor", response_model=AdminUserOut)
def assign_doctor(user_id: str, body: AssignDoctorIn, admin: CurrentAdmin, db: Db) -> AdminUserOut:
    """Moves a patient to another doctor. The patient's records move with them."""
    patient = db.scalar(select(Patient).where(Patient.user_id == as_uuid(user_id)))
    if patient is None:
        raise not_found()
    patient.doctor_id = _doctor_by_display_id(db, body.doctor_display_id).id
    audit(db, actor_id=admin.id, action="assign_doctor", entity_type="patient", entity_id=patient.id)
    db.commit()
    return _rows(db, patient.user_id)[0]
