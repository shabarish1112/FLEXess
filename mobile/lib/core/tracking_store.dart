import 'package:sqflite/sqflite.dart';
import 'diary_outbox.dart';

enum TrackKind { weight, water, exercise }

class TrackRecord {
  const TrackRecord({
    this.id,
    required this.kind,
    required this.day,
    required this.value,
    this.name = '',
    this.category = '',
    this.intensity = '',
    this.energy,
  });

  final int? id;
  final TrackKind kind;
  final String day, name, category, intensity;
  final int value;
  final int? energy;

  factory TrackRecord.fromRow(Map<String, Object?> row) => TrackRecord(
    id: row['id'] as int,
    kind: TrackKind.values[row['kind'] as int],
    day: row['day'] as String,
    value: row['value'] as int,
    name: row['name'] as String,
    category: row['category'] as String,
    intensity: row['intensity'] as String,
    energy: row['energy'] as int?,
  );
}

class Targets {
  const Targets({
    this.energy,
    this.protein,
    this.carbs,
    this.fat,
    this.water,
    this.weight,
    this.exerciseCredit = false,
  });
  final int? energy, protein, carbs, fat, water, weight;
  final bool exerciseCredit;
}

int weightGrams(double value, {required bool pounds}) =>
    (value * (pounds ? 453.59237 : 1000)).round();

int waterMilliliters(double value, {required bool ounces}) =>
    (value * (ounces ? 29.5735295625 : 1)).round();

int? exerciseEstimate(int minutes, int? grams, String intensity) {
  final met = const {'Light': 3, 'Moderate': 5, 'Vigorous': 8}[intensity];
  if (met == null || grams == null) return null;
  return ((met - 1) * grams * minutes * 35 / 2000000).round();
}

class TrackingStore {
  const TrackingStore(this.db, {this.outbox, this.onChanged});
  final DiaryOutbox? outbox;
  final void Function()? onChanged;
  final Database db;

  static Future<void> migrate(DatabaseExecutor db) async {
    await db.execute("""
      CREATE TABLE tracking (
        id INTEGER PRIMARY KEY, kind INTEGER NOT NULL CHECK(kind BETWEEN 0 AND 2),
        day TEXT NOT NULL CHECK(length(day)=10), value INTEGER NOT NULL,
        name TEXT NOT NULL, category TEXT NOT NULL, intensity TEXT NOT NULL,
        energy INTEGER CHECK(energy IS NULL OR energy >= 0),
        CHECK((kind=0 AND value BETWEEN 1000 AND 1000000 AND energy IS NULL) OR
              (kind=1 AND value BETWEEN 1 AND 20000 AND energy IS NULL) OR
              (kind=2 AND value BETWEEN 1 AND 1440 AND length(trim(name)) BETWEEN 1 AND 80))
      )
    """);
    await db.execute(
      'CREATE INDEX tracking_day_kind ON tracking(day, kind, id)',
    );
    await db.execute("""
      CREATE TABLE nutrition_goals (
        day TEXT PRIMARY KEY NOT NULL, energy INTEGER CHECK(energy BETWEEN 1 AND 20000),
        protein INTEGER CHECK(protein BETWEEN 1 AND 2000), carbs INTEGER CHECK(carbs BETWEEN 1 AND 2000),
        fat INTEGER CHECK(fat BETWEEN 1 AND 2000), water INTEGER CHECK(water BETWEEN 1 AND 20000),
        weight INTEGER CHECK(weight BETWEEN 1000 AND 1000000),
        exercise_credit INTEGER NOT NULL CHECK(exercise_credit IN (0,1))
      )
    """);
  }

