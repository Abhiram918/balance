import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balance/core/models/app_block_event.dart';
import 'package:balance/core/models/app_limit.dart';
import 'package:balance/core/models/focus_preset.dart';
import 'package:balance/core/models/focus_session.dart';
import 'package:balance/core/services/app_enforcement_service.dart';
import 'package:balance/core/services/focus_notification_service.dart';
import 'package:balance/core/services/focus_service.dart';
import 'package:balance/core/services/settings_service.dart';
import 'package:balance/core/services/usage_repository.dart';
import 'package:balance/core/services/windows_process_manager.dart';
import 'package:balance/core/widgets/app_block_dialog.dart';
import 'package:balance/app/theme/app_colors.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  bool _matches(MockProcess p, String appName, String? exePath) {
    if (exePath != null && exePath.trim().isNotEmpty) {
      if (p.exePath.toLowerCase() == exePath.trim().toLowerCase()) return true;
    }
    final cleanApp = appName.trim().toLowerCase();
    final pBase = p.exeName.toLowerCase().replaceAll('.exe', '');
    if (pBase == cleanApp || p.exeName.toLowerCase() == '$cleanApp.exe') return true;

    // Aliases
    if (cleanApp == 'google chrome' && pBase == 'chrome') return true;
    if (cleanApp == 'visual studio code' && pBase == 'code') return true;
    if (cleanApp == 'telegram desktop' && pBase == 'telegram') return true;
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

class FakeNotificationService extends FocusNotificationService {
  final List<String> sessionNotifications = [];
  final List<String> focusBlockedNotifications = [];
  final List<String> dailyLimitWarnings = [];
  final List<String> dailyLimitReached = [];

  FakeNotificationService({super.settingsService});

  @override
  Future<bool> notifySessionCompleted({
    required FocusSessionType type,
    required bool completedNaturally,
    bool soundEnabled = true,
  }) async {
    if (settingsService != null && !settingsService!.notifications) return false;
    sessionNotifications.add(type.name);
    return true;
  }

  @override
  Future<bool> notifyFocusAppBlocked({
    required String appName,
    String? presetName,
    bool soundEnabled = true,
  }) async {
    if (settingsService != null && !settingsService!.notifications) return false;
    focusBlockedNotifications.add(appName);
    return true;
  }

  @override
  Future<bool> notifyAppLimitWarning({
    required String appName,
    required Duration used,
    required Duration limit,
    required int warningPercentage,
  }) async {
    if (settingsService != null && !settingsService!.notifications) return false;
    dailyLimitWarnings.add(appName);
    return true;
  }

