"""model input image and Grad-CAM map per analysis

Revision ID: 0004
Revises: 0003
"""
from alembic import op
import sqlalchemy as sa

revision = '0004'
down_revision = '0003'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('analyses', sa.Column('model_input', sa.LargeBinary(), nullable=True))
    op.add_column('analyses', sa.Column('heatmap', sa.LargeBinary(), nullable=True))
    op.add_column('analyses', sa.Column('explanation_method', sa.String(length=24), nullable=True))


def downgrade() -> None:
    op.drop_column('analyses', 'explanation_method')
    op.drop_column('analyses', 'heatmap')
    op.drop_column('analyses', 'model_input')
