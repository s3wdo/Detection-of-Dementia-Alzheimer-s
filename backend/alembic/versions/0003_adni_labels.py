"""model labels AD, LMCI, EMCI, CN

The connected model's classes are AD, LMCI, EMCI, CN (in that output order).
Results stored before this change carry the junior-project labels, which the
server had assigned to the same output units in alphabetical order. This
renames them unit by unit, so a stored model output keeps its meaning.

Revision ID: 0003
Revises: 0002
"""
from alembic import op

revision = '0003'
down_revision = '0002'
branch_labels = None
depends_on = None

# Old name of output unit i -> new name of output unit i.
_UNITS = {
    'MildDemented': 'AD',
    'ModerateDemented': 'LMCI',
    'NonDemented': 'EMCI',
    'VeryMildDemented': 'CN',
}


def _rename(mapping: dict[str, str]) -> None:
    for old, new in mapping.items():
        op.execute(f"UPDATE analyses SET predicted_label = '{new}' WHERE predicted_label = '{old}'")
        op.execute(f"UPDATE reviews SET final_label = '{new}' WHERE final_label = '{old}'")
        op.execute(
            f"UPDATE analyses SET probabilities = (probabilities - '{old}') || jsonb_build_object('{new}', probabilities -> '{old}') "
            f"WHERE probabilities ? '{old}'"
        )


def upgrade() -> None:
    _rename(_UNITS)


def downgrade() -> None:
    _rename({new: old for old, new in _UNITS.items()})
