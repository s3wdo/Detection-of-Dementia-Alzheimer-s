"""Patients. Doctors see their assigned patients; a patient sees only themselves."""
from typing import Literal

from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.deps import AccessDep, CurrentDoctor, Db
from app.core.errors import invalid
from app.db.models import Analysis, DoctorNote, JobStatus, Patient
from app.schemas.api import ContactIn, NoteIn, NoteOut, PatientOut
from app.services.events import audit
from app.services.serialize import patient_out

router = APIRouter(tags=["patients"])


def latest_completed(db: Session, patient_ids: list) -> dict:
    """Most recent completed analysis for each patient (doctor views only)."""
    if not patient_ids:
        return {}
    rows = db.scalars(
        select(Analysis)
        .where(Analysis.patient_id.in_(patient_ids), Analysis.job_status == JobStatus.completed)
        .order_by(Analysis.patient_id, Analysis.created_at.desc())
        .distinct(Analysis.patient_id)
    )
    return {a.patient_id: a for a in rows}


@router.get("/patients", response_model=list[PatientOut])
def list_patients(
    doctor: CurrentDoctor,
    db: Db,
    search: str = "",
    filter: Literal["all", "needsReview", "reviewed", "noAnalyses"] = "all",
) -> list[PatientOut]:
    patients = list(db.scalars(select(Patient).where(Patient.doctor_id == doctor.id)))
    latest = latest_completed(db, [p.id for p in patients])
    q = search.strip().lower()

    def keep(p: Patient) -> bool:
        a = latest.get(p.id)
        if q and q not in p.user.full_name.lower() and q not in p.display_id.lower():
            return False
        if filter == "needsReview":
            return a is not None and a.review is None
        if filter == "reviewed":
            return a is not None and a.review is not None
        if filter == "noAnalyses":
            return a is None
        return True

    kept = [p for p in patients if keep(p)]
    # Most recent analysis first; patients without one last, by name.
    kept.sort(key=lambda p: p.user.full_name)
    kept.sort(key=lambda p: latest[p.id].created_at.timestamp() if p.id in latest else 0, reverse=True)
    return [patient_out(p, latest.get(p.id)) for p in kept]


@router.get("/patients/{patient_id}", response_model=PatientOut)
def get_patient(patient_id: str, access: AccessDep) -> PatientOut:
    patient = access.patient(patient_id)
    # The latest AI analysis is included for doctors only.
    latest = latest_completed(access.db, [patient.id]).get(patient.id) if access.is_doctor else None
    return patient_out(patient, latest)


@router.patch("/patients/{patient_id}/contact", response_model=PatientOut)
def update_contact(patient_id: str, body: ContactIn, access: AccessDep) -> PatientOut:
    patient = access.assigned_patient(patient_id)
    patient.phone = body.phone.strip()
    patient.emergency_contact = body.emergency_contact.strip()
    audit(access.db, actor_id=access.user.id, action="contact_updated", entity_type="patient", entity_id=patient.id)
    access.db.commit()
    return patient_out(patient, latest_completed(access.db, [patient.id]).get(patient.id))


def _note_out(note: DoctorNote) -> NoteOut:
    return NoteOut(
        id=note.id,
        patient_id=note.patient_id,
        author=note.doctor.user.full_name,
        body=note.body,
        created_at=note.created_at,
    )


@router.get("/patients/{patient_id}/notes", response_model=list[NoteOut])
def list_notes(patient_id: str, access: AccessDep) -> list[NoteOut]:
    """Doctor-only working notes. Patients get 403 from assigned_patient()."""
    patient = access.assigned_patient(patient_id)
    notes = access.db.scalars(
        select(DoctorNote).where(DoctorNote.patient_id == patient.id).order_by(DoctorNote.created_at.desc())
    )
    return [_note_out(n) for n in notes]


@router.post("/patients/{patient_id}/notes", response_model=NoteOut, status_code=201)
def add_note(patient_id: str, body: NoteIn, access: AccessDep) -> NoteOut:
    patient = access.assigned_patient(patient_id)
    if not body.body.strip():
        raise invalid("Write a note first.")
    # The author is the signed-in doctor, never a name from the request.
    note = DoctorNote(patient_id=patient.id, doctor_id=access.doctor.id, body=body.body.strip())
    access.db.add(note)
    access.db.commit()
    return _note_out(note)
