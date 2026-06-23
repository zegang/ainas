"""Add all_model_files column to ai_models table.

Revision ID: 0006_add_all_model_files
Revises: 0005_add_download_progress
Create Date: 2026-06-24
"""
from alembic import op
import sqlalchemy as sa

revision = "0006_add_all_model_files"
down_revision = "0005_add_download_progress"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("ai_models", sa.Column("all_model_files", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("ai_models", "all_model_files")
