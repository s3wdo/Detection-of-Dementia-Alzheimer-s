"""Appointments, messages, notifications, timeline and dashboards.

Every route limits its query to the caller's own records: a doctor's assigned
patients, or the patient themselves.
"""
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Response
from sqlalchemy import func, select, update

from app.core.deps import AccessDep, CurrentDoctor, CurrentPatient, CurrentUser, Db, as_uuid
from app.core.errors import conflict, invalid, not_found
from app.db.models import (
    Analysis,
    Appointment,
    AppointmentStatus,
    JobStatus,
    Message,
    Notification,
    NotificationType,
    Patient,
    Review,
)
from app.schemas.api import (
    AppointmentIn,
    AppointmentOut,
    AppointmentPatchIn,
    DoctorDashboardOut,
    MessageIn,
    MessageOut,
    NotificationOut,
    PatientDashboardOut,
    ThreadOut,
    TimelineEventOut,
)
from app.services.events import audit, notify
from app.services.serialize import appointment_out, message_out, patient_analysis
from app.services.timeline import patient_timeline

router = APIRouter()


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ---------------------------------------------------------------- appointments

def _own_appointments(access):
    query = select(Appointment)
    if access.is_doctor:
        return query.where(Appointment.doctor_id == access.doctor.id)
    return query.where(Appointment.patient_id == access.own_patient.id)


def _own_appointment(access, appointment_id: str, *, for_update: bool = False) -> Appointment:
    query = _own_appointments(access).where(Appointment.id == as_uuid(appointment_id))
    if for_update:
        query = query.with_for_update()
    appointment = access.db.scalar(query)
    if appointment is None:
        raise not_found()
    return appointment


@router.get("/appointments", response_model=list[AppointmentOut], tags=["appointments"])
def list_appointments(access: AccessDep) -> list[AppointmentOut]:
    rows = access.db.scalars(_own_appointments(access).order_by(Appointment.starts_at))
    return [appointment_out(a) for a in rows]


@router.get("/appointments/{appointment_id}", response_model=AppointmentOut, tags=["appointments"])
def get_appointment(appointment_id: str, access: AccessDep) -> AppointmentOut:
    return appointment_out(_own_appointment(access, appointment_id))


@router.post("/appointments", response_model=AppointmentOut, status_code=201, tags=["appointments"])
def request_appointment(body: AppointmentIn, access: AccessDep) -> AppointmentOut:
    if access.is_doctor:
        if not body.patient_id:
            raise invalid("Choose the patient for this appointment.")
        patient = access.assigned_patient(body.patient_id)
    else:
        patient = access.own_patient  # body.patient_id is ignored for patients
    if body.starts_at <= _now():
        raise invalid("Choose a time in the future.")
    appointment = Appointment(
        patient_id=patient.id,
        doctor_id=patient.doctor_id,
        starts_at=body.starts_at,
        reason=body.reason.strip(),
        notes=body.notes.strip(),
        status=AppointmentStatus.confirmed if access.is_doctor else AppointmentStatus.requested,
    )
    access.db.add(appointment)
    access.db.flush()
    if access.is_doctor:
        notify(
            access.db,
            user_id=patient.user_id,
            type=NotificationType.appointment,
            title="Appointment scheduled",
            body=f"{appointment.reason} with {patient.doctor.user.full_name}.",
            dedupe_key=f"appointment-created:{appointment.id}",
            entity_type="appointment",
            entity_id=appointment.id,
            patient_id=patient.id,
        )
    else:
        notify(
            access.db,
            user_id=patient.doctor.user_id,
            type=NotificationType.appointment,
            title=f"Appointment requested — {patient.user.full_name}",
            body=appointment.reason,
            dedupe_key=f"appointment-created:{appointment.id}",
            entity_type="appointment",
            entity_id=appointment.id,
            patient_id=patient.id,
        )
    access.db.commit()
    return appointment_out(appointment)


