"""Add current_model_files column to ai_models table.

Revision ID: 0010_add_current_model_files
Revises: 0009_remove_download_progress
Create Date: 2026-06-24
"""
from alembic import op
import sqlalchemy as sa

revision = "0010_add_current_model_files"
down_revision = "0009_remove_download_progress"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("ai_models", sa.Column("current_model_files", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("ai_models", "current_model_files")
