# Phase 20 CI verification

The workflow defines independent backend, mobile and secret checks, plus a seven-day debug APK artifact. The backend runs migration, ownership and database recovery checks on a disposable cluster. Production credentials are unnecessary.

Local evidence is tracked in TEST_RESULTS.md. Hosted GitHub Actions execution, secret and dependency scan results, APK artifact publication and Docker build need runner evidence.
