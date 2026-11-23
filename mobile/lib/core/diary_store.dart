import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import '../features/diary/domain.dart';
import 'catalog.dart';
import 'diary_outbox.dart';
import 'diary_projection.dart';
import 'tracking_store.dart';
import 'tracker_projection.dart';
import 'sync_inbox.dart';
import 'guest_transfer.dart';
import 'product_store.dart';

class DiaryStore {
  DiaryStore(this.db) : outbox = null;
  DiaryStore._account(this.db, String id) : outbox = DiaryOutbox(db, id);
  final DiaryOutbox? outbox;
  TrackingStore get tracking => TrackingStore(
    db,
    outbox: outbox,
    onChanged: () => _remoteTrackerRevision.value++,
  );
  final _remoteDiaryRevision = ValueNotifier(0);
  final _remoteTrackerRevision = ValueNotifier(0);
  ValueListenable<int> get remoteTrackerRevision => _remoteTrackerRevision;
  ValueListenable<int> get remoteDiaryRevision => _remoteDiaryRevision;
  SyncInbox? get inbox => outbox == null
      ? null
      : SyncInbox(
          db,
          outbox!.accountId,
          project: (txn, record) => record['kind'] == 'diary'
              ? projectDiary(txn, record)
              : projectTracker(txn, record),
          onCommitted: (kinds) {
            if (kinds.contains('diary')) _remoteDiaryRevision.value++;
            if (kinds.any(trackerKinds.contains)) {
              _remoteTrackerRevision.value++;
            }
          },
        );
  final Database db;

  static Future<DiaryStore> open({
    DatabaseFactory? factory,
    String? location,
    String? accountId,
  }) async {
    if (accountId != null &&
        (location != null ||
            !RegExp(
              r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
            ).hasMatch(accountId))) {
      throw ArgumentError('An account requires its own UUID-named database.');
    }
    final driver = factory ?? databaseFactory;
    final db = await driver.openDatabase(
      location ??
          path.join(
            await driver.getDatabasesPath(),
            accountId == null
                ? 'fitness_diary.db'
                : 'flex_account_$accountId.db',
          ),
      options: OpenDatabaseOptions(
        version: 8,
        onUpgrade: (db, from, _) async {
          if (from < 8) await ProductStore.migrate(db);
          if (from < 2) await _v2(db);
          if (from < 3) await TrackingStore.migrate(db);
          if (from < 4) await DiaryOutbox.migrate(db);
          if (from < 5) await SyncInbox.migrate(db);
          if (from < 7) {
            await GuestTransfer.migrate(db);
            await db.execute("""
              INSERT OR IGNORE INTO preferences(key, value)
              SELECT 'last-tracker-id', max(id) FROM tracking HAVING max(id) > 0
            """);
          }
          if (from >= 5 && from < 7 && accountId != null) {
            await db.delete(
              'sync_cursor',
              where: 'account_id = ?',
              whereArgs: [accountId],
            );
          }
        },
        onCreate: (db, _) async {
          await db.execute("""
            CREATE TABLE entries (
              id TEXT PRIMARY KEY NOT NULL,
              day TEXT NOT NULL,
              meal INTEGER NOT NULL CHECK(meal BETWEEN 0 AND 3),
              food TEXT NOT NULL,
              serving INTEGER NOT NULL CHECK(serving >= 0),
              quantity INTEGER NOT NULL CHECK(quantity BETWEEN 1 AND 100000),
              snapshot TEXT NOT NULL
            )
          """);
          await db.execute(
            'CREATE INDEX entries_day_meal ON entries(day, meal)',
          );
          await db.execute(
            'CREATE TABLE preferences (key TEXT PRIMARY KEY, value INTEGER NOT NULL CHECK(value > 0))',
          );
          await _v2(db);
          await TrackingStore.migrate(db);
          await DiaryOutbox.migrate(db);
          await SyncInbox.migrate(db);
          await GuestTransfer.migrate(db);
          await ProductStore.migrate(db);
        },
      ),
    );
    final store = accountId == null
        ? DiaryStore(db)
        : DiaryStore._account(db, accountId);
    if (factory == null && location == null) {
      try {
        final bundle = await rootBundle.loadString('assets/catalog.json');
        final rows = (jsonDecode(bundle) as List).cast<Map<String, dynamic>>();
        if (rows.isNotEmpty) await store.importCatalog(rows);
      } catch (_) {
        await db.close();
        rethrow;
      }
    }
    return store;
  }