@router.patch("/appointments/{appointment_id}", response_model=AppointmentOut, tags=["appointments"])
def update_appointment(appointment_id: str, body: AppointmentPatchIn, access: AccessDep) -> AppointmentOut:
    """Doctors confirm, complete, cancel or reschedule. Patients may only cancel their own."""
    appointment = _own_appointment(access, appointment_id, for_update=True)
    if appointment.status in (AppointmentStatus.cancelled, AppointmentStatus.completed):
        raise conflict("This appointment can no longer be changed.")
    if not access.is_doctor and (body.status != "cancelled" or body.starts_at is not None):
        raise conflict("Patients can only cancel an appointment. Ask your clinic for other changes.")

    change = None
    if body.starts_at is not None:
        if body.starts_at <= _now():
            raise invalid("Choose a time in the future.")
        appointment.starts_at = body.starts_at
        appointment.status = AppointmentStatus.confirmed
        change = "rescheduled"
    if body.status is not None:
        appointment.status = AppointmentStatus(body.status)
        change = body.status
    if change is None:
        raise invalid("Nothing to change.")

    patient = appointment.patient
    recipient = patient.user_id if access.is_doctor else patient.doctor.user_id
    notify(
        access.db,
        user_id=recipient,
        type=NotificationType.appointment,
        title=f"Appointment {change}" + ("" if access.is_doctor else f" — {patient.user.full_name}"),
        body=appointment.reason,
        dedupe_key=f"appointment-{change}:{appointment.id}:{int(appointment.starts_at.timestamp())}",
        entity_type="appointment",
        entity_id=appointment.id,
        patient_id=patient.id,
    )
    audit(access.db, actor_id=access.user.id, action=f"appointment_{change}", entity_type="appointment", entity_id=appointment.id)
    access.db.commit()
    return appointment_out(appointment)


# ---------------------------------------------------------------- messages

@router.get("/messages/threads", response_model=list[ThreadOut], tags=["messages"])
def message_threads(doctor: CurrentDoctor, db: Db) -> list[ThreadOut]:
    """One conversation per assigned patient who has messages, newest first."""
    threads = []
    for patient in db.scalars(select(Patient).where(Patient.doctor_id == doctor.id)):
        last = db.scalar(
            select(Message).where(Message.patient_id == patient.id).order_by(Message.created_at.desc()).limit(1)
        )
        if last is None:
            continue
        unread = db.scalar(
            select(func.count())
            .select_from(Message)
            .where(Message.patient_id == patient.id, Message.from_doctor.is_(False), Message.read_at.is_(None))
        )
        threads.append(
            ThreadOut(patient_id=patient.id, patient_name=patient.user.full_name, last=message_out(last), unread=unread)
        )
    threads.sort(key=lambda t: t.last.created_at, reverse=True)
    return threads


@router.get("/patients/{patient_id}/messages", response_model=list[MessageOut], tags=["messages"])
def list_messages(patient_id: str, access: AccessDep) -> list[MessageOut]:
    patient = access.patient(patient_id)
    rows = access.db.scalars(select(Message).where(Message.patient_id == patient.id).order_by(Message.created_at))
    return [message_out(m) for m in rows]


@router.post("/patients/{patient_id}/messages", response_model=MessageOut, status_code=201, tags=["messages"])
def send_message(patient_id: str, body: MessageIn, access: AccessDep) -> MessageOut:
    patient = access.patient(patient_id)
    if not body.body.strip():
        raise invalid("Write a message first.")
    # Sender and direction come from the signed-in user, not from the request.
    message = Message(
        patient_id=patient.id,
        sender_id=access.user.id,
        from_doctor=access.is_doctor,
        body=body.body.strip(),
        linked_to=(body.linked_to or "").strip() or None,
    )
    access.db.add(message)
    access.db.flush()
    notify(
        access.db,
        user_id=patient.user_id if access.is_doctor else patient.doctor.user_id,
        type=NotificationType.message,
        title="New message from your doctor" if access.is_doctor else f"New message — {patient.user.full_name}",
        body="Open the conversation to read it.",  # the message text is not copied into the notification
        dedupe_key=f"message:{message.id}",
        entity_type="message",
        entity_id=message.id,
        patient_id=patient.id,
    )
    access.db.commit()
    return message_out(message)


@router.post("/patients/{patient_id}/messages/read", status_code=204, tags=["messages"])
def mark_thread_read(patient_id: str, access: AccessDep) -> Response:
    """Marks the other side's messages as read."""
    patient = access.patient(patient_id)
    access.db.execute(
        update(Message)
        .where(
            Message.patient_id == patient.id,
            Message.from_doctor.is_(not access.is_doctor),
            Message.read_at.is_(None),
        )
        .values(read_at=_now())
    )
    access.db.commit()
    return Response(status_code=204)


