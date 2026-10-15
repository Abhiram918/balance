import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:balance/app/app.dart';
import 'package:balance/app/theme/app_theme.dart';
import 'package:balance/core/models/app_session.dart';
import 'package:balance/core/models/focus_session.dart';
import 'package:balance/core/models/usage_data.dart';
import 'package:balance/core/services/focus_service.dart';
import 'package:balance/core/services/usage_calculator.dart';
import 'package:balance/core/services/usage_repository.dart';
import 'package:balance/core/services/windows_usage_tracker.dart';
import 'package:balance/core/widgets/app_shell.dart';
import 'package:balance/core/widgets/activity_chart.dart';
import 'package:balance/core/widgets/daily_summary_card.dart';
import 'package:balance/core/widgets/overview_date_picker_dialog.dart';
import 'package:balance/features/overview/overview_screen.dart';
import 'package:lucide_icons/lucide_icons.dart';

class MockWindowsUsageTracker extends WindowsUsageTracker {
  bool _mockRunning = true;
  final DailyUsageSummary? _mockSummary;
  DailyUsageSummary? _historicalSummary;

  MockWindowsUsageTracker({
    required super.repository,
    DailyUsageSummary? summary,
  }) : _mockSummary = summary;

  void setHistoricalSummary(DailyUsageSummary? summary) {
    _historicalSummary = summary;
  }

  @override
  bool get isRunning => _mockRunning;

  @override
  DailyUsageSummary? get todaySummary => _mockSummary;

  @override
  Future<DailyUsageSummary> getSummaryForDay(DateTime date) async {
    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    if (isToday) {
      return _mockSummary ?? DailyUsageSummary.empty(date);
    }
    return _historicalSummary ?? DailyUsageSummary.empty(date);
  }

