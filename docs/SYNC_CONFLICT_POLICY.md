# Sync conflict policy

- Concurrent edits and stale updates require a matching base revision. Preserve the local proposed state and server state for explicit resolution.
- A deletion leaves a tombstone and increments the revision. A stale update cannot resurrect it. Explicit restoration creates a new revision after review.
- Identical delivery returns the stored receipt. A changed payload using the same operation identifier is rejected. A second create using the same record identifier is a conflict unless it is the original delivery.
- Out-of-order operations pause the affected record queue. Other records can proceed.
- If the network drops after server commit or after restart, resend the same operation identifier. Persist the acknowledgement before removing pending state.
- Permanent rejection stays visible with safe recovery instructions. Guest imports require explicit approval and replay with the original mapping.
