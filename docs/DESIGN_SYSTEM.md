# FLEX design system

## Foundations

| Token | Value | Usage |
| --- | --- | --- |
| Primary | `#6D5EF8` | Main actions and progress |
| Secondary | `#18B7A0` | Hydration and activity indicators |
| Accent | `#F4B860` | Supporting activity emphasis |
| Dark canvas / surface | `#10121B` / `#1A1D29` | App background and cards |
| Light canvas / surface | `#F7F8FC` / `#FFFFFF` | Light appearance |
| Dark text / secondary | `#F1F2FA` / `#B4BAD0` | Readable labels |
| Light text / secondary | `#10121B` / `#555D74` | Readable labels |
| Dark action text | `#B3ABFF` | Small action labels on dark surfaces |
| Error | `#FFB4AB` dark / `#B3261E` light | Validation and failure |

Use white text on violet. Teal and amber are chart/icon accents, not white-text button backgrounds. Error feedback includes words and semantic live regions. No visual style alone proves WCAG conformance; actual device and assistive-technology acceptance remains necessary.

Inter is bundled at `mobile/assets/fonts/Inter.ttf` with its SIL Open Font License. Source: https://github.com/google/fonts/tree/main/ofl/inter. No runtime font request is required.

Typography: metrics 36/700, page headings 28/700, section headings 22/600, titles 16/600, body 14 with 1.5 line height. Figma uses Inter throughout. Spacing uses 8, 12, 16, 20, 24 and 32 px. Cards have 24 px radii; controls use 16 px. Buttons have a minimum 48×52 px target. Native Material icons provide consistent iconography; the F mark is original FLEX artwork.

## Reusable implementation

`ui/design_system.dart` owns both themes, `MetricCard`, `GoalRing`, `ValueBars` and `LoadingCards`. Existing food, goal, tracker, dialog and snackbar patterns use the shared Material themes. Charts retain textual labels; missing values are distinct from zero. Large text switches the bounded energy ring to an unconstrained text summary. No custom perpetual animation or blur pipeline is introduced.

## Figma

Editable file: https://www.figma.com/design/leE6qFHI8f29Y5LKxJSrak

52 screen/state/theme views, semantic color variables, reusable record/input/button/navigation components, and linked flows. Sample figures illustrate the design and do not represent user records. Dark/light previews are in `docs/screenshots/`. Authentication remains a hosted native-provider handoff. Conflict resolution is labeled as planned, not implemented.
