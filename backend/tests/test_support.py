"""Appointments, messages, notifications, timeline, dashboards, patients list and image retention."""
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import select

from app.db import models as m
from app.services.retention import purge_images
from tests.conftest import upload

API = "/api/v1"


def _in_days(days: int) -> str:
    return (datetime.now(timezone.utc) + timedelta(days=days)).isoformat()


def _release(client, world, run_jobs, headers=None, shade=90) -> str:
    aid = upload(client, headers or world.h_patient_1, shade=shade)["analysis_id"]
    run_jobs()
    done = client.post(
        f"{API}/analyses/{aid}/review",
        headers=world.h_doctor_a,
        json={"decision": "confirmed", "patient_summary": "summary", "release_to_patient": True},
    )
    assert done.status_code == 201
    return aid


def test_appointment_request_confirm_reschedule_and_cancel(client, world):
    created = client.post(
        f"{API}/appointments", headers=world.h_patient_1, json={"reason": "Results discussion", "starts_at": _in_days(3)}
    )
    assert created.status_code == 201
    appointment = created.json()
    assert appointment["status"] == "requested" and appointment["doctor_name"] == "Dr. Alpha"
    apid = appointment["id"]
    assert "Appointment requested — Pat One" in [
        n["title"] for n in client.get(f"{API}/notifications", headers=world.h_doctor_a).json()
    ]

    past = client.post(f"{API}/appointments", headers=world.h_patient_1, json={"reason": "x", "starts_at": _in_days(-1)})
    assert past.status_code == 422

    # A patient may only cancel.
    assert client.patch(f"{API}/appointments/{apid}", headers=world.h_patient_1, json={"status": "confirmed"}).status_code == 409
    assert client.patch(
        f"{API}/appointments/{apid}", headers=world.h_patient_1, json={"starts_at": _in_days(5)}
    ).status_code == 409

    confirmed = client.patch(f"{API}/appointments/{apid}", headers=world.h_doctor_a, json={"status": "confirmed"})
    assert confirmed.json()["status"] == "confirmed"
    moved = client.patch(f"{API}/appointments/{apid}", headers=world.h_doctor_a, json={"starts_at": _in_days(6)})
    assert moved.status_code == 200 and moved.json()["starts_at"] != appointment["starts_at"]

    cancelled = client.patch(f"{API}/appointments/{apid}", headers=world.h_patient_1, json={"status": "cancelled"})
    assert cancelled.json()["status"] == "cancelled"
    # A cancelled appointment cannot be changed again.
    assert client.patch(f"{API}/appointments/{apid}", headers=world.h_doctor_a, json={"status": "confirmed"}).status_code == 409

    assert [a["id"] for a in client.get(f"{API}/appointments", headers=world.h_doctor_a).json()] == [apid]
    assert client.get(f"{API}/appointments/{apid}", headers=world.h_patient_1).json()["status"] == "cancelled"


def test_messages_between_patient_and_doctor(client, world):
    pid = world.patient_1.id
    sent = client.post(
        f"{API}/patients/{pid}/messages", headers=world.h_patient_1, json={"body": "When are my results ready?", "linked_to": "MRI analysis · 5 Oct"}
    )
    assert sent.status_code == 201 and sent.json()["linked_to"] == "MRI analysis · 5 Oct"

    threads = client.get(f"{API}/messages/threads", headers=world.h_doctor_a).json()
    assert len(threads) == 1 and threads[0]["unread"] == 1 and threads[0]["patient_name"] == "Pat One"
    # The notification does not copy the message text.
    note = client.get(f"{API}/notifications", headers=world.h_doctor_a).json()[0]
    assert note["type"] == "message" and "results" not in note["body"]

    assert client.post(f"{API}/patients/{pid}/messages/read", headers=world.h_doctor_a).status_code == 204
    assert client.get(f"{API}/messages/threads", headers=world.h_doctor_a).json()[0]["unread"] == 0

    client.post(f"{API}/patients/{pid}/messages", headers=world.h_doctor_a, json={"body": "This week."})
    thread = client.get(f"{API}/patients/{pid}/messages", headers=world.h_patient_1).json()
    assert [(msg["from_doctor"], msg["sender_name"]) for msg in thread] == [(False, "Pat One"), (True, "Dr. Alpha")]
    assert thread[0]["read_at"] is not None and thread[1]["read_at"] is None
    assert client.post(f"{API}/patients/{pid}/messages", headers=world.h_patient_1, json={"body": "   "}).status_code == 422


def test_notifications_can_be_marked_read(client, world, run_jobs):
    upload(client, world.h_patient_1, shade=1)
    upload(client, world.h_patient_2, shade=2)
    run_jobs()
    notes = client.get(f"{API}/notifications", headers=world.h_doctor_a).json()
    assert len(notes) == 2 and all(n["read_at"] is None for n in notes)

    assert client.post(f"{API}/notifications/{notes[0]['id']}/read", headers=world.h_doctor_a).status_code == 204
    after = {n["id"]: n["read_at"] for n in client.get(f"{API}/notifications", headers=world.h_doctor_a).json()}
    assert after[notes[0]["id"]] is not None and after[notes[1]["id"]] is None

    assert client.post(f"{API}/notifications/read-all", headers=world.h_doctor_a).status_code == 204
    assert all(n["read_at"] for n in client.get(f"{API}/notifications", headers=world.h_doctor_a).json())
    assert client.post(f"{API}/notifications/{uuid.uuid4()}/read", headers=world.h_doctor_a).status_code == 404


