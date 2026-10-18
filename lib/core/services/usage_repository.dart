import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'dart:io';
import '../models/app_session.dart';
import '../models/focus_session.dart';
import '../models/focus_preset.dart';
import '../models/app_limit.dart';

class UsageRepository {
  final String dbName;
  final String? baseDirectory;
  final bool enableLegacyMigration;
  final List<String>? legacyCandidates;
  Database? _db;

  UsageRepository({
    this.dbName = 'usage.db',
    this.baseDirectory,
    this.enableLegacyMigration = true,
    this.legacyCandidates,
  });

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

  /// Resolves the canonical directory for the SQLite database.
  /// On Windows, this defaults to `%LOCALAPPDATA%\Balance`.
  static String get defaultDatabaseDirectory {
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.trim().isNotEmpty) {
        return join(localAppData, 'Balance');
      }
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.trim().isNotEmpty) {
        return join(appData, 'Balance');
      }
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && userProfile.trim().isNotEmpty) {
        return join(userProfile, 'AppData', 'Local', 'Balance');
      }
    } else if (Platform.isLinux) {
      final xdgData = Platform.environment['XDG_DATA_HOME'];
      if (xdgData != null && xdgData.trim().isNotEmpty) {
        return join(xdgData, 'Balance');
      }
      final home = Platform.environment['HOME'];
      if (home != null && home.trim().isNotEmpty) {
        return join(home, '.local', 'share', 'Balance');
      }
    } else if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home != null && home.trim().isNotEmpty) {
        return join(home, 'Library', 'Application Support', 'Balance');
      }
    }
    return join(Directory.systemTemp.path, 'Balance');
  }

  /// Resolves the absolute database file path for [filePath] or [dbName].
  Future<String> resolveDatabasePath([String? filePath]) async {
    final name = filePath ?? dbName;
    if (name == inMemoryDatabasePath) {
      return inMemoryDatabasePath;
    }
    if (isAbsolute(name)) {
      return name;
    }
    if (baseDirectory != null) {
      return join(baseDirectory!, name);
    }
    if (name == 'usage.db') {
      return join(defaultDatabaseDirectory, name);
    }
    final dbPath = await getDatabasesPath();
    return join(dbPath, name);
  }

  /// Searches known locations where legacy development or early release databases were saved.
  Future<List<File>> findLegacyDatabases([String? targetPath]) async {
    if (legacyCandidates != null) {
      final list = <File>[];
      for (final p in legacyCandidates!) {
        final f = File(p);
        if (f.existsSync() && f.lengthSync() > 0) {
          list.add(f);
        }
      }
      return list;
    }

    final candidatePaths = <String>{};

    // 1. sqflite default desktop databases path
    try {
      final defaultDbDir = await getDatabasesPath();
      candidatePaths.add(join(defaultDbDir, 'usage.db'));
    } catch (_) {}

    // 2. Current working directory .dart_tool path
    candidatePaths.add(
      join(Directory.current.path, '.dart_tool', 'sqflite_common_ffi', 'databases', 'usage.db'),
    );

    // 3. Current working directory Release build output path
    candidatePaths.add(
      join(Directory.current.path, 'build', 'windows', 'x64', 'runner', 'Release', '.dart_tool', 'sqflite_common_ffi', 'databases', 'usage.db'),
    );

    // 4. Resolved executable directory and ancestors (up to 5 levels)
    try {
      var currentDir = File(Platform.resolvedExecutable).parent;
      for (var i = 0; i < 5; i++) {
        candidatePaths.add(
          join(currentDir.path, '.dart_tool', 'sqflite_common_ffi', 'databases', 'usage.db'),
        );
        final parent = currentDir.parent;
        if (parent.path == currentDir.path) break;
        currentDir = parent;
      }
    } catch (_) {}

    final results = <File>[];
    final normalizedTarget = targetPath != null ? canonicalize(targetPath) : null;
    final seenPaths = <String>{};

    for (final p in candidatePaths) {
      try {
        final canon = canonicalize(p);
        if (normalizedTarget != null && canon == normalizedTarget) {
          continue;
        }
        if (!seenPaths.add(canon)) {
          continue;
        }
        final file = File(p);
        if (file.existsSync() && file.lengthSync() > 0) {
          results.add(file);
        }
      } catch (_) {}
    }

    return results;
  }

  Future<void> _performPreOpenMigration(String targetPath) async {
    try {
      final targetFile = File(targetPath);
      if (await targetFile.exists()) {
        return;
      }

      final legacyFiles = await findLegacyDatabases(targetPath);
      if (legacyFiles.isEmpty) return;

      // Pick the legacy database with the largest file size
      legacyFiles.sort((a, b) {
        final lenA = a.existsSync() ? a.lengthSync() : 0;
        final lenB = b.existsSync() ? b.lengthSync() : 0;
        return lenB.compareTo(lenA);
      });

      final bestCandidate = legacyFiles.first;
      if (await bestCandidate.exists() && bestCandidate.lengthSync() > 0) {
        final targetDir = Directory(dirname(targetPath));
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }
        await bestCandidate.copy(targetPath);
      }
    } catch (_) {
      // Safe fallback: never let migration errors block database initialization
    }
  }

  Future<void> _performPostOpenMerge(Database db, String targetPath) async {
    try {
      // Check if legacy data was already imported
      final settingRows = await db.query(
        'Settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['legacy_data_imported'],
        limit: 1,
      );
      if (settingRows.isNotEmpty && settingRows.first['value'] == 'true') {
        return;
      }

      final legacyFiles = await findLegacyDatabases(targetPath);
      final normalizedTarget = canonicalize(targetPath);

      for (final legacyFile in legacyFiles) {
        if (!await legacyFile.exists() || legacyFile.lengthSync() == 0) continue;
        if (canonicalize(legacyFile.path) == normalizedTarget) continue;

        try {
          final legacyDb = await databaseFactory.openDatabase(
            legacyFile.path,
            options: OpenDatabaseOptions(readOnly: true),
          );

          await _mergeLegacyData(db, legacyDb);
          await legacyDb.close();
        } catch (_) {}
      }

      await db.insert(
        'Settings',
        {'key': 'legacy_data_imported', 'value': 'true'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      // Safe fallback: never throw unhandled exception
    }
  }

  Future<void> _mergeLegacyData(Database targetDb, Database legacyDb) async {
    // 1. AppSessions (deduplicate by appName, exePath, startTime, endTime)
    try {
      final legacySessions = await legacyDb.query('AppSessions');
      for (final s in legacySessions) {
        final existing = await targetDb.query(
          'AppSessions',
          where: 'appName = ? AND exePath = ? AND startTime = ? AND endTime = ?',
          whereArgs: [s['appName'], s['exePath'], s['startTime'], s['endTime']],
          limit: 1,
        );
        if (existing.isEmpty) {
          await targetDb.insert('AppSessions', {
            'appName': s['appName'],
            'exePath': s['exePath'],
            'startTime': s['startTime'],
            'endTime': s['endTime'],
          });
        }
      }
    } catch (_) {}

    // 2. Settings (only insert keys that do not exist yet)
    try {
      final legacySettings = await legacyDb.query('Settings');
      for (final row in legacySettings) {
        final key = row['key'] as String?;
        if (key == null || key == 'legacy_data_imported') continue;
        final existing = await targetDb.query('Settings', where: 'key = ?', whereArgs: [key], limit: 1);
        if (existing.isEmpty) {
          await targetDb.insert('Settings', row);
        }
      }
    } catch (_) {}

    // 3. FocusSessions (deduplicate by startTime, endTime)
    try {
      final legacyFocus = await legacyDb.query('FocusSessions');
      for (final s in legacyFocus) {
        final existing = await targetDb.query(
          'FocusSessions',
          where: 'startTime = ? AND endTime = ?',
          whereArgs: [s['startTime'], s['endTime']],
          limit: 1,
        );
        if (existing.isEmpty) {
          await targetDb.insert('FocusSessions', {
            'type': s['type'],
            'plannedSeconds': s['plannedSeconds'],
            'actualSeconds': s['actualSeconds'],
            'startTime': s['startTime'],
            'endTime': s['endTime'],
            'completedNaturally': s['completedNaturally'],
            if (s.containsKey('presetName')) 'presetName': s['presetName'],
            if (s.containsKey('cycleIndex')) 'cycleIndex': s['cycleIndex'],
            if (s.containsKey('interruptionReason')) 'interruptionReason': s['interruptionReason'],
          });
        }
      }
    } catch (_) {}

    // 4. AppLimits (deduplicate by appName)
    try {
      final legacyLimits = await legacyDb.query('AppLimits');
      for (final lim in legacyLimits) {
        final appName = (lim['appName'] as String?)?.toLowerCase() ?? '';
        if (appName.isEmpty) continue;
        final existing = await targetDb.query(
          'AppLimits',
          where: 'LOWER(appName) = ?',
          whereArgs: [appName],
          limit: 1,
        );
        if (existing.isEmpty) {
          final map = Map<String, dynamic>.from(lim)..remove('id');
          await targetDb.insert('AppLimits', map);
        }
      }
    } catch (_) {}
  }

  Future<Database> _initDB(String filePath) async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final path = await resolveDatabasePath(filePath);

    if (path != inMemoryDatabasePath) {
      final dir = Directory(dirname(path));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      if (enableLegacyMigration && (filePath == 'usage.db' || baseDirectory != null)) {
        await _performPreOpenMigration(path);
      }
    }

    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 6,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createDB,
        onUpgrade: _onUpgradeDB,
      ),
    );

    if (path != inMemoryDatabasePath && enableLegacyMigration && (filePath == 'usage.db' || baseDirectory != null)) {
      await _performPostOpenMerge(db, path);
    }

    return db;
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
        completedNaturally INTEGER NOT NULL,
        presetName TEXT,
        cycleIndex INTEGER,
        interruptionReason TEXT
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
        remainingSeconds INTEGER NOT NULL,
        presetId INTEGER,
        presetName TEXT,
        currentCycle INTEGER NOT NULL DEFAULT 1,
        totalCycles INTEGER NOT NULL DEFAULT 4,
        isLongBreak INTEGER NOT NULL DEFAULT 0,
        lastTickTime INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS FocusPresets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        focusDurationSeconds INTEGER NOT NULL,
        shortBreakDurationSeconds INTEGER NOT NULL,
        longBreakDurationSeconds INTEGER NOT NULL,
        cyclesBeforeLongBreak INTEGER NOT NULL DEFAULT 4,
        autoStartBreaks INTEGER NOT NULL DEFAULT 0,
        autoStartFocus INTEGER NOT NULL DEFAULT 0,
        allowSkipBreak INTEGER NOT NULL DEFAULT 1,
        soundEnabled INTEGER NOT NULL DEFAULT 1,
        unblockDuringBreaks INTEGER NOT NULL DEFAULT 1,
        isDefault INTEGER NOT NULL DEFAULT 0,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_focus_presets_name ON FocusPresets (name)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS FocusPresetBlockedApps (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        presetId INTEGER NOT NULL,
        appName TEXT NOT NULL,
        exePath TEXT,
        FOREIGN KEY (presetId) REFERENCES FocusPresets(id) ON DELETE CASCADE,
        UNIQUE(presetId, appName)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_preset_blocked_apps_preset ON FocusPresetBlockedApps (presetId)
    ''');

    // Seed default presets
    for (final preset in FocusPreset.defaultPresets) {
      await db.insert(
        'FocusPresets',
        preset.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

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

  Future<bool> _tableExists(DatabaseExecutor db, String tableName) async {
    final res = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [tableName],
    );
    return res.isNotEmpty;
  }

  Future<bool> _columnExists(DatabaseExecutor db, String table, String column) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.any((row) => (row['name'] as String?)?.toLowerCase() == column.toLowerCase());
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
      if (await _tableExists(db, 'AppLimits')) {
        if (!await _columnExists(db, 'AppLimits', 'isEnforced')) {
          await db.execute('''
            ALTER TABLE AppLimits ADD COLUMN isEnforced INTEGER NOT NULL DEFAULT 0
          ''');
        }
      }
    }
    if (oldVersion < 6) {
      // 1. Create FocusPresets table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS FocusPresets (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          focusDurationSeconds INTEGER NOT NULL,
          shortBreakDurationSeconds INTEGER NOT NULL,
          longBreakDurationSeconds INTEGER NOT NULL,
          cyclesBeforeLongBreak INTEGER NOT NULL DEFAULT 4,
          autoStartBreaks INTEGER NOT NULL DEFAULT 0,
          autoStartFocus INTEGER NOT NULL DEFAULT 0,
          allowSkipBreak INTEGER NOT NULL DEFAULT 1,
          soundEnabled INTEGER NOT NULL DEFAULT 1,
          unblockDuringBreaks INTEGER NOT NULL DEFAULT 1,
          isDefault INTEGER NOT NULL DEFAULT 0,
          createdAt INTEGER NOT NULL,
          updatedAt INTEGER NOT NULL
        )
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_focus_presets_name ON FocusPresets (name)
      ''');

      // 2. Create FocusPresetBlockedApps table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS FocusPresetBlockedApps (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          presetId INTEGER NOT NULL,
          appName TEXT NOT NULL,
          exePath TEXT,
          FOREIGN KEY (presetId) REFERENCES FocusPresets(id) ON DELETE CASCADE,
          UNIQUE(presetId, appName)
        )
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_preset_blocked_apps_preset ON FocusPresetBlockedApps (presetId)
      ''');

      // 3. FocusSessions table: create if missing, or alter if existing
      final hasFocusSessions = await _tableExists(db, 'FocusSessions');
      if (!hasFocusSessions) {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS FocusSessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            plannedSeconds INTEGER NOT NULL,
            actualSeconds INTEGER NOT NULL,
            startTime INTEGER NOT NULL,
            endTime INTEGER NOT NULL,
            completedNaturally INTEGER NOT NULL,
            presetName TEXT,
            cycleIndex INTEGER,
            interruptionReason TEXT
          )
        ''');
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_focus_sessions_time ON FocusSessions (startTime DESC)
        ''');
      } else {
        if (!await _columnExists(db, 'FocusSessions', 'presetName')) {
          await db.execute('ALTER TABLE FocusSessions ADD COLUMN presetName TEXT');
        }
        if (!await _columnExists(db, 'FocusSessions', 'cycleIndex')) {
          await db.execute('ALTER TABLE FocusSessions ADD COLUMN cycleIndex INTEGER');
        }
        if (!await _columnExists(db, 'FocusSessions', 'interruptionReason')) {
          await db.execute('ALTER TABLE FocusSessions ADD COLUMN interruptionReason TEXT');
        }
      }

      // 4. ActiveFocus table: create if missing, or alter if existing
      final hasActiveFocus = await _tableExists(db, 'ActiveFocus');
      if (!hasActiveFocus) {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS ActiveFocus (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            type TEXT NOT NULL,
            status TEXT NOT NULL,
            targetSeconds INTEGER NOT NULL,
            startTime INTEGER NOT NULL,
            expectedEndTime INTEGER NOT NULL,
            remainingSeconds INTEGER NOT NULL,
            presetId INTEGER,
            presetName TEXT,
            currentCycle INTEGER NOT NULL DEFAULT 1,
            totalCycles INTEGER NOT NULL DEFAULT 4,
            isLongBreak INTEGER NOT NULL DEFAULT 0,
            lastTickTime INTEGER
          )
        ''');
      } else {
        if (!await _columnExists(db, 'ActiveFocus', 'presetId')) {
          await db.execute('ALTER TABLE ActiveFocus ADD COLUMN presetId INTEGER');
        }
        if (!await _columnExists(db, 'ActiveFocus', 'presetName')) {
          await db.execute('ALTER TABLE ActiveFocus ADD COLUMN presetName TEXT');
        }
        if (!await _columnExists(db, 'ActiveFocus', 'currentCycle')) {
          await db.execute('ALTER TABLE ActiveFocus ADD COLUMN currentCycle INTEGER NOT NULL DEFAULT 1');
        }
        if (!await _columnExists(db, 'ActiveFocus', 'totalCycles')) {
          await db.execute('ALTER TABLE ActiveFocus ADD COLUMN totalCycles INTEGER NOT NULL DEFAULT 4');
        }
        if (!await _columnExists(db, 'ActiveFocus', 'isLongBreak')) {
          await db.execute('ALTER TABLE ActiveFocus ADD COLUMN isLongBreak INTEGER NOT NULL DEFAULT 0');
        }
        if (!await _columnExists(db, 'ActiveFocus', 'lastTickTime')) {
          await db.execute('ALTER TABLE ActiveFocus ADD COLUMN lastTickTime INTEGER');
        }
      }

      // 5. Seed default presets
      for (final preset in FocusPreset.defaultPresets) {
        await db.insert(
          'FocusPresets',
          preset.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
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
    return session.copyWith(id: id);
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

  Future<List<FocusSessionRecord>> getFocusSessionsForRange(DateTime start, DateTime end) async {
    final db = await database;
    final maps = await db.query(
      'FocusSessions',
      where: 'startTime < ? AND endTime > ?',
      whereArgs: [
        end.millisecondsSinceEpoch,
        start.millisecondsSinceEpoch,
      ],
      orderBy: 'startTime ASC',
    );
    return maps.map((map) => FocusSessionRecord.fromMap(map)).toList();
  }

  Future<List<FocusSessionRecord>> getFocusSessionsForDay(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day + 1);
    return getFocusSessionsForRange(startOfDay, endOfDay);
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

  // --- Focus Presets & Blocked Apps Persistence ---

  Future<FocusPreset> insertFocusPreset(FocusPreset preset) async {
    final db = await database;
    return await db.transaction((txn) async {
      if (preset.isDefault) {
        await txn.update('FocusPresets', {'isDefault': 0});
      }
      final map = preset.toMap();
      final id = await txn.insert('FocusPresets', map);

      final insertedApps = <FocusPresetBlockedApp>[];
      for (final app in preset.blockedApps) {
        final appId = await txn.insert(
          'FocusPresetBlockedApps',
          app.toMap(overridePresetId: id),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        insertedApps.add(app.copyWith(id: appId, presetId: id));
      }
      return preset.copyWith(id: id, blockedApps: insertedApps);
    });
  }

  Future<void> updateFocusPreset(FocusPreset preset) async {
    if (preset.id == null) {
      throw ArgumentError('Cannot update preset without an id.');
    }
    final db = await database;
    await db.transaction((txn) async {
      if (preset.isDefault) {
        await txn.update(
          'FocusPresets',
          {'isDefault': 0},
          where: 'id != ?',
          whereArgs: [preset.id],
        );
      }
      final map = preset.toMap()..['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
      await txn.update(
        'FocusPresets',
        map,
        where: 'id = ?',
        whereArgs: [preset.id],
      );

      // Synchronize blocked apps
      await txn.delete(
        'FocusPresetBlockedApps',
        where: 'presetId = ?',
        whereArgs: [preset.id],
      );
      for (final app in preset.blockedApps) {
        await txn.insert(
          'FocusPresetBlockedApps',
          app.toMap(overridePresetId: preset.id),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> deleteFocusPreset(int presetId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('FocusPresetBlockedApps', where: 'presetId = ?', whereArgs: [presetId]);
      await txn.delete('FocusPresets', where: 'id = ?', whereArgs: [presetId]);
    });
  }

  Future<List<FocusPreset>> getAllFocusPresets() async {
    final db = await database;
    final presetRows = await db.query(
      'FocusPresets',
      orderBy: 'isDefault DESC, name ASC',
    );
    if (presetRows.isEmpty) return [];

    final appRows = await db.query(
      'FocusPresetBlockedApps',
      orderBy: 'appName ASC',
    );

    final appsByPreset = <int, List<FocusPresetBlockedApp>>{};
    for (final row in appRows) {
      final pid = row['presetId'] as int?;
      if (pid != null) {
        appsByPreset.putIfAbsent(pid, () => []).add(FocusPresetBlockedApp.fromMap(row));
      }
    }

    return presetRows.map((row) {
      final id = row['id'] as int?;
      return FocusPreset.fromMap(
        row,
        blockedApps: id != null ? appsByPreset[id] ?? const [] : const [],
      );
    }).toList();
  }

  Future<FocusPreset?> getFocusPresetById(int id) async {
    final db = await database;
    final presetRows = await db.query(
      'FocusPresets',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (presetRows.isEmpty) return null;

    final appRows = await db.query(
      'FocusPresetBlockedApps',
      where: 'presetId = ?',
      whereArgs: [id],
      orderBy: 'appName ASC',
    );
    final apps = appRows.map((r) => FocusPresetBlockedApp.fromMap(r)).toList();
    return FocusPreset.fromMap(presetRows.first, blockedApps: apps);
  }

  Future<FocusPreset?> getFocusPresetByName(String name) async {
    final db = await database;
    final presetRows = await db.query(
      'FocusPresets',
      where: 'LOWER(name) = ?',
      whereArgs: [name.trim().toLowerCase()],
      limit: 1,
    );
    if (presetRows.isEmpty) return null;

    final id = presetRows.first['id'] as int?;
    List<FocusPresetBlockedApp> apps = [];
    if (id != null) {
      final appRows = await db.query(
        'FocusPresetBlockedApps',
        where: 'presetId = ?',
        whereArgs: [id],
        orderBy: 'appName ASC',
      );
      apps = appRows.map((r) => FocusPresetBlockedApp.fromMap(r)).toList();
    }
    return FocusPreset.fromMap(presetRows.first, blockedApps: apps);
  }

  Future<FocusPreset?> getDefaultFocusPreset() async {
    final db = await database;
    final presetRows = await db.query(
      'FocusPresets',
      where: 'isDefault = 1',
      limit: 1,
    );
    if (presetRows.isEmpty) {
      final all = await getAllFocusPresets();
      return all.isNotEmpty ? all.first : null;
    }
    final id = presetRows.first['id'] as int?;
    List<FocusPresetBlockedApp> apps = [];
    if (id != null) {
      final appRows = await db.query(
        'FocusPresetBlockedApps',
        where: 'presetId = ?',
        whereArgs: [id],
        orderBy: 'appName ASC',
      );
      apps = appRows.map((r) => FocusPresetBlockedApp.fromMap(r)).toList();
    }
    return FocusPreset.fromMap(presetRows.first, blockedApps: apps);
  }

  Future<List<FocusPresetBlockedApp>> getBlockedAppsForPreset(int presetId) async {
    final db = await database;
    final appRows = await db.query(
      'FocusPresetBlockedApps',
      where: 'presetId = ?',
      whereArgs: [presetId],
      orderBy: 'appName ASC',
    );
    return appRows.map((r) => FocusPresetBlockedApp.fromMap(r)).toList();
  }

  Future<void> setBlockedAppsForPreset(int presetId, List<FocusPresetBlockedApp> apps) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'FocusPresetBlockedApps',
        where: 'presetId = ?',
        whereArgs: [presetId],
      );
      for (final app in apps) {
        await txn.insert(
          'FocusPresetBlockedApps',
          app.toMap(overridePresetId: presetId),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }
}

