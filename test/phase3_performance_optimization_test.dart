import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:balance/app/app.dart';
import 'package:balance/app/theme/app_colors.dart';
import 'package:balance/core/models/analytics_data.dart';
import 'package:balance/core/models/app_limit.dart';
import 'package:balance/core/models/app_session.dart';
import 'package:balance/core/models/application_analytics_models.dart';
import 'package:balance/core/models/focus_preset.dart';
import 'package:balance/core/models/focus_session.dart';
import 'package:balance/core/models/usage_data.dart';
import 'package:balance/core/services/app_enforcement_service.dart';
import 'package:balance/core/services/application_analytics_service.dart';
import 'package:balance/core/services/focus_service.dart';
import 'package:balance/core/services/limits_service.dart';
import 'package:balance/core/services/usage_analytics_service.dart';
import 'package:balance/core/services/usage_repository.dart';
import 'package:balance/core/services/windows_process_manager.dart';
import 'package:balance/core/services/windows_tray_service.dart';
import 'package:balance/core/services/windows_usage_tracker.dart';
import 'package:balance/features/applications/applications_screen.dart';
import 'package:balance/features/insights/insights_screen.dart';
import 'package:balance/features/overview/overview_screen.dart';

class TestableWindowsUsageTracker extends WindowsUsageTracker {
  DailyUsageSummary? _customSummary;

  TestableWindowsUsageTracker({
    required super.repository,
    super.idleTimeProvider,
    super.foregroundWindowProvider,
    super.clock,
    super.checkpointInterval,
  });

  void setTodaySummaryForTesting(DailyUsageSummary summary) {
    _customSummary = summary;
  }

  @override
  DailyUsageSummary? get todaySummary => _customSummary ?? super.todaySummary;
}

class Phase3TestRepository extends UsageRepository {
  final List<AppSession> storedSessions = [];
  final List<FocusSessionRecord> storedFocusSessions = [];
  final List<AppLimit> storedLimits = [];
  final List<FocusPreset> storedPresets = [];
  ActiveFocusState? storedActiveState;

  int getSessionsForDayCalls = 0;
  int getSessionsForRangeCalls = 0;
  int insertSessionCalls = 0;
  int updateSessionEndTimeCalls = 0;

  Phase3TestRepository() : super(dbName: inMemoryDatabasePath);

  @override
  Future<List<AppSession>> getSessionsForDay(DateTime date) async {
    getSessionsForDayCalls++;
    final start = DateTime(date.year, date.month, date.day);
    final end = DateTime(date.year, date.month, date.day + 1);
    return storedSessions.where((s) => s.startTime.isBefore(end) && s.endTime.isAfter(start)).toList();
  }

  @override
  Future<List<AppSession>> getSessionsForRange(DateTime start, DateTime end) async {
    getSessionsForRangeCalls++;
    return storedSessions.where((s) => s.startTime.isBefore(end) && s.endTime.isAfter(start)).toList();
  }

  @override
  Future<AppSession> insertSession(AppSession session) async {
    insertSessionCalls++;
    final assignedId = storedSessions.length + 1;
    final created = AppSession(
      id: assignedId,
      appName: session.appName,
      exePath: session.exePath,
      startTime: session.startTime,
      endTime: session.endTime,
    );
    storedSessions.add(created);
    return created;
  }

  @override
  Future<void> updateSessionEndTime(int id, DateTime endTime) async {
    updateSessionEndTimeCalls++;
    final idx = storedSessions.indexWhere((s) => s.id == id);
    if (idx != -1) {
      final old = storedSessions[idx];
      storedSessions[idx] = AppSession(
        id: old.id,
        appName: old.appName,
        exePath: old.exePath,
        startTime: old.startTime,
        endTime: endTime,
      );
    }
  }