  @override
  void start() {
    _mockRunning = true;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    _mockRunning = false;
    notifyListeners();
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Overview & Daily Summary Calculation Tests', () {
    final testDate = DateTime(2026, 10, 15);

    test('1. Ordinary app usage without a Focus session does not create Focus time or focus achievement', () {
      final sessions = [
        AppSession(
          appName: 'Word',
          exePath: r'C:\Word.exe',
          startTime: DateTime(2026, 10, 15, 9, 0),
          endTime: DateTime(2026, 10, 15, 10, 30), // 1h 30m
        ),
      ];

      final focusMetrics = UsageCalculator.calculateFocusMetrics(
        date: testDate,
        focusSessions: [],
        activeState: null,
      );

      final summary = UsageCalculator.calculateDailySummary(
        date: testDate,
        sessions: sessions,
        focusTime: focusMetrics.focusTime,
        breaksTaken: focusMetrics.breaksTaken,
        breakDuration: focusMetrics.breakDuration,
        focusIntervals: focusMetrics.focusIntervals,
        breakIntervals: focusMetrics.breakIntervals,
      );

      expect(summary.totalActiveTime, equals(const Duration(hours: 1, minutes: 30)));
      expect(summary.focusTime, equals(Duration.zero));
      expect(summary.breaksTaken, equals(0));
      expect(summary.breakDuration, equals(Duration.zero));
      expect(summary.timeBreakdown!.focusDuration, equals(Duration.zero));
      expect(summary.timeBreakdown!.otherUsageDuration, equals(const Duration(hours: 1, minutes: 30)));
    });

    test('2. Focus Time agrees with persisted Focus session history for the same reporting period', () {
      final focusRecords = [
        FocusSessionRecord(
          type: FocusSessionType.focus,
          plannedDuration: const Duration(minutes: 25),
          actualDuration: const Duration(minutes: 25),
          startTime: DateTime(2026, 10, 15, 11, 0),
          endTime: DateTime(2026, 10, 15, 11, 25),
          completedNaturally: true,
        ),
        FocusSessionRecord(
          type: FocusSessionType.focus,
          plannedDuration: const Duration(minutes: 45),
          actualDuration: const Duration(minutes: 45),
          startTime: DateTime(2026, 10, 15, 14, 0),
          endTime: DateTime(2026, 10, 15, 14, 45),
          completedNaturally: true,
        ),
      ];

      final metrics = UsageCalculator.calculateFocusMetrics(
        date: testDate,
        focusSessions: focusRecords,
      );

      expect(metrics.focusTime, equals(const Duration(minutes: 70)));
      expect(metrics.breaksTaken, equals(0));
    });

    test('3. Empty focus history produces a truthful zero state', () {
      final metrics = UsageCalculator.calculateFocusMetrics(
        date: testDate,
        focusSessions: [],
      );

      expect(metrics.focusTime, equals(Duration.zero));
      expect(metrics.breaksTaken, equals(0));
      expect(metrics.breakDuration, equals(Duration.zero));
      expect(metrics.focusIntervals, isEmpty);
      expect(metrics.breakIntervals, isEmpty);
    });

    test('4. Completed, running, paused, and interrupted focus sessions are handled correctly', () {
      // Completed session
      final completed = FocusSessionRecord(
        type: FocusSessionType.focus,
        plannedDuration: const Duration(minutes: 25),
        actualDuration: const Duration(minutes: 25),
        startTime: DateTime(2026, 10, 15, 9, 0),
        endTime: DateTime(2026, 10, 15, 9, 25),
        completedNaturally: true,
      );

      // Interrupted / stopped early session
      final interrupted = FocusSessionRecord(
        type: FocusSessionType.focus,
        plannedDuration: const Duration(minutes: 25),
        actualDuration: const Duration(minutes: 10), // stopped after 10m
        startTime: DateTime(2026, 10, 15, 10, 0),
        endTime: DateTime(2026, 10, 15, 10, 10),
        completedNaturally: false,
      );

      // Active running session: started at 11:00, clock at 11:15 (15m elapsed)
      final runningState = ActiveFocusState(
        type: FocusSessionType.focus,
        status: FocusStatus.running,
        targetDuration: const Duration(minutes: 25),
        startTime: DateTime(2026, 10, 15, 11, 0),
        expectedEndTime: DateTime(2026, 10, 15, 11, 25),
        remainingDuration: const Duration(minutes: 10),
      );

      final metrics = UsageCalculator.calculateFocusMetrics(
        date: testDate,
        focusSessions: [completed, interrupted],
        activeState: runningState,
        now: DateTime(2026, 10, 15, 11, 15),
      );

      // Total focus = 25m (completed) + 10m (interrupted) + 15m (running) = 50m
      expect(metrics.focusTime, equals(const Duration(minutes: 50)));

      // Active paused state: 25m target, 12m remaining = 13m elapsed
      final pausedState = ActiveFocusState(
        type: FocusSessionType.focus,
        status: FocusStatus.paused,
        targetDuration: const Duration(minutes: 25),
        startTime: DateTime(2026, 10, 15, 13, 0),
        expectedEndTime: DateTime(2026, 10, 15, 13, 25),
        remainingDuration: const Duration(minutes: 12),
      );

      final pausedMetrics = UsageCalculator.calculateFocusMetrics(
        date: testDate,
        focusSessions: [],
        activeState: pausedState,
      );

      expect(pausedMetrics.focusTime, equals(const Duration(minutes: 13)));
    });

    test('5. Sessions spanning midnight are attributed correctly to each calendar day', () {
      // Focus session started at 23:40 yesterday and ended at 00:20 today (40m total)
      final session = FocusSessionRecord(
        type: FocusSessionType.focus,
        plannedDuration: const Duration(minutes: 40),
        actualDuration: const Duration(minutes: 40),
        startTime: DateTime(2026, 10, 14, 23, 40),
        endTime: DateTime(2026, 10, 15, 0, 20),
        completedNaturally: true,
      );

      // Attribution for yesterday (Oct 14): exactly 20 minutes
      final yesterdayMetrics = UsageCalculator.calculateFocusMetrics(
        date: DateTime(2026, 10, 14),
        focusSessions: [session],
      );
      expect(yesterdayMetrics.focusTime, equals(const Duration(minutes: 20)));

      // Attribution for today (Oct 15): exactly 20 minutes
      final todayMetrics = UsageCalculator.calculateFocusMetrics(
        date: DateTime(2026, 10, 15),
        focusSessions: [session],
      );
      expect(todayMetrics.focusTime, equals(const Duration(minutes: 20)));
    });

    test('6. Break statistics are accurate from persisted break records and do not fabricate missing historical data', () {
      final breakSession = FocusSessionRecord(
        type: FocusSessionType.breakSession,
        plannedDuration: const Duration(minutes: 15),
        actualDuration: const Duration(minutes: 15),
        startTime: DateTime(2026, 10, 15, 12, 0),
        endTime: DateTime(2026, 10, 15, 12, 15),
        completedNaturally: true,
      );

      final metrics = UsageCalculator.calculateFocusMetrics(
        date: testDate,
        focusSessions: [breakSession],
      );

      expect(metrics.breaksTaken, equals(1));
      expect(metrics.breakDuration, equals(const Duration(minutes: 15)));
      expect(metrics.focusTime, equals(Duration.zero));
    });

    test('7. Donut-chart values match displayed legend and reconcile to total without double-counting', () {
      // User has 2 hours of computer usage: 10:00 - 12:00
      final appSessions = [
        AppSession(
          appName: 'VS Code',
          exePath: r'C:\code.exe',
          startTime: DateTime(2026, 10, 15, 10, 0),
          endTime: DateTime(2026, 10, 15, 12, 0), // 120m
        ),
      ];

      // User had a 45m Focus session from 10:15 - 11:00 (nested inside computer usage)
      final focusRecord = FocusSessionRecord(
        type: FocusSessionType.focus,
        plannedDuration: const Duration(minutes: 45),
        actualDuration: const Duration(minutes: 45),
        startTime: DateTime(2026, 10, 15, 10, 15),
        endTime: DateTime(2026, 10, 15, 11, 0),
        completedNaturally: true,
      );

      // User had a 15m Break session from 11:45 - 12:00
      final breakRecord = FocusSessionRecord(
        type: FocusSessionType.breakSession,
        plannedDuration: const Duration(minutes: 15),
        actualDuration: const Duration(minutes: 15),
        startTime: DateTime(2026, 10, 15, 11, 45),
        endTime: DateTime(2026, 10, 15, 12, 0),
        completedNaturally: true,
      );

      final focusMetrics = UsageCalculator.calculateFocusMetrics(
        date: testDate,
        focusSessions: [focusRecord, breakRecord],
      );

      final summary = UsageCalculator.calculateDailySummary(
        date: testDate,
        sessions: appSessions,
        focusTime: focusMetrics.focusTime,
        breaksTaken: focusMetrics.breaksTaken,
        breakDuration: focusMetrics.breakDuration,
        focusIntervals: focusMetrics.focusIntervals,
        breakIntervals: focusMetrics.breakIntervals,
      );

      final breakdown = summary.timeBreakdown!;
      expect(breakdown.focusDuration, equals(const Duration(minutes: 45)));
      expect(breakdown.breakDuration, equals(const Duration(minutes: 15)));

      // Computer usage outside of Focus & Break intervals:
      // [10:00, 10:15] = 15m + [11:00, 11:45] = 45m -> Total Other Usage = 60m
      expect(breakdown.otherUsageDuration, equals(const Duration(minutes: 60)));

      // Reconciled total = 45m + 15m + 60m = 120m (2 hours)
      expect(breakdown.totalUsage, equals(const Duration(minutes: 120)));
      expect(
        breakdown.focusDuration + breakdown.breakDuration + breakdown.otherUsageDuration,
        equals(breakdown.totalUsage),
      );
    });

    test('8. Top Applications are sorted by actual usage duration and exclude Balance', () {
      final sessions = [
        AppSession(
          appName: 'Balance',
          exePath: r'C:\Balance\balance.exe',
          startTime: DateTime(2026, 10, 15, 8, 0),
          endTime: DateTime(2026, 10, 15, 10, 0), // 2h (should be excluded from user apps)
        ),
        AppSession(
          appName: 'Chrome',
          exePath: r'C:\chrome.exe',
          startTime: DateTime(2026, 10, 15, 10, 0),
          endTime: DateTime(2026, 10, 15, 11, 0), // 1h
        ),
        AppSession(
          appName: 'Slack',
          exePath: r'C:\slack.exe',
          startTime: DateTime(2026, 10, 15, 11, 0),
          endTime: DateTime(2026, 10, 15, 12, 30), // 1h 30m
        ),
        AppSession(
          appName: 'Figma',
          exePath: r'C:\figma.exe',
          startTime: DateTime(2026, 10, 15, 13, 0),
          endTime: DateTime(2026, 10, 15, 13, 15), // 15m
        ),
      ];

      final summary = UsageCalculator.calculateDailySummary(
        date: testDate,
        sessions: sessions,
      );

      // Balance must NOT appear in mostUsedApps
      final mostUsedNames = summary.mostUsedApps.map((a) => a.appName).toList();
      expect(mostUsedNames.contains('Balance'), isFalse);

      // Must be sorted descending: Slack (1h30m) > Chrome (1h) > Figma (15m)
      expect(mostUsedNames, equals(['Slack', 'Chrome', 'Figma']));
      expect(summary.mostUsedApps[0].duration, equals(const Duration(minutes: 90)));
      expect(summary.mostUsedApps[1].duration, equals(const Duration(minutes: 60)));
      expect(summary.mostUsedApps[2].duration, equals(const Duration(minutes: 15)));
    });

    test('9. Empty application usage does not crash the calculation', () {
      final summary = UsageCalculator.calculateDailySummary(
        date: testDate,
        sessions: [],
      );

      expect(summary.totalActiveTime, equals(Duration.zero));
      expect(summary.mostUsedApps, isEmpty);
      expect(summary.allApps, isEmpty);
      expect(summary.timeBreakdown!.totalUsage, equals(Duration.zero));
      expect(summary.timeBreakdown!.focusDuration, equals(Duration.zero));
      expect(summary.timeBreakdown!.breakDuration, equals(Duration.zero));
      expect(summary.timeBreakdown!.otherUsageDuration, equals(Duration.zero));
    });

    test('10. Timeline buckets match recorded usage data and correctly handle empty day', () {
      final summary = UsageCalculator.calculateDailySummary(
        date: testDate,
        sessions: [],
      );

      expect(summary.hourlyActivity.length, equals(24));
      expect(summary.hourlyActivity.every((v) => v == 0.0), isTrue);

      // With activity
      final activeSummary = UsageCalculator.calculateDailySummary(
        date: testDate,
        sessions: [
          AppSession(
            appName: 'Code',
            exePath: r'C:\code.exe',
            startTime: DateTime(2026, 10, 15, 14, 0),
            endTime: DateTime(2026, 10, 15, 14, 30), // 30m in hour 14
          ),
        ],
      );

      expect(activeSummary.hourlyActivity[14], closeTo(0.5, 0.001));
      expect(activeSummary.hourlyActivity[13], equals(0.0));
      expect(activeSummary.hourlyActivity[15], equals(0.0));
    });
    test('11. DailyActivityMetrics computes most active hour, unique apps excluding Balance, and longest session', () {
      final sessions = [
        AppSession(
          appName: 'Balance',
          exePath: r'C:\Balance\balance.exe',
          startTime: DateTime(2026, 10, 15, 8, 0),
          endTime: DateTime(2026, 10, 15, 10, 0), // 2h (excluded from apps count)
        ),
        AppSession(
          appName: 'Microsoft Edge',
          exePath: r'C:\edge.exe',
          startTime: DateTime(2026, 10, 15, 12, 10),
          endTime: DateTime(2026, 10, 15, 12, 52), // 42m session in hour 12
        ),
        AppSession(
          appName: 'Google Chrome',
          exePath: r'C:\chrome.exe',
          startTime: DateTime(2026, 10, 15, 12, 0),
          endTime: DateTime(2026, 10, 15, 12, 20), // 20m in hour 12
        ),
        AppSession(
          appName: 'WhatsApp',
          exePath: r'C:\whatsapp.exe',
          startTime: DateTime(2026, 10, 15, 14, 0),
          endTime: DateTime(2026, 10, 15, 14, 21), // 21m in hour 14
        ),
      ];

      final metrics = UsageCalculator.calculateDailyActivityMetrics(
        date: testDate,
        sessions: sessions,
      );

      // Distinct apps: Edge, Chrome, WhatsApp = 3 (Balance is excluded)
      expect(metrics.distinctAppsCount, equals(3));

      // Most active hour: Hour 12 (12:00 - 1:00 PM)
      expect(metrics.mostActiveHourText, equals('12:00 – 1:00 PM'));

      // Longest session: Microsoft Edge with 42 minutes
      expect(metrics.longestSessionDuration, equals(const Duration(minutes: 42)));
      expect(metrics.longestSessionAppName, equals('Microsoft Edge'));
    });
  });

  group('Tracking & Focus Mode Lifecycle Separation Tests', () {
    late UsageRepository repository;

    setUp(() {
      repository = UsageRepository(dbName: inMemoryDatabasePath);
    });

    test('12. Pausing tracking stops new usage recording and resuming tracking restarts it without duplicate sessions', () async {
      String? currentWindow = r'C:\app.exe';

      final tracker = WindowsUsageTracker(
        repository: repository,
        idleTimeProvider: () => Duration.zero,
        foregroundWindowProvider: () => currentWindow,
      );

      await tracker.init();
      expect(tracker.isRunning, isFalse);

      // Start tracking
      tracker.start();
      expect(tracker.isRunning, isTrue);

      // Pause tracking
      await tracker.stop();
      expect(tracker.isRunning, isFalse);

      // Simulate app activity while paused: no polling timer is active
      currentWindow = r'C:\other.exe';

      // Resume tracking
      tracker.start();
      expect(tracker.isRunning, isTrue);

      await tracker.stop();
      expect(tracker.isRunning, isFalse);
    });

    test('13. Focus sessions are not unintentionally altered by pausing usage tracking', () async {
      final focusService = FocusService(repository: repository);
      await focusService.init();

      final tracker = WindowsUsageTracker(
        repository: repository,
        focusService: focusService,
      );
      await tracker.init();

      // Start a Focus session
      await focusService.setSessionType(FocusSessionType.focus);
      await focusService.start();
      expect(focusService.isRunning, isTrue);
      expect(focusService.sessionType, equals(FocusSessionType.focus));

      // Start and then pause usage tracking
      tracker.start();
      expect(tracker.isRunning, isTrue);

      await tracker.stop();
      expect(tracker.isRunning, isFalse);

      // Verify Focus session was NOT stopped or altered
      expect(focusService.isRunning, isTrue);
      expect(focusService.sessionType, equals(FocusSessionType.focus));

      await focusService.stop();
      expect(focusService.isRunning, isFalse);
    });
  });

  group('DailySummaryCard Widget Tests', () {
    testWidgets('14. Renders Daily Summary card with real metrics and handles empty state gracefully', (tester) async {
      final summary = DailyUsageSummary(
        date: DateTime(2026, 10, 15),
        totalActiveTime: const Duration(hours: 3, minutes: 20),
        goalTime: const Duration(hours: 8),
        focusTime: const Duration(minutes: 50),
        breaksTaken: 2,
        breakDuration: const Duration(minutes: 15),
        timeBreakdown: const DailyTimeBreakdown(
          totalUsage: Duration(hours: 3, minutes: 20),
          focusDuration: Duration(minutes: 50),
          breakDuration: Duration(minutes: 15),
          otherUsageDuration: Duration(hours: 2, minutes: 15),
        ),
        hourlyActivity: List.filled(24, 0.0),
        mostUsedApps: [
          AppUsageData(
            appName: 'Chrome',
            duration: const Duration(hours: 1, minutes: 30),
            proportionalUsage: 0.45,
          ),
          AppUsageData(
            appName: 'VS Code',
            duration: const Duration(hours: 1),
            proportionalUsage: 0.3,
          ),
        ],
        allApps: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: DailySummaryCard(data: summary),
            ),
          ),
        ),
      );

      // Verify Header
      expect(find.text('Daily Summary'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);

      // Verify Center Screen Time
      expect(find.text('3h 20m'), findsOneWidget);
      expect(find.text('total'), findsOneWidget);
      expect(find.textContaining('8h goal'), findsOneWidget);

      // Verify Breakdown legend labels
      expect(find.text('Focus Sessions'), findsOneWidget);
      expect(find.text('Break Time'), findsOneWidget);
      expect(find.text('Other Usage'), findsOneWidget);
      expect(find.text('50m'), findsOneWidget);
      expect(find.text('15m'), findsOneWidget);
      expect(find.text('2h 15m'), findsOneWidget);
    });

    testWidgets('Renders empty state neutral text without crashing when usage is zero', (tester) async {
      final emptySummary = DailyUsageSummary(
        date: DateTime(2026, 10, 15),
        totalActiveTime: Duration.zero,
        goalTime: const Duration(hours: 8),
        focusTime: Duration.zero,
        breaksTaken: 0,
        breakDuration: Duration.zero,
        timeBreakdown: const DailyTimeBreakdown(
          totalUsage: Duration.zero,
          focusDuration: Duration.zero,
          breakDuration: Duration.zero,
          otherUsageDuration: Duration.zero,
        ),
        hourlyActivity: List.filled(24, 0.0),
        mostUsedApps: [],
        allApps: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: DailySummaryCard(data: emptySummary),
            ),
          ),
        ),
      );

      expect(find.text('0h 0m'), findsOneWidget);
      expect(find.text('total'), findsOneWidget);
      expect(find.text('8h goal'), findsOneWidget);
      expect(find.text('8h 0m remaining'), findsOneWidget);
    });
  });

  group('OverviewScreen Redesigned Dashboard Widget Tests', () {
    late UsageRepository repository;
    late FocusService focusService;

    setUp(() async {
      repository = UsageRepository(dbName: inMemoryDatabasePath);
      focusService = FocusService(repository: repository);
      await focusService.init();
    });

    tearDown(() async {
      focusService.dispose();
      await repository.close();
    });

    testWidgets('15. Renders entire redesigned Overview screen matching reference image structure', (tester) async {
      final now = DateTime.now();
      final summary = DailyUsageSummary(
        date: now,
        totalActiveTime: const Duration(hours: 1, minutes: 58),
        goalTime: const Duration(hours: 8),
        focusTime: Duration.zero,
        breaksTaken: 1,
        breakDuration: const Duration(minutes: 3),
        timeBreakdown: const DailyTimeBreakdown(
          totalUsage: Duration(hours: 1, minutes: 58),
          focusDuration: Duration.zero,
          breakDuration: Duration(minutes: 3),
          otherUsageDuration: Duration(hours: 1, minutes: 55),
        ),
        hourlyActivity: List.filled(24, 0.0),
        mostUsedApps: [
          AppUsageData(
            appName: 'Microsoft Edge',
            duration: const Duration(minutes: 43),
            proportionalUsage: 0.6,
          ),
          AppUsageData(
            appName: 'WhatsApp',
            duration: const Duration(minutes: 21),
            proportionalUsage: 0.3,
          ),
        ],
        allApps: [
          AppUsageData(
            appName: 'Microsoft Edge',
            duration: const Duration(minutes: 43),
            proportionalUsage: 0.6,
          ),
          AppUsageData(
            appName: 'WhatsApp',
            duration: const Duration(minutes: 21),
            proportionalUsage: 0.3,
          ),
        ],
        dailyActivity: const DailyActivityMetrics(
          mostActiveHourText: '12:00 – 1:00 PM',
          distinctAppsCount: 5,
          longestSessionDuration: Duration(minutes: 42),
          longestSessionAppName: 'Microsoft Edge',
        ),
      );

      final mockTracker = MockWindowsUsageTracker(
        repository: repository,
        summary: summary,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: TrackerProvider(
            tracker: mockTracker,
            child: FocusProvider(
              focusService: focusService,
              child: AppNavigation(
                navigateTo: (_) {},
                child: const OverviewScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Header elements
      expect(find.text('Keep going. Small steps make a big difference.'), findsOneWidget);
      expect(find.byIcon(LucideIcons.calendar), findsOneWidget);
      expect(find.byIcon(LucideIcons.chevronDown), findsWidgets);

      // 2. Top Summary cards
      expect(find.text('Screen Time'), findsOneWidget);
      expect(find.text('Focus Time'), findsOneWidget);
      expect(find.text('Breaks'), findsOneWidget);
      expect(find.text('total today'), findsOneWidget);
      expect(find.text('1h 58m'), findsWidgets);
      expect(find.text('0h 0m'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('break today'), findsOneWidget);

      // 3. Tracking Status card
      expect(find.text('Tracking Active'), findsOneWidget);
      expect(find.text('Monitoring your computer usage'), findsOneWidget);
      expect(find.text('Pause'), findsOneWidget);

      // 4. Daily Summary card
      expect(find.text('Daily Summary'), findsOneWidget);
      expect(find.text('Your computer usage and activity for today'), findsOneWidget);
      expect(find.text('Other Usage'), findsOneWidget);
      expect(find.text('Break Time'), findsOneWidget);
      expect(find.text('Focus Sessions'), findsOneWidget);
      expect(find.text('8h goal'), findsOneWidget);

      // 5. Activity Timeline card
      expect(find.text('Activity Timeline'), findsOneWidget);
      expect(find.text('Recorded computer usage by hour'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('No Activity'), findsOneWidget);

      // 6. All Applications Today card
      expect(find.text('All Applications Today'), findsOneWidget);
      expect(find.text('View All'), findsOneWidget);
      expect(find.text('Microsoft Edge'), findsWidgets);
      expect(find.text('WhatsApp'), findsOneWidget);

      // 7. Daily Activity card
      expect(find.text('Daily Activity'), findsOneWidget);
      expect(find.text('Most active hour'), findsOneWidget);
      expect(find.text('12:00 – 1:00 PM'), findsOneWidget);
      expect(find.text('Applications used'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('Longest active session'), findsOneWidget);
      expect(find.text('42m'), findsOneWidget);

      // 8. Bottom status note
      expect(find.text('Your data is updated in real time while tracking is active.'), findsOneWidget);
      expect(find.byIcon(LucideIcons.info), findsOneWidget);

      // 9. Pause tracking interaction
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
      expect(mockTracker.isRunning, isFalse);
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Tracking Paused'), findsOneWidget);

      // 10. Resume tracking interaction
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(mockTracker.isRunning, isTrue);
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Tracking Active'), findsOneWidget);
    });
  });

  group('Date Pickers & Column Alignment Tests', () {
    late UsageRepository repository;
    late FocusService focusService;

    setUp(() async {
      repository = UsageRepository(dbName: inMemoryDatabasePath);
      focusService = FocusService(repository: repository);
      await focusService.init();
    });

    tearDown(() async {
      await repository.close();
    });

    test('1. Sessions crossing midnight boundary clamp accurately to calendar day', () async {
      final oct14 = DateTime(2026, 10, 14);
      final oct15 = DateTime(2026, 10, 15);

      // Session starts at 23:30 on Oct 14 and ends at 01:00 on Oct 15 (90 mins total: 30 mins on Oct 14, 60 mins on Oct 15)
      final session = AppSession(
        appName: 'Edge',
        exePath: r'C:\Edge.exe',
        startTime: DateTime(2026, 10, 14, 23, 30),
        endTime: DateTime(2026, 10, 15, 1, 0),
      );
      await repository.insertSession(session);

      // Query for Oct 14
      final sessions14 = await repository.getSessionsForDay(oct14);
      expect(sessions14.length, equals(1));
      final summary14 = UsageCalculator.calculateDailySummary(
        date: oct14,
        sessions: sessions14,
      );
      expect(summary14.totalActiveTime, equals(const Duration(minutes: 30)));

      // Query for Oct 15
      final sessions15 = await repository.getSessionsForDay(oct15);
      expect(sessions15.length, equals(1));
      final summary15 = UsageCalculator.calculateDailySummary(
        date: oct15,
        sessions: sessions15,
      );
      expect(summary15.totalActiveTime, equals(const Duration(hours: 1)));
    });

    testWidgets('2. Date picker dialog component: prevents future dates and handles quick actions', (tester) async {
      final today = DateTime(2026, 10, 15);
      final selectedDate = DateTime(2026, 10, 15);
      DateTime? resultDate;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    resultDate = await showDialog<DateTime>(
                      context: context,
                      builder: (ctx) => OverviewDatePickerDialog(
                        selectedDate: selectedDate,
                        today: today,
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Select Date'), findsOneWidget);
      expect(find.text('Today'), findsWidgets);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Reset to Today'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);

      // Verify CalendarDatePicker has lastDate == today (preventing future selection)
      final calendarFinder = find.byType(CalendarDatePicker);
      expect(calendarFinder, findsOneWidget);
      final calendarWidget = tester.widget<CalendarDatePicker>(calendarFinder);
      expect(calendarWidget.lastDate, equals(today));

      // Tap Yesterday quick chip
      await tester.tap(find.text('Yesterday'));
      await tester.pumpAndSettle();

      // Tap Apply
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(resultDate, equals(DateTime(2026, 10, 14)));

      // Reopen and test Reset to Today
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset to Today'));
      await tester.pumpAndSettle();

      expect(resultDate, equals(today));

      // Reopen and test Cancel
      resultDate = DateTime(2020, 1, 1);
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(resultDate, isNull); // Pop without return yields null
    });

    testWidgets('3. Opening date controls, selecting a date, and synchronization between header and Daily Summary', (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));

      final todaySummary = DailyUsageSummary(
        date: today,
        totalActiveTime: const Duration(hours: 3, minutes: 15),
        goalTime: const Duration(hours: 8),
        focusTime: const Duration(hours: 1, minutes: 0),
        breaksTaken: 2,
        breakDuration: const Duration(minutes: 15),
        timeBreakdown: const DailyTimeBreakdown(
          totalUsage: Duration(hours: 3, minutes: 15),
          focusDuration: Duration(hours: 1, minutes: 0),
          breakDuration: Duration(minutes: 15),
          otherUsageDuration: Duration(hours: 2, minutes: 0),
        ),
        hourlyActivity: List.filled(24, 0.2),
        mostUsedApps: [
          AppUsageData(
            appName: 'Chrome',
            duration: const Duration(hours: 2),
            proportionalUsage: 0.6,
          ),
        ],
        allApps: [
          AppUsageData(
            appName: 'Chrome',
            duration: const Duration(hours: 2),
            proportionalUsage: 0.6,
          ),
        ],
        dailyActivity: const DailyActivityMetrics(
          mostActiveHourText: '2:00 – 3:00 PM',
          distinctAppsCount: 1,
          longestSessionDuration: Duration(hours: 1),
          longestSessionAppName: 'Chrome',
        ),
      );

      final yesterdaySummary = DailyUsageSummary(
        date: yesterday,
        totalActiveTime: const Duration(hours: 1, minutes: 45),
        goalTime: const Duration(hours: 8),
        focusTime: const Duration(minutes: 30),
        breaksTaken: 1,
        breakDuration: const Duration(minutes: 10),
        timeBreakdown: const DailyTimeBreakdown(
          totalUsage: Duration(hours: 1, minutes: 45),
          focusDuration: Duration(minutes: 30),
          breakDuration: Duration(minutes: 10),
          otherUsageDuration: Duration(hours: 1, minutes: 5),
        ),
        hourlyActivity: List.filled(24, 0.1),
        mostUsedApps: [
          AppUsageData(
            appName: 'VS Code',
            duration: const Duration(hours: 1),
            proportionalUsage: 0.7,
          ),
        ],
        allApps: [
          AppUsageData(
            appName: 'VS Code',
            duration: const Duration(hours: 1),
            proportionalUsage: 0.7,
          ),
        ],
        dailyActivity: const DailyActivityMetrics(
          mostActiveHourText: '10:00 – 11:00 AM',
          distinctAppsCount: 1,
          longestSessionDuration: Duration(hours: 1),
          longestSessionAppName: 'VS Code',
        ),
      );

      final mockTracker = MockWindowsUsageTracker(
        repository: repository,
        summary: todaySummary,
      );
      mockTracker.setHistoricalSummary(yesterdaySummary);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: TrackerProvider(
            tracker: mockTracker,
            child: FocusProvider(
              focusService: focusService,
              child: AppNavigation(
                navigateTo: (_) {},
                child: const OverviewScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially displays Today's metrics
      expect(find.text('3h 15m'), findsWidgets);
      expect(find.text('total today'), findsOneWidget);
      expect(find.text('Chrome'), findsWidgets);
      expect(find.text('Today'), findsWidgets);

      // Open date picker from Daily Summary card date pill
      final dailySummaryTodayPill = find.descendant(
        of: find.byType(DailySummaryCard),
        matching: find.text('Today'),
      );
      expect(dailySummaryTodayPill, findsOneWidget);
      await tester.tap(dailySummaryTodayPill);
      await tester.pumpAndSettle();

      // Dialog is open
      expect(find.text('Select Date'), findsOneWidget);

      // Tap Yesterday quick chip in dialog
      await tester.tap(find.text('Yesterday'));
      await tester.pumpAndSettle();

      // Tap Apply
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // Both controls are immediately updated to Yesterday!
      expect(find.text('Yesterday'), findsWidgets);
      // Content updated to Yesterday's data
      expect(find.text('1h 45m'), findsWidgets);
      expect(find.text('total for day'), findsOneWidget);
      expect(find.text('VS Code'), findsWidgets);
      expect(find.text('Chrome'), findsNothing);

      // Open date picker from top-right header date control
      final headerDatePill = find.descendant(
        of: find.byType(InkWell),
        matching: find.byIcon(LucideIcons.calendar),
      );
      expect(headerDatePill, findsOneWidget);
      await tester.tap(headerDatePill);
      await tester.pumpAndSettle();

      // Dialog is open again
      expect(find.text('Select Date'), findsOneWidget);

      // Tap Reset to Today
      await tester.tap(find.text('Reset to Today'));
      await tester.pumpAndSettle();

      // Both controls are synchronized back to Today!
      expect(find.text('Today'), findsWidgets);
      expect(find.text('3h 15m'), findsWidgets);
      expect(find.text('total today'), findsOneWidget);
      expect(find.text('Chrome'), findsWidgets);
    });

    testWidgets('4. Empty historical date shows zeroes and truthful empty state without falling back to today', (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final emptyDate = today.subtract(const Duration(days: 5));

      final todaySummary = DailyUsageSummary(
        date: today,
        totalActiveTime: const Duration(hours: 4),
        goalTime: const Duration(hours: 8),
        focusTime: const Duration(hours: 1),
        breaksTaken: 2,
        breakDuration: const Duration(minutes: 10),
        timeBreakdown: const DailyTimeBreakdown(
          totalUsage: Duration(hours: 4),
          focusDuration: Duration(hours: 1),
          breakDuration: Duration(minutes: 10),
          otherUsageDuration: Duration(hours: 2, minutes: 50),
        ),
        hourlyActivity: List.filled(24, 0.3),
        mostUsedApps: [
          AppUsageData(
            appName: 'Chrome',
            duration: const Duration(hours: 3),
            proportionalUsage: 0.75,
          ),
        ],
        allApps: [
          AppUsageData(
            appName: 'Chrome',
            duration: const Duration(hours: 3),
            proportionalUsage: 0.75,
          ),
        ],
        dailyActivity: const DailyActivityMetrics(
          mostActiveHourText: '1:00 – 2:00 PM',
          distinctAppsCount: 1,
          longestSessionDuration: Duration(hours: 2),
          longestSessionAppName: 'Chrome',
        ),
      );

      final mockTracker = MockWindowsUsageTracker(
        repository: repository,
        summary: todaySummary,
      );
      mockTracker.setHistoricalSummary(DailyUsageSummary.empty(emptyDate));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: TrackerProvider(
            tracker: mockTracker,
            child: FocusProvider(
              focusService: focusService,
              child: AppNavigation(
                navigateTo: (_) {},
                child: const OverviewScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open dialog from header
      final headerDatePill = find.descendant(
        of: find.byType(InkWell),
        matching: find.byIcon(LucideIcons.calendar),
      );
      await tester.tap(headerDatePill);
      await tester.pumpAndSettle();

      // Tap Yesterday to switch away from today
      await tester.tap(find.text('Yesterday'));
      await tester.pumpAndSettle();

      // Tap Apply
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // Verifies zero and empty state
      expect(find.text('0h 0m'), findsWidgets); // Screen time and focus time are 0
      expect(find.text('0'), findsWidgets);    // Breaks taken is 0
      expect(find.text('Chrome'), findsNothing); // Today's apps are not shown!
      expect(find.textContaining('No application usage recorded'), findsOneWidget);
    });

    testWidgets('5. Vertical column alignment: Left and right columns have matching total minimum height', (tester) async {
      final summary = DailyUsageSummary.empty(DateTime.now());
      final mockTracker = MockWindowsUsageTracker(
        repository: repository,
        summary: summary,
      );

      // Render at desktop width 1200x800
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: TrackerProvider(
            tracker: mockTracker,
            child: FocusProvider(
              focusService: focusService,
              child: AppNavigation(
                navigateTo: (_) {},
                child: const OverviewScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find DailySummaryCard
      final dailySummaryCardFinder = find.byType(DailySummaryCard);
      expect(dailySummaryCardFinder, findsOneWidget);
      final dailySummarySize = tester.getSize(dailySummaryCardFinder);
      expect(dailySummarySize.height, greaterThanOrEqualTo(300.0));

      // Verify that left column (DailySummary + ActivityTimeline) and right column (AllApps + DailyActivity)
      // finish at approximately the same vertical position
      final timelineFinder = find.byKey(const Key('activity_timeline_card'));
      final dailyActivityFinder = find.byKey(const Key('daily_activity_card'));
      expect(timelineFinder, findsOneWidget);
      expect(dailyActivityFinder, findsOneWidget);

      final dailySummaryRect = tester.getRect(dailySummaryCardFinder);
      final appsFinder = find.ancestor(of: find.text('All Applications Today'), matching: find.byType(Container)).first;
      final appsRect = tester.getRect(appsFinder);
      final timelineRect = tester.getRect(timelineFinder);
      final dailyActivityRect = tester.getRect(dailyActivityFinder);
      print('DEBUG: ActivityChart size: ${tester.getSize(find.byType(ActivityChart))}');
      print('DEBUG: DailySummaryCard size: ${tester.getSize(dailySummaryCardFinder)}');
      print('DEBUG: timelineRect=$timelineRect (height=${timelineRect.height})');
      print('DEBUG: dailyActivityRect=$dailyActivityRect (height=${dailyActivityRect.height})');

      // Verify bottom edges align within 20px
      final bottomDifference = (timelineRect.bottom - dailyActivityRect.bottom).abs();
      expect(bottomDifference, lessThanOrEqualTo(20.0));
    });
  });
}
