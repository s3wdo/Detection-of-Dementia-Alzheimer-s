"""Database tables. UUID primary keys inside; D-1001 / P-1024 display IDs for people."""
import enum
import uuid
from datetime import date, datetime, timezone

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    Enum,
    Float,
    ForeignKey,
    Index,
    Integer,
    LargeBinary,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def _uuid() -> uuid.UUID:
    return uuid.uuid4()


class Base(DeclarativeBase):
    pass


def _pk() -> Mapped[uuid.UUID]:
    return mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)


def _ts(nullable: bool = False, default: bool = True) -> Mapped[datetime]:
    return mapped_column(DateTime(timezone=True), nullable=nullable, default=now_utc if default else None)


def _enum(cls: type[enum.Enum], name: str):
    # Stored as text values with a CHECK constraint (simple to migrate).
    return Enum(
        cls,
        name=name,
        native_enum=False,
        create_constraint=True,
        values_callable=lambda e: [m.value for m in e],
        length=32,
    )


class Role(str, enum.Enum):
    doctor = "doctor"
    patient = "patient"
    admin = "admin"


class Sex(str, enum.Enum):
    female = "female"
    male = "male"


class JobStatus(str, enum.Enum):
    queued = "queued"
    running = "running"
    completed = "completed"
    failed = "failed"


class Gate(str, enum.Enum):
    """Routing by model confidence. Names match the app's ReviewStatus."""

    awaiting_confirmation = "awaitingConfirmation"
    pending_review = "pendingReview"


class Decision(str, enum.Enum):
    confirmed = "confirmed"
    overridden = "overridden"


class AppointmentStatus(str, enum.Enum):
    requested = "requested"
    confirmed = "confirmed"
    cancelled = "cancelled"
    completed = "completed"


class NotificationType(str, enum.Enum):
    review = "review"
    message = "message"
    appointment = "appointment"
    analysis = "analysis"


# The four model classes, by the names the app uses on the wire, from normal to
# Alzheimer's disease. The model's own output order is set in model_config.yaml.
MODEL_LABELS = ("CN", "EMCI", "LMCI", "AD")


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = _pk()
    email: Mapped[str] = mapped_column(String(254), unique=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    role: Mapped[Role] = mapped_column(_enum(Role, "role"))
    full_name: Mapped[str] = mapped_column(String(120))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = _ts()

    doctor: Mapped["Doctor | None"] = relationship(back_populates="user", uselist=False)
    patient: Mapped["Patient | None"] = relationship(back_populates="user", uselist=False)


class RefreshToken(Base):
    __tablename__ = "refresh_tokens"

    id: Mapped[uuid.UUID] = _pk()
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    # All tokens descended from one login. Reuse of a rotated token revokes the family.
    family_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = _ts()


class Admin(Base):
    """Creates accounts and assigns patients to doctors. Sees no clinical data."""

    __tablename__ = "admins"

    id: Mapped[uuid.UUID] = _pk()
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), unique=True)
    display_id: Mapped[str] = mapped_column(String(16), unique=True)  # A-1001


class Doctor(Base):
    __tablename__ = "doctors"

    id: Mapped[uuid.UUID] = _pk()
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), unique=True)
    display_id: Mapped[str] = mapped_column(String(16), unique=True)  # D-1001
    specialty: Mapped[str] = mapped_column(String(80), default="")
    license_no: Mapped[str] = mapped_column(String(40), default="")
    clinic: Mapped[str] = mapped_column(String(120), default="")
    phone: Mapped[str] = mapped_column(String(40), default="")

    user: Mapped[User] = relationship(back_populates="doctor")
    patients: Mapped[list["Patient"]] = relationship(back_populates="doctor")


