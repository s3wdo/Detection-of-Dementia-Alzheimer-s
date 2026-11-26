"""A patient's timeline, built from analyses, reviews, appointments and doctor
messages. With `patient_view` only released results appear."""
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.models import Analysis, Appointment, Decision, JobStatus, Message, Patient
from app.schemas.api import TimelineEventOut

_LABELS = {
    "CN": "Cognitively Normal",
    "EMCI": "Early MCI",
    "LMCI": "Late MCI",
    "AD": "Alzheimer's Disease",
}


def patient_timeline(db: Session, patient: Patient, *, patient_view: bool) -> list[TimelineEventOut]:
    name = patient.user.full_name
    events: list[TimelineEventOut] = []

    analyses = db.scalars(
        select(Analysis).where(Analysis.patient_id == patient.id, Analysis.job_status == JobStatus.completed)
    )
    for a in analyses:
        review = a.review
        released = review is not None and review.released_at is not None
        if patient_view and not released:
            continue  # nothing about an unreleased analysis reaches the patient
        events.append(
            TimelineEventOut(
                id=f"{a.id}-ai",
                patient_id=patient.id,
                patient_name=name,
                date=a.created_at,
                type="mriAnalysis",
                source="ai",
                title="MRI analysis",
                # Patients are not shown the model's confidence score.
                summary=_LABELS[a.predicted_label]
                if patient_view
                else f"{_LABELS[a.predicted_label]} · {a.confidence * 100:.1f}% model confidence",
                pending=review is None,
            )
        )
        if review is not None:
            decision = (
                f"Final classification: {_LABELS[review.final_label]}"
                if review.decision == Decision.overridden
                else "AI result confirmed"
            )
            suffix = " · released to patient" if released and not patient_view else ""
            events.append(
                TimelineEventOut(
                    id=f"{a.id}-review",
                    patient_id=patient.id,
                    patient_name=name,
                    date=review.reviewed_at,
                    type="doctorReview",
                    source="doctor",
                    title="Doctor review",
                    summary=f"Reviewed by {review.doctor.user.full_name} · {decision}{suffix}",
                )
            )

    for ap in db.scalars(select(Appointment).where(Appointment.patient_id == patient.id)):
        events.append(
            TimelineEventOut(
                id=f"{ap.id}-appt",
                patient_id=patient.id,
                patient_name=name,
                date=ap.starts_at,
                type="appointment",
                source="admin",
                title=ap.reason,
                summary=f"{ap.status.value.capitalize()} · {ap.duration_min} min",
            )
        )

    for m in db.scalars(select(Message).where(Message.patient_id == patient.id, Message.from_doctor.is_(True))):
        events.append(
            TimelineEventOut(
                id=f"msg-{m.id}",
                patient_id=patient.id,
                patient_name=name,
                date=m.created_at,
                type="message",
                source="doctor",
                title=f"Message from {m.sender.full_name}",
                summary=m.body,
            )
        )

    events.sort(key=lambda e: e.date, reverse=True)
    return events
