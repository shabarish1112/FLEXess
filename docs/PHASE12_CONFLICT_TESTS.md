# Phase 12 conflict tests

Backend tests cover stable acknowledgement replay for create, update and delete, changed payload under the same operation ID, update arriving before create, stale revision, and an attempted update after tombstoning. The client keeps immutable local operations and an optional server conflict payload. A blocked record queue does not block another record.

Tests of the HTTPS path against a live service, two real mobile devices, interactive conflict resolution and change-feed application remain pending.
On PostgreSQL 18.4, two concurrent replays returned the same acknowledgement and competing updates to the same revision produced one successful edit and one explicit conflict.