  Future<List<DiaryEntry>> read(String day) async => [
    for (final row in await db.query(
      'entries',
      where: 'day = ?',
      whereArgs: [day],
      orderBy: 'meal, rowid',
    ))
      _entry(row),
  ];

  DiaryEntry _entry(Map<String, Object?> row) {
    final record = row['food_record'] as String?;
    final food = record == null
        ? fixture.firstWhere((item) => item.id == row['food'])
        : foodFromRecord(jsonDecode(record) as Map<String, dynamic>);
    final snapshot =
        jsonDecode(row['snapshot'] as String) as Map<String, dynamic>;
    return DiaryEntry(
      row['id'] as String,
      row['day'] as String,
      Meal.values[row['meal'] as int],
      food,
      food.servings[row['serving'] as int],
      row['quantity'] as int,
      {for (final n in Nutrient.values) n: snapshot[n.name] as int?},
    );
  }

  Future<void> save(DiaryEntry entry, {required bool editing}) async {
    await db.transaction((txn) => _save(txn, entry, editing: editing));
    _remoteDiaryRevision.value++;
  }

  Future<void> _save(
    Transaction txn,
    DiaryEntry entry, {
    required bool editing,
  }) async {
    if (entry.food.version == 'sync-v1-legacy') {
      throw StateError(
        'This historical snapshot has no serving weight for recalculation.',
      );
    }
    final snapshot = entry.food.scale(entry.serving, entry.quantity);
    final values = {
      'id': entry.id,
      'day': entry.day,
      'meal': entry.meal.index,
      'food': entry.food.id,
      'food_record': jsonEncode(foodRecord(entry.food)),
      'serving': entry.food.servings.indexOf(entry.serving),
      'quantity': entry.quantity,
      'snapshot': jsonEncode({
        for (final n in Nutrient.values) n.name: snapshot[n],
      }),
    };
    if (editing) {
      final changed = await txn.update(
        'entries',
        values,
        where: 'id = ?',
        whereArgs: [entry.id],
      );
      if (changed != 1) throw StateError('Entry no longer exists.');
    } else {
      await txn.insert('entries', values);
      await txn.delete('drafts', where: 'id = ?', whereArgs: [entry.id]);
    }
    await outbox?.enqueue(txn, entry.id, editing ? 'update' : 'create', {
      'day': entry.day,
      'meal': entry.meal.name,
      'name': entry.food.name,
      'serving': entry.serving.label,
      'quantity_milli': entry.quantity,
      'serving_grams': entry.serving.grams,
      'per_100g': {
        for (final n in Nutrient.values) n.name: entry.food.per100g[n],
      },
      'nutrients': {for (final n in Nutrient.values) n.name: snapshot[n]},
    });
  }

  Future<void> addMeal(List<DiaryEntry> entries, String day, Meal meal) async {
    if (entries.isEmpty ||
        entries.length > 100 ||
        DateTime.tryParse(day) == null ||
        day.length != 10) {
      throw const FormatException('Choose a valid date and 1–100 foods.');
    }
    final stamp = DateTime.now().microsecondsSinceEpoch;
    await db.transaction((txn) async {
      for (var i = 0; i < entries.length; i++) {
        final e = entries[i];
        await _save(
          txn,
          DiaryEntry('$stamp-$i', day, meal, e.food, e.serving, e.quantity, {}),
          editing: false,
        );
      }
    });
    _remoteDiaryRevision.value++;
  }

  Future<void> remove(String id) async {
    await db.transaction((txn) async {
      if (await txn.delete('entries', where: 'id = ?', whereArgs: [id]) != 1) {
        throw StateError('Entry no longer exists.');
      }
      await outbox?.enqueue(txn, id, 'delete', null);
    });
    _remoteDiaryRevision.value++;
  }

  static Future<void> _v2(DatabaseExecutor db) async {
    await db.execute('ALTER TABLE entries ADD COLUMN food_record TEXT');
    await db.execute("""
      CREATE TABLE drafts (
        id TEXT PRIMARY KEY NOT NULL, day TEXT NOT NULL,
        meal INTEGER NOT NULL CHECK(meal BETWEEN 0 AND 3),
        food_record TEXT NOT NULL, serving INTEGER NOT NULL,
        quantity TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      )
    """);
    await db.execute('CREATE INDEX drafts_day ON drafts(day, updated_at)');
    await db.execute("""
      CREATE TABLE catalog (
        source TEXT NOT NULL, id TEXT NOT NULL, version TEXT NOT NULL,
        name TEXT NOT NULL COLLATE NOCASE, payload TEXT NOT NULL,
        PRIMARY KEY(source, id)
      )
    """);
    await db.execute('CREATE INDEX catalog_name ON catalog(name)');
    for (final food in fixture) {
      await db.insert('catalog', {
        'source': food.source,
        'id': food.id,
        'version': food.version,
        'name': food.name,
        'payload': jsonEncode(foodRecord(food)),
      });
      await db.update(
        'entries',
        {'food_record': jsonEncode(foodRecord(food))},
        where: 'food = ?',
        whereArgs: [food.id],
      );
    }
  }

