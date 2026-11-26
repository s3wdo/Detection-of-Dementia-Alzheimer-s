"""full MRI scans (.nii) uploaded by doctors

Revision ID: 0005
Revises: 0004
"""
from alembic import op
import sqlalchemy as sa

revision = '0005'
down_revision = '0004'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('scans', sa.Column('kind', sa.String(length=8), nullable=False, server_default='slice'))
    op.add_column('scans', sa.Column('volume', sa.LargeBinary(), nullable=True))
    for name in ('slices_total', 'slices_kept', 'slices_used', 'slice_index'):
        op.add_column('analyses', sa.Column(name, sa.Integer(), nullable=True))


def downgrade() -> None:
    for name in ('slice_index', 'slices_used', 'slices_kept', 'slices_total'):
        op.drop_column('analyses', name)
    op.drop_column('scans', 'volume')
    op.drop_column('scans', 'kind')
