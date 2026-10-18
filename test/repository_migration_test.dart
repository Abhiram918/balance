import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:balance/core/models/app_limit.dart';
import 'package:balance/core/models/app_session.dart';
import 'package:balance/core/models/focus_session.dart';
import 'package:balance/core/models/focus_preset.dart';
import 'package:balance/core/services/usage_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Database Schema and Migration Tests', () {
    test('Migration from v1 preserves existing records and adds index and settings', () async {
      final tempDir = await Directory.systemTemp.createTemp('balance_migration_test');
      final dbPath = '${tempDir.path}${Platform.pathSeparator}migration_test.db';

      // 1. Create a version 1 database with the old schema
      var db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE AppSessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                appName TEXT NOT NULL,
                exePath TEXT NOT NULL,
                startTime INTEGER NOT NULL,
                endTime INTEGER NOT NULL
              )
            ''');
          },
        ),
      );

      // Insert test records into v1
      final now = DateTime.now();
      await db.insert('AppSessions', {
        'appName': 'V1 Old App',
        'exePath': r'C:\old.exe',
        'startTime': now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
        'endTime': now.millisecondsSinceEpoch,
      });

      await db.close();

      // 2. Open with the new v2 schema with onUpgrade
      db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 2,
          onUpgrade: (db, oldVersion, newVersion) async {
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
          },
        ),
      );

      // Verify old records are preserved
      final records = await db.query('AppSessions');
      expect(records.length, equals(1));
      expect(records.first['appName'], equals('V1 Old App'));

      // Verify Settings table exists and is writable
      await db.insert('Settings', {'key': 'testKey', 'value': 'testVal'});
      final settings = await db.query('Settings', where: 'key = ?', whereArgs: ['testKey']);
      expect(settings.first['value'], equals('testVal'));

      await db.close();
      await tempDir.delete(recursive: true);
    });

    test('getSessionsForDay retrieves sessions that overlap day boundaries', () async {
      final repository = UsageRepository(dbName: 'boundary_test.db');
      final db = await repository.database;
      await db.delete('AppSessions');
      final day = DateTime(2026, 10, 11);
      final startOfDay = DateTime(2026, 10, 11, 0, 0);

      // Session started yesterday at 23:30, ended today at 00:30
      final crossingMidnightSession = AppSession(
        appName: 'MidnightApp',
        exePath: r'C:\midnight.exe',
        startTime: startOfDay.subtract(const Duration(minutes: 30)),
        endTime: startOfDay.add(const Duration(minutes: 30)),
      );

      // Session completely within today
      final normalSession = AppSession(
        appName: 'NormalApp',
        exePath: r'C:\normal.exe',
        startTime: DateTime(2026, 10, 11, 14, 0),
        endTime: DateTime(2026, 10, 11, 15, 0),
      );

      // Session completely in yesterday
      final yesterdaySession = AppSession(
        appName: 'YesterdayApp',
        exePath: r'C:\yesterday.exe',
        startTime: DateTime(2026, 10, 10, 10, 0),
        endTime: DateTime(2026, 10, 10, 11, 0),
      );

      await repository.insertSession(crossingMidnightSession);
      await repository.insertSession(normalSession);
      await repository.insertSession(yesterdaySession);

      final todaySessions = await repository.getSessionsForDay(day);

      expect(todaySessions.any((s) => s.appName == 'MidnightApp'), isTrue);
      expect(todaySessions.any((s) => s.appName == 'NormalApp'), isTrue);
      expect(todaySessions.any((s) => s.appName == 'YesterdayApp'), isFalse);
    });

    test('Migration from v2 to v3 creates FocusSessions and ActiveFocus tables and preserves records', () async {
      final tempDir = await Directory.systemTemp.createTemp('balance_v3_migration_test');
      final dbPath = '${tempDir.path}${Platform.pathSeparator}v3_migration.db';

      // 1. Create a version 2 database with AppSessions and Settings
      var db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE AppSessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                appName TEXT NOT NULL,
                exePath TEXT NOT NULL,
                startTime INTEGER NOT NULL,
                endTime INTEGER NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE Settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
              )
            ''');
          },
        ),
      );

      await db.insert('AppSessions', {
        'appName': 'V2 App',
        'exePath': r'C:\v2.exe',
        'startTime': 1000,
        'endTime': 2000,
      });
      await db.insert('Settings', {'key': 'theme', 'value': 'dark'});
      await db.close();

      // 2. Open using UsageRepository (which upgrades to v3)
      final repo = UsageRepository(dbName: dbPath);
      final upgradedDb = await repo.database;

      // Old records preserved
      final apps = await upgradedDb.query('AppSessions');
      expect(apps.length, equals(1));
      expect(apps.first['appName'], equals('V2 App'));

      final settingsVal = await repo.getSetting('theme');
      expect(settingsVal, equals('dark'));

      // v3 tables are writable
      final focusSession = FocusSessionRecord(
        type: FocusSessionType.focus,
        plannedDuration: const Duration(minutes: 25),
        actualDuration: const Duration(minutes: 25),
        startTime: DateTime.fromMillisecondsSinceEpoch(10000),
        endTime: DateTime.fromMillisecondsSinceEpoch(25000),
        completedNaturally: true,
      );
      final inserted = await repo.insertFocusSession(focusSession);
      expect(inserted.id, isNotNull);

      final recent = await repo.getRecentFocusSessions();
      expect(recent.length, equals(1));
      expect(recent.first.type, equals(FocusSessionType.focus));

      await repo.close();
      await tempDir.delete(recursive: true);
    });

    test('Migration from v3 to v4 creates AppLimits and LimitNotificationLog tables while preserving existing data', () async {
      final tempDir = await Directory.systemTemp.createTemp('balance_v4_migration_test');
      final dbPath = '${tempDir.path}${Platform.pathSeparator}v4_migration.db';

      // 1. Create a version 3 database with AppSessions, Settings, FocusSessions, ActiveFocus
      var db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE AppSessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                appName TEXT NOT NULL,
                exePath TEXT NOT NULL,
                startTime INTEGER NOT NULL,
                endTime INTEGER NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE Settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE FocusSessions (
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
              CREATE TABLE ActiveFocus (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                type TEXT NOT NULL,
                status TEXT NOT NULL,
                targetSeconds INTEGER NOT NULL,
                startTime INTEGER NOT NULL,
                expectedEndTime INTEGER NOT NULL,
                remainingSeconds INTEGER NOT NULL
              )
            ''');
          },
        ),
      );

      // Populate v3 records
      await db.insert('AppSessions', {
        'appName': 'V3 Chrome',
        'exePath': r'C:\chrome.exe',
        'startTime': 100000,
        'endTime': 200000,
      });
      await db.insert('Settings', {'key': 'idleTimeout', 'value': '300'});
      await db.insert('FocusSessions', {
        'type': 'focus',
        'plannedSeconds': 1500,
        'actualSeconds': 1500,
        'startTime': 100000,
        'endTime': 101500,
        'completedNaturally': 1,
      });
      await db.close();

      // 2. Open using UsageRepository (which runs onUpgrade for v3 -> v4)
      final repo = UsageRepository(dbName: dbPath);
      final upgradedDb = await repo.database;

      // Verify all v3 records are preserved
      final apps = await upgradedDb.query('AppSessions');
      expect(apps.length, equals(1));
      expect(apps.first['appName'], equals('V3 Chrome'));

      final settingsVal = await repo.getSetting('idleTimeout');
      expect(settingsVal, equals('300'));

      final focusSessions = await repo.getRecentFocusSessions();
      expect(focusSessions.length, equals(1));
      expect(focusSessions.first.plannedDuration, equals(const Duration(seconds: 1500)));

      // 3. Verify v4 AppLimits table works with CRUD
      final limit = AppLimit(
        appName: 'V3 Chrome',
        exePath: r'C:\chrome.exe',
        limitDuration: const Duration(hours: 1),
        warningThresholdPercentage: 75,
        isEnabled: true,
        createdAt: DateTime(2026, 10, 11, 10, 0),
        updatedAt: DateTime(2026, 10, 11, 10, 0),
      );
      final insertedLimit = await repo.insertLimit(limit);
      expect(insertedLimit.id, isNotNull);

      final retrievedLimits = await repo.getAllLimits();
      expect(retrievedLimits.length, equals(1));
      expect(retrievedLimits.first.appName, equals('V3 Chrome'));
      expect(retrievedLimits.first.warningThresholdPercentage, equals(75));

      // 4. Verify v4 LimitNotificationLog table works with deduplication
      final wasSentBefore = await repo.hasLimitNotificationBeenSent(
        insertedLimit.id!,
        'warning',
        '2026-10-11',
      );
      expect(wasSentBefore, isFalse);

      await repo.recordLimitNotificationSent(
        insertedLimit.id!,
        'warning',
        '2026-10-11',
        DateTime(2026, 10, 11, 10, 45),
      );

      final wasSentAfter = await repo.hasLimitNotificationBeenSent(
        insertedLimit.id!,
        'warning',
        '2026-10-11',
      );
      expect(wasSentAfter, isTrue);

      // Verify different date is not marked as sent
      final wasSentNextDay = await repo.hasLimitNotificationBeenSent(
        insertedLimit.id!,
        'warning',
        '2026-10-12',
      );
      expect(wasSentNextDay, isFalse);

      await repo.close();
      await tempDir.delete(recursive: true);
    });

    test('Migration from v4 to v5 adds isEnforced column and preserves existing app limits', () async {
      final tempDir = await Directory.systemTemp.createTemp('balance_v5_migration_test');
      final dbPath = '${tempDir.path}${Platform.pathSeparator}v5_migration.db';

      // 1. Create a version 4 database with AppLimits table (without isEnforced column)
      var db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 4,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE AppLimits (
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
          },
        ),
      );

      // Populate existing v4 record
      final now = DateTime(2026, 10, 11, 10, 0);
      await db.insert('AppLimits', {
        'appName': 'Telegram',
        'exePath': r'C:\Telegram.exe',
        'limitMinutes': 5,
        'warningPercentage': 85,
        'isEnabled': 1,
        'createdAt': now.millisecondsSinceEpoch,
        'updatedAt': now.millisecondsSinceEpoch,
      });
      await db.close();

      // 2. Open using UsageRepository (which upgrades v4 -> v5)
      final repo = UsageRepository(dbName: dbPath);
      final upgradedDb = await repo.database;

      // Verify v4 records are preserved and isEnforced defaults to false (0)
      final rawRecords = await upgradedDb.query('AppLimits');
      expect(rawRecords.length, equals(1));
      expect(rawRecords.first['appName'], equals('Telegram'));
      expect(rawRecords.first['isEnforced'], equals(0));

      final limits = await repo.getAllLimits();
      expect(limits.length, equals(1));
      final telegramLimit = limits.first;
      expect(telegramLimit.appName, equals('Telegram'));
      expect(telegramLimit.limitMinutes, equals(5));
      expect(telegramLimit.warningThresholdPercentage, equals(85));
      expect(telegramLimit.isEnabled, isTrue);
      expect(telegramLimit.isEnforced, isFalse);

      // 3. Update existing limit to enable enforcement
      final enforcedLimit = telegramLimit.copyWith(isEnforced: true);
      await repo.updateLimit(enforcedLimit);

      final updated = await repo.getLimitById(enforcedLimit.id!);
      expect(updated, isNotNull);
      expect(updated!.isEnforced, isTrue);

      // 4. Insert a new limit with enforcement enabled
      final newLimit = AppLimit(
        appName: 'Discord',
        limitDuration: const Duration(hours: 1),
        isEnforced: true,
        createdAt: now,
        updatedAt: now,
      );
      final inserted = await repo.insertLimit(newLimit);
      expect(inserted.id, isNotNull);
      expect(inserted.isEnforced, isTrue);

      final retrievedDiscord = await repo.getLimitByAppName('Discord');
      expect(retrievedDiscord, isNotNull);
      expect(retrievedDiscord!.isEnforced, isTrue);

      await repo.close();
      await tempDir.delete(recursive: true);
    });

    test('Migration from v5 to v6 preserves all existing data, seeds default presets, and enables preset and metadata CRUD', () async {
      final tempDir = await Directory.systemTemp.createTemp('balance_v6_migration_test');
      final dbPath = '${tempDir.path}${Platform.pathSeparator}v6_migration.db';

      // 1. Create a version 5 database with v5 schema
      var db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 5,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE AppSessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                appName TEXT NOT NULL,
                exePath TEXT NOT NULL,
                startTime INTEGER NOT NULL,
                endTime INTEGER NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE Settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE FocusSessions (
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
              CREATE TABLE ActiveFocus (
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
              CREATE TABLE AppLimits (
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
              CREATE TABLE LimitNotificationLog (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                limitId INTEGER NOT NULL,
                notificationType TEXT NOT NULL,
                dateKey TEXT NOT NULL,
                notifiedAt INTEGER NOT NULL,
                UNIQUE(limitId, notificationType, dateKey)
              )
            ''');
          },
        ),
      );

      // Populate v5 data across all existing tables
      final baseTime = DateTime(2026, 10, 18, 10, 0);
      await db.insert('AppSessions', {
        'appName': 'VS Code',
        'exePath': r'C:\Code.exe',
        'startTime': baseTime.millisecondsSinceEpoch,
        'endTime': baseTime.add(const Duration(hours: 2)).millisecondsSinceEpoch,
      });

      await db.insert('Settings', {'key': 'notifications_enabled', 'value': 'true'});

      await db.insert('FocusSessions', {
        'type': 'focus',
        'plannedSeconds': 1500,
        'actualSeconds': 1400,
        'startTime': baseTime.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
        'endTime': baseTime.millisecondsSinceEpoch,
        'completedNaturally': 1,
      });

      await db.insert('ActiveFocus', {
        'id': 1,
        'type': 'focus',
        'status': 'running',
        'targetSeconds': 1500,
        'startTime': baseTime.millisecondsSinceEpoch,
        'expectedEndTime': baseTime.add(const Duration(minutes: 25)).millisecondsSinceEpoch,
        'remainingSeconds': 1200,
      });

      final limitId = await db.insert('AppLimits', {
        'appName': 'YouTube',
        'exePath': r'C:\browser.exe',
        'limitMinutes': 30,
        'warningPercentage': 80,
        'isEnabled': 1,
        'isEnforced': 1,
        'createdAt': baseTime.millisecondsSinceEpoch,
        'updatedAt': baseTime.millisecondsSinceEpoch,
      });

      await db.insert('LimitNotificationLog', {
        'limitId': limitId,
        'notificationType': 'limit_reached',
        'dateKey': '2026-10-18',
        'notifiedAt': baseTime.millisecondsSinceEpoch,
      });

      await db.close();

      // 2. Open via UsageRepository (triggers v5 -> v6 migration)
      final repo = UsageRepository(dbName: dbPath);
      final upgradedDb = await repo.database;

      // Verify DB version is 6
      final version = await upgradedDb.getVersion();
      expect(version, equals(6));

      // Verify existing AppSessions preserved
      final sessions = await repo.getSessionsForRange(
        baseTime.subtract(const Duration(minutes: 1)),
        baseTime.add(const Duration(hours: 3)),
      );
      expect(sessions.length, equals(1));
      expect(sessions.first.appName, equals('VS Code'));

      // Verify existing Settings preserved
      final settingVal = await repo.getSetting('notifications_enabled');
      expect(settingVal, equals('true'));

      // Verify existing FocusSessions preserved (with null new columns)
      final focusHistory = await repo.getRecentFocusSessions();
      expect(focusHistory.length, equals(1));
      expect(focusHistory.first.plannedDuration, equals(const Duration(seconds: 1500)));
      expect(focusHistory.first.actualDuration, equals(const Duration(seconds: 1400)));
      expect(focusHistory.first.presetName, isNull);
      expect(focusHistory.first.cycleIndex, isNull);
      expect(focusHistory.first.interruptionReason, isNull);

      // Verify existing ActiveFocus preserved with safe defaults for new columns
      final active = await repo.getActiveFocusState();
      expect(active, isNotNull);
      expect(active!.status, equals(FocusStatus.running));
      expect(active.remainingDuration, equals(const Duration(seconds: 1200)));
      expect(active.currentCycle, equals(1));
      expect(active.totalCycles, equals(4));
      expect(active.isLongBreak, isFalse);
      expect(active.presetId, isNull);
      expect(active.presetName, isNull);
      expect(active.lastTickTime, isNull);

      // Verify existing AppLimits preserved
      final limits = await repo.getAllLimits();
      expect(limits.length, equals(1));
      expect(limits.first.appName, equals('YouTube'));
      expect(limits.first.isEnforced, isTrue);

      // Verify existing LimitNotificationLog preserved
      final notificationSent = await repo.hasLimitNotificationBeenSent(
        limitId,
        'limit_reached',
        '2026-10-18',
      );
      expect(notificationSent, isTrue);

      // Verify default presets seeded
      final presets = await repo.getAllFocusPresets();
      expect(presets.length, equals(3));
      final names = presets.map((p) => p.name).toSet();
      expect(names, containsAll(['Standard Pomodoro', 'Deep Work', 'Quick Sprint']));

      final defaultPreset = await repo.getDefaultFocusPreset();
      expect(defaultPreset, isNotNull);
      expect(defaultPreset!.name, equals('Standard Pomodoro'));
      expect(defaultPreset.isDefault, isTrue);

      // 3. Test Focus Preset CRUD & blocked applications
      final customPreset = FocusPreset(
        name: 'Coding Sprint',
        focusDuration: const Duration(minutes: 30),
        shortBreakDuration: const Duration(minutes: 5),
        longBreakDuration: const Duration(minutes: 15),
        cyclesBeforeLongBreak: 3,
        autoStartBreaks: true,
        isDefault: false,
        blockedApps: const [
          FocusPresetBlockedApp(appName: 'Steam', exePath: r'C:\Steam\steam.exe'),
          FocusPresetBlockedApp(appName: 'Discord', exePath: r'C:\Discord\discord.exe'),
        ],
      );

      final insertedPreset = await repo.insertFocusPreset(customPreset);
      expect(insertedPreset.id, isNotNull);
      expect(insertedPreset.blockedApps.length, equals(2));

      // Query by ID
      final fetchedById = await repo.getFocusPresetById(insertedPreset.id!);
      expect(fetchedById, isNotNull);
      expect(fetchedById!.name, equals('Coding Sprint'));
      expect(fetchedById.blockedApps.length, equals(2));
      expect(fetchedById.blockedApps.map((a) => a.appName).toSet(), containsAll(['Steam', 'Discord']));

      // Query by Name (case-insensitive)
      final fetchedByName = await repo.getFocusPresetByName('coding sprint');
      expect(fetchedByName, isNotNull);
      expect(fetchedByName!.id, equals(insertedPreset.id));

      // Update preset
      final updatedPreset = fetchedById.copyWith(
        name: 'Intense Coding Sprint',
        isDefault: true,
        blockedApps: const [
          FocusPresetBlockedApp(appName: 'Steam', exePath: r'C:\Steam\steam.exe'),
        ],
      );
      await repo.updateFocusPreset(updatedPreset);

      final verifiedUpdated = await repo.getFocusPresetById(insertedPreset.id!);
      expect(verifiedUpdated!.name, equals('Intense Coding Sprint'));
      expect(verifiedUpdated.isDefault, isTrue);
      expect(verifiedUpdated.blockedApps.length, equals(1));
      expect(verifiedUpdated.blockedApps.first.appName, equals('Steam'));

      // Check that former default preset was unset
      final oldDefault = await repo.getFocusPresetByName('Standard Pomodoro');
      expect(oldDefault!.isDefault, isFalse);

      // Set blocked apps independently
      await repo.setBlockedAppsForPreset(insertedPreset.id!, const [
        FocusPresetBlockedApp(appName: 'Twitter'),
        FocusPresetBlockedApp(appName: 'Reddit'),
      ]);
      final apps = await repo.getBlockedAppsForPreset(insertedPreset.id!);
      expect(apps.length, equals(2));
      expect(apps.map((a) => a.appName).toSet(), containsAll(['Twitter', 'Reddit']));

      // Delete preset and verify cascade
      await repo.deleteFocusPreset(insertedPreset.id!);
      final deletedPreset = await repo.getFocusPresetById(insertedPreset.id!);
      expect(deletedPreset, isNull);
      final remainingApps = await repo.getBlockedAppsForPreset(insertedPreset.id!);
      expect(remainingApps, isEmpty);

      // 4. Test new FocusSessionRecord metadata persistence
      final newSession = FocusSessionRecord(
        type: FocusSessionType.focus,
        plannedDuration: const Duration(minutes: 25),
        actualDuration: const Duration(minutes: 15),
        startTime: baseTime.add(const Duration(hours: 3)),
        endTime: baseTime.add(const Duration(hours: 3, minutes: 15)),
        completedNaturally: false,
        presetName: 'Deep Work',
        cycleIndex: 1,
        interruptionReason: 'User paused and stopped',
      );
      final insertedSession = await repo.insertFocusSession(newSession);
      expect(insertedSession.id, isNotNull);
      expect(insertedSession.presetName, equals('Deep Work'));
      expect(insertedSession.cycleIndex, equals(1));
      expect(insertedSession.interruptionReason, equals('User paused and stopped'));

      // 5. Test ActiveFocusState with cycle & preset persistence
      final newActiveState = ActiveFocusState(
        type: FocusSessionType.breakSession,
        status: FocusStatus.paused,
        targetDuration: const Duration(minutes: 5),
        startTime: baseTime.add(const Duration(hours: 4)),
        expectedEndTime: baseTime.add(const Duration(hours: 4, minutes: 5)),
        remainingDuration: const Duration(minutes: 3),
        presetId: 1,
        presetName: 'Standard Pomodoro',
        currentCycle: 2,
        totalCycles: 4,
        isLongBreak: false,
        lastTickTime: baseTime.add(const Duration(hours: 4, minutes: 2)),
      );
      await repo.saveActiveFocusState(newActiveState);

      final loadedActiveState = await repo.getActiveFocusState();
      expect(loadedActiveState, isNotNull);
      expect(loadedActiveState!.type, equals(FocusSessionType.breakSession));
      expect(loadedActiveState.status, equals(FocusStatus.paused));
      expect(loadedActiveState.presetId, equals(1));
      expect(loadedActiveState.presetName, equals('Standard Pomodoro'));
      expect(loadedActiveState.currentCycle, equals(2));
      expect(loadedActiveState.totalCycles, equals(4));
      expect(loadedActiveState.isLongBreak, isFalse);
      expect(loadedActiveState.lastTickTime, isNotNull);

      await repo.close();
      await tempDir.delete(recursive: true);
    });
  });
}
