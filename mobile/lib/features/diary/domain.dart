enum Meal { breakfast, lunch, dinner, snacks }

enum Nutrient {
  energy('Calories', 'kcal'),
  protein('Protein', 'g'),
  carbs('Carbs', 'g'),
  fat('Fat', 'g'),
  fiber('Fiber', 'g');

  const Nutrient(this.label, this.unit);
  final String label, unit;
}

typedef Amounts = Map<Nutrient, int?>;

class Serving {
  const Serving(this.label, this.grams);
  final String label;
  final num grams;
}

class Food {
  const Food(
    this.id,
    this.name,
    this.per100g,
    this.servings, {
    this.source = 'Synthetic development data',
    this.version = 'fixture-1',
  });
  final String id, name, source, version;
  final Amounts per100g;
  final List<Serving> servings;

  Amounts scale(Serving serving, int quantityMilli) {
    if (!servings.contains(serving) ||
        quantityMilli < 1 ||
        quantityMilli > 100000) {
      throw ArgumentError(
        'Choose an available serving and a quantity from 0.001 to 100.',
      );
    }
    return {
      for (final nutrient in Nutrient.values)
        nutrient: switch (per100g[nutrient]) {
          final int value =>
            (value * (serving.grams * 1000).round() * quantityMilli +
                    50000000) ~/
                100000000,
          null => null,
        },
    };
  }
}

const fixture = [
  Food(
    'oats',
    'Sample rolled oats',
    {
      Nutrient.energy: 380000,
      Nutrient.protein: 13000,
      Nutrient.carbs: 68000,
      Nutrient.fat: 7000,
    },
    [Serving('Bowl · 40 g', 40), Serving('100 g', 100)],
  ),
  Food(
    'beans',
    'Sample cooked beans',
    {
      Nutrient.energy: 125000,
      Nutrient.protein: 8500,
      Nutrient.carbs: 22000,
      Nutrient.fat: null,
    },
    [Serving('Scoop · 75 g', 75), Serving('100 g', 100)],
  ),
  Food(
    'mango',
    'Sample sliced mango',
    {
      Nutrient.energy: 60000,
      Nutrient.protein: 800,
      Nutrient.carbs: 15000,
      Nutrient.fat: 400,
    },
    [Serving('Cup · 165 g', 165), Serving('100 g', 100)],
  ),
];

int? parseQuantity(String input) {
  final match = RegExp(r'^(\d{1,3})(?:\.(\d{1,3}))?$').firstMatch(input.trim());
  if (match == null) return null;
  final value =
      int.parse(match[1]!) * 1000 +
      int.parse((match[2] ?? '').padRight(3, '0'));
  return value >= 1 && value <= 100000 ? value : null;
}

String diaryDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class DiaryEntry {
  const DiaryEntry(
    this.id,
    this.day,
    this.meal,
    this.food,
    this.serving,
    this.quantity,
    this.amounts,
  );
  final String id, day;
  final Meal meal;
  final Food food;
  final Serving serving;
  final int quantity;
  final Amounts amounts;
}

({int known, int missing}) total(
  Iterable<DiaryEntry> entries,
  Nutrient nutrient,
) {
  var known = 0;
  var missing = 0;
  for (final entry in entries) {
    final value = entry.amounts[nutrient];
    if (value == null) {
      missing++;
    } else {
      known += value;
    }
  }
  return (known: known, missing: missing);
}