  @override
  Future<bool> notifyAppLimitReached({
    required String appName,
    required Duration used,
    required Duration limit,
  }) async {
    if (settingsService != null && !settingsService!.notifications) return false;
    dailyLimitReached.add(appName);
    return true;
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Phase 3 - Focus Mode Windows Application Blocking Tests', () {
    late Directory tempDir;
    late String dbPath;
    late UsageRepository repository;
    late FakeProcessManager processManager;
    late FakeNotificationService notificationService;
    late SettingsService settingsService;
    late AppEnforcementService enforcementService;
    late FocusService focusService;
    late DateTime simulatedTime;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('focus_enforcement_test_');
      dbPath = '${tempDir.path}${Platform.pathSeparator}test.db';
      repository = UsageRepository(databasePath: dbPath);
      await repository.initializeDatabase();

      simulatedTime = DateTime(2026, 10, 18, 10, 0, 0);

      settingsService = SettingsService(repository: repository);
      await settingsService.init();

      notificationService = FakeNotificationService(settingsService: settingsService);

      processManager = FakeProcessManager();
      enforcementService = AppEnforcementService(
        processManager: processManager,
        notificationService: notificationService,
        gracePeriod: Duration.zero,
        clock: () => simulatedTime,
      );

      focusService = FocusService(
        repository: repository,
        notificationService: notificationService,
        enforcementService: enforcementService,
        clock: () => simulatedTime,
      );
      await focusService.init();
    });

    tearDown(() async {
      focusService.dispose();
      enforcementService.dispose();
      await repository.close();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('1. Independent restriction sources: Focus session and daily limits operate independently', () async {
      // Create and enforce a daily limit on Telegram
      final dailyLimit = AppLimit(
        id: 1,
        appName: 'Telegram',
        exePath: r'C:\Telegram\Telegram.exe',
        limitDuration: const Duration(minutes: 30),
        isEnabled: true,
        isEnforced: true,
        createdAt: simulatedTime,
        updatedAt: simulatedTime,
      );

      await enforcementService.enforceLimit(dailyLimit);
      expect(enforcementService.isDailyLimitRestricted('Telegram'), isTrue);
      expect(enforcementService.isAppRestricted('Telegram'), isTrue);
      expect(enforcementService.dailyLimitRestrictedApps, contains('telegram'));

      // Create a Focus preset blocking Discord and Steam
      final focusPreset = await focusService.createPreset(
        name: 'Work Sprint',
        focusDuration: const Duration(minutes: 25),
        shortBreakDuration: const Duration(minutes: 5),
        blockedApps: [
          const FocusPresetBlockedApp(appName: 'Discord', exePath: r'C:\Discord\Discord.exe'),
          const FocusPresetBlockedApp(appName: 'Steam', exePath: r'C:\Steam\steam.exe'),
        ],
      );

      focusService.selectPreset(focusPreset);
      await focusService.start();

      // Focus restrictions are active alongside daily limit
      expect(enforcementService.isFocusEnforcing, isTrue);
      expect(enforcementService.isFocusRestricted('Discord'), isTrue);
      expect(enforcementService.isFocusRestricted('Steam'), isTrue);
      expect(enforcementService.isDailyLimitRestricted('Telegram'), isTrue);
      expect(enforcementService.isAppRestricted('Discord'), isTrue);
      expect(enforcementService.isAppRestricted('Steam'), isTrue);
      expect(enforcementService.isAppRestricted('Telegram'), isTrue);

      // Stopping focus session removes focus restrictions, daily limit remains 100% intact
      await focusService.stop();
      expect(enforcementService.isFocusEnforcing, isFalse);
      expect(enforcementService.isFocusRestricted('Discord'), isFalse);
      expect(enforcementService.isFocusRestricted('Steam'), isFalse);

      // Telegram MUST remain restricted by daily limit
      expect(enforcementService.isDailyLimitRestricted('Telegram'), isTrue);
      expect(enforcementService.isAppRestricted('Telegram'), isTrue);
      expect(enforcementService.dailyLimitRestrictedApps, contains('telegram'));
    });

    test('2. Independent restriction sources: Midnight reset clears daily limits while active focus restrictions persist', () async {
      final dailyLimit = AppLimit(
        id: 1,
        appName: 'Twitter',
        limitDuration: const Duration(minutes: 15),
        isEnabled: true,
        isEnforced: true,
        createdAt: simulatedTime,
        updatedAt: simulatedTime,
      );
      await enforcementService.enforceLimit(dailyLimit);

      final preset = await focusService.createPreset(
        name: 'Midnight Session',
        focusDuration: const Duration(minutes: 45),
        shortBreakDuration: const Duration(minutes: 5),
        blockedApps: [
          const FocusPresetBlockedApp(appName: 'YouTube', exePath: r'C:\Browser\chrome.exe'),
        ],
      );
      focusService.selectPreset(preset);
      await focusService.start();

      expect(enforcementService.isDailyLimitRestricted('Twitter'), isTrue);
      expect(enforcementService.isFocusRestricted('YouTube'), isTrue);

      // Advance clock past midnight (to next calendar day)
      simulatedTime = DateTime(2026, 10, 19, 0, 15, 0);

      // Daily limit for Twitter is reset
      expect(enforcementService.isDailyLimitRestricted('Twitter'), isFalse);
      // Active focus restriction on YouTube PERSISTS across midnight
      expect(enforcementService.isFocusRestricted('YouTube'), isTrue);
      expect(enforcementService.isAppRestricted('YouTube'), isTrue);
    });

    test('3. Per-preset blocked applications: Matching by name, exePath, and executable name', () async {
      final blocked = [
        const FocusPresetBlockedApp(appName: '  Visual Studio Code  ', exePath: r'C:\Apps\Code.exe'),
        const FocusPresetBlockedApp(appName: 'Spotify'),
      ];

      await enforcementService.setFocusRestrictions(
        blockedApps: blocked,
        presetName: 'Code Focus',
        isEnforcing: true,
        closeRunningNow: false,
      );

      // Matches by clean appName (case-insensitive & trimmed)
      expect(enforcementService.isFocusRestricted('visual studio code'), isTrue);
      expect(enforcementService.isFocusRestricted('VISUAL STUDIO CODE'), isTrue);
      expect(enforcementService.isFocusRestricted('spotify'), isTrue);

      // Matches by exePath
      expect(enforcementService.isFocusRestricted('Code', exePath: r'C:\Apps\Code.exe'), isTrue);

      // Matches by exeName
      expect(enforcementService.isFocusRestricted('Spotify', exePath: r'C:\Spotify\spotify.exe'), isTrue);

      // Does not match unrelated app
      expect(enforcementService.isFocusRestricted('Notepad', exePath: r'C:\Windows\notepad.exe'), isFalse);
    });

    test('4. Break policy: unblockDuringBreaks: true temporarily suspends focus restrictions during break', () async {
      final preset = await focusService.createPreset(
        name: 'Normal Pomodoro',
        focusDuration: const Duration(minutes: 25),
        shortBreakDuration: const Duration(minutes: 5),
        unblockDuringBreaks: true,
        autoStartBreaks: true,
        blockedApps: [
          const FocusPresetBlockedApp(appName: 'Discord', exePath: r'C:\Discord\Discord.exe'),
        ],
      );

      focusService.selectPreset(preset);
      await focusService.start();

      // Focus phase: Discord restricted
      expect(focusService.sessionType, FocusSessionType.focus);
      expect(focusService.shouldEnforceFocusRestrictions, isTrue);
      expect(enforcementService.isFocusRestricted('Discord'), isTrue);

      // Advance clock by 25 minutes to complete focus phase naturally
      simulatedTime = simulatedTime.add(const Duration(minutes: 25));
      focusService.tick();
      await focusService.pendingDbOp;

      // Now in Break phase: unblockDuringBreaks is true -> restrictions SUSPENDED
      expect(focusService.sessionType, FocusSessionType.breakSession);
      expect(focusService.shouldEnforceFocusRestrictions, isFalse);
      expect(enforcementService.isFocusEnforcing, isFalse);
      expect(enforcementService.isFocusRestricted('Discord'), isFalse);

      // Advance clock by 5 minutes to complete break phase naturally (with autoStartFocus: false)
      simulatedTime = simulatedTime.add(const Duration(minutes: 5));
      focusService.tick();
      await focusService.pendingDbOp;

      // Now start next focus cycle
      await focusService.startNextPhase();
      expect(focusService.sessionType, FocusSessionType.focus);
      expect(focusService.shouldEnforceFocusRestrictions, isTrue);
      expect(enforcementService.isFocusRestricted('Discord'), isTrue);
    });

    test('5. Break policy: unblockDuringBreaks: false continues enforcing focus restrictions during break', () async {
      final preset = await focusService.createPreset(
        name: 'Strict Focus',
        focusDuration: const Duration(minutes: 25),
        shortBreakDuration: const Duration(minutes: 5),
        unblockDuringBreaks: false, // Apps stay blocked during breaks
        autoStartBreaks: true,
        blockedApps: [
          const FocusPresetBlockedApp(appName: 'Gaming', exePath: r'C:\Games\game.exe'),
        ],
      );

      focusService.selectPreset(preset);
      await focusService.start();

      expect(focusService.sessionType, FocusSessionType.focus);
      expect(enforcementService.isFocusRestricted('Gaming'), isTrue);

      // Advance clock to trigger break
      simulatedTime = simulatedTime.add(const Duration(minutes: 25));
      focusService.tick();
      await focusService.pendingDbOp;

      // In break phase: unblockDuringBreaks is false -> restrictions REMAIN ACTIVE
      expect(focusService.sessionType, FocusSessionType.breakSession);
      expect(focusService.shouldEnforceFocusRestrictions, isTrue);
      expect(enforcementService.isFocusEnforcing, isTrue);
      expect(enforcementService.isFocusRestricted('Gaming'), isTrue);
    });

    test('6. Session lifecycle transitions: pause, resume, stop, reset, skipBreak, and restart', () async {
      final preset = await focusService.createPreset(
        name: 'Cycle Ops',
        focusDuration: const Duration(minutes: 25),
        shortBreakDuration: const Duration(minutes: 5),
        unblockDuringBreaks: true,
        blockedApps: [
          const FocusPresetBlockedApp(appName: 'Reddit'),
        ],
      );

      focusService.selectPreset(preset);
      await focusService.start();
      expect(enforcementService.isFocusRestricted('Reddit'), isTrue);

      // Pause suspends focus restrictions
      await focusService.pause();
      expect(focusService.isPaused, isTrue);
      expect(focusService.shouldEnforceFocusRestrictions, isFalse);
      expect(enforcementService.isFocusRestricted('Reddit'), isFalse);

      // Resume restores focus restrictions
      await focusService.resume();
      expect(focusService.isRunning, isTrue);
      expect(focusService.shouldEnforceFocusRestrictions, isTrue);
      expect(enforcementService.isFocusRestricted('Reddit'), isTrue);

      // Restart current phase preserves restrictions
      await focusService.restartCurrentPhase();
      expect(focusService.isRunning, isTrue);
      expect(enforcementService.isFocusRestricted('Reddit'), isTrue);

      // Reset clears restrictions
      await focusService.reset();
      expect(focusService.isIdle, isTrue);
      expect(enforcementService.isFocusRestricted('Reddit'), isFalse);
      expect(enforcementService.isFocusEnforcing, isFalse);
    });

    test('7. Running session snapshot isolation: Modifying or deleting preset while running preserves active blocked apps', () async {
      final preset = await focusService.createPreset(
        name: 'Snapshot Test',
        focusDuration: const Duration(minutes: 25),
        shortBreakDuration: const Duration(minutes: 5),
        blockedApps: [
          const FocusPresetBlockedApp(appName: 'OriginalBlockedApp'),
        ],
      );

      focusService.selectPreset(preset);
      await focusService.start();
      expect(focusService.activeBlockedApps.length, equals(1));
      expect(focusService.activeBlockedApps.first.appName, equals('OriginalBlockedApp'));
      expect(enforcementService.isFocusRestricted('OriginalBlockedApp'), isTrue);

      // Update preset in database to block a different app
      final updatedPreset = preset.copyWith(
        blockedApps: [
          const FocusPresetBlockedApp(appName: 'NewBlockedApp'),
        ],
      );
      await focusService.updatePreset(updatedPreset);

      // Running session retains its snapshotted blocked apps!
      expect(focusService.activeBlockedApps.length, equals(1));
      expect(focusService.activeBlockedApps.first.appName, equals('OriginalBlockedApp'));
      expect(enforcementService.isFocusRestricted('OriginalBlockedApp'), isTrue);
      expect(enforcementService.isFocusRestricted('NewBlockedApp'), isFalse);

      await focusService.stop();
    });

    test('8. Process close: Starting focus session closes already running instances of blocked apps', () async {
      // Mock two running processes for Discord
      final p1 = MockProcess(
        pid: 3001,
        appName: 'Discord',
        exeName: 'Discord.exe',
        exePath: r'C:\Discord\Discord.exe',
      );
      final p2 = MockProcess(
        pid: 3002,
        appName: 'Discord',
        exeName: 'Discord.exe',
        exePath: r'C:\Discord\Discord.exe',
      );
      processManager.processes.addAll([p1, p2]);

      final preset = await focusService.createPreset(
        name: 'Auto Close',
        focusDuration: const Duration(minutes: 25),
        shortBreakDuration: const Duration(minutes: 5),
        blockedApps: [
          const FocusPresetBlockedApp(appName: 'Discord', exePath: r'C:\Discord\Discord.exe'),
        ],
      );

      focusService.selectPreset(preset);
      await focusService.start();

      // Starting session must have closed both processes
      expect(processManager.gracefulCloseAttempts, containsAll([3001, 3002]));
      expect(p1.isAlive, isFalse);
      expect(p2.isAlive, isFalse);
    });

    test('9. Foreground detection and notification deduplication: Throttles repeat notifications within 30s', () async {
      final preset = await focusService.createPreset(
        name: 'Notif Throttle',
        focusDuration: const Duration(minutes: 25),
        shortBreakDuration: const Duration(minutes: 5),
        blockedApps: [
          const FocusPresetBlockedApp(appName: 'Telegram', exePath: r'C:\Telegram\Telegram.exe'),
        ],
      );

      focusService.selectPreset(preset);
      await focusService.start();

      // User attempts to open Telegram 4 times in rapid succession (simulating polling ticks)
      for (int i = 0; i < 4; i++) {
        simulatedTime = simulatedTime.add(const Duration(seconds: 2));
        await enforcementService.onForegroundAppDetected(
          appName: 'Telegram',
          exePath: r'C:\Telegram\Telegram.exe',
          limits: const [],
          todayUsage: Duration.zero,
        );
      }

      // Exactly ONE desktop notification toast dispatched despite 4 reopen attempts
      expect(notificationService.focusBlockedNotifications.length, equals(1));
      expect(notificationService.focusBlockedNotifications.first, equals('Telegram'));

      // Advance clock past the 30-second throttle cooldown
      simulatedTime = simulatedTime.add(const Duration(seconds: 35));

      // User attempts to open Telegram again after cooldown
      await enforcementService.onForegroundAppDetected(
        appName: 'Telegram',
        exePath: r'C:\Telegram\Telegram.exe',
        limits: const [],
        todayUsage: Duration.zero,
      );

      // Second notification is now allowed
      expect(notificationService.focusBlockedNotifications.length, equals(2));
    });

    test('10. Global notification toggle suppresses focus blocked notifications', () async {
      // Disable notifications globally in settings
      await settingsService.setNotifications(false);

      final preset = await focusService.createPreset(
        name: 'Silent Preset',
        focusDuration: const Duration(minutes: 25),
        shortBreakDuration: const Duration(minutes: 5),
        blockedApps: [
          const FocusPresetBlockedApp(appName: 'Slack'),
        ],
      );

      focusService.selectPreset(preset);
      await focusService.start();

      await enforcementService.onForegroundAppDetected(
        appName: 'Slack',
        exePath: r'C:\Slack\slack.exe',
        limits: const [],
        todayUsage: Duration.zero,
      );

      // Desktop notifications suppressed because global notification setting is off
      expect(notificationService.focusBlockedNotifications, isEmpty);
    });

    test('11. Crash / Restart Recovery: Restoring running focus session reinstates enforcement', () async {
      final preset = await focusService.createPreset(
        name: 'Crash Recovery',
        focusDuration: const Duration(minutes: 25),
        shortBreakDuration: const Duration(minutes: 5),
        blockedApps: [
          const FocusPresetBlockedApp(appName: 'Steam', exePath: r'C:\Steam\steam.exe'),
        ],
      );

      // Simulate active session in SQLite before restart
      final active = ActiveFocusState(
        type: FocusSessionType.focus,
        status: FocusStatus.running,
        targetDuration: const Duration(minutes: 25),
        startTime: simulatedTime,
        expectedEndTime: simulatedTime.add(const Duration(minutes: 25)),
        remainingDuration: const Duration(minutes: 25),
        presetId: preset.id,
        presetName: preset.name,
        currentCycle: 1,
        totalCycles: 4,
        isLongBreak: false,
        lastTickTime: simulatedTime,
      );
      await repository.saveActiveFocusState(active);

      // Re-initialize FocusService (simulating Balance app launch)
      final newEnforcement = AppEnforcementService(
        processManager: processManager,
        notificationService: notificationService,
        gracePeriod: Duration.zero,
        clock: () => simulatedTime,
      );
      final newFocusService = FocusService(
        repository: repository,
        notificationService: notificationService,
        enforcementService: newEnforcement,
        clock: () => simulatedTime,
      );

      await newFocusService.init();

      // State is restored to running, and focus restrictions are active!
      expect(newFocusService.status, FocusStatus.running);
      expect(newEnforcement.isFocusEnforcing, isTrue);
      expect(newEnforcement.isFocusRestricted('Steam'), isTrue);

      newFocusService.dispose();
      newEnforcement.dispose();
    });

    test('12. Crash / Restart Recovery: Restoring paused session leaves focus enforcement inactive', () async {
      final preset = await focusService.createPreset(
        name: 'Paused Recovery',
        focusDuration: const Duration(minutes: 25),
        shortBreakDuration: const Duration(minutes: 5),
        blockedApps: [
          const FocusPresetBlockedApp(appName: 'Steam'),
        ],
      );

      final active = ActiveFocusState(
        type: FocusSessionType.focus,
        status: FocusStatus.paused,
        targetDuration: const Duration(minutes: 25),
        startTime: simulatedTime,
        expectedEndTime: simulatedTime.add(const Duration(minutes: 25)),
        remainingDuration: const Duration(minutes: 15),
        presetId: preset.id,
        presetName: preset.name,
        currentCycle: 1,
        totalCycles: 4,
        isLongBreak: false,
        lastTickTime: simulatedTime,
      );
      await repository.saveActiveFocusState(active);

      final newEnforcement = AppEnforcementService(
        processManager: processManager,
        notificationService: notificationService,
        gracePeriod: Duration.zero,
        clock: () => simulatedTime,
      );
      final newFocusService = FocusService(
        repository: repository,
        notificationService: notificationService,
        enforcementService: newEnforcement,
        clock: () => simulatedTime,
      );

      await newFocusService.init();

      // Paused session does NOT enforce restrictions
      expect(newFocusService.status, FocusStatus.paused);
      expect(newEnforcement.isFocusEnforcing, isFalse);
      expect(newEnforcement.isFocusRestricted('Steam'), isFalse);

      newFocusService.dispose();
      newEnforcement.dispose();
    });

    testWidgets('13. User feedback dialog: Focus block event displays distinguishable Focus dialog', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool dismissed = false;
      final focusEvent = AppBlockEvent(
        appName: 'Discord',
        exePath: r'C:\Discord\Discord.exe',
        reason: AppBlockReason.focusSession,
        focusPresetName: 'Deep Work',
        remainingFocusDuration: const Duration(minutes: 20),
        resetTime: simulatedTime.add(const Duration(minutes: 20)),
        timestamp: simulatedTime,
      );

      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          extensions: [AppThemeColors.dark],
        ),
        home: Scaffold(
          body: AppBlockDialog(
            event: focusEvent,
            onDismiss: () => dismissed = true,
          ),
        ),
      ));
      await tester.pump();

      // Verify Focus Mode specific UI
      expect(find.byType(AppBlockDialog), findsOneWidget);
      expect(find.text('Focus mode restriction'), findsOneWidget);
      expect(find.text('Discord is blocked during your active focus session (Deep Work). Stay in the zone!'), findsOneWidget);
      expect(find.text('Focus preset:'), findsOneWidget);
      expect(find.text('Deep Work'), findsOneWidget);
      expect(find.text('Remaining focus:'), findsOneWidget);
      expect(find.text('20m'), findsOneWidget);
      expect(find.text('Unblocks when focus session ends'), findsOneWidget);

      await tester.tap(find.byKey(const Key('block_dialog_got_it_button')));
      await tester.pump();
      expect(dismissed, isTrue);
    });

    testWidgets('14. User feedback dialog: Daily limit event displays distinguishable Daily Limit dialog', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool dismissed = false;
      final dailyEvent = AppBlockEvent(
        appName: 'YouTube',
        exePath: r'C:\Browser\chrome.exe',
        reason: AppBlockReason.dailyLimit,
        limitDuration: const Duration(hours: 1),
        usedDuration: const Duration(hours: 1, minutes: 10),
        resetTime: DateTime(2026, 10, 19, 0, 0),
        timestamp: simulatedTime,
      );

      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          extensions: [AppThemeColors.dark],
        ),
        home: Scaffold(
          body: AppBlockDialog(
            event: dailyEvent,
            onDismiss: () => dismissed = true,
          ),
        ),
      ));
      await tester.pump();

      // Verify Daily Limit specific UI
      expect(find.text('Daily limit reached'), findsOneWidget);
      expect(find.text("You've reached your daily limit for YouTube. You can't access this app again until your daily limit resets."), findsOneWidget);
      expect(find.text('Daily limit:'), findsOneWidget);
      expect(find.text('1h'), findsOneWidget);
      expect(find.text('Used today:'), findsOneWidget);
      expect(find.text('1h 10m'), findsOneWidget);
      expect(find.text('Resets at midnight (12:00 AM)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('block_dialog_got_it_button')));
      await tester.pump();
      expect(dismissed, isTrue);
    });
  });
}
