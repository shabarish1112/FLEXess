from pathlib import Path
from uuid import uuid4

from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, text


def test_additive_identity_migration_preserves_legacy_account(tmp_path, monkeypatch):
    url = f"sqlite:///{tmp_path / 'migration.sqlite'}"
    monkeypatch.setenv("DATABASE_URL", url)
    config = Config(str(Path(__file__).parents[1] / "alembic.ini"))
    config.set_main_option("script_location", str(Path(__file__).parents[1] / "migrations"))
    command.upgrade(config, "0002")
    engine = create_engine(url)
    account = str(uuid4())
    with engine.begin() as db:
        db.execute(text("INSERT INTO app_user (id, identity_subject, identity_issuer, active) VALUES (:id, 'legacy', 'https://legacy.invalid/', true)"), {"id": account})
    command.upgrade(config, "head")
    command.upgrade(config, "head")
    with engine.connect() as db:
        assert db.execute(text("SELECT owner_id FROM linked_identity WHERE subject='legacy'")).scalar_one() == account
        assert db.execute(text("SELECT id FROM app_user")).scalar_one() == account
        assert db.execute(text("SELECT count(*) FROM account_registration")).scalar_one() == 0
        assert db.execute(text("SELECT count(*) FROM role_assignment")).scalar_one() == 0
    engine.dispose()
