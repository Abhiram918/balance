import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balance/app/app.dart';
import 'package:balance/app/theme/app_colors.dart';
import 'package:balance/core/models/app_block_event.dart';
import 'package:balance/core/models/app_limit.dart';
import 'package:balance/core/models/app_session.dart';
import 'package:balance/core/models/focus_session.dart';
import 'package:balance/core/models/usage_data.dart';
import 'package:balance/core/services/app_enforcement_service.dart';
import 'package:balance/core/services/focus_notification_service.dart';
import 'package:balance/core/services/limits_service.dart';
import 'package:balance/core/services/usage_repository.dart';
import 'package:balance/core/services/windows_process_manager.dart';
import 'package:balance/core/services/windows_tray_service.dart';
import 'package:balance/core/services/windows_usage_tracker.dart';
import 'package:balance/core/widgets/app_block_dialog.dart';
import 'package:balance/core/widgets/app_block_dialog_manager.dart';

class MockProcess {
  final int pid;
  final String appName;
  final String exeName;
  final String exePath;
  bool isAlive;
  bool exitsOnGracefulClose;

  MockProcess({
    required this.pid,
    required this.appName,
    required this.exeName,
    required this.exePath,
    this.isAlive = true,
    this.exitsOnGracefulClose = true,
  });
}

class FakeProcessManager implements ProcessManager {
  final int currentPid;
  final List<MockProcess> processes = [];
  final List<int> gracefulCloseAttempts = [];
  final List<int> terminatedPids = [];

  FakeProcessManager({this.currentPid = 9999});

  @override
  int getCurrentProcessId() => currentPid;

  @override
  Future<List<RunningProcessInfo>> findProcessesForApp({
    required String appName,
    String? exePath,
  }) async {
    final results = <RunningProcessInfo>[];
    for (final p in processes) {
      if (!p.isAlive) continue;
      if (p.pid == currentPid || p.pid <= 4) continue;

      if (_matches(p, appName, exePath)) {
        results.add(RunningProcessInfo(
          pid: p.pid,
          exePath: p.exePath,
          exeName: p.exeName,
        ));
      }
    }
    return results;
  }

  @override
  Future<Map<TargetAppCriteria, List<RunningProcessInfo>>> findProcessesForApps(
    List<TargetAppCriteria> targets,
  ) async {
    final result = <TargetAppCriteria, List<RunningProcessInfo>>{};
    for (final target in targets) {
      result[target] = await findProcessesForApp(
        appName: target.appName,
        exePath: target.exePath,
      );
    }
    return result;
  }

  bool _matches(MockProcess p, String appName, String? exePath) {
    if (exePath != null && exePath.isNotEmpty) {
      if (p.exePath.toLowerCase() == exePath.toLowerCase()) return true;
    }
    final cleanApp = appName.trim().toLowerCase();
    final pBase = p.exeName.toLowerCase().replaceAll('.exe', '');
    if (pBase == cleanApp || p.exeName.toLowerCase() == '$cleanApp.exe') {
      return true;
    }
    if (AppEnforcementService.areAppAliases(cleanApp, pBase)) {
      return true;
    }
    return false;
  }

  @override
  Future<bool> closeProcessGracefully(RunningProcessInfo process) async {
    gracefulCloseAttempts.add(process.pid);
    final mock = processes.firstWhere((p) => p.pid == process.pid);
    if (mock.exitsOnGracefulClose) {
      mock.isAlive = false;
      return true;
    }
    return true;
  }

  @override
  Future<bool> isProcessRunning(int pid) async {
    final idx = processes.indexWhere((p) => p.pid == pid);
    if (idx == -1) return false;
    return processes[idx].isAlive;
  }

  @override
  Future<bool> terminateProcess(int pid) async {
    terminatedPids.add(pid);
    final idx = processes.indexWhere((p) => p.pid == pid);
    if (idx != -1) {
      processes[idx].isAlive = false;
      return true;
    }
    return false;
  }
}

class FakeUsageRepository extends UsageRepository {
  final List<AppLimit> storedLimits = [];
  final List<AppSession> storedSessions = [];
  final Map<int, Set<String>> sentNotifications = {};

  FakeUsageRepository() : super(dbName: 'fake_regression_test.db');

  @override
  Future<List<AppLimit>> getAllLimits() async => List.unmodifiable(storedLimits);

