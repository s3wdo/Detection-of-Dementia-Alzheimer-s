"""Admins create every account and assign patients to doctors; nobody else can."""
from app.db import models as m
from tests.conftest import PASSWORD, _PASSWORD_HASH, login, make_doctor, make_patient, upload

NEW_PASSWORD = "a long demo password"


def make_admin(db) -> m.Admin:
    user = m.User(email="admin@example.test", password_hash=_PASSWORD_HASH, role=m.Role.admin, full_name="Ada Admin")
    db.add(user)
    db.flush()
    admin = m.Admin(user_id=user.id, display_id="A-1001")
    db.add(admin)
    db.commit()
    admin.user = user  # login() reads person.user.email
    return admin


def _sign_in(client, name, password=PASSWORD):
    return client.post("/api/v1/auth/login", json={"email": name, "password": password})


def _post(client, headers, **body):
    return client.post("/api/v1/admin/users", headers=headers, json=body)


def test_admin_creates_a_doctor_and_a_patient_who_can_then_work_together(client, db, run_jobs):
    headers = login(client, make_admin(db))

    doctor = _post(client, headers, role="doctor", full_name="Dr. New Doctor", email="New.Doctor@example.test",
                   password=NEW_PASSWORD, specialty="Neurologist")
    assert doctor.status_code == 201, doctor.text
    assert doctor.json()["display_id"] == "D-1001" and doctor.json()["patient_count"] == 0

    patient = _post(client, headers, role="patient", full_name="New Patient", email="new.patient@example.test",
                    password=NEW_PASSWORD, doctor_display_id="d-1001", date_of_birth="1950-02-03", sex="male")
    assert patient.status_code == 201, patient.text
    assert patient.json()["display_id"] == "P-1001"
    assert patient.json()["doctor_display_id"] == "D-1001"

    # Sign-in works with the email or with the ID.
    as_patient = _sign_in(client, "P-1001", NEW_PASSWORD)
    assert as_patient.status_code == 200 and as_patient.json()["user"]["display_id"] == "P-1001"
    as_doctor = _sign_in(client, "new.doctor@example.test", NEW_PASSWORD)
    assert as_doctor.status_code == 200

    # The new patient's scan reaches the new doctor's review queue.
    upload(client, {"Authorization": f"Bearer {as_patient.json()['access_token']}"})
    run_jobs()
    queue = client.get(
        "/api/v1/doctor/review-queue", headers={"Authorization": f"Bearer {as_doctor.json()['access_token']}"}
    ).json()
    assert [item["patient_display_id"] for item in queue] == ["P-1001"]

    listed = client.get("/api/v1/admin/users", headers=headers).json()
    assert {u["display_id"] for u in listed} == {"A-1001", "D-1001", "P-1001"}
    assert next(u for u in listed if u["role"] == "doctor")["patient_count"] == 1


def test_admin_can_create_another_admin_and_ids_count_up(client, db):
    headers = login(client, make_admin(db))
    make_doctor(db, display_id="D-1007")
    common = {"full_name": "Second Person", "password": NEW_PASSWORD}
    assert _post(client, headers, role="admin", email="a2@example.test", **common).json()["display_id"] == "A-1002"
    assert _post(client, headers, role="doctor", email="d2@example.test", **common).json()["display_id"] == "D-1008"
    me = client.get("/api/v1/me", headers=headers).json()
    assert me["role"] == "admin" and me["display_id"] == "A-1001"
    assert client.get("/api/v1/me/profile", headers=headers).status_code == 200


def test_invalid_accounts_are_refused(client, db):
    headers = login(client, make_admin(db))
    doctor = make_doctor(db)
    base = {"role": "patient", "full_name": "Some Patient", "email": "p@example.test", "password": NEW_PASSWORD,
            "doctor_display_id": doctor.display_id, "date_of_birth": "1950-02-03", "sex": "female"}

    def post(**changes):
        return client.post("/api/v1/admin/users", headers=headers, json={**base, **changes})

    assert post(doctor_display_id="D-9999").status_code == 422  # unknown doctor
    assert post(doctor_display_id=None).status_code == 422  # a patient always has a doctor
    assert post(date_of_birth=None).status_code == 422
    assert post(password="short").status_code == 422
    assert post(email="not-an-email").status_code == 422
    assert post(role="superuser").status_code == 422
    assert post(email=doctor.user.email).status_code == 409  # email already used
    # A refused request leaves no half-made account behind.
    assert db.query(m.User).filter_by(email="p@example.test").count() == 0
    assert post().status_code == 201


def test_only_admins_reach_the_admin_routes(client, db):
    doctor = make_doctor(db)
    patient = make_patient(db, doctor)
    for person in (doctor, patient):
        headers = login(client, person)
        assert client.get("/api/v1/admin/users", headers=headers).status_code == 403
        assert _post(client, headers, role="doctor", full_name="Dr. X Y", email="x@example.test",
                     password=NEW_PASSWORD).status_code == 403
        assert client.patch(f"/api/v1/admin/users/{patient.user_id}/doctor", headers=headers,
                            json={"doctor_display_id": doctor.display_id}).status_code == 403
    assert client.get("/api/v1/admin/users").status_code == 401


def test_admin_has_no_access_to_clinical_data(client, db, run_jobs):
    doctor = make_doctor(db)
    patient = make_patient(db, doctor)
    analysis_id = upload(client, login(client, patient))["analysis_id"]
    run_jobs()
    headers = login(client, make_admin(db))
    for path in ("/patients", f"/patients/{patient.id}", f"/patients/{patient.id}/analyses", f"/analyses/{analysis_id}",
                 f"/analyses/{analysis_id}/image", "/doctor/review-queue", "/scans/mine",
                 f"/patients/{patient.id}/messages", f"/patients/{patient.id}/timeline", "/notifications"):
        status = client.get(f"/api/v1{path}", headers=headers).status_code
        assert status in (403, 404) or path == "/notifications", path


def test_reassigning_a_patient_moves_them_to_the_other_doctor(client, db):
    first, second = make_doctor(db, display_id="D-1001"), make_doctor(db, name="Dr. Test Two", display_id="D-1002")
    patient = make_patient(db, first)
    headers = login(client, make_admin(db))
    moved = client.patch(f"/api/v1/admin/users/{patient.user_id}/doctor", headers=headers,
                         json={"doctor_display_id": "D-1002"})
    assert moved.status_code == 200 and moved.json()["doctor_display_id"] == "D-1002"
    assert client.get("/api/v1/patients", headers=login(client, first)).json() == []
    assert len(client.get("/api/v1/patients", headers=login(client, second)).json()) == 1
    assert client.patch(f"/api/v1/admin/users/{first.user_id}/doctor", headers=headers,
                        json={"doctor_display_id": "D-1002"}).status_code == 404  # not a patient
