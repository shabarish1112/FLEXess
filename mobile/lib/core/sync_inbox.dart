import 'dart:convert';

import 'package:sqflite/sqflite.dart';

class ProjectionConflict implements Exception {
  const ProjectionConflict();
}

class SyncInbox {
  SyncInbox(this.db, this.accountId, {this.project, this.onCommitted});
  final void Function(Set<String>)? onCommitted;
  final Future<void> Function(Transaction, Map<String, dynamic>)? project;
  final Database db;
  final String accountId;

  static Future<void> migrate(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE sync_cursor (
        account_id TEXT PRIMARY KEY NOT NULL,
        sequence INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sync_remote_record (
        account_id TEXT NOT NULL,
        record_id TEXT NOT NULL,
        revision INTEGER NOT NULL,
        record TEXT NOT NULL,
        conflict INTEGER NOT NULL,
        PRIMARY KEY (account_id, record_id)
      )
    ''');
  }

  Future<int> cursor() => _cursor(db);

  Future<int> _cursor(DatabaseExecutor executor) async {
    final rows = await executor.query(
      'sync_cursor',
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
    return rows.isEmpty ? 0 : rows.single['sequence'] as int;
  }

  Future<int> apply(List<Map<String, dynamic>> changes) async {
    final result = await db.transaction((txn) async {
      final projectedKinds = <String>{};
      var position = await _cursor(txn);
      for (final change in changes) {
        final sequence = change['sequence'];
        if (sequence is! int || sequence < 1) {
          throw const FormatException('Invalid change sequence.');
        }
        if (sequence <= position) continue;
        if (sequence != position + 1) {
          throw const FormatException('Change feed has a gap.');
        }
        final record = change['record'];
        if (record is! Map<String, dynamic> ||
            record['id'] is! String ||
            !_uuid.hasMatch(record['id'] as String) ||
            !_kinds.contains(record['kind']) ||
            record['revision'] is! int ||
            (record['revision'] as int) < 1 ||
            record['deleted'] is! bool ||
            (record['deleted'] == true
                ? record['payload'] != null
                : record['payload'] is! Map<String, dynamic>)) {
          throw const FormatException('Invalid remote record.');
        }
        final id = record['id'] as String;
        final revision = record['revision'] as int;
        final prior = await txn.query(
          'sync_remote_record',
          where: 'account_id = ? AND record_id = ?',
          whereArgs: [accountId, id],
        );
        if (prior.isEmpty || (prior.single['revision'] as int) <= revision) {
          final pending = await txn.rawQuery(
            '''
              SELECT op.operation_id FROM sync_outbox op
              JOIN sync_diary_mapping mapping ON mapping.local_id = op.local_id
              WHERE op.account_id = ? AND mapping.record_id = ?
                AND op.status != 'acknowledged' LIMIT 1
            ''',
            [accountId, id],
          );
          var conflict = pending.isNotEmpty;
          if (!conflict && record['kind'] != 'profile' && project != null) {
            try {
              await project!(txn, record);
              projectedKinds.add(record['kind'] as String);
            } on ProjectionConflict {
              conflict = true;
            }
          }
          await txn.insert('sync_remote_record', {
            'account_id': accountId,
            'record_id': id,
            'revision': revision,
            'record': jsonEncode(record),
            'conflict': conflict ? 1 : 0,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        position = sequence;
      }
      await txn.insert('sync_cursor', {
        'account_id': accountId,
        'sequence': position,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return (position, projectedKinds);
    });
    if (result.$2.isNotEmpty) onCommitted?.call(result.$2);
    return result.$1;
  }

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  static const _kinds = {
    'profile',
    'goals',
    'diary',
    'weight',
    'water',
    'exercise',
  };
}