# ---------------------------------------------------------------- notifications

@router.get("/notifications", response_model=list[NotificationOut], tags=["notifications"])
def list_notifications(user: CurrentUser, db: Db) -> list[NotificationOut]:
    rows = db.scalars(
        select(Notification).where(Notification.user_id == user.id).order_by(Notification.created_at.desc()).limit(100)
    )
    return [NotificationOut.model_validate(n) for n in rows]


@router.post("/notifications/{notification_id}/read", status_code=204, tags=["notifications"])
def mark_notification_read(notification_id: str, user: CurrentUser, db: Db) -> Response:
    result = db.execute(
        update(Notification)
        .where(Notification.id == as_uuid(notification_id), Notification.user_id == user.id)
        .values(read_at=func.coalesce(Notification.read_at, _now()))
    )
    if not result.rowcount:
        raise not_found()
    db.commit()
    return Response(status_code=204)


@router.post("/notifications/read-all", status_code=204, tags=["notifications"])
def mark_all_notifications_read(user: CurrentUser, db: Db) -> Response:
    db.execute(
        update(Notification)
        .where(Notification.user_id == user.id, Notification.read_at.is_(None))
        .values(read_at=_now())
    )
    db.commit()
    return Response(status_code=204)


# ---------------------------------------------------------------- timeline and dashboards

@router.get("/patients/{patient_id}/timeline", response_model=list[TimelineEventOut], tags=["timeline"])
def timeline(patient_id: str, access: AccessDep) -> list[TimelineEventOut]:
    patient = access.patient(patient_id)
    return patient_timeline(access.db, patient, patient_view=not access.is_doctor)


@router.get("/doctor/dashboard", response_model=DoctorDashboardOut, tags=["dashboard"])
def doctor_dashboard(doctor: CurrentDoctor, db: Db) -> DoctorDashboardOut:
    now = _now()
    patients = list(db.scalars(select(Patient).where(Patient.doctor_id == doctor.id)))
    ids = [p.id for p in patients]
    completed = select(func.count()).select_from(Analysis).where(
        Analysis.patient_id.in_(ids), Analysis.job_status == JobStatus.completed
    )
    pending = db.scalar(
        completed.outerjoin(Review, Review.analysis_id == Analysis.id).where(Review.id.is_(None))
    )
    recent = db.scalar(completed.where(Analysis.created_at > now - timedelta(days=7)))
    upcoming = db.scalar(
        select(func.count())
        .select_from(Appointment)
        .where(
            Appointment.doctor_id == doctor.id,
            Appointment.starts_at > now,
            Appointment.starts_at < now + timedelta(days=7),
            Appointment.status.in_([AppointmentStatus.confirmed, AppointmentStatus.requested]),
        )
    )
    activity = [e for p in patients for e in patient_timeline(db, p, patient_view=False) if e.date <= now]
    activity.sort(key=lambda e: e.date, reverse=True)
    return DoctorDashboardOut(
        patient_count=len(patients),
        pending_reviews=pending or 0,
        recent_analyses=recent or 0,
        upcoming_appointments=upcoming or 0,
        recent_activity=activity[:5],
    )


@router.get("/patient/dashboard", response_model=PatientDashboardOut, tags=["dashboard"])
def patient_dashboard(patient: CurrentPatient, db: Db) -> PatientDashboardOut:
    now = _now()
    latest = db.scalar(
        select(Analysis)
        .join(Review, Review.analysis_id == Analysis.id)
        .where(Analysis.patient_id == patient.id, Review.released_at.is_not(None))
        .order_by(Analysis.created_at.desc())
        .limit(1)
    )
    next_appointment = db.scalar(
        select(Appointment)
        .where(
            Appointment.patient_id == patient.id,
            Appointment.starts_at > now,
            Appointment.status.in_([AppointmentStatus.confirmed, AppointmentStatus.requested]),
        )
        .order_by(Appointment.starts_at)
        .limit(1)
    )
    activity = [e for e in patient_timeline(db, patient, patient_view=True) if e.date <= now]
    return PatientDashboardOut(
        latest_released=None if latest is None else patient_analysis(latest),
        next_appointment=None if next_appointment is None else appointment_out(next_appointment),
        recent_activity=activity[:3],
    )
