import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../features/diary/domain.dart';
import 'catalog.dart';
import 'diary_store.dart';
import 'tracking_store.dart';

class GuestTransfer {
  GuestTransfer(this.guest, this.account) {
    if (guest.outbox != null ||
        account.outbox == null ||
        identical(guest.db, account.db)) {
      throw ArgumentError(
        'Transfer requires distinct guest and account stores.',
      );
    }
  }

  final DiaryStore guest, account;

  static Future<void> migrate(DatabaseExecutor db) => db.execute('''
    CREATE TABLE guest_transfer (
      source_key TEXT PRIMARY KEY NOT NULL,
      operation_id TEXT NOT NULL REFERENCES sync_outbox(operation_id)
    )
  ''');

  // A preview contains the exact source snapshots approved by the user.
  Future<Map<String, List<Map<String, Object?>>>> preview() =>
      guest.db.transaction((txn) async {
        final trackers = await txn.query('tracking');
        return {
          'diary': await txn.query('entries'),
          'goals': await txn.query('nutrition_goals'),
          for (final kind in TrackKind.values)
            kind.name: trackers
                .where((row) => row['kind'] == kind.index)
                .toList(),
        };
      });

  Future<int> stage(
    Map<String, List<Map<String, Object?>>> snapshots,
    Set<String> selected,
    String? Function() activeAccount,
  ) async {
    final outbox = account.outbox!;
    if (activeAccount() != outbox.accountId) {
      throw StateError('Account changed.');
    }
    return account.db.transaction((txn) async {
      var count = 0;
      for (final kind in selected) {
        for (final row in snapshots[kind] ?? const <Map<String, Object?>>[]) {
          if (activeAccount() != outbox.accountId) {
            throw StateError('Account changed.');
          }
          final source = '$kind:${row['id'] ?? row['day']}';
          if ((await txn.query(
            'guest_transfer',
            where: 'source_key = ?',
            whereArgs: [source],
          )).isNotEmpty) {
            continue;
          }
          final String localId;
          final Map<String, Object?> body;
          if (kind == 'diary') {
            localId = 'guest:${row['id']}';
            final raw = row['food_record'];
            final food = raw is String
                ? foodFromRecord(jsonDecode(raw) as Map<String, dynamic>)
                : fixture.firstWhere((food) => food.id == row['food']);
            final serving = food.servings[row['serving'] as int];
            body = {
              'day': row['day'],
              'meal': Meal.values[row['meal'] as int].name,
              'name': food.name,
              'serving': serving.label,
              'serving_grams': serving.grams,
              'quantity_milli': row['quantity'],
              'nutrients': jsonDecode(row['snapshot'] as String),
              'per_100g': {
                for (final n in Nutrient.values) n.name: food.per100g[n],
              },
            };
            await txn.insert('entries', {...row, 'id': localId});
          } else if (kind == 'goals') {
            final day = row['day'];
            localId = 'goal:$day';
            // Leave account goals intact when both profiles have a goal for this date.
            if ((await txn.query(
                  'nutrition_goals',
                  where: 'day = ?',
                  whereArgs: [day],
                )).isNotEmpty ||
                (await txn.query(
                  'sync_diary_mapping',
                  where: 'local_id = ?',
                  whereArgs: [localId],
                )).isNotEmpty) {
              throw StateError(
                'Account has a conflicting goal date. Deselect goals to continue.',
              );
            }
            int? mg(String key) =>
                row[key] == null ? null : (row[key] as int) * 1000;
            body = {
              'day': day,
              'calories': row['energy'],
              'protein_mg': mg('protein'),
              'carbs_mg': mg('carbs'),
              'fat_mg': mg('fat'),
              'water_ml': row['water'],
              'weight_grams': row['weight'],
              'exercise_credit': row['exercise_credit'] == 1,
            };
            await txn.insert('nutrition_goals', row);
          } else {
            final values = {...row}..remove('id');
            final id = await insertSyncedTracker(txn, values);
            localId = 'track:$id';
            body = {
              'day': row['day'],
              switch (kind) {
                'weight' => 'grams',
                'water' => 'milliliters',
                'exercise' => 'minutes',
                _ => throw const FormatException('Unsupported guest record.'),
              }: row['value'],
              if (kind == 'exercise') ...{
                'name': row['name'],
                'category': row['category'],
                'energy_kcal': row['energy'],
                'intensity': const {
                  'Light': 'light',
                  'Moderate': 'moderate',
                  'Vigorous': 'vigorous',
                }[row['intensity']],
              },
            };
          }
          await outbox.enqueue(txn, localId, 'create', body, kind: kind);
          final operation = (await txn.query(
            'sync_outbox',
            columns: ['operation_id'],
            where: 'local_id = ? AND account_id = ?',
            whereArgs: [localId, outbox.accountId],
          )).single;
          await txn.insert('guest_transfer', {
            'source_key': source,
            ...operation,
          });
          count++;
        }
      }
      if (activeAccount() != outbox.accountId) {
        throw StateError('Account changed.');
      }
      return count;
    });
  }

  Future<Map<String, int>> status() async => {
    for (final row in await account.db.rawQuery(
      '''
      SELECT status, COUNT(*) AS count
      FROM guest_transfer JOIN sync_outbox USING (operation_id)
      WHERE account_id = ? GROUP BY status
    ''',
      [account.outbox!.accountId],
    ))
      row['status'] as String: row['count'] as int,
  };
}
