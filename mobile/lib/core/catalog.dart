import '../features/diary/domain.dart';

class Draft {
  const Draft(
    this.id,
    this.day,
    this.meal,
    this.food,
    this.serving,
    this.quantity,
  );
  final String id, day, quantity;
  final Meal meal;
  final Food food;
  final Serving serving;
}

Map<String, Object?> foodRecord(Food food) => {
  'id': food.id,
  'name': food.name,
  'nutrients': {
    for (final item in food.per100g.entries) item.key.name: item.value,
  },
  'servings': [
    for (final item in food.servings)
      {'label': item.label, 'grams': item.grams},
  ],
  'source': food.source,
  'version': food.version,
};

Food foodFromRecord(Map<String, dynamic> row) => Food(
  row['id'] as String,
  row['name'] as String,
  {
    for (final nutrient in Nutrient.values)
      nutrient: row['nutrients'][nutrient.name] as int?,
  },
  [
    for (final item in row['servings'] as List)
      Serving(item['label'] as String, item['grams'] as num),
  ],
  source: row['source'] as String,
  version: row['version'] as String,
);
