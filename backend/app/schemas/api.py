"""Request and response shapes. Field names match what the Flutter models parse."""
import uuid
from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class Out(BaseModel):
    # protected_namespaces=() allows the field names model_name / model_version.
    model_config = ConfigDict(from_attributes=True, protected_namespaces=())


# ---------------------------------------------------------------- auth

class LoginIn(BaseModel):
    email: str = Field(max_length=254)
    password: str = Field(max_length=200)


class RefreshIn(BaseModel):
    refresh_token: str = Field(max_length=200)


class UserOut(Out):
    """Matches the app's Session.fromJson."""

    id: uuid.UUID
    full_name: str
    role: str
    subtitle: str
    patient_id: uuid.UUID | None = None
    display_id: str


class TokensOut(Out):
    access_token: str
    refresh_token: str
    user: UserOut


class ProfileFieldOut(Out):
    label: str
    value: str


class ProfileOut(Out):
    personal: list[ProfileFieldOut]
    health: list[ProfileFieldOut]


class ExplanationOut(Out):
    """Grad-CAM for one analysis: the image the model analysed and the map, both PNG."""

    method: Literal["gradcam"]
    target_label: str
    image_base64: str  # the model's input, after brain masking
    heatmap_base64: str  # the map in the JET colour scale (red = strongest)
    width: int
    height: int


# ---------------------------------------------------------------- admin

