"""Add download_progress column to ai_models table.

Revision ID: 0005_add_download_progress
Revises: 0004_add_feature_metadata
Create Date: 2026-06-23
"""
from alembic import op
import sqlalchemy as sa

revision = "0005_add_download_progress"
down_revision = "0004_add_feature_metadata"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("ai_models", sa.Column("download_progress", sa.Integer(), nullable=True))


def downgrade() -> None:
    op.drop_column("ai_models", "download_progress")
