import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

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
import 'package:balance/core/services/usage_repository.dart';
import 'package:balance/core/services/windows_process_manager.dart';
import 'package:balance/core/services/windows_tray_service.dart';
import 'package:balance/core/services/windows_usage_tracker.dart';
import 'package:balance/features/applications/applications_screen.dart';
import 'package:balance/features/overview/overview_screen.dart';

class Phase4CountingAnalyticsService extends ApplicationAnalyticsService {
  int loadCalls = 0;
  DateRangeSelection? lastSelection;

  Phase4CountingAnalyticsService({required super.repository});

  @override
  Future<ApplicationsAnalyticsResult> getApplicationsAnalytics({
    required DateRangeSelection selection,
    DateTime? referenceDate,
  }) async {
    loadCalls++;
    lastSelection = selection;
    return ApplicationsAnalyticsResult(
      selection: selection,
      totalScreenTime: Duration(hours: loadCalls),
      activeAppsCount: 2,
      chartBars: const [],
      applications: [
        AppItemAnalytics(
          appName: 'Code',
          totalDuration: const Duration(hours: 1),
          sessionCount: 2,
          proportionalUsage: 0.6,
        ),
      ],
    );
  }
}

class FakeReliabilityProcessManager implements ProcessManager {
  final int currentPid;
  final List<({int pid, String appName, String exePath, bool isAlive})> processes = [];
  final List<int> closedPids = [];

  FakeReliabilityProcessManager({this.currentPid = 9999});

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
  Future<bool> terminateProcess(int pid) async {
    closedPids.add(pid);
    final idx = processes.indexWhere((p) => p.pid == pid);
    if (idx != -1) {
      processes[idx] = (pid: pid, appName: processes[idx].appName, exePath: processes[idx].exePath, isAlive: false);
    }
    return true;
  }