class AdminUserIn(BaseModel):
    role: Literal["admin", "doctor", "patient"]
    full_name: str = Field(min_length=2, max_length=120)
    email: str = Field(min_length=5, max_length=254, pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
    password: str = Field(min_length=8, max_length=200)
    # Doctors
    specialty: str = Field(default="", max_length=80)
    # Patients: the doctor's display ID (D-1001), date of birth and sex are required.
    doctor_display_id: str | None = Field(default=None, max_length=16)
    date_of_birth: date | None = None
    sex: Literal["female", "male"] | None = None


class AssignDoctorIn(BaseModel):
    doctor_display_id: str = Field(max_length=16)


class AdminUserOut(Out):
    """An account as the admin sees it. No clinical data."""

    id: uuid.UUID
    display_id: str
    role: str
    full_name: str
    email: str
    is_active: bool
    doctor_display_id: str | None = None  # patients: the assigned doctor
    doctor_name: str | None = None
    patient_count: int | None = None  # doctors


# ---------------------------------------------------------------- analyses

class ReviewOut(Out):
    """The doctor's view of a review, including doctor-only fields."""

    final_label: str
    doctor_name: str
    reviewed_at: datetime
    override_reason: str | None
    clinical_notes: str | None
    patient_summary: str | None
    released_to_patient: bool


class PatientReviewOut(Out):
    """What a patient may see of a review. There is deliberately no field for
    clinical notes or the override reason."""

    final_label: str
    doctor_name: str
    reviewed_at: datetime
    patient_summary: str | None
    released_to_patient: bool


class AnalysisOut(Out):
    """Doctor view. `status` is the app's ReviewStatus."""

    id: uuid.UUID
    patient_id: uuid.UUID
    created_at: datetime
    predicted_label: str
    confidence: float
    probabilities: dict[str, float]
    status: Literal["awaitingConfirmation", "pendingReview", "confirmed", "overridden"]
    model_name: str
    model_version: str
    simulated: bool
    review: ReviewOut | None = None
    # "slice": one uploaded image. "volume": a full scan; the scores are averaged
    # over `slices_used` slices and the image shown is axial slice `slice_index`.
    input_kind: Literal["slice", "volume"] = "slice"
    slices_total: int | None = None
    slices_kept: int | None = None
    slices_used: int | None = None
    slice_index: int | None = None


class PatientAnalysisOut(Out):
    """Patient view of a RELEASED analysis: no model confidence, no per-class scores,
    no doctor-only fields."""

    id: uuid.UUID
    patient_id: uuid.UUID
    created_at: datetime
    predicted_label: str
    status: Literal["confirmed", "overridden"]
    model_name: str
    model_version: str
    simulated: bool
    review: PatientReviewOut


class ScanUploadIn(BaseModel):
    image_base64: str
    filename: str = Field(default="", max_length=120)
    # Doctors only. Ignored for patients, whose record comes from their token.
    patient_id: str | None = None


class ScanReceiptOut(Out):
    """Returned to the uploader. Carries no analysis output."""

    scan_id: uuid.UUID
    analysis_id: uuid.UUID
    status: Literal["received"] = "received"


class UploadStateOut(Out):
    """A patient's own upload, with a coarse state and nothing about the result."""

    scan_id: uuid.UUID
    analysis_id: uuid.UUID
    uploaded_at: datetime
    state: Literal["received", "released", "needs_reupload"]


class JobStatusOut(Out):
    analysis_id: uuid.UUID
    job_status: Literal["queued", "running", "completed", "failed"]
    error_code: str | None = None


class ImageOut(Out):
    image_base64: str
    mime: str
    width: int
    height: int


class ReviewIn(BaseModel):
    """Matches the app's ReviewDraft.toJson."""

    decision: Literal["confirmed", "overridden"]
    final_label: str | None = None
    override_reason: str | None = Field(default=None, max_length=2000)
    clinical_notes: str = Field(default="", max_length=5000)
    patient_summary: str = Field(default="", max_length=2000)
    release_to_patient: bool = False


class ReviewQueueItemOut(Out):
    analysis_id: uuid.UUID
    patient_id: uuid.UUID
    patient_name: str
    patient_display_id: str
    uploaded_at: datetime
    job_status: Literal["completed", "failed"]
    # Present for completed analyses only.
    analysis: AnalysisOut | None = None


# ---------------------------------------------------------------- patients

class PatientOut(Out):
    """Matches the app's Patient.fromJson (`mrn` is the display ID, e.g. P-1024)."""

    id: uuid.UUID
    mrn: str
    full_name: str
    date_of_birth: date
    sex: str
    phone: str
    email: str
    emergency_contact: str
    latest_analysis: AnalysisOut | None = None


class ContactIn(BaseModel):
    phone: str = Field(max_length=40)
    emergency_contact: str = Field(max_length=120)


class NoteIn(BaseModel):
    body: str = Field(min_length=1, max_length=5000)


class NoteOut(Out):
    id: uuid.UUID
    patient_id: uuid.UUID
    author: str
    body: str
    created_at: datetime


# ---------------------------------------------------------------- appointments, messages, notifications

class AppointmentOut(Out):
    id: uuid.UUID
    patient_id: uuid.UUID
    patient_name: str
    doctor_name: str
    starts_at: datetime
    duration_min: int
    reason: str
    status: str
    location: str | None


class AppointmentIn(BaseModel):
    reason: str = Field(min_length=1, max_length=120)
    starts_at: datetime
    notes: str = Field(default="", max_length=2000)
    # Doctors only; a patient always books for themselves.
    patient_id: str | None = None


class AppointmentPatchIn(BaseModel):
    status: Literal["confirmed", "cancelled", "completed"] | None = None
    starts_at: datetime | None = None


class MessageOut(Out):
    id: uuid.UUID
    patient_id: uuid.UUID
    from_doctor: bool
    sender_name: str
    body: str
    created_at: datetime
    read_at: datetime | None
    linked_to: str | None


class MessageIn(BaseModel):
    body: str = Field(min_length=1, max_length=4000)
    linked_to: str | None = Field(default=None, max_length=120)


class ThreadOut(Out):
    patient_id: uuid.UUID
    patient_name: str
    last: MessageOut
    unread: int


class NotificationOut(Out):
    id: uuid.UUID
    user_id: uuid.UUID
    type: str
    title: str
    body: str
    created_at: datetime
    read_at: datetime | None
    entity_type: str | None
    entity_id: uuid.UUID | None
    patient_id: uuid.UUID | None


# ---------------------------------------------------------------- timeline, dashboards

class TimelineEventOut(Out):
    """Matches the app's TimelineEvent.fromJson."""

    id: str
    patient_id: uuid.UUID
    date: datetime
    type: Literal["mriAnalysis", "doctorReview", "appointment", "message"]
    source: Literal["ai", "doctor", "admin"]
    title: str
    summary: str
    patient_name: str | None = None
    pending: bool = False


class DoctorDashboardOut(Out):
    patient_count: int
    pending_reviews: int
    recent_analyses: int
    upcoming_appointments: int
    recent_activity: list[TimelineEventOut]


class PatientDashboardOut(Out):
    latest_released: PatientAnalysisOut | None
    next_appointment: AppointmentOut | None
    recent_activity: list[TimelineEventOut]
