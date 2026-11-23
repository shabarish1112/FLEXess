# Authentication architecture

Proposed only. Use a managed OpenID Connect identity service with a supported Flutter client, password reset, token renewal and revocation. Select the provider against those requirements and verify its supported settings before integration. Use authorization code with PKCE where the provider supports browser-based native login. Keep renewal credentials in platform secure storage; keep bearer tokens and credentials out of SQLite, logs and diagnostics.

FastAPI must validate JWT signature with provider keys, the configured issuer and audience, expiry, and allowed algorithms. Map issuer and subject to one local account. Product routes must check active account state on each request and derive ownership from the authenticated principal. Use consistent 401 responses for invalid sessions and 404 for inaccessible record IDs. Apply rate limits to provider sign-in and reset flows, and quota limits to authenticated sync.

Test missing, invalid, expired and wrong-audience tokens, disabled and deleted accounts, two-user reads and mutations, and invalid request bodies. Sign-out clears secure session state and suspends uploads. Account deletion requires reauthentication, token revocation, a defined backup retention period, and deletion of owned cloud data. Keep local-data removal a separate explicit choice.
