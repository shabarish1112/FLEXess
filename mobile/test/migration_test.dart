import 'dart:io';
import 'package:fitness_diary/core/diary_store.dart';
import 'package:fitness_diary/features/diary/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  test('upgrade preserves v1 entries and goals', () async {
    final dir = await Directory.systemTemp.createTemp('flex_migration_');
    addTearDown(() => dir.delete(recursive: true));
    final file = path.join(dir.path, 'v1.sqlite');
    final old = await databaseFactoryFfi.openDatabase(
      file,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE entries (id TEXT PRIMARY KEY, day TEXT, meal INTEGER, food TEXT, serving INTEGER, quantity INTEGER, snapshot TEXT)',
          );
          await db.execute(
            'CREATE TABLE preferences (key TEXT PRIMARY KEY, value INTEGER)',
          );
          await db.insert('entries', {
            'id': 'keep',
            'day': '2026-11-17',
            'meal': 0,
            'food': 'oats',
            'serving': 0,
            'quantity': 1000,
            'snapshot': '{"energy":152000,"fat":null}',
          });
          await db.insert('preferences', {'key': 'energy', 'value': 1900});
        },
      ),
    );
    await old.close();
    final store = await DiaryStore.open(
      factory: databaseFactoryFfi,
      location: file,
    );
    addTearDown(store.db.close);
    final entry = (await store.read('2026-11-17')).single;
    expect(entry.id, 'keep');
    expect(entry.amounts[Nutrient.energy], 152000);
    expect(entry.amounts[Nutrient.fat], isNull);
    expect(await store.goal(), 1900);
    expect(await store.drafts('2026-11-17'), isEmpty);
  });
}
