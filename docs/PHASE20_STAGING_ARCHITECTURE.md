# Phase 20 staging architecture

Use a private staging HTTPS proxy in front of the loopback API listener. Terminate TLS with a trusted certificate, restrict network ingress and use separate least-privilege database accounts for the runtime and migrations. Store environment files and CA material outside Git. Set FLEX_API_ENV_FILE, FLEX_MIGRATION_ENV_FILE and FLEX_POSTGRES_CA_PATH for Compose. Files should be readable by the container's numeric UID where mounted.

Both environment files need FLEX_ENVIRONMENT=staging, DATABASE_URL with the postgresql+psycopg driver, DATABASE_CA_FILE=/run/flex/postgres-ca.pem and IDENTITY_ISSUER, IDENTITY_AUDIENCE, IDENTITY_JWKS_URL and IDENTITY_CLIENT_ID for the staging tenant. Set CORS_ORIGINS to a JSON array of explicit HTTPS origins only if a browser client needs it. Use different database credentials in each file.

Run docker compose --profile migration build, then docker compose --profile migration run --rm migrate, then docker compose up -d api. Check /health/live and /health/ready locally and run ownership tests over the staging HTTPS endpoint before accepting traffic. Configure the proxy to redact authorization headers and query strings. Public hosting was not provisioned.
