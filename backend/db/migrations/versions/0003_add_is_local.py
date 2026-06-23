"""Create ai_models table with all current columns.

Revision ID: 0003_add_is_local
Revises: 0002_function_models
Create Date: 2026-06-23
"""
from alembic import op
import sqlalchemy as sa

revision = "0003_add_is_local"
down_revision = "0002_function_models"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "ai_models",
        sa.Column("id", sa.Integer(), primary_key=True, index=True, nullable=False),
        sa.Column("name", sa.String(), unique=True, index=True, nullable=False),
        sa.Column("provider", sa.String(), nullable=False),
        sa.Column("model_type", sa.String(), nullable=False, default="chat"),
        sa.Column("api_base", sa.String(), nullable=True),
        sa.Column("config", sa.Text(), nullable=True),
        sa.Column("is_active", sa.Boolean(), default=False),
        sa.Column("is_local", sa.Boolean(), default=False),
        sa.Column("is_ready", sa.Boolean(), default=False),
        sa.Column("download_start_at", sa.DateTime(), nullable=True),
        sa.Column("downloaded_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=True),
        sa.Column("updated_at", sa.DateTime(), nullable=True),
    )


def downgrade() -> None:
    op.drop_table("ai_models")
