# Guest account migration

Guest mode remains the local default. Sign-in leaves guest data on the device. Present a separate opt-in preview with record categories and counts before any upload. Keep drafts local. Map selected records to stable UUIDs once inside a SQLite transaction. Bind the resulting outbox operations to the consenting account. Preserve original snapshots and leave guest data intact if the import fails or is cancelled.

On logout, pause that account's queue and hide its account-scoped data from any subsequently signed-in identity. Resume only when the same account returns. Never adopt or silently merge another account's queue.
