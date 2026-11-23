import 'dart:io';

import 'package:fitness_diary/core/diary_outbox.dart';
import 'package:fitness_diary/core/diary_store.dart';
import 'package:fitness_diary/core/guest_transfer.dart';
import 'package:fitness_diary/core/tracking_store.dart';
import 'package:fitness_diary/features/diary/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _account = '25fc8bd4-b696-4da3-a1ea-4b9a10315f53';
const _day = '2026-11-17';

void main() {
  sqfliteFfiInit();
  test(
    'guest transfer rolls back atomically and keeps durable acknowledged and pending work',
    () async {
      final directory = await Directory.systemTemp.createTemp('flex-transfer-');
      final factory = databaseFactoryFfi;
      final old = await factory.getDatabasesPath();
      await factory.setDatabasesPath(directory.path);
      addTearDown(() async {
        await factory.setDatabasesPath(old);
        await directory.delete(recursive: true);
      });
      final guest = await DiaryStore.open(factory: factory);
      addTearDown(guest.db.close);
      var account = await DiaryStore.open(
        factory: factory,
        accountId: _account,
      );
      addTearDown(() => account.db.close());
      final food = fixture.first;
      await guest.save(
        DiaryEntry(
          'original',
          _day,
          Meal.breakfast,
          food,
          food.servings.first,
          1000,
          {},
        ),
        editing: false,
      );
      await guest.tracking.save(
        const TrackRecord(kind: TrackKind.water, day: _day, value: 300),
      );
      var transfer = GuestTransfer(guest, account);
      final snapshots = await transfer.preview();
      await account.db.execute("""
      CREATE TRIGGER fail_transfer BEFORE INSERT ON sync_outbox
      WHEN NEW.local_id LIKE 'track:%'
      BEGIN SELECT RAISE(ABORT, 'fixture failure'); END
    """);
      await expectLater(
        transfer.stage(snapshots, {'diary', 'water'}, () => _account),
        throwsA(isA<DatabaseException>()),
      );
      expect(await account.read(_day), isEmpty);
      expect(await transfer.status(), isEmpty);
      await account.db.execute('DROP TRIGGER fail_transfer');
      expect(
        await transfer.stage(snapshots, {'diary', 'water'}, () => _account),
        2,
      );
      await account.outbox!.drain(
        signedInAccount: () => _account,
        submit: (_, body) async => SyncResult(
          body['kind'] == 'diary' ? Delivery.acknowledged : Delivery.retry,
        ),
      );
      expect(await transfer.status(), {'acknowledged': 1, 'pending': 1});
      await account.db.close();
      account = await DiaryStore.open(factory: factory, accountId: _account);
      transfer = GuestTransfer(guest, account);
      expect(await transfer.status(), {'acknowledged': 1, 'pending': 1});
      expect(
        await transfer.stage(snapshots, {'diary', 'water'}, () => _account),
        0,
      );
      expect(
        (await account.read(_day)).single.amounts,
        (await guest.read(_day)).single.amounts,
      );
      final before = (await guest.tracking.records(_day, _day)).single;
      expect(before.value, 300);
      await guest.tracking.remove(before);
      await guest.tracking.save(
        const TrackRecord(kind: TrackKind.water, day: _day, value: 450),
      );
      final after = (await guest.tracking.records(_day, _day)).single;
      expect(after.id, isNot(before.id));
      expect(
        await transfer.stage(await transfer.preview(), {
          'water',
        }, () => _account),
        1,
      );
    },
  );

  test(
    'distinct goal IDs for one effective date preserve the local record and remote conflict',
    () async {
      final directory = await Directory.systemTemp.createTemp('flex-goals-');
      final factory = databaseFactoryFfi;
      final old = await factory.getDatabasesPath();
      await factory.setDatabasesPath(directory.path);
      addTearDown(() async {
        await factory.setDatabasesPath(old);
        await directory.delete(recursive: true);
      });
      final account = await DiaryStore.open(
        factory: factory,
        accountId: _account,
      );
      addTearDown(account.db.close);
      await account.tracking.saveGoals(_day, const Targets(energy: 1800));
      expect(
        await account.inbox!.apply([
          {
            'sequence': 1,
            'record': {
              'kind': 'goals',
              'id': '35fc8bd4-b696-4da3-a1ea-4b9a10315f53',
              'revision': 1,
              'deleted': false,
              'updated_at': '2026-11-17T10:00:00Z',
              'payload': {'day': _day, 'calories': 2100},
            },
          },
        ]),
        1,
      );
      expect((await account.tracking.goals(_day)).energy, 1800);
      expect(
        (await account.db.query('sync_remote_record')).single['conflict'],
        1,
      );
    },
  );
}
