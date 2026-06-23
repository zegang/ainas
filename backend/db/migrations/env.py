"""
Alembic environment configuration.
Reads the database URL from the application config and uses the SQLAlchemy
models' metadata for auto-generating migration scripts.
"""
import sys
import os
import logging

from sqlalchemy import engine_from_config, pool
from alembic import context

# Make backend package importable from alembic env
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from backend.db.database import Base, db_manager

# Alembic Config object — gives access to values in alembic.ini
config = context.config

# Wire up Alembic loggers to propagate to the root logger so they end up
# in the project log file (set up by core/logger.py::setup_logging).
# Without this, fileConfig(disable_existing_loggers=True) wipes the root
# logger's handlers and Alembic output only goes to stderr.
logging.getLogger("alembic").setLevel(logging.INFO)
logging.getLogger("alembic").propagate = True
logging.getLogger("sqlalchemy.engine").setLevel(logging.WARNING)
logging.getLogger("sqlalchemy.engine").propagate = True

# The metadata object that drives auto-generation
target_metadata = Base.metadata

# Override sqlalchemy.url from application config so there is a single source
# of truth — no need to duplicate the URL in alembic.ini
config.set_main_option("sqlalchemy.url", db_manager.url)


def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode (emit SQL to stdout, no live connection)."""
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        render_as_batch=True,   # Required for SQLite ALTER TABLE support
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run migrations in 'online' mode (connect to DB and apply changes)."""
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            render_as_batch=True,   # Required for SQLite ALTER TABLE support
        )
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
