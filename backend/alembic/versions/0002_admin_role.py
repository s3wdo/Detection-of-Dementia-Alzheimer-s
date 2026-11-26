"""admin role

Revision ID: 0002
Revises: 0001
"""
from alembic import op
import sqlalchemy as sa

revision = '0002'
down_revision = '0001'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'admins',
        sa.Column('id', sa.UUID(), nullable=False),
        sa.Column('user_id', sa.UUID(), nullable=False),
        sa.Column('display_id', sa.String(length=16), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('display_id'),
        sa.UniqueConstraint('user_id'),
    )
    op.drop_constraint('role', 'users', type_='check')
    op.create_check_constraint('role', 'users', "role IN ('doctor', 'patient', 'admin')")


def downgrade() -> None:
    op.drop_constraint('role', 'users', type_='check')
    op.create_check_constraint('role', 'users', "role IN ('doctor', 'patient')")
    op.drop_table('admins')
