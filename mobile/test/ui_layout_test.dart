import 'package:fitness_diary/app.dart';
import 'package:fitness_diary/core/diary_store.dart';
import 'package:fitness_diary/core/tracking_store.dart';
import 'package:fitness_diary/features/tracking.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  for (final config in [
    (const Size(320, 720), 1.0),
    (const Size(390, 844), 2.0),
    (const Size(1440, 960), 1.0),
  ]) {
    testWidgets(
      'home and navigation fit ${config.$1} at text scale ${config.$2}',
      (tester) async {
        tester.view.physicalSize = config.$1;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = config.$2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final store = await tester.runAsync(
          () => DiaryStore.open(
            factory: databaseFactoryFfi,
            location: inMemoryDatabasePath,
          ),
        );
        addTearDown(store!.db.close);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [storeProvider.overrideWith((ref) async => store)],
            child: const FitnessApp(),
          ),
        );
        for (var i = 0; i < 8; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump(const Duration(milliseconds: 150));
        }
        expect(tester.takeException(), isNull);
        expect(
          config.$1.width >= 840
              ? find.byType(NavigationRail)
              : find.byType(NavigationBar),
          findsOneWidget,
        );
        await tester.tap(find.text('Profile').last);
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('saving other targets preserves decimal goal weight', (
    tester,
  ) async {
    final store = await tester.runAsync(
      () => DiaryStore.open(
        factory: databaseFactoryFfi,
        location: inMemoryDatabasePath,
      ),
    );
    addTearDown(store!.db.close);
    await tester.pumpWidget(
      MaterialApp(
        home: GoalsPage(
          store: store.tracking,
          day: '2026-11-20',
          initial: const Targets(weight: 72500),
        ),
      ),
    );
    expect(find.widgetWithText(TextFormField, '72.5'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save goals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save goals'));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    final goals = await tester.runAsync(
      () => store.tracking.goals('2026-11-20'),
    );
    expect(goals!.weight, 72500);
  });
}