  @override
  Future<AppLimit?> getLimitByAppName(String appName) async {
    final clean = appName.trim().toLowerCase();
    for (final l in storedLimits) {
      if (l.appName.trim().toLowerCase() == clean ||
          AppEnforcementService.areAppAliases(l.appName, clean)) {
        return l;
      }
    }
    return null;
  }

  @override
  Future<AppLimit> insertLimit(AppLimit limit) async {
    final created = limit.copyWith(id: storedLimits.length + 1);
    storedLimits.add(created);
    return created;
  }

  @override
  Future<void> updateLimit(AppLimit limit) async {
    final idx = storedLimits.indexWhere((l) => l.id == limit.id);
    if (idx != -1) storedLimits[idx] = limit;
  }

  @override
  Future<void> deleteLimit(int id) async {
    storedLimits.removeWhere((l) => l.id == id);
  }

  @override
  Future<bool> hasLimitNotificationBeenSent(
    int limitId,
    String notificationType,
    String dateKey,
  ) async {
    return sentNotifications[limitId]?.contains('$notificationType:$dateKey') ?? false;
  }

  @override
  Future<void> recordLimitNotificationSent(
    int limitId,
    String notificationType,
    String dateKey,
    DateTime timestamp,
  ) async {
    sentNotifications.putIfAbsent(limitId, () => {}).add('$notificationType:$dateKey');
  }

  @override
  Future<AppSession> insertSession(AppSession session) async {
    final created = AppSession(
      id: storedSessions.length + 1,
      appName: session.appName,
      exePath: session.exePath,
      startTime: session.startTime,
      endTime: session.endTime,
    );
    storedSessions.add(created);
    return created;
  }

  @override
  Future<List<AppSession>> getSessionsForDay(DateTime date) async {
    return storedSessions.where((s) =>
      s.startTime.year == date.year &&
      s.startTime.month == date.month &&
      s.startTime.day == date.day
    ).toList();
  }

  @override
  Future<List<FocusSessionRecord>> getFocusSessionsForDay(DateTime date) async => [];

  @override
  Future<ActiveFocusState?> getActiveFocusState() async => null;
}

class FakeNotificationService extends FocusNotificationService {
  final List<String> reached = [];
  final List<String> warnings = [];

  FakeNotificationService() : super();

  @override
  Future<bool> notifyAppLimitWarning({
    required String appName,
    required Duration used,
    required Duration limit,
    required int warningPercentage,
  }) async {
    warnings.add(appName);
    return true;
  }

  @override
  Future<bool> notifyAppLimitReached({
    required String appName,
    required Duration used,
    required Duration limit,
  }) async {
    reached.add(appName);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeProcessManager processManager;
  late FakeUsageRepository repository;
  late FakeNotificationService notificationService;
  late AppEnforcementService enforcementService;
  late LimitsService limitsService;
  late DateTime testTime;

  setUp(() {
    testTime = DateTime(2026, 10, 25, 10, 0);
    processManager = FakeProcessManager();
    repository = FakeUsageRepository();
    notificationService = FakeNotificationService();

    enforcementService = AppEnforcementService(
      processManager: processManager,
      gracePeriod: Duration.zero,
      notificationService: notificationService,
      clock: () => testTime,
    );

    limitsService = LimitsService(
      repository: repository,
      notificationService: notificationService,
      enforcementService: enforcementService,
      clock: () => testTime,
    );
  });

  Widget buildTestApp({
    LimitsService? serviceOverride,
    FutureOr<void> Function()? onRestoreWindow,
  }) {
    final effectiveLimitsService = serviceOverride ?? limitsService;
    return LimitsProvider(
      limitsService: effectiveLimitsService,
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(
          extensions: [AppThemeColors.dark],
        ),
        home: AppBlockDialogManager(
          limitsService: effectiveLimitsService,
          enforcementService: enforcementService,
          onRestoreWindow: onRestoreWindow,
          child: const Scaffold(
            body: Center(child: Text('Balance App Background Shell')),
          ),
        ),
      ),
    );
  }

