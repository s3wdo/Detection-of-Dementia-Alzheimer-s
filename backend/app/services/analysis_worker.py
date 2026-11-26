"""Runs queued analyses, one at a time, in a background thread of the API process.

Why not FastAPI BackgroundTasks: those are lost on restart and can run twice.
Here the queue is the `analyses` table itself:
  queued -> running -> completed | failed
- A job is claimed with SELECT ... FOR UPDATE SKIP LOCKED, so it runs once.
- Jobs left `running` by a crash are put back in the queue at startup.
- After `max_analysis_attempts` tries a job is marked failed and people are told.
Limits: one API process, one inference at a time. That is enough for this
project; the same claim query would also work with several worker processes.
"""
import io
import logging
import threading
import uuid
from datetime import datetime, timezone

from PIL import Image
from sqlalchemy import select, update
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import Settings
from app.db.models import Analysis, Gate, JobStatus, NotificationType, Patient, Scan
from app.ml.predictor import Predictor
from app.services.events import audit, notify
from app.services.retention import purge_images

log = logging.getLogger("neurosense.worker")


def _now() -> datetime:
    return datetime.now(timezone.utc)


def requeue_interrupted(db: Session) -> int:
    """Called at startup: anything still `running` was interrupted by a restart."""
    result = db.execute(update(Analysis).where(Analysis.job_status == JobStatus.running).values(job_status=JobStatus.queued))
    db.commit()
    return result.rowcount or 0


def _claim(db: Session) -> uuid.UUID | None:
    analysis = db.scalar(
        select(Analysis)
        .where(Analysis.job_status == JobStatus.queued)
        .order_by(Analysis.created_at)
        .limit(1)
        .with_for_update(skip_locked=True)
        .execution_options(populate_existing=True)
    )
    if analysis is None:
        db.rollback()
        return None
    analysis.job_status = JobStatus.running
    analysis.started_at = _now()
    analysis.attempts += 1
    db.commit()
    return analysis.id


def _fail(db: Session, analysis: Analysis, error_code: str) -> None:
    patient = db.get(Patient, analysis.patient_id)
    analysis.job_status = JobStatus.failed
    analysis.error_code = error_code
    analysis.completed_at = _now()
    notify(
        db,
        user_id=patient.doctor.user_id,
        type=NotificationType.analysis,
        title=f"Analysis failed — {patient.user.full_name}",
        body="The scan could not be analysed. Retry it or ask for a new upload.",
        dedupe_key=f"analysis-failed:{analysis.id}:{analysis.attempts}",
        entity_type="patient",
        entity_id=patient.id,
        patient_id=patient.id,
    )
    notify(
        db,
        user_id=patient.user_id,
        type=NotificationType.analysis,
        title="We could not process your scan",
        body="Please upload the image again, or contact your clinic.",
        dedupe_key=f"analysis-failed-patient:{analysis.id}:{analysis.attempts}",
        entity_type="upload",
        entity_id=analysis.scan_id,
        patient_id=patient.id,
    )
    audit(db, actor_id=None, action="analysis_failed", entity_type="analysis", entity_id=analysis.id)


def _analyse_volume(raw: bytes, predictor: Predictor, brain_filter, settings: Settings):
    from app.ml.volume import analyse_volume

    return analyse_volume(
        raw,
        predictor,
        brain_filter,
        prune_last=settings.volume_prune_last,
        min_slices=settings.volume_min_slices,
        max_unpacked_bytes=settings.max_volume_unpacked_bytes,
    )