  Future<Targets> goals(String day) async {
    final rows = await db.query(
      'nutrition_goals',
      where: 'day <= ?',
      whereArgs: [day],
      orderBy: 'day DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      final legacy = await db.query(
        'preferences',
        where: 'key = ?',
        whereArgs: ['energy'],
      );
      return Targets(
        energy: legacy.isEmpty ? null : legacy.single['value'] as int,
      );
    }
    final row = rows.single;
    return Targets(
      energy: row['energy'] as int?,
      protein: row['protein'] as int?,
      carbs: row['carbs'] as int?,
      fat: row['fat'] as int?,
      water: row['water'] as int?,
      weight: row['weight'] as int?,
      exerciseCredit: row['exercise_credit'] == 1,
    );
  }

  Future<void> saveGoals(String day, Targets goals) async {
    final values = {
      'day': day,
      'energy': goals.energy,
      'protein': goals.protein,
      'carbs': goals.carbs,
      'fat': goals.fat,
      'water': goals.water,
      'weight': goals.weight,
      'exercise_credit': goals.exerciseCredit ? 1 : 0,
    };
    await db.transaction((txn) async {
      await txn.insert(
        'nutrition_goals',
        values,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _queue(txn, 'goals', 'goal:$day', {
        'day': day,
        'calories': goals.energy,
        'protein_mg': _mg(goals.protein),
        'carbs_mg': _mg(goals.carbs),
        'fat_mg': _mg(goals.fat),
        'water_ml': goals.water,
        'weight_grams': goals.weight,
        'exercise_credit': goals.exerciseCredit,
      });
    });
    onChanged?.call();
  }

  Future<List<TrackRecord>> records(String first, String last) async => [
    for (final row in await db.query(
      'tracking',
      where: 'day BETWEEN ? AND ?',
      whereArgs: [first, last],
      orderBy: 'day DESC, id DESC',
    ))
      TrackRecord.fromRow(row),
  ];

  Future<int?> latestWeight(String day) async {
    final rows = await db.query(
      'tracking',
      columns: ['value'],
      where: 'kind=0 AND day<=?',
      whereArgs: [day],
      orderBy: 'day DESC, id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['value'] as int;
  }

  Future<void> save(TrackRecord record) async {
    final values = {
      'kind': record.kind.index,
      'day': record.day,
      'value': record.value,
      'name': record.name,
      'category': record.category,
      'intensity': record.intensity,
      'energy': record.energy,
    };
    await db.transaction((txn) async {
      final int id;
      if (record.id == null) {
        id = await insertSyncedTracker(txn, values);
      } else {
        id = record.id!;
        final changed = await txn.update(
          'tracking',
          values,
          where: 'id=? AND kind=?',
          whereArgs: [id, record.kind.index],
        );
        if (changed != 1) throw StateError('Record no longer exists.');
      }
      await _queue(txn, record.kind.name, 'track:$id', {
        'day': record.day,
        switch (record.kind) {
          TrackKind.weight => 'grams',
          TrackKind.water => 'milliliters',
          TrackKind.exercise => 'minutes',
        }: record.value,
        if (record.kind == TrackKind.exercise) ...{
          'name': record.name,
          'category': record.category,
          'intensity': const {
            'Light': 'light',
            'Moderate': 'moderate',
            'Vigorous': 'vigorous',
          }[record.intensity],
          'energy_kcal': record.energy,
        },
      });
    });
    onChanged?.call();
  }

  Future<void> remove(TrackRecord record) async {
    await db.transaction((txn) async {
      final changed = await txn.delete(
        'tracking',
        where: 'id=? AND kind=?',
        whereArgs: [record.id, record.kind.index],
      );
      if (changed != 1) throw StateError('Record no longer exists.');
      final localId = 'track:${record.id}';
      if (outbox != null && await _mapped(txn, localId)) {
        await outbox!.enqueue(
          txn,
          localId,
          'delete',
          null,
          kind: record.kind.name,
        );
      }
    });
    onChanged?.call();
  }

  Future<void> _queue(
    Transaction txn,
    String kind,
    String localId,
    Map<String, Object?> payload,
  ) async {
    if (outbox == null) return;
    final exists = await _mapped(txn, localId);
    await outbox!.enqueue(
      txn,
      localId,
      exists ? 'update' : 'create',
      payload,
      kind: kind,
    );
  }

  static Future<bool> _mapped(Transaction txn, String id) async =>
      (await txn.query(
        'sync_diary_mapping',
        columns: ['local_id'],
        where: 'local_id = ?',
        whereArgs: [id],
      )).isNotEmpty;

  static int? _mg(int? grams) => grams == null ? null : grams * 1000;
}

Future<int> insertSyncedTracker(
  Transaction txn,
  Map<String, Object?> values,
) async {
  final rows = await txn.rawQuery("""
    SELECT max(id) AS last_id FROM (
      SELECT id FROM tracking
      UNION ALL
      SELECT value FROM preferences WHERE key = 'last-tracker-id'
      UNION ALL
      SELECT CAST(substr(local_id, 7) AS INTEGER) FROM sync_diary_mapping
      WHERE local_id GLOB 'track:[0-9]*'
    )
  """);
  final id = ((rows.single['last_id'] as int?) ?? 0) + 1;
  await txn.insert('preferences', {
    'key': 'last-tracker-id',
    'value': id,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  return txn.insert('tracking', {...values, 'id': id});
}
