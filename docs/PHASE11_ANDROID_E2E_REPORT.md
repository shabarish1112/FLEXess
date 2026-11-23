# Phase 11 Android end-to-end report

The existing installation of dev.independent.fitness_diary was launched without reinstalling or clearing its SQLite database. No pre-existing records were changed. System UI ANR and hierarchy instability delayed traversal. See the device matrix for current scope and the ADB report for the commands and recovery.

The recovered device successfully opened Diary and Breakfast food search. The hierarchy exposed the expected search hint and a focused input. One run delivered an altered search query, so that result could not establish catalog behavior.

The recovered emulator completed real USDA search for Bananas, ripe and slightly ripe, raw. The source was USDA FoodData Central and the release date was 2026-10-29. Two 100 g servings showed 194 kcal. The runner discarded its temporary draft and confirmed the search screen returned.

The write smoke verified exactly one investigator-created banana entry after adding through Breakfast. After force-stop and launch, compressed UIAutomator returned a null root. A separate uncompressed capture verified one matching entry still present, then the named deletion dialog and absence afterward. The dated total and quantity edit were not independently tested in this run. No other record was deleted.
