# FLEX food catalog

The bundled local catalog is sourced from USDA FoodData Central Foundation Foods, October 2026 release (archive 2026-10-29). USDA publishes FoodData Central data under CC0 and requests source acknowledgment. The app displays USDA FoodData Central and the dataset version. The asset also records the source record ID, publication date, category, energy nutrient ID and USDA attribution.

- Official release page: https://fdc.nal.usda.gov/download-datasets/
- Download: https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_foundation_food_json_2026-10-29.zip
- Downloaded at 2026-11-17T12:40:11.3718469Z.
- ZIP SHA-256: dd414cc9f1a132626bad354ef6655972c78b44aff14f16114dc899708663c579.
- JSON format: FoundationFoods array. 424 source records, 414 accepted, 10 rejected for negative nutrient measurements. The normalized asset is 222,884 bytes.
- Importer: scripts/import_usda.py, Phase 10 revision. Candidate records are non-historical Foundation foods. Reject rows are listed in the generated reject sidecar.
- Energy precedence is Atwater general (2047), then specific (2048), then legacy Energy (1008), retaining the selected source identifier. The supplied asset has 269 general, 95 legacy, and 50 unknown values. Units are not summed across definitions.
- Sources: https://fdc.nal.usda.gov/api-guide/ and https://fdc.nal.usda.gov/Foundation_Foods_Documentation/

## Reproduce

```powershell
python -m zipfile -e catalog-staging/foundation-2026-10.zip catalog-staging
python scripts/import_usda.py catalog-staging/FoodData_Central_foundation_food_json_2026-10-29.json catalog-staging/catalog.json --version 2026-10-29 --foundation-curated
python -m unittest discover -s scripts -p test_import_usda.py
```

Validate staged records and copy only reviewed catalog.json to mobile/assets/catalog.json. Archive and reject files belong in the ignored staging directory. The app imports with one SQLite transaction. It leaves previous rows in place and updates matching source IDs; diary and draft snapshots remain unchanged. The setup can restore a prior catalog by provisioning its reviewed asset or restoring a protected pre-upgrade database backup. Existing fixtures are hidden from search when USDA records are present.

Search prioritizes exact and prefix matches over substring matches, uses a NOCASE name index and caps results at 100. Leading-wildcard lookup scans candidate names; FTS is deferred until a larger release requires it. Sample checks: Banana 1105314 provides 97 kcal/100 g and a 115 g USDA portion; oats 2346396 provides 382 kcal/100 g with fiber unknown; lentils 2644283 provides 360 kcal/100 g.

No commercial food data or MyFitnessPal data is included.
