"""Scan upload, analysis results, doctor review and release.

The rule this file protects: a patient never receives any analysis output
until the doctor has reviewed AND released it. Patient-facing queries filter on
`reviews.released_at` in SQL, and patient responses use their own schema.
"""
import base64
import hashlib
import io
from datetime import datetime, timedelta, timezone
from typing import Annotated

from PIL import Image as PILImage

from fastapi import APIRouter, Body, Query, Request, Response
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from app.core.config import get_settings
from app.core.deps import AccessDep, CurrentDoctor, CurrentPatient, Db
from app.core.errors import ApiError, conflict, invalid, not_found
from app.db.models import (
    MODEL_LABELS,
    Analysis,
    Decision,
    JobStatus,
    NotificationType,
    Patient,
    Review,
    Scan,
)
from app.schemas.api import (
    AnalysisOut,
    ExplanationOut,
    ImageOut,
    JobStatusOut,
    PatientAnalysisOut,
    ReviewIn,
    ReviewQueueItemOut,
    ScanReceiptOut,
    ScanUploadIn,
    UploadStateOut,
)
from app.services.events import audit, notify
from app.services.image_validation import validate_image
from app.services.serialize import doctor_analysis, patient_analysis

router = APIRouter(tags=["scans and analyses"])


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ---------------------------------------------------------------- upload

@router.post("/scans", response_model=ScanReceiptOut, status_code=202)
def upload_scan(body: ScanUploadIn, access: AccessDep, request: Request) -> ScanReceiptOut:
    """Stores the image and queues its analysis. The response is a receipt only."""
    if access.is_doctor:
        if not body.patient_id:
            raise invalid("Choose the patient this scan belongs to.")
        patient = access.assigned_patient(body.patient_id)
    else:
        patient = access.own_patient  # from the token; body.patient_id is ignored

    image = validate_image(body.image_base64, get_settings())
    db = access.db

    def wake_worker() -> None:
        worker = getattr(request.app.state, "worker", None)
        if worker is not None:
            worker.wake()

    def receipt_for_existing() -> ScanReceiptOut | None:
        existing = db.scalar(select(Scan).where(Scan.patient_id == patient.id, Scan.sha256 == image.sha256))
        if existing is None or existing.analysis is None:
            return None
        again = existing.analysis
        if again.job_status == JobStatus.failed:
            # Uploading the same image again after a failure retries that analysis.
            if existing.image is None:
                existing.image, existing.image_purged_at = image.png, None
            again.job_status, again.attempts, again.error_code = JobStatus.queued, 0, None
            db.commit()
            wake_worker()
        return ScanReceiptOut(scan_id=existing.id, analysis_id=again.id)

    # The same image for the same patient (a retried request) returns the first receipt.
    if (existing := receipt_for_existing()) is not None:
        return existing

    scan = Scan(
        patient_id=patient.id,
        uploaded_by=access.user.id,
        filename=body.filename.strip()[:120],
        image=image.png,
        width=image.width,
        height=image.height,
        size_bytes=len(image.png),
        sha256=image.sha256,
    )
    analysis = Analysis(scan=scan, patient_id=patient.id, job_status=JobStatus.queued)
    db.add_all([scan, analysis])
    try:
        db.flush()  # assigns the ids
        audit(db, actor_id=access.user.id, action="scan_uploaded", entity_type="scan", entity_id=scan.id)
        db.commit()
    except IntegrityError:
        # Two identical uploads raced; the other one won.
        db.rollback()
        if (existing := receipt_for_existing()) is not None:
            return existing
        raise conflict("This scan was already uploaded.")

    wake_worker()
    return ScanReceiptOut(scan_id=scan.id, analysis_id=analysis.id)


