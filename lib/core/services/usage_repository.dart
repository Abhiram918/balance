import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'dart:io';
import '../models/app_session.dart';
import '../models/focus_session.dart';
import '../models/app_limit.dart';

class UsageRepository {
  final String dbName;
  Database? _db;

  UsageRepository({this.dbName = 'usage.db'});

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB(dbName);
    return _db!;
  }

  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }

  Future<Database> _initDB(String filePath) async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final String path;
    if (filePath == inMemoryDatabasePath) {
      path = inMemoryDatabasePath;
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, filePath);
    }

    return await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: _createDB,
        onUpgrade: _onUpgradeDB,
      ),
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS AppSessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        appName TEXT NOT NULL,
        exePath TEXT NOT NULL,
        startTime INTEGER NOT NULL,
        endTime INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sessions_time ON AppSessions (startTime, endTime)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS FocusSessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        plannedSeconds INTEGER NOT NULL,
        actualSeconds INTEGER NOT NULL,
        startTime INTEGER NOT NULL,
        endTime INTEGER NOT NULL,
        completedNaturally INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_focus_sessions_time ON FocusSessions (startTime DESC)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ActiveFocus (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        type TEXT NOT NULL,
        status TEXT NOT NULL,
        targetSeconds INTEGER NOT NULL,
        startTime INTEGER NOT NULL,
        expectedEndTime INTEGER NOT NULL,
        remainingSeconds INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS AppLimits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        appName TEXT NOT NULL UNIQUE,
        exePath TEXT,
        limitMinutes INTEGER NOT NULL,
        warningPercentage INTEGER NOT NULL DEFAULT 80,
        isEnabled INTEGER NOT NULL DEFAULT 1,
        isEnforced INTEGER NOT NULL DEFAULT 0,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_app_limits_app ON AppLimits (appName)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS LimitNotificationLog (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        limitId INTEGER NOT NULL,
        notificationType TEXT NOT NULL,
        dateKey TEXT NOT NULL,
        notifiedAt INTEGER NOT NULL,
        UNIQUE(limitId, notificationType, dateKey)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_limit_notif_date ON LimitNotificationLog (dateKey)
    ''');
  }

  Future<void> _onUpgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_sessions_time ON AppSessions (startTime, endTime)
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS Settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS FocusSessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type TEXT NOT NULL,
          plannedSeconds INTEGER NOT NULL,
          actualSeconds INTEGER NOT NULL,
          startTime INTEGER NOT NULL,
          endTime INTEGER NOT NULL,
          completedNaturally INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_focus_sessions_time ON FocusSessions (startTime DESC)
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ActiveFocus (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          type TEXT NOT NULL,
          status TEXT NOT NULL,
          targetSeconds INTEGER NOT NULL,
          startTime INTEGER NOT NULL,
          expectedEndTime INTEGER NOT NULL,
          remainingSeconds INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS AppLimits (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          appName TEXT NOT NULL UNIQUE,
          exePath TEXT,
          limitMinutes INTEGER NOT NULL,
          warningPercentage INTEGER NOT NULL DEFAULT 80,
          isEnabled INTEGER NOT NULL DEFAULT 1,
          createdAt INTEGER NOT NULL,
          updatedAt INTEGER NOT NULL
        )
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_app_limits_app ON AppLimits (appName)
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS LimitNotificationLog (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          limitId INTEGER NOT NULL,
          notificationType TEXT NOT NULL,
          dateKey TEXT NOT NULL,
          notifiedAt INTEGER NOT NULL,
          UNIQUE(limitId, notificationType, dateKey)
        )
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_limit_notif_date ON LimitNotificationLog (dateKey)
      ''');
    }
    if (oldVersion < 5) {
      await db.execute('''
        ALTER TABLE AppLimits ADD COLUMN isEnforced INTEGER NOT NULL DEFAULT 0
      ''');
    }
  }

  Future<AppSession> insertSession(AppSession session) async {
    final db = await database;
    final id = await db.insert('AppSessions', session.toMap());
    return AppSession(
      id: id,
      appName: session.appName,
      exePath: session.exePath,
      startTime: session.startTime,
      endTime: session.endTime,
    );
  }

  Future<void> updateSessionEndTime(int id, DateTime endTime) async {
    final db = await database;
    await db.update(
      'AppSessions',
      {'endTime': endTime.millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<AppSession>> getSessionsForDay(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day + 1);
    return getSessionsForRange(startOfDay, endOfDay);
  }

  Future<List<AppSession>> getSessionsForRange(DateTime start, DateTime end) async {
    final db = await database;
    final maps = await db.query(
      'AppSessions',
      where: 'startTime < ? AND endTime > ?',
      whereArgs: [
        end.millisecondsSinceEpoch,
        start.millisecondsSinceEpoch,
      ],
      orderBy: 'startTime ASC',
    );

    return maps.map((map) => AppSession.fromMap(map)).toList();
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final maps = await db.query(
      'Settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return maps.first['value'] as String?;
    }
    return null;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'Settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<FocusSessionRecord> insertFocusSession(FocusSessionRecord session) async {
    final db = await database;
    final id = await db.insert('FocusSessions', session.toMap());
    return FocusSessionRecord(
      id: id,
      type: session.type,
      plannedDuration: session.plannedDuration,
      actualDuration: session.actualDuration,
      startTime: session.startTime,
      endTime: session.endTime,
      completedNaturally: session.completedNaturally,
    );
  }

  Future<List<FocusSessionRecord>> getRecentFocusSessions({int limit = 20}) async {
    final db = await database;
    final maps = await db.query(
      'FocusSessions',
      orderBy: 'startTime DESC',
      limit: limit,
    );
    return maps.map((map) => FocusSessionRecord.fromMap(map)).toList();
  }

  Future<void> saveActiveFocusState(ActiveFocusState state) async {
    final db = await database;
    final map = state.toMap();
    map['id'] = 1;
    await db.insert(
      'ActiveFocus',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ActiveFocusState?> getActiveFocusState() async {
    final db = await database;
    final maps = await db.query(
      'ActiveFocus',
      where: 'id = 1',
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return ActiveFocusState.fromMap(maps.first);
    }
    return null;
  }

  Future<void> clearActiveFocusState() async {
    final db = await database;
    await db.delete('ActiveFocus', where: 'id = 1');
  }

  // --- App Limits Persistence ---

  Future<AppLimit> insertLimit(AppLimit limit) async {
    final db = await database;
    final id = await db.insert(
      'AppLimits',
      limit.toMap(),
      conflictAlgorithm: ConflictAlgorithm.fail,
    );
    return limit.copyWith(id: id);
  }

  Future<void> updateLimit(AppLimit limit) async {
    final db = await database;
    await db.update(
      'AppLimits',
      limit.toMap(),
      where: 'id = ?',
      whereArgs: [limit.id],
    );
  }

  Future<void> deleteLimit(int id) async {
    final db = await database;
    await db.delete('AppLimits', where: 'id = ?', whereArgs: [id]);
    await db.delete('LimitNotificationLog', where: 'limitId = ?', whereArgs: [id]);
  }

  Future<List<AppLimit>> getAllLimits() async {
    final db = await database;
    final maps = await db.query('AppLimits', orderBy: 'appName ASC');
    return maps.map((map) => AppLimit.fromMap(map)).toList();
  }

  Future<AppLimit?> getLimitById(int id) async {
    final db = await database;
    final maps = await db.query(
      'AppLimits',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return AppLimit.fromMap(maps.first);
    }
    return null;
  }

  Future<AppLimit?> getLimitByAppName(String appName) async {
    final db = await database;
    final maps = await db.query(
      'AppLimits',
      where: 'LOWER(appName) = ?',
      whereArgs: [appName.toLowerCase()],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return AppLimit.fromMap(maps.first);
    }
    return null;
  }

  Future<bool> hasLimitNotificationBeenSent(
    int limitId,
    String notificationType,
    String dateKey,
  ) async {
    final db = await database;
    final maps = await db.query(
      'LimitNotificationLog',
      where: 'limitId = ? AND notificationType = ? AND dateKey = ?',
      whereArgs: [limitId, notificationType, dateKey],
      limit: 1,
    );
    return maps.isNotEmpty;
  }

  Future<void> recordLimitNotificationSent(
    int limitId,
    String notificationType,
    String dateKey,
    DateTime timestamp,
  ) async {
    final db = await database;
    await db.insert(
      'LimitNotificationLog',
      {
        'limitId': limitId,
        'notificationType': notificationType,
        'dateKey': dateKey,
        'notifiedAt': timestamp.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<String>> getDistinctTrackedApps() async {
    final db = await database;
    final maps = await db.query(
      'AppSessions',
      distinct: true,
      columns: ['appName'],
      where: 'appName IS NOT NULL AND TRIM(appName) != ?',
      whereArgs: [''],
      orderBy: 'appName ASC',
    );
    final seen = <String>{};
    final result = <String>[];
    for (final m in maps) {
      final name = (m['appName'] as String?)?.trim();
      if (name != null && name.isNotEmpty) {
        if (seen.add(name.toLowerCase())) {
          result.add(name);
        }
      }
    }
    result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  /// Returns distinct application records with both appName and exePath from tracked history.
  Future<List<Map<String, String>>> getDistinctTrackedAppsWithPaths() async {
    final db = await database;
    final maps = await db.query(
      'AppSessions',
      distinct: true,
      columns: ['appName', 'exePath'],
      where: 'appName IS NOT NULL AND TRIM(appName) != ?',
      whereArgs: [''],
      orderBy: 'appName ASC',
    );
    final result = <Map<String, String>>[];
    final seen = <String>{};
    for (final m in maps) {
      final name = (m['appName'] as String?)?.trim() ?? '';
      final exe = (m['exePath'] as String?)?.trim() ?? '';
      if (name.isNotEmpty) {
        final key = '${name.toLowerCase()}|${exe.toLowerCase()}';
        if (seen.add(key)) {
          result.add({'appName': name, 'exePath': exe});
        }
      }
    }
    return result;
  }
}

