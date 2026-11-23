# Screen inventory

| Area | Audited implementation | Required refinement |
| --- | --- | --- |
| Startup | Native branded splash | New palette; optional onboarding |
| Home | Energy and macro text | Ring, tracking summaries, quick logging, adaptive composition |
| Diary | Four meals, date arrows, CRUD, durable drafts | Calendar, copy, saved meals, dated notes |
| Search | Bounded offline USDA search and portion preview | Recent, frequent, favorites, custom foods, explicit scanner availability |
| Nutrition | Daily totals and per-meal nutrient text | Daily/weekly charts with textual values |
| Weight/water/exercise | Durable CRUD, unit conversion and quick water | Primary Add entry points and persistent display preference |
| Goals | Dated energy, macros, water, weight, exercise credit | Activity target, onboarding integration, decimal weight precision |
| Progress | 7/30/90-day records and weight bars | Chart hierarchy and accessible historical editing |
| Profile | Native account page | Local profile, units/theme preferences, export, help/privacy |
| Identity | Hosted native login/signup/recovery/logout | Preserve; provider configuration and live acceptance remain required |
| Deletion | No cloud erasure API | Honest unavailable workflow; no simulated successful deletion |
| Sync | Gated manual native sync and guest transfer | Preserve conflict state; do not enable automatic sync |

Figma: https://www.figma.com/design/leE6qFHI8f29Y5LKxJSrak

The expanded design contains 52 editable screen, state and theme views using Inter and the requested violet/teal/amber palette. The implemented product now covers the refinements in the table except for the external/unsupported capabilities explicitly recorded in FEATURE_COMPLETENESS.md.