  @override
  Future<bool> isProcessRunning(int pid) async {
    final p = processes.cast<({int pid, String appName, String exePath, bool isAlive})?>().firstWhere(
      (item) => item?.pid == pid,
      orElse: () => null,
    );
    return p?.isAlive ?? false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  int dbCounter = 0;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('balance_phase4_tests_');
  });

  tearDownAll(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  UsageRepository createUniqueRepository() {
    dbCounter++;
    final dbFile = p.join(tempDir.path, 'test_db_$dbCounter.db');
    return UsageRepository(
      dbName: dbFile,
      enableLegacyMigration: false,
    );
  }

  final testTheme = ThemeData.dark().copyWith(
    extensions: [AppThemeColors.dark],
  );

  group('Phase 4 Reliability Audit & Deterministic Verification Tests', () {
    // 1. Foreground usage tracking: app switching and transient glance filtering
    test('1. Usage is recorded correctly across foreground app switches and filters transient glances', () async {
      final repository = createUniqueRepository();
      DateTime simulatedTime = DateTime(2026, 10, 21, 10, 0, 0);
      String? currentForeground = r'C:\Tools\Editor.exe';

      final tracker = WindowsUsageTracker(
        repository: repository,
        clock: () => simulatedTime,
        idleTimeProvider: () => Duration.zero,
        foregroundWindowProvider: () => currentForeground,
        checkpointInterval: const Duration(seconds: 15),
      );
      await tracker.init();
      tracker.start();

      // Start Editor.exe at 10:00:00
      await tracker.checkForegroundWindow();

      // Advance 10s: still in Editor.exe
      simulatedTime = simulatedTime.add(const Duration(seconds: 10));
      await tracker.checkForegroundWindow();

      // Switch to Transient.exe for only 1 second (<= 2s glance threshold)
      simulatedTime = simulatedTime.add(const Duration(seconds: 1));
      currentForeground = r'C:\Tools\Transient.exe';
      await tracker.checkForegroundWindow();

      // Switch immediately to Browser.exe for 20 seconds
      simulatedTime = simulatedTime.add(const Duration(seconds: 1));
      currentForeground = r'C:\Apps\Browser.exe';
      await tracker.checkForegroundWindow();

      simulatedTime = simulatedTime.add(const Duration(seconds: 20));
      await tracker.checkForegroundWindow();

      // Stop tracker to flush all active sessions
      await tracker.stop();

      // Verify sessions in SQLite
      final sessions = await repository.getSessionsForDay(DateTime(2026, 10, 21));

      // Editor.exe (11s) and Browser.exe (20s) must be committed
      expect(sessions.any((s) => s.appName.toLowerCase() == 'editor'), isTrue);
      expect(sessions.any((s) => s.appName.toLowerCase() == 'browser'), isTrue);

      // Transient.exe (1s) must be cleanly discarded to prevent database clutter
      expect(sessions.any((s) => s.appName.toLowerCase() == 'transient'), isFalse);

      final editorSession = sessions.firstWhere((s) => s.appName.toLowerCase() == 'editor');
      final browserSession = sessions.firstWhere((s) => s.appName.toLowerCase() == 'browser');
      expect(editorSession.duration, equals(const Duration(seconds: 11)));
      expect(browserSession.duration, equals(const Duration(seconds: 20)));

      tracker.dispose();
      await repository.close();
    });

    // 2. Normal shutdown session flush
    test('2. The active in-progress session is flushed cleanly on normal shutdown', () async {
      final repository = createUniqueRepository();
      DateTime simulatedTime = DateTime(2026, 10, 21, 14, 0, 0);

      final tracker = WindowsUsageTracker(
        repository: repository,
        clock: () => simulatedTime,
        idleTimeProvider: () => Duration.zero,
        foregroundWindowProvider: () => r'C:\Apps\CodeEditor.exe',
      );
      await tracker.init();
      tracker.start();

      // Session starts at 14:00:00
      await tracker.checkForegroundWindow();

      // 8 seconds elapse (less than 15s checkpoint, so not yet checkpointed)
      simulatedTime = simulatedTime.add(const Duration(seconds: 8));
      await tracker.checkForegroundWindow();

      final focusService = FocusService(repository: repository, clock: () => simulatedTime);
      await focusService.init();

      bool didShutdownRun = false;
      final trayService = WindowsTrayService(
        isPlatformSupported: false,
        exitHandler: (code) {},
        onShutdown: () async {
          await tracker.stop();
          await focusService.handleAppShutdown();
          await repository.close();
          didShutdownRun = true;
        },
      );
      await trayService.init();

      // Trigger deliberate clean shutdown
      await trayService.cleanShutdown();
      expect(didShutdownRun, isTrue);

      // Reopen repository to verify that CodeEditor session was flushed with exact 8s duration
      final verifyRepo = UsageRepository(
        dbName: (await repository.resolveDatabasePath()),
        enableLegacyMigration: false,
      );
      final sessions = await verifyRepo.getSessionsForDay(DateTime(2026, 10, 21));
      expect(sessions.length, equals(1));
      expect(sessions.first.appName.toLowerCase(), equals('codeeditor'));
      expect(sessions.first.duration, equals(const Duration(seconds: 8)));

      tracker.dispose();
      focusService.dispose();
      trayService.dispose();
      await verifyRepo.close();
    });

    // 3. Restart recovery does not double-count or lose previously committed sessions
    test('3. Restart recovery does not double-count or lose previously committed sessions', () async {
      final repository = createUniqueRepository();
      final day = DateTime(2026, 10, 21);

      // Seed 2 committed sessions from earlier in the day
      await repository.insertSession(AppSession(
        appName: 'Terminal',
        exePath: r'C:\Tools\Terminal.exe',
        startTime: DateTime(2026, 10, 21, 8, 0, 0),
        endTime: DateTime(2026, 10, 21, 9, 0, 0), // 1 hour
      ));
      await repository.insertSession(AppSession(
        appName: 'Browser',
        exePath: r'C:\Apps\Browser.exe',
        startTime: DateTime(2026, 10, 21, 9, 15, 0),
        endTime: DateTime(2026, 10, 21, 9, 45, 0), // 30 minutes
      ));

      DateTime simulatedTime = DateTime(2026, 10, 21, 10, 0, 0);

      // Launch fresh WindowsUsageTracker instance simulating application restart
      final tracker = WindowsUsageTracker(
        repository: repository,
        clock: () => simulatedTime,
        idleTimeProvider: () => Duration.zero,
        foregroundWindowProvider: () => r'C:\Apps\Browser.exe',
        checkpointInterval: const Duration(seconds: 15),
      );
      await tracker.init();
      tracker.start();

      // On startup, initial summary must exactly reflect 1h 30m without double-counting
      expect(tracker.todaySummary?.totalActiveTime, equals(const Duration(hours: 1, minutes: 30)));

      // Resume using Browser for 15 minutes
      await tracker.checkForegroundWindow();
      simulatedTime = simulatedTime.add(const Duration(minutes: 15));
      await tracker.checkForegroundWindow();

      // Total usage must be exactly 1h 45m (1h Terminal + 45m Browser)
      expect(tracker.todaySummary?.totalActiveTime, equals(const Duration(hours: 1, minutes: 45)));

      final browserUsage = tracker.todaySummary?.allApps.firstWhere((a) => a.appName == 'Browser');
      expect(browserUsage?.duration, equals(const Duration(minutes: 45)));

      await tracker.stop();
      tracker.dispose();
      await repository.close();
    });

    // 4. Local midnight rollover for usage tracking and daily limits
    test('4. Local midnight rollover correctly splits sessions and resets daily limits', () async {
      final repository = createUniqueRepository();
      final processManager = FakeReliabilityProcessManager();
      processManager.processes.add(
        (pid: 701, appName: 'Game', exePath: r'C:\Games\Game.exe', isAlive: true),
      );

      DateTime simulatedTime = DateTime(2026, 10, 21, 23, 55, 0);

      final enforcement = AppEnforcementService(
        processManager: processManager,
        gracePeriod: Duration.zero,
        clock: () => simulatedTime,
      );

      // App limit of 8 minutes for Game
      final dailyLimit = AppLimit(
        id: 1,
        appName: 'Game',
        exePath: r'C:\Games\Game.exe',
        limitDuration: const Duration(minutes: 8),
        isEnabled: true,
        isEnforced: true,
        createdAt: simulatedTime,
        updatedAt: simulatedTime,
      );
      await repository.insertLimit(dailyLimit);

      final tracker = WindowsUsageTracker(
        repository: repository,
        clock: () => simulatedTime,
        idleTimeProvider: () => Duration.zero,
        foregroundWindowProvider: () => r'C:\Games\Game.exe',
        checkpointInterval: const Duration(seconds: 15),
      );
      await tracker.init();
      tracker.start();

      final limitsService = LimitsService(
        repository: repository,
        tracker: tracker,
        enforcementService: enforcement,
        clock: () => simulatedTime,
      );
      await limitsService.init();

      // Start session in Game at 23:55:00
      await tracker.checkForegroundWindow();

      // Advance to 00:05:00 next day (crossing midnight, 10 mins total continuous use)
      simulatedTime = DateTime(2026, 10, 22, 0, 5, 0);
      enforcement.setClock(() => simulatedTime);
      limitsService.setClock(() => simulatedTime);
      await tracker.checkForegroundWindow();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Day 1 (Oct 21) must have recorded exactly 5 minutes (23:55:00 to 23:59:59.999)
      final day1Summary = await tracker.getSummaryForDay(DateTime(2026, 10, 21));
      expect(day1Summary.totalActiveTime.inMinutes, equals(5));

      // Day 2 (Oct 22) must have recorded 5 minutes (00:00:00 to 00:05:00)
      expect(tracker.todaySummary?.totalActiveTime.inMinutes, equals(5));

      // Since Day 2 usage is 5 minutes (< 8 min limit), Game must NOT be restricted on Day 2!
      expect(enforcement.isDailyLimitRestricted('Game'), isFalse);

      limitsService.dispose();
      await tracker.stop();
      tracker.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      enforcement.dispose();
      await repository.close();
    });

    // 5. OverviewScreen and ApplicationsScreen auto-advance across midnight
    testWidgets('5. OverviewScreen and ApplicationsScreen auto-advance across midnight without showing stale yesterday', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repository = createUniqueRepository();
      DateTime simulatedTime = DateTime(2026, 10, 21, 23, 58, 0);

      final tracker = WindowsUsageTracker(
        repository: repository,
        clock: () => simulatedTime,
        idleTimeProvider: () => Duration.zero,
        foregroundWindowProvider: () => r'C:\Tools\Code.exe',
      );
      await tracker.init();
      tracker.start();

      final focusService = FocusService(repository: repository, clock: () => simulatedTime);
      await focusService.init();
      final limitsService = LimitsService(repository: repository, tracker: tracker, clock: () => simulatedTime);
      await limitsService.init();

      final analyticsService = Phase4CountingAnalyticsService(repository: repository);

      await tester.pumpWidget(
        TrackerProvider(
          tracker: tracker,
          child: FocusProvider(
            focusService: focusService,
            child: LimitsProvider(
              limitsService: limitsService,
              child: MaterialApp(
                theme: testTheme,
                home: const Scaffold(body: OverviewScreen()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially displays Day 1
      expect(find.textContaining('Today, Oct 21, 2026'), findsOneWidget);

      // Cross midnight to Oct 22
      simulatedTime = DateTime(2026, 10, 22, 0, 2, 0);
      await tracker.checkForegroundWindow();
      await tester.pumpAndSettle();

      // Screen MUST automatically track the new day ("Today, Oct 22, 2026") instead of flipping to "Yesterday"
      expect(find.textContaining('Today, Oct 22, 2026'), findsOneWidget);
      expect(find.textContaining('Yesterday'), findsNothing);

      // Now test ApplicationsScreen auto-reanchoring across midnight
      await tester.pumpWidget(
        TrackerProvider(
          tracker: tracker,
          child: LimitsProvider(
            limitsService: limitsService,
            child: MaterialApp(
              theme: testTheme,
              home: Scaffold(
                body: ApplicationsScreen(
                  analyticsService: analyticsService,
                  clock: () => simulatedTime,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial selection was re-anchored to Oct 22
      expect(analyticsService.lastSelection?.startDate, equals(DateTime(2026, 10, 22)));

      focusService.dispose();
      limitsService.dispose();
      await tracker.stop();
      tracker.dispose();
      await repository.close();
    });

    // 6. Focus timers, pause/resume, and sleep/wake recovery
    test('6. Focus timers exclude paused duration, survive sleep/wake, and record exact active time', () async {
      final repository = createUniqueRepository();
      DateTime simulatedTime = DateTime(2026, 10, 21, 9, 0, 0);

      final focusService = FocusService(
        repository: repository,
        clock: () => simulatedTime,
      );
      await focusService.init();

      final preset = FocusPreset(
        name: 'Reliability Preset',
        focusDuration: const Duration(minutes: 25),
        shortBreakDuration: const Duration(minutes: 5),
        longBreakDuration: const Duration(minutes: 15),
      );
      await focusService.createPreset(preset);
      await focusService.selectPreset(focusService.presets.last);

      // 1. Start focus session
      await focusService.start();
      expect(focusService.isRunning, isTrue);

      // Run for 10 minutes
      simulatedTime = simulatedTime.add(const Duration(minutes: 10));
      focusService.tick();
      expect(focusService.remainingDuration, equals(const Duration(minutes: 15)));

      // 2. Pause session for 20 minutes (simulating meeting or break)
      await focusService.pause();
      expect(focusService.isPaused, isTrue);
      simulatedTime = simulatedTime.add(const Duration(minutes: 20));

      // 3. Resume session: remaining duration must still be 15 minutes!
      await focusService.resume();
      expect(focusService.isRunning, isTrue);
      expect(focusService.remainingDuration, equals(const Duration(minutes: 15)));

      // 4. Run for another 5 minutes and stop early
      simulatedTime = simulatedTime.add(const Duration(minutes: 5));
      focusService.tick();
      await focusService.stop();
      await focusService.pendingDbOp;

      // Actual recorded focus time MUST be strictly 15 minutes (10m + 5m), excluding the 20m paused time!
      final recordedSessions = await repository.getRecentFocusSessions();
      expect(recordedSessions.length, equals(1));
      expect(recordedSessions.first.actualDuration, equals(const Duration(minutes: 15)));
      expect(recordedSessions.first.completedNaturally, isFalse);

      // 5. Test sleep/wake recovery: session auto-completes without timer drift
      await focusService.start();
      // Simulate PC sleeping for 30 minutes (exceeding 25 min target)
      simulatedTime = simulatedTime.add(const Duration(minutes: 30));
      focusService.tick();
      await focusService.pendingDbOp;

      // Session must naturally complete on wakeup and transition to break
      expect(focusService.sessionType, equals(FocusSessionType.breakSession));
      final updatedHistory = await repository.getRecentFocusSessions();
      expect(updatedHistory.first.completedNaturally, isTrue);
      expect(updatedHistory.first.actualDuration, equals(const Duration(minutes: 25)));

      focusService.dispose();
      await repository.close();
    });

    // 7. Repeated tray hide/restore does not duplicate subscriptions or timers
    test('7. Repeated tray hide/restore is idempotent and maintains correct visibility states', () async {
      final trayService = WindowsTrayService(isPlatformSupported: false);
      await trayService.init();

      int visibilityChanges = 0;
      trayService.windowVisibilityNotifier.addListener(() {
        visibilityChanges++;
      });

      expect(trayService.isWindowVisible, isTrue);

      // 10 cycles of hide and restore
      for (int i = 0; i < 10; i++) {
        await trayService.hideToTray();
        expect(trayService.isWindowHidden, isTrue);
        expect(trayService.isWindowVisible, isFalse);

        await trayService.restoreWindow();
        expect(trayService.isWindowHidden, isFalse);
        expect(trayService.isWindowVisible, isTrue);
      }

      // Exactly 20 visibility toggles (10 down, 10 up)
      expect(visibilityChanges, equals(20));

      trayService.dispose();
    });

    // 8. Release build database directory resolution
    test('8. Database path resolves to local app data directory in Windows environment', () async {
      final repo = UsageRepository();
      final defaultDir = repo.defaultDatabaseDirectory;

      if (Platform.isWindows) {
        final expectedLocal = Platform.environment['LOCALAPPDATA'];
        if (expectedLocal != null && expectedLocal.isNotEmpty) {
          expect(defaultDir, equals(p.join(expectedLocal, 'Balance')));
          final dbPath = await repo.resolveDatabasePath('usage.db');
          expect(dbPath, equals(p.join(expectedLocal, 'Balance', 'usage.db')));
        }
      }

      expect(defaultDir.isNotEmpty, isTrue);
    });
  });
}
