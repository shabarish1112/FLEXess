import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../features/diary/domain.dart';
import 'catalog.dart';

Future<void> projectDiary(Transaction txn, Map<String, dynamic> record) async {
  final id = record['id'] as String;
  final revision = record['revision'] as int;
  final updated = record['updated_at'];
  if (updated is! String || DateTime.tryParse(updated) == null) {
    throw const FormatException('Invalid diary update timestamp.');
  }
  final mappings = await txn.query(
    'sync_diary_mapping',
    where: 'record_id = ?',
    whereArgs: [id],
  );
  final localId = mappings.isEmpty
      ? 'remote:$id'
      : mappings.single['local_id'] as String;
  if (record['deleted'] == true) {
    await txn.delete('entries', where: 'id = ?', whereArgs: [localId]);
  } else {
    final p = record['payload'] as Map<String, dynamic>;
    final day = p['day'];
    final parsed = day is String ? DateTime.tryParse(day) : null;
    final meal = Meal.values.where((m) => m.name == p['meal']).firstOrNull;
    final quantity = p['quantity_milli'];
    final name = p['name'];
    final label = p['serving'];
    final nutrients = p['nutrients'];
    if (parsed == null ||
        diaryDate(parsed) != day ||
        meal == null ||
        quantity is! int ||
        quantity < 1 ||
        quantity > 100000 ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 300 ||
        label is! String ||
        label.trim().isEmpty ||
        label.length > 120 ||
        nutrients is! Map<String, dynamic> ||
        nutrients.entries.any(
          (e) =>
              !Nutrient.values.any((n) => n.name == e.key) ||
              (e.value != null &&
                  (e.value is! int || e.value < 0 || e.value > 100000000)),
        )) {
      throw const FormatException('Invalid diary snapshot.');
    }
    final saved = {
      for (final n in Nutrient.values) n: nutrients[n.name] as int?,
    };
    final grams = p['serving_grams'];
    final density = p['per_100g'];
    if ((grams == null) != (density == null) ||
        (grams != null &&
            (grams is! num ||
                !grams.isFinite ||
                grams <= 0 ||
                grams > 100000 ||
                density is! Map<String, dynamic> ||
                density.values.any(
                  (value) =>
                      value != null &&
                      (value is! int || value < 0 || value > 100000000),
                )))) {
      throw const FormatException('Invalid serving metadata.');
    }
    final food = Food(
      id,
      name,
      {
        for (final n in Nutrient.values)
          n: density is Map<String, dynamic>
              ? density[n.name] as int?
              : saved[n] == null
              ? null
              : (saved[n]! * 1000 / quantity).round(),
      },
      [Serving(label, grams as num? ?? 100)],
      source: 'Synced diary snapshot',
      version: grams == null ? 'sync-v1-legacy' : 'sync-v1',
    );
    final values = {
      'id': localId,
      'day': day,
      'meal': meal.index,
      'food': id,
      'food_record': jsonEncode(foodRecord(food)),
      'serving': 0,
      'quantity': quantity,
      'snapshot': jsonEncode(nutrients),
    };
    // Keep the original catalog metadata on locally authored entries.
    if (mappings.isNotEmpty) {
      final current = await txn.query(
        'entries',
        where: 'id = ?',
        whereArgs: [localId],
      );
      if (current.isNotEmpty) {
        final row = current.single;
        final old = row['food_record'];
        if (old is String) {
          final original = foodFromRecord(
            jsonDecode(old) as Map<String, dynamic>,
          );
          final serving = original.servings.indexWhere((s) => s.label == label);
          if (serving >= 0 && original.name == name) {
            values['food'] = row['food'];
            values['food_record'] = old;
            values['serving'] = serving;
          }
        }
      }
    }
    await txn.insert(
      'entries',
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  await txn.insert('sync_diary_mapping', {
    'local_id': localId,
    'record_id': id,
    'revision': revision,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}
