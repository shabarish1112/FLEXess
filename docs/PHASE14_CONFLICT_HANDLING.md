# Phase 14 conflicts

Unacknowledged local changes prevent projection. The outbox retains the local mutation and base revision, and the inbox retains the remote state and conflict flag. Tombstones remove active rows when no local change is pending. Interactive resolution remains pending.
