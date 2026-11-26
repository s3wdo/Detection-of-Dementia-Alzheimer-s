"""Upload validation, and how analysis jobs behave: failures, retries, restarts, duplicates."""
import base64
import io
import uuid

from PIL import Image
from sqlalchemy import select

from app.core.config import get_settings
from app.db import models as m
from app.services.analysis_worker import process_one, requeue_interrupted
from tests.conftest import image_b64, upload

API = "/api/v1"


def _post(client, headers, image_base64):
    return client.post(f"{API}/scans", headers=headers, json={"image_base64": image_base64, "filename": "x.png"})


def _code(response):
    return response.json()["error"]["code"]


def test_invalid_uploads_are_rejected(client, world, db):
    h = world.h_patient_1

    bad_base64 = _post(client, h, "this is not base64 !!!")
    assert bad_base64.status_code == 422 and _code(bad_base64) == "IMAGE_INVALID_BASE64"

    not_an_image = _post(client, h, base64.b64encode(b"%PDF-1.4 not an image at all").decode())
    assert not_an_image.status_code == 422 and _code(not_an_image) == "IMAGE_UNREADABLE"

    # A real image in a format that is not allowed, even if named .png by the client.
    gif = io.BytesIO()
    Image.new("L", (64, 64), 50).save(gif, format="GIF")
    wrong_format = _post(client, h, base64.b64encode(gif.getvalue()).decode())
    assert wrong_format.status_code == 422 and _code(wrong_format) == "IMAGE_UNSUPPORTED_FORMAT"

    truncated = _post(client, h, base64.b64encode(base64.b64decode(image_b64())[:60]).decode())
    assert truncated.status_code == 422 and _code(truncated) == "IMAGE_UNREADABLE"

    too_wide = _post(client, h, image_b64(size=(257, 100)))
    assert too_wide.status_code == 422 and _code(too_wide) == "IMAGE_DIMENSIONS_TOO_LARGE"

    assert _post(client, h, "").status_code == 422
    assert db.scalars(select(m.Scan)).all() == []  # nothing was stored


def test_size_limits(client, world):
    h = world.h_patient_1
    assert _post(client, h, image_b64(size=(256, 256))).status_code == 202  # exactly at the limit

    # Over 1 MB once decoded (but under the request-body limit).
    big = base64.b64encode(b"\x89PNG\r\n\x1a\n" + b"0" * 1_100_000).decode()
    too_big = _post(client, h, big)
    assert too_big.status_code == 413 and _code(too_big) == "IMAGE_TOO_LARGE"

    # Over the request-body limit: refused before the JSON is parsed.
    huge = _post(client, h, "A" * 2_200_000)
    assert huge.status_code == 413 and _code(huge) == "PAYLOAD_TOO_LARGE"


def test_jpeg_is_accepted_and_stored_as_clean_png(client, world, db):
    receipt = _post(client, world.h_patient_1, image_b64(fmt="JPEG"))
    assert receipt.status_code == 202
    scan = db.get(m.Scan, uuid.UUID(receipt.json()["scan_id"]))
    assert scan.image.startswith(b"\x89PNG") and (scan.width, scan.height) == (128, 128)


def test_uploading_the_same_image_twice_returns_the_same_receipt(client, world, db, run_jobs):
    first = upload(client, world.h_patient_1, shade=10)
    second = upload(client, world.h_patient_1, shade=10)
    assert first == second
    assert len(db.scalars(select(m.Scan)).all()) == 1
    assert run_jobs() == 1
    # A different patient uploading the same bytes gets their own scan.
    assert upload(client, world.h_patient_2, shade=10)["scan_id"] != first["scan_id"]


def test_the_stub_marks_every_result_as_simulated(client, world, run_jobs, db):
    upload(client, world.h_patient_1)
    run_jobs()
    analysis = db.scalar(select(m.Analysis))
    assert analysis.simulated is True and analysis.model_version == "stub"
    assert analysis.model_sha256 is None
    assert client.get("/health").json()["model"] == "stub"


