"""Normalize a USDA Foundation/SR Legacy foods JSON export for FLEX."""
import argparse
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
import json
import re
from pathlib import Path

NUTRIENTS = {1003: ("protein", "g"),
             1005: ("carbs", "g"), 1004: ("fat", "g"), 1079: ("fiber", "g")}
ENERGY = (2047, 2048, 1008)

def normalize(rows, version):
    if not version.strip():
        raise ValueError("A dataset release version is required.")
    records, rejected, seen = [], [], set()
    for index, row in enumerate(rows):
        try:
            identifier = str(row["fdcId"])
            name = row["description"].strip()
            if not identifier.isdecimal() or not name or identifier in seen:
                raise ValueError("invalid or duplicate food identity")
            measured, energies = {}, {}
            for entry in row.get("foodNutrients", []):
                nutrient = entry["nutrient"]
                nutrient_id = nutrient["id"]
                canonical = ("energy", "kcal") if nutrient_id in ENERGY else NUTRIENTS.get(nutrient_id)
                if canonical is None or entry.get("amount") is None:
                    continue
                key, unit = canonical
                found = nutrient["unitName"].lower()
                target, lookup = (energies, nutrient_id) if key == "energy" else (measured, key)
                if lookup in target or (found != unit and not (unit == "g" and found == "mg")):
                    raise ValueError("duplicate nutrient or incompatible unit")
                amount = Decimal(str(entry["amount"]))
                if found == "mg":
                    amount /= 1000
                if not amount.is_finite() or not 0 <= amount <= 1000:
                    raise ValueError("nutrient outside supported range")
                target[lookup] = int((amount * 1000).quantize(Decimal(1), rounding=ROUND_HALF_UP))
            energy_id = next((key for key in ENERGY if key in energies), None)
            servings = [{"label": "100 g", "grams": 100}]
            labels = {"100 g"}
            for portion in row.get("foodPortions", []):
                grams = portion.get("gramWeight")
                unit = portion.get("measureUnit", {}).get("name", "")
                amount = portion.get("amount")
                note = (portion.get("modifier") or portion.get("portionDescription") or "").strip()
                if not isinstance(grams, (int, float)) or not 0 < grams <= 10000:
                    continue
                if unit.lower() in {"undetermined", "racc", ""}:
                    if not note or re.fullmatch(r"\d+", note):
                        continue
                    label = note
                else:
                    if not isinstance(amount, (int, float)) or amount <= 0:
                        continue
                    label = f"{amount:g} {unit}" + (f" ({note})" if note else "")
                if label in labels:
                    continue
                labels.add(label)
                servings.append({"label": label, "grams": grams})
            records.append({
                "id": "usda:" + identifier, "name": name, "source": "USDA FoodData Central",
                "sourceId": identifier, "version": version, "brand": row.get("brandOwner"),
                "category": row.get("foodCategory", {}).get("description"),
                "attribution": "USDA Agricultural Research Service, FoodData Central",
                "updatedAt": datetime.now(timezone.utc).isoformat(),
                "nutrients": {"energy": energies.get(energy_id), **{key: measured.get(key) for key, _ in NUTRIENTS.values()}},
                "energyNutrientId": energy_id, "publicationDate": row.get("publicationDate"),
                "servings": servings,
            })
            seen.add(identifier)
        except (ValueError, KeyError, AttributeError, TypeError, InvalidOperation) as exc:
            rejected.append({"row": index, "reason": str(exc)})
    return records, rejected

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--foundation-curated", action="store_true", help="Exclude historical reference and non-food experimental samples")
    args = parser.parse_args()
    data = json.loads(args.source.read_text(encoding="utf-8"))
    groups = [data[key] for key in ("FoundationFoods", "SRLegacyFoods") if key in data]
    if len(groups) != 1 or not isinstance(groups[0], list):
        parser.error("Supply a FoundationFoods or SRLegacyFoods USDA JSON export.")
    rows = groups[0]
    excluded = 0
    if args.foundation_curated:
        selected = [r for r in rows if not r.get("isHistoricalReference") and r.get("dataType") == "Foundation"]
        excluded = len(rows) - len(selected)
        rows = selected
    records, rejected = normalize(rows, args.version)
    if not records:
        parser.error("No valid records; inspect source format.")
    args.output.write_text(json.dumps(records, ensure_ascii=False), encoding="utf-8")
    args.output.with_suffix(".rejects.json").write_text(json.dumps(rejected), encoding="utf-8")
    print(f"{len(groups[0])} source, {excluded} excluded, {len(records)} accepted, {len(rejected)} rejected")

if __name__ == "__main__":
    main()