class Patient(Base):
    __tablename__ = "patients"

    id: Mapped[uuid.UUID] = _pk()
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), unique=True)
    display_id: Mapped[str] = mapped_column(String(16), unique=True)  # P-1024
    # One assigned doctor per patient in this version; a doctor has many patients.
    doctor_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("doctors.id"), index=True)
    date_of_birth: Mapped[date] = mapped_column(Date)
    sex: Mapped[Sex] = mapped_column(_enum(Sex, "sex"))
    phone: Mapped[str] = mapped_column(String(40), default="")
    emergency_contact: Mapped[str] = mapped_column(String(120), default="")

    user: Mapped[User] = relationship(back_populates="patient")
    doctor: Mapped[Doctor] = relationship(back_populates="patients")


class Scan(Base):
    __tablename__ = "scans"
    __table_args__ = (UniqueConstraint("patient_id", "sha256", name="uq_scan_patient_sha"),)

    id: Mapped[uuid.UUID] = _pk()
    patient_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("patients.id"), index=True)
    uploaded_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"))
    filename: Mapped[str] = mapped_column(String(120), default="")
    # "slice": one image. "volume": a full scan (.nii / .nii.gz) uploaded by a doctor.
    kind: Mapped[str] = mapped_column(String(8), default="slice", server_default="slice")
    # PNG bytes, re-encoded by the server. NULL after the retention purge.
    # For a full scan: the slice shown to the doctor, set when the analysis completes.
    image: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    # The uploaded scan file. Kept only until its analysis has completed.
    volume: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    width: Mapped[int] = mapped_column(Integer)
    height: Mapped[int] = mapped_column(Integer)
    size_bytes: Mapped[int] = mapped_column(Integer)
    sha256: Mapped[str] = mapped_column(String(64))
    uploaded_at: Mapped[datetime] = _ts()
    image_purged_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    patient: Mapped[Patient] = relationship()
    analysis: Mapped["Analysis | None"] = relationship(back_populates="scan", uselist=False)


class Analysis(Base):
    __tablename__ = "analyses"
    __table_args__ = (
        CheckConstraint("confidence IS NULL OR (confidence >= 0 AND confidence <= 1)", name="ck_analysis_confidence"),
        Index("ix_analyses_open_jobs", "created_at", postgresql_where="job_status IN ('queued', 'running')"),
    )

    id: Mapped[uuid.UUID] = _pk()
    # One analysis per scan in this version.
    scan_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("scans.id", ondelete="CASCADE"), unique=True)
    patient_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("patients.id"), index=True)

    job_status: Mapped[JobStatus] = mapped_column(_enum(JobStatus, "job_status"), default=JobStatus.queued)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    error_code: Mapped[str | None] = mapped_column(String(40), nullable=True)
    created_at: Mapped[datetime] = _ts()
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    # Filled in when the job completes.
    predicted_label: Mapped[str | None] = mapped_column(String(32), nullable=True)
    confidence: Mapped[float | None] = mapped_column(Float, nullable=True)
    probabilities: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    gate: Mapped[Gate | None] = mapped_column(_enum(Gate, "gate"), nullable=True)
    model_name: Mapped[str] = mapped_column(String(80), default="")
    model_version: Mapped[str] = mapped_column(String(40), default="")
    model_sha256: Mapped[str | None] = mapped_column(String(64), nullable=True)
    # True when no real model produced this result. Returned by every analysis response.
    simulated: Mapped[bool] = mapped_column(Boolean, default=True)
    # From a real model only: the image it analysed (after masking) and its
    # Grad-CAM map for the predicted class. Removed with the scan image (retention).
    model_input: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    heatmap: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    explanation_method: Mapped[str | None] = mapped_column(String(24), nullable=True)
    # Full scans only: axial slices in the scan, kept by the brain detector, used
    # after pruning, and the (0-based) slice shown with the Grad-CAM map.
    slices_total: Mapped[int | None] = mapped_column(Integer, nullable=True)
    slices_kept: Mapped[int | None] = mapped_column(Integer, nullable=True)
    slices_used: Mapped[int | None] = mapped_column(Integer, nullable=True)
    slice_index: Mapped[int | None] = mapped_column(Integer, nullable=True)

    scan: Mapped[Scan] = relationship(back_populates="analysis")
    patient: Mapped[Patient] = relationship()
    review: Mapped["Review | None"] = relationship(back_populates="analysis", uselist=False)


