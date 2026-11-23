import 'dart:io';

import 'package:fitness_diary/app.dart';
import 'package:fitness_diary/core/diary_outbox.dart';
import 'package:fitness_diary/core/diary_store.dart';
import 'package:fitness_diary/core/guest_transfer.dart';
import 'package:fitness_diary/core/tracking_store.dart';
import 'package:fitness_diary/core/sync_http.dart';
import 'package:fitness_diary/features/diary/domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const day = '2026-11-17';

void main() {
  sqfliteFfiInit();
  final env = Platform.environment;
  test(
    'two SQLite clients reconcile through authenticated PostgreSQL over TLS',
    () async {
      final account = env['FLEX_TEST_ACCOUNT']!;
      final other = env['FLEX_OTHER_ACCOUNT']!;
      final untrusted = SyncHttp(
        Uri.parse(env['FLEX_TEST_URL']!),
        (_) async => env['FLEX_TEST_TOKEN'],
      );
      addTearDown(untrusted.close);
      await expectLater(
        untrusted.changes(account, 0),
        throwsA(isA<HandshakeException>()),
      );
      final trust = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificates(env['FLEX_TEST_CERT']!);
      final transport = SyncHttp(Uri.parse(env['FLEX_TEST_URL']!), (id) async {
        if (id == account) return env['FLEX_TEST_TOKEN'];
        if (id == other) return env['FLEX_OTHER_TOKEN'];
        return null;
      }, trust: trust);
      addTearDown(transport.close);
      final root = await Directory.systemTemp.createTemp('flex-two-clients-');
      final factory = databaseFactoryFfi;
      final original = await factory.getDatabasesPath();
      addTearDown(() async {
        await factory.setDatabasesPath(original);
        await root.delete(recursive: true);
      });

      Future<DiaryStore> client(String name, {String? owner}) async {
        final directory = Directory('${root.path}/$name');
        await directory.create();
        await factory.setDatabasesPath(directory.path);
        final store = await DiaryStore.open(factory: factory, accountId: owner);
        return store;
      }

      final a = await client('a', owner: account);
      var b = await client('b', owner: account);
      final guest = await client('guest');
      addTearDown(a.db.close);
      addTearDown(() => b.db.close());
      addTearDown(guest.db.close);
      final food = fixture[1];
      DiaryEntry entry(String id, int quantity) => DiaryEntry(
        id,
        day,
        Meal.breakfast,
        food,
        food.servings.first,
        quantity,
        {},
      );
      await guest.save(entry('guest', 1000), editing: false);
      await a.save(entry('local', 2000), editing: false);
      final clock = DateTime.now();
      var submissions = 0;
      await a.outbox!.drain(
        signedInAccount: () => account,
        clock: () => clock,
        submit: (id, body) async {
          expect(
            (await transport.submit(id, body)).delivery,
            Delivery.acknowledged,
          );
          submissions++;
          return const SyncResult(Delivery.retry);
        },
      );
      await a.outbox!.drain(
        signedInAccount: () => account,
        clock: () => clock.add(const Duration(seconds: 2)),
        submit: (id, body) async {
          submissions++;
          return transport.submit(id, body);
        },
      );
      expect(submissions, 2);
      expect(await a.outbox!.statusCounts(), {'acknowledged': 1});
      expect(await transport.changes(other, 0), isEmpty);
      await expectLater(
        transport.changes('unsigned', 0),
        throwsA(isA<HttpException>()),
      );

      ProviderContainer providers(DiaryStore store) => ProviderContainer(
        overrides: [storeProvider.overrideWith((ref) async => store)],
      );
      var state = providers(b);
      addTearDown(() => state.dispose());
      Future<List<DiaryEntry>> visible() =>
          state.read(diaryProvider(day).future);
      Future<void> pull() =>
          state.read(applyDiaryChangesProvider)(b, transport);
      expect(await visible(), isEmpty);
      expect(await state.read(diaryProvider('2026-11-18').future), isEmpty);
      await pull();
      var downloaded = (await visible()).single;
      final local = (await a.read(day)).single;
      expect(downloaded.amounts, local.amounts);
      expect(downloaded.quantity, local.quantity);
      expect(downloaded.day, day);
      expect(downloaded.meal, Meal.breakfast);
      expect(downloaded.serving.grams, local.serving.grams);
      expect(downloaded.amounts[Nutrient.fat], isNull);
      expect(await state.read(diaryProvider('2026-11-18').future), isEmpty);
      final recordId = (await a.db.query(
        'sync_diary_mapping',
      )).single['record_id'];
      expect(
        (await b.db.query('sync_diary_mapping')).single['record_id'],
        recordId,
      );
      expect(await b.inbox!.cursor(), 1);

      await b.save(entry(downloaded.id, 3000), editing: true);
      await b.outbox!.drain(
        signedInAccount: () => account,
        submit: transport.submit,
      );
      final aState = providers(a);
      addTearDown(aState.dispose);
      await aState.read(diaryProvider(day).future);
      await aState.read(applyDiaryChangesProvider)(a, transport);
      final onA = (await aState.read(diaryProvider(day).future)).single;
      expect(onA.quantity, 3000);
      expect(onA.day, day);
      expect(onA.meal, Meal.breakfast);
      expect(onA.amounts, (await b.read(day)).single.amounts);
      for (final nutrient in Nutrient.values) {
        expect(
          total(await aState.read(diaryProvider(day).future), nutrient),
          total(await b.read(day), nutrient),
        );
      }
      await pull();
      downloaded = (await visible()).single;
      expect(downloaded.quantity, 3000);

      state.dispose();
      await b.db.close();
      b = await client('b', owner: account);
      state = providers(b);
      expect(await b.inbox!.cursor(), 2);
      expect((await visible()).single.quantity, 3000);

      await b.save(entry(downloaded.id, 5000), editing: true);
      await a.save(entry('local', 4000), editing: true);
      await a.outbox!.drain(
        signedInAccount: () => account,
        submit: transport.submit,
      );
      await pull();
      expect((await b.read(day)).single.quantity, 5000);
      await b.outbox!.drain(
        signedInAccount: () => account,
        submit: transport.submit,
      );
      expect(await b.outbox!.statusCounts(), {
        'acknowledged': 1,
        'conflict': 1,
      });
      expect((await b.db.query('sync_remote_record')).single['conflict'], 1);

      final clean = await client('clean', owner: account);
      addTearDown(clean.db.close);
      final cleanState = providers(clean);
      addTearDown(cleanState.dispose);
      await cleanState.read(applyDiaryChangesProvider)(clean, transport);
      expect(
        (await cleanState.read(diaryProvider(day).future)).single.quantity,
        4000,
      );

      await a.remove('local');
      await a.outbox!.drain(
        signedInAccount: () => account,
        submit: transport.submit,
      );
      await pull();
      expect((await b.read(day)).single.quantity, 5000);
      final tombstone = (await transport.changes(account, 3)).single;
      expect(tombstone['record']['deleted'], true);
      await cleanState.read(applyDiaryChangesProvider)(clean, transport);
      expect(await cleanState.read(diaryProvider(day).future), isEmpty);
      expect(await clean.inbox!.cursor(), 4);
      await a.tracking.saveGoals(
        day,
        const Targets(
          energy: 2050,
          protein: 110,
          carbs: 240,
          fat: 65,
          water: 2600,
          weight: 72000,
          exerciseCredit: true,
        ),
      );
      await a.tracking.save(
        TrackRecord(
          kind: TrackKind.weight,
          day: day,
          value: weightGrams(160, pounds: true),
        ),
      );
      await a.tracking.save(
        const TrackRecord(kind: TrackKind.water, day: day, value: 240),
      );
      await a.tracking.save(
        const TrackRecord(kind: TrackKind.water, day: day, value: 480),
      );
      await a.tracking.save(
        const TrackRecord(
          kind: TrackKind.exercise,
          day: day,
          name: 'Walk',
          category: 'Cardio',
          intensity: 'Light',
          value: 25,
          energy: 61,
        ),
      );
      await a.outbox!.drain(
        signedInAccount: () => account,
        submit: transport.submit,
      );
      await cleanState.read(applyDiaryChangesProvider)(clean, transport);

      final goal = await clean.tracking.goals('2026-11-18');
      expect(
        [
          goal.energy,
          goal.protein,
          goal.carbs,
          goal.fat,
          goal.water,
          goal.weight,
          goal.exerciseCredit,
        ],
        [2050, 110, 240, 65, 2600, 72000, true],
      );
      final rows = await clean.tracking.records(day, day);
      expect(
        rows
            .where((row) => row.kind == TrackKind.water)
            .fold<int>(0, (total, row) => total + row.value),
        720,
      );
      expect(
        rows.singleWhere((row) => row.kind == TrackKind.weight).value,
        weightGrams(160, pounds: true),
      );
      final workout = rows.singleWhere((row) => row.kind == TrackKind.exercise);
      expect(
        [
          workout.name,
          workout.category,
          workout.intensity,
          workout.value,
          workout.energy,
        ],
        ['Walk', 'Cardio', 'Light', 25, 61],
      );
      final originalWeight = rows.singleWhere(
        (row) => row.kind == TrackKind.weight,
      );
      await clean.tracking.save(
        TrackRecord(
          id: originalWeight.id,
          kind: TrackKind.weight,
          day: day,
          value: 74000,
        ),
      );
      await clean.tracking.remove(workout);
      await clean.outbox!.drain(
        signedInAccount: () => account,
        submit: transport.submit,
      );
      await aState.read(applyDiaryChangesProvider)(a, transport);
      expect(
        (await a.tracking.records(
          day,
          day,
        )).where((row) => row.kind == TrackKind.exercise),
        isEmpty,
      );

      expect(await a.tracking.latestWeight(day), 74000);
      final serving = (await a.tracking.records(
        day,
        day,
      )).singleWhere((row) => row.kind == TrackKind.water && row.value == 240);
      await a.tracking.save(
        TrackRecord(
          id: serving.id,
          kind: TrackKind.water,
          day: day,
          value: 300,
        ),
      );
      await a.tracking.saveGoals(
        day,
        const Targets(energy: 2150, exerciseCredit: true),
      );
      await a.outbox!.drain(
        signedInAccount: () => account,
        submit: transport.submit,
      );
      await cleanState.read(applyDiaryChangesProvider)(clean, transport);
      expect((await clean.tracking.goals(day)).energy, 2150);
      expect(
        (await clean.tracking.records(day, day))
            .where((row) => row.kind == TrackKind.water)
            .fold<int>(0, (total, row) => total + row.value),
        780,
      );

      await guest.tracking.save(
        const TrackRecord(kind: TrackKind.water, day: day, value: 300),
      );
      final transfer = GuestTransfer(guest, a);
      final preview = await transfer.preview();
      expect(await transfer.stage(preview, {}, () => account), 0);
      await expectLater(
        transfer.stage(preview, {'diary'}, () => other),
        throwsStateError,
      );
      expect(
        await transfer.stage(preview, {'diary', 'water'}, () => account),
        2,
      );
      expect(
        await transfer.stage(preview, {'diary', 'water'}, () => account),
        0,
      );
      expect(await transfer.status(), {'pending': 2});
      await a.outbox!.drain(
        signedInAccount: () => account,
        submit: transport.submit,
      );
      expect(await transfer.status(), {'acknowledged': 2});
      await cleanState.read(applyDiaryChangesProvider)(clean, transport);
      expect(
        (await clean.read(day)).single.amounts,
        (await guest.read(day)).single.amounts,
      );
      expect((await guest.tracking.records(day, day)).single.value, 300);
      expect(await transport.changes(other, 0), isEmpty);
      expect((await guest.read(day)).single.id, 'guest');
    },
    skip: !env.containsKey('FLEX_TEST_URL'),
  );
}
