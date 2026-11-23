# Phase 15 sync contract

| Field | Wire and mobile contract |
| --- | --- |
| operation_id and record_id | UUID strings; the operation ID is the idempotency key. The record ID survives create, edit, and delete. |
| kind and action | Diary operations use diary and create, update, or delete. |
| base_revision and payload_version | Nonnegative integer revision and version 1. Create begins at revision 0. |
| payload | Date, meal, name, serving label, quantity in thousandths, and saved nullable nutrient milliunits. Weight in grams and density per 100 g are paired optional metadata. |
| record | Server-owned result includes revision, updated_at, payload, and deletion marker. A tombstone has null payload. |
| sequence | Monotonic sequence per account. The client applies consecutive sequences and persists the cursor in the same transaction. |

The Phase 14 legacy receipt format remains readable. Historical totals are retained when serving facts are incomplete.
