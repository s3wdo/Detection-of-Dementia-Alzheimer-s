"""Notifications and audit events. Both are written in the caller's transaction,
so they exist exactly when the change they describe was committed."""
import uuid

from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.db.models import AuditEvent, Notification, NotificationType


def notify(
    db: Session,
    *,
    user_id: uuid.UUID,
    type: NotificationType,
    title: str,
    body: str,
    dedupe_key: str,
    entity_type: str | None = None,
    entity_id: uuid.UUID | None = None,
    patient_id: uuid.UUID | None = None,
) -> None:
    """Creates a notification once per `dedupe_key`; a retry of the same event adds nothing."""
    db.execute(
        insert(Notification)
        .values(
            id=uuid.uuid4(),
            user_id=user_id,
            type=type,
            title=title,
            body=body,
            entity_type=entity_type,
            entity_id=entity_id,
            patient_id=patient_id,
            dedupe_key=dedupe_key,
        )
        .on_conflict_do_nothing(index_elements=["dedupe_key"])
    )


def audit(db: Session, *, actor_id: uuid.UUID | None, action: str, entity_type: str, entity_id: uuid.UUID) -> None:
    db.add(AuditEvent(actor_id=actor_id, action=action, entity_type=entity_type, entity_id=entity_id))
