"""Record-level access: every route that takes an ID is tried by the wrong
patient and by a doctor the patient is not assigned to. All must answer 404."""
import uuid
from datetime import datetime, timedelta, timezone

import pytest

from app.db import models as m
from tests.conftest import upload

API = "/api/v1"


@pytest.fixture
def records(client, world, run_jobs, db):
    """Patient 1 (doctor A) has a released analysis, an appointment, a note and a message."""
    aid = upload(client, world.h_patient_1)["analysis_id"]
    run_jobs()
    client.post(
        f"{API}/analyses/{aid}/review",
        headers=world.h_doctor_a,
        json={"decision": "confirmed", "patient_summary": "summary", "release_to_patient": True},
    )
    starts = (datetime.now(timezone.utc) + timedelta(days=3)).isoformat()
    appointment = client.post(
        f"{API}/appointments", headers=world.h_patient_1, json={"reason": "Follow-up", "starts_at": starts}
    ).json()
    client.post(f"{API}/patients/{world.patient_1.id}/notes", headers=world.h_doctor_a, json={"body": "doctor note"})
    client.post(f"{API}/patients/{world.patient_1.id}/messages", headers=world.h_patient_1, json={"body": "hello"})
    notification = client.get(f"{API}/notifications", headers=world.h_patient_1).json()[0]
    return {"aid": aid, "apid": appointment["id"], "nid": notification["id"], "pid": str(world.patient_1.id)}


def _routes(r):
    pid, aid, apid, nid = r["pid"], r["aid"], r["apid"], r["nid"]
    return [
        ("GET", f"/patients/{pid}", None),
        ("PATCH", f"/patients/{pid}/contact", {"phone": "1", "emergency_contact": "x"}),
        ("GET", f"/patients/{pid}/notes", None),
        ("POST", f"/patients/{pid}/notes", {"body": "x"}),
        ("GET", f"/patients/{pid}/analyses", None),
        ("GET", f"/patients/{pid}/timeline", None),
        ("GET", f"/patients/{pid}/messages", None),
        ("POST", f"/patients/{pid}/messages", {"body": "x"}),
        ("POST", f"/patients/{pid}/messages/read", None),
        ("GET", f"/analyses/{aid}", None),
        ("GET", f"/analyses/{aid}/status", None),
        ("GET", f"/analyses/{aid}/image", None),
        ("POST", f"/analyses/{aid}/retry", None),
        ("POST", f"/analyses/{aid}/review", {"decision": "confirmed"}),
        ("POST", f"/analyses/{aid}/release", None),
        ("GET", f"/appointments/{apid}", None),
        ("PATCH", f"/appointments/{apid}", {"status": "cancelled"}),
        ("POST", f"/notifications/{nid}/read", None),
    ]


def _call(client, method, path, body, headers):
    return client.request(method, f"{API}{path}", json=body, headers=headers)


def test_an_unassigned_doctor_gets_404_everywhere(client, world, records):
    for method, path, body in _routes(records):
        response = _call(client, method, path, body, world.h_doctor_b)
        assert response.status_code == 404, f"{method} {path} -> {response.status_code}"


def test_another_patient_gets_404_or_403_and_never_data(client, world, records):
    """Patient 2 has the same doctor as patient 1 and still sees nothing of theirs.
    Doctor-only routes answer 403 (wrong role); everything else 404."""
    doctor_only = ("/notes", "/contact", "/status", "/retry", "/review", "/release")
    for method, path, body in _routes(records):
        response = _call(client, method, path, body, world.h_patient_2)
        expected = 403 if path.endswith(doctor_only) else 404
        assert response.status_code == expected, f"{method} {path} -> {response.status_code}"


def test_unknown_and_malformed_ids_are_404(client, world):
    for bad in (str(uuid.uuid4()), "not-a-uuid", "1 OR 1=1"):
        assert client.get(f"{API}/patients/{bad}", headers=world.h_doctor_a).status_code == 404
        assert client.get(f"{API}/analyses/{bad}", headers=world.h_doctor_a).status_code == 404
        assert client.get(f"{API}/appointments/{bad}", headers=world.h_doctor_a).status_code == 404


def test_lists_contain_only_the_callers_records(client, world, records):
    assert {p["full_name"] for p in client.get(f"{API}/patients", headers=world.h_doctor_a).json()} == {"Pat One", "Pat Two"}
    assert [p["full_name"] for p in client.get(f"{API}/patients", headers=world.h_doctor_b).json()] == ["Pat Three"]

    assert client.get(f"{API}/doctor/review-queue", headers=world.h_doctor_b).json() == []
    assert client.get(f"{API}/appointments", headers=world.h_doctor_b).json() == []
    assert client.get(f"{API}/appointments", headers=world.h_patient_2).json() == []
    assert client.get(f"{API}/messages/threads", headers=world.h_doctor_b).json() == []
    assert client.get(f"{API}/scans/mine", headers=world.h_patient_2).json() == []
    assert client.get(f"{API}/notifications", headers=world.h_patient_2).json() == []
    assert client.get(f"{API}/doctor/dashboard", headers=world.h_doctor_b).json()["pending_reviews"] == 0
    assert client.get(f"{API}/doctor/dashboard", headers=world.h_doctor_b).json()["recent_activity"] == []


def test_identity_in_the_request_body_is_ignored(client, world, db):
    pid = world.patient_1.id
    # A patient claiming to be the doctor.
    sent = client.post(
        f"{API}/patients/{pid}/messages",
        headers=world.h_patient_1,
        json={"body": "hi", "from_doctor": True, "sender_name": "Dr. Alpha", "patient_id": str(world.patient_2.id)},
    ).json()
    assert sent["from_doctor"] is False and sent["sender_name"] == "Pat One" and sent["patient_id"] == str(pid)

    # A doctor's note is always authored by the signed-in doctor.
    note = client.post(
        f"{API}/patients/{pid}/notes", headers=world.h_doctor_a, json={"body": "n", "author": "Someone Else"}
    ).json()
    assert note["author"] == "Dr. Alpha"

    # A patient booking "for" someone else books for themselves.
    starts = (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()
    booked = client.post(
        f"{API}/appointments",
        headers=world.h_patient_1,
        json={"reason": "r", "starts_at": starts, "patient_id": str(world.patient_3.id)},
    ).json()
    assert booked["patient_id"] == str(pid) and booked["status"] == "requested"


def test_a_patient_reads_their_own_profile_without_doctor_only_data(client, world, records):
    own = client.get(f"{API}/patients/{records['pid']}", headers=world.h_patient_1)
    assert own.status_code == 200 and own.json()["latest_analysis"] is None
    assert db_has_note_hidden(client, world, records)


def db_has_note_hidden(client, world, records) -> bool:
    everything = "".join(
        client.get(f"{API}{path}", headers=world.h_patient_1).text
        for path in (
            f"/patients/{records['pid']}",
            f"/patients/{records['pid']}/analyses",
            f"/patients/{records['pid']}/timeline",
            f"/analyses/{records['aid']}",
            "/patient/dashboard",
            "/notifications",
            "/me/profile",
        )
    )
    return "doctor note" not in everything and "clinical_notes" not in everything
