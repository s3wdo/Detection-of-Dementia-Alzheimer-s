"""The main workflow: patient upload -> analysis -> doctor review -> release -> patient sees the result.
Also what the patient must NOT be able to see before release."""
import uuid

from sqlalchemy import select

from app.db import models as m
from tests.conftest import upload

API = "/api/v1"
AI_FIELDS = ("predicted_label", "confidence", "probabilities", "model_name", "simulated", "gate", "job_status")


def _notifications(client, headers):
    return client.get(f"{API}/notifications", headers=headers).json()


def test_full_flow_from_patient_upload_to_released_result(client, world, run_jobs):
    pid = world.patient_1.id

    # 1. The patient uploads. The reply is a receipt with no analysis output.
    receipt = upload(client, world.h_patient_1)
    assert set(receipt) == {"scan_id", "analysis_id", "status"} and receipt["status"] == "received"
    aid = receipt["analysis_id"]

    # 2. The server analyses it. Only the doctor is told.
    assert run_jobs() == 1
    doctor_notes = _notifications(client, world.h_doctor_a)
    assert [n["title"] for n in doctor_notes] == ["Analysis ready for review — Pat One"]
    assert doctor_notes[0]["entity_type"] == "analysis" and doctor_notes[0]["entity_id"] == aid
    assert _notifications(client, world.h_patient_1) == []

    # 3. The doctor finds it in the review queue, however many times it is fetched.
    for _ in range(3):
        queue = client.get(f"{API}/doctor/review-queue", headers=world.h_doctor_a).json()
        assert [item["analysis_id"] for item in queue] == [aid]
    item = queue[0]
    assert item["patient_name"] == "Pat One" and item["job_status"] == "completed"
    analysis = item["analysis"]
    assert analysis["simulated"] is True  # no real model is connected: never hidden
    assert analysis["status"] in ("awaitingConfirmation", "pendingReview")
    assert abs(sum(analysis["probabilities"].values()) - 1) < 1e-6
    assert client.get(f"{API}/analyses/{aid}/image", headers=world.h_doctor_a).json()["mime"] == "image/png"

    # 4. The doctor reviews without releasing: still invisible to the patient.
    reviewed = client.post(
        f"{API}/analyses/{aid}/review",
        headers=world.h_doctor_a,
        json={"decision": "confirmed", "clinical_notes": "private note", "patient_summary": "We will talk it through."},
    )
    assert reviewed.status_code == 201
    assert reviewed.json()["status"] == "confirmed"
    assert reviewed.json()["review"]["released_to_patient"] is False
    assert client.get(f"{API}/doctor/review-queue", headers=world.h_doctor_a).json() == []
    assert client.get(f"{API}/analyses/{aid}", headers=world.h_patient_1).status_code == 404
    assert _notifications(client, world.h_patient_1) == []

    # 5. The doctor releases it. The patient is notified and can now read it.
    released = client.post(f"{API}/analyses/{aid}/release", headers=world.h_doctor_a)
    assert released.status_code == 200 and released.json()["review"]["released_to_patient"] is True
    assert [n["title"] for n in _notifications(client, world.h_patient_1)] == ["Your MRI result is ready"]

    seen = client.get(f"{API}/analyses/{aid}", headers=world.h_patient_1)
    assert seen.status_code == 200
    seen = seen.json()
    assert seen["simulated"] is True
    assert seen["review"]["patient_summary"] == "We will talk it through."
    # Doctor-only information is absent from the patient's copy.
    assert "probabilities" not in seen and "confidence" not in seen
    timeline = client.get(f"{API}/patients/{pid}/timeline", headers=world.h_patient_1).json()
    assert timeline and all("confidence" not in e["summary"] and "%" not in e["summary"] for e in timeline)
    assert "clinical_notes" not in seen["review"] and "override_reason" not in seen["review"]
    assert "private note" not in str(seen)

    assert [a["id"] for a in client.get(f"{API}/patients/{pid}/analyses", headers=world.h_patient_1).json()] == [aid]
    assert client.get(f"{API}/analyses/{aid}/image", headers=world.h_patient_1).status_code == 200
    assert client.get(f"{API}/scans/mine", headers=world.h_patient_1).json()[0]["state"] == "released"


def test_nothing_about_an_unreleased_analysis_reaches_the_patient(client, world, run_jobs):
    pid = world.patient_1.id
    aid = upload(client, world.h_patient_1)["analysis_id"]
    run_jobs()
    # Reviewed but NOT released.
    client.post(
        f"{API}/analyses/{aid}/review",
        headers=world.h_doctor_a,
        json={"decision": "confirmed", "clinical_notes": "private", "patient_summary": "summary"},
    )
    h = world.h_patient_1

    assert client.get(f"{API}/analyses/{aid}", headers=h).status_code == 404
    assert client.get(f"{API}/analyses/{aid}/image", headers=h).status_code == 404
    assert client.get(f"{API}/analyses/{aid}/status", headers=h).status_code == 403
    assert client.get(f"{API}/patients/{pid}/analyses", headers=h).json() == []
    assert client.get(f"{API}/patients/{pid}/timeline", headers=h).json() == []
    dashboard = client.get(f"{API}/patient/dashboard", headers=h).json()
    assert dashboard["latest_released"] is None and dashboard["recent_activity"] == []
    assert client.get(f"{API}/patients/{pid}", headers=h).json()["latest_analysis"] is None
    assert client.get(f"{API}/notifications", headers=h).json() == []

    # The upload list shows only that the scan was received.
    uploads = client.get(f"{API}/scans/mine", headers=h).json()
    assert uploads == [
        {"scan_id": uploads[0]["scan_id"], "analysis_id": aid, "uploaded_at": uploads[0]["uploaded_at"], "state": "received"}
    ]
    for field in AI_FIELDS:
        assert field not in uploads[0]

    # A patient cannot review or release.
    assert client.post(f"{API}/analyses/{aid}/release", headers=h).status_code == 403
    assert client.post(f"{API}/analyses/{aid}/review", headers=h, json={"decision": "confirmed"}).status_code == 403


