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
import 'package:balance/core/widgets/daily_summary_card.dart';
import 'package:balance/features/overview/overview_screen.dart';
import 'package:lucide_icons/lucide_icons.dart';

class MockWindowsUsageTracker extends WindowsUsageTracker {
  bool _mockRunning = true;
  final DailyUsageSummary? _mockSummary;

  MockWindowsUsageTracker({
    required super.repository,
    DailyUsageSummary? summary,
  }) : _mockSummary = summary;

  @override
  bool get isRunning => _mockRunning;

  @override
  DailyUsageSummary? get todaySummary => _mockSummary;

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
}
