import 'package:flutter_test/flutter_test.dart';
import 'package:balance/core/services/settings_service.dart';
import 'package:balance/core/services/usage_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SettingsService Tests', () {
    late UsageRepository repository;
    late SettingsService settingsService;

    setUp(() async {
      repository = UsageRepository(dbName: 'settings_test.db');
      final db = await repository.database;
      await db.delete('Settings');
      settingsService = SettingsService(repository: repository);
      await settingsService.init();
    });

    test('Defaults to dark mode and 2 minutes idle timeout', () {
      expect(settingsService.darkMode, isTrue);
      expect(settingsService.idleTimeoutMinutes, equals(2.0));
      expect(settingsService.notifications, isTrue);
    });

    test('Persists and restores dark mode toggle', () async {
      await settingsService.setDarkMode(false);
      expect(settingsService.darkMode, isFalse);

      // Verify saved in repository
      final saved = await repository.getSetting('darkMode');
      expect(saved, equals('false'));

      // New instance restoring from repository
      final newService = SettingsService(repository: repository);
      await newService.init();
      expect(newService.darkMode, isFalse);

      // Revert to true
      await newService.setDarkMode(true);
      expect(newService.darkMode, isTrue);
    });

    test('Persists and restores idle timeout slider value', () async {
      await settingsService.setIdleTimeoutMinutes(8.0);
      expect(settingsService.idleTimeoutMinutes, equals(8.0));

      final saved = await repository.getSetting('idleTimeoutMinutes');
      expect(saved, equals('8.0'));

      final newService = SettingsService(repository: repository);
      await newService.init();
      expect(newService.idleTimeoutMinutes, equals(8.0));
    });

    test('Persists and restores notifications toggle', () async {
      await settingsService.setNotifications(false);
      expect(settingsService.notifications, isFalse);

      final saved = await repository.getSetting('notifications');
      expect(saved, equals('false'));

      final newService = SettingsService(repository: repository);
      await newService.init();
      expect(newService.notifications, isFalse);
    });
  });
}
