"""Initial schema — creates files and tags tables with full metadata columns.

Revision ID: 0001_initial
Revises: (none)
Create Date: 2026-06-21
"""
from alembic import op
import sqlalchemy as sa

revision = "0001_initial"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Create 'files' table with all columns (including the metadata columns
    # added in the second session: size, created_at, updated_at).
    op.create_table(
        "files",
        sa.Column("id", sa.Integer(), primary_key=True, index=True, nullable=False),
        sa.Column("path", sa.String(), unique=True, index=True, nullable=False),
        sa.Column("size", sa.BigInteger(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=True),
        sa.Column("updated_at", sa.DateTime(), nullable=True),
    )

    # Create 'tags' table
    op.create_table(
        "tags",
        sa.Column("id", sa.Integer(), primary_key=True, index=True, nullable=False),
        sa.Column("name", sa.String(), index=True, nullable=True),
        sa.Column("file_id", sa.Integer(), sa.ForeignKey("files.id"), nullable=True),
    )


def downgrade() -> None:
    op.drop_table("tags")
    op.drop_table("files")
