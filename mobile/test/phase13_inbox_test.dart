import 'dart:io';

import 'package:fitness_diary/core/diary_store.dart';
import 'package:fitness_diary/core/sync_inbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, dynamic> change(
  int sequence,
  int revision, {
  bool deleted = false,
}) => {
  'sequence': sequence,
  'record': {
    'id': '25fc8bd4-b696-4da3-a1ea-4b9a10315f53',
    'kind': 'weight',
    'revision': revision,
    'deleted': deleted,
    'payload': deleted ? null : {'day': '2026-11-17', 'grams': 70000},
  },
};

void main() {
  sqfliteFfiInit();
  test(
    'inbox persists cursors and tombstones and rolls back incomplete pages',
    () async {
      final temp = await Directory.systemTemp.createTemp('flex-inbox-');
      addTearDown(() => temp.delete(recursive: true));
      final file = '${temp.path}/test.db';
      Future<DiaryStore> open() =>
          DiaryStore.open(factory: databaseFactoryFfi, location: file);
      var store = await open();
      var inbox = SyncInbox(store.db, 'first');
      expect(await inbox.apply([change(1, 1)]), 1);
      await expectLater(
        inbox.apply([change(2, 2), change(4, 3)]),
        throwsFormatException,
      );
      expect(await inbox.cursor(), 1);
      expect(
        (await store.db.query('sync_remote_record')).single['revision'],
        1,
      );
      await store.db.close();
      store = await open();
      addTearDown(store.db.close);
      inbox = SyncInbox(store.db, 'first');
      expect(await inbox.apply([change(1, 1), change(2, 2, deleted: true)]), 2);
      expect(
        (await store.db.query('sync_remote_record')).single['record'],
        contains('"deleted":true'),
      );
      expect(await SyncInbox(store.db, 'second').cursor(), 0);
    },
  );
}
