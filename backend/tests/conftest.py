"""Test setup: a separate PostgreSQL database (<name>_test), created by the real
migrations and emptied before every test. The analysis worker thread is off;
tests run jobs explicitly with `run_jobs()` so they are deterministic."""
import base64
import io
import os
import uuid
from datetime import date

import pytest
from PIL import Image
from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url

_base_url = make_url(os.environ["DATABASE_URL"])
_test_url = _base_url.set(database=f"{_base_url.database}_test")
os.environ["DATABASE_URL"] = _test_url.render_as_string(hide_password=False)
os.environ["START_WORKER"] = "false"
# Tests never load the real brain detector; full-scan tests pass a fake one.
os.environ["BRAIN_FILTER_PATH"] = "/nonexistent/brain_detector.keras"
os.environ.setdefault("JWT_SECRET", "test-secret-test-secret-test-secret-test")
os.environ["LOGIN_ATTEMPTS_PER_MINUTE"] = "5"

from alembic import command  # noqa: E402
from alembic.config import Config  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.core.config import get_settings  # noqa: E402
from app.core.security import hash_password  # noqa: E402
from app.db import models as m  # noqa: E402
from app.db.session import SessionLocal, engine  # noqa: E402
from app.main import create_app  # noqa: E402
from app.ml.predictor import StubPredictor  # noqa: E402
from app.routers.auth import reset_login_attempts  # noqa: E402
from app.services.analysis_worker import process_one  # noqa: E402

PASSWORD = "correct horse battery"
_PASSWORD_HASH = hash_password(PASSWORD)


@pytest.fixture(scope="session", autouse=True)
def _database():
    admin = create_engine(_base_url.set(database="postgres"), isolation_level="AUTOCOMMIT")
    with admin.connect() as conn:
        conn.execute(text(f'DROP DATABASE IF EXISTS "{_test_url.database}" WITH (FORCE)'))
        conn.execute(text(f'CREATE DATABASE "{_test_url.database}"'))
    admin.dispose()
    # Build the schema with the migrations, so they are tested too.
    config = Config("alembic.ini")
    command.upgrade(config, "head")
    yield
    engine.dispose()


@pytest.fixture(autouse=True)
def _clean():
    tables = ", ".join(f'"{t.name}"' for t in m.Base.metadata.sorted_tables)
    with engine.begin() as conn:
        conn.execute(text(f"TRUNCATE {tables} RESTART IDENTITY CASCADE"))
    reset_login_attempts()
    yield


@pytest.fixture
def db():
    with SessionLocal() as session:
        yield session


@pytest.fixture
def predictor():
    return StubPredictor()


@pytest.fixture
def client(predictor):
    with TestClient(create_app(predictor=predictor, start_worker=False)) as c:
        yield c


@pytest.fixture
def run_jobs(db, predictor):
    """Runs every queued analysis, as the worker thread would."""

    def _run(with_predictor=None) -> int:
        count = 0
        while process_one(db, with_predictor or predictor, get_settings()):
            count += 1
        db.expire_all()
        return count

    return _run


# ---------------------------------------------------------------- data builders

def make_doctor(db, name="Dr. Test One", display_id=None) -> m.Doctor:
    display_id = display_id or f"D-{uuid.uuid4().hex[:6]}"
    user = m.User(
        email=f"{display_id.lower()}@example.test", password_hash=_PASSWORD_HASH, role=m.Role.doctor, full_name=name
    )
    doctor = m.Doctor(user=user, display_id=display_id, specialty="Neurologist")
    db.add_all([user, doctor])
    db.commit()
    return doctor


def make_patient(db, doctor: m.Doctor, name="Pat Example", display_id=None) -> m.Patient:
    display_id = display_id or f"P-{uuid.uuid4().hex[:6]}"
    user = m.User(
        email=f"{display_id.lower()}@example.test", password_hash=_PASSWORD_HASH, role=m.Role.patient, full_name=name
    )
    patient = m.Patient(
        user=user,
        display_id=display_id,
        doctor_id=doctor.id,
        date_of_birth=date(1955, 5, 5),
        sex=m.Sex.female,
        phone="000",
        emergency_contact="Someone (friend)",
    )
    db.add_all([user, patient])
    db.commit()
    return patient


def login(client, person) -> dict:
    """Authorization header for a doctor or patient row."""
    response = client.post("/api/v1/auth/login", json={"email": person.user.email, "password": PASSWORD})
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def image_b64(size=(128, 128), shade=90, fmt="PNG") -> str:
    """A plain grey test image (not a scan)."""
    out = io.BytesIO()
    Image.new("L", size, shade).save(out, format=fmt)
    return base64.b64encode(out.getvalue()).decode()


def upload(client, headers, *, shade=90, patient_id=None, size=(128, 128)) -> dict:
    body = {"image_base64": image_b64(size=size, shade=shade), "filename": "slice.png"}
    if patient_id is not None:
        body["patient_id"] = str(patient_id)
    response = client.post("/api/v1/scans", json=body, headers=headers)
    assert response.status_code == 202, response.text
    return response.json()


@pytest.fixture
def world(db, client):
    """Two doctors; doctor A has patients 1 and 2, doctor B has patient 3."""

    class World:
        pass

    w = World()
    w.doctor_a = make_doctor(db, "Dr. Alpha")
    w.doctor_b = make_doctor(db, "Dr. Beta")
    w.patient_1 = make_patient(db, w.doctor_a, "Pat One")
    w.patient_2 = make_patient(db, w.doctor_a, "Pat Two")
    w.patient_3 = make_patient(db, w.doctor_b, "Pat Three")
    w.h_doctor_a = login(client, w.doctor_a)
    w.h_doctor_b = login(client, w.doctor_b)
    w.h_patient_1 = login(client, w.patient_1)
    w.h_patient_2 = login(client, w.patient_2)
    w.h_patient_3 = login(client, w.patient_3)
    return w
