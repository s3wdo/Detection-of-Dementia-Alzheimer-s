"""Removes stored image bytes some days after the doctor's review.

The analysis result, the review and the audit trail stay. Running it twice
changes nothing the second time.

    python -m app.services.retention
"""
from datetime import datetime, timedelta, timezone

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.db.models import Analysis, Review, Scan


def purge_images(db: Session, retention_days: int, now: datetime | None = None) -> int:
    now = now or datetime.now(timezone.utc)
    cutoff = now - timedelta(days=retention_days)
    reviewed_before_cutoff = (
        select(Analysis.scan_id).join(Review, Review.analysis_id == Analysis.id).where(Review.reviewed_at <= cutoff)
    )
    result = db.execute(
        update(Scan)
        .where(Scan.image.is_not(None), Scan.id.in_(reviewed_before_cutoff))
        .values(image=None, volume=None, image_purged_at=now)
    )
    # The masked image and the Grad-CAM map are made from the scan, so they go with it.
    db.execute(
        update(Analysis)
        .where(Analysis.scan_id.in_(select(Scan.id).where(Scan.image.is_(None))))
        .where(Analysis.model_input.is_not(None) | Analysis.heatmap.is_not(None))
        .values(model_input=None, heatmap=None)
    )
    db.commit()
    return result.rowcount or 0


if __name__ == "__main__":
    from app.core.config import get_settings
    from app.db.session import SessionLocal

    with SessionLocal() as session:
        print(f"removed {purge_images(session, get_settings().image_retention_days)} stored images")