def test_a_review_cannot_be_submitted_twice(client, world, run_jobs, db):
    aid = upload(client, world.h_patient_1)["analysis_id"]
    run_jobs()
    body = {"decision": "confirmed", "patient_summary": "ok"}
    assert client.post(f"{API}/analyses/{aid}/review", headers=world.h_doctor_a, json=body).status_code == 201
    again = client.post(f"{API}/analyses/{aid}/review", headers=world.h_doctor_a, json=body)
    assert again.status_code == 409 and again.json()["error"]["code"] == "CONFLICT"
    assert len(db.scalars(select(m.Review)).all()) == 1


def test_review_rules_are_enforced_by_the_server(client, world, run_jobs, db):
    aid = upload(client, world.h_patient_1)["analysis_id"]

    # Not analysed yet: there is nothing to review or release.
    early = client.post(f"{API}/analyses/{aid}/review", headers=world.h_doctor_a, json={"decision": "confirmed"})
    assert early.status_code == 409
    assert client.post(f"{API}/analyses/{aid}/release", headers=world.h_doctor_a).status_code == 409

    run_jobs()
    predicted = db.get(m.Analysis, uuid.UUID(aid)).predicted_label
    other = next(label for label in m.MODEL_LABELS if label != predicted)

    def review(**fields):
        return client.post(f"{API}/analyses/{aid}/review", headers=world.h_doctor_a, json=fields)

    assert review(decision="overridden").status_code == 422  # no final label
    assert review(decision="overridden", final_label="Alzheimers", override_reason="long enough reason").status_code == 422
    assert review(decision="overridden", final_label=predicted, override_reason="long enough reason").status_code == 422
    assert review(decision="overridden", final_label=other, override_reason="short").status_code == 422
    assert review(decision="confirmed", release_to_patient=True).status_code == 422  # no patient summary
    assert db.scalars(select(m.Review)).all() == []

    ok = review(decision="overridden", final_label=other, override_reason="Clinical picture differs.")
    assert ok.status_code == 201
    assert ok.json()["status"] == "overridden" and ok.json()["review"]["final_label"] == other

    # Release needs a patient summary, and none was written.
    assert client.post(f"{API}/analyses/{aid}/release", headers=world.h_doctor_a).status_code == 409
    assert client.get(f"{API}/analyses/{aid}", headers=world.h_patient_1).status_code == 404


def test_review_and_release_in_one_step_and_release_is_idempotent(client, world, run_jobs, db):
    aid = upload(client, world.h_patient_1)["analysis_id"]
    run_jobs()
    done = client.post(
        f"{API}/analyses/{aid}/review",
        headers=world.h_doctor_a,
        json={"decision": "confirmed", "patient_summary": "All explained at your visit.", "release_to_patient": True},
    )
    assert done.status_code == 201 and done.json()["review"]["released_to_patient"] is True
    first_release = db.scalar(select(m.Review.released_at))

    # Releasing again changes nothing and does not notify twice.
    assert client.post(f"{API}/analyses/{aid}/release", headers=world.h_doctor_a).status_code == 200
    db.expire_all()
    assert db.scalar(select(m.Review.released_at)) == first_release
    assert len(client.get(f"{API}/notifications", headers=world.h_patient_1).json()) == 1

    actions = set(db.scalars(select(m.AuditEvent.action)))
    assert {"scan_uploaded", "analysis_completed", "review_confirmed", "result_released"} <= actions


def test_a_doctor_can_upload_for_an_assigned_patient_only(client, world, run_jobs):
    assert client.post(
        f"{API}/scans", headers=world.h_doctor_a, json={"image_base64": "x", "filename": "a.png"}
    ).status_code == 422  # a doctor must name the patient

    receipt = upload(client, world.h_doctor_a, patient_id=world.patient_2.id)
    run_jobs()
    status = client.get(f"{API}/analyses/{receipt['analysis_id']}/status", headers=world.h_doctor_a).json()
    assert status["job_status"] == "completed"

    # Not their patient.
    from tests.conftest import image_b64

    other = client.post(
        f"{API}/scans",
        headers=world.h_doctor_a,
        json={"image_base64": image_b64(), "filename": "a.png", "patient_id": str(world.patient_3.id)},
    )
    assert other.status_code == 404


def test_a_patient_cannot_upload_into_another_patients_record(client, world, db):
    receipt = upload(client, world.h_patient_1, patient_id=world.patient_2.id)  # patient_id is ignored
    scan = db.get(m.Scan, uuid.UUID(receipt["scan_id"]))
    assert scan.patient_id == world.patient_1.id
