import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:balance/core/models/analytics_data.dart';
import 'package:balance/core/models/app_session.dart';
import 'package:balance/core/models/focus_session.dart';
import 'package:balance/core/services/usage_analytics_service.dart';
import 'package:balance/core/services/usage_repository.dart';
import 'package:balance/core/services/windows_usage_tracker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('UsageAnalyticsService Unit & Edge Case Tests', () {
    late UsageRepository repository;
    late UsageAnalyticsService analyticsService;

    // Fixed reference date: Wednesday, October 14, 2026, 14:00
    final refDate = DateTime(2026, 10, 14, 14, 0);

    setUp(() async {
      repository = UsageRepository(dbName: inMemoryDatabasePath);
      // Initialize DB
      await repository.database;
      analyticsService = UsageAnalyticsService(repository: repository);
    });

    tearDown(() async {
      await repository.close();
    });

    test('1. No recorded sessions: returns clean zeros without errors', () async {
      final analytics = await analyticsService.getAnalytics(
        period: AnalyticsPeriod.last7Days,
        referenceDate: refDate,
      );

      expect(analytics.totalScreenTime, equals(Duration.zero));
      expect(analytics.dailyAverage, equals(Duration.zero));
      expect(analytics.dailySeries.length, equals(7));
      expect(analytics.dailySeries.every((p) => p.duration == Duration.zero), isTrue);
      expect(analytics.topApplications, isEmpty);
      expect(analytics.mostUsedApp, isNull);
      expect(analytics.mostActiveDay, isNull);
      expect(analytics.activeDaysCount, equals(0));
      expect(analytics.totalDaysCount, equals(7));
      expect(analytics.hasUsage, isFalse);
      expect(analytics.percentageChangeVsPrevious, equals(0.0));
    });

    test('2. One completed session: calculates accurate totals and averages', () async {
      // 1 hour session on Oct 14 (today)
      await repository.insertSession(AppSession(
        appName: 'VS Code',
        exePath: r'C:\vscode.exe',
        startTime: DateTime(2026, 10, 14, 10, 0),
        endTime: DateTime(2026, 10, 14, 11, 0),
      ));

      final analytics = await analyticsService.getAnalytics(
        period: AnalyticsPeriod.last7Days,
        referenceDate: refDate,
      );

      expect(analytics.totalScreenTime, equals(const Duration(hours: 1)));
      // 1 hour / 7 days = 60 mins / 7 = ~8.57 mins
      expect(analytics.dailyAverage.inMinutes, equals(8));
      expect(analytics.activeDaysCount, equals(1));
      expect(analytics.mostUsedApp?.appName, equals('VS Code'));
      expect(analytics.mostUsedApp?.duration, equals(const Duration(hours: 1)));
      expect(analytics.mostUsedApp?.proportionalUsage, equals(1.0));
      expect(analytics.mostActiveDay?.duration, equals(const Duration(hours: 1)));
      expect(analytics.dailySeries.last.duration, equals(const Duration(hours: 1)));
      expect(analytics.dailySeries.last.isToday, isTrue);
    });

    test('3. Multiple sessions for the same application: merges intervals and sums duration', () async {
      // Two separate sessions for Telegram on Oct 13 (yesterday)
      await repository.insertSession(AppSession(
        appName: 'Telegram',
        exePath: r'C:\telegram.exe',
        startTime: DateTime(2026, 10, 13, 9, 0),
        endTime: DateTime(2026, 10, 13, 9, 30), // 30m
      ));
      await repository.insertSession(AppSession(
        appName: 'Telegram',
        exePath: r'C:\telegram.exe',
        startTime: DateTime(2026, 10, 13, 15, 0),
        endTime: DateTime(2026, 10, 13, 16, 0), // 60m
      ));

      final analytics = await analyticsService.getAnalytics(
        period: AnalyticsPeriod.last7Days,
        referenceDate: refDate,
      );

      expect(analytics.totalScreenTime, equals(const Duration(minutes: 90)));
      expect(analytics.topApplications.length, equals(1));
      expect(analytics.topApplications.first.appName, equals('Telegram'));
      expect(analytics.topApplications.first.duration, equals(const Duration(minutes: 90)));
    });

    test('4. Sessions from multiple applications: sorts by duration and computes proportions', () async {
      await repository.insertSession(AppSession(
        appName: 'Browser',
        exePath: r'C:\browser.exe',
        startTime: DateTime(2026, 10, 14, 8, 0),
        endTime: DateTime(2026, 10, 14, 9, 0), // 1h
      ));
      await repository.insertSession(AppSession(
        appName: 'Code Editor',
        exePath: r'C:\code.exe',
        startTime: DateTime(2026, 10, 14, 10, 0),
        endTime: DateTime(2026, 10, 14, 13, 0), // 3h
      ));

      final analytics = await analyticsService.getAnalytics(
        period: AnalyticsPeriod.last7Days,
        referenceDate: refDate,
      );

      expect(analytics.totalScreenTime, equals(const Duration(hours: 4)));
      expect(analytics.topApplications.length, equals(2));
      // Code Editor should be first (#1)
      expect(analytics.topApplications[0].appName, equals('Code Editor'));
      expect(analytics.topApplications[0].duration, equals(const Duration(hours: 3)));
      expect(analytics.topApplications[0].proportionalUsage, closeTo(0.75, 0.001));

      // Browser should be second (#2)
      expect(analytics.topApplications[1].appName, equals('Browser'));
      expect(analytics.topApplications[1].duration, equals(const Duration(hours: 1)));
      expect(analytics.topApplications[1].proportionalUsage, closeTo(0.25, 0.001));
    });

    test('5. Session spanning midnight: splits usage accurately between consecutive calendar days', () async {
      // Session starts Oct 12 at 23:30 (Monday) and ends Oct 13 at 01:00 (Tuesday)
      // Total 90m: 30m on Oct 12 and 60m on Oct 13
      await repository.insertSession(AppSession(
        appName: 'NightOwl',
        exePath: r'C:\nightowl.exe',
        startTime: DateTime(2026, 10, 12, 23, 30),
        endTime: DateTime(2026, 10, 13, 1, 0),
      ));

      final analytics = await analyticsService.getAnalytics(
        period: AnalyticsPeriod.last7Days,
        referenceDate: refDate,
      );

      expect(analytics.totalScreenTime, equals(const Duration(minutes: 90)));

      // Oct 12 is index 5 in the 7-day series (Oct 8..14)
      final oct12 = analytics.dailySeries.firstWhere(
        (p) => p.date.year == 2026 && p.date.month == 10 && p.date.day == 12,
      );
      final oct13 = analytics.dailySeries.firstWhere(
        (p) => p.date.year == 2026 && p.date.month == 10 && p.date.day == 13,
      );

      expect(oct12.duration, equals(const Duration(minutes: 30)));
      expect(oct13.duration, equals(const Duration(minutes: 60)));
    });

    test('6. Session beginning before requested range and ending inside it: clamped to range start', () async {
      // Window is Oct 8 00:00 to Oct 15 00:00
      // Session starts Oct 7 at 22:00 and ends Oct 8 at 02:00 (4 hours total)
      // Only 2 hours fall inside Oct 8
      await repository.insertSession(AppSession(
        appName: 'BeforeApp',
        exePath: r'C:\before.exe',
        startTime: DateTime(2026, 10, 7, 22, 0),
        endTime: DateTime(2026, 10, 8, 2, 0),
      ));

      final analytics = await analyticsService.getAnalytics(
        period: AnalyticsPeriod.last7Days,
        referenceDate: refDate,
      );

      expect(analytics.totalScreenTime, equals(const Duration(hours: 2)));
      final oct8 = analytics.dailySeries.firstWhere(
        (p) => p.date.year == 2026 && p.date.month == 10 && p.date.day == 8,
      );
      expect(oct8.duration, equals(const Duration(hours: 2)));
    });

    test('7. Session beginning inside requested range and ending after it: clamped to range end', () async {
      // Session starts Oct 14 at 23:00 and ends Oct 15 at 03:00 (4 hours total)
      // Range ends at Oct 15 00:00, so only 1 hour should be counted
      await repository.insertSession(AppSession(
        appName: 'AfterApp',
        exePath: r'C:\after.exe',
        startTime: DateTime(2026, 10, 14, 23, 0),
        endTime: DateTime(2026, 10, 15, 3, 0),
      ));

      final analytics = await analyticsService.getAnalytics(
        period: AnalyticsPeriod.last7Days,
        referenceDate: refDate,
      );

      expect(analytics.totalScreenTime, equals(const Duration(hours: 1)));
      final oct14 = analytics.dailySeries.last;
      expect(oct14.duration, equals(const Duration(hours: 1)));
    });

    test('8. Session overlapping entire range: clamped to range boundaries', () async {
      // Single session covering Oct 1 to Oct 20
      // For 7-day window (Oct 8..14), exactly 7 * 24 = 168 hours should be counted
      await repository.insertSession(AppSession(
        appName: 'MegaSession',
        exePath: r'C:\mega.exe',
        startTime: DateTime(2026, 10, 1, 0, 0),
        endTime: DateTime(2026, 10, 20, 0, 0),
      ));

      final analytics = await analyticsService.getAnalytics(
        period: AnalyticsPeriod.last7Days,
        referenceDate: refDate,
      );

      expect(analytics.totalScreenTime, equals(const Duration(days: 7)));
      expect(analytics.dailyAverage, equals(const Duration(hours: 24)));
      expect(analytics.dailySeries.every((p) => p.duration == const Duration(hours: 24)), isTrue);
    });

    test('9. Zero-duration and invalid sessions: excluded gracefully', () async {
      // Zero duration
      await repository.insertSession(AppSession(
        appName: 'ZeroApp',
        exePath: r'C:\zero.exe',
        startTime: DateTime(2026, 10, 14, 10, 0),
        endTime: DateTime(2026, 10, 14, 10, 0),
      ));
      // Inverted duration
      await repository.insertSession(AppSession(
        appName: 'InvertedApp',
        exePath: r'C:\inv.exe',
        startTime: DateTime(2026, 10, 14, 12, 0),
        endTime: DateTime(2026, 10, 14, 11, 0),
      ));

      final analytics = await analyticsService.getAnalytics(
        period: AnalyticsPeriod.last7Days,
        referenceDate: refDate,
      );

      expect(analytics.totalScreenTime, equals(Duration.zero));
      expect(analytics.topApplications, isEmpty);
    });

    test('10. Live in-progress session: merged without duplicate counting', () async {
      // SQLite has a completed session of 30 mins
      await repository.insertSession(AppSession(
        appName: 'LiveApp',
        exePath: r'C:\live.exe',
        startTime: DateTime(2026, 10, 14, 8, 0),
        endTime: DateTime(2026, 10, 14, 8, 30),
      ));

      // Mock tracker with an active foreground window
      final tracker = WindowsUsageTracker(
        repository: repository,
        foregroundWindowProvider: () => r'C:\live.exe',
        idleTimeProvider: () => Duration.zero,
      );

      // Start tracker session
      final serviceWithTracker = UsageAnalyticsService(
        repository: repository,
        tracker: tracker,
      );

      // Verify that service runs without error and correctly queries data
      final analytics = await serviceWithTracker.getAnalytics(
        period: AnalyticsPeriod.last7Days,
        referenceDate: refDate,
      );

      expect(analytics.totalScreenTime, equals(const Duration(minutes: 30)));
      expect(analytics.topApplications.first.appName, equals('LiveApp'));
    });

    test('11. Seven-day period containing zero-usage days: daily average includes all 7 days', () async {
      // Exactly 7 hours of usage spread over 2 days (Oct 10 and Oct 14)
      // The other 5 days have 0 usage
      await repository.insertSession(AppSession(
        appName: 'AppA',
        exePath: r'C:\a.exe',
        startTime: DateTime(2026, 10, 10, 10, 0),
        endTime: DateTime(2026, 10, 10, 14, 0), // 4h
      ));
      await repository.insertSession(AppSession(
        appName: 'AppA',
        exePath: r'C:\a.exe',
        startTime: DateTime(2026, 10, 14, 10, 0),
        endTime: DateTime(2026, 10, 14, 13, 0), // 3h
      ));

      final analytics = await analyticsService.getAnalytics(
        period: AnalyticsPeriod.last7Days,
        referenceDate: refDate,
      );

      expect(analytics.totalScreenTime, equals(const Duration(hours: 7)));
      // Total 7h / 7 days = exactly 1h daily average!
      expect(analytics.dailyAverage, equals(const Duration(hours: 1)));
      expect(analytics.activeDaysCount, equals(2));
      expect(analytics.totalDaysCount, equals(7));

      final zeroDays = analytics.dailySeries.where((p) => p.duration == Duration.zero).toList();
      expect(zeroDays.length, equals(5));
    });

    test('12. Merges overlapping sessions to prevent double-counting', () async {
      // Overlapping intervals:
      // Session 1: 10:00 - 11:00 (60m)
      // Session 2: 10:30 - 11:30 (60m)
      // Non-overlapping interval: 10:00 - 11:30 = 90m
      await repository.insertSession(AppSession(
        appName: 'OverlapApp',
        exePath: r'C:\overlap.exe',
        startTime: DateTime(2026, 10, 14, 10, 0),
        endTime: DateTime(2026, 10, 14, 11, 0),
      ));
      await repository.insertSession(AppSession(
        appName: 'OverlapApp',
        exePath: r'C:\overlap.exe',
        startTime: DateTime(2026, 10, 14, 10, 30),
        endTime: DateTime(2026, 10, 14, 11, 30),
      ));

      final analytics = await analyticsService.getAnalytics(
        period: AnalyticsPeriod.last7Days,
        referenceDate: refDate,
      );

      expect(analytics.totalScreenTime, equals(const Duration(minutes: 90)));
      expect(analytics.topApplications.first.duration, equals(const Duration(minutes: 90)));
    });

    test('13. Comparison with previous period: calculates percentage change safely', () async {
      // Previous period (Oct 1..7): 2 hours on Oct 5
      await repository.insertSession(AppSession(
        appName: 'Work',
        exePath: r'C:\work.exe',
        startTime: DateTime(2026, 10, 5, 10, 0),
        endTime: DateTime(2026, 10, 5, 12, 0), // 2h
      ));

      // Current period (Oct 8..14): 3 hours on Oct 14
      await repository.insertSession(AppSession(
        appName: 'Work',
        exePath: r'C:\work.exe',
        startTime: DateTime(2026, 10, 14, 10, 0),
        endTime: DateTime(2026, 10, 14, 13, 0), // 3h
      ));

      final analytics = await analyticsService.getAnalytics(
        period: AnalyticsPeriod.last7Days,
        referenceDate: refDate,
      );

      expect(analytics.totalScreenTime, equals(const Duration(hours: 3)));
      expect(analytics.previousPeriodScreenTime, equals(const Duration(hours: 2)));
      expect(analytics.differenceVsPrevious, equals(const Duration(hours: 1)));
      // Change: ((3 - 2) / 2) * 100 = +50%
      expect(analytics.percentageChangeVsPrevious, closeTo(50.0, 0.001));
    });

    test('14. Comparison when previous period has zero usage: avoids division by zero', () async {
      // Previous period has 0 usage
      // Current period has 2 hours
      await repository.insertSession(AppSession(
        appName: 'Work',
        exePath: r'C:\work.exe',
        startTime: DateTime(2026, 10, 14, 10, 0),
        endTime: DateTime(2026, 10, 14, 12, 0),
      ));

      final analytics = await analyticsService.getAnalytics(
        period: AnalyticsPeriod.last7Days,
        referenceDate: refDate,
      );

      expect(analytics.totalScreenTime, equals(const Duration(hours: 2)));
      expect(analytics.previousPeriodScreenTime, equals(Duration.zero));
      // Should be null, cleanly representing no previous baseline
      expect(analytics.percentageChangeVsPrevious, isNull);
      expect(analytics.differenceVsPrevious, equals(const Duration(hours: 2)));
    });

    test('15. Focus sessions: calculates actual focus time from SQLite records', () async {
      // Insert a completed focus session
      await repository.insertFocusSession(FocusSessionRecord(
        type: FocusSessionType.focus,
        plannedDuration: const Duration(minutes: 25),
        actualDuration: const Duration(minutes: 25),
        startTime: DateTime(2026, 10, 14, 9, 0),
        endTime: DateTime(2026, 10, 14, 9, 25),
        completedNaturally: true,
      ));

      final analytics = await analyticsService.getAnalytics(
        period: AnalyticsPeriod.last7Days,
        referenceDate: refDate,
      );

      expect(analytics.totalFocusTime, equals(const Duration(minutes: 25)));
    });

    test('16. Today period: calculates 1-day statistics and series', () async {
      await repository.insertSession(AppSession(
        appName: 'Editor',
        exePath: r'C:\editor.exe',
        startTime: DateTime(2026, 10, 14, 11, 0),
        endTime: DateTime(2026, 10, 14, 12, 30), // 1h 30m
      ));

      final analytics = await analyticsService.getAnalytics(
        period: AnalyticsPeriod.today,
        referenceDate: refDate,
      );

      expect(analytics.totalScreenTime, equals(const Duration(minutes: 90)));
      expect(analytics.dailyAverage, equals(const Duration(minutes: 90)));
      expect(analytics.dailySeries.length, equals(1));
      expect(analytics.dailySeries.first.isToday, isTrue);
      expect(analytics.topApplications.first.appName, equals('Editor'));
    });

    test('17. Period persistence: getSavedPeriod defaults to last7Days when no setting exists', () async {
      final period = await analyticsService.getSavedPeriod();
      expect(period, equals(AnalyticsPeriod.last7Days));
    });

    test('18. Period persistence: savePeriod persists and getSavedPeriod restores selection', () async {
      await analyticsService.savePeriod(AnalyticsPeriod.today);
      await analyticsService.pendingSaveOp;

      final storedValue = await repository.getSetting(UsageAnalyticsService.insightsPeriodSettingKey);
      expect(storedValue, equals('today'));

      final restored = await analyticsService.getSavedPeriod();
      expect(restored, equals(AnalyticsPeriod.today));
    });

    test('19. Period persistence: re-creating service with same repository restores saved selection', () async {
      await analyticsService.savePeriod(AnalyticsPeriod.last30Days);
      await analyticsService.pendingSaveOp;

      // Create new service instance with same repository simulating app restart
      final freshService = UsageAnalyticsService(repository: repository);
      final restored = await freshService.getSavedPeriod();
      expect(restored, equals(AnalyticsPeriod.last30Days));
    });

    test('20. Period persistence: handles invalid, corrupted, or blank stored values safely by returning last7Days', () async {
      await repository.setSetting(UsageAnalyticsService.insightsPeriodSettingKey, 'invalid_period_garbage');
      expect(await analyticsService.getSavedPeriod(), equals(AnalyticsPeriod.last7Days));

      await repository.setSetting(UsageAnalyticsService.insightsPeriodSettingKey, '');
      expect(await analyticsService.getSavedPeriod(), equals(AnalyticsPeriod.last7Days));

      await repository.setSetting(UsageAnalyticsService.insightsPeriodSettingKey, '   ');
      expect(await analyticsService.getSavedPeriod(), equals(AnalyticsPeriod.last7Days));
    });

    test('21. Period persistence: relative ranges re-anchor correctly when evaluated across date changes', () async {
      // User has saved Today preference
      await analyticsService.savePeriod(AnalyticsPeriod.today);
      final savedPeriod = await analyticsService.getSavedPeriod();
      expect(savedPeriod, equals(AnalyticsPeriod.today));

      // Day 1 evaluation (Wednesday Oct 14)
      final day1 = DateTime(2026, 10, 14, 10, 0);
      final analyticsDay1 = await analyticsService.getAnalytics(
        period: savedPeriod,
        referenceDate: day1,
      );
      expect(analyticsDay1.startDate, equals(DateTime(2026, 10, 14)));
      expect(analyticsDay1.endDate, equals(DateTime(2026, 10, 15)));

      // Day 2 evaluation (Thursday Oct 15) - same restored period automatically shifts to new day
      final day2 = DateTime(2026, 10, 15, 12, 0);
      final analyticsDay2 = await analyticsService.getAnalytics(
        period: savedPeriod,
        referenceDate: day2,
      );
      expect(analyticsDay2.startDate, equals(DateTime(2026, 10, 15)));
      expect(analyticsDay2.endDate, equals(DateTime(2026, 10, 16)));

      // Same verification for last7Days: relative bounds shift with the date
      await analyticsService.savePeriod(AnalyticsPeriod.last7Days);
      final saved7Days = await analyticsService.getSavedPeriod();
      final analytics7Day1 = await analyticsService.getAnalytics(
        period: saved7Days,
        referenceDate: day1,
      );
      final analytics7Day2 = await analyticsService.getAnalytics(
        period: saved7Days,
        referenceDate: day2,
      );
      expect(analytics7Day1.startDate, equals(DateTime(2026, 10, 8)));
      expect(analytics7Day2.startDate, equals(DateTime(2026, 10, 9)));
    });
  });
}
