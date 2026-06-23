"""Add feature_title and feature_description columns to function_models table.

Revision ID: 0004_add_feature_metadata
Revises: 0003_add_is_local
Create Date: 2026-06-23
"""
from alembic import op
import sqlalchemy as sa

revision = "0004_add_feature_metadata"
down_revision = "0003_add_is_local"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("function_models", sa.Column("feature_title", sa.String(), nullable=True))
    op.add_column("function_models", sa.Column("feature_description", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("function_models", "feature_description")
    op.drop_column("function_models", "feature_title")