def process_one(db: Session, predictor: Predictor, settings: Settings, brain_filter=None) -> bool:
    """Runs the next queued analysis. Returns False when the queue is empty."""
    # Other requests (uploads, retries) change these rows: never trust cached objects.
    db.expire_all()
    analysis_id = _claim(db)
    if analysis_id is None:
        return False

    scan = db.scalar(select(Scan).join(Analysis, Analysis.scan_id == Scan.id).where(Analysis.id == analysis_id))
    is_volume = scan is not None and scan.kind == "volume"
    image_bytes = (scan.volume if is_volume else scan.image) if scan else None
    db.rollback()  # no transaction is held open during inference

    attempts = db.scalar(select(Analysis.attempts).where(Analysis.id == analysis_id)) or 0
    db.rollback()

    prediction, volume, error_code = None, None, None
    if attempts > settings.max_analysis_attempts:
        # It kept being interrupted (for example the process died during inference).
        error_code = "TOO_MANY_ATTEMPTS"
    elif image_bytes is None:
        error_code = "IMAGE_MISSING"
    elif is_volume:
        from app.ml.predictor import Prediction
        from app.ml.volume import VolumeError

        if brain_filter is None:
            error_code = "BRAIN_FILTER_MISSING"
        else:
            try:
                volume = _analyse_volume(image_bytes, predictor, brain_filter, settings)
                prediction = Prediction(
                    volume.probabilities,
                    model_input_png=volume.model_input_png,
                    heatmap_png=volume.heatmap_png,
                    explanation_method=volume.explanation_method,
                )
            except VolumeError as exc:
                error_code = exc.code  # a problem with the scan itself: retrying will not help
            except Exception:  # noqa: BLE001
                log.error("analysis %s failed in the full-scan pipeline", analysis_id)
                error_code = "MODEL_ERROR"
    else:
        try:
            with Image.open(io.BytesIO(image_bytes)) as image:
                image.load()
                prediction = predictor.predict(image)
        except Exception:  # noqa: BLE001 - any model error is recorded on the job
            # The exception text is not logged: it could contain data from the image.
            log.error("analysis %s failed in the predictor", analysis_id)
            error_code = "MODEL_ERROR"

    analysis = db.scalar(
        select(Analysis).where(Analysis.id == analysis_id).with_for_update().execution_options(populate_existing=True)
    )
    if analysis is None or analysis.job_status != JobStatus.running:
        db.rollback()
        return True
    if prediction is None:
        if error_code == "MODEL_ERROR" and analysis.attempts < settings.max_analysis_attempts:
            analysis.job_status = JobStatus.queued  # try again
        else:
            _fail(db, analysis, error_code or "MODEL_ERROR")
        db.commit()
        return True

    patient = db.get(Patient, analysis.patient_id)
    analysis.predicted_label = prediction.label
    analysis.confidence = prediction.confidence
    analysis.probabilities = prediction.probabilities
    analysis.gate = Gate.pending_review if prediction.confidence < settings.confidence_gate else Gate.awaiting_confirmation
    analysis.model_name = predictor.name
    analysis.model_version = predictor.version
    analysis.model_sha256 = predictor.sha256
    analysis.simulated = predictor.simulated
    analysis.model_input = prediction.model_input_png
    analysis.heatmap = prediction.heatmap_png
    analysis.explanation_method = prediction.explanation_method
    if volume is not None:
        analysis.slices_total = volume.slices_total
        analysis.slices_kept = volume.slices_kept
        analysis.slices_used = volume.slices_used
        analysis.slice_index = volume.slice_index
        scan = db.get(Scan, analysis.scan_id)
        # Keep the slice the doctor is shown; the full scan file is not kept.
        scan.image = volume.slice_png
        scan.volume = None
    analysis.job_status = JobStatus.completed
    analysis.error_code = None
    analysis.completed_at = _now()
    # Only the doctor is told. The patient hears nothing until the result is released.
    notify(
        db,
        user_id=patient.doctor.user_id,
        type=NotificationType.analysis,
        title=f"Analysis ready for review — {patient.user.full_name}",
        body="A scan has been analysed and is waiting for your review.",
        dedupe_key=f"analysis-completed:{analysis.id}",
        entity_type="analysis",
        entity_id=analysis.id,
        patient_id=patient.id,
    )
    audit(db, actor_id=None, action="analysis_completed", entity_type="analysis", entity_id=analysis.id)
    db.commit()
    return True


class AnalysisWorker:
    def __init__(self, session_factory: sessionmaker, predictor: Predictor, settings: Settings, brain_filter=None):
        self._session_factory, self._predictor, self._settings = session_factory, predictor, settings
        self._brain_filter = brain_filter
        self._wake = threading.Event()
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, name="analysis-worker", daemon=True)
        self._last_purge: datetime | None = None

    def start(self) -> None:
        with self._session_factory() as db:
            count = requeue_interrupted(db)
            if count:
                log.warning("re-queued %d analyses interrupted by a restart", count)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        self._wake.set()
        self._thread.join(timeout=5)

    def wake(self) -> None:
        """Called after an upload so the job starts without waiting for the poll."""
        self._wake.set()

    def _run(self) -> None:
        while not self._stop.is_set():
            try:
                with self._session_factory() as db:
                    while process_one(db, self._predictor, self._settings, self._brain_filter):
                        pass
                    self._purge_daily(db)
            except Exception:  # noqa: BLE001 - keep the worker alive (e.g. database restart)
                log.exception("analysis worker error")
            self._wake.wait(self._settings.worker_poll_seconds)
            self._wake.clear()

    def _purge_daily(self, db: Session) -> None:
        now = _now()
        if self._last_purge is None or (now - self._last_purge).total_seconds() > 86_400:
            purged = purge_images(db, self._settings.image_retention_days, now)
            self._last_purge = now
            if purged:
                log.warning("retention: removed %d stored images", purged)
