import 'dart:convert';
import 'dart:io';

import 'package:fitness_diary/core/diary_outbox.dart';
import 'package:fitness_diary/core/diary_store.dart';
import 'package:fitness_diary/core/sync_http.dart';
import 'package:fitness_diary/features/diary/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _account = '25fc8bd4-b696-4da3-a1ea-4b9a10315f53';
const _day = '2026-11-17';

DiaryEntry _entry([int amount = 1000]) {
  final food = fixture.first;
  return DiaryEntry(
    'test',
    _day,
    Meal.breakfast,
    food,
    food.servings.first,
    amount,
    {},
  );
}

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  test(
    'guest diary has no outbox and account transactions roll back together',
    () async {
      final temp = await Directory.systemTemp.createTemp('flex-p12-');
      final previous = await factory.getDatabasesPath();
      await factory.setDatabasesPath(temp.path);
      addTearDown(() async {
        await factory.setDatabasesPath(previous);
        await temp.delete(recursive: true);
      });
      final guest = await DiaryStore.open(factory: factory);
      final account = await DiaryStore.open(
        factory: factory,
        accountId: _account,
      );
      addTearDown(guest.db.close);
      addTearDown(account.db.close);
      await guest.save(_entry(), editing: false);
      expect(await guest.db.query('sync_outbox'), isEmpty);
      expect(await account.read(_day), isEmpty);
      await account.db.execute('''
      CREATE TRIGGER injected_failure BEFORE INSERT ON sync_outbox BEGIN
        SELECT RAISE(ABORT, 'test write failure');
      END
    ''');
      await expectLater(
        account.save(_entry(), editing: false),
        throwsA(isA<DatabaseException>()),
      );
      expect(await account.read(_day), isEmpty);
      expect(await account.db.query('sync_diary_mapping'), isEmpty);
      expect(await guest.read(_day), hasLength(1));
    },
  );

  test(
    'offline FIFO survives restart, retries with same ID and preserves conflicts',
    () async {
      final temp = await Directory.systemTemp.createTemp('flex-p12-');
      final previous = await factory.getDatabasesPath();
      await factory.setDatabasesPath(temp.path);
      addTearDown(() async {
        await factory.setDatabasesPath(previous);
        await temp.delete(recursive: true);
      });
      var store = await DiaryStore.open(factory: factory, accountId: _account);
      await store.save(_entry(), editing: false);
      await store.save(_entry(2000), editing: true);
      await store.remove('test');
      await store.db.close();
      store = await DiaryStore.open(factory: factory, accountId: _account);
      addTearDown(store.db.close);
      final outbox = store.outbox!;
      expect(await outbox.statusCounts(), {'pending': 3});
      expect(await store.read(_day), isEmpty);
      final seen = <Map<String, dynamic>>[];
      var now = DateTime.now();
      DateTime clock() => now;
      await outbox.drain(
        signedInAccount: () => 'other',
        clock: clock,
        submit: (_, _) async {
          fail('Cannot upload with another account');
        },
      );
      await outbox.drain(
        signedInAccount: () => _account,
        clock: clock,
        submit: (_, body) async {
          seen.add(body);
          return const SyncResult(Delivery.retry);
        },
      );
      await outbox.drain(
        signedInAccount: () => _account,
        clock: clock,
        submit: (_, _) async {
          fail('Expected retry backoff');
        },
      );
      now = now.add(const Duration(seconds: 2));
      await outbox.drain(
        signedInAccount: () => _account,
        clock: clock,
        submit: (_, body) async {
          expect(body, seen.single);
          return const SyncResult(Delivery.acknowledged);
        },
      );
      await outbox.drain(
        signedInAccount: () => _account,
        clock: clock,
        submit: (_, body) async {
          expect(body['action'], 'update');
          expect(body['base_revision'], 1);
          expect(body['record_id'], seen.single['record_id']);
          return const SyncResult(Delivery.conflict, remote: {'revision': 2});
        },
      );
      expect(await outbox.statusCounts(), {
        'acknowledged': 1,
        'conflict': 1,
        'pending': 1,
      });
      await outbox.drain(
        signedInAccount: () => _account,
        clock: clock,
        submit: (_, _) async {
          fail('The deletion must wait behind the conflicted update');
        },
      );
      final conflict = (await store.db.query(
        'sync_outbox',
        where: "status = 'conflict'",
      )).single;
      expect(jsonDecode(conflict['remote_conflict'] as String)['revision'], 2);
      expect(
        jsonDecode(conflict['body'] as String)['payload']['quantity_milli'],
        2000,
      );
    },
  );

  test(
    'expired session preserves pending work and rejection remains visible',
    () async {
      final temp = await Directory.systemTemp.createTemp('flex-p12-');
      final previous = await factory.getDatabasesPath();
      await factory.setDatabasesPath(temp.path);
      addTearDown(() async {
        await factory.setDatabasesPath(previous);
        await temp.delete(recursive: true);
      });
      final store = await DiaryStore.open(
        factory: factory,
        accountId: _account,
      );
      addTearDown(store.db.close);
      await store.save(_entry(), editing: false);
      final outbox = store.outbox!;
      await outbox.drain(
        signedInAccount: () => _account,
        submit: (_, _) async => const SyncResult(Delivery.unauthorized),
      );
      expect(await outbox.statusCounts(), {'pending': 1});
      await outbox.drain(
        signedInAccount: () => _account,
        submit: (_, _) async => const SyncResult(Delivery.rejected),
      );
      expect(await outbox.statusCounts(), {'rejected': 1});
      expect(await store.read(_day), hasLength(1));
    },
  );

  test('transport refuses plaintext and unauthenticated upload', () async {
    expect(
      () => SyncHttp(Uri.parse('http://localhost'), (_) async => null),
      throwsArgumentError,
    );
    final transport = SyncHttp(
      Uri.parse('https://sync.example.invalid'),
      (_) async => null,
    );
    addTearDown(transport.close);
    expect(
      (await transport.submit(_account, {})).delivery,
      Delivery.unauthorized,
    );
  });
}
