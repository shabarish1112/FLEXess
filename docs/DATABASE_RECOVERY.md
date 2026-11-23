# SQLite backup and recovery

Android keeps dev.independent.fitness_diary and fitness_diary.db. V3 adds tracking and dated targets within the versioned upgrade transaction. V1 still converges through the v2 snapshot backfill. Existing entries, drafts, catalog rows and old energy preference remain in place.

Before upgrading a development install with data, force-stop the app and back up the SQLite file and any present WAL/SHM companions together using the debug app identity or a device backup mechanism. Keep that bundle outside Git in private storage. Verify a copy on an isolated test install. Never capture databases of other apps. If restoration is necessary, stop the app first and restore the whole matching set to the original package, with the matching application version. Do not run the old binary directly against the new schema. A schema migration failure rolls back; a full installation rollback requires the matching backup.

No production device database was copied in this phase.