@router.post("/scans/volume", response_model=ScanReceiptOut, status_code=202)
def upload_volume(
    body: Annotated[bytes, Body(media_type="application/octet-stream")],
    access: AccessDep,
    request: Request,
    patient_id: Annotated[str, Query()],
    filename: Annotated[str, Query(max_length=200)] = "scan.nii",
) -> ScanReceiptOut:
    """A full MRI scan (.nii or .nii.gz), sent as the raw file. Doctors only.
    The analysis extracts the axial slices, keeps the brain slices and averages
    the model's scores over them (see app/ml/volume.py)."""
    from app.ml.volume import VolumeError, read_nifti

    if not access.is_doctor:
        raise ApiError(403, "FORBIDDEN", "Only doctors can upload a full MRI scan.")
    patient = access.assigned_patient(patient_id)
    if getattr(request.app.state, "brain_filter", None) is None:
        raise ApiError(503, "FULL_SCANS_UNAVAILABLE", "Full-scan analysis is not available on this server.")
    settings = get_settings()
    if not body:
        raise invalid("The file is empty.", "VOLUME_INVALID")
    if len(body) > settings.max_volume_bytes:
        raise ApiError(413, "VOLUME_TOO_LARGE", "The scan file is too large.")
    try:
        shape = read_nifti(body, max_unpacked_bytes=settings.max_volume_unpacked_bytes).shape
    except VolumeError as exc:
        status = 413 if exc.code == "VOLUME_TOO_LARGE" else 422
        raise ApiError(status, exc.code, str(exc)) from exc

    db = access.db
    digest = hashlib.sha256(body).hexdigest()

    def wake_worker() -> None:
        worker = getattr(request.app.state, "worker", None)
        if worker is not None:
            worker.wake()

    existing = db.scalar(select(Scan).where(Scan.patient_id == patient.id, Scan.sha256 == digest))
    if existing is not None and existing.analysis is not None:
        again = existing.analysis
        if again.job_status == JobStatus.failed:
            # The same file again after a failure retries that analysis.
            existing.volume = body
            again.job_status, again.attempts, again.error_code = JobStatus.queued, 0, None
            db.commit()
            wake_worker()
        return ScanReceiptOut(scan_id=existing.id, analysis_id=again.id)

    scan = Scan(
        patient_id=patient.id,
        uploaded_by=access.user.id,
        filename=filename.strip()[:120],
        kind="volume",
        image=None,
        volume=body,
        width=int(shape[0]),
        height=int(shape[1]),
        size_bytes=len(body),
        sha256=digest,
    )
    analysis = Analysis(scan=scan, patient_id=patient.id, job_status=JobStatus.queued)
    db.add_all([scan, analysis])
    try:
        db.flush()
        audit(db, actor_id=access.user.id, action="volume_uploaded", entity_type="scan", entity_id=scan.id)
        db.commit()
    except IntegrityError:
        db.rollback()
        raise conflict("This scan was already uploaded.")
    wake_worker()
    return ScanReceiptOut(scan_id=scan.id, analysis_id=analysis.id)


@router.get("/scans/mine", response_model=list[UploadStateOut])
def my_uploads(patient: CurrentPatient, db: Db) -> list[UploadStateOut]:
    """A patient's own uploads with a coarse state. Nothing here reveals whether
    the analysis has run, what it found, or whether the doctor has looked at it."""
    scans = db.scalars(select(Scan).where(Scan.patient_id == patient.id).order_by(Scan.uploaded_at.desc()))
    result = []
    for scan in scans:
        analysis = scan.analysis
        if analysis is None:
            continue
        if analysis.review is not None and analysis.review.released_at is not None:
            state = "released"
        elif analysis.job_status == JobStatus.failed:
            state = "needs_reupload"
        else:
            state = "received"
        result.append(
            UploadStateOut(scan_id=scan.id, analysis_id=analysis.id, uploaded_at=scan.uploaded_at, state=state)
        )
    return result


# ---------------------------------------------------------------- reading results

@router.get("/patients/{patient_id}/analyses", response_model=None)
def list_analyses(patient_id: str, access: AccessDep) -> list[AnalysisOut] | list[PatientAnalysisOut]:
    patient = access.patient(patient_id)
    query = (
        select(Analysis)
        .where(Analysis.patient_id == patient.id, Analysis.job_status == JobStatus.completed)
        .order_by(Analysis.created_at.desc())
    )
    if access.is_doctor:
        return [doctor_analysis(a) for a in access.db.scalars(query)]
    released = query.join(Review, Review.analysis_id == Analysis.id).where(Review.released_at.is_not(None))
    return [patient_analysis(a) for a in access.db.scalars(released)]


@router.get("/analyses/{analysis_id}", response_model=None)
def get_analysis(analysis_id: str, access: AccessDep) -> AnalysisOut | PatientAnalysisOut:
    analysis = access.analysis(analysis_id)  # patients: released only, else 404
    if analysis.job_status != JobStatus.completed:
        raise not_found()  # no result yet; doctors poll /status instead
    return doctor_analysis(analysis) if access.is_doctor else patient_analysis(analysis)


