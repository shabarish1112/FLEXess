# Phase 19 security verification

Account identity still comes from the existing verified backend and profile-scoped SQLite filenames. The server derives ownership from signed access tokens. Transfer requires explicit consent and a matching active account. Guest files stay local, checkout documentation carries no credentials, and ordinary-user sync and guest transfer gates default off. The development Auth0 and HTTPS dependency remains blocked.
