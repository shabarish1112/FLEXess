import 'dart:convert';
import 'dart:io';

import 'package:fitness_diary/core/diary_store.dart';
import 'package:fitness_diary/features/diary/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_diary/features/tracking.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const account = '25fc8bd4-b696-4da3-a1ea-4b9a10315f53';
const day = '2026-11-17';

Map<String, dynamic> receipt(
  Map<String, dynamic> operation,
  int sequence,
  int revision,
) => {
  'sequence': sequence,
  'operation_id': operation['operation_id'],
  'record': {
    'id': operation['record_id'],
    'kind': 'diary',
    'revision': revision,
    'updated_at': '2026-11-17T11:22:00Z',
    'deleted': operation['action'] == 'delete',
    'payload': operation['payload'],
  },
};

void main() {
  sqfliteFfiInit();
  testWidgets(
    'open Progress refreshes only after a committed remote diary page',
    (tester) async {
      final store = (await tester.runAsync(() async {
        final root = await Directory.systemTemp.createTemp('flex-progress-');
        final factory = databaseFactoryFfi;
        final originalPath = await factory.getDatabasesPath();
        await factory.setDatabasesPath(root.path);
        final store = await DiaryStore.open(
          factory: factory,
          accountId: account,
        );
        addTearDown(() async {
          await store.db.close();
          await factory.setDatabasesPath(originalPath);
          await root.delete(recursive: true);
        });
        return store;
      }))!;
      final inbox = store.inbox!;
      Map<String, dynamic> change(int sequence, int? energy) => receipt(
        {
          'record_id': '35fc8bd4-b696-4da3-a1ea-4b9a10315f53',
          'action': energy == null ? 'delete' : 'update',
          'payload': energy == null
              ? null
              : {
                  'day': day,
                  'meal': 'breakfast',
                  'name': 'Synthetic oats',
                  'serving': '40 g',
                  'serving_grams': 40,
                  'quantity_milli': energy == 152000 ? 1000 : 2000,
                  'nutrients': {'energy': energy, 'fat': null},
                  'per_100g': {'energy': 380000, 'fat': null},
                },
        },
        sequence,
        sequence,
      );
      Future<void> settleText(Finder target) async {
        for (
          var attempt = 0;
          attempt < 10 && target.evaluate().isEmpty;
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(target, findsOneWidget);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: ProgressPage(diary: store, end: DateTime.parse(day)),
        ),
      );
      await settleText(find.text('No records in this range.'));
      await tester.runAsync(() => inbox.apply([change(1, 152000)]));
      await settleText(find.textContaining('Calories: 152.0 kcal'));
      await tester.runAsync(() => inbox.apply([change(2, 304000)]));
      await settleText(find.textContaining('Calories: 304.0 kcal'));

      await tester.runAsync(() async {
        await expectLater(
          inbox.apply([change(3, 152000), change(5, null)]),
          throwsFormatException,
        );
        expect(await inbox.cursor(), 2);
      });
      await tester.pump();
      expect(store.remoteDiaryRevision.value, 2);
      expect(find.textContaining('Calories: 304.0 kcal'), findsOneWidget);
      await tester.runAsync(() => inbox.apply([change(3, null)]));
      await settleText(find.text('No records in this range.'));
      expect(store.remoteDiaryRevision.value, 3);
    },
  );

  test(
    'independent account databases project snapshots, preserve edits and apply tombstones',
    () async {
      final root = await Directory.systemTemp.createTemp('flex-project-');
      final factory = databaseFactoryFfi;
      final originalPath = await factory.getDatabasesPath();
      addTearDown(() async {
        await factory.setDatabasesPath(originalPath);
        await root.delete(recursive: true);
      });
      Future<DiaryStore> client(String name) async {
        final location = await Directory('${root.path}/$name').create();
        await factory.setDatabasesPath(location.path);
        final store = await DiaryStore.open(
          factory: factory,
          accountId: account,
        );
        addTearDown(store.db.close);
        return store;
      }

      final a = await client('a');
      final b = await client('b');
      final food = fixture[1];
      await a.save(
        DiaryEntry(
          'entry',
          day,
          Meal.breakfast,
          food,
          food.servings.first,
          2000,
          {},
        ),
        editing: false,
      );
      final queued = (await a.db.query('sync_outbox')).single['body'] as String;
      final create = receipt(jsonDecode(queued) as Map<String, dynamic>, 1, 1);
      expect(await b.inbox!.apply([create]), 1);
      expect(await b.inbox!.apply([create]), 1);
      final projected = (await b.read(day)).single;
      expect(projected.amounts, (await a.read(day)).single.amounts);
      expect(projected.quantity, 2000);
      expect(projected.meal, Meal.breakfast);

      final remote = create['record'] as Map<String, dynamic>;
      final invalid = {
        ...create,
        'sequence': 3,
        'record': {...remote, 'revision': 3, 'updated_at': 'bad'},
      };
      await expectLater(
        b.inbox!.apply([
          {
            ...create,
            'sequence': 2,
            'record': {...remote, 'revision': 2},
          },
          invalid,
        ]),
        throwsFormatException,
      );
      expect(await b.inbox!.cursor(), 1);
      expect((await b.db.query('sync_diary_mapping')).single['revision'], 1);

      await b.save(
        DiaryEntry(
          projected.id,
          day,
          projected.meal,
          projected.food,
          projected.serving,
          3000,
          {},
        ),
        editing: true,
      );
      final tombstone = {
        ...create,
        'sequence': 2,
        'record': {...remote, 'revision': 2, 'deleted': true, 'payload': null},
      };
      await b.inbox!.apply([tombstone]);
      expect((await b.read(day)).single.quantity, 3000);
      expect((await b.db.query('sync_remote_record')).single['conflict'], 1);

      final c = await client('c');
      await c.inbox!.apply([create, tombstone]);
      expect(await c.read(day), isEmpty);
      expect((await c.db.query('sync_diary_mapping')).single['revision'], 2);
    },
  );
}
