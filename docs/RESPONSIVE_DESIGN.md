# Responsive design

- Below 840 px: five-destination bottom navigation and vertically composed content.
- At 840 px: a navigation rail replaces the bottom bar.
- At 1200 px: rail labels expand. Dashboard/diary content uses two columns when the available content area reaches 900 px; the main content caps at 1440 px.
- Lists retain page-storage keys across tabs. The primary stack retains Progress/Profile state. Local commit notifications refresh Progress without discarding another tab's state.
- Inputs expand into their available width. Keyboard-aware Scaffold routes, scrolling forms, safe areas and visible labels preserve access on compact devices.
- At large system text sizes the bounded energy ring becomes a text summary. Bottom navigation gains height rather than clipping labels.
- Goal and chart text always includes units. Charts are accompanied by date/value labels and explicit unknown/incomplete descriptions.

Automated layout cases cover 320×720, 390×844 with 2× text and 1440×960. These do not replace physical device, TalkBack, browser/OS and tablet acceptance.
