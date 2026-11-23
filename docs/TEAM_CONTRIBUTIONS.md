# FLEX contributions to one repository

Host repository: https://github.com/shabarish1112/FLEXess

| Member | Part |
| --- | --- |
| Shabarish | Host/integration, authentication services, entrypoints, dependencies, native build configuration, CI and deployment |
| Pramod | FastAPI, PostgreSQL models/migrations, server authorization, API contracts and backend tests |
| Harshita | Consumer screens, account/sign-in presentation, design tokens, branding and consumer UI tests |
| Prajwal | Admin frontend, local stores, catalog import, sync/guest transfer and data/admin regression tests |

Each source file belongs to exactly one part. The parts share folder names such as `mobile/`, but their files do not overlap. All four parts combine into one working application; a part is not a standalone app.

## Folder and upload layout

The local distribution folder is `team/contributions/`. Each member has a folder containing `files/` with their actual contribution, a file list and instructions. Their matching ZIP contains only repository-relative project paths, without an extra member or `files` directory.

Extract the four ZIPs into the same repository root. The result has one `backend/`, one `mobile/`, one `docs/` and the root configuration files. Preserve these paths when contributing. Do not put the outer member folders or ZIP archives into the application's source tree.

For development, each member clones the complete host repository, creates their own branch, changes their assigned part and submits a pull request. Shabarish reviews integration, merges and deploys. The repository already contains the existing application; extracting unchanged files alone does not produce a new code change to commit.

The handoff excludes private configuration, local databases, account-console screenshots, dependency/build caches, compiled APKs and Git history. These parts do not grant cloud credentials, application administrator roles or GitHub collaborator access.
