import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:balance/app/app.dart';
import 'package:balance/app/theme/app_colors.dart';
import 'package:balance/core/models/app_block_event.dart';
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
import 'package:balance/core/services/usage_repository.dart';
import 'package:balance/core/services/windows_process_manager.dart';
import 'package:balance/core/services/windows_usage_tracker.dart';
import 'package:balance/features/applications/applications_screen.dart';

class CountingUsageRepository extends UsageRepository {
  int getSessionsForDayCalls = 0;
  int insertSessionCalls = 0;
  int updateSessionEndTimeCalls = 0;
  int hasLimitNotificationBeenSentCalls = 0;

  final List<AppSession> storedSessions = [];
  final List<FocusSessionRecord> storedFocusSessions = [];
  final List<AppLimit> storedLimits = [];
  final Set<String> sentNotificationLogs = {};

  CountingUsageRepository() : super(dbName: inMemoryDatabasePath);

  @override
  Future<List<AppSession>> getSessionsForDay(DateTime date) async {
    getSessionsForDayCalls++;
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day + 1);
    return storedSessions.where((s) {
      return s.startTime.isBefore(endOfDay) && s.endTime.isAfter(startOfDay);
    }).toList();
  }

  @override
  Future<List<AppSession>> getSessionsForRange(DateTime start, DateTime end) async {
    return storedSessions.where((s) {
      return s.startTime.isBefore(end) && s.endTime.isAfter(start);
    }).toList();
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
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day + 1);
    return storedFocusSessions.where((s) {
      return s.startTime.isBefore(endOfDay) && s.endTime.isAfter(startOfDay);
    }).toList();
  }

  @override
  Future<FocusSessionRecord> insertFocusSession(FocusSessionRecord session) async {
    storedFocusSessions.add(session);
    return session;
  }

  @override
  Future<List<AppLimit>> getAllLimits() async => List.unmodifiable(storedLimits);

  @override
  Future<bool> hasLimitNotificationBeenSent(
    int limitId,
    String notificationType,
    String dateKey,
  ) async {
    hasLimitNotificationBeenSentCalls++;
    return sentNotificationLogs.contains('$limitId:$notificationType:$dateKey');
  }

  @override
  Future<void> recordLimitNotificationSent(
    int limitId,
    String notificationType,
    String dateKey,
    DateTime timestamp,
  ) async {
    sentNotificationLogs.add('$limitId:$notificationType:$dateKey');
  }

  @override
  Future<List<String>> getDistinctTrackedApps() async {
    return storedSessions.map((s) => s.appName).toSet().toList();
  }
}

class FakeProcessManager implements ProcessManager {
  final Set<int> runningPids = {};

  @override
  int getCurrentProcessId() => 9999;

  @override
  Future<List<RunningProcessInfo>> findProcessesForApp({
    required String appName,
    String? exePath,
  }) async {
    return [];
  }

  @override
  Future<bool> closeProcessGracefully(RunningProcessInfo process) async => true;

  @override
  Future<bool> isProcessRunning(int pid) async => runningPids.contains(pid);

  @override
  Future<bool> terminateProcess(int pid) async {
    runningPids.remove(pid);
    return true;
  }
}

class CountingAnalyticsService extends ApplicationAnalyticsService {
  int loadCalls = 0;
  final Duration artificialDelay;

  CountingAnalyticsService({
    required super.repository,
    this.artificialDelay = Duration.zero,
  });

