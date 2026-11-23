# Phase 16 live diary sync

The separate FLEX_ENABLE_DIARY_SYNC build define defaults to false. The account page exposes a manual action only when the flag is enabled and the account has been verified. It drains the current account outbox, pulls and projects pages, refreshes the diary provider and reports pending, rejected or conflicting operations. Foreground scheduling, automatic retries and an already-open Progress route are pending. Ordinary-user sync remains disabled.
