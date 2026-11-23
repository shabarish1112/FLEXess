# Synchronization architecture

Proposed only. Keep SQLite authoritative for immediate UI. Commit the local mutation and its outbox operation in one transaction. Each operation carries a stable operation UUID, record UUID, base revision, action and immutable snapshot. Store ownership scope with the queue. After authentication, send oldest operations for each record in order. Track pending, acknowledged, conflict and permanent rejection explicitly.

On PostgreSQL, validate ownership before any lookup result or mutation is exposed. Use one transaction to compare revisions, write the owned record or tombstone, and persist the operation receipt. Enforce unique (owner_id, operation_id). Replayed requests must return the stored result if the payload matches. Retry transient failures with backoff and stable keys. Stop on 401 and resume only with the same identity. Enable no ordinary-user sync before two-account and two-device integration tests pass.
