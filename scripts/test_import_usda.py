import unittest
from import_usda import normalize

class ImportTest(unittest.TestCase):
    def test_units_missing_duplicates_and_invalid(self):
        row = {"fdcId": 17, "description": "Test Food",
               "foodNutrients": [{"nutrient": {"id": 1003, "unitName": "MG"}, "amount": 1250}]}
        rows, rejected = normalize([row, row, {}, {**row, "fdcId":18,
                                  "foodNutrients":[{"nutrient":{"id":1003,"unitName":"kcal"},"amount":12}]}], "test-1")
        self.assertEqual(len(rejected), 3)
        self.assertEqual(rows[0]["nutrients"]["protein"], 1250)
        self.assertIsNone(rows[0]["nutrients"]["energy"])
        self.assertEqual(rows[0]["version"], "test-1")
