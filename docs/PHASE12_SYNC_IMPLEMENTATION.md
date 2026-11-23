# Phase 12 sync implementation

SQLite v4 creates an outbox and local-to-remote diary ID mapping. The Flutter guest route opens the existing filename and does not enqueue. An explicitly opened account diary uses a distinct UUID-named file. Diary create, edit and delete in that file mutate the entry and write its operation in one transaction. Unacknowledged operations survive restarts. Stable operation IDs, bounded batches, per-record ordering and retry backoff are implemented. An account switch or authorization error pauses the queue. Conflicts preserve local mutation and any returned remote version.

The HTTPS transport has request timeouts and disables redirects. It is not wired to the running Flutter app. Account selection, consented guest import, background scheduling, changes application, tracking-module enqueue, and interactive resolution still need integration. Do not enable the transport for ordinary users until those flows and provider sessions pass device tests.
