"""Initial schema with cascading foreign keys and owner indexes."""
from alembic import op
import sqlalchemy as sa
revision = '001'
down_revision = None


def upgrade():
    op.create_table('users', sa.Column('id', sa.String(128), primary_key=True))
    for name in ('saved_places', 'saved_routes'):
        op.create_table(name,
            sa.Column('id', sa.String(36), primary_key=True),
            sa.Column('user_id', sa.String(128), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
            sa.Column('data', sa.JSON, nullable=False))
        op.create_index(f'ix_{name}_user_id', name, ['user_id'])
    op.create_table('route_checks',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('user_id', sa.String(128), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('checked_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('status', sa.String(32), nullable=False))
    op.create_index('ix_route_checks_user_id', 'route_checks', ['user_id'])
    op.create_index('ix_checks_time', 'route_checks', ['checked_at'])
    op.create_table('user_settings',
        sa.Column('user_id', sa.String(128), sa.ForeignKey('users.id', ondelete='CASCADE'), primary_key=True),
        sa.Column('data', sa.JSON, nullable=False))


def downgrade():
    for name in ('user_settings', 'route_checks', 'saved_routes', 'saved_places', 'users'):
        op.drop_table(name)