  group('App Limit Enforcement Regression Suite', () {
    testWidgets('1. Tracker-to-enforcement pipeline: Exceeding limit in foreground restores window and presents dialog', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool windowRestored = false;

      // Running process for Chrome
      processManager.processes.add(MockProcess(
        pid: 101,
        appName: 'chrome',
        exeName: 'chrome.exe',
        exePath: r'C:\Program Files\Google\Chrome\Application\chrome.exe',
      ));

      // Limit of 30 minutes for Chrome
      final limit = AppLimit(
        id: 1,
        appName: 'Google Chrome',
        exePath: r'C:\Program Files\Google\Chrome\Application\chrome.exe',
        limitDuration: const Duration(minutes: 30),
        isEnabled: true,
        isEnforced: true,
        createdAt: testTime,
        updatedAt: testTime,
      );
      await repository.insertLimit(limit);

      String activeExe = r'C:\Program Files\Google\Chrome\Application\chrome.exe';
      final tracker = WindowsUsageTracker(
        repository: repository,
        clock: () => testTime,
        idleTimeProvider: () => Duration.zero,
        foregroundWindowProvider: () => activeExe,
      );
      await tracker.init();

      final activeLimitsService = LimitsService(
        repository: repository,
        tracker: tracker,
        enforcementService: enforcementService,
        notificationService: notificationService,
        clock: () => testTime,
      );
      await activeLimitsService.init();

      await tester.pumpWidget(buildTestApp(
        serviceOverride: activeLimitsService,
        onRestoreWindow: () async {
          windowRestored = true;
        },
      ));
      await tester.pump();

      // Start tracker at 0m
      await tracker.checkForegroundWindow();
      expect(enforcementService.isDailyLimitRestricted('Google Chrome'), isFalse);
      expect(windowRestored, isFalse);

      // Advance by 30 minutes and 5 seconds (exceeding daily limit)
      testTime = testTime.add(const Duration(minutes: 30, seconds: 5));
      await tracker.checkForegroundWindow();
      await activeLimitsService.lastTrackerSync;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Window MUST have been restored
      expect(windowRestored, isTrue, reason: 'Balance window must be restored and focused when dialog appears');

      // The dialog MUST be visible
      expect(find.byType(AppBlockDialog), findsOneWidget);
      expect(find.text('Daily limit reached'), findsOneWidget);

      // The process MUST have been closed
      expect(processManager.gracefulCloseAttempts, contains(101));
      expect(enforcementService.isDailyLimitRestricted('Google Chrome'), isTrue);

      // Dismiss dialog cleanly
      await tester.tap(find.byKey(const Key('block_dialog_got_it_button')));
      await tester.pumpAndSettle();

      activeLimitsService.dispose();
      tracker.dispose();
    });

    test('2. Order of operations: Block event is dispatched before process graceful close/termination wait', () async {
      // Configure enforcement with a noticeable grace period
      final delayedEnforcement = AppEnforcementService(
        processManager: processManager,
        gracePeriod: const Duration(milliseconds: 100),
        clock: () => testTime,
      );

      processManager.processes.add(MockProcess(
        pid: 201,
        appName: 'Telegram',
        exeName: 'Telegram.exe',
        exePath: r'C:\Telegram\Telegram.exe',
      ));

      final limit = AppLimit(
        id: 2,
        appName: 'Telegram',
        limitDuration: const Duration(hours: 1),
        isEnabled: true,
        isEnforced: true,
        createdAt: testTime,
        updatedAt: testTime,
      );

      DateTime? eventEmittedTime;
      final sub = delayedEnforcement.blockEvents.listen((event) {
        eventEmittedTime = DateTime.now();
      });

      final startTime = DateTime.now();
      await delayedEnforcement.enforceLimit(limit);
      final finishTime = DateTime.now();

      await sub.cancel();
      delayedEnforcement.dispose();

      expect(eventEmittedTime, isNotNull);
      // Event must be dispatched at start, not delayed until finishTime
      final eventLatency = eventEmittedTime!.difference(startTime).inMilliseconds;
      final totalOperationDuration = finishTime.difference(startTime).inMilliseconds;

      expect(eventLatency < totalOperationDuration, isTrue,
          reason: 'AppBlockEvent must be dispatched before process termination grace period completes');
      expect(processManager.gracefulCloseAttempts, contains(201));
    });

    testWidgets('3. Toast deduplication versus dialog presentation: Toast deduplication does not suppress dialog on relaunch', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await limitsService.createLimit(
        appName: 'Telegram',
        duration: const Duration(minutes: 10),
        isEnforced: true,
      );

      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      // 1. Initial limit reached event: toast sent and dialog shown
      await limitsService.evaluateUsage(summary: DailyUsageSummary(
        date: testTime,
        totalActiveTime: const Duration(minutes: 10),
        goalTime: const Duration(hours: 6),
        focusTime: Duration.zero,
        breaksTaken: 0,
        hourlyActivity: List.filled(24, 0.0),
        mostUsedApps: [],
        allApps: [
          AppUsageData(appName: 'Telegram', duration: const Duration(minutes: 10), proportionalUsage: 1.0),
        ],
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(notificationService.reached, contains('Telegram'));
      expect(notificationService.reached.length, equals(1));
      expect(find.byType(AppBlockDialog), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.byKey(const Key('block_dialog_got_it_button')));
      await tester.pumpAndSettle();
      expect(find.byType(AppBlockDialog), findsNothing);

      // 2. User tries to relaunch Telegram later on the same day
      testTime = testTime.add(const Duration(minutes: 5));
      processManager.processes.add(MockProcess(
        pid: 302,
        appName: 'Telegram',
        exeName: 'Telegram.exe',
        exePath: r'C:\Telegram\Telegram.exe',
      ));

      // Foreground app detection intercepts relaunch
      await enforcementService.onForegroundAppDetected(
        appName: 'Telegram',
        exePath: r'C:\Telegram\Telegram.exe',
        limits: limitsService.limits,
        todayUsage: const Duration(minutes: 10),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // CRITICAL: The dialog MUST appear again!
      expect(find.byType(AppBlockDialog), findsOneWidget);

      // Toast must NOT be spammed again (toast deduplication intact)
      expect(notificationService.reached.length, equals(1));

      // Process must be closed
      expect(processManager.gracefulCloseAttempts, contains(302));

      // Dismiss dialog cleanly
      await tester.tap(find.byKey(const Key('block_dialog_got_it_button')));
      await tester.pumpAndSettle();
    });

    testWidgets('4. Repeated blocked launches: Every subsequent relaunch displays the warning dialog after dismissal', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final limit = await limitsService.createLimit(
        appName: 'Discord',
        duration: const Duration(minutes: 5),
        isEnforced: true,
      );

      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      // Launch 1: Initial block
      processManager.processes.add(MockProcess(
        pid: 401,
        appName: 'Discord',
        exeName: 'Discord.exe',
        exePath: r'C:\Discord\Discord.exe',
      ));

      await enforcementService.onForegroundAppDetected(
        appName: 'Discord',
        exePath: r'C:\Discord\Discord.exe',
        limits: [limit],
        todayUsage: const Duration(minutes: 6),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(AppBlockDialog), findsOneWidget, reason: 'Attempt 1 displays dialog');
      expect(processManager.gracefulCloseAttempts, contains(401));

      // Dismiss dialog 1
      await tester.tap(find.byKey(const Key('block_dialog_got_it_button')));
      await tester.pumpAndSettle();
      expect(find.byType(AppBlockDialog), findsNothing);

      // Launch 2: Repeated attempt after dismissing
      testTime = testTime.add(const Duration(seconds: 10));
      processManager.processes.add(MockProcess(
        pid: 402,
        appName: 'Discord',
        exeName: 'Discord.exe',
        exePath: r'C:\Discord\Discord.exe',
      ));

      await enforcementService.onForegroundAppDetected(
        appName: 'Discord',
        exePath: r'C:\Discord\Discord.exe',
        limits: [limit],
        todayUsage: const Duration(minutes: 6),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(AppBlockDialog), findsOneWidget, reason: 'Attempt 2 displays dialog');
      expect(processManager.gracefulCloseAttempts, contains(402));

      // Dismiss dialog 2
      await tester.tap(find.byKey(const Key('block_dialog_got_it_button')));
      await tester.pumpAndSettle();
      expect(find.byType(AppBlockDialog), findsNothing);

      // Launch 3: Third repeated attempt after dismissing
      testTime = testTime.add(const Duration(seconds: 15));
      processManager.processes.add(MockProcess(
        pid: 403,
        appName: 'Discord',
        exeName: 'Discord.exe',
        exePath: r'C:\Discord\Discord.exe',
      ));

      await enforcementService.onForegroundAppDetected(
        appName: 'Discord',
        exePath: r'C:\Discord\Discord.exe',
        limits: [limit],
        todayUsage: const Duration(minutes: 6),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(AppBlockDialog), findsOneWidget, reason: 'Attempt 3 displays dialog');
      expect(processManager.gracefulCloseAttempts, contains(403));

      // Dismiss final dialog cleanly
      await tester.tap(find.byKey(const Key('block_dialog_got_it_button')));
      await tester.pumpAndSettle();
    });

    test('5. Cooldown coordination: Foreground detection is not locked out by evaluateUsage', () async {
      final limit = AppLimit(
        id: 5,
        appName: 'chrome',
        limitDuration: const Duration(minutes: 15),
        isEnabled: true,
        isEnforced: true,
        createdAt: testTime,
        updatedAt: testTime,
      );
      await repository.insertLimit(limit);

      String currentExe = r'C:\chrome.exe';
      final tracker = WindowsUsageTracker(
        repository: repository,
        clock: () => testTime,
        idleTimeProvider: () => Duration.zero,
        foregroundWindowProvider: () => currentExe,
      );
      await tracker.init();

      final trackerLimitsService = LimitsService(
        repository: repository,
        tracker: tracker,
        enforcementService: enforcementService,
        notificationService: notificationService,
        clock: () => testTime,
      );
      await trackerLimitsService.init();

      final blockEvents = <AppBlockEvent>[];
      final sub = enforcementService.blockEvents.listen(blockEvents.add);

      processManager.processes.add(MockProcess(
        pid: 501,
        appName: 'chrome',
        exeName: 'chrome.exe',
        exePath: r'C:\chrome.exe',
      ));

      // Initial check at t=0
      await tracker.checkForegroundWindow();
      await trackerLimitsService.lastTrackerSync;

      // Advance by 16 minutes: cross limit while Chrome is active
      testTime = testTime.add(const Duration(minutes: 16));
      await tracker.checkForegroundWindow();
      await trackerLimitsService.lastTrackerSync;

      // Must have triggered dialog event exactly once without duplicate cooldown drop
      expect(blockEvents.length, equals(1));
      expect(blockEvents.first.appName, equals('chrome'));
      expect(processManager.gracefulCloseAttempts, contains(501));

      await sub.cancel();
      trackerLimitsService.dispose();
      tracker.dispose();
    });

    test('6. Application name alias matching: Matches common Windows applications bidirectionally', () {
      final chromeLimit = AppLimit(
        id: 6,
        appName: 'Google Chrome',
        limitDuration: const Duration(hours: 1),
        isEnabled: true,
        isEnforced: true,
        createdAt: testTime,
        updatedAt: testTime,
      );

      // Verify matchesLimitApp
      expect(
        enforcementService.matchesLimitApp(
          limit: chromeLimit,
          targetAppName: 'chrome',
          targetExePath: r'C:\Program Files\Google\Chrome\Application\chrome.exe',
        ),
        isTrue,
      );

      // Verify static alias helper
      expect(AppEnforcementService.areAppAliases('Google Chrome', 'chrome'), isTrue);
      expect(AppEnforcementService.areAppAliases('chrome', 'Google Chrome'), isTrue);
      expect(AppEnforcementService.areAppAliases('Visual Studio Code', 'code'), isTrue);
      expect(AppEnforcementService.areAppAliases('Telegram Desktop', 'telegram'), isTrue);
      expect(AppEnforcementService.areAppAliases('Microsoft Edge', 'msedge'), isTrue);
      expect(AppEnforcementService.areAppAliases('Mozilla Firefox', 'firefox'), isTrue);

      // Verify isDailyLimitRestricted with aliases
      enforcementService.evaluateEnforcements([chromeLimit], {'Google Chrome': const Duration(hours: 2)});
      expect(enforcementService.isDailyLimitRestricted('Google Chrome'), isTrue);
      expect(enforcementService.isDailyLimitRestricted('chrome'), isTrue);

      // Verify removeRestriction removes alias
      enforcementService.removeRestriction('chrome');
      expect(enforcementService.isDailyLimitRestricted('chrome'), isFalse);
      expect(enforcementService.isDailyLimitRestricted('Google Chrome'), isFalse);
    });

    test('7. System tray integration: restoreWindow marks window visible and fires restoration', () async {
      bool restoredFired = false;
      final trayService = WindowsTrayService(
        onRestore: () {
          restoredFired = true;
        },
        isPlatformSupported: false, // Testing in headless environment
      );

      await trayService.init();

      // Hide to tray
      await trayService.hideToTray();
      expect(trayService.isWindowHidden, isTrue);
      expect(trayService.isWindowVisible, isFalse);

      // Restore window
      await trayService.restoreWindow();
      expect(trayService.isWindowHidden, isFalse);
      expect(trayService.isWindowVisible, isTrue);
      expect(restoredFired, isTrue);

      trayService.dispose();
    });
  });
}
