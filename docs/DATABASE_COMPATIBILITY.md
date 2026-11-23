# Database compatibility

Consumer SQLite stays at v8. Existing entries, profile settings, saved meals, favorites, guest-transfer ledger, account projections, tombstones and sync cursors are preserved.

Backend Alembic 0003 adds `linked_identity`, `account_registration`, `role_assignment`, `audit_event` and `catalog_food`. It does not rewrite `owned_record` or `sync_receipt`, change user UUIDs, or move nutrition/tracker history. The identity mapping is backfilled from existing issuer/subject pairs. Historical registration dates stay unknown; only new account creation records a timestamp.

Do not apply to production until a pre-migration backup has been restored into a separate database and tested. Run `python -m alembic upgrade head` with the migration owner, then grant the API only its necessary table privileges. The sync runtime needs new identity/registration permissions. Administration additionally needs catalog/audit/role reads and bounded writes; role changes remain an operator responsibility.

Revision 0003 intentionally rejects automated downgrade: dropping aliases after linking can strand user accounts. Rollback means restoring a verified pre-migration backup and compatible application release, with a maintenance window and a decision about writes made after backup. Never discard linked identities to satisfy a downgrade smoke test.

Tests cover legacy account preservation, alias backfill, no invented registration dates/no seeded roles, repeat upgrade and existing sync behavior. PostgreSQL backup/restore smoke includes the new tables; legacy 0002 downgrade is checked before upgrading to 0003. Actual production data has not been migrated.
