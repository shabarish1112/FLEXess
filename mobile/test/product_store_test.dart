import 'dart:convert';
import 'dart:io';

import 'package:fitness_diary/core/diary_store.dart';
import 'package:fitness_diary/core/product_store.dart';
import 'package:fitness_diary/core/tracking_store.dart';
import 'package:fitness_diary/features/diary/domain.dart';
import 'package:fitness_diary/features/profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late DiaryStore diary;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('flex_product_');
    diary = await DiaryStore.open(
      factory: databaseFactoryFfi,
      location: '${dir.path}/diary.db',
    );
  });
  tearDown(() async {
    await diary.db.close();
    await dir.delete(recursive: true);
  });

  test(
    'preferences, notes, favorites and saved meals survive reopening',
    () async {
      final store = ProductStore(diary.db);
      final food = fixture.first;
      await store.savePreferences(
        profileDefaults({
          'name': 'Tester',
          'height': 172.5,
          'theme': 'dark',
          'units': 'imperial',
        }),
      );
      await store.saveNote('2026-11-20', 'A local note');
      await store.favorite(food, selected: true);
      final entry = DiaryEntry(
        'source',
        '2026-11-20',
        Meal.breakfast,
        food,
        food.servings.first,
        1500,
        {},
      );
      await diary.save(entry, editing: false);
      await store.saveMeal('Morning oats', [entry]);
      await diary.db.close();
      diary = await DiaryStore.open(
        factory: databaseFactoryFfi,
        location: '${dir.path}/diary.db',
      );
      final reopened = ProductStore(diary.db);
      expect((await reopened.preferences())['height'], 172.5);
      expect(await reopened.note('2026-11-20'), 'A local note');
      expect((await reopened.favorites()).single.id, food.id);
      final meal = (await reopened.savedMeals()).single;
      await diary.addMeal(
        reopened.mealEntries(
          meal['payload'] as String,
          '2026-11-21',
          Meal.lunch,
        ),
        '2026-11-21',
        Meal.lunch,
      );
      final copy = (await diary.read('2026-11-21')).single;
      expect(copy.quantity, 1500);
      expect(copy.meal, Meal.lunch);
      expect(copy.amounts, (await diary.read('2026-11-20')).single.amounts);
      expect((await reopened.loggedFoods(frequent: true)).single.id, food.id);
      await reopened.favorite(food, selected: false);
      expect(await reopened.favorites(), isEmpty);
      final exported = jsonDecode(await reopened.export()) as Map;
      expect((exported['entries'] as List).length, 2);
      expect(exported.containsKey('sync_outbox'), isFalse);
    },
  );

  test(
    'meal copy rolls back all entries if any serving cannot be recalculated',
    () async {
      final food = fixture.first;
      final valid = DiaryEntry(
        'a',
        '2026-11-20',
        Meal.breakfast,
        food,
        food.servings.first,
        1000,
        {},
      );
      final historical = Food(
        'old',
        'Historical',
        food.per100g,
        food.servings,
        version: 'sync-v1-legacy',
      );
      final invalid = DiaryEntry(
        'b',
        '2026-11-20',
        Meal.breakfast,
        historical,
        historical.servings.first,
        1000,
        {},
      );
      await expectLater(
        diary.addMeal([valid, invalid], '2026-11-21', Meal.dinner),
        throwsStateError,
      );
      expect(await diary.read('2026-11-21'), isEmpty);
      expect(await diary.db.query('drafts'), isEmpty);
    },
  );

  test('invalid profile and note input cannot replace saved data', () async {
    final store = ProductStore(diary.db);
    await store.savePreferences(profileDefaults({'name': 'Original'}));
    await expectLater(
      store.savePreferences(
        profileDefaults({'name': 'Bad', 'height': double.nan}),
      ),
      throwsFormatException,
    );
    await expectLater(store.saveNote('bad', 'note'), throwsFormatException);
    expect((await store.preferences())['name'], 'Original');
  });

  test(
    'local notifications fire only after successful diary and tracker commits',
    () async {
      var diaryChanges = 0, trackerChanges = 0;
      diary.remoteDiaryRevision.addListener(() => diaryChanges++);
      diary.remoteTrackerRevision.addListener(() => trackerChanges++);
      final f = fixture.first;
      await diary.save(
        DiaryEntry(
          'notify',
          '2026-11-20',
          Meal.breakfast,
          f,
          f.servings.first,
          1000,
          {},
        ),
        editing: false,
      );
      expect(diaryChanges, 1);
      await expectLater(
        diary.save(
          DiaryEntry(
            'notify',
            '2026-11-20',
            Meal.breakfast,
            f,
            f.servings.first,
            1000,
            {},
          ),
          editing: false,
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(diaryChanges, 1);
      await diary.tracking.save(
        const TrackRecord(kind: TrackKind.water, day: '2026-11-20', value: 250),
      );
      expect(trackerChanges, 1);
      await expectLater(
        diary.tracking.save(
          const TrackRecord(kind: TrackKind.water, day: '2026-11-20', value: 0),
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(trackerChanges, 1);
    },
  );
}
