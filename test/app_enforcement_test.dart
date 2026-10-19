import 'package:flutter_test/flutter_test.dart';
import 'package:balance/core/models/app_limit.dart';
import 'package:balance/core/models/app_session.dart';
import 'package:balance/core/models/usage_data.dart';
import 'package:balance/core/services/app_enforcement_service.dart';
import 'package:balance/core/services/focus_notification_service.dart';
import 'package:balance/core/services/limits_service.dart';
import 'package:balance/core/services/usage_repository.dart';
import 'package:balance/core/services/windows_process_manager.dart';

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

      // Matching
      final match = _matches(p, appName, exePath);
      if (match) {
        results.add(RunningProcessInfo(
          pid: p.pid,
          exePath: p.exePath,
          exeName: p.exeName,
        ));
      }
    }
    return results;
  }

  bool _matches(MockProcess p, String appName, String? exePath) {
    if (exePath != null && exePath.isNotEmpty) {
      if (p.exePath.toLowerCase() == exePath.toLowerCase()) return true;
    }
    final cleanApp = appName.trim().toLowerCase();
    final pBase = p.exeName.toLowerCase().replaceAll('.exe', '');
    return pBase == cleanApp || p.exeName.toLowerCase() == '$cleanApp.exe';
  }

  @override
  Future<bool> closeProcessGracefully(RunningProcessInfo process) async {
    gracefulCloseAttempts.add(process.pid);
    final mock = processes.firstWhere((p) => p.pid == process.pid);
    if (mock.exitsOnGracefulClose) {
      mock.isAlive = false;
      return true;
    }
    return true; // Sent message, but process stayed open
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

class FakeNotificationService extends FocusNotificationService {
  final List<String> warnings = [];
  final List<String> reached = [];

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

class FakeUsageRepo extends UsageRepository {
  final List<AppLimit> limits = [];
  final Map<int, Set<String>> sentNotifications = {};

  @override
  Future<List<AppLimit>> getAllLimits() async => List.unmodifiable(limits);

  @override
  Future<AppLimit?> getLimitByAppName(String appName) async {
    for (final l in limits) {
      if (l.appName.toLowerCase() == appName.toLowerCase()) return l;
    }
    return null;
  }

  @override
  Future<AppLimit> insertLimit(AppLimit limit) async {
    final created = limit.copyWith(id: limits.length + 1);
    limits.add(created);
    return created;
  }

  @override
  Future<void> updateLimit(AppLimit limit) async {
    final idx = limits.indexWhere((l) => l.id == limit.id);
    if (idx != -1) limits[idx] = limit;
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
  Future<List<AppSession>> getSessionsForDay(DateTime date) async => [];

  @override
  Future<void> close() async {}
}

void main() {
  group('AppEnforcementService and Process Management Tests', () {
    late FakeProcessManager processManager;
    late AppEnforcementService enforcementService;
    late DateTime testTime;

    DateTime getClock() => testTime;

    setUp(() {
      testTime = DateTime(2026, 10, 11, 14, 0); // 2:00 PM Sunday
      processManager = FakeProcessManager(currentPid: 9999);
      enforcementService = AppEnforcementService(
        processManager: processManager,
        gracePeriod: Duration.zero, // instant for unit tests
        clock: getClock,
      );
    });

    test('Protection: Never matches, closes, or terminates Balance PID or system processes', () async {
      // Balance itself
      processManager.processes.add(MockProcess(
        pid: 9999,
        appName: 'Balance',
        exeName: 'balance.exe',
        exePath: r'C:\Balance\balance.exe',
      ));
      // System process
      processManager.processes.add(MockProcess(
        pid: 4,
        appName: 'System',
        exeName: 'system',
        exePath: 'system',
      ));
      // Target app
      processManager.processes.add(MockProcess(
        pid: 1001,
        appName: 'Telegram',
        exeName: 'Telegram.exe',
        exePath: r'C:\Telegram\Telegram.exe',
      ));

      final balanceProcs = await processManager.findProcessesForApp(appName: 'Balance');
      expect(balanceProcs, isEmpty, reason: 'Balance self-PID must never be returned');

      final systemProcs = await processManager.findProcessesForApp(appName: 'System');
      expect(systemProcs, isEmpty, reason: 'Kernel PID 4 must never be returned');

      final telegramProcs = await processManager.findProcessesForApp(appName: 'Telegram');
      expect(telegramProcs.length, equals(1));
      expect(telegramProcs.first.pid, equals(1001));
    });

    test('Enforcement disabled: Does not close target application even when limit is exceeded', () async {
      processManager.processes.add(MockProcess(
        pid: 1001,
        appName: 'Telegram',
        exeName: 'Telegram.exe',
        exePath: r'C:\Telegram\Telegram.exe',
      ));

      final limit = AppLimit(
        id: 1,
        appName: 'Telegram',
        limitDuration: const Duration(minutes: 5),
        isEnabled: true,
        isEnforced: false, // Enforcement OFF
        createdAt: testTime,
        updatedAt: testTime,
      );

      final result = await enforcementService.enforceLimit(limit);
      expect(result.isEnforced, isFalse);
      expect(processManager.gracefulCloseAttempts, isEmpty);
      expect(processManager.terminatedPids, isEmpty);
      expect(processManager.processes.first.isAlive, isTrue);
      expect(enforcementService.isAppRestricted('Telegram'), isFalse);
    });

    test('Enforcement enabled with graceful exit: Closes target application without forceful kill', () async {
      processManager.processes.add(MockProcess(
        pid: 1001,
        appName: 'Telegram',
        exeName: 'Telegram.exe',
        exePath: r'C:\Telegram\Telegram.exe',
        exitsOnGracefulClose: true,
      ));

      final limit = AppLimit(
        id: 1,
        appName: 'Telegram',
        limitDuration: const Duration(minutes: 5),
        isEnabled: true,
        isEnforced: true, // Enforcement ON
        createdAt: testTime,
        updatedAt: testTime,
      );

      final result = await enforcementService.enforceLimit(limit);
      expect(result.isEnforced, isTrue);
      expect(result.discoveredProcesses, equals(1));
      expect(result.gracefullyClosed, equals(1));
      expect(result.terminated, equals(0));

      expect(processManager.gracefulCloseAttempts, contains(1001));
      expect(processManager.terminatedPids, isEmpty);
      expect(processManager.processes.first.isAlive, isFalse);
      expect(enforcementService.isAppRestricted('Telegram'), isTrue);
    });

    test('Enforcement fallback: Terminates process if application does not exit gracefully', () async {
      processManager.processes.add(MockProcess(
        pid: 2002,
        appName: 'Telegram',
        exeName: 'Telegram.exe',
        exePath: r'C:\Telegram\Telegram.exe',
        exitsOnGracefulClose: false, // Ignores WM_CLOSE
      ));

      final limit = AppLimit(
        id: 1,
        appName: 'Telegram',
        limitDuration: const Duration(minutes: 5),
        isEnabled: true,
        isEnforced: true,
        createdAt: testTime,
        updatedAt: testTime,
      );

      final result = await enforcementService.enforceLimit(limit);
      expect(result.isEnforced, isTrue);
      expect(result.discoveredProcesses, equals(1));
      expect(result.gracefullyClosed, equals(1));
      expect(result.terminated, equals(1));

      expect(processManager.gracefulCloseAttempts, contains(2002));
      expect(processManager.terminatedPids, contains(2002));
      expect(processManager.processes.first.isAlive, isFalse);
    });

    test('Handles multiple processes belonging to the same application', () async {
      processManager.processes.addAll([
        MockProcess(pid: 3001, appName: 'Telegram', exeName: 'Telegram.exe', exePath: r'C:\Telegram\Telegram.exe'),
        MockProcess(pid: 3002, appName: 'Telegram', exeName: 'Telegram.exe', exePath: r'C:\Telegram\Telegram.exe'),
      ]);

      final limit = AppLimit(
        id: 1,
        appName: 'Telegram',
        limitDuration: const Duration(minutes: 5),
        isEnabled: true,
        isEnforced: true,
        createdAt: testTime,
        updatedAt: testTime,
      );

      final result = await enforcementService.enforceLimit(limit);
      expect(result.discoveredProcesses, equals(2));
      expect(processManager.gracefulCloseAttempts, containsAll([3001, 3002]));
      expect(processManager.processes.every((p) => !p.isAlive), isTrue);
    });

    test('Relaunch detection: Closes target application when brought back into use after limit exceeded', () async {
      final limit = AppLimit(
        id: 1,
        appName: 'Telegram',
        limitDuration: const Duration(minutes: 5),
        isEnabled: true,
        isEnforced: true,
        createdAt: testTime,
        updatedAt: testTime,
      );

      // Reopening Telegram after limit exceeded
      final reopenedProcess = MockProcess(
        pid: 4001,
        appName: 'Telegram',
        exeName: 'Telegram.exe',
        exePath: r'C:\Telegram\Telegram.exe',
      );
      processManager.processes.add(reopenedProcess);

      // Advance time past cooldown
      testTime = testTime.add(const Duration(seconds: 10));

      await enforcementService.onForegroundAppDetected(
        appName: 'Telegram',
        exePath: r'C:\Telegram\Telegram.exe',
        limits: [limit],
        todayUsage: const Duration(minutes: 6), // Exceeded
      );

      expect(processManager.gracefulCloseAttempts, contains(4001));
      expect(reopenedProcess.isAlive, isFalse);
    });

    test('Daily reset: Resets enforcement when next calendar day begins', () async {
      final limit = AppLimit(
        id: 1,
        appName: 'Telegram',
        limitDuration: const Duration(minutes: 5),
        isEnabled: true,
        isEnforced: true,
        createdAt: testTime,
        updatedAt: testTime,
      );

      // Enforce on Sunday
      await enforcementService.enforceLimit(limit);
      expect(enforcementService.isAppRestricted('Telegram'), isTrue);

      // Advance clock to Monday 8:00 AM (next local calendar day)
      testTime = DateTime(2026, 10, 12, 8, 0);

      // Restriction should be reset
      expect(enforcementService.isAppRestricted('Telegram'), isFalse);

      // Reopening on Monday morning with 0 usage should NOT close Telegram
      final mondayProcess = MockProcess(
        pid: 5001,
        appName: 'Telegram',
        exeName: 'Telegram.exe',
        exePath: r'C:\Telegram\Telegram.exe',
      );
      processManager.processes.add(mondayProcess);

      await enforcementService.onForegroundAppDetected(
        appName: 'Telegram',
        exePath: r'C:\Telegram\Telegram.exe',
        limits: [limit],
        todayUsage: const Duration(minutes: 1), // Only 1 min on new day
      );

      expect(processManager.gracefulCloseAttempts, isNot(contains(5001)));
      expect(mondayProcess.isAlive, isTrue);
    });

    test('Full integration with LimitsService: Telegram 5m limit and 85% warning', () async {
      final repo = FakeUsageRepo();
      final notificationService = FakeNotificationService();

      final limitsService = LimitsService(
        repository: repo,
        notificationService: notificationService,
        enforcementService: enforcementService,
        clock: getClock,
      );
      await limitsService.init();

      // Configure Telegram: 5m limit, 85% warning threshold, enforcement enabled
      final createdLimit = await limitsService.createLimit(
        appName: 'Telegram',
        exePath: r'C:\Telegram\Telegram.exe',
        duration: const Duration(minutes: 5),
        warningPercentage: 85,
        isEnforced: true,
      );
      expect(createdLimit.isEnforced, isTrue);

      // Process running
      final telegramProc = MockProcess(
        pid: 6001,
        appName: 'Telegram',
        exeName: 'Telegram.exe',
        exePath: r'C:\Telegram\Telegram.exe',
      );
      processManager.processes.add(telegramProc);

      // 1. At 4m 15s (85%): warning notification fires, process remains open and alive
      final summary4m = DailyUsageSummary(
        date: testTime,
        totalActiveTime: const Duration(minutes: 4, seconds: 15),
        goalTime: const Duration(hours: 6),
        focusTime: Duration.zero,
        breaksTaken: 0,
        hourlyActivity: List.filled(24, 0.0),
        mostUsedApps: [],
        allApps: [
          AppUsageData(
            appName: 'Telegram',
            duration: const Duration(minutes: 4, seconds: 15),
            proportionalUsage: 1.0,
          ),
        ],
      );
      await limitsService.evaluateUsage(summary: summary4m);

      expect(notificationService.warnings, contains('Telegram'));
      expect(notificationService.reached, isEmpty);
      expect(processManager.gracefulCloseAttempts, isEmpty);
      expect(telegramProc.isAlive, isTrue);

      // Advance clock past cooldown
      testTime = testTime.add(const Duration(seconds: 10));

      // 2. At 5 minutes (100%): limit-reached notification fires AND Telegram is automatically closed
      final summary5m = DailyUsageSummary(
        date: testTime,
        totalActiveTime: const Duration(minutes: 5),
        goalTime: const Duration(hours: 6),
        focusTime: Duration.zero,
        breaksTaken: 0,
        hourlyActivity: List.filled(24, 0.0),
        mostUsedApps: [],
        allApps: [
          AppUsageData(
            appName: 'Telegram',
            duration: const Duration(minutes: 5),
            proportionalUsage: 1.0,
          ),
        ],
      );
      await limitsService.evaluateUsage(summary: summary5m);

      expect(notificationService.reached, contains('Telegram'));
      expect(processManager.gracefulCloseAttempts, contains(6001));
      expect(telegramProc.isAlive, isFalse);
      expect(enforcementService.isAppRestricted('Telegram'), isTrue);
    });

    test('Zero-minute limit: Immediately restricts and terminates app on detection without grace period', () async {
      final zeroLimit = AppLimit(
        id: 10,
        appName: 'Discord',
        limitDuration: Duration.zero,
        isEnabled: true,
        isEnforced: true,
        createdAt: testTime,
        updatedAt: testTime,
      );

      final discordProc = MockProcess(
        pid: 7001,
        appName: 'Discord',
        exeName: 'Discord.exe',
        exePath: r'C:\Discord\Discord.exe',
      );
      processManager.processes.add(discordProc);

      // Even with 0 usage duration, app must be immediately enforced and closed
      await enforcementService.onForegroundAppDetected(
        appName: 'Discord',
        exePath: r'C:\Discord\Discord.exe',
        limits: [zeroLimit],
        todayUsage: Duration.zero,
      );

      expect(processManager.gracefulCloseAttempts, contains(7001));
      expect(discordProc.isAlive, isFalse);
      expect(enforcementService.isDailyLimitRestricted('Discord'), isTrue);
      expect(enforcementService.isAppRestricted('Discord'), isTrue);
    });

    test('Zero-minute limit: Disabling enforcement allows application to run freely', () async {
      final unenforcedZeroLimit = AppLimit(
        id: 11,
        appName: 'Discord',
        limitDuration: Duration.zero,
        isEnabled: true,
        isEnforced: false, // Enforcement disabled
        createdAt: testTime,
        updatedAt: testTime,
      );

      final discordProc = MockProcess(
        pid: 7002,
        appName: 'Discord',
        exeName: 'Discord.exe',
        exePath: r'C:\Discord\Discord.exe',
      );
      processManager.processes.add(discordProc);

      await enforcementService.onForegroundAppDetected(
        appName: 'Discord',
        exePath: r'C:\Discord\Discord.exe',
        limits: [unenforcedZeroLimit],
        todayUsage: Duration.zero,
      );

      expect(processManager.gracefulCloseAttempts, isNot(contains(7002)));
      expect(discordProc.isAlive, isTrue);
      expect(enforcementService.isDailyLimitRestricted('Discord'), isFalse);
    });

    test('Zero-minute limit: Preserves restriction across midnight resets while positive limits reset', () async {
      final zeroLimit = AppLimit(
        id: 12,
        appName: 'Roblox',
        limitDuration: Duration.zero,
        isEnabled: true,
        isEnforced: true,
        createdAt: testTime,
        updatedAt: testTime,
      );
      final positiveLimit = AppLimit(
        id: 13,
        appName: 'Steam',
        limitDuration: const Duration(hours: 1),
        isEnabled: true,
        isEnforced: true,
        createdAt: testTime,
        updatedAt: testTime,
      );

      // Evaluate enforcements today
      enforcementService.evaluateEnforcements(
        [zeroLimit, positiveLimit],
        {'roblox': Duration.zero, 'steam': const Duration(hours: 2)}, // Both exceeded today
      );
      expect(enforcementService.isDailyLimitRestricted('Roblox'), isTrue);
      expect(enforcementService.isDailyLimitRestricted('Steam'), isTrue);

      // Advance clock past midnight to next calendar day
      testTime = DateTime(2026, 10, 12, 0, 1); // Monday 12:01 AM
      enforcementService.setClock(getClock);

      // Roblox (zero allowance) must STILL be restricted on the new day
      expect(enforcementService.isDailyLimitRestricted('Roblox'), isTrue);
      // Steam (positive allowance) must have its restriction reset
      expect(enforcementService.isDailyLimitRestricted('Steam'), isFalse);
    });

    test('Zero-minute limit: Remains independent from Focus Mode restrictions', () async {
      final zeroLimit = AppLimit(
        id: 14,
        appName: 'SocialApp',
        limitDuration: Duration.zero,
        isEnabled: true,
        isEnforced: true,
        createdAt: testTime,
        updatedAt: testTime,
      );

      enforcementService.evaluateEnforcements([zeroLimit], {'socialapp': Duration.zero});
      expect(enforcementService.isDailyLimitRestricted('SocialApp'), isTrue);
      expect(enforcementService.isFocusRestricted('SocialApp'), isFalse);

      // Start and clear focus mode
      await enforcementService.setFocusRestrictions(
        blockedApps: const [],
        isEnforcing: true,
      );
      enforcementService.clearFocusRestrictions();

      // Daily limit restriction for SocialApp must remain unaffected
      expect(enforcementService.isDailyLimitRestricted('SocialApp'), isTrue);
    });
  });
}
