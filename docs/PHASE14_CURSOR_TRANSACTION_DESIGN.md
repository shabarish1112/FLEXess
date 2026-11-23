# Phase 14 cursor transaction

Remote snapshots, diary rows, mappings and cursor updates share one SQLite transaction. Invalid records and sequence gaps roll back the page. The v6 migration resets only the v5 account cursor so staged records can replay into the account diary.
