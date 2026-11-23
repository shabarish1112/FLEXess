import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

enum Delivery { acknowledged, retry, unauthorized, rejected, conflict }

class SyncResult {
  const SyncResult(this.delivery, {this.remote});
  final Delivery delivery;
  final Map<String, dynamic>? remote;
}

typedef SubmitOperation =
    Future<SyncResult> Function(String accountId, Map<String, dynamic> body);

final _random = Random.secure();

String _id() {
  final bytes = List.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class DiaryOutbox {
  DiaryOutbox(this.db, this.accountId);
  final Database db;
  final String accountId;

  static Future<void> migrate(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE sync_diary_mapping (
        local_id TEXT PRIMARY KEY NOT NULL,
        record_id TEXT UNIQUE NOT NULL,
        revision INTEGER NOT NULL CHECK(revision > 0)
      )
    ''');
    await db.execute('''
      CREATE TABLE sync_outbox (
        sequence INTEGER PRIMARY KEY AUTOINCREMENT,
        operation_id TEXT UNIQUE NOT NULL,
        account_id TEXT NOT NULL,
        local_id TEXT NOT NULL,
        body TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        last_attempt_at INTEGER,
        next_attempt_at INTEGER NOT NULL DEFAULT 0,
        retries INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending'
          CHECK(status IN ('pending','acknowledged','rejected','conflict')),
        failure TEXT,
        remote_conflict TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX sync_outbox_record ON sync_outbox(account_id, local_id, sequence)',
    );
  }

  Future<void> enqueue(
    Transaction transaction,
    String localId,
    String action,
    Map<String, Object?>? payload, {
    String kind = 'diary',
  }) async {
    final rows = await transaction.query(
      'sync_diary_mapping',
      where: 'local_id = ?',
      whereArgs: [localId],
    );
    if ((action == 'create') != rows.isEmpty) {
      throw StateError('Diary record does not match its sync history.');
    }
    final current = rows.isEmpty ? null : rows.single;
    final recordId = current?['record_id'] as String? ?? _id();
    final base = current?['revision'] as int? ?? 0;
    final mapping = {
      'local_id': localId,
      'record_id': recordId,
      'revision': base + 1,
    };
    await transaction.insert(
      'sync_diary_mapping',
      mapping,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    final id = _id();
    await transaction.insert('sync_outbox', {
      'operation_id': id,
      'account_id': accountId,
      'local_id': localId,
      'body': jsonEncode({
        'operation_id': id,
        'record_id': recordId,
        'kind': kind,
        'action': action,
        'base_revision': base,
        'payload_version': 1,
        'payload': payload,
      }),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<Map<String, int>> statusCounts() async => {
    for (final row in await db.rawQuery(
      'SELECT status, COUNT(*) AS count FROM sync_outbox WHERE account_id = ? GROUP BY status',
      [accountId],
    ))
      row['status'] as String: row['count'] as int,
  };

  bool _draining = false;

  Future<void> drain({
    required String? Function() signedInAccount,
    required SubmitOperation submit,
    DateTime Function()? clock,
  }) async {
    if (_draining || signedInAccount() != accountId) return;
    _draining = true;
    try {
      final now = (clock?.call() ?? DateTime.now()).millisecondsSinceEpoch;
      final rows = await db.rawQuery(
        '''
        SELECT op.* FROM sync_outbox op
        WHERE op.account_id = ? AND op.status = 'pending' AND op.next_attempt_at <= ?
          AND NOT EXISTS (
            SELECT 1 FROM sync_outbox earlier
            WHERE earlier.account_id = op.account_id AND earlier.local_id = op.local_id
              AND earlier.sequence < op.sequence AND earlier.status != 'acknowledged'
          )
        ORDER BY op.sequence LIMIT 20
      ''',
        [accountId, now],
      );
      for (final row in rows) {
        if (signedInAccount() != accountId) return;
        final result = await submit(
          accountId,
          jsonDecode(row['body'] as String) as Map<String, dynamic>,
        );
        if (result.delivery == Delivery.unauthorized ||
            signedInAccount() != accountId) {
          return;
        }
        final retry = row['retries'] as int;
        final update = switch (result.delivery) {
          Delivery.acknowledged => {'status': 'acknowledged', 'failure': null},
          Delivery.conflict => {
            'status': 'conflict',
            'failure': 'revision_conflict',
            'remote_conflict': result.remote == null
                ? null
                : jsonEncode(result.remote),
          },
          Delivery.rejected => {
            'status': 'rejected',
            'failure': 'operation_rejected',
          },
          Delivery.retry => {
            'retries': retry + 1,
            'next_attempt_at': now + 1000 * (1 << min(10, retry)),
            'failure': 'temporary_delivery_failure',
          },
          Delivery.unauthorized => throw StateError(
            'Session already rejected.',
          ),
        };
        await db.update(
          'sync_outbox',
          {...update, 'last_attempt_at': now},
          where: 'account_id = ? AND operation_id = ? AND status = ?',
          whereArgs: [accountId, row['operation_id'], 'pending'],
        );
      }
    } finally {
      _draining = false;
    }
  }
}
