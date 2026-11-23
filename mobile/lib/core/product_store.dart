import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../features/diary/domain.dart';
import 'catalog.dart';

/// Device-local preferences and collections; not part of the cloud contract.
class ProductStore {
  const ProductStore(this.db);
  final Database db;

  static Future<void> migrate(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE food_favorites (source TEXT NOT NULL, id TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(source, id))',
    );
    await db.execute(
      'CREATE TABLE saved_meals (id TEXT PRIMARY KEY, name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 80), payload TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE day_notes (day TEXT PRIMARY KEY, note TEXT NOT NULL CHECK(length(note) <= 2000))',
    );
  }

  Future<Map<String, dynamic>> preferences() async {
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['profile'],
    );
    return rows.isEmpty
        ? {}
        : (jsonDecode(rows.single['value'] as String) as Map<String, dynamic>);
  }

  Future<void> savePreferences(Map<String, dynamic> values) async {
    final name = values['name'];
    final height = values['height'];
    final target = values['activityMinutes'];
    if (name is! String ||
        name.trim().length > 80 ||
        (height != null &&
            (height is! num ||
                !height.isFinite ||
                height < 50 ||
                height > 250)) ||
        (target != null && (target is! int || target < 1 || target > 1440)) ||
        !['system', 'light', 'dark'].contains(values['theme']) ||
        !['metric', 'imperial'].contains(values['units']) ||
        ![
          'Maintain',
          'Lose',
          'Gain',
          'Build habits',
        ].contains(values['goal']) ||
        !['Low', 'Moderate', 'High'].contains(values['activity'])) {
      throw const FormatException('Invalid profile preferences.');
    }
    await db.insert('app_settings', {
      'key': 'profile',
      'value': jsonEncode(values),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Food>> favorites() async => [
    for (final row in await db.query('food_favorites', orderBy: 'source, id'))
      foodFromRecord(
        jsonDecode(row['payload'] as String) as Map<String, dynamic>,
      ),
  ];

  Future<List<Food>> loggedFoods({required bool frequent}) async {
    final rows = await db.rawQuery(
      'SELECT food_record, count(*) AS uses, max(rowid) AS latest FROM entries WHERE food_record IS NOT NULL GROUP BY food_record ORDER BY latest DESC',
    );
    final foods = <(String, String), ({Food food, int uses, int latest})>{};
    for (final row in rows) {
      final food = foodFromRecord(
        jsonDecode(row['food_record'] as String) as Map<String, dynamic>,
      );
      final key = (food.source, food.id);
      final old = foods[key];
      foods[key] = (
        food: old?.food ?? food,
        uses: (old?.uses ?? 0) + (row['uses'] as int),
        latest: old?.latest ?? row['latest'] as int,
      );
    }
    final values = foods.values.toList()
      ..sort(
        (a, b) =>
            frequent ? b.uses.compareTo(a.uses) : b.latest.compareTo(a.latest),
      );
    return values.take(100).map((r) => r.food).toList();
  }

  Future<void> favorite(Food food, {required bool selected}) async {
    if (!selected) {
      await db.delete(
        'food_favorites',
        where: 'source = ? AND id = ?',
        whereArgs: [food.source, food.id],
      );
    } else {
      await db.insert('food_favorites', {
        'source': food.source,
        'id': food.id,
        'payload': jsonEncode(foodRecord(food)),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<String> note(String day) async {
    final rows = await db.query(
      'day_notes',
      where: 'day = ?',
      whereArgs: [day],
    );
    return rows.isEmpty ? '' : rows.single['note'] as String;
  }

  Future<void> saveNote(String day, String note) async {
    if (note.length > 2000 ||
        DateTime.tryParse(day) == null ||
        day.length != 10) {
      throw const FormatException('Invalid diary note.');
    }
    await db.insert('day_notes', {
      'day': day,
      'note': note,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> savedMeals() =>
      db.query('saved_meals', orderBy: 'name');

  Future<void> saveMeal(String name, List<DiaryEntry> entries) async {
    if (name.trim().isEmpty ||
        name.trim().length > 80 ||
        entries.isEmpty ||
        entries.length > 100) {
      throw const FormatException('Name a meal with 1–100 foods.');
    }
    final payload = [
      for (final entry in entries)
        {
          'food': foodRecord(entry.food),
          'serving': entry.food.servings.indexOf(entry.serving),
          'quantity': entry.quantity,
        },
    ];
    await db.insert('saved_meals', {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'name': name.trim(),
      'payload': jsonEncode(payload),
    });
  }

  List<DiaryEntry> mealEntries(String payload, String day, Meal meal) {
    final rows = jsonDecode(payload);
    if (rows is! List || rows.isEmpty || rows.length > 100) {
      throw const FormatException('Invalid saved meal.');
    }
    return [
      for (final row in rows)
        _mealEntry(row as Map<String, dynamic>, day, meal),
    ];
  }

  DiaryEntry _mealEntry(Map<String, dynamic> row, String day, Meal meal) {
    final food = foodFromRecord(row['food'] as Map<String, dynamic>);
    final index = row['serving'];
    final quantity = row['quantity'];
    if (index is! int ||
        index < 0 ||
        index >= food.servings.length ||
        quantity is! int) {
      throw const FormatException('Invalid saved portion.');
    }
    final serving = food.servings[index];
    food.scale(serving, quantity);
    return DiaryEntry('', day, meal, food, serving, quantity, {});
  }

  Future<String> export() async => const JsonEncoder.withIndent('  ').convert({
    'format': 'flex-local-export-v1',
    'created_at': DateTime.now().toUtc().toIso8601String(),
    for (final table in [
      'entries',
      'drafts',
      'tracking',
      'nutrition_goals',
      'app_settings',
      'food_favorites',
      'saved_meals',
      'day_notes',
    ])
      table: await db.query(table),
    'custom_foods': await db.query(
      'catalog',
      where: 'source = ?',
      whereArgs: ['Custom food'],
    ),
  });
}
