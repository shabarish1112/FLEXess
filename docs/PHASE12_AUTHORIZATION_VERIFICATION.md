# Phase 12 authorization verification

The owner comes from validated token claims. Application request bodies cannot send an owner identifier. Record, list and change-feed reads use the authenticated owner in their queries. Mutations lock the owner row and look up records and receipts by owner plus ID. A different identity receives 404 for foreign record IDs and cannot enumerate another account's timeline.

The backend suite checks a distinct signed identity for each user, invalid, missing, expired and wrong-issuer or wrong-audience tokens, disabled accounts, invalid mutations, and untrusted owner fields. The tests use an in-process JWKS key so live provider availability and key rotation still require verification.
Nine PostgreSQL API tests passed with the restricted test role, including concurrent replay and only one accepted revision from competing edits. Ten backend tests passed in the default suite, and the PostgreSQL-only test was skipped there.
