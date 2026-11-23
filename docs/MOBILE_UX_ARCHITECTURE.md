# Mobile UX architecture

Consumer entrypoint: `mobile/lib/main.dart`. Existing Riverpod state, SQLite schema v8, food snapshots, account database separation, outbox/inbox and explicit guest-transfer workflow remain in place. No consumer database migration is introduced by FLEX 2.

Home, Diary, Add, Progress and Profile remain the consumer destinations. New changes add an animated calorie ring, expandable meals, duplicate-entry action using the existing atomic meal-copy transaction, chart value tooltips and Firebase account controls. Reduced-motion disables new animations. Save and failure feedback remain tied to transaction completion.

Firebase is initialized only when build configuration is supplied. Initialization failure preserves local guest access. Auth0 remains available on configured native builds. Firebase tokens are obtained from the SDK; backend UUIDs continue to name account databases. A changed Firebase UID cannot reuse another account's token cache.

The existing native sync transport is preserved, including custom trust support for tests. Browser sync uses a separate conditional HTTP implementation with the same operation acknowledgement, conflict and retry contract. Browser cloud operation is not accepted until an HTTPS backend and CORS configuration are verified.

Still outstanding: account erasure, full interactive macro/milestone exploration, swipe gestures, pull-to-refresh and native acceptance on healthy Android hardware. Notification scheduling and health integrations remain outside the implemented capabilities. No completion claims are made for these paths.