  Future<List<Food>> search(String query) async {
    final term = query.trim().toLowerCase();
    final prefix = term
        .replaceAll('!', '!!')
        .replaceAll('%', '!%')
        .replaceAll('_', '!_');
    final rows = await db.rawQuery(
      """
      SELECT payload FROM catalog
      WHERE name LIKE ? ESCAPE '!'
      AND (source <> 'Synthetic development data' OR NOT EXISTS (SELECT 1 FROM catalog WHERE source = 'USDA FoodData Central'))
      ORDER BY CASE WHEN name = ? COLLATE NOCASE THEN 0
                    WHEN name LIKE ? ESCAPE '!' THEN 1 ELSE 2 END, name
      LIMIT 100
    """,
      ['%$prefix%', term, '$prefix%'],
    );
    return [
      for (final row in rows)
        foodFromRecord(
          jsonDecode(row['payload'] as String) as Map<String, dynamic>,
        ),
    ];
  }

  Future<void> importCatalog(List<Map<String, dynamic>> records) async {
    await db.transaction((txn) async {
      final seen = <(String, String)>{};
      for (final record in records) {
        final food = foodFromRecord(record);
        if (food.id.isEmpty ||
            food.name.trim().isEmpty ||
            food.source.isEmpty ||
            food.version.isEmpty ||
            !seen.add((food.source, food.id)) ||
            food.servings.isEmpty ||
            food.servings.any((s) => s.grams < 1 || s.grams > 10000) ||
            food.per100g.values.any(
              (v) => v != null && (v < 0 || v > 1000000),
            )) {
          throw const FormatException('Invalid or duplicate catalog record.');
        }
        await txn.insert('catalog', {
          'source': food.source,
          'id': food.id,
          'version': food.version,
          'name': food.name,
          'payload': jsonEncode(record),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<Draft>> drafts(String day) async => [
    for (final row in await db.query(
      'drafts',
      where: 'day = ?',
      whereArgs: [day],
      orderBy: 'updated_at DESC',
    ))
      _draft(row),
  ];

  Draft _draft(Map<String, Object?> row) {
    final food = foodFromRecord(
      jsonDecode(row['food_record'] as String) as Map<String, dynamic>,
    );
    final index = row['serving'] as int;
    return Draft(
      row['id'] as String,
      row['day'] as String,
      Meal.values[row['meal'] as int],
      food,
      index >= 0 && index < food.servings.length
          ? food.servings[index]
          : food.servings.first,
      row['quantity'] as String,
    );
  }

  Future<void> saveDraft(Draft draft) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.rawInsert(
      """
      INSERT INTO drafts (id, day, meal, food_record, serving, quantity, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET day=excluded.day, meal=excluded.meal,
        food_record=excluded.food_record, serving=excluded.serving,
        quantity=excluded.quantity, updated_at=excluded.updated_at
    """,
      [
        draft.id,
        draft.day,
        draft.meal.index,
        jsonEncode(foodRecord(draft.food)),
        draft.food.servings.indexOf(draft.serving),
        draft.quantity,
        now,
        now,
      ],
    );
  }

  Future<void> discard(String id) async {
    await db.delete('drafts', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<DiaryEntry>> history(String first, String last) async => [
    for (final row in await db.query(
      'entries',
      where: 'day BETWEEN ? AND ?',
      whereArgs: [first, last],
    ))
      _entry(row),
  ];

  Future<int?> goal() async {
    final rows = await db.query(
      'preferences',
      where: 'key = ?',
      whereArgs: ['energy'],
    );
    return rows.isEmpty ? null : rows.single['value'] as int;
  }

  Future<void> setGoal(int goal) async {
    if (goal <= 0) throw ArgumentError.value(goal);
    await db.insert('preferences', {
      'key': 'energy',
      'value': goal,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