  @override
  Future<List<FocusSessionRecord>> getFocusSessionsForDay(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = DateTime(date.year, date.month, date.day + 1);
    return storedFocusSessions.where((s) => s.startTime.isBefore(end) && s.endTime.isAfter(start)).toList();
  }

  @override
  Future<List<FocusSessionRecord>> getFocusSessionsForRange(DateTime start, DateTime end) async {
    return storedFocusSessions.where((s) => s.startTime.isBefore(end) && s.endTime.isAfter(start)).toList();
  }

  @override
  Future<List<FocusSessionRecord>> getRecentFocusSessions({int limit = 10}) async {
    return List.unmodifiable(storedFocusSessions.reversed.take(limit).toList());
  }

  @override
  Future<FocusSessionRecord> insertFocusSession(FocusSessionRecord session) async {
    storedFocusSessions.add(session);
    return session;
  }

  @override
  Future<List<AppLimit>> getAllLimits() async => List.unmodifiable(storedLimits);

  @override
  Future<ActiveFocusState?> getActiveFocusState() async => storedActiveState;

  @override
  Future<void> saveActiveFocusState(ActiveFocusState state) async {
    storedActiveState = state;
  }

  @override
  Future<void> clearActiveFocusState() async {
    storedActiveState = null;
  }

  final Set<String> sentNotificationKeys = {};

  @override
  Future<bool> hasLimitNotificationBeenSent(int limitId, String notificationType, String dateKey) async {
    return sentNotificationKeys.contains('$limitId:$notificationType:$dateKey');
  }

  @override
  Future<void> recordLimitNotificationSent(int limitId, String notificationType, String dateKey, DateTime sentAt) async {
    sentNotificationKeys.add('$limitId:$notificationType:$dateKey');
  }

  final Map<String, String> storedSettings = {};

  @override
  Future<String?> getSetting(String key) async => storedSettings[key];

  @override
  Future<void> setSetting(String key, String value) async {
    storedSettings[key] = value;
  }

  @override
  Future<List<FocusPreset>> getAllFocusPresets() async => List.unmodifiable(storedPresets);

  @override
  Future<FocusPreset> insertFocusPreset(FocusPreset preset) async {
    final created = preset.copyWith(id: storedPresets.length + 1);
    storedPresets.add(created);
    return created;
  }
}

class FakeCountingProcessManager implements ProcessManager {
  final int currentPid;
  final List<({int pid, String appName, String exePath, bool isAlive})> processes = [];
  final List<int> closedPids = [];
  final List<int> terminatedPids = [];

  FakeCountingProcessManager({this.currentPid = 9999});

  @override
  int getCurrentProcessId() => currentPid;

  @override
  Future<List<RunningProcessInfo>> findProcessesForApp({required String appName, String? exePath}) async {
    final results = <RunningProcessInfo>[];
    for (final p in processes) {
      if (!p.isAlive) continue;
      if (p.pid == currentPid || p.pid <= 4) continue;
      if (p.appName.toLowerCase() == appName.toLowerCase() ||
          (exePath != null && p.exePath.toLowerCase() == exePath.toLowerCase())) {
        results.add(RunningProcessInfo(pid: p.pid, exePath: p.exePath, exeName: p.appName));
      }
    }
    return results;
  }

  @override
  Future<Map<TargetAppCriteria, List<RunningProcessInfo>>> findProcessesForApps(List<TargetAppCriteria> targets) async {
    final result = <TargetAppCriteria, List<RunningProcessInfo>>{for (final t in targets) t: []};
    for (final t in targets) {
      result[t] = await findProcessesForApp(appName: t.appName, exePath: t.exePath);
    }
    return result;
  }

  @override
  Future<bool> closeProcessGracefully(RunningProcessInfo process) async {
    closedPids.add(process.pid);
    final idx = processes.indexWhere((p) => p.pid == process.pid);
    if (idx != -1) {
      processes[idx] = (pid: process.pid, appName: processes[idx].appName, exePath: processes[idx].exePath, isAlive: false);
    }
    return true;
  }