class Review(Base):
    __tablename__ = "reviews"

    id: Mapped[uuid.UUID] = _pk()
    # UNIQUE: an analysis can be reviewed once, enforced by the database.
    analysis_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("analyses.id", ondelete="CASCADE"), unique=True)
    doctor_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("doctors.id"))
    decision: Mapped[Decision] = mapped_column(_enum(Decision, "decision"))
    final_label: Mapped[str] = mapped_column(String(32))
    override_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    clinical_notes: Mapped[str | None] = mapped_column(Text, nullable=True)  # doctor-only
    patient_summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    reviewed_at: Mapped[datetime] = _ts()
    # The patient can see the result only when this is set.
    released_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    released_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id"), nullable=True)

    analysis: Mapped[Analysis] = relationship(back_populates="review")
    doctor: Mapped[Doctor] = relationship()


class DoctorNote(Base):
    __tablename__ = "doctor_notes"

    id: Mapped[uuid.UUID] = _pk()
    patient_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("patients.id"), index=True)
    doctor_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("doctors.id"))
    body: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = _ts()

    doctor: Mapped[Doctor] = relationship()


class Appointment(Base):
    __tablename__ = "appointments"

    id: Mapped[uuid.UUID] = _pk()
    patient_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("patients.id"), index=True)
    doctor_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("doctors.id"), index=True)
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    duration_min: Mapped[int] = mapped_column(Integer, default=30)
    reason: Mapped[str] = mapped_column(String(120))
    notes: Mapped[str] = mapped_column(Text, default="")
    location: Mapped[str | None] = mapped_column(String(80), nullable=True)
    status: Mapped[AppointmentStatus] = mapped_column(
        _enum(AppointmentStatus, "appointment_status"), default=AppointmentStatus.requested
    )
    created_at: Mapped[datetime] = _ts()

    patient: Mapped[Patient] = relationship()
    doctor: Mapped[Doctor] = relationship()


class Message(Base):
    __tablename__ = "messages"

    id: Mapped[uuid.UUID] = _pk()
    patient_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("patients.id"), index=True)
    sender_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"))
    from_doctor: Mapped[bool] = mapped_column(Boolean)
    body: Mapped[str] = mapped_column(Text)
    linked_to: Mapped[str | None] = mapped_column(String(120), nullable=True)
    created_at: Mapped[datetime] = _ts()
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    sender: Mapped[User] = relationship()


class Notification(Base):
    __tablename__ = "notifications"

    id: Mapped[uuid.UUID] = _pk()
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    type: Mapped[NotificationType] = mapped_column(_enum(NotificationType, "notification_type"))
    title: Mapped[str] = mapped_column(String(160))
    body: Mapped[str] = mapped_column(String(300))
    # What the notification points at; the app turns this into a screen route.
    entity_type: Mapped[str | None] = mapped_column(String(24), nullable=True)
    entity_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    patient_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("patients.id"), nullable=True)
    # Same event twice (a retry) creates one notification.
    dedupe_key: Mapped[str] = mapped_column(String(120), unique=True)
    created_at: Mapped[datetime] = _ts()
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class AuditEvent(Base):
    """Who did what to which record, and when. No free text and no clinical content."""

    __tablename__ = "audit_events"

    id: Mapped[uuid.UUID] = _pk()
    actor_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id"), nullable=True)
    action: Mapped[str] = mapped_column(String(40))
    entity_type: Mapped[str] = mapped_column(String(24))
    entity_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True))
    at: Mapped[datetime] = _ts()
