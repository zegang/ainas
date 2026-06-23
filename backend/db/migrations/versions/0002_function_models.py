"""Add function_models table to record which AI model is selected per functionality.

Revision ID: 0002_function_models
Revises: 0001_initial
Create Date: 2026-06-23
"""
from alembic import op
import sqlalchemy as sa

revision = "0002_function_models"
down_revision = "0001_initial"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "function_models",
        sa.Column("id", sa.Integer(), primary_key=True, index=True, nullable=False),
        sa.Column("functionality", sa.String(), unique=True, index=True, nullable=False),
        sa.Column("model_name", sa.String(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=True),
        sa.Column("updated_at", sa.DateTime(), nullable=True),
    )


def downgrade() -> None:
    op.drop_table("function_models")
