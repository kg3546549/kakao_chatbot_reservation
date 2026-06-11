import 'dart:async';
import 'dart:math';

import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/item.dart';
import '../models/reservation.dart';
import '../models/room.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;
  static const _databaseVersion = 6;
  static const _legacyTenantId = '__legacy__';
  static String _tenantId = _legacyTenantId;
  static final StreamController<String> _tenantChanges =
      StreamController<String>.broadcast();

  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Stream<String> get tenantChanges => _tenantChanges.stream;
  String get tenantId => _tenantId;

  Future<void> setTenant(String tenantId) async {
    if (tenantId.isEmpty || tenantId == _tenantId) return;
    final db = await database;
    await db.transaction((transaction) async {
      for (final table in [
        'items',
        'rooms',
        'reservations',
        'logs',
        'sync_queue'
      ]) {
        await transaction.update(
          table,
          {'tenant_id': tenantId},
          where: 'tenant_id = ?',
          whereArgs: [_legacyTenantId],
        );
      }
    });
    _tenantId = tenantId;
    _tenantChanges.add(tenantId);
  }

  void clearTenant() {
    _tenantId = _legacyTenantId;
    _tenantChanges.add(_tenantId);
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'kakao_bot.db');
    return openDatabase(
      path,
      version: _databaseVersion,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async => _createTables(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _cleanupOrphanReservations(db);
        }
        if (oldVersion < 3) {
          await _createLegacySyncQueue(db);
        }
        if (oldVersion < 4) {
          await _migrateToTenantScopedTables(db);
        }
        if (oldVersion >= 4 && oldVersion < 5) {
          await db.execute(
              'ALTER TABLE sync_queue ADD COLUMN next_attempt_at TEXT');
        }
        if (oldVersion >= 4 && oldVersion < 6) {
          await db.execute('ALTER TABLE reservations ADD COLUMN cloud_id TEXT');
        }
      },
      onOpen: (db) async => _cleanupOrphanReservations(db),
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenant_id TEXT NOT NULL,
        name TEXT NOT NULL,
        max_capacity INTEGER,
        template TEXT,
        UNIQUE(tenant_id, name)
      )
    ''');
    await db.execute('''
      CREATE TABLE reservations(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenant_id TEXT NOT NULL,
        cloud_id TEXT,
        item_id INTEGER,
        nickname TEXT,
        room_name TEXT,
        created_at TEXT,
        FOREIGN KEY (item_id) REFERENCES items (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE rooms(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenant_id TEXT NOT NULL,
        name TEXT NOT NULL,
        type INTEGER,
        UNIQUE(tenant_id, name)
      )
    ''');
    await db.execute('''
      CREATE TABLE logs(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenant_id TEXT NOT NULL,
        timestamp TEXT,
        type TEXT,
        content TEXT
      )
    ''');
    await _createSyncQueue(db);
  }

  Future<void> _createLegacySyncQueue(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue(
        event_id TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createSyncQueue(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue(
        event_id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        next_attempt_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _migrateToTenantScopedTables(Database db) async {
    await db.execute('PRAGMA foreign_keys = OFF');
    for (final table in [
      'items',
      'reservations',
      'rooms',
      'logs',
      'sync_queue'
    ]) {
      await db.execute('ALTER TABLE $table RENAME TO ${table}_legacy');
    }
    await _createTables(db);
    await db.execute('''
      INSERT INTO items(id, tenant_id, name, max_capacity, template)
      SELECT id, '$_legacyTenantId', name, max_capacity, template
      FROM items_legacy
    ''');
    await db.execute('''
      INSERT INTO reservations(id, tenant_id, item_id, nickname, room_name, created_at)
      SELECT id, '$_legacyTenantId', item_id, nickname, room_name, created_at
      FROM reservations_legacy
    ''');
    await db.execute('''
      INSERT INTO rooms(id, tenant_id, name, type)
      SELECT id, '$_legacyTenantId', name, type FROM rooms_legacy
    ''');
    await db.execute('''
      INSERT INTO logs(id, tenant_id, timestamp, type, content)
      SELECT id, '$_legacyTenantId', timestamp, type, content FROM logs_legacy
    ''');
    await db.execute('''
      INSERT INTO sync_queue(event_id, tenant_id, payload, status, attempts, last_error, created_at, updated_at)
      SELECT event_id, '$_legacyTenantId', payload, status, attempts, last_error, created_at, updated_at
      FROM sync_queue_legacy
    ''');
    for (final table in [
      'items',
      'reservations',
      'rooms',
      'logs',
      'sync_queue'
    ]) {
      await db.execute('DROP TABLE ${table}_legacy');
    }
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _cleanupOrphanReservations(Database db) async {
    await db.delete(
      'reservations',
      where: 'item_id NOT IN (SELECT id FROM items)',
    );
  }

  Future<int> insertItem(Item item) async {
    final db = await database;
    return db.insert(
      'items',
      {...item.toMap(), 'tenant_id': _tenantId},
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<List<Item>> getItems() async {
    final db = await database;
    final maps = await db.query(
      'items',
      where: 'tenant_id = ?',
      whereArgs: [_tenantId],
    );
    return maps.map(Item.fromMap).toList();
  }

  Future<int> updateItem(Item item) async {
    final db = await database;
    return db.update(
      'items',
      item.toMap(),
      where: 'id = ? AND tenant_id = ?',
      whereArgs: [item.id, _tenantId],
    );
  }

  Future<int> deleteItem(int id) async {
    final db = await database;
    return db.delete(
      'items',
      where: 'id = ? AND tenant_id = ?',
      whereArgs: [id, _tenantId],
    );
  }

  Future<int> insertReservation(Reservation reservation) async {
    final db = await database;
    return db.insert(
      'reservations',
      {...reservation.toMap(), 'tenant_id': _tenantId},
    );
  }

  Future<bool> hasLocalItems() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM items WHERE tenant_id = ?',
      [_tenantId],
    );
    return (result.first['count'] as int) > 0;
  }

  Future<void> restoreBotSnapshot({
    required List<Map<String, dynamic>> items,
    required List<Map<String, dynamic>> reservations,
    required List<Map<String, dynamic>> rooms,
  }) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete(
        'reservations',
        where: 'tenant_id = ?',
        whereArgs: [_tenantId],
      );
      await transaction.delete(
        'items',
        where: 'tenant_id = ?',
        whereArgs: [_tenantId],
      );
      await transaction.delete(
        'rooms',
        where: 'tenant_id = ?',
        whereArgs: [_tenantId],
      );

      final restoredItemIds = <int>{};
      for (final item in items) {
        final itemId = int.tryParse(item['itemId']?.toString() ?? '');
        final name = item['name']?.toString().trim() ?? '';
        final maxCapacity = item['maxCapacity'];
        if (itemId == null ||
            name.isEmpty ||
            maxCapacity is! num ||
            maxCapacity <= 0) {
          continue;
        }
        await transaction.insert('items', {
          'id': itemId,
          'tenant_id': _tenantId,
          'name': name,
          'max_capacity': maxCapacity.toInt(),
          'template': item['template']?.toString() ?? '',
        });
        restoredItemIds.add(itemId);
      }

      for (final reservation in reservations) {
        final itemId = int.tryParse(reservation['itemId']?.toString() ?? '');
        final cloudId = reservation['reservationId']?.toString() ?? '';
        if (itemId == null ||
            cloudId.isEmpty ||
            !restoredItemIds.contains(itemId)) {
          continue;
        }
        await transaction.insert('reservations', {
          'tenant_id': _tenantId,
          'cloud_id': cloudId,
          'item_id': itemId,
          'nickname': reservation['nickname']?.toString() ?? '',
          'room_name': reservation['roomName']?.toString() ?? '',
          'created_at': reservation['createdAt']?.toString().isNotEmpty == true
              ? reservation['createdAt'].toString()
              : DateTime.now().toIso8601String(),
        });
      }
      for (final room in rooms) {
        final name = room['name']?.toString().trim() ?? '';
        final typeName = room['type']?.toString() ?? 'general';
        final typeIndex = switch (typeName) {
          'reservation' => RoomType.reservation.index,
          'admin' => RoomType.admin.index,
          _ => RoomType.general.index,
        };
        if (name.isEmpty) continue;
        await transaction.insert(
          'rooms',
          {
            'tenant_id': _tenantId,
            'name': name,
            'type': typeIndex,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    _tenantChanges.add(_tenantId);
  }

  Future<List<Reservation>> getReservations(
      {int? itemId, DateTime? date}) async {
    final db = await database;
    var where = 'tenant_id = ?';
    final whereArgs = <Object?>[_tenantId];
    if (itemId != null) {
      where += ' AND item_id = ?';
      whereArgs.add(itemId);
    }
    if (date != null) {
      where += ' AND created_at LIKE ?';
      whereArgs.add('${DateFormat('yyyy-MM-dd').format(date)}%');
    }
    final maps = await db.query(
      'reservations',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'created_at ASC',
    );
    return maps.map(Reservation.fromMap).toList();
  }

  Future<int> deleteReservation(int id) async {
    final db = await database;
    return db.delete(
      'reservations',
      where: 'id = ? AND tenant_id = ?',
      whereArgs: [id, _tenantId],
    );
  }

  Future<int> clearReservations(int itemId, {DateTime? date}) async {
    final db = await database;
    var where = 'tenant_id = ? AND item_id = ?';
    final whereArgs = <Object?>[_tenantId, itemId];
    if (date != null) {
      where += ' AND created_at LIKE ?';
      whereArgs.add('${DateFormat('yyyy-MM-dd').format(date)}%');
    }
    return db.delete('reservations', where: where, whereArgs: whereArgs);
  }

  Future<int> insertRoom(Room room) async {
    final db = await database;
    return db.insert(
      'rooms',
      {...room.toMap(), 'tenant_id': _tenantId},
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<List<Room>> getRooms() async {
    final db = await database;
    final maps = await db.query(
      'rooms',
      where: 'tenant_id = ?',
      whereArgs: [_tenantId],
    );
    return maps.map(Room.fromMap).toList();
  }

  Future<int> updateRoom(Room room) async {
    final db = await database;
    return db.update(
      'rooms',
      room.toMap(),
      where: 'id = ? AND tenant_id = ?',
      whereArgs: [room.id, _tenantId],
    );
  }

  Future<Room?> getRoomByName(String name) async {
    final db = await database;
    final maps = await db.query(
      'rooms',
      where: 'tenant_id = ? AND name = ?',
      whereArgs: [_tenantId, name],
      limit: 1,
    );
    return maps.isEmpty ? null : Room.fromMap(maps.first);
  }

  Future<void> addLog(String type, String content) async {
    final db = await database;
    await db.insert('logs', {
      'tenant_id': _tenantId,
      'timestamp': DateTime.now().toIso8601String(),
      'type': type,
      'content': content,
    });
  }

  Future<List<Map<String, dynamic>>> getLogs() async {
    final db = await database;
    return db.query(
      'logs',
      where: 'tenant_id = ?',
      whereArgs: [_tenantId],
      orderBy: 'timestamp DESC',
      limit: 100,
    );
  }

  Future<void> enqueueSyncEvent(String eventId, String payload) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'sync_queue',
      {
        'event_id': eventId,
        'tenant_id': _tenantId,
        'payload': payload,
        'status': 'pending',
        'attempts': 0,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<Map<String, dynamic>>> getPendingSyncEvents(
      {int limit = 50}) async {
    final db = await database;
    return db.query(
      'sync_queue',
      where: '''
        tenant_id = ?
        AND status IN (?, ?)
        AND attempts < ?
        AND (next_attempt_at IS NULL OR next_attempt_at <= ?)
      ''',
      whereArgs: [
        _tenantId,
        'pending',
        'failed',
        10,
        DateTime.now().toIso8601String(),
      ],
      orderBy: 'created_at ASC',
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> getSyncQueueEvents() async {
    final db = await database;
    return db.query(
      'sync_queue',
      where: 'tenant_id = ?',
      whereArgs: [_tenantId],
      orderBy: 'created_at DESC',
      limit: 200,
    );
  }

  Future<void> resetSyncEvent(String eventId) async {
    final db = await database;
    await db.update(
      'sync_queue',
      {
        'status': 'pending',
        'attempts': 0,
        'last_error': null,
        'next_attempt_at': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'event_id = ? AND tenant_id = ?',
      whereArgs: [eventId, _tenantId],
    );
  }

  Future<void> resetFailedSyncEvents() async {
    final db = await database;
    await db.update(
      'sync_queue',
      {
        'status': 'pending',
        'attempts': 0,
        'last_error': null,
        'next_attempt_at': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'tenant_id = ? AND status = ?',
      whereArgs: [_tenantId, 'failed'],
    );
  }

  Future<void> markSyncEventCompleted(String eventId) async {
    final db = await database;
    await db.delete(
      'sync_queue',
      where: 'event_id = ? AND tenant_id = ?',
      whereArgs: [eventId, _tenantId],
    );
  }

  Future<void> markSyncEventFailed(String eventId, Object error) async {
    final db = await database;
    final rows = await db.query(
      'sync_queue',
      columns: ['attempts'],
      where: 'event_id = ? AND tenant_id = ?',
      whereArgs: [eventId, _tenantId],
      limit: 1,
    );
    final attempts = rows.isEmpty ? 0 : rows.first['attempts'] as int;
    final delayMinutes = pow(2, min(attempts, 6)).toInt();
    await db.rawUpdate(
      '''
      UPDATE sync_queue
      SET status = 'failed',
          attempts = attempts + 1,
          last_error = ?,
          next_attempt_at = ?,
          updated_at = ?
      WHERE event_id = ? AND tenant_id = ?
      ''',
      [
        error.toString(),
        DateTime.now().add(Duration(minutes: delayMinutes)).toIso8601String(),
        DateTime.now().toIso8601String(),
        eventId,
        _tenantId,
      ],
    );
  }
}
