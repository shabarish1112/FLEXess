# Phase 20 conflict resolution

The existing offline outbox regression covers retain-on-conflict and replay with the same operation ID. Interactive resolution remains open. Exercise each choice against the observed remote revision, preserve newer local edits, and commit projection and outbox changes within one transaction. Include restart and a second stale-revision test before shipping.
