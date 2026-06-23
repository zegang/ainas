"""Add total_size column to ai_models table.

Revision ID: 0007_add_total_size
Revises: 0006_add_all_model_files
Create Date: 2026-06-24
"""
from alembic import op
import sqlalchemy as sa

revision = "0007_add_total_size"
down_revision = "0006_add_all_model_files"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("ai_models", sa.Column("total_size", sa.Integer(), nullable=True))


def downgrade() -> None:
    op.drop_column("ai_models", "total_size")
