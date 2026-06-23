"""Remove download_progress column from ai_models table.

Revision ID: 0009_remove_download_progress
Revises: 0008_add_current_total_size
Create Date: 2026-06-24
"""
from alembic import op
import sqlalchemy as sa

revision = "0009_remove_download_progress"
down_revision = "0008_add_current_total_size"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("ai_models") as batch_op:
        batch_op.drop_column("download_progress")


def downgrade() -> None:
    with op.batch_alter_table("ai_models") as batch_op:
        batch_op.add_column(sa.Column("download_progress", sa.Integer(), nullable=True))
