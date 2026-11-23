import 'package:sqflite/sqflite.dart';

import '../features/diary/domain.dart';
import 'tracking_store.dart';
import 'sync_inbox.dart';

const trackerKinds = {'goals', 'weight', 'water', 'exercise'};

int? _number(Object? value, int minimum, int maximum, {bool optional = false}) {
  if (optional && value == null) return null;
  if (value is! int || value < minimum || value > maximum) {
    throw const FormatException('Invalid tracker quantity.');
  }
  return value;
}

int? _grams(Object? value) {
  final mg = _number(value, 1000, 2000000, optional: true);
  if (mg != null && mg % 1000 != 0) {
    throw const FormatException('Goal targets must use whole grams.');
  }
  return mg == null ? null : mg ~/ 1000;
}

Future<void> projectTracker(
  Transaction txn,
  Map<String, dynamic> record,
) async {
  final id = record['id'] as String;
  final revision = record['revision'] as int;
  final updated = record['updated_at'];
  if (updated is! String || DateTime.tryParse(updated) == null) {
    throw const FormatException('Invalid tracker timestamp.');
  }
  final kind = record['kind'] as String;
  final rows = await txn.query(
    'sync_diary_mapping',
    where: 'record_id = ?',
    whereArgs: [id],
  );
  String? local = rows.firstOrNull?['local_id'] as String?;
  final prefix = kind == 'goals' ? 'goal:' : 'track:';
  if (local != null && !local.startsWith(prefix)) {
    throw const FormatException('Tracker identity changed type.');
  }
  if (record['deleted'] == true) {
    if (local == null) return;
    await txn.delete(
      kind == 'goals' ? 'nutrition_goals' : 'tracking',
      where: kind == 'goals' ? 'day = ?' : 'id = ? AND kind = ?',
      whereArgs: kind == 'goals'
          ? [local.substring(5)]
          : [
              int.parse(local.substring(6)),
              TrackKind.values.byName(kind).index,
            ],
    );
  } else {
    final payload = record['payload'] as Map<String, dynamic>;
    final day = payload['day'];
    final parsed = day is String ? DateTime.tryParse(day) : null;
    if (parsed == null || diaryDate(parsed) != day) {
      throw const FormatException('Invalid tracker date.');
    }
    if (kind == 'goals') {
      final key = 'goal:$day';
      if (local != null && local != key) {
        throw const FormatException('Goal date changed.');
      }
      if (local == null &&
          (await txn.query(
            'nutrition_goals',
            where: 'day = ?',
            whereArgs: [day],
          )).isNotEmpty) {
        throw const ProjectionConflict();
      }
      final credit = payload['exercise_credit'];
      if (credit != null && credit is! bool) {
        throw const FormatException('Invalid exercise credit.');
      }
      await txn.insert('nutrition_goals', {
        'day': day,
        'energy': _number(payload['calories'], 1, 20000, optional: true),
        'protein': _grams(payload['protein_mg']),
        'carbs': _grams(payload['carbs_mg']),
        'fat': _grams(payload['fat_mg']),
        'water': _number(payload['water_ml'], 1, 20000, optional: true),
        'weight': _number(
          payload['weight_grams'],
          1000,
          1000000,
          optional: true,
        ),
        'exercise_credit': credit == true ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      local = key;
    } else {
      final type = TrackKind.values.byName(kind);
      final name = payload['name'];
      final category = payload['category'];
      final intensity = payload['intensity'];
      const levels = {
        'light': 'Light',
        'moderate': 'Moderate',
        'vigorous': 'Vigorous',
      };
      if (type == TrackKind.exercise &&
          (name is! String ||
              name.trim().isEmpty ||
              name.trim().length > 80 ||
              (category != null &&
                  (category is! String || category.length > 80)) ||
              (intensity != null && !levels.containsKey(intensity)))) {
        throw const FormatException('Invalid exercise metadata.');
      }
      final values = <String, Object?>{
        'day': day,
        'kind': type.index,
        'value': switch (type) {
          TrackKind.weight => _number(payload['grams'], 1000, 1000000),
          TrackKind.water => _number(payload['milliliters'], 1, 20000),
          TrackKind.exercise => _number(payload['minutes'], 1, 1440),
        },
        'name': type == TrackKind.exercise ? name : '',
        'category': type == TrackKind.exercise ? category ?? '' : '',
        'intensity': type == TrackKind.exercise
            ? levels[intensity] ?? 'Unspecified'
            : '',
        'energy': type == TrackKind.exercise
            ? _number(payload['energy_kcal'], 0, 100000000, optional: true)
            : null,
      };
      if (local == null) {
        local = 'track:${await insertSyncedTracker(txn, values)}';
      } else if (await txn.update(
            'tracking',
            values,
            where: 'id = ? AND kind = ?',
            whereArgs: [int.parse(local.substring(6)), type.index],
          ) !=
          1) {
        throw StateError('The mapped tracker record is missing.');
      }
    }
  }
  await txn.insert('sync_diary_mapping', {
    'local_id': local,
    'record_id': id,
    'revision': revision,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}
