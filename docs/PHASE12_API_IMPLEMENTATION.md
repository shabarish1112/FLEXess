# Phase 12 API implementation

The working backend routes are GET /health/live, GET /health/ready, GET /v1/me, GET /v1/records/{kind}, GET /v1/records/{kind}/{record_id}, POST /v1/sync/operations and GET /v1/sync/changes. The record kinds are profile, goals, diary, weight, water and exercise. Each kind has its own validated payload schema. Diary nutrition snapshots use nullable milliunits. Account UUID, record UUID, revision and timestamps are returned by the server.

All record writes use the sync operation route so create, update and delete share ownership and idempotency logic. Changes use an owner-scoped integer cursor and records paginate by UUID. The files in contracts/ continue to describe the larger proposed product API. FastAPI generates the runtime contract from registered endpoints.
