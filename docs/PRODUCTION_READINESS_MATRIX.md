# FLEX production readiness matrix

| Gate | Phase 18 status | Required evidence |
| --- | --- | --- |
| Host regression and JWT isolation | Passed | Signed JWT, TLS trust, ownership, migrations and replay tests |
| Public Auth0 and HTTPS configuration | Blocked | Tenant owner supplies public development values and reachable trusted HTTPS API |
| Real Android authentication and recovery | Blocked | Universal Login, callback, registration and hosted recovery |
| Secure session lifecycle | Host tests only | Keystore restoration, renewal, logout and switching on Android |
| Live Android diary sync | Blocked | Two authorized Android clients observe creation, edit, deletion and restart |
| Visible post-commit totals | Blocked for signed-in devices | Observe Diary, Today, Nutrition and Progress |
| Guest isolation | Host tests and isolated Android guest diary passed | Still verify guest and account separation with a real signed-in device |
| Release approval | Open | Complete live and device gates before any rollout |

Phase 18B adds the hosted browser logout request. Dashboard allow-list and browser-cookie clearing still require the live provider test.

Phase 18C confirmed the public identity and API values are still missing. Phase 19 Progress refresh now has an independent implementation. Its host widget result is in TEST_RESULTS.md. Signed-in Android refresh remains blocked.

Phase 19 tracker sync and guest staging are development-only. Live provider and Android cloud acceptance remain required before enabling either gate for users.

## Phase 20 gates

Verified locally: PostgreSQL restore, signed synthetic ownership checks, and scoped record export. Prepared: backend container, staging TLS and pool configuration, and CI workflow. Open: external staging, hosted checks, native tracker CRUD, interactive conflict resolution, and account erasure. Ordinary Android cloud sync stays disabled pending live Auth0 acceptance.
