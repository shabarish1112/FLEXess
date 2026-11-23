import 'dart:io';
import 'package:fitness_diary/app.dart';
import 'package:fitness_diary/core/catalog.dart';
import 'package:fitness_diary/core/diary_store.dart';
import 'package:fitness_diary/features/diary/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const day = '2026-11-16';
DiaryEntry sample(
  String id, {
  int quantity = 1000,
  Meal meal = Meal.breakfast,
}) {
  final food = fixture.first;
  return DiaryEntry(id, day, meal, food, food.servings.first, quantity, {});
}

class FailOnceStore extends DiaryStore {
  FailOnceStore(super.db);
  bool failNext = true;

  @override
  Future<void> save(DiaryEntry entry, {required bool editing}) {
    if (failNext) {
      failNext = false;
      return Future<void>.error(StateError('synthetic write failure'));
    }
    return super.save(entry, editing: editing);
  }
}

void main() {
  sqfliteFfiInit();
  test('scales quantity and serving, validates and preserves missing', () {
    final food = fixture.first;
    expect(food.scale(food.servings.first, 500)[Nutrient.energy], 76000);
    expect(food.scale(food.servings.first, 2000)[Nutrient.energy], 304000);
    expect(food.scale(food.servings.last, 1000)[Nutrient.energy], 380000);
    expect(
      fixture[1].scale(fixture[1].servings.first, 1000)[Nutrient.fat],
      isNull,
    );
    expect(parseQuantity('0.5'), 500);
    for (final bad in ['0', '-2', '1.0012', 'NaN', '101']) {
      expect(parseQuantity(bad), isNull);
    }
    expect(diaryDate(DateTime(2026, 12, 32)), '2027-01-01');
  });

  test(
    'commits snapshots, rejects duplicates, reloads on reopen, edits and deletes',
    () async {
      final folder = await Directory.systemTemp.createTemp('fitness_store_');
      addTearDown(() => folder.delete(recursive: true));
      final location = path.join(folder.path, 'diary.db');
      var store = await DiaryStore.open(
        factory: databaseFactoryFfi,
        location: location,
      );
      await store.save(sample('a'), editing: false);
      await store.save(sample('b', meal: Meal.dinner), editing: false);
      await expectLater(
        store.save(sample('a'), editing: false),
        throwsA(isA<DatabaseException>()),
      );
      await store.db.close();
      store = await DiaryStore.open(
        factory: databaseFactoryFfi,
        location: location,
      );
      addTearDown(store.db.close);
      expect(total(await store.read(day), Nutrient.energy).known, 304000);
      expect(await store.read('2026-11-17'), isEmpty);
      await store.save(sample('a', quantity: 2000), editing: true);
      expect(total(await store.read(day), Nutrient.energy).known, 456000);
      await store.remove('a');
      expect(total(await store.read(day), Nutrient.energy).known, 152000);
    },
  );

  test(
    'drafts persist independently and catalog refresh keeps entry snapshots',
    () async {
      final folder = await Directory.systemTemp.createTemp('flex_draft_');
      addTearDown(() => folder.delete(recursive: true));
      final file = path.join(folder.path, 'diary.db');
      var store = await DiaryStore.open(
        factory: databaseFactoryFfi,
        location: file,
      );
      final food = fixture.first;
      await store.saveDraft(
        Draft('draft', day, Meal.lunch, food, food.servings.last, '2.5'),
      );
      expect(await store.read(day), isEmpty);
      await store.db.close();
      store = await DiaryStore.open(
        factory: databaseFactoryFfi,
        location: file,
      );
      addTearDown(store.db.close);
      final draft = (await store.drafts(day)).single;
      expect(draft.quantity, '2.5');
      expect(draft.serving.grams, 100);
      expect(draft.meal, Meal.lunch);
      expect((await store.search('sample rolled')).single.id, food.id);
      final entry = DiaryEntry(
        draft.id,
        day,
        draft.meal,
        draft.food,
        draft.serving,
        2500,
        {},
      );
      await store.save(entry, editing: false);
      expect(await store.drafts(day), isEmpty);
      await expectLater(
        store.save(entry, editing: false),
        throwsA(isA<DatabaseException>()),
      );
      final revision = Map<String, dynamic>.from(foodRecord(food))
        ..['name'] = 'Updated oats'
        ..['version'] = 'fixture-2';
      await store.importCatalog([revision]);
      expect((await store.search('updated')).single.version, 'fixture-2');
      expect((await store.read(day)).single.food.name, food.name);
      await expectLater(
        store.importCatalog([revision, revision]),
        throwsFormatException,
      );
      await store.saveDraft(draft);
      await store.discard(draft.id);
      expect(await store.drafts(day), isEmpty);
    },
  );

  testWidgets('search, preview and successful save navigate back to diary', (
    tester,
  ) async {
    final store = await tester.runAsync(
      () => DiaryStore.open(
        factory: databaseFactoryFfi,
        location: inMemoryDatabasePath,
      ),
    );
    final wrapped = FailOnceStore(store!.db);
    addTearDown(store.db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storeProvider.overrideWith((ref) async => wrapped)],
        child: const FitnessApp(),
      ),
    );
    Future<void> settleDb() async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump(const Duration(milliseconds: 350));
      }
    }

    await settleDb();
    await tester.ensureVisible(find.text('Open diary'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open diary'));
    await settleDb();
    await tester.ensureVisible(find.byTooltip('Add food to breakfast'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add food to breakfast'));
    await settleDb();
    await tester.enterText(find.byType(TextField), 'oats');
    await tester.pump(const Duration(milliseconds: 250));
    await settleDb();
    await tester.tap(find.text('Sample rolled oats'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '2');
    await tester.pumpAndSettle();
    expect(find.textContaining('304 kcal'), findsOneWidget);
    await tester.ensureVisible(find.text('Add to diary'));
    await tester.tap(find.text('Add to diary'));
    await settleDb();
    expect(
      find.text('Could not save. Your changes are still here.'),
      findsOneWidget,
    );
    expect(find.text('Serving preview'), findsOneWidget);
    expect(find.textContaining('304 kcal'), findsOneWidget);
    await tester.ensureVisible(find.text('Add to diary'));
    await tester.tap(find.text('Add to diary'));
    await settleDb();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(find.text('Sample rolled oats'), findsOneWidget);
  });
}