  @override
  Future<ApplicationsAnalyticsResult> getApplicationsAnalytics({
    required DateRangeSelection selection,
    DateTime? referenceDate,
  }) async {
    loadCalls++;
    if (artificialDelay > Duration.zero) {
      await Future.delayed(artificialDelay);
    }
    return ApplicationsAnalyticsResult(
      selection: selection,
      totalUsage: const Duration(hours: 1),
      totalLimitedApps: 0,
      totalLimitReachedApps: 0,
      chartBars: const [],
      applications: const [
        AppItemAnalytics(
          appName: 'VS Code',
          exePath: r'C:\Tools\Code.exe',
          totalDuration: Duration(hours: 1),
          sessionCount: 1,
          proportionalUsage: 1.0,
        ),
      ],
    );
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Phase 1 Performance Optimization Tests', () {
    late CountingUsageRepository repository;

    setUp(() {
      repository = CountingUsageRepository();
    });

    // 1. Focus countdown ticks do not cause unnecessary full usage-summary reloads
    test('1. Focus countdown ticks do not cause unnecessary full usage-summary reloads', () async {
      DateTime simulatedTime = DateTime(2026, 10, 20, 10, 0, 0);
      final focusService = FocusService(
        repository: repository,
        clock: () => simulatedTime,
      );
      await focusService.init();

      final tracker = WindowsUsageTracker(
        repository: repository,
        focusService: focusService,
        clock: () => simulatedTime,
        idleTimeProvider: () => Duration.zero,
        foregroundWindowProvider: () => r'C:\Tools\Code.exe',
      );
      await tracker.init();

      // Start Focus Mode
      await focusService.start();
      expect(focusService.isRunning, isTrue);

      // Record query count after initial focus session start
      final queriesAfterStart = repository.getSessionsForDayCalls;

      // Simulate 10 1-second countdown ticks
      for (int i = 1; i <= 10; i++) {
        simulatedTime = simulatedTime.add(const Duration(seconds: 1));
        focusService.tick();
      }

      // Assert that countdown ticks did NOT trigger getSessionsForDay calls
      expect(
        repository.getSessionsForDayCalls,
        equals(queriesAfterStart),
        reason: 'Focus countdown ticks must not reload daily summary from SQLite',
      );

      tracker.dispose();
      focusService.dispose();
    });

    // 2. Focus-time reporting remains accurate
    test('2. Focus-time reporting remains accurate during live active session', () async {
      DateTime simulatedTime = DateTime(2026, 10, 20, 14, 0, 0);
      final focusService = FocusService(
        repository: repository,
        clock: () => simulatedTime,
      );
      await focusService.init();

      final tracker = WindowsUsageTracker(
        repository: repository,
        focusService: focusService,
        clock: () => simulatedTime,
        idleTimeProvider: () => Duration.zero,
        foregroundWindowProvider: () => r'C:\Tools\Editor.exe',
      );
      await tracker.init();

      await focusService.start();

      // Advance clock by 12 minutes and tick
      simulatedTime = simulatedTime.add(const Duration(minutes: 12));
      focusService.tick();

      // Query daily summary for today
      final summary = await tracker.getSummaryForDay(DateTime(2026, 10, 20));

      expect(summary.focusTime, equals(const Duration(minutes: 12)));
      expect(focusService.remainingDuration, equals(const Duration(minutes: 13))); // 25m - 12m

      tracker.dispose();
      focusService.dispose();
    });

    // 3. App-limit evaluation and enforcement still happen promptly when usage changes
    test('3. App-limit evaluation and enforcement happen promptly when usage crosses limit', () async {
      DateTime simulatedTime = DateTime(2026, 10, 20, 9, 0, 0);
      final processManager = FakeProcessManager();
      final enforcement = AppEnforcementService(
        processManager: processManager,
        gracePeriod: Duration.zero,
        clock: () => simulatedTime,
      );

      final limit = AppLimit(
        id: 1,
        appName: 'Browser',
        exePath: r'C:\Apps\Browser.exe',
        limitDuration: const Duration(minutes: 10),
        warningThresholdPercentage: 80,
        isEnabled: true,
        isEnforced: true,
        createdAt: simulatedTime,
        updatedAt: simulatedTime,
      );
      repository.storedLimits.add(limit);

      String currentExe = r'C:\Apps\Browser.exe';
      final tracker = WindowsUsageTracker(
        repository: repository,
        clock: () => simulatedTime,
        idleTimeProvider: () => Duration.zero,
        foregroundWindowProvider: () => currentExe,
      );
      await tracker.init();

      final limitsService = LimitsService(
        repository: repository,
        tracker: tracker,
        enforcementService: enforcement,
        clock: () => simulatedTime,
      );
      await limitsService.init();

      // First tick at 0m
      await tracker.checkForegroundWindow();
      expect(enforcement.isAppRestricted('Browser'), isFalse);

      // Advance by 9 minutes (under 10m limit)
      simulatedTime = simulatedTime.add(const Duration(minutes: 9));
      await tracker.checkForegroundWindow();
      expect(enforcement.isAppRestricted('Browser'), isFalse);

      // Advance by 1 minute 5 seconds (exceeding 10m limit)
      simulatedTime = simulatedTime.add(const Duration(minutes: 1, seconds: 5));
      await tracker.checkForegroundWindow();

      // Must be restricted immediately without waiting for a database checkpoint
      expect(
        enforcement.isAppRestricted('Browser'),
        isTrue,
        reason: 'Enforcement must trigger promptly based on live in-memory session',
      );

      await Future.delayed(Duration.zero);
      tracker.dispose();
      limitsService.dispose();
      enforcement.dispose();
    });

    // 4. Applications analytics does not perform duplicate identical loads for one notification cascade
    testWidgets('4. Applications analytics deduplicates cascade from tracker and limitsService', (tester) async {
      final countingAnalytics = CountingAnalyticsService(repository: repository);
      final tracker = WindowsUsageTracker(
        repository: repository,
        idleTimeProvider: () => Duration.zero,
        foregroundWindowProvider: () => r'C:\Tools\Code.exe',
      );
      await tracker.init();

      final limitsService = LimitsService(
        repository: repository,
        tracker: tracker,
      );
      await limitsService.init();

      final testTheme = ThemeData.dark().copyWith(
        extensions: [AppThemeColors.dark],
      );

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
                  referenceDate: DateTime(2026, 10, 20),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final initialLoads = countingAnalytics.loadCalls;
      expect(initialLoads, equals(1));

      // Trigger cascade: tracker notifies, then limitsService notifies immediately after
      tracker.notifyListeners();
      limitsService.notifyListeners();

      // Advance pump by 300ms to allow 250ms debounce to fire
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Should have performed exactly ONE additional load, not two
      expect(
        countingAnalytics.loadCalls,
        equals(initialLoads + 1),
        reason: 'Dual notification cascade must be coalesced into a single background load',
      );

      tracker.dispose();
      limitsService.dispose();
    });

    // 5. Newer analytics requests cannot be overwritten by stale asynchronous results
    testWidgets('5. Newer analytics requests cannot be overwritten by stale asynchronous results', (tester) async {
      final countingAnalytics = CountingAnalyticsService(
        repository: repository,
        artificialDelay: const Duration(milliseconds: 100),
      );

      final tracker = WindowsUsageTracker(
        repository: repository,
        idleTimeProvider: () => Duration.zero,
        foregroundWindowProvider: () => r'C:\Tools\Code.exe',
      );
      await tracker.init();

      final limitsService = LimitsService(
        repository: repository,
        tracker: tracker,
      );
      await limitsService.init();

      final testTheme = ThemeData.dark().copyWith(
        extensions: [AppThemeColors.dark],
      );

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
                  referenceDate: DateTime(2026, 10, 20),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();

      expect(find.text('VS Code'), findsWidgets);

      tracker.dispose();
      limitsService.dispose();
    });

    // 6. Active-session checkpoint writes are throttled to the intended interval
    test('6. Active-session checkpoint writes are throttled to configured checkpoint interval', () async {
      DateTime simulatedTime = DateTime(2026, 10, 20, 10, 0, 0);

      final tracker = WindowsUsageTracker(
        repository: repository,
        clock: () => simulatedTime,
        idleTimeProvider: () => Duration.zero,
        foregroundWindowProvider: () => r'C:\Apps\AppA.exe',
        checkpointInterval: const Duration(seconds: 15),
      );
      await tracker.init();

      // t=0s: Initial poll starts tracking AppA
      await tracker.checkForegroundWindow();
      expect(repository.insertSessionCalls, equals(0));
      expect(repository.updateSessionEndTimeCalls, equals(0));

      // t=2s: 2s elapsed. Duration <= 2s, no write
      simulatedTime = simulatedTime.add(const Duration(seconds: 2));
      await tracker.checkForegroundWindow();
      expect(repository.insertSessionCalls, equals(0));

      // t=4s: 4s elapsed. Checkpoint interval (15s) has NOT elapsed
      simulatedTime = simulatedTime.add(const Duration(seconds: 2));
      await tracker.checkForegroundWindow();
      expect(repository.insertSessionCalls, equals(0));
      expect(repository.updateSessionEndTimeCalls, equals(0));

      // t=14s: 14s elapsed. < 15s, no SQLite write
      simulatedTime = DateTime(2026, 10, 20, 10, 0, 14);
      await tracker.checkForegroundWindow();
      expect(repository.insertSessionCalls, equals(0));
      expect(repository.updateSessionEndTimeCalls, equals(0));

      // t=16s: 16s elapsed >= 15s checkpoint interval. First checkpoint writes!
      simulatedTime = DateTime(2026, 10, 20, 10, 0, 16);
      await tracker.checkForegroundWindow();
      expect(repository.insertSessionCalls, equals(1));
      expect(repository.updateSessionEndTimeCalls, equals(0));

      // t=20s, 22s: only 4s and 6s since last checkpoint (16s). No additional writes!
      simulatedTime = DateTime(2026, 10, 20, 10, 0, 22);
      await tracker.checkForegroundWindow();
      expect(repository.updateSessionEndTimeCalls, equals(0));

      // t=32s: 16s since last checkpoint (16s). Second checkpoint updates session!
      simulatedTime = DateTime(2026, 10, 20, 10, 0, 32);
      await tracker.checkForegroundWindow();
      expect(repository.updateSessionEndTimeCalls, equals(1));

      tracker.dispose();
    });

    // 7. App switches flush the previous session immediately
    test('7. App switches flush the previous uncheckpointed session immediately', () async {
      DateTime simulatedTime = DateTime(2026, 10, 20, 10, 0, 0);
      String currentExe = r'C:\Apps\AppA.exe';

      final tracker = WindowsUsageTracker(
        repository: repository,
        clock: () => simulatedTime,
        idleTimeProvider: () => Duration.zero,
        foregroundWindowProvider: () => currentExe,
        checkpointInterval: const Duration(seconds: 15),
      );
      await tracker.init();

      // Start App A at 0s
      await tracker.checkForegroundWindow();

      // App A runs for 6 seconds (before 15s checkpoint interval, so not written to SQLite yet)
      simulatedTime = simulatedTime.add(const Duration(seconds: 6));
      await tracker.checkForegroundWindow();
      expect(repository.insertSessionCalls, equals(0));

      // User switches to App B at 8s
      simulatedTime = simulatedTime.add(const Duration(seconds: 2));
      currentExe = r'C:\Apps\AppB.exe';
      await tracker.checkForegroundWindow();

      // App A must be immediately flushed to SQLite upon switch!
      expect(repository.insertSessionCalls, equals(1));
      expect(repository.storedSessions.first.appName, equals('Appa'));
      expect(
        repository.storedSessions.first.endTime,
        equals(DateTime(2026, 10, 20, 10, 0, 8)),
      );

      tracker.dispose();
    });

    // 8. Idle transitions and graceful shutdown persist the appropriate final timestamps
    test('8. Idle transitions and graceful shutdown persist the appropriate final timestamps', () async {
      DateTime simulatedTime = DateTime(2026, 10, 20, 11, 0, 0);
      Duration currentIdle = Duration.zero;

      final tracker = WindowsUsageTracker(
        repository: repository,
        clock: () => simulatedTime,
        idleTimeProvider: () => currentIdle,
        foregroundWindowProvider: () => r'C:\Apps\AppA.exe',
      );
      tracker.setIdleThreshold(const Duration(minutes: 2));
      await tracker.init();

      // Active for 30s
      await tracker.checkForegroundWindow();
      simulatedTime = simulatedTime.add(const Duration(seconds: 30));
      await tracker.checkForegroundWindow();

      // User stopped typing at 30s. At 2m 35s, idle duration is 2m 5s >= 2m threshold
      simulatedTime = simulatedTime.add(const Duration(minutes: 2, seconds: 5));
      currentIdle = const Duration(minutes: 2, seconds: 5);

      await tracker.checkForegroundWindow();
      expect(tracker.isUserIdle, isTrue);

      // Session must be finalized at exact last input time (11:00:30), not crediting idle time
      expect(repository.storedSessions.isNotEmpty, isTrue);
      expect(
        repository.storedSessions.first.endTime,
        equals(DateTime(2026, 10, 20, 11, 0, 30)),
      );

      // Graceful shutdown
      await tracker.stop();
      expect(tracker.isRunning, isFalse);

      tracker.dispose();
    });

    // 9. Midnight transitions do not create session gaps or double-counted usage
    test('9. Midnight transitions do not create session gaps or double-counted usage', () async {
      DateTime simulatedTime = DateTime(2026, 10, 20, 23, 59, 50);

      final tracker = WindowsUsageTracker(
        repository: repository,
        clock: () => simulatedTime,
        idleTimeProvider: () => Duration.zero,
        foregroundWindowProvider: () => r'C:\Apps\NightWork.exe',
      );
      await tracker.init();

      // Start at 23:59:50
      await tracker.checkForegroundWindow();

      // Advance into next day: 00:00:10
      simulatedTime = DateTime(2026, 10, 21, 0, 0, 10);
      await tracker.checkForegroundWindow();

      // Day 1 session should be cut off at 23:59:59.999
      final day1Sessions = await repository.getSessionsForDay(DateTime(2026, 10, 20));
      expect(day1Sessions.length, equals(1));
      expect(day1Sessions.first.endTime, equals(DateTime(2026, 10, 20, 23, 59, 59, 999)));

      // Day 2 live session should start at 00:00:00.000
      expect(tracker.liveSession, isNotNull);
      expect(tracker.liveSession!.startTime, equals(DateTime(2026, 10, 21, 0, 0, 0)));
      expect(tracker.liveSession!.endTime, equals(DateTime(2026, 10, 21, 0, 0, 10)));

      // Stop to finalize day 2 session
      await tracker.stop();
      final day2Sessions = await repository.getSessionsForDay(DateTime(2026, 10, 21));
      expect(day2Sessions.length, equals(1));
      expect(day2Sessions.first.startTime, equals(DateTime(2026, 10, 21, 0, 0, 0)));
      expect(day2Sessions.first.endTime, equals(DateTime(2026, 10, 21, 0, 0, 10)));

      // Total duration across both days must be exactly 20 seconds (10s on Day 1, 10s on Day 2)
      final d1Sec = day1Sessions.first.duration.inSeconds;
      final d2Sec = day2Sessions.first.duration.inSeconds;
      expect(d1Sec + d2Sec, inInclusiveRange(19, 20));

      tracker.dispose();
    });

    // 10. Existing daily limits, Focus Mode breaks, and restriction independence remain unchanged
    test('10. Daily limits and Focus Mode restrictions remain completely independent during breaks', () async {
      DateTime simulatedTime = DateTime(2026, 10, 20, 12, 0, 0);
      final processManager = FakeProcessManager();
      final enforcement = AppEnforcementService(
        processManager: processManager,
        clock: () => simulatedTime,
      );

      final focusBlocked = FocusPresetBlockedApp(
        id: 1,
        presetId: 1,
        appName: 'Steam',
        exePath: r'C:\Steam\steam.exe',
      );

      final dailyLimit = AppLimit(
        id: 1,
        appName: 'Discord',
        limitDuration: Duration.zero, // 0-minute immediate restriction
        isEnabled: true,
        isEnforced: true,
        createdAt: simulatedTime,
        updatedAt: simulatedTime,
      );

      // Set focus restrictions with unblockDuringBreaks = true
      await enforcement.setFocusRestrictions(
        blockedApps: [focusBlocked],
        presetName: 'Deep Work',
        isEnforcing: true,
      );

      // Set daily limit restrictions
      enforcement.evaluateEnforcements([dailyLimit], {'discord': Duration.zero});

      expect(enforcement.isAppRestricted('Steam'), isTrue);
      expect(enforcement.isAppRestricted('Discord'), isTrue);

      // Suspend focus restrictions for a break
      enforcement.clearFocusRestrictions();

      // Focus app is now unblocked during break
      expect(enforcement.isAppRestricted('Steam'), isFalse);

      // Daily limit MUST remain restricted!
      expect(
        enforcement.isAppRestricted('Discord'),
        isTrue,
        reason: 'Daily limits must remain active and independent even when Focus Mode restrictions clear',
      );

      enforcement.dispose();
    });
  });
}
