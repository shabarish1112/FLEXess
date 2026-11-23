# Phase 18 device stability

ADB listed emulator-5554 and no attached physical ARM64 phone. Shell echo FLEX and standalone compressed UIAutomator capture succeeded. The emulator window was owned by a com.android.systemui unresponsive dialog. The verified Close app action was selected without clearing app or emulator data. FLEX subsequently regained focus. The runner now reports System UI ANR explicitly when a hierarchy does not expose a FLEX control.

The currently installed isolated package is dev.independent.fitness_diary.isolatedtest. No user FLEX app upgrade or database reset was performed. Windows reported 1481276 KiB free RAM during recovery. A separate AVD was not started.

The initial am start -W timed out after saving the synthetic draft. ADB later confirmed the restarted isolated activity. After committing the draft, UIAutomator returned null roots on restart. Once focused, the runner resumed from the committed test entry rather than writing a duplicate. The smoke now accepts explicit Draft or Entry resume for the isolated package, verifies the expected record count and handles merged Flutter semantics and bounded search input.
