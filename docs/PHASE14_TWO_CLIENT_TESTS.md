# Phase 14 client regression

Independent SQLite databases exercised an operation from the real outbox, synthetic receipts, replay, snapshot equality, local edits versus a tombstone, and clean tombstone removal. These fixture tests did not connect both clients to FastAPI. The backend suite ran separately.
