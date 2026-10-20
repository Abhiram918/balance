import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:balance/core/models/app_block_event.dart';
import 'package:balance/core/models/app_limit.dart';
import 'package:balance/core/models/app_session.dart';
import 'package:balance/core/models/focus_preset.dart';
import 'package:balance/core/models/focus_session.dart';
import 'package:balance/core/services/app_enforcement_service.dart';
import 'package:balance/core/services/focus_service.dart';
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

class FakeCountingProcessManager implements ProcessManager {
  final int currentPid;
  final List<MockProcess> processes = [];
  final List<int> gracefulCloseAttempts = [];
  final List<int> terminatedPids = [];
  int findProcessesForAppCalls = 0;
  int findProcessesForAppsCalls = 0;

  FakeCountingProcessManager({this.currentPid = 9999});

  @override
  int getCurrentProcessId() => currentPid;

  @override
  Future<List<RunningProcessInfo>> findProcessesForApp({
    required String appName,
    String? exePath,
  }) async {
    findProcessesForAppCalls++;
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
    findProcessesForAppsCalls++;
    final result = <TargetAppCriteria, List<RunningProcessInfo>>{
      for (final t in targets) t: <RunningProcessInfo>[],
    };

    for (final p in processes) {
      if (!p.isAlive) continue;
      if (p.pid == currentPid || p.pid <= 4) continue;

      RunningProcessInfo? info;
      for (final target in targets) {
        if (_matches(p, target.appName, target.exePath)) {
          info ??= RunningProcessInfo(
            pid: p.pid,
            exePath: p.exePath,
            exeName: p.exeName,
          );
          result[target]!.add(info);
        }
      }
    }
    return result;
  }

