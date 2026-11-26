"""Builds API responses from database rows. The patient and doctor variants are
separate functions returning separate types, so doctor-only data has no path
into a patient response."""
from app.db.models import Analysis, Appointment, Doctor, Message, Patient, Review, User
from app.schemas.api import (
    AnalysisOut,
    AppointmentOut,
    MessageOut,
    PatientAnalysisOut,
    PatientOut,
    PatientReviewOut,
    ReviewOut,
    UserOut,
)


def analysis_status(analysis: Analysis) -> str:
    """The app's ReviewStatus: the doctor's decision if reviewed, else the confidence gate."""
    if analysis.review is not None:
        return analysis.review.decision.value
    return analysis.gate.value


def doctor_analysis(analysis: Analysis) -> AnalysisOut:
    review: Review | None = analysis.review
    return AnalysisOut(
        id=analysis.id,
        patient_id=analysis.patient_id,
        created_at=analysis.created_at,
        predicted_label=analysis.predicted_label,
        confidence=analysis.confidence,
        probabilities=analysis.probabilities or {},
        status=analysis_status(analysis),
        model_name=analysis.model_name,
        model_version=analysis.model_version,
        simulated=analysis.simulated,
        input_kind="volume" if analysis.scan is not None and analysis.scan.kind == "volume" else "slice",
        slices_total=analysis.slices_total,
        slices_kept=analysis.slices_kept,
        slices_used=analysis.slices_used,
        slice_index=analysis.slice_index,
        review=None
        if review is None
        else ReviewOut(
            final_label=review.final_label,
            doctor_name=review.doctor.user.full_name,
            reviewed_at=review.reviewed_at,
            override_reason=review.override_reason,
            clinical_notes=review.clinical_notes,
            patient_summary=review.patient_summary,
            released_to_patient=review.released_at is not None,
        ),
    )


def patient_analysis(analysis: Analysis) -> PatientAnalysisOut:
    """Only call for a released analysis (the queries guarantee it; this asserts it)."""
    review = analysis.review
    if review is None or review.released_at is None:
        raise RuntimeError("unreleased analysis reached a patient response")
    return PatientAnalysisOut(
        id=analysis.id,
        patient_id=analysis.patient_id,
        created_at=analysis.created_at,
        predicted_label=analysis.predicted_label,
        status=review.decision.value,
        model_name=analysis.model_name,
        model_version=analysis.model_version,
        simulated=analysis.simulated,
        review=PatientReviewOut(
            final_label=review.final_label,
            doctor_name=review.doctor.user.full_name,
            reviewed_at=review.reviewed_at,
            patient_summary=review.patient_summary,
            released_to_patient=True,
        ),
    )


def patient_out(patient: Patient, latest: Analysis | None = None) -> PatientOut:
    return PatientOut(
        id=patient.id,
        mrn=patient.display_id,
        full_name=patient.user.full_name,
        date_of_birth=patient.date_of_birth,
        sex=patient.sex.value,
        phone=patient.phone,
        email=patient.user.email,
        emergency_contact=patient.emergency_contact,
        latest_analysis=None if latest is None else doctor_analysis(latest),
    )


def user_out(user: User, doctor: Doctor | None, patient: Patient | None, admin_id: str | None = None) -> UserOut:
    if doctor is None and patient is None:
        return UserOut(
            id=user.id, full_name=user.full_name, role=user.role.value, subtitle="Administrator", display_id=admin_id or ""
        )
    if doctor is not None:
        return UserOut(
            id=user.id,
            full_name=user.full_name,
            role=user.role.value,
            subtitle=doctor.specialty,
            display_id=doctor.display_id,
        )
    return UserOut(
        id=user.id,
        full_name=user.full_name,
        role=user.role.value,
        subtitle=f"Patient ID {patient.display_id}",
        patient_id=patient.id,
        display_id=patient.display_id,
    )


def appointment_out(a: Appointment) -> AppointmentOut:
    return AppointmentOut(
        id=a.id,
        patient_id=a.patient_id,
        patient_name=a.patient.user.full_name,
        doctor_name=a.doctor.user.full_name,
        starts_at=a.starts_at,
        duration_min=a.duration_min,
        reason=a.reason,
        status=a.status.value,
        location=a.location,
    )


def message_out(m: Message) -> MessageOut:
    return MessageOut(
        id=m.id,
        patient_id=m.patient_id,
        from_doctor=m.from_doctor,
        sender_name=m.sender.full_name,
        body=m.body,
        created_at=m.created_at,
        read_at=m.read_at,
        linked_to=m.linked_to,
    )
