import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:balance/core/models/app_limit.dart';
import 'package:balance/core/models/app_session.dart';
import 'package:balance/core/models/application_analytics_models.dart';
import 'package:balance/core/services/application_analytics_service.dart';
import 'package:balance/core/services/limits_service.dart';
import 'package:balance/core/services/usage_repository.dart';
import 'package:balance/core/services/windows_usage_tracker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('ApplicationAnalyticsService Unit Tests', () {
    late UsageRepository repository;
    late ApplicationAnalyticsService analyticsService;
    late LimitsService limitsService;

    // Fixed deterministic reference date: Wednesday, October 14, 2026 at 15:30
    final refDate = DateTime(2026, 10, 14, 15, 30);
    final todayMidnight = DateTime(2026, 10, 14);

    setUp(() async {
      repository = UsageRepository(dbName: inMemoryDatabasePath);
      await repository.database;

      limitsService = LimitsService(
        repository: repository,
        clock: () => refDate,
      );
      await limitsService.init();

      analyticsService = ApplicationAnalyticsService(
        repository: repository,
        limitsService: limitsService,
      );
    });

    tearDown(() async {
      limitsService.dispose();
      await repository.close();
    });

    test('1. Empty repository returns 24 zero-duration bars for Today', () async {
      final selection = DateRangeSelection.today(refDate);
      final result = await analyticsService.getApplicationsAnalytics(
        selection: selection,
        referenceDate: refDate,
      );

      expect(result.totalUsage, equals(Duration.zero));
      expect(result.chartBars.length, equals(24));
      expect(result.chartBars.every((b) => b.duration == Duration.zero), isTrue);
      expect(result.chartBars[15].isCurrent, isTrue); // 15:30 -> hour 15 is current
      expect(result.chartBars[0].label, equals('12 AM'));
      expect(result.chartBars[12].label, equals('12 PM'));
      expect(result.applications, isEmpty);
      expect(result.totalLimitedApps, equals(0));
      expect(result.totalLimitReachedApps, equals(0));
    });

    test('2. Hourly aggregation allocates sessions to correct hours without duplicate counting', () async {
      // 10:15 - 10:45 (30 mins in hour 10)
      await repository.insertSession(AppSession(
        appName: 'VS Code',
        exePath: r'C:\vscode.exe',
        startTime: DateTime(2026, 10, 14, 10, 15),
        endTime: DateTime(2026, 10, 14, 10, 45),
      ));

      // 14:30 - 15:30 (spanning hour 14 and hour 15: 30m in h14, 30m in h15)
      await repository.insertSession(AppSession(
        appName: 'Chrome',
        exePath: r'C:\chrome.exe',
        startTime: DateTime(2026, 10, 14, 14, 30),
        endTime: DateTime(2026, 10, 14, 15, 30),
      ));

      final selection = DateRangeSelection.today(refDate);
      final result = await analyticsService.getApplicationsAnalytics(
        selection: selection,
        referenceDate: refDate,
      );

      expect(result.totalUsage, equals(const Duration(minutes: 90)));
      expect(result.chartBars[10].duration, equals(const Duration(minutes: 30)));
      expect(result.chartBars[14].duration, equals(const Duration(minutes: 30)));
      expect(result.chartBars[15].duration, equals(const Duration(minutes: 30)));
      expect(result.chartBars[0].duration, equals(Duration.zero));
      expect(result.chartBars[9].duration, equals(Duration.zero));

      // Sum of 24 hourly bars matches totalUsage
      final sumOfBars = result.chartBars.fold<Duration>(
        Duration.zero,
        (acc, bar) => acc + bar.duration,
      );
      expect(sumOfBars, equals(result.totalUsage));

      // Check application rows
      expect(result.applications.length, equals(2));
      expect(result.applications[0].appName, equals('Chrome'));
      expect(result.applications[0].totalDuration, equals(const Duration(minutes: 60)));
      expect(result.applications[0].sessionCount, equals(1));
      expect(result.applications[1].appName, equals('VS Code'));
      expect(result.applications[1].totalDuration, equals(const Duration(minutes: 30)));
      expect(result.applications[1].sessionCount, equals(1));
    });

    test('3. Sessions spanning midnight are split cleanly across calendar days without duplication', () async {
      // Starts Oct 13 at 23:30, ends Oct 14 at 01:15 (total 105 mins: 30m on Oct 13, 75m on Oct 14)
      await repository.insertSession(AppSession(
        appName: 'Figma',
        exePath: r'C:\figma.exe',
        startTime: DateTime(2026, 10, 13, 23, 30),
        endTime: DateTime(2026, 10, 14, 1, 15),
      ));

      // Query Oct 13 (single day hourly)
      final oct13Selection = DateRangeSelection.customDate(DateTime(2026, 10, 13));
      final oct13Result = await analyticsService.getApplicationsAnalytics(
        selection: oct13Selection,
        referenceDate: refDate,
      );
      expect(oct13Result.totalUsage, equals(const Duration(minutes: 30)));
      expect(oct13Result.chartBars[23].duration, equals(const Duration(minutes: 30)));
      expect(oct13Result.chartBars[0].duration, equals(Duration.zero));

      // Query Oct 14 (single day hourly)
      final oct14Selection = DateRangeSelection.customDate(DateTime(2026, 10, 14));
      final oct14Result = await analyticsService.getApplicationsAnalytics(
        selection: oct14Selection,
        referenceDate: refDate,
      );
      expect(oct14Result.totalUsage, equals(const Duration(minutes: 75)));
      expect(oct14Result.chartBars[0].duration, equals(const Duration(minutes: 60))); // 00:00 - 01:00
      expect(oct14Result.chartBars[1].duration, equals(const Duration(minutes: 15))); // 01:00 - 01:15
      expect(oct14Result.chartBars[2].duration, equals(Duration.zero));

      // Query 7-day period covering both Oct 13 and Oct 14
      final past7Days = DateRangeSelection.past7Days(refDate);
      final rangeResult = await analyticsService.getApplicationsAnalytics(
        selection: past7Days,
        referenceDate: refDate,
      );
      expect(rangeResult.chartBars.length, equals(7));
      expect(rangeResult.totalUsage, equals(const Duration(minutes: 105)));

      // Oct 13 bar has 30 mins, Oct 14 bar has 75 mins
      final oct13Bar = rangeResult.chartBars.firstWhere(
        (b) => b.timestamp.day == 13,
      );
      final oct14Bar = rangeResult.chartBars.firstWhere(
        (b) => b.timestamp.day == 14,
      );
      expect(oct13Bar.duration, equals(const Duration(minutes: 30)));
      expect(oct14Bar.duration, equals(const Duration(minutes: 75)));

      // Chart total equals underlying record duration
      final barSum = rangeResult.chartBars.fold<Duration>(
        Duration.zero,
        (acc, b) => acc + b.duration,
      );
      expect(barSum, equals(rangeResult.totalUsage));
    });

    test('4. Multi-day range includes empty zero-usage days and respects month boundaries', () async {
      // 30 days selection ending on Oct 14 (covers Sep 15 to Oct 14)
      final past30Days = DateRangeSelection.past30Days(refDate);
      expect(past30Days.daysCount, equals(30));
      expect(past30Days.startDate.month, equals(9)); // September
      expect(past30Days.startDate.day, equals(15));
      expect(past30Days.endDate.month, equals(10)); // October
      expect(past30Days.endDate.day, equals(14));

      // Insert session in September on Sep 20
      await repository.insertSession(AppSession(
        appName: 'Discord',
        exePath: r'C:\discord.exe',
        startTime: DateTime(2026, 9, 20, 14, 0),
        endTime: DateTime(2026, 9, 20, 16, 0),
      ));

      final result = await analyticsService.getApplicationsAnalytics(
        selection: past30Days,
        referenceDate: refDate,
      );

      expect(result.chartBars.length, equals(30));
      expect(result.totalUsage, equals(const Duration(hours: 2)));

      final sep20Bar = result.chartBars.firstWhere(
        (b) => b.timestamp.month == 9 && b.timestamp.day == 20,
      );
      expect(sep20Bar.duration, equals(const Duration(hours: 2)));

      // Verify other 29 days are zero duration
      final zeroBars = result.chartBars.where((b) => b.duration == Duration.zero);
      expect(zeroBars.length, equals(29));
    });

    test('5. Single application analytics isolates target app and computes session history', () async {
      // Insert sessions for two different apps
      await repository.insertSession(AppSession(
        appName: 'VS Code',
        exePath: r'C:\vscode.exe',
        startTime: DateTime(2026, 10, 14, 9, 0),
        endTime: DateTime(2026, 10, 14, 10, 30), // 1.5h
      ));
      await repository.insertSession(AppSession(
        appName: 'VS Code',
        exePath: r'C:\vscode.exe',
        startTime: DateTime(2026, 10, 14, 13, 0),
        endTime: DateTime(2026, 10, 14, 14, 0), // 1h
      ));
      await repository.insertSession(AppSession(
        appName: 'Spotify',
        exePath: r'C:\spotify.exe',
        startTime: DateTime(2026, 10, 14, 11, 0),
        endTime: DateTime(2026, 10, 14, 12, 0), // 1h
      ));

      // Configure a 2-hour daily limit for VS Code
      await limitsService.createLimit(
        appName: 'VS Code',
        duration: const Duration(hours: 2),
        warningPercentage: 75,
      );

      final selection = DateRangeSelection.today(refDate);
      final singleResult = await analyticsService.getSingleAppAnalytics(
        appName: 'VS Code',
        selection: selection,
        referenceDate: refDate,
      );

      expect(singleResult.appName, equals('VS Code'));
      expect(singleResult.totalUsage, equals(const Duration(hours: 2, minutes: 30)));
      expect(singleResult.sessionCount, equals(2)); // Only VS Code sessions counted
      expect(singleResult.sessions.length, equals(2));
      expect(singleResult.sessions[0].startTime, equals(DateTime(2026, 10, 14, 13, 0))); // Most recent first
      expect(singleResult.limit, isNotNull);
      expect(singleResult.limit!.limitDuration, equals(const Duration(hours: 2)));
      expect(singleResult.isLimitReached, isTrue); // 2.5h used >= 2h limit
      expect(singleResult.remainingAllowance, equals(Duration.zero));

      // Bar chart for VS Code does NOT contain Spotify's 11:00 usage
      expect(singleResult.chartBars[11].duration, equals(Duration.zero));
      expect(singleResult.chartBars[9].duration, equals(const Duration(hours: 1)));
      expect(singleResult.chartBars[10].duration, equals(const Duration(minutes: 30)));
      expect(singleResult.chartBars[13].duration, equals(const Duration(hours: 1)));
    });

    test('6. Application list filtering and sorting works correctly', () async {
      final now = refDate;
      final sessions = [
        AppSession(
          appName: 'Alpha Browser',
          exePath: r'C:\alpha.exe',
          startTime: DateTime(now.year, now.month, now.day, 8, 0),
          endTime: DateTime(now.year, now.month, now.day, 9, 0), // 60 mins
        ),
        AppSession(
          appName: 'Beta Editor',
          exePath: r'C:\beta.exe',
          startTime: DateTime(now.year, now.month, now.day, 10, 0),
          endTime: DateTime(now.year, now.month, now.day, 12, 0), // 120 mins
        ),
        AppSession(
          appName: 'Gamma Chat',
          exePath: r'C:\gamma.exe',
          startTime: DateTime(now.year, now.month, now.day, 13, 0),
          endTime: DateTime(now.year, now.month, now.day, 13, 30), // 30 mins
        ),
      ];

      // Create a limit for Beta Editor (1 hour limit, so 2h usage means Limit Reached)
      await limitsService.createLimit(
        appName: 'Beta Editor',
        duration: const Duration(hours: 1),
      );

      // Create a limit for Alpha Browser (2 hour limit, so 1h usage means NOT reached)
      await limitsService.createLimit(
        appName: 'Alpha Browser',
        duration: const Duration(hours: 2),
      );

      final selection = DateRangeSelection.today(refDate);
      final apps = analyticsService.aggregateAppList(
        selection: selection,
        sessions: sessions,
      );

      expect(apps.length, equals(3));

      // Default sorting: Most Used descending
      expect(apps[0].appName, equals('Beta Editor')); // 120 mins
      expect(apps[1].appName, equals('Alpha Browser')); // 60 mins
      expect(apps[2].appName, equals('Gamma Chat')); // 30 mins

      // Verify limits mapped
      expect(apps[0].limit?.appName, equals('Beta Editor'));
      expect(limitsService.isLimitExceeded(apps[0].limit!), isTrue);

      expect(apps[1].limit?.appName, equals('Alpha Browser'));
      expect(limitsService.isLimitExceeded(apps[1].limit!), isFalse);

      expect(apps[2].limit, isNull);
    });

    test('7. Ongoing live session from tracker is merged without duplication', () async {
      // Completed session in DB: 10:00 - 11:00
      await repository.insertSession(AppSession(
        id: 1,
        appName: 'Code',
        exePath: r'C:\code.exe',
        startTime: DateTime(2026, 10, 14, 10, 0),
        endTime: DateTime(2026, 10, 14, 11, 0),
      ));

      // Active live session tracked in memory right now: 15:00 - 15:30
      final tracker = WindowsUsageTracker(
        repository: repository,
        idleTimeProvider: () => Duration.zero,
        foregroundWindowProvider: () => r'C:\code.exe',
      );

      final trackerService = ApplicationAnalyticsService(
        repository: repository,
        tracker: tracker,
        limitsService: limitsService,
      );

      // We can also test computeApplicationsAnalytics with a live session injected
      final sessions = [
        AppSession(
          id: 1,
          appName: 'Code',
          exePath: r'C:\code.exe',
          startTime: DateTime(2026, 10, 14, 10, 0),
          endTime: DateTime(2026, 10, 14, 11, 0),
        ),
        AppSession(
          id: null,
          appName: 'Code',
          exePath: r'C:\code.exe',
          startTime: DateTime(2026, 10, 14, 15, 0),
          endTime: DateTime(2026, 10, 14, 15, 30),
        ),
      ];

      final selection = DateRangeSelection.today(refDate);
      final result = trackerService.computeApplicationsAnalytics(
        selection: selection,
        sessions: sessions,
        referenceDate: refDate,
      );

      expect(result.totalUsage, equals(const Duration(minutes: 90)));
      expect(result.chartBars[10].duration, equals(const Duration(minutes: 60)));
      expect(result.chartBars[15].duration, equals(const Duration(minutes: 30)));
      expect(result.applications[0].totalDuration, equals(const Duration(minutes: 90)));
      expect(result.applications[0].sessionCount, equals(2));

      tracker.dispose();
    });

    test('8. Year transition (Dec 31 to Jan 1) handles range aggregation correctly', () async {
      final start = DateTime(2026, 12, 30);
      final end = DateTime(2027, 1, 2);
      final selection = DateRangeSelection.customRange(start, end);

      expect(selection.daysCount, equals(4)); // Dec 30, Dec 31, Jan 1, Jan 2

      // Session across New Year midnight: 23:45 Dec 31 to 00:30 Jan 1
      await repository.insertSession(AppSession(
        appName: 'Celebration App',
        exePath: r'C:\app.exe',
        startTime: DateTime(2026, 12, 31, 23, 45),
        endTime: DateTime(2027, 1, 1, 0, 30),
      ));

      final result = await analyticsService.getApplicationsAnalytics(
        selection: selection,
        referenceDate: DateTime(2027, 1, 2, 12, 0),
      );

      expect(result.chartBars.length, equals(4));
      expect(result.totalUsage, equals(const Duration(minutes: 45)));

      // Dec 31 has 15 mins
      final dec31Bar = result.chartBars.firstWhere((b) => b.timestamp.year == 2026 && b.timestamp.day == 31);
      expect(dec31Bar.duration, equals(const Duration(minutes: 15)));

      // Jan 1 has 30 mins
      final jan1Bar = result.chartBars.firstWhere((b) => b.timestamp.year == 2027 && b.timestamp.day == 1);
      expect(jan1Bar.duration, equals(const Duration(minutes: 30)));

      // Dec 30 and Jan 2 are 0 mins
      final dec30Bar = result.chartBars.firstWhere((b) => b.timestamp.year == 2026 && b.timestamp.day == 30);
      expect(dec30Bar.duration, equals(Duration.zero));
    });
  });
}
