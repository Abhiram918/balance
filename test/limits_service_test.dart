import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:balance/core/models/app_session.dart';
import 'package:balance/core/services/focus_notification_service.dart';
import 'package:balance/core/services/limits_service.dart';
import 'package:balance/core/services/settings_service.dart';
import 'package:balance/core/services/usage_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class TestNotificationService extends FocusNotificationService {
  final List<String> warnings = [];
  final List<String> reached = [];

  TestNotificationService({super.settingsService});

  @override
  Future<bool> notifyAppLimitWarning({
    required String appName,
    required Duration used,
    required Duration limit,
    required int warningPercentage,
  }) async {
    if (settingsService != null && !settingsService!.notifications) {
      return false;
    }
    warnings.add(appName);
    return true;
  }

  @override
  Future<bool> notifyAppLimitReached({
    required String appName,
    required Duration used,
    required Duration limit,
  }) async {
    if (settingsService != null && !settingsService!.notifications) {
      return false;
    }
    reached.add(appName);
    return true;
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('LimitsService Tests', () {
    late Directory tempDir;
    late String dbPath;
    late UsageRepository repository;
    late SettingsService settingsService;
    late TestNotificationService notificationService;
    late DateTime testNow;
    DateTime getClock() => testNow;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('limits_service_test');
      dbPath = '${tempDir.path}${Platform.pathSeparator}test.db';
      repository = UsageRepository(dbName: dbPath);

      settingsService = SettingsService(repository: repository);
      await settingsService.init();

      notificationService = TestNotificationService(settingsService: settingsService);
      testNow = DateTime(2026, 10, 11, 14, 0); // Sunday 2:00 PM
    });

    tearDown(() async {
      await repository.close();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('Create, edit, toggle, and delete limits', () async {
      final service = LimitsService(
        repository: repository,
        notificationService: notificationService,
        clock: getClock,
      );
      await service.init();

      // 1. Create a limit
      final created = await service.createLimit(
        appName: 'Discord',
        exePath: r'C:\Discord.exe',
        duration: const Duration(hours: 1),
        warningPercentage: 80,
      );

      expect(created.id, isNotNull);
      expect(created.appName, equals('Discord'));
      expect(created.limitDuration, equals(const Duration(hours: 1)));
      expect(created.warningThresholdPercentage, equals(80));
      expect(created.isEnabled, isTrue);
      expect(service.limits.length, equals(1));
      expect(service.enabledLimits.length, equals(1));

      // Validation errors
      expect(
        () => service.createLimit(
          appName: '   ',
          duration: const Duration(minutes: 30),
        ),
        throwsArgumentError,
      );
      expect(
        () => service.createLimit(
          appName: 'Game',
          duration: const Duration(minutes: -1),
        ),
        throwsArgumentError,
      );
      expect(
        () => service.createLimit(
          appName: 'Game',
          duration: const Duration(minutes: 30),
          warningPercentage: 110,
        ),
        throwsArgumentError,
      );
      // Duplicate rejection
      expect(
        () => service.createLimit(
          appName: 'Discord',
          duration: const Duration(hours: 2),
        ),
        throwsArgumentError,
      );

      // 2. Edit the limit
      await service.updateLimit(
        id: created.id!,
        duration: const Duration(hours: 2),
        warningPercentage: 90,
      );
      expect(service.limits.first.limitDuration, equals(const Duration(hours: 2)));
      expect(service.limits.first.warningThresholdPercentage, equals(90));

      // 3. Toggle enabled
      await service.toggleLimit(created.id!, false);
      expect(service.limits.first.isEnabled, isFalse);
      expect(service.enabledLimits, isEmpty);

      await service.toggleLimit(created.id!, true);
      expect(service.limits.first.isEnabled, isTrue);
      expect(service.enabledLimits.length, equals(1));

      // 4. Delete the limit
      await service.deleteLimit(created.id!);
      expect(service.limits, isEmpty);
      expect(service.enabledLimits, isEmpty);
    });

    test('Limits persist in SQLite and restore on service restart', () async {
      final service1 = LimitsService(
        repository: repository,
        notificationService: notificationService,
        clock: getClock,
      );
      await service1.init();

      await service1.createLimit(
        appName: 'Steam',
        duration: const Duration(minutes: 90),
        warningPercentage: 75,
      );
      await service1.createLimit(
        appName: 'Spotify',
        duration: const Duration(hours: 3),
        warningPercentage: 80,
      );

      // Simulate app restart by creating a new service instance with same DB
      final service2 = LimitsService(
        repository: repository,
        notificationService: notificationService,
        clock: getClock,
      );
      await service2.init();

      expect(service2.limits.length, equals(2));
      final steam = service2.limits.firstWhere((l) => l.appName == 'Steam');
      expect(steam.limitDuration, equals(const Duration(minutes: 90)));
      expect(steam.warningThresholdPercentage, equals(75));

      final spotify = service2.limits.firstWhere((l) => l.appName == 'Spotify');
      expect(spotify.limitDuration, equals(const Duration(hours: 3)));
    });

    test('Daily usage calculation handles midnight-crossing and overlapping sessions', () async {
      // Midnight crossing: started yesterday 23:45, ended today 00:30 (30m today)
      await repository.insertSession(AppSession(
        appName: 'YouTube',
        exePath: r'C:\chrome.exe',
        startTime: DateTime(2026, 10, 10, 23, 45),
        endTime: DateTime(2026, 10, 11, 0, 30),
      ));

      // Overlapping sessions today:
      // Session 1: 10:00 - 10:40 (40m)
      // Session 2: 10:20 - 11:00 (40m)
      // Non-overlapping interval: 10:00 - 11:00 = 60m
      await repository.insertSession(AppSession(
        appName: 'YouTube',
        exePath: r'C:\chrome.exe',
        startTime: DateTime(2026, 10, 11, 10, 0),
        endTime: DateTime(2026, 10, 11, 10, 40),
      ));
      await repository.insertSession(AppSession(
        appName: 'YouTube',
        exePath: r'C:\chrome.exe',
        startTime: DateTime(2026, 10, 11, 10, 20),
        endTime: DateTime(2026, 10, 11, 11, 0),
      ));

      final service = LimitsService(
        repository: repository,
        notificationService: notificationService,
        clock: getClock,
      );
      await service.init();

      // Total YouTube usage should be 30m + 60m = 90m (1h 30m)
      final used = service.getUsageForApp('YouTube');
      expect(used, equals(const Duration(minutes: 90)));

      // Limit of 2 hours (120m)
      final limit = await service.createLimit(
        appName: 'YouTube',
        duration: const Duration(hours: 2),
        warningPercentage: 80,
      );

      // Remaining allowance = 120m - 90m = 30m
      expect(service.getRemainingAllowance(limit), equals(const Duration(minutes: 30)));
      expect(service.isLimitExceeded(limit), isFalse);
      expect(service.getProgress(limit), closeTo(90 / 120, 0.001));
    });

    test('Remaining allowance never displays negative time when limit is exceeded', () async {
      await repository.insertSession(AppSession(
        appName: 'Game',
        exePath: r'C:\game.exe',
        startTime: DateTime(2026, 10, 11, 12, 0),
        endTime: DateTime(2026, 10, 11, 14, 0), // 2 hours
      ));

      final service = LimitsService(
        repository: repository,
        notificationService: notificationService,
        clock: getClock,
      );
      await service.init();

      // Limit was only 1 hour
      final limit = await service.createLimit(
        appName: 'Game',
        duration: const Duration(hours: 1),
      );

      expect(service.isLimitExceeded(limit), isTrue);
      expect(service.getRemainingAllowance(limit), equals(Duration.zero));
      expect(service.getProgress(limit), equals(1.0));
    });

    test('Warning threshold triggers notification and deduplicates on same day', () async {
      final service = LimitsService(
        repository: repository,
        notificationService: notificationService,
        clock: getClock,
      );
      await service.init();

      // Create limit: 100m, warning at 80% (80m)
      final limit = await service.createLimit(
        appName: 'Code',
        duration: const Duration(minutes: 100),
        warningPercentage: 80,
      );

      // Usage at 50m (below threshold)
      await repository.insertSession(AppSession(
        appName: 'Code',
        exePath: r'C:\code.exe',
        startTime: DateTime(2026, 10, 11, 9, 0),
        endTime: DateTime(2026, 10, 11, 9, 50),
      ));
      await service.evaluateUsage();
      expect(notificationService.warnings, isEmpty);
      expect(service.isNearLimit(limit), isFalse);

      // Usage reaches 85m (between 80m and 100m)
      await repository.insertSession(AppSession(
        appName: 'Code',
        exePath: r'C:\code.exe',
        startTime: DateTime(2026, 10, 11, 10, 0),
        endTime: DateTime(2026, 10, 11, 10, 35),
      ));
      await service.evaluateUsage();

      // Exactly 1 warning sent
      expect(notificationService.warnings, equals(['Code']));
      expect(service.isNearLimit(limit), isTrue);

      // Second evaluation on the same day (e.g. repeated tracker poll)
      await service.evaluateUsage();
      expect(notificationService.warnings, equals(['Code']), reason: 'Should not send duplicate warning on same day');
    });

    test('Limit reached triggers notification and deduplicates on same day', () async {
      final service = LimitsService(
        repository: repository,
        notificationService: notificationService,
        clock: getClock,
      );
      await service.init();

      final limit = await service.createLimit(
        appName: 'Social',
        duration: const Duration(minutes: 60),
        warningPercentage: 80,
      );

      // Usage hits 65m (exceeds 60m limit)
      await repository.insertSession(AppSession(
        appName: 'Social',
        exePath: r'C:\social.exe',
        startTime: DateTime(2026, 10, 11, 12, 0),
        endTime: DateTime(2026, 10, 11, 13, 5),
      ));
      await service.evaluateUsage();

      expect(notificationService.reached, equals(['Social']));
      expect(service.isLimitExceeded(limit), isTrue);

      // Further evaluations on the same day should not repeat notification
      await service.evaluateUsage();
      await service.evaluateUsage();
      expect(notificationService.reached, equals(['Social']));
    });

    test('Warning deduplication survives application restart', () async {
      final service1 = LimitsService(
        repository: repository,
        notificationService: notificationService,
        clock: getClock,
      );
      await service1.init();

      await service1.createLimit(
        appName: 'Browser',
        duration: const Duration(hours: 1),
        warningPercentage: 80,
      );

      // Add 50m session (50m / 60m = 83.3% -> warning range)
      await repository.insertSession(AppSession(
        appName: 'Browser',
        exePath: r'C:\browser.exe',
        startTime: DateTime(2026, 10, 11, 10, 0),
        endTime: DateTime(2026, 10, 11, 10, 50),
      ));
      await service1.evaluateUsage();
      expect(notificationService.warnings, equals(['Browser']));

      // Simulate cold restart of application
      final restartNotifications = TestNotificationService(settingsService: settingsService);
      final service2 = LimitsService(
        repository: repository,
        notificationService: restartNotifications,
        clock: getClock,
      );
      await service2.init();

      // Must not send duplicate warning after restart
      expect(restartNotifications.warnings, isEmpty);
    });

    test('Disabled notification setting suppresses warnings and limit-reached toasts', () async {
      // Disable notifications in settings
      await settingsService.setNotifications(false);

      final service = LimitsService(
        repository: repository,
        notificationService: notificationService,
        clock: getClock,
      );
      await service.init();

      await service.createLimit(
        appName: 'Gaming',
        duration: const Duration(hours: 1),
        warningPercentage: 80,
      );

      // 90 minutes of gaming (exceeded)
      await repository.insertSession(AppSession(
        appName: 'Gaming',
        exePath: r'C:\gaming.exe',
        startTime: DateTime(2026, 10, 11, 10, 0),
        endTime: DateTime(2026, 10, 11, 11, 30),
      ));
      await service.evaluateUsage();

      // No notifications should be emitted
      expect(notificationService.warnings, isEmpty);
      expect(notificationService.reached, isEmpty);
    });

    test('Disabled limits do not emit warnings or limit-reached toasts', () async {
      final service = LimitsService(
        repository: repository,
        notificationService: notificationService,
        clock: getClock,
      );
      await service.init();

      final limit = await service.createLimit(
        appName: 'Office',
        duration: const Duration(hours: 1),
      );

      // Disable the limit
      await service.toggleLimit(limit.id!, false);

      // Exceeded usage
      await repository.insertSession(AppSession(
        appName: 'Office',
        exePath: r'C:\office.exe',
        startTime: DateTime(2026, 10, 11, 9, 0),
        endTime: DateTime(2026, 10, 11, 11, 0),
      ));
      await service.evaluateUsage();

      expect(notificationService.warnings, isEmpty);
      expect(notificationService.reached, isEmpty);
    });

    test('New calendar day resets warning and limit-reached notification deduplication', () async {
      final service = LimitsService(
        repository: repository,
        notificationService: notificationService,
        clock: getClock,
      );
      await service.init();

      await service.createLimit(
        appName: 'Editor',
        duration: const Duration(hours: 1),
        warningPercentage: 80,
      );

      // Day 1 (2026-10-11): 50m usage (warning threshold)
      await repository.insertSession(AppSession(
        appName: 'Editor',
        exePath: r'C:\editor.exe',
        startTime: DateTime(2026, 10, 11, 10, 0),
        endTime: DateTime(2026, 10, 11, 10, 50),
      ));
      await service.evaluateUsage();
      expect(notificationService.warnings, equals(['Editor']));

      // Advance clock to Day 2 (2026-10-12)
      testNow = DateTime(2026, 10, 12, 11, 0);

      // Day 2: 50m usage on the new calendar day
      await repository.insertSession(AppSession(
        appName: 'Editor',
        exePath: r'C:\editor.exe',
        startTime: DateTime(2026, 10, 12, 10, 0),
        endTime: DateTime(2026, 10, 12, 10, 50),
      ));
      await service.evaluateUsage();

      // Should have received a second warning for the new day
      expect(notificationService.warnings, equals(['Editor', 'Editor']));
    });

    test('getDistinctTrackedApps returns empty list without crashing when database has no sessions', () async {
      final apps = await repository.getDistinctTrackedApps();
      expect(apps, isEmpty);
    });

    test('getDistinctTrackedApps correctly queries SQLite without double-quote error and filters empty or whitespace names', () async {
      await repository.insertSession(AppSession(
        appName: 'Figma',
        exePath: r'C:\figma.exe',
        startTime: DateTime(2026, 10, 11, 10, 0),
        endTime: DateTime(2026, 10, 11, 11, 0),
      ));
      await repository.insertSession(AppSession(
        appName: 'figma', // duplicate with different case
        exePath: r'C:\figma.exe',
        startTime: DateTime(2026, 10, 11, 11, 0),
        endTime: DateTime(2026, 10, 11, 12, 0),
      ));
      await repository.insertSession(AppSession(
        appName: 'Code',
        exePath: r'C:\code.exe',
        startTime: DateTime(2026, 10, 11, 12, 0),
        endTime: DateTime(2026, 10, 11, 13, 0),
      ));
      // Empty string and whitespace-only records
      await repository.insertSession(AppSession(
        appName: '',
        exePath: r'C:\empty.exe',
        startTime: DateTime(2026, 10, 11, 13, 0),
        endTime: DateTime(2026, 10, 11, 13, 5),
      ));
      await repository.insertSession(AppSession(
        appName: '   ',
        exePath: r'C:\spaces.exe',
        startTime: DateTime(2026, 10, 11, 13, 5),
        endTime: DateTime(2026, 10, 11, 13, 10),
      ));

      final apps = await repository.getDistinctTrackedApps();
      expect(apps.length, equals(2));
      expect(apps, containsAll(['Code', 'Figma']));
      expect(apps.contains(''), isFalse);
      expect(apps.contains('   '), isFalse);
    });

    test('LimitsService.getAvailableApplications combines historical and live tracker apps', () async {
      await repository.insertSession(AppSession(
        appName: 'Obsidian',
        exePath: r'C:\obsidian.exe',
        startTime: DateTime(2026, 10, 11, 9, 0),
        endTime: DateTime(2026, 10, 11, 10, 0),
      ));

      final service = LimitsService(
        repository: repository,
        notificationService: notificationService,
        clock: getClock,
      );
      await service.init();

      final available = await service.getAvailableApplications();
      expect(available, contains('Obsidian'));
    });

    test('Zero-minute limit creation, edit, reload, and notification behavior', () async {
      final service = LimitsService(
        repository: repository,
        notificationService: notificationService,
        clock: getClock,
      );
      await service.init();

      // 1. Create a zero-minute limit
      final zeroLimit = await service.createLimit(
        appName: 'TikTok',
        exePath: r'C:\tiktok.exe',
        duration: Duration.zero,
        warningPercentage: 80,
        isEnforced: true,
      );

      expect(zeroLimit.limitDuration, equals(Duration.zero));
      expect(zeroLimit.limitMinutes, equals(0));
      expect(zeroLimit.isEnforced, isTrue);

      // 2. Metrics for zero-minute limit
      expect(service.isLimitExceeded(zeroLimit), isTrue);
      expect(service.isNearLimit(zeroLimit), isFalse);
      expect(service.getRemainingAllowance(zeroLimit), equals(Duration.zero));
      expect(service.getProgress(zeroLimit), equals(1.0));

      // 3. Evaluate usage: should trigger limit-reached notification, NOT warning notification
      await service.evaluateUsage();
      expect(notificationService.warnings, isEmpty);
      expect(notificationService.reached, equals(['TikTok']));

      // 4. Repeated evaluation on same day: should not duplicate notification
      await service.evaluateUsage();
      expect(notificationService.reached, equals(['TikTok']));

      // 5. Update zero-minute limit to another zero-minute or edited values
      await service.updateLimit(
        id: zeroLimit.id!,
        duration: Duration.zero,
        warningPercentage: 90,
        isEnforced: false,
      );
      expect(service.limits.first.limitDuration, equals(Duration.zero));
      expect(service.limits.first.isEnforced, isFalse);

      // 6. Persistence and restart verification
      final serviceRestarted = LimitsService(
        repository: repository,
        notificationService: notificationService,
        clock: getClock,
      );
      await serviceRestarted.init();

      expect(serviceRestarted.limits.length, equals(1));
      final reloaded = serviceRestarted.limits.first;
      expect(reloaded.appName, equals('TikTok'));
      expect(reloaded.limitDuration, equals(Duration.zero));
      expect(reloaded.limitMinutes, equals(0));
      expect(reloaded.isEnforced, isFalse);
    });
  });
}

