# Phase 20 database recovery

The disposable PostgreSQL 18.4 drill upgraded Alembic to 0002, ran the signed identity and cloud API suite, made a custom-format pg_dump and restored it to a separate database. The database snapshots matched for all 1 migration, 13 user, 10 owned record and 13 receipt rows. Downgrade and re-upgrade passed. The temporary cluster and backup are removed by the script.

Reproduce with python scripts/phase12-postgres-smoke.py followed by the PostgreSQL bin directory. The drill covers logical data recovery. Before staging acceptance, test scheduled encrypted backups and point-in-time recovery with the managed provider and agree on retention, recovery objectives, and deletion handling.
