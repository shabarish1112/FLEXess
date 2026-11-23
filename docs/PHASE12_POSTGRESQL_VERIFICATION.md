# Phase 12 PostgreSQL verification

The smoke used PostgreSQL 18.4, a fresh UTF-8 cluster listening on loopback, SCRAM credentials and a disposable flex_tests database. The application role could access only the granted tables and could not create in the schema.

Alembic upgraded to 0001, inserted a synthetic legacy row and upgraded to 0002 head. The legacy row survived. Nine cloud API tests passed with the restricted role on real PostgreSQL, including concurrent replay and competing edits. Downgrade to 0001 removed the new tables and preserved the legacy row. Re-upgrade passed, and the cluster stopped successfully.

An earlier attempt hung despite a ready database because PostgreSQL inherited process pipes. Redirecting command output to files resolved the timeout. The runner creates its own database and overrides DATABASE_URL for migrations. Reproduce from the repository root with project Python dependencies available.

```powershell
python scripts/phase12-postgres-smoke.py C:/src/PostgreSQL/18/bin
```