  @override
  Future<bool> isProcessRunning(int pid) async {
    final idx = processes.indexWhere((p) => p.pid == pid);
    return idx != -1 && processes[idx].isAlive;
  }

  @override
  Future<bool> terminateProcess(int pid) async {
    terminatedPids.add(pid);
    final idx = processes.indexWhere((p) => p.pid == pid);
    if (idx != -1) {
      processes[idx] = (pid: pid, appName: processes[idx].appName, exePath: processes[idx].exePath, isAlive: false);
      return true;
    }
    return false;
  }
}

class CountingApplicationsAnalyticsService extends ApplicationAnalyticsService {
  int loadCalls = 0;

  CountingApplicationsAnalyticsService({required super.repository});

  @override
  Future<ApplicationsAnalyticsResult> getApplicationsAnalytics({
    required DateRangeSelection selection,
    DateTime? referenceDate,
  }) async {
    loadCalls++;
    return ApplicationsAnalyticsResult(
      selection: selection,
      totalUsage: Duration(minutes: 45 * loadCalls),
      totalLimitedApps: 1,
      totalLimitReachedApps: 0,
      chartBars: const [],
      applications: [
        AppItemAnalytics(
          appName: 'VS Code',
          exePath: r'C:\Tools\Code.exe',
          totalDuration: Duration(minutes: 45 * loadCalls),
          sessionCount: loadCalls,
          proportionalUsage: 1.0,
        ),
      ],
    );
  }
}

class CountingInsightsAnalyticsService extends UsageAnalyticsService {
  int loadCalls = 0;

  CountingInsightsAnalyticsService({required super.repository});

