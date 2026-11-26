from datetime import datetime, timedelta, timezone

from app.core.security import create_access_token
from tests.conftest import PASSWORD, login, make_doctor, make_patient

API = "/api/v1"


def test_login_returns_tokens_and_the_session_the_app_expects(client, db):
    doctor = make_doctor(db, "Dr. Alpha", "D-1001")
    patient = make_patient(db, doctor, "Pat One", "P-1024")

    body = client.post(f"{API}/auth/login", json={"email": patient.user.email, "password": PASSWORD}).json()
    assert body["access_token"] and body["refresh_token"]
    assert body["user"] == {
        "id": str(patient.user_id),
        "full_name": "Pat One",
        "role": "patient",
        "subtitle": "Patient ID P-1024",
        "patient_id": str(patient.id),
        "display_id": "P-1024",
    }

    me = client.get(f"{API}/me", headers=login(client, doctor)).json()
    assert me["role"] == "doctor" and me["display_id"] == "D-1001" and me["patient_id"] is None


def test_wrong_password_and_unknown_email_give_the_same_error(client, db):
    doctor = make_doctor(db)
    wrong = client.post(f"{API}/auth/login", json={"email": doctor.user.email, "password": "nope"})
    unknown = client.post(f"{API}/auth/login", json={"email": "nobody@example.test", "password": PASSWORD})
    assert wrong.status_code == unknown.status_code == 401
    assert wrong.json() == unknown.json()
    assert wrong.json()["error"]["code"] == "INVALID_CREDENTIALS"


def test_login_attempts_are_limited(client, db):
    doctor = make_doctor(db)
    for _ in range(5):
        client.post(f"{API}/auth/login", json={"email": doctor.user.email, "password": "nope"})
    blocked = client.post(f"{API}/auth/login", json={"email": doctor.user.email, "password": PASSWORD})
    assert blocked.status_code == 429


def test_there_is_no_registration_endpoint(client):
    for path in ("/auth/register", "/auth/signup", "/users"):
        assert client.post(f"{API}{path}", json={}).status_code in (404, 405)


def test_requests_without_a_valid_token_are_rejected(client, db):
    doctor = make_doctor(db)
    assert client.get(f"{API}/me").status_code == 401
    assert client.get(f"{API}/me", headers={"Authorization": "Bearer not-a-token"}).status_code == 401

    expired = create_access_token(doctor.user_id, "doctor", now=datetime.now(timezone.utc) - timedelta(hours=1))
    response = client.get(f"{API}/me", headers={"Authorization": f"Bearer {expired}"})
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "UNAUTHENTICATED"


def test_refresh_rotates_and_a_reused_refresh_token_ends_the_session(client, db):
    doctor = make_doctor(db)
    first = client.post(f"{API}/auth/login", json={"email": doctor.user.email, "password": PASSWORD}).json()

    second = client.post(f"{API}/auth/refresh", json={"refresh_token": first["refresh_token"]})
    assert second.status_code == 200
    second = second.json()
    assert second["refresh_token"] != first["refresh_token"]
    assert client.get(f"{API}/me", headers={"Authorization": f"Bearer {second['access_token']}"}).status_code == 200

    # The first refresh token was already used: presenting it again is treated as theft.
    assert client.post(f"{API}/auth/refresh", json={"refresh_token": first["refresh_token"]}).status_code == 401
    # ...and the newer token from the same login no longer works either.
    assert client.post(f"{API}/auth/refresh", json={"refresh_token": second["refresh_token"]}).status_code == 401


def test_logout_revokes_the_refresh_token(client, db):
    doctor = make_doctor(db)
    tokens = client.post(f"{API}/auth/login", json={"email": doctor.user.email, "password": PASSWORD}).json()
    assert client.post(f"{API}/auth/logout", json={"refresh_token": tokens["refresh_token"]}).status_code == 204
    assert client.post(f"{API}/auth/refresh", json={"refresh_token": tokens["refresh_token"]}).status_code == 401
    # Logging out twice, or with an unknown token, is harmless.
    assert client.post(f"{API}/auth/logout", json={"refresh_token": "unknown"}).status_code == 204


def test_inactive_accounts_cannot_sign_in_or_use_old_tokens(client, db):
    doctor = make_doctor(db)
    headers = login(client, doctor)
    doctor.user.is_active = False
    db.commit()
    assert client.get(f"{API}/me", headers=headers).status_code == 401
    assert client.post(f"{API}/auth/login", json={"email": doctor.user.email, "password": PASSWORD}).status_code == 401


def test_roles_are_enforced(client, world):
    # Doctor-only routes refuse patients, and the reverse.
    assert client.get(f"{API}/patients", headers=world.h_patient_1).status_code == 403
    assert client.get(f"{API}/doctor/review-queue", headers=world.h_patient_1).status_code == 403
    assert client.get(f"{API}/doctor/dashboard", headers=world.h_patient_1).status_code == 403
    assert client.get(f"{API}/messages/threads", headers=world.h_patient_1).status_code == 403
    assert client.get(f"{API}/patient/dashboard", headers=world.h_doctor_a).status_code == 403
    assert client.get(f"{API}/scans/mine", headers=world.h_doctor_a).status_code == 403


def test_profile_lists_ids(client, world):
    profile = client.get(f"{API}/me/profile", headers=world.h_patient_1).json()
    labels = {f["label"]: f["value"] for f in profile["health"]}
    assert labels["Patient ID"] == world.patient_1.display_id
    assert labels["Assigned doctor"] == "Dr. Alpha"
