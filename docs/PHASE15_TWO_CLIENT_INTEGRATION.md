# Phase 15 two-client integration

Opt in with FLEX_RUN_FLUTTER_SYNC=1 and run scripts/phase12-postgres-smoke.py from the repository root with Python dependencies available. The runner uses a disposable PostgreSQL cluster, loopback Uvicorn over TLS, a per-run RSA identity verifier, two synthetic identities and independent SQLite files. The Dart trust store trusts only the generated certificate for this test. The test simulates a lost client acknowledgement by intentionally discarding an accepted response.
Verified a lost acknowledgement replay, accepted edits in both directions, cursor recovery, cross-account isolation, preserved conflicts, clean deletion with Riverpod refresh, and unchanged guest data.
