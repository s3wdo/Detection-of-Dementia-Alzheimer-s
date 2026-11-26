"""Creates FICTIONAL development accounts. Not real people or records.

    docker compose exec api python -m app.db.seed

Every account gets the password from SEED_PASSWORD. Safe to run more than once.
No scans or results are seeded: analyses only come from real uploads.
"""
import sys
from datetime import date, datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.security import hash_password
from app.db.models import Admin, Appointment, AppointmentStatus, Doctor, Patient, Role, Sex, User

ADMIN = ("A-1001", "Demo Admin", "admin@neurosense.test")

DOCTORS = [
    # display_id, name, email, specialty
    ("D-1001", "Dr. Ahmed Khan", "ahmed.khan@neurosense.test", "Neurologist"),
    ("D-1002", "Dr. Layla Nasser", "layla.nasser@neurosense.test", "Neurologist"),
]

PATIENTS = [
    # display_id, name, date of birth, sex, emergency contact, doctor
    ("P-1024", "Sarah Johnson", date(1958, 3, 12), Sex.female, "Daniel Johnson (son)", "D-1001"),
    ("P-1031", "Robert Smith", date(1951, 7, 4), Sex.male, "Mary Smith (wife)", "D-1001"),
    ("P-1047", "Emily Davis", date(1960, 11, 23), Sex.female, "Tom Davis (husband)", "D-1001"),
    ("P-1052", "Michael Chen", date(1955, 1, 30), Sex.male, "Grace Chen (daughter)", "D-1001"),
    ("P-1063", "Aisha Rahman", date(1949, 9, 8), Sex.female, "Yusuf Rahman (son)", "D-1001"),
    ("P-1071", "Omar Haddad", date(1947, 5, 17), Sex.male, "Layla Haddad (wife)", "D-1001"),
    ("P-1088", "Lina Saleh", date(1962, 2, 2), Sex.female, "Karim Saleh (brother)", "D-1001"),
    ("P-1093", "James Carter", date(1953, 12, 19), Sex.male, "Anna Carter (wife)", "D-1001"),
    ("P-2001", "Noah Fischer", date(1956, 6, 21), Sex.male, "Eva Fischer (wife)", "D-1002"),
]


def _email(name: str) -> str:
    return name.lower().replace("dr. ", "").replace(" ", ".") + "@neurosense.test"


def seed(db: Session, password: str) -> int:
    """Returns how many accounts were created."""
    created = 0
    password_hash = hash_password(password)
    doctors: dict[str, Doctor] = {}

    admin_id, admin_name, admin_email = ADMIN
    if db.scalar(select(Admin).where(Admin.display_id == admin_id)) is None:
        user = User(email=admin_email, password_hash=password_hash, role=Role.admin, full_name=admin_name)
        db.add(user)
        db.flush()
        db.add(Admin(user_id=user.id, display_id=admin_id))
        created += 1

    for display_id, name, email, specialty in DOCTORS:
        doctor = db.scalar(select(Doctor).where(Doctor.display_id == display_id))
        if doctor is None:
            user = User(email=email, password_hash=password_hash, role=Role.doctor, full_name=name)
            doctor = Doctor(
                user=user,
                display_id=display_id,
                specialty=specialty,
                license_no=f"DEMO-{display_id[2:]}",
                clinic="NeuroSense Demo Clinic",
                phone="+000 555 0100",
            )
            db.add_all([user, doctor])
            created += 1
        doctors[display_id] = doctor
    db.flush()

    for display_id, name, dob, sex, emergency, doctor_display_id in PATIENTS:
        if db.scalar(select(Patient).where(Patient.display_id == display_id)) is not None:
            continue
        user = User(email=_email(name), password_hash=password_hash, role=Role.patient, full_name=name)
        patient = Patient(
            user=user,
            display_id=display_id,
            doctor_id=doctors[doctor_display_id].id,
            date_of_birth=dob,
            sex=sex,
            phone=f"+000 555 {display_id[2:]}",
            emergency_contact=emergency,
        )
        db.add_all([user, patient])
        created += 1
        if display_id == "P-1024":
            db.flush()
            start = (datetime.now(timezone.utc) + timedelta(days=2)).replace(hour=10, minute=0, second=0, microsecond=0)
            db.add(
                Appointment(
                    patient_id=patient.id,
                    doctor_id=patient.doctor_id,
                    starts_at=start,
                    reason="Neurology consultation",
                    location="Room 3B",
                    status=AppointmentStatus.confirmed,
                )
            )
    db.commit()
    return created


if __name__ == "__main__":
    settings = get_settings()
    if settings.app_env == "production":
        sys.exit("Refusing to seed demo accounts when APP_ENV=production.")
    if not settings.seed_password or settings.seed_password == "CHANGE-ME":
        sys.exit("Set SEED_PASSWORD in backend/.env first.")
    from app.db.session import SessionLocal

    with SessionLocal() as session:
        count = seed(session, settings.seed_password)
    print(f"Seed complete: {count} new fictional accounts.")
    print("Admin:    " + ADMIN[2])
    print("Doctors:  " + ", ".join(email for _, _, email, _ in DOCTORS))
    print("Patients: " + ", ".join(_email(name) for _, name, *_ in PATIENTS))