@router.get("/analyses/{analysis_id}/status", response_model=JobStatusOut)
def analysis_status(analysis_id: str, access: AccessDep) -> JobStatusOut:
    """Job progress, for doctors only. Patients are never told how far an analysis is."""
    _ = access.doctor
    analysis = access.analysis(analysis_id)
    return JobStatusOut(analysis_id=analysis.id, job_status=analysis.job_status.value, error_code=analysis.error_code)


@router.get("/analyses/{analysis_id}/image", response_model=ImageOut)
def analysis_image(analysis_id: str, access: AccessDep) -> ImageOut:
    analysis = access.analysis(analysis_id)  # patients: released only, else 404
    scan = analysis.scan
    if scan.image is None:
        raise not_found("The image for this scan is no longer stored.")
    return ImageOut(
        image_base64=base64.b64encode(scan.image).decode(), mime="image/png", width=scan.width, height=scan.height
    )


@router.get("/analyses/{analysis_id}/explanation", response_model=ExplanationOut)
def analysis_explanation(analysis_id: str, access: AccessDep) -> ExplanationOut:
    """The Grad-CAM map. 404 when there is none: stub results, results from before
    maps were made, a model without Grad-CAM, or after the retention purge."""
    analysis = access.analysis(analysis_id)  # patients: released only, else 404
    if analysis.heatmap is None or analysis.model_input is None or analysis.explanation_method != "gradcam":
        raise not_found("There is no explainability map for this result.")
    from app.ml.gradcam import colour_heatmap_png

    with PILImage.open(io.BytesIO(analysis.model_input)) as shown:
        width, height = shown.size
    return ExplanationOut(
        method="gradcam",
        target_label=analysis.predicted_label,
        image_base64=base64.b64encode(analysis.model_input).decode(),
        heatmap_base64=base64.b64encode(colour_heatmap_png(analysis.heatmap)).decode(),
        width=width,
        height=height,
    )


@router.get("/analyses/{analysis_id}/report.pdf", response_class=Response)
def analysis_report_pdf(
    analysis_id: str,
    access: AccessDep,
    utc_offset_minutes: Annotated[int, Query(ge=-14 * 60, le=14 * 60)] = 0,
) -> Response:
    """The report as a PDF. Doctors: any reviewed analysis of an assigned patient.
    Patients: released results only (404 otherwise), in the patient version that
    has no model confidence, class scores or doctor-only fields."""
    from app.services.report_pdf import build_report

    analysis = access.analysis(analysis_id)  # patients: released only, else 404
    if analysis.job_status != JobStatus.completed:
        raise not_found()
    if analysis.review is None:
        raise conflict("A report is available after the doctor has reviewed the result.")
    pdf = build_report(
        analysis,
        for_patient=not access.is_doctor,
        generated_at=_now(),
        utc_offset=timedelta(minutes=utc_offset_minutes),
    )
    audit(access.db, actor_id=access.user.id, action="report_downloaded", entity_type="analysis",
          entity_id=analysis.id)
    access.db.commit()
    day = analysis.created_at.strftime("%Y-%m-%d")
    filename = f"NeuroSense-report-{analysis.patient.display_id}-{day}.pdf"
    return Response(
        content=pdf,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"', "Cache-Control": "no-store"},
    )


@router.post("/analyses/{analysis_id}/retry", response_model=JobStatusOut)
def retry_analysis(analysis_id: str, access: AccessDep, request: Request) -> JobStatusOut:
    """Puts a failed analysis back in the queue."""
    _ = access.doctor
    analysis = access.analysis(analysis_id, for_update=True)
    if analysis.job_status != JobStatus.failed:
        raise conflict("Only a failed analysis can be retried.")
    if analysis.scan.image is None:
        raise conflict("The image is no longer stored. Ask for a new upload.")
    analysis.job_status = JobStatus.queued
    analysis.attempts = 0
    analysis.error_code = None
    audit(access.db, actor_id=access.user.id, action="analysis_retried", entity_type="analysis", entity_id=analysis.id)
    access.db.commit()
    worker = getattr(request.app.state, "worker", None)
    if worker is not None:
        worker.wake()
    return JobStatusOut(analysis_id=analysis.id, job_status="queued")


# ---------------------------------------------------------------- doctor review queue

