import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/driver_entry.dart';

class DBHelper {
  static final DBHelper instance = DBHelper._init();
  static Database? _database;

  DBHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('cctv_driver.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE driver_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL UNIQUE,
        dayType TEXT NOT NULL,
        vehicleNumber TEXT,
        startTime TEXT,
        endTime TEXT,
        int1Start TEXT,
        int1End TEXT,
        int2Start TEXT,
        int2End TEXT,
        regularHours REAL,
        overtimeHours REAL,
        intermitenciaHours REAL,
        nightHours REAL,
        hasMealAllowance INTEGER,
        firstMeal TEXT,
        secondMeal TEXT,
        hasCollection INTEGER DEFAULT 0
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE driver_entries ADD COLUMN hasCollection INTEGER DEFAULT 0');
      } catch (_) {}
    }
  }

  Future<int> insertOrUpdate(DriverEntry entry) async {
    final db = await instance.database;
    return await db.insert(
      'driver_entries',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<DriverEntry>> getEntriesBetween(String start, String end) async {
    final db = await instance.database;
    final result = await db.query(
      'driver_entries',
      where: 'date >= ? AND date <= ?',
      whereArgs: [start, end],
      orderBy: 'date ASC',
    );
    return result.map((json) => DriverEntry.fromMap(json)).toList();
  }

  Future<List<DriverEntry>> getAllEntries() async {
    final db = await instance.database;
    final result = await db.query('driver_entries', orderBy: 'date ASC');
    return result.map((json) => DriverEntry.fromMap(json)).toList();
  }

  Future<int> deleteEntry(int id) async {
    final db = await instance.database;
    return await db.delete('driver_entries', where: 'id = ?', whereArgs: [id]);
  }
}