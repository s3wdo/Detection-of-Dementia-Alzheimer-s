"""Who is calling, and which records they may touch.

Every route gets its identity from the access token through these helpers.
Identity fields in request bodies (patient_id for patients, sender names…) are
never trusted.
"""
import uuid
from typing import Annotated

from fastapi import Depends, Header
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.errors import ApiError, not_found
from app.core.security import decode_access_token
from app.db.models import Analysis, Doctor, Patient, Review, Role, User
from app.db.session import get_db

Db = Annotated[Session, Depends(get_db)]


def current_user(db: Db, authorization: Annotated[str | None, Header()] = None) -> User:
    unauthenticated = ApiError(401, "UNAUTHENTICATED", "Please sign in.")
    if not authorization or not authorization.lower().startswith("bearer "):
        raise unauthenticated
    claims = decode_access_token(authorization[7:].strip())
    if claims is None:
        raise unauthenticated
    try:
        user = db.get(User, uuid.UUID(claims["sub"]))
    except (KeyError, ValueError):
        raise unauthenticated
    if user is None or not user.is_active:
        raise unauthenticated
    return user


CurrentUser = Annotated[User, Depends(current_user)]


def current_doctor(user: CurrentUser, db: Db) -> Doctor:
    doctor = db.scalar(select(Doctor).where(Doctor.user_id == user.id)) if user.role == Role.doctor else None
    if doctor is None:
        raise ApiError(403, "FORBIDDEN", "This action is for doctors.")
    return doctor


def current_patient(user: CurrentUser, db: Db) -> Patient:
    patient = db.scalar(select(Patient).where(Patient.user_id == user.id)) if user.role == Role.patient else None
    if patient is None:
        raise ApiError(403, "FORBIDDEN", "This action is for patients.")
    return patient


CurrentDoctor = Annotated[Doctor, Depends(current_doctor)]
CurrentPatient = Annotated[Patient, Depends(current_patient)]


def as_uuid(value: str) -> uuid.UUID:
    """Path IDs that are not UUIDs are treated as unknown records."""
    try:
        return uuid.UUID(str(value))
    except ValueError:
        raise not_found()


class Access:
    """Record-level checks for the signed-in user. "Not yours" is always 404."""

    def __init__(self, user: CurrentUser, db: Db):
        self.user, self.db = user, db
        self.is_doctor = user.role == Role.doctor
        self._doctor: Doctor | None = None
        self._patient: Patient | None = None

    @property
    def doctor(self) -> Doctor:
        if self._doctor is None:
            self._doctor = current_doctor(self.user, self.db)
        return self._doctor

    @property
    def own_patient(self) -> Patient:
        if self._patient is None:
            self._patient = current_patient(self.user, self.db)
        return self._patient

    def patient(self, patient_id: str) -> Patient:
        """A patient this user may see: assigned (doctor) or themselves (patient)."""
        pid = as_uuid(patient_id)
        if self.is_doctor:
            patient = self.db.scalar(select(Patient).where(Patient.id == pid, Patient.doctor_id == self.doctor.id))
        else:
            patient = self.own_patient if self.own_patient.id == pid else None
        if patient is None:
            raise not_found()
        return patient

    def assigned_patient(self, patient_id: str) -> Patient:
        """Doctor-only: one of the doctor's own patients."""
        _ = self.doctor  # 403 for patients
        return self.patient(patient_id)

    def analysis(self, analysis_id: str, *, for_update: bool = False) -> Analysis:
        """An analysis this user may see.

        Doctors: any analysis of an assigned patient. Patients: their own,
        and only once the doctor has released it.
        """
        aid = as_uuid(analysis_id)
        query = select(Analysis).join(Patient, Analysis.patient_id == Patient.id).where(Analysis.id == aid)
        if self.is_doctor:
            query = query.where(Patient.doctor_id == self.doctor.id)
        else:
            query = (
                query.join(Review, Review.analysis_id == Analysis.id)
                .where(Analysis.patient_id == self.own_patient.id)
                .where(Review.released_at.is_not(None))
            )
        if for_update:
            query = query.with_for_update(of=Analysis)
        analysis = self.db.scalar(query)
        if analysis is None:
            raise not_found()
        return analysis


AccessDep = Annotated[Access, Depends(Access)]
