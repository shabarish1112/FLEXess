import 'package:flutter/material.dart';
import 'package:fitness_diary/features/tracking.dart';
import 'dart:convert';
import 'dart:io';
import 'package:fitness_diary/core/catalog.dart';
import 'package:fitness_diary/core/diary_store.dart';
import 'package:fitness_diary/core/tracking_store.dart';
import 'package:fitness_diary/features/diary/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const day = '2026-11-17';

void main() {
  sqfliteFfiInit();

  test('canonical unit conversions and net exercise estimates', () {
    expect(weightGrams(154.3236, pounds: true), 70000);
    expect(waterMilliliters(8, ounces: true), 237);
    expect(exerciseEstimate(30, 70000, 'Moderate'), 147);
    expect(exerciseEstimate(30, null, 'Moderate'), isNull);
    expect(exerciseEstimate(30, 70000, 'Unspecified'), isNull);
  });

  test(
    'goals and all tracking kinds persist, edit and delete across dates',
    () async {
      final dir = await Directory.systemTemp.createTemp('flex_track_');
      addTearDown(() => dir.delete(recursive: true));
      final location = path.join(dir.path, 'tracker.db');
      var diary = await DiaryStore.open(
        factory: databaseFactoryFfi,
        location: location,
      );
      var store = TrackingStore(diary.db);
      await diary.setGoal(1800);
      await store.saveGoals(
        day,
        const Targets(
          energy: 2000,
          protein: 120,
          carbs: 230,
          fat: 70,
          water: 2200,
          weight: 68000,
          exerciseCredit: true,
        ),
      );
      expect((await store.goals('2026-11-16')).energy, 1800);
      await store.save(
        const TrackRecord(kind: TrackKind.weight, day: day, value: 70000),
      );
      await store.save(
        const TrackRecord(kind: TrackKind.weight, day: day, value: 71000),
      );
      await store.save(
        const TrackRecord(kind: TrackKind.water, day: day, value: 250),
      );
      await store.save(
        const TrackRecord(
          kind: TrackKind.exercise,
          day: day,
          value: 30,
          name: 'Walk',
          category: 'Cardio',
          energy: 147,
        ),
      );
      await expectLater(
        store.save(
          const TrackRecord(
            kind: TrackKind.exercise,
            day: day,
            value: 0,
            name: 'Invalid',
          ),
        ),
        throwsA(isA<DatabaseException>()),
      );
      await diary.db.close();
      diary = await DiaryStore.open(
        factory: databaseFactoryFfi,
        location: location,
      );
      addTearDown(diary.db.close);
      store = TrackingStore(diary.db);
      expect((await store.goals('2026-11-18')).protein, 120);
      expect(await store.latestWeight(day), 71000);
      final rows = await store.records(day, day);
      expect(rows.length, 4);
      expect(await store.records('2026-11-18', '2026-11-18'), isEmpty);
      final water = rows.singleWhere((r) => r.kind == TrackKind.water);
      await store.save(
        TrackRecord(id: water.id, kind: water.kind, day: day, value: 500),
      );
      expect(
        (await store.records(
          day,
          day,
        )).singleWhere((r) => r.id == water.id).value,
        500,
      );
      for (final row in rows) {
        await store.remove(row);
      }
      expect(await store.records(day, day), isEmpty);
      expect(await diary.read(day), isEmpty);
    },
  );

  test(
    'upgrades a populated v2 file without clearing draft, entry or goal',
    () async {
      final dir = await Directory.systemTemp.createTemp('flex_v2_to_v3_');
      addTearDown(() => dir.delete(recursive: true));
      final file = path.join(dir.path, 'diary.db');
      final old = await DiaryStore.open(
        factory: databaseFactoryFfi,
        location: file,
      );
      final food = fixture.first;
      await old.save(
        DiaryEntry(
          'entry',
          day,
          Meal.breakfast,
          food,
          food.servings.first,
          1000,
          {},
        ),
        editing: false,
      );
      await old.saveDraft(
        Draft('draft', day, Meal.lunch, food, food.servings.last, '2'),
      );
      await old.setGoal(1900);
      // Recreate the schema state left by Phase 9 on this isolated fixture.
      await old.db.execute('DROP TABLE tracking');
      await old.db.execute('DROP TABLE nutrition_goals');
      await old.db.execute('DROP TABLE sync_outbox');
      await old.db.execute('DROP TABLE sync_diary_mapping');
      await old.db.execute('DROP TABLE sync_cursor');
      await old.db.execute('DROP TABLE sync_remote_record');
      await old.db.execute('DROP TABLE guest_transfer');
      for (final table in [
        'app_settings',
        'food_favorites',
        'saved_meals',
        'day_notes',
      ]) {
        await old.db.execute('DROP TABLE $table');
      }
      await old.db.setVersion(2);
      await old.db.close();
      final upgraded = await DiaryStore.open(
        factory: databaseFactoryFfi,
        location: file,
      );
      addTearDown(upgraded.db.close);
      expect(await upgraded.db.getVersion(), 8);
      expect(await upgraded.db.query('sync_outbox'), isEmpty);
      expect((await upgraded.read(day)).single.id, 'entry');
      expect((await upgraded.drafts(day)).single.quantity, '2');
      expect((await TrackingStore(upgraded.db).goals(day)).energy, 1900);
    },
  );

  test(
    'official catalog searches offline and suppresses development fixtures',
    () async {
      final rows =
          (jsonDecode(File('assets/catalog.json').readAsStringSync()) as List)
              .cast<Map<String, dynamic>>();
      expect(rows.length, greaterThan(300));
      final dir = await Directory.systemTemp.createTemp('flex_real_catalog_');
      addTearDown(() => dir.delete(recursive: true));
      final file = path.join(dir.path, 'catalog.db');
      var store = await DiaryStore.open(
        factory: databaseFactoryFfi,
        location: file,
      );
      await store.importCatalog(rows);
      final results = await store.search('bananas');
      final food = results.firstWhere((item) => item.id == 'usda:1105314');
      expect(food.source, 'USDA FoodData Central');
      expect(food.servings.any((s) => s.grams == 115), isTrue);
      final serving = food.servings.firstWhere((s) => s.grams == 115);
      expect(food.scale(serving, 2000)[Nutrient.energy], 223100);
      expect(await store.search('sample rolled oats'), isEmpty);
      await store.db.close();
      store = await DiaryStore.open(
        factory: databaseFactoryFfi,
        location: file,
      );
      addTearDown(store.db.close);
      final oats = (await store.search(
        'Oats, whole grain, rolled, old fashioned',
      )).first;
      expect(oats.id, 'usda:2346396');
      expect(oats.per100g[Nutrient.fiber], isNull);
      final watch = Stopwatch()..start();
      for (var i = 0; i < 20; i++) {
        await store.search(i.isEven ? 'rice' : 'oats');
      }
      stdout.writeln(
        'Catalog measurement: ${File(file).lengthSync()} SQLite bytes; ${watch.elapsedMilliseconds} ms for 20 local queries.',
      );
    },
  );

  testWidgets('Progress displays stored weight, water, exercise and food', (
    tester,
  ) async {
    final diary = (await tester.runAsync(() async {
      final storage = await DiaryStore.open(
        factory: databaseFactoryFfi,
        location: inMemoryDatabasePath,
      );
      final log = TrackingStore(storage.db);
      await log.save(
        const TrackRecord(kind: TrackKind.weight, day: day, value: 72000),
      );
      await log.save(
        const TrackRecord(kind: TrackKind.water, day: day, value: 400),
      );
      await log.save(
        const TrackRecord(
          kind: TrackKind.exercise,
          day: day,
          value: 30,
          name: 'Walk',
        ),
      );
      final food = fixture.first;
      await storage.save(
        DiaryEntry(
          'entry',
          day,
          Meal.breakfast,
          food,
          food.servings.first,
          1000,
          {},
        ),
        editing: false,
      );
      return storage;
    }))!;
    addTearDown(diary.db.close);
    await tester.pumpWidget(
      MaterialApp(
        home: ProgressPage(diary: diary, end: DateTime.parse(day)),
      ),
    );
    for (var attempt = 0; attempt < 6; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Weight trend'), findsOneWidget);
    expect(find.text('2026-11-17 · 72.00 kg'), findsOneWidget);
    expect(find.textContaining('Calories: 152.0 kcal'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Water: 400 mL'), 180);
    await tester.pumpAndSettle();
    expect(find.text('Water: 400 mL'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Exercise: 30 min'), 100);
    await tester.pumpAndSettle();
    expect(find.text('Exercise: 30 min'), findsOneWidget);
  });
}
