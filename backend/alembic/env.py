"""Alembic environment: migrations run against DATABASE_URL."""
from logging.config import fileConfig

from alembic import context
from sqlalchemy import create_engine

from app.core.config import get_settings
from app.db.models import Base

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name, disable_existing_loggers=False)

target_metadata = Base.metadata


def run_migrations() -> None:
    # Tests pass their own URL with `-x url=...` or config.attributes.
    url = config.attributes.get("url") or get_settings().database_url
    engine = create_engine(url)
    with engine.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata, compare_type=True)
        with context.begin_transaction():
            context.run_migrations()
    engine.dispose()


run_migrations()
