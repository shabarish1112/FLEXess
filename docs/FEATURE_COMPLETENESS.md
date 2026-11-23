# Feature completeness

## Implemented local product workflows

| Area | Working behavior |
| --- | --- |
| Onboarding | Welcome, optional name/height, starting weight editor, goal/activity selection, activity target, dated nutrition/water/weight target configuration, completion |
| Home | Profile greeting, known calories, energy ring, optional exercise adjustment, remaining/over label, macro progress, water/activity/latest weight, quick logging |
| Navigation | Home, Diary, central Add sheet, Progress, Profile; compact bottom navigation and expanded navigation rail; retained tab state and Android back-to-Home behavior |
| Diary | Calendar and adjacent dates, four meal groups, source-preserving entries, portions, edit/delete confirmation, autosaved drafts, atomic copy to another date, saved meals and date-local notes |
| Food discovery | Local USDA search, recent foods, frequency-ranked foods, favorites, custom food creation, serving conversions and nutrient preview |
| Analytics | Daily/7/30-day nutrition views, energy bars, average macro grams, dated goals versus actual, explicit missingness |
| Tracking | Weight/water/exercise CRUD, quick water amounts, historical date selection, unit conversion, rough exercise estimates with missing-data handling |
| Progress | 7/30/90-day history, weight/hydration charts with text, observed weight change and target, dated tracking edit entry points |
| Profile/settings | Persisted local profile, system/light/dark appearance, metric/imperial display preference, readable/copyable local JSON export, help and privacy |
| Persistence | Additive SQLite v8, old entries/drafts/goals preserved, transactional multi-food copies, notifications only after committed local or remote changes |
| Browser | Existing Flutter application using SQLite/IndexedDB, origin-specific guest storage and explicit storage notice |

## External or unsupported capabilities

| Capability | Status and dependency |
| --- | --- |
| Android hosted login/signup/recovery | Existing configuration-gated Auth0/AppAuth implementation preserved; live tenant, client/API values and device acceptance still required |
| Android cloud sync and guest transfer | Existing owner-scoped backend/outbox/inbox preserved. Manual sync/transfer remain gated until live acceptance; automatic sync is off |
| Browser account/cloud sync | Unavailable; native session implementation is deliberately not activated in a browser |
| Cloud account deletion | No erasure endpoint or verified provider/retention flow. UI explains unavailability and does not simulate a request |
| Interactive sync-conflict resolution | Still pending; conflicting versions are preserved |
| Barcode camera scanning | Not installed; availability dialog routes users to name search or custom food entry |
| Native health/tracker integrations | No supported integration configured; help explains availability |
| Notifications | No scheduler or permission flow; UI states that reminders are unavailable |
| New local profile/notes/favorites/saved meals | Stored locally per active SQLite database; no new cloud payload contract is claimed |
| Browser offline reload | Not implemented; initial page load requires network. Loaded local diary operations do not require a server |
| Android public release | Debug verification is separate from store signing and physical ARM device acceptance |

FLEX remains a development release, not an accepted production cloud service. Nutrition targets are user-selected; no personalized calorie prescription or fabricated verified nutrition is provided.
