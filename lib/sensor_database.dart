import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'plant_data.dart';

/// SensorDatabase — persists sensor readings locally on the phone.
///
/// Dependencies (add to pubspec.yaml):
///   sqflite: ^2.3.2
///   path: ^1.9.0
class SensorDatabase {
  static final SensorDatabase instance = SensorDatabase._init();
  static Database? _database;

  SensorDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('farmlink_sensors.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE sensor_logs (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp   TEXT    NOT NULL,
        moisture    INTEGER,
        water_level INTEGER,
        air_temp    REAL,
        air_humid   REAL,
        soil_temp   REAL,
        light       INTEGER,
        motion      INTEGER,
        pump_status INTEGER
      )
    ''');
  }

  /// Insert a new reading. Call this whenever you receive a data packet.
  Future<void> insertReading(PlantData data) async {
    final db = await database;
    await db.insert('sensor_logs', {
      'timestamp': DateTime.now().toIso8601String(),
      'moisture': data.moisture,
      'water_level': data.waterLevel,
      'air_temp': data.airTemp,
      'air_humid': data.airHumid,
      'soil_temp': data.soilTemp,
      'light': data.light,
      'motion': data.motion,
      'pump_status': data.pumpStatus,
    });
  }

  /// Fetch the last [limit] readings, newest first.
  Future<List<Map<String, dynamic>>> getRecentReadings({int limit = 50}) async {
    final db = await database;
    return db.query('sensor_logs', orderBy: 'id DESC', limit: limit);
  }

  /// Delete logs older than [days] days.
  Future<void> pruneOldLogs({int days = 7}) async {
    final db = await database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String();
    await db.delete('sensor_logs', where: 'timestamp < ?', whereArgs: [cutoff]);
  }

  Future<void> close() async {
    final db = await _database;
    db?.close();
  }
}