@router.get("/doctor/review-queue", response_model=list[ReviewQueueItemOut])
def review_queue(doctor: CurrentDoctor, db: Db) -> list[ReviewQueueItemOut]:
    """Everything waiting for this doctor, oldest first: completed analyses with
    no review yet, and failed analyses. Read-only: fetching it changes nothing,
    so items stay here until they are reviewed, however often it is fetched."""
    rows = db.scalars(
        select(Analysis)
        .join(Patient, Analysis.patient_id == Patient.id)
        .outerjoin(Review, Review.analysis_id == Analysis.id)
        .where(
            Patient.doctor_id == doctor.id,
            Review.id.is_(None),
            Analysis.job_status.in_([JobStatus.completed, JobStatus.failed]),
        )
        .order_by(Analysis.created_at)
    )
    return [
        ReviewQueueItemOut(
            analysis_id=a.id,
            patient_id=a.patient_id,
            patient_name=a.patient.user.full_name,
            patient_display_id=a.patient.display_id,
            uploaded_at=a.scan.uploaded_at,
            job_status=a.job_status.value,
            analysis=doctor_analysis(a) if a.job_status == JobStatus.completed else None,
        )
        for a in rows
    ]


# ---------------------------------------------------------------- review and release

def _release(db, analysis: Analysis, review: Review, actor_id) -> None:
    """Makes a reviewed result visible to the patient. Called inside the caller's transaction."""
    if not (review.patient_summary or "").strip():
        raise conflict("Add a patient summary before releasing the result.")
    if review.released_at is not None:
        return  # already released: nothing changes, no second notification
    review.released_at = _now()
    review.released_by = actor_id
    patient = analysis.patient
    notify(
        db,
        user_id=patient.user_id,
        type=NotificationType.review,
        title="Your MRI result is ready",
        body="Your doctor has reviewed your MRI analysis and released the result.",
        dedupe_key=f"result-released:{analysis.id}",
        entity_type="analysis",
        entity_id=analysis.id,
        patient_id=patient.id,
    )
    audit(db, actor_id=actor_id, action="result_released", entity_type="analysis", entity_id=analysis.id)


@router.post("/analyses/{analysis_id}/review", response_model=AnalysisOut, status_code=201)
def submit_review(analysis_id: str, body: ReviewIn, access: AccessDep) -> AnalysisOut:
    doctor = access.doctor
    db = access.db
    analysis = access.analysis(analysis_id, for_update=True)  # row lock: one review at a time
    if analysis.job_status != JobStatus.completed:
        raise conflict("This analysis has no result to review yet.")
    if analysis.review is not None:
        raise conflict("This analysis has already been reviewed.")

    # The app checks these too; the server does not rely on that.
    if body.decision == "overridden":
        if body.final_label not in MODEL_LABELS:
            raise invalid("Select the final classification.")
        if body.final_label == analysis.predicted_label:
            raise invalid("An override must differ from the AI prediction.")
        if len((body.override_reason or "").strip()) < 10:
            raise invalid("Explain why you are overriding the AI result (at least 10 characters).")
        final_label, reason = body.final_label, body.override_reason.strip()
    else:
        final_label, reason = analysis.predicted_label, None
    if body.release_to_patient and not body.patient_summary.strip():
        raise invalid("Write a summary for the patient before releasing the result.")

    review = Review(
        analysis_id=analysis.id,
        doctor_id=doctor.id,
        decision=Decision(body.decision),
        final_label=final_label,
        override_reason=reason,
        clinical_notes=body.clinical_notes.strip() or None,
        patient_summary=body.patient_summary.strip() or None,
    )
    db.add(review)
    analysis.review = review
    audit(db, actor_id=access.user.id, action=f"review_{body.decision}", entity_type="analysis", entity_id=analysis.id)
    if body.release_to_patient:
        _release(db, analysis, review, access.user.id)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise conflict("This analysis has already been reviewed.")
    return doctor_analysis(analysis)


@router.post("/analyses/{analysis_id}/release", response_model=AnalysisOut)
def release_result(analysis_id: str, access: AccessDep) -> AnalysisOut:
    _ = access.doctor
    analysis = access.analysis(analysis_id, for_update=True)
    if analysis.review is None:
        raise conflict("Review the result before releasing it.")
    _release(access.db, analysis, analysis.review, access.user.id)
    access.db.commit()
    return doctor_analysis(analysis)