  bool _matches(MockProcess p, String appName, String? exePath) {
    if (exePath != null && exePath.trim().isNotEmpty) {
      if (p.exePath.toLowerCase() == exePath.trim().toLowerCase()) return true;
      final targetName = exePath.split(r'\').last.toLowerCase();
      if (p.exeName.toLowerCase() == targetName) return true;
    }
    final cleanApp = appName.trim().toLowerCase();
    final pBase = p.exeName.toLowerCase().replaceAll('.exe', '');
    if (pBase == cleanApp || p.exeName.toLowerCase() == '$cleanApp.exe') return true;

    // Common aliases
    if (cleanApp == 'google chrome' && pBase == 'chrome') return true;
    if (cleanApp == 'visual studio code' && pBase == 'code') return true;
    if (cleanApp == 'telegram desktop' && pBase == 'telegram') return true;
    if (cleanApp == 'microsoft edge' && pBase == 'msedge') return true;
    if (cleanApp == 'mozilla firefox' && pBase == 'firefox') return true;

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
    return true; // Sent signal, process did not exit immediately
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
  final List<FocusSessionRecord> storedFocusSessions = [];
  final List<AppLimit> storedLimits = [];

  FakeUsageRepository() : super(dbName: inMemoryDatabasePath);

  @override
  Future<List<AppSession>> getSessionsForDay(DateTime date) async => [];

  @override
  Future<List<AppSession>> getSessionsForRange(DateTime start, DateTime end) async => [];

  @override
  Future<List<FocusSessionRecord>> getFocusSessionsForDay(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = DateTime(date.year, date.month, date.day + 1);
    return storedFocusSessions.where((s) {
      return s.startTime.isBefore(end) && s.startTime.isAfter(start.subtract(const Duration(milliseconds: 1)));
    }).toList();
  }

  @override
  Future<FocusSessionRecord> insertFocusSession(FocusSessionRecord session) async {
    final record = session.copyWith(id: storedFocusSessions.length + 1);
    storedFocusSessions.add(record);
    return record;
  }

  @override
  Future<List<AppLimit>> getAllLimits() async => List.unmodifiable(storedLimits);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Phase 2 Windows Process Enumeration Tests', () {
    late FakeUsageRepository repository;

    setUp(() {
      repository = FakeUsageRepository();
    });

    // 1. Batch matching returns the same results as individual-app lookup
    test('1. Batch matching returns the same results as individual-app lookup', () async {
      // Set up simulated Windows processes
      final mockProcesses = {
        101: r'C:\Users\User\AppData\Local\Discord\Discord.exe',
        102: r'C:\Program Files\Microsoft VS Code\Code.exe',
        103: r'C:\Program Files\Google\Chrome\Application\chrome.exe',
        104: r'C:\Spotify\Spotify.exe',
        105: r'C:\Games\Game.exe',
      };

      final processManager = WindowsProcessManager(
        currentPidProvider: () => 9999,
        pidWindowsProvider: (selfPid) => {
          101: [],
          102: [],
          103: [],
          104: [],
          105: [],
        },
        processListProvider: () => [4, 101, 102, 103, 104, 105, 9999],
        processPathProvider: (pid) => mockProcesses[pid] ?? '',
      );

      final targets = [
        const TargetAppCriteria(appName: 'Discord', exePath: r'C:\Users\User\AppData\Local\Discord\Discord.exe'),
        const TargetAppCriteria(appName: 'Visual Studio Code', exePath: r'C:\Program Files\Microsoft VS Code\Code.exe'),
        const TargetAppCriteria(appName: 'Google Chrome', exePath: r'C:\Program Files\Google\Chrome\Application\chrome.exe'),
        const TargetAppCriteria(appName: 'Spotify', exePath: r'C:\Spotify\Spotify.exe'),
        const TargetAppCriteria(appName: 'Steam', exePath: r'C:\Steam\steam.exe'), // Not running
      ];

      // Query individually
      final individualResults = <TargetAppCriteria, List<RunningProcessInfo>>{};
      for (final target in targets) {
        individualResults[target] = await processManager.findProcessesForApp(
          appName: target.appName,
          exePath: target.exePath,
        );
      }

      // Query in batch
      final batchResults = await processManager.findProcessesForApps(targets);

      expect(batchResults.keys.length, equals(targets.length));

      for (final target in targets) {
        final individual = individualResults[target]!;
        final batch = batchResults[target]!;

        expect(
          batch.length,
          equals(individual.length),
          reason: 'Count for ${target.appName} must match',
        );

        for (int i = 0; i < batch.length; i++) {
          expect(batch[i].pid, equals(individual[i].pid));
          expect(batch[i].exePath, equals(individual[i].exePath));
          expect(batch[i].exeName, equals(individual[i].exeName));
        }
      }

      // Verify specific matches
      expect(batchResults[targets[0]]!.map((p) => p.pid), contains(101));
      expect(batchResults[targets[1]]!.map((p) => p.pid), contains(102));
      expect(batchResults[targets[2]]!.map((p) => p.pid), contains(103));
      expect(batchResults[targets[3]]!.map((p) => p.pid), contains(104));
      expect(batchResults[targets[4]], isEmpty);
    });

    // 2. Multiple blocked apps can be enforced in a single batch
    test('2. Multiple blocked apps are discovered and enforced in a single batch', () async {
      final fakeManager = FakeCountingProcessManager();
      fakeManager.processes.addAll([
        MockProcess(pid: 201, appName: 'Discord', exeName: 'Discord.exe', exePath: r'C:\Discord\Discord.exe', exitsOnGracefulClose: true),
        MockProcess(pid: 202, appName: 'Telegram', exeName: 'Telegram.exe', exePath: r'C:\Telegram\Telegram.exe', exitsOnGracefulClose: false),
        MockProcess(pid: 203, appName: 'Unrelated', exeName: 'Editor.exe', exePath: r'C:\Editor\Editor.exe'),
      ]);

      final enforcement = AppEnforcementService(
        processManager: fakeManager,
        gracePeriod: Duration.zero,
      );

      final blockedApps = [
        const FocusPresetBlockedApp(id: 1, presetId: 1, appName: 'Discord', exePath: r'C:\Discord\Discord.exe'),
        const FocusPresetBlockedApp(id: 2, presetId: 1, appName: 'Telegram', exePath: r'C:\Telegram\Telegram.exe'),
        const FocusPresetBlockedApp(id: 3, presetId: 1, appName: 'Steam', exePath: r'C:\Steam\steam.exe'),
      ];

      // Act: Enforce focus restrictions
      await enforcement.setFocusRestrictions(
        blockedApps: blockedApps,
        presetName: 'Deep Work',
        isEnforcing: true,
        closeRunningNow: true,
      );

      // Verify batch process lookup was used exactly ONCE instead of 3 sequential lookups
      expect(fakeManager.findProcessesForAppsCalls, equals(1));

      // Verify graceful close was sent to both running processes
      expect(fakeManager.gracefulCloseAttempts, containsAll([201, 202]));

      // Discord exited on graceful close, Telegram did not so Telegram was terminated
      expect(fakeManager.terminatedPids, contains(202));
      expect(fakeManager.terminatedPids, isNot(contains(201)));

      // Unrelated process was NOT touched
      expect(fakeManager.gracefulCloseAttempts, isNot(contains(203)));
      expect(fakeManager.terminatedPids, isNot(contains(203)));

      enforcement.dispose();
    });

    // 3. Focus Mode restrictions remain independent of daily limits
    test('3. Focus Mode restrictions remain completely independent of daily limits', () async {
      final fakeManager = FakeCountingProcessManager();
      final enforcement = AppEnforcementService(processManager: fakeManager);

      final dailyLimit = AppLimit(
        id: 1,
        appName: 'Browser',
        limitDuration: const Duration(hours: 1),
        isEnabled: true,
        isEnforced: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // 1. Exceed daily limit
      enforcement.evaluateEnforcements([dailyLimit], {'browser': const Duration(hours: 2)});
      expect(enforcement.isDailyLimitRestricted('Browser'), isTrue);
      expect(enforcement.isFocusRestricted('Browser'), isFalse);
      expect(enforcement.isAppRestricted('Browser'), isTrue);

      // 2. Start Focus Mode blocking 'Slack'
      await enforcement.setFocusRestrictions(
        blockedApps: [const FocusPresetBlockedApp(id: 1, presetId: 1, appName: 'Slack')],
        presetName: 'Sprint',
        isEnforcing: true,
        closeRunningNow: false,
      );

      expect(enforcement.isDailyLimitRestricted('Browser'), isTrue);
      expect(enforcement.isFocusRestricted('Slack'), isTrue);
      expect(enforcement.isFocusRestricted('Browser'), isFalse);
      expect(enforcement.restrictedApps, containsAll(['browser', 'slack']));

      // 3. Clear focus restrictions (e.g. session stopped)
      enforcement.clearFocusRestrictions();

      // Focus app is cleared
      expect(enforcement.isFocusRestricted('Slack'), isFalse);

      // Daily limit MUST remain strictly restricted!
      expect(enforcement.isDailyLimitRestricted('Browser'), isTrue);
      expect(enforcement.isAppRestricted('Browser'), isTrue);
      expect(enforcement.restrictedApps, contains('browser'));
      expect(enforcement.restrictedApps, isNot(contains('slack')));

      enforcement.dispose();
    });

    // 4. Break exemptions still work
    test('4. Break exemptions temporarily suspend focus restrictions while keeping daily limits active', () async {
      final fakeManager = FakeCountingProcessManager();
      final enforcement = AppEnforcementService(processManager: fakeManager);

      final focusService = FocusService(
        repository: repository,
        enforcementService: enforcement,
      );
      await focusService.init();

      // Configure preset with unblockDuringBreaks = true
      final preset = FocusPreset(
        id: 1,
        name: 'Work',
        focusDuration: const Duration(minutes: 25),
        shortBreakDuration: const Duration(minutes: 5),
        longBreakDuration: const Duration(minutes: 15),
        cyclesBeforeLongBreak: 4,
        unblockDuringBreaks: true,
        blockedApps: const [FocusPresetBlockedApp(id: 1, presetId: 1, appName: 'Steam')],
      );
      await focusService.selectPreset(preset);

      // Also set a daily limit for 'Discord'
      final limit = AppLimit(
        id: 1,
        appName: 'Discord',
        limitDuration: const Duration(minutes: 30),
        isEnabled: true,
        isEnforced: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      enforcement.evaluateEnforcements([limit], {'discord': const Duration(minutes: 45)});

      // Start focus session
      await focusService.start();
      expect(focusService.isRunning, isTrue);
      expect(enforcement.isFocusRestricted('Steam'), isTrue);
      expect(enforcement.isDailyLimitRestricted('Discord'), isTrue);

      // Transition to break
      focusService.skipToBreak();
      expect(focusService.sessionType, equals(FocusSessionType.breakSession));

      // Steam is exempt during break
      expect(enforcement.isFocusRestricted('Steam'), isFalse);

      // Discord (daily limit) REMAINS strictly restricted!
      expect(enforcement.isDailyLimitRestricted('Discord'), isTrue);
      expect(enforcement.isAppRestricted('Discord'), isTrue);

      focusService.dispose();
      enforcement.dispose();
    });

    // 5. Pausing and resuming Focus Mode correctly updates restrictions
    test('5. Pausing and resuming Focus Mode correctly updates and re-enforces restrictions', () async {
      final fakeManager = FakeCountingProcessManager();
      fakeManager.processes.add(
        MockProcess(pid: 301, appName: 'Game', exeName: 'Game.exe', exePath: r'C:\Games\Game.exe'),
      );

      final enforcement = AppEnforcementService(
        processManager: fakeManager,
        gracePeriod: Duration.zero,
      );

      final focusService = FocusService(
        repository: repository,
        enforcementService: enforcement,
      );
      await focusService.init();

      final preset = FocusPreset(
        id: 1,
        name: 'Study',
        focusDuration: const Duration(minutes: 25),
        blockedApps: const [FocusPresetBlockedApp(id: 1, presetId: 1, appName: 'Game')],
      );
      await focusService.selectPreset(preset);

      // Start focus
      await focusService.start();
      expect(focusService.isRunning, isTrue);
      expect(enforcement.isFocusRestricted('Game'), isTrue);

      // Pause focus
      await focusService.pause();
      expect(focusService.isPaused, isTrue);
      expect(enforcement.isFocusRestricted('Game'), isFalse);

      // User reopened Game while paused
      fakeManager.processes.add(
        MockProcess(pid: 302, appName: 'Game', exeName: 'Game.exe', exePath: r'C:\Games\Game.exe'),
      );

      // Resume focus
      await focusService.resume();
      expect(focusService.isRunning, isTrue);
      expect(enforcement.isFocusRestricted('Game'), isTrue);

      // Process 302 must be closed on resume
      expect(fakeManager.gracefulCloseAttempts, contains(302));

      focusService.dispose();
      enforcement.dispose();
    });

    // 6. Applications cannot bypass an active restriction by reopening
    test('6. Applications cannot bypass an active restriction by reopening', () async {
      final fakeManager = FakeCountingProcessManager();
      fakeManager.processes.add(
        MockProcess(pid: 401, appName: 'Twitter', exeName: 'Twitter.exe', exePath: r'C:\Apps\Twitter.exe'),
      );

      final enforcement = AppEnforcementService(
        processManager: fakeManager,
        gracePeriod: Duration.zero,
      );

      final blockedApps = [
        const FocusPresetBlockedApp(id: 1, presetId: 1, appName: 'Twitter', exePath: r'C:\Apps\Twitter.exe'),
      ];

      await enforcement.setFocusRestrictions(
        blockedApps: blockedApps,
        presetName: 'Deep Focus',
        isEnforcing: true,
        closeRunningNow: true,
      );

      expect(fakeManager.gracefulCloseAttempts, contains(401));

      // Simulate user immediately launching a new instance of Twitter (PID 402)
      fakeManager.processes.add(
        MockProcess(pid: 402, appName: 'Twitter', exeName: 'Twitter.exe', exePath: r'C:\Apps\Twitter.exe'),
      );

      final blockEvents = <AppBlockEvent>[];
      final subscription = enforcement.blockEvents.listen(blockEvents.add);

      // Window takes foreground
      await enforcement.onForegroundAppDetected(
        appName: 'Twitter',
        exePath: r'C:\Apps\Twitter.exe',
        limits: const [],
        todayUsage: Duration.zero,
      );

      // Must be intercepted, closed, and block event dispatched
      expect(fakeManager.gracefulCloseAttempts, contains(402));
      expect(blockEvents.length, equals(1));
      expect(blockEvents.first.appName, equals('Twitter'));
      expect(blockEvents.first.reason, equals(AppBlockReason.focusSession));

      await subscription.cancel();
      enforcement.dispose();
    });

    // 7. Protected or inaccessible processes remain safely handled
    test('7. Protected or inaccessible processes are never matched or terminated', () async {
      final mockPaths = {
        0: '',
        4: '',
        501: r'C:\Windows\explorer.exe',
        502: r'C:\Windows\System32\dwm.exe',
        503: r'C:\Program Files\Balance\balance.exe',
        504: r'C:\Tools\flutter_tester.exe',
        505: r'C:\Windows\System32\svchost.exe',
        506: '', // Inaccessible process
        507: r'C:\Apps\AllowedApp.exe',
      };

      bool terminateCalledOnProtected = false;

      final processManager = WindowsProcessManager(
        currentPidProvider: () => 9999,
        pidWindowsProvider: (selfPid) => {
          501: [],
          502: [],
          503: [],
          504: [],
          505: [],
          506: [],
          507: [],
        },
        processListProvider: () => [0, 4, 501, 502, 503, 504, 505, 506, 507, 9999],
        processPathProvider: (pid) => mockPaths[pid] ?? '',
        terminateProvider: (pid) {
          if (pid <= 4 || pid == 9999 || pid == 501 || pid == 502 || pid == 503 || pid == 504 || pid == 505) {
            terminateCalledOnProtected = true;
          }
          return true;
        },
      );

      final targets = [
        const TargetAppCriteria(appName: 'explorer', exePath: r'C:\Windows\explorer.exe'),
        const TargetAppCriteria(appName: 'dwm', exePath: r'C:\Windows\System32\dwm.exe'),
        const TargetAppCriteria(appName: 'balance', exePath: r'C:\Program Files\Balance\balance.exe'),
        const TargetAppCriteria(appName: 'svchost'),
        const TargetAppCriteria(appName: 'AllowedApp', exePath: r'C:\Apps\AllowedApp.exe'),
      ];

      final batch = await processManager.findProcessesForApps(targets);

      // Protected apps must NOT be returned in batch matching
      expect(batch[targets[0]], isEmpty, reason: 'explorer.exe must be protected');
      expect(batch[targets[1]], isEmpty, reason: 'dwm.exe must be protected');
      expect(batch[targets[2]], isEmpty, reason: 'balance.exe must be protected');
      expect(batch[targets[3]], isEmpty, reason: 'svchost.exe must be protected');

      // Only AllowedApp should match
      expect(batch[targets[4]]!.length, equals(1));
      expect(batch[targets[4]]!.first.pid, equals(507));

      // Attempting to terminate protected process must return false
      final terminatedExplorer = await processManager.terminateProcess(501);
      expect(terminatedExplorer, isFalse);
      expect(terminateCalledOnProtected, isFalse);

      final terminatedSelf = await processManager.terminateProcess(9999);
      expect(terminatedSelf, isFalse);
    });

    // 8. Native handles and buffers are cleaned up correctly where testable
    test('8. Process enumeration handles empty lists and provider exceptions safely', () async {
      final processManager = WindowsProcessManager(
        currentPidProvider: () => 1000,
        pidWindowsProvider: (selfPid) => throw Exception('Simulated EnumWindows error'),
        processListProvider: () => [1001, 1002],
        processPathProvider: (pid) => r'C:\Apps\SafeApp.exe',
      );

      // Should handle exception in pidWindows collection gracefully and return empty windows
      final result = await processManager.findProcessesForApps([
        const TargetAppCriteria(appName: 'SafeApp'),
      ]);

      expect(result.values.first.length, equals(2));
      expect(result.values.first.first.windowHandles, isEmpty);

      // Empty target list returns empty map immediately
      final emptyResult = await processManager.findProcessesForApps([]);
      expect(emptyResult, isEmpty);
    });
  });
}