  @override
  Future<PeriodAnalytics> getAnalytics({
    required AnalyticsPeriod period,
    DateTime? referenceDate,
  }) async {
    loadCalls++;
    final now = referenceDate ?? DateTime(2026, 10, 21);
    return PeriodAnalytics(
      period: period,
      startDate: now.subtract(const Duration(days: 7)),
      endDate: now,
      totalScreenTime: Duration(hours: loadCalls),
      dailyAverage: Duration(minutes: 10 * loadCalls),
      dailySeries: const [],
      topApplications: const [],
      mostUsedApp: null,
      mostActiveDay: null,
      activeDaysCount: 1,
      totalDaysCount: 7,
      previousPeriodScreenTime: Duration.zero,
      percentageChangeVsPrevious: null,
      differenceVsPrevious: Duration(hours: loadCalls),
      totalFocusTime: Duration(minutes: 25 * loadCalls),
    );
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  final testTheme = ThemeData.dark().copyWith(
    extensions: [AppThemeColors.dark],
  );

  group('Phase 3 Performance Optimization Tests: System Tray and Analytics Efficiency', () {
    late Phase3TestRepository repository;

    setUp(() {
      repository = Phase3TestRepository();
    });

    // 1. Hiding the window does not stop foreground usage tracking
    test('1. Hiding the window does not stop foreground usage tracking', () async {
      DateTime simulatedTime = DateTime(2026, 10, 21, 10, 0, 0);
      String? currentForeground = r'C:\Tools\Editor.exe';

      final trayService = WindowsTrayService(isPlatformSupported: false);
      await trayService.init();

      final tracker = WindowsUsageTracker(
        repository: repository,
        clock: () => simulatedTime,
        idleTimeProvider: () => Duration.zero,
        foregroundWindowProvider: () => currentForeground,
        checkpointInterval: const Duration(seconds: 15),
      );
      await tracker.init();
      tracker.start();

      // Window starts visible
      expect(trayService.isWindowHidden, isFalse);
      expect(trayService.isWindowVisible, isTrue);

      // Hide window to system tray
      await trayService.hideToTray();
      expect(trayService.isWindowHidden, isTrue);
      expect(trayService.isWindowVisible, isFalse);

      // Foreground usage tracking must continue while window is hidden in tray
      await tracker.checkForegroundWindow();
      expect(tracker.isRunning, isTrue);

      // Advance by 16 seconds (>= 15s checkpoint interval)
      simulatedTime = simulatedTime.add(const Duration(seconds: 16));
      await tracker.checkForegroundWindow();

      // Verify tracker checkpointed usage into SQLite even though window is hidden
      expect(repository.insertSessionCalls, equals(1));
      expect(tracker.todaySummary?.totalActiveTime, greaterThanOrEqualTo(const Duration(seconds: 15)));

      // Switch application while still hidden in tray
      simulatedTime = simulatedTime.add(const Duration(seconds: 2));
      currentForeground = r'C:\Apps\Browser.exe';
      await tracker.checkForegroundWindow();

      // Previous session must be flushed on app switch while hidden
      expect(repository.storedSessions.any((s) => s.appName.toLowerCase() == 'editor'), isTrue);

      // Restore window
      await trayService.restoreWindow();
      expect(trayService.isWindowHidden, isFalse);
      expect(trayService.isWindowVisible, isTrue);

      await tracker.stop();
      tracker.dispose();
      trayService.dispose();
    });

    // 2. Hiding the window does not stop daily-limit or Focus Mode enforcement
    test('2. Hiding the window does not stop daily-limit or Focus Mode enforcement', () async {
      DateTime simulatedTime = DateTime(2026, 10, 21, 14, 0, 0);
      final processManager = FakeCountingProcessManager();
      processManager.processes.add(
        (pid: 501, appName: 'Browser', exePath: r'C:\Apps\Browser.exe', isAlive: true),
      );
      processManager.processes.add(
        (pid: 502, appName: 'Distraction', exePath: r'C:\Apps\Distraction.exe', isAlive: true),
      );

      final enforcement = AppEnforcementService(
        processManager: processManager,
        gracePeriod: Duration.zero,
        clock: () => simulatedTime,
      );

      final dailyLimit = AppLimit(
        id: 1,
        appName: 'Browser',
        exePath: r'C:\Apps\Browser.exe',
        limitDuration: const Duration(minutes: 5),
        isEnabled: true,
        isEnforced: true,
        createdAt: simulatedTime,
        updatedAt: simulatedTime,
      );
      repository.storedLimits.add(dailyLimit);

      final trayService = WindowsTrayService(isPlatformSupported: false);
      await trayService.init();

      final tracker = WindowsUsageTracker(
        repository: repository,
        clock: () => simulatedTime,
        idleTimeProvider: () => Duration.zero,
        foregroundWindowProvider: () => r'C:\Apps\Browser.exe',
      );
      await tracker.init();
      tracker.start();
      // Establish initial active foreground session at 14:00:00
      await tracker.checkForegroundWindow();

      final limitsService = LimitsService(
        repository: repository,
        tracker: tracker,
        enforcementService: enforcement,
        clock: () => simulatedTime,
      );
      await limitsService.init();

      final focusService = FocusService(
        repository: repository,
        enforcementService: enforcement,
        clock: () => simulatedTime,
      );
      await focusService.init();

      // Hide window to system tray
      await trayService.hideToTray();
      expect(trayService.isWindowHidden, isTrue);

      // 1. Advance time past daily limit (5 mins) while hidden
      simulatedTime = simulatedTime.add(const Duration(minutes: 5, seconds: 5));
      await tracker.checkForegroundWindow();
      // Allow async limit evaluation and enforcement to complete
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Daily limit enforcement MUST trigger while window is hidden
      expect(enforcement.isDailyLimitRestricted('Browser'), isTrue);
      expect(processManager.closedPids, contains(501));

      // 2. Start Focus Mode session with blocked app while hidden
      final preset = FocusPreset(
        name: 'Custom Focus Preset',
        focusDuration: const Duration(minutes: 25),
        shortBreakDuration: const Duration(minutes: 5),
        longBreakDuration: const Duration(minutes: 15),
        blockedApps: const [FocusPresetBlockedApp(appName: 'Distraction', exePath: r'C:\Apps\Distraction.exe')],
      );
      await focusService.createPreset(preset);
      await focusService.selectPreset(focusService.presets.last);
      await focusService.start();

      expect(focusService.isRunning, isTrue);
      // Focus enforcement MUST trigger and close distraction process while hidden
      expect(enforcement.isFocusRestricted('Distraction'), isTrue);
      expect(processManager.closedPids, contains(502));

      await focusService.stop();
      focusService.dispose();
      limitsService.dispose();
      await tracker.stop();
      tracker.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      enforcement.dispose();
      trayService.dispose();
    });

    // 3. Focus timers and break transitions continue while hidden
    test('3. Focus timers and break transitions continue while hidden', () async {
      DateTime simulatedTime = DateTime(2026, 10, 21, 9, 0, 0);

      final trayService = WindowsTrayService(isPlatformSupported: false);
      await trayService.init();

      final focusService = FocusService(
        repository: repository,
        clock: () => simulatedTime,
      );
      await focusService.init();

      final preset = FocusPreset(
        name: 'Auto Break Preset',
        focusDuration: const Duration(minutes: 25),
        shortBreakDuration: const Duration(minutes: 5),
        longBreakDuration: const Duration(minutes: 15),
        cyclesBeforeLongBreak: 4,
        autoStartBreaks: true,
        autoStartFocus: true,
      );
      await focusService.createPreset(preset);
      await focusService.selectPreset(focusService.presets.last);

      // Hide window to system tray
      await trayService.hideToTray();
      expect(trayService.isWindowHidden, isTrue);

      // Start focus session
      await focusService.start();
      expect(focusService.isRunning, isTrue);
      expect(focusService.sessionType, equals(FocusSessionType.focus));

      // Simulate 25 minutes + 1 second passing while hidden in tray
      simulatedTime = simulatedTime.add(const Duration(minutes: 25, seconds: 1));
      focusService.tick();
      await focusService.pendingDbOp;

      // Focus mode MUST naturally complete and auto-transition to break while hidden
      expect(focusService.sessionType, equals(FocusSessionType.breakSession));
      expect(focusService.isRunning, isTrue);
      expect(focusService.targetDuration, equals(const Duration(minutes: 5)));
      expect(repository.storedFocusSessions.length, equals(1));
      expect(repository.storedFocusSessions.first.completedNaturally, isTrue);

      // Simulate 5 minutes of break passing while hidden in tray
      simulatedTime = simulatedTime.add(const Duration(minutes: 5, seconds: 1));
      focusService.tick();
      await focusService.pendingDbOp;

      // Break MUST naturally complete and advance to cycle 2 Focus while hidden
      expect(focusService.sessionType, equals(FocusSessionType.focus));
      expect(focusService.currentCycle, equals(2));
      expect(focusService.isRunning, isTrue);
      expect(repository.storedFocusSessions.length, equals(2));

      await focusService.stop();
      focusService.dispose();
      trayService.dispose();
    });

    // 4. Restoring the window refreshes the displayed data correctly
    testWidgets('4. Restoring the window refreshes displayed data correctly on all screens', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final visibilityNotifier = ValueNotifier<bool>(true);
      final countingAnalytics = CountingApplicationsAnalyticsService(repository: repository);
      final countingInsights = CountingInsightsAnalyticsService(repository: repository);

      final tracker = TestableWindowsUsageTracker(
        repository: repository,
        idleTimeProvider: () => Duration.zero,
        foregroundWindowProvider: () => r'C:\Tools\Code.exe',
      );
      final limitsService = LimitsService(repository: repository, tracker: tracker);
      final focusService = FocusService(repository: repository);
      await focusService.init();

      // Test 4a: OverviewScreen skips rebuild while hidden, refreshes immediately upon restore
      await tester.pumpWidget(
        TrackerProvider(
          tracker: tracker,
          child: FocusProvider(
            focusService: focusService,
            child: LimitsProvider(
              limitsService: limitsService,
              child: MaterialApp(
                theme: testTheme,
                home: Scaffold(
                  body: OverviewScreen(windowVisibility: visibilityNotifier),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial active time is 0h 0m
      expect(find.text('0h 0m'), findsWidgets);
      expect(find.text('2h 15m'), findsNothing);

      // Hide window to system tray
      visibilityNotifier.value = false;
      await tester.pump();

      // Update tracker live summary while hidden
      final codeUsage = AppUsageData(
        appName: 'Code',
        duration: const Duration(hours: 2, minutes: 15),
        proportionalUsage: 1.0,
      );
      tracker.setTodaySummaryForTesting(DailyUsageSummary(
        date: DateTime.now(),
        totalActiveTime: const Duration(hours: 2, minutes: 15),
        focusTime: const Duration(minutes: 30),
        breaksTaken: 2,
        goalTime: const Duration(hours: 8),
        mostUsedApps: [codeUsage],
        allApps: [codeUsage],
        hourlyActivity: const [],
      ));

      // Tracker notifies while hidden
      tracker.notifyListeners();
      await tester.pump();

      // Screen must NOT have updated while hidden
      expect(find.text('2h 15m'), findsNothing);

      // Restore window
      visibilityNotifier.value = true;
      await tester.pump();

      // Screen MUST immediately reflect the new 2h 15m usage upon restoration!
      expect(find.text('2h 15m'), findsWidgets);

      // Test 4b: ApplicationsScreen skips background loads while hidden, refreshes on restore
      await tester.pumpWidget(
        TrackerProvider(
          tracker: tracker,
          child: LimitsProvider(
            limitsService: limitsService,
            child: MaterialApp(
              theme: testTheme,
              home: Scaffold(
                body: ApplicationsScreen(
                  analyticsService: countingAnalytics,
                  windowVisibility: visibilityNotifier,
                  debounceDuration: const Duration(milliseconds: 20),
                  backgroundThrottleDuration: Duration.zero,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final loadsWhenShown = countingAnalytics.loadCalls;
      expect(loadsWhenShown, equals(1));

      // Hide window to tray
      visibilityNotifier.value = false;
      await tester.pump();

      // Multiple tracker notifications while hidden
      tracker.notifyListeners();
      await tester.pump(const Duration(milliseconds: 30));
      tracker.notifyListeners();
      await tester.pump(const Duration(milliseconds: 30));

      // Must NOT have loaded analytics while hidden
      expect(countingAnalytics.loadCalls, equals(loadsWhenShown));

      // Restore window
      visibilityNotifier.value = true;
      await tester.pump();

      // Restoring MUST immediately refresh analytics
      expect(countingAnalytics.loadCalls, equals(loadsWhenShown + 1));

      // Test 4c: InsightsScreen skips background reloads while hidden, refreshes on restore
      await tester.pumpWidget(
        TrackerProvider(
          tracker: tracker,
          child: MaterialApp(
            theme: testTheme,
            home: Scaffold(
              body: InsightsScreen(
                analyticsService: countingInsights,
                windowVisibility: visibilityNotifier,
                trackerUpdateThrottle: Duration.zero,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final insightsLoads = countingInsights.loadCalls;
      expect(insightsLoads, equals(1));

      // Hide window
      visibilityNotifier.value = false;
      await tester.pump();

      // Tracker notifies while hidden
      tracker.notifyListeners();
      await tester.pump(const Duration(milliseconds: 20));

      // Must NOT have reloaded insights while hidden
      expect(countingInsights.loadCalls, equals(insightsLoads));

      // Restore window
      visibilityNotifier.value = true;
      await tester.pump();

      // Restoring MUST refresh insights immediately
      expect(countingInsights.loadCalls, equals(insightsLoads + 1));

      focusService.dispose();
      tracker.dispose();
      limitsService.dispose();
      visibilityNotifier.dispose();
    });

    // 5. Repeated hide/restore cycles do not create duplicate listeners or timers
    testWidgets('5. Repeated hide/restore cycles do not create duplicate listeners or timers', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final visibilityNotifier = ValueNotifier<bool>(true);
      final countingAnalytics = CountingApplicationsAnalyticsService(repository: repository);
      final tracker = WindowsUsageTracker(
        repository: repository,
        idleTimeProvider: () => Duration.zero,
        foregroundWindowProvider: () => r'C:\Tools\Code.exe',
      );
      final limitsService = LimitsService(repository: repository, tracker: tracker);

      await tester.pumpWidget(
        TrackerProvider(
          tracker: tracker,
          child: LimitsProvider(
            limitsService: limitsService,
            child: MaterialApp(
              theme: testTheme,
              home: Scaffold(
                body: ApplicationsScreen(
                  analyticsService: countingAnalytics,
                  windowVisibility: visibilityNotifier,
                  debounceDuration: const Duration(milliseconds: 30),
                  backgroundThrottleDuration: Duration.zero,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(countingAnalytics.loadCalls, equals(1));

      // Perform 5 repeated hide and restore cycles
      for (int i = 0; i < 5; i++) {
        visibilityNotifier.value = false;
        await tester.pump();
        visibilityNotifier.value = true;
        await tester.pump();
      }

      final loadsAfterCycles = countingAnalytics.loadCalls;

      // Trigger a single tracker notification
      tracker.notifyListeners();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // Exactly ONE load should fire, proving no duplicate listeners were registered during cycles
      expect(
        countingAnalytics.loadCalls,
        equals(loadsAfterCycles + 1),
        reason: 'Repeated hide/restore cycles must never duplicate listeners',
      );

      tracker.dispose();
      limitsService.dispose();
      visibilityNotifier.dispose();
    });

    // 6. Applications analytics still deduplicates notification cascades
    testWidgets('6. Applications analytics still deduplicates notification cascades', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final visibilityNotifier = ValueNotifier<bool>(true);
      final countingAnalytics = CountingApplicationsAnalyticsService(repository: repository);
      final tracker = WindowsUsageTracker(
        repository: repository,
        idleTimeProvider: () => Duration.zero,
        foregroundWindowProvider: () => r'C:\Tools\Code.exe',
      );
      final limitsService = LimitsService(repository: repository, tracker: tracker);

      await tester.pumpWidget(
        TrackerProvider(
          tracker: tracker,
          child: LimitsProvider(
            limitsService: limitsService,
            child: MaterialApp(
              theme: testTheme,
              home: Scaffold(
                body: ApplicationsScreen(
                  analyticsService: countingAnalytics,
                  windowVisibility: visibilityNotifier,
                  debounceDuration: const Duration(milliseconds: 50),
                  backgroundThrottleDuration: Duration.zero,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final initialLoads = countingAnalytics.loadCalls;
      expect(initialLoads, equals(1));

      // Trigger cascade: tracker notifies, followed immediately by limitsService
      tracker.notifyListeners();
      limitsService.notifyListeners();

      // Debounce period passes
      await tester.pump(const Duration(milliseconds: 70));
      await tester.pumpAndSettle();

      // Coalesced into exactly one additional load
      expect(
        countingAnalytics.loadCalls,
        equals(initialLoads + 1),
        reason: 'Dual notification cascade must coalesce into a single background reload',
      );

      tracker.dispose();
      limitsService.dispose();
      visibilityNotifier.dispose();
    });

    // 7. User-initiated range and filter changes update promptly
    testWidgets('7. User-initiated range and filter changes update promptly', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final countingAnalytics = CountingApplicationsAnalyticsService(repository: repository);
      final tracker = WindowsUsageTracker(
        repository: repository,
        idleTimeProvider: () => Duration.zero,
        foregroundWindowProvider: () => r'C:\Tools\Code.exe',
      );
      final limitsService = LimitsService(repository: repository, tracker: tracker);

      await tester.pumpWidget(
        TrackerProvider(
          tracker: tracker,
          child: LimitsProvider(
            limitsService: limitsService,
            child: MaterialApp(
              theme: testTheme,
              home: Scaffold(
                body: ApplicationsScreen(
                  analyticsService: countingAnalytics,
                  referenceDate: DateTime(2026, 10, 21),
                  backgroundThrottleDuration: const Duration(seconds: 30), // Long throttle for background
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(countingAnalytics.loadCalls, equals(1));

      // User changes range to 'Past 7 Days'
      await tester.tap(find.text('Past 7 Days'));
      await tester.pumpAndSettle();

      // Must load immediately without being throttled by background throttle!
      expect(countingAnalytics.loadCalls, equals(2));

      // User changes range to 'Past 30 Days'
      await tester.tap(find.text('Past 30 Days'));
      await tester.pumpAndSettle();

      expect(countingAnalytics.loadCalls, equals(3));

      // User taps refresh button
      await tester.tap(find.byTooltip('Refresh Analytics'));
      await tester.pumpAndSettle();

      expect(countingAnalytics.loadCalls, equals(4));

      // User interacts with filter pills (in-memory)
      await tester.tap(find.byKey(const ValueKey('filter_pill_limited')));
      await tester.pumpAndSettle();

      // Filtered immediately
      expect(find.byKey(const ValueKey('filter_pill_limited')), findsOneWidget);

      tracker.dispose();
      limitsService.dispose();
    });

    // 8. Disposed screens do not continue receiving updates
    testWidgets('8. Disposed screens do not continue receiving updates', (tester) async {
      final visibilityNotifier = ValueNotifier<bool>(true);
      final countingAnalytics = CountingApplicationsAnalyticsService(repository: repository);
      final tracker = WindowsUsageTracker(
        repository: repository,
        idleTimeProvider: () => Duration.zero,
        foregroundWindowProvider: () => r'C:\Tools\Code.exe',
      );
      final limitsService = LimitsService(repository: repository, tracker: tracker);

      bool showScreen = true;

      await tester.pumpWidget(
        TrackerProvider(
          tracker: tracker,
          child: LimitsProvider(
            limitsService: limitsService,
            child: StatefulBuilder(
              builder: (context, setState) {
                return MaterialApp(
                  theme: testTheme,
                  home: Scaffold(
                    body: showScreen
                        ? ApplicationsScreen(
                            analyticsService: countingAnalytics,
                            windowVisibility: visibilityNotifier,
                            debounceDuration: const Duration(milliseconds: 20),
                            backgroundThrottleDuration: Duration.zero,
                          )
                        : const SizedBox(),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(countingAnalytics.loadCalls, equals(1));

      // Dispose the screen by removing it from the tree
      showScreen = false;
      await tester.pumpWidget(
        TrackerProvider(
          tracker: tracker,
          child: LimitsProvider(
            limitsService: limitsService,
            child: MaterialApp(
              theme: testTheme,
              home: const Scaffold(body: SizedBox()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final loadsAfterDispose = countingAnalytics.loadCalls;

      // Notify tracker, limits, and visibility
      tracker.notifyListeners();
      limitsService.notifyListeners();
      visibilityNotifier.value = false;
      visibilityNotifier.value = true;
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // No new loads must occur
      expect(countingAnalytics.loadCalls, equals(loadsAfterDispose));

      tracker.dispose();
      limitsService.dispose();
      visibilityNotifier.dispose();
    });
  });
}