def test_confidence_gate_routes_the_result(client, world, db):
    class Fixed:
        name, version, sha256, simulated = "fixed", "t", None, True

        def __init__(self, confidence):
            self.confidence = confidence

        def predict(self, image):
            from app.ml.predictor import Prediction

            rest = (1 - self.confidence) / 3
            return Prediction(
                {"LMCI": self.confidence, "CN": rest, "EMCI": rest, "AD": rest}
            )

    upload(client, world.h_patient_1, shade=1)
    process_one(db, Fixed(0.79), get_settings())
    upload(client, world.h_patient_2, shade=2)
    process_one(db, Fixed(0.80), get_settings())
    db.expire_all()
    gates = {a.patient_id: a.gate for a in db.scalars(select(m.Analysis))}
    assert gates[world.patient_1.id] == m.Gate.pending_review
    assert gates[world.patient_2.id] == m.Gate.awaiting_confirmation


class _Broken:
    name, version, sha256, simulated = "broken", "t", None, True

    def predict(self, image):
        raise RuntimeError("model exploded")


def test_a_failing_model_is_retried_then_marked_failed_and_people_are_told(client, world, db, run_jobs):
    aid = upload(client, world.h_patient_1)["analysis_id"]

    attempts = run_jobs(_Broken())
    assert attempts == get_settings().max_analysis_attempts
    analysis = db.get(m.Analysis, uuid.UUID(aid))
    assert analysis.job_status == m.JobStatus.failed and analysis.error_code == "MODEL_ERROR"
    assert analysis.predicted_label is None

    status = client.get(f"{API}/analyses/{aid}/status", headers=world.h_doctor_a).json()
    assert status == {"analysis_id": aid, "job_status": "failed", "error_code": "MODEL_ERROR"}
    # There is no result to read or review.
    assert client.get(f"{API}/analyses/{aid}", headers=world.h_doctor_a).status_code == 404
    assert client.post(
        f"{API}/analyses/{aid}/review", headers=world.h_doctor_a, json={"decision": "confirmed"}
    ).status_code == 409

    # The doctor sees it in the queue as failed, and both sides are notified.
    queue = client.get(f"{API}/doctor/review-queue", headers=world.h_doctor_a).json()
    assert queue[0]["job_status"] == "failed" and queue[0]["analysis"] is None
    assert "Analysis failed" in client.get(f"{API}/notifications", headers=world.h_doctor_a).json()[0]["title"]
    patient_note = client.get(f"{API}/notifications", headers=world.h_patient_1).json()[0]
    assert patient_note["title"] == "We could not process your scan"
    assert client.get(f"{API}/scans/mine", headers=world.h_patient_1).json()[0]["state"] == "needs_reupload"

    # The doctor retries it once the model works again.
    retried = client.post(f"{API}/analyses/{aid}/retry", headers=world.h_doctor_a)
    assert retried.status_code == 200 and retried.json()["job_status"] == "queued"
    assert run_jobs() == 1
    db.expire_all()
    assert db.get(m.Analysis, uuid.UUID(aid)).job_status == m.JobStatus.completed
    # Retrying something that did not fail is refused.
    assert client.post(f"{API}/analyses/{aid}/retry", headers=world.h_doctor_a).status_code == 409


def test_reuploading_after_a_failure_retries_the_analysis(client, world, db, run_jobs):
    first = upload(client, world.h_patient_1, shade=33)
    run_jobs(_Broken())
    again = upload(client, world.h_patient_1, shade=33)
    assert again == first
    assert run_jobs() == 1
    db.expire_all()
    assert db.scalar(select(m.Analysis.job_status)) == m.JobStatus.completed


def test_jobs_interrupted_by_a_restart_are_run_again(client, world, db, run_jobs):
    aid = uuid.UUID(upload(client, world.h_patient_1)["analysis_id"])
    analysis = db.get(m.Analysis, aid)
    analysis.job_status = m.JobStatus.running  # as if the process died mid-inference
    analysis.attempts = 1
    db.commit()

    assert run_jobs() == 0  # a running job is not picked up twice
    assert requeue_interrupted(db) == 1  # what startup does
    assert run_jobs() == 1
    assert db.get(m.Analysis, aid).job_status == m.JobStatus.completed
    # One completion notification, not two.
    assert len(client.get(f"{API}/notifications", headers=world.h_doctor_a).json()) == 1


def test_a_job_that_keeps_being_interrupted_eventually_fails(client, world, db, run_jobs):
    aid = uuid.UUID(upload(client, world.h_patient_1)["analysis_id"])
    analysis = db.get(m.Analysis, aid)
    analysis.attempts = get_settings().max_analysis_attempts  # already tried the maximum
    db.commit()
    run_jobs()
    assert db.get(m.Analysis, aid).job_status == m.JobStatus.failed
    assert db.get(m.Analysis, aid).error_code == "TOO_MANY_ATTEMPTS"