def test_patient_list_filters_and_latest_analysis(client, world, run_jobs):
    _release(client, world, run_jobs, shade=5)  # patient 1: reviewed
    upload(client, world.h_patient_2, shade=6)  # patient 2: waiting for review
    run_jobs()

    def names(**params):
        return [p["full_name"] for p in client.get(f"{API}/patients", headers=world.h_doctor_a, params=params).json()]

    assert set(names()) == {"Pat One", "Pat Two"}
    assert names(filter="needsReview") == ["Pat Two"]
    assert names(filter="reviewed") == ["Pat One"]
    assert names(filter="noAnalyses") == []
    assert names(search="two") == ["Pat Two"]
    assert names(search=world.patient_1.display_id.lower()) == ["Pat One"]

    listed = client.get(f"{API}/patients", headers=world.h_doctor_a, params={"filter": "reviewed"}).json()[0]
    assert listed["mrn"] == world.patient_1.display_id
    assert listed["latest_analysis"]["status"] == "confirmed"
    assert listed["latest_analysis"]["simulated"] is True

    updated = client.patch(
        f"{API}/patients/{world.patient_1.id}/contact",
        headers=world.h_doctor_a,
        json={"phone": "+000 1", "emergency_contact": "New Contact"},
    )
    assert updated.json()["emergency_contact"] == "New Contact"


def test_timeline_and_dashboards(client, world, run_jobs):
    aid = _release(client, world, run_jobs, shade=7)
    upload(client, world.h_patient_1, shade=8)  # a second, unreleased analysis
    run_jobs()
    client.post(f"{API}/appointments", headers=world.h_patient_1, json={"reason": "Follow-up", "starts_at": _in_days(2)})
    pid = world.patient_1.id

    doctor_view = client.get(f"{API}/patients/{pid}/timeline", headers=world.h_doctor_a).json()
    assert [e["type"] for e in doctor_view].count("mriAnalysis") == 2
    assert any(e["pending"] for e in doctor_view)
    assert any("released to patient" in e["summary"] for e in doctor_view)

    patient_view = client.get(f"{API}/patients/{pid}/timeline", headers=world.h_patient_1).json()
    assert [e["type"] for e in patient_view].count("mriAnalysis") == 1  # only the released one
    assert not any(e["pending"] for e in patient_view)
    assert not any("released to patient" in e["summary"] for e in patient_view)
    assert {e["source"] for e in patient_view} == {"ai", "doctor", "admin"}

    doctor_dash = client.get(f"{API}/doctor/dashboard", headers=world.h_doctor_a).json()
    assert doctor_dash["patient_count"] == 2
    assert doctor_dash["pending_reviews"] == 1
    assert doctor_dash["recent_analyses"] == 2
    assert doctor_dash["upcoming_appointments"] == 1
    assert doctor_dash["recent_activity"] and doctor_dash["recent_activity"][0]["patient_name"] == "Pat One"

    patient_dash = client.get(f"{API}/patient/dashboard", headers=world.h_patient_1).json()
    assert patient_dash["latest_released"]["id"] == aid
    assert "probabilities" not in patient_dash["latest_released"]
    assert patient_dash["next_appointment"]["reason"] == "Follow-up"


def test_images_are_purged_after_the_retention_period_and_stay_gone(client, world, run_jobs, db):
    aid = _release(client, world, run_jobs, shade=9)
    unreviewed = upload(client, world.h_patient_2, shade=10)["analysis_id"]
    run_jobs()
    now = datetime.now(timezone.utc)

    assert purge_images(db, retention_days=30, now=now + timedelta(days=29)) == 0
    assert client.get(f"{API}/analyses/{aid}/image", headers=world.h_doctor_a).status_code == 200

    assert purge_images(db, retention_days=30, now=now + timedelta(days=31)) == 1
    assert purge_images(db, retention_days=30, now=now + timedelta(days=32)) == 0  # running it again changes nothing

    db.expire_all()
    scan = db.scalar(select(m.Scan).join(m.Analysis).where(m.Analysis.id == uuid.UUID(aid)))
    assert scan.image is None and scan.image_purged_at is not None

    for headers in (world.h_doctor_a, world.h_patient_1):
        gone = client.get(f"{API}/analyses/{aid}/image", headers=headers)
        assert gone.status_code == 404 and "image_base64" not in gone.text
    # The result itself is kept.
    assert client.get(f"{API}/analyses/{aid}", headers=world.h_patient_1).status_code == 200
    # An analysis that has not been reviewed keeps its image.
    assert client.get(f"{API}/analyses/{unreviewed}/image", headers=world.h_doctor_a).status_code == 200


def test_errors_use_the_envelope_and_do_not_echo_input(client, world):
    response = client.post(f"{API}/auth/login", json={"email": "secret-value@example.test"})
    assert response.status_code == 422
    body = response.json()
    assert set(body) == {"error"} and set(body["error"]) == {"code", "message"}
    assert "secret-value" not in response.text

    missing = client.get(f"{API}/nowhere", headers=world.h_doctor_a)
    assert missing.status_code == 404 and missing.json()["error"]["code"] == "NOT_FOUND"
