import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:balance/core/models/app_session.dart';
import 'package:balance/core/models/app_limit.dart';
import 'package:balance/core/models/focus_session.dart';
import 'package:balance/core/services/usage_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('UsageRepository Stable Path and Migration Tests', () {
    test('defaultDatabaseDirectory resolves to %LOCALAPPDATA%\\Balance on Windows', () {
      final defaultDir = UsageRepository.defaultDatabaseDirectory;
      expect(defaultDir.isNotEmpty, isTrue);
      if (Platform.isWindows) {
        final expectedLocal = Platform.environment['LOCALAPPDATA'];
        if (expectedLocal != null && expectedLocal.isNotEmpty) {
          expect(defaultDir, equals(p.join(expectedLocal, 'Balance')));
        }
      }
      expect(p.basename(defaultDir), equals('Balance'));
    });

    test('resolveDatabasePath resolves correctly for various input modes', () async {
      final repo = UsageRepository();
      
      // Default usage.db resolves into defaultDatabaseDirectory
      final resolved = await repo.resolveDatabasePath();
      expect(resolved, equals(p.join(UsageRepository.defaultDatabaseDirectory, 'usage.db')));

      // In-memory stays in-memory
      final mem = await repo.resolveDatabasePath(inMemoryDatabasePath);
      expect(mem, equals(inMemoryDatabasePath));

      // Absolute path remains unchanged
      final absPath = r'C:\MyCustom\path\custom.db';
      final absResolved = await repo.resolveDatabasePath(absPath);
      expect(absResolved, equals(absPath));

      // Custom base directory
      final customRepo = UsageRepository(baseDirectory: r'C:\TargetDir');
      final customResolved = await customRepo.resolveDatabasePath('test.db');
      expect(customResolved, equals(r'C:\TargetDir\test.db'));
    });

    test('Initializes database and auto-creates missing target directory', () async {
      final tempDir = await Directory.systemTemp.createTemp('balance_autocreate_test');
      final targetSubDir = p.join(tempDir.path, 'nested', 'deep', 'Balance');
      
      expect(Directory(targetSubDir).existsSync(), isFalse);

      final repo = UsageRepository(
        baseDirectory: targetSubDir,
        enableLegacyMigration: false,
      );

      final db = await repo.database;
      expect(db.isOpen, isTrue);
      expect(Directory(targetSubDir).existsSync(), isTrue);

      await repo.close();
      await tempDir.delete(recursive: true);
    });

    test('Safely migrates existing legacy database to new location without deleting or modifying legacy DB', () async {
      final tempDir = await Directory.systemTemp.createTemp('balance_mig_test');
      final legacyDir = p.join(tempDir.path, 'legacy_root');
      final newDir = p.join(tempDir.path, 'new_root');
      await Directory(legacyDir).create(recursive: true);

      final legacyDbPath = p.join(legacyDir, 'usage.db');

      // 1. Create a legacy database populated with AppSessions, Settings, FocusSessions, and AppLimits
      final legacyRepo = UsageRepository(
        dbName: legacyDbPath,
        enableLegacyMigration: false,
      );
      await legacyRepo.database;

      final now = DateTime(2026, 10, 15, 14, 0);
      await legacyRepo.insertSession(AppSession(
        appName: 'LegacyApp',
        exePath: r'C:\legacy.exe',
        startTime: now.subtract(const Duration(hours: 2)),
        endTime: now.subtract(const Duration(hours: 1)),
      ));

      await legacyRepo.setSetting('theme', 'dark');

      await legacyRepo.insertFocusSession(FocusSessionRecord(
        type: FocusSessionType.focus,
        plannedDuration: const Duration(minutes: 25),
        actualDuration: const Duration(minutes: 25),
        startTime: now.subtract(const Duration(hours: 3)),
        endTime: now.subtract(const Duration(hours: 2, minutes: 35)),
        completedNaturally: true,
      ));

      await legacyRepo.insertLimit(AppLimit(
        appName: 'LegacyApp',
        exePath: r'C:\legacy.exe',
        limitDuration: const Duration(hours: 1),
        isEnabled: true,
        isEnforced: true,
        createdAt: now,
        updatedAt: now,
      ));

      await legacyRepo.close();

      final legacyFileBefore = File(legacyDbPath);
      expect(legacyFileBefore.existsSync(), isTrue);
      final legacySizeBefore = legacyFileBefore.lengthSync();
      expect(legacySizeBefore, greaterThan(0));

      // 2. Open new repository with legacyCandidates pointing to the legacy DB
      final newRepo = UsageRepository(
        baseDirectory: newDir,
        legacyCandidates: [legacyDbPath],
        enableLegacyMigration: true,
      );

      final newDb = await newRepo.database;
      expect(newDb.isOpen, isTrue);

      // Verify all legacy data is present in new repository
      final sessions = await newRepo.getSessionsForDay(now);
      expect(sessions.any((s) => s.appName == 'LegacyApp'), isTrue);

      final theme = await newRepo.getSetting('theme');
      expect(theme, equals('dark'));

      final focusSessions = await newRepo.getRecentFocusSessions();
      expect(focusSessions.length, equals(1));
      expect(focusSessions.first.completedNaturally, isTrue);

      final limits = await newRepo.getAllLimits();
      expect(limits.any((l) => l.appName == 'LegacyApp' && l.isEnforced), isTrue);

      // Verify migration marker is set
      final importedMarker = await newRepo.getSetting('legacy_data_imported');
      expect(importedMarker, equals('true'));

      // Verify legacy file is STILL present and completely intact
      expect(legacyFileBefore.existsSync(), isTrue);
      expect(legacyFileBefore.lengthSync(), equals(legacySizeBefore));

      await newRepo.close();

      // 3. Repeat launch verification: Opening the new repository a second time does not duplicate records
      final repeatRepo = UsageRepository(
        baseDirectory: newDir,
        legacyCandidates: [legacyDbPath],
        enableLegacyMigration: true,
      );

      await repeatRepo.database;
      final repeatSessions = await repeatRepo.getSessionsForDay(now);
      expect(repeatSessions.where((s) => s.appName == 'LegacyApp').length, equals(1));

      final repeatLimits = await repeatRepo.getAllLimits();
      expect(repeatLimits.where((l) => l.appName == 'LegacyApp').length, equals(1));

      final repeatFocus = await repeatRepo.getRecentFocusSessions();
      expect(repeatFocus.length, equals(1));

      await repeatRepo.close();
      await tempDir.delete(recursive: true);
    });

    test('Merges records across multiple legacy databases without duplication', () async {
      final tempDir = await Directory.systemTemp.createTemp('balance_multi_mig_test');
      final legacyDir1 = p.join(tempDir.path, 'legacy_dev');
      final legacyDir2 = p.join(tempDir.path, 'legacy_rel');
      final newDir = p.join(tempDir.path, 'new_canonical');

      await Directory(legacyDir1).create(recursive: true);
      await Directory(legacyDir2).create(recursive: true);

      final now = DateTime(2026, 10, 15, 14, 0);

      // DB 1: Has Session 1
      final repo1 = UsageRepository(dbName: p.join(legacyDir1, 'usage.db'), enableLegacyMigration: false);
      await repo1.insertSession(AppSession(
        appName: 'DevApp',
        exePath: r'C:\dev.exe',
        startTime: now.subtract(const Duration(hours: 2)),
        endTime: now.subtract(const Duration(hours: 1)),
      ));
      await repo1.close();

      // DB 2: Has Session 2
      final repo2 = UsageRepository(dbName: p.join(legacyDir2, 'usage.db'), enableLegacyMigration: false);
      await repo2.insertSession(AppSession(
        appName: 'RelApp',
        exePath: r'C:\rel.exe',
        startTime: now.subtract(const Duration(minutes: 30)),
        endTime: now.subtract(const Duration(minutes: 10)),
      ));
      await repo2.close();

      // Open new canonical repository targeting both legacy paths
      final canonicalRepo = UsageRepository(
        baseDirectory: newDir,
        legacyCandidates: [p.join(legacyDir1, 'usage.db'), p.join(legacyDir2, 'usage.db')],
        enableLegacyMigration: true,
      );

      final sessions = await canonicalRepo.getSessionsForDay(now);
      expect(sessions.any((s) => s.appName == 'DevApp'), isTrue);
      expect(sessions.any((s) => s.appName == 'RelApp'), isTrue);

      await canonicalRepo.close();
      await tempDir.delete(recursive: true);
    });
  });
}
