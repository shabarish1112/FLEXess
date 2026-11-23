# FLEX 2 design system

The shared implementation is `mobile/lib/ui/design_system.dart`. Preserve the established violet #6D5EF8, teal #18B7A0 and amber #F4B860 brand. Canvas #10121B, surface #1A1D29; light canvas #F7F8FC. Inter is bundled with its OFL license. Material color roles provide accessible text and error colors.

Spacing uses 4/8/12/16/20/24/32 pixels; controls target 48 pixels. Use 16-pixel form radii, 24-pixel cards, restrained borders and no full-screen blur. Mobile emphasizes daily progress; administration emphasizes tables, tools and operational density.

The calorie ring interpolates over 380 ms and meal expansion over 220 ms. Both honor `MediaQuery.disableAnimations`. Value bars expose exact text and tap/hover tooltips; numbers remain available without interpreting color. Duplicate food actions use supported platform haptics after the transaction commits.

Admin uses a collapsible rail from 1000 pixels and a drawer below it. Horizontal scrolling preserves readable data-table columns. Forms are keyboard reachable; Ctrl+K opens global search and Ctrl+R reloads the active report. Do not invent charts or notifications when their underlying measurements do not exist.
