import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/item.dart';
import '../models/reservation.dart';
import '../models/room.dart';
import 'package:intl/intl.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'kakao_bot.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE,
            max_capacity INTEGER,
            template TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE reservations(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
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
            name TEXT UNIQUE,
            type INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE logs(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT,
            type TEXT,
            content TEXT
          )
        ''');
      },
    );
  }

  // Items
  Future<int> insertItem(Item item) async {
    final db = await database;
    return await db.insert('items', item.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Item>> getItems() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('items');
    return List.generate(maps.length, (i) => Item.fromMap(maps[i]));
  }

  Future<int> updateItem(Item item) async {
    final db = await database;
    return await db.update('items', item.toMap(),
        where: 'id = ?', whereArgs: [item.id]);
  }

  Future<int> deleteItem(int id) async {
    final db = await database;
    return await db.delete('items', where: 'id = ?', whereArgs: [id]);
  }

  // Reservations
  Future<int> insertReservation(Reservation res) async {
    final db = await database;
    return await db.insert('reservations', res.toMap());
  }

  Future<List<Reservation>> getReservations({int? itemId, DateTime? date}) async {
    final db = await database;
    String? where;
    List<dynamic>? whereArgs;

    if (itemId != null && date != null) {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      where = 'item_id = ? AND created_at LIKE ?';
      whereArgs = [itemId, '$dateStr%'];
    } else if (itemId != null) {
      where = 'item_id = ?';
      whereArgs = [itemId];
    } else if (date != null) {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      where = 'created_at LIKE ?';
      whereArgs = ['$dateStr%'];
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'reservations',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'created_at ASC',
    );
    return List.generate(maps.length, (i) => Reservation.fromMap(maps[i]));
  }

  Future<int> deleteReservation(int id) async {
    final db = await database;
    return await db.delete('reservations', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> clearReservations(int itemId, {DateTime? date}) async {
    final db = await database;
    if (date != null) {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      return await db.delete('reservations', 
          where: 'item_id = ? AND created_at LIKE ?', 
          whereArgs: [itemId, '$dateStr%']);
    }
    return await db.delete('reservations', where: 'item_id = ?', whereArgs: [itemId]);
  }

  // Rooms
  Future<int> insertRoom(Room room) async {
    final db = await database;
    return await db.insert('rooms', room.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Room>> getRooms() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('rooms');
    return List.generate(maps.length, (i) => Room.fromMap(maps[i]));
  }

  Future<int> updateRoom(Room room) async {
    final db = await database;
    return await db.update('rooms', room.toMap(),
        where: 'id = ?', whereArgs: [room.id]);
  }

  // Logs
  Future<void> addLog(String type, String content) async {
    final db = await database;
    await db.insert('logs', {
      'timestamp': DateTime.now().toIso8601String(),
      'type': type,
      'content': content,
    });
  }

  Future<List<Map<String, dynamic>>> getLogs() async {
    final db = await database;
    return await db.query('logs', orderBy: 'timestamp DESC', limit: 100);
  }
}
