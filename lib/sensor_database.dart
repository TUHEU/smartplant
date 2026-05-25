import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'plant_data.dart';

class SensorDatabase {
  static final SensorDatabase instance = SensorDatabase._init();
  static Database? _database;
  SensorDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('farmlink.db');
    return _database!;
  }

  Future<Database> _initDB(String f) async {
    final p = join(await getDatabasesPath(), f);
    return openDatabase(
      p,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
        CREATE TABLE logs (
          id          INTEGER PRIMARY KEY AUTOINCREMENT,
          ts          TEXT,
          moisture    INTEGER,
          water_level INTEGER,
          air_temp    REAL,
          air_humid   REAL,
          soil_temp   REAL,
          light       INTEGER,
          motion      INTEGER,
          pump        INTEGER
        )
      ''');
      },
    );
  }

  Future<void> insert(PlantData d) async {
    final db = await database;
    await db.insert('logs', {
      'ts': DateTime.now().toIso8601String(),
      'moisture': d.moisture,
      'water_level': d.waterLevel,
      'air_temp': d.airTemp,
      'air_humid': d.airHumid,
      'soil_temp': d.soilTemp,
      'light': d.light,
      'motion': d.motion,
      'pump': d.pumpStatus,
    });
  }

  Future<List<Map<String, dynamic>>> recent({int limit = 80}) async {
    final db = await database;
    return db.query('logs', orderBy: 'id DESC', limit: limit);
  }

  Future<void> clear() async {
    final db = await database;
    await db.delete('logs');
  }

  Future<void> prune({int days = 7}) async {
    final db = await database;
    final cut = DateTime.now().subtract(Duration(days: days)).toIso8601String();
    await db.delete('logs', where: 'ts < ?', whereArgs: [cut]);
  }
}
