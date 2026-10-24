"""Local account credentials and onboarding profile; existing guest data preserved."""
from alembic import op
from app.accounts.models import Account
revision = '003'
down_revision = '002'

def upgrade():
    Account.__table__.create(op.get_bind(), checkfirst=True)

def downgrade():
    Account.__table__.drop(op.get_bind())
