import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:balance/core/models/focus_preset.dart';
import 'package:balance/core/models/focus_session.dart';
import 'package:balance/core/services/focus_notification_service.dart';
import 'package:balance/core/services/focus_service.dart';
import 'package:balance/core/services/settings_service.dart';
import 'package:balance/core/services/usage_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockNotificationService extends FocusNotificationService {
  int notifyCount = 0;
  FocusSessionType? lastType;
  bool? lastCompletedNaturally;
  bool? lastSoundEnabled;

  MockNotificationService({super.settingsService});

  @override
  Future<bool> notifySessionCompleted({
    required FocusSessionType type,
    required bool completedNaturally,
    bool soundEnabled = true,
  }) async {
    if (settingsService != null && !settingsService!.notifications) {
      return false;
    }
    notifyCount++;
    lastType = type;
    lastCompletedNaturally = completedNaturally;
    lastSoundEnabled = soundEnabled;
    return true;
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('FocusService Phase 2 - Custom Presets and Pomodoro Cycle Engine Tests', () {
    late Directory tempDir;
    late String dbPath;
    late UsageRepository repository;
    late DateTime simulatedTime;
    late MockNotificationService notificationService;

    DateTime clock() => simulatedTime;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pomodoro_test_');
      dbPath = '${tempDir.path}${Platform.pathSeparator}test_pomodoro.db';
      repository = UsageRepository(dbName: dbPath);
      simulatedTime = DateTime(2026, 10, 18, 9, 0, 0);
      notificationService = MockNotificationService();
    });

    tearDown(() async {
      await repository.close();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('Default presets are seeded on init and not duplicated across multiple inits', () async {
      final service1 = FocusService(
        repository: repository,
        notificationService: notificationService,
        clock: clock,
      );
      await service1.init();

      expect(service1.presets.length, equals(3));
      final names1 = service1.presets.map((p) => p.name).toList();
      expect(names1, containsAll(['Standard Pomodoro', 'Deep Work', 'Quick Sprint']));
      expect(service1.selectedPreset, isNotNull);
      expect(service1.selectedPreset!.name, equals('Standard Pomodoro'));
      service1.dispose();

      // Second init on same database
      final service2 = FocusService(
        repository: repository,
        notificationService: notificationService,
        clock: clock,
      );
      await service2.init();

      expect(service2.presets.length, equals(3));
      service2.dispose();
    });

    test('Creating custom preset validates input and rejects duplicate names case-insensitively', () async {
      final service = FocusService(repository: repository, clock: clock);
      await service.init();

      // 1. Invalid duration
      expect(
        () => service.createPreset(
          FocusPreset(
            name: 'Zero Focus',
            focusDuration: Duration.zero,
            shortBreakDuration: const Duration(minutes: 5),
            longBreakDuration: const Duration(minutes: 15),
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );

      // 2. Empty name
      expect(
        () => service.createPreset(
          FocusPreset(
            name: '   ',
            focusDuration: const Duration(minutes: 25),
            shortBreakDuration: const Duration(minutes: 5),
            longBreakDuration: const Duration(minutes: 15),
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );

      // 3. Duplicate name matching built-in preset with different casing and whitespace
      expect(
        () => service.createPreset(
          FocusPreset(
            name: '  standard pomodoro  ',
            focusDuration: const Duration(minutes: 30),
            shortBreakDuration: const Duration(minutes: 5),
            longBreakDuration: const Duration(minutes: 15),
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );

      // 4. Valid custom preset with blocked apps
      final custom = FocusPreset(
        name: 'Coding Intensive',
        focusDuration: const Duration(minutes: 45),
        shortBreakDuration: const Duration(minutes: 7),
        longBreakDuration: const Duration(minutes: 25),
        cyclesBeforeLongBreak: 3,
        autoStartBreaks: true,
        autoStartFocus: false,
        allowSkipBreak: true,
        soundEnabled: true,
        unblockDuringBreaks: true,
        blockedApps: const [
          FocusPresetBlockedApp(appName: 'Discord', exePath: r'C:\Discord.exe'),
          FocusPresetBlockedApp(appName: 'Steam', exePath: r'C:\Steam.exe'),
        ],
      );

      final created = await service.createPreset(custom);
      expect(created.id, isNotNull);
      expect(service.presets.length, equals(4));

      // Selecting custom preset updates target durations and cycles
      await service.selectPreset(created);
      expect(service.selectedPreset!.name, equals('Coding Intensive'));
      expect(service.targetDuration, equals(const Duration(minutes: 45)));
      expect(service.totalCycles, equals(3));
      expect(service.autoStartBreaks, isTrue);

      service.dispose();
    });

    test('Duplicating and editing a preset works cleanly and preserves settings', () async {
      final service = FocusService(repository: repository, clock: clock);
      await service.init();

      final standard = service.presets.firstWhere((p) => p.name == 'Standard Pomodoro');
      final duplicate = await service.duplicatePreset(standard);

      expect(duplicate.name, equals('Standard Pomodoro (Copy)'));
      expect(duplicate.focusDuration, equals(const Duration(minutes: 25)));
      expect(duplicate.isDefault, isFalse);
      expect(service.presets.length, equals(4));

      // Update duplicate
      final updated = duplicate.copyWith(
        name: 'Custom Pomodoro',
        focusDuration: const Duration(minutes: 30),
        shortBreakDuration: const Duration(minutes: 6),
      );
      await service.updatePreset(updated);

      final found = service.presets.firstWhere((p) => p.id == duplicate.id);
      expect(found.name, equals('Custom Pomodoro'));
      expect(found.focusDuration, equals(const Duration(minutes: 30)));
      expect(found.shortBreakDuration, equals(const Duration(minutes: 6)));

      service.dispose();
    });

    test('Built-in system presets cannot be deleted, but custom presets can', () async {
      final service = FocusService(repository: repository, clock: clock);
      await service.init();

      final deepWork = service.presets.firstWhere((p) => p.name == 'Deep Work');

      // Attempt deleting built-in preset throws StateError
      expect(
        () => service.deletePreset(deepWork.id!),
        throwsA(isA<StateError>()),
      );

      // Create and delete a custom preset
      final tempPreset = await service.createPreset(
        FocusPreset(
          name: 'Temporary Sprint',
          focusDuration: const Duration(minutes: 10),
          shortBreakDuration: const Duration(minutes: 2),
          longBreakDuration: const Duration(minutes: 5),
        ),
      );
      expect(service.presets.length, equals(4));

      await service.deletePreset(tempPreset.id!);
      expect(service.presets.length, equals(3));
      expect(service.presets.any((p) => p.name == 'Temporary Sprint'), isFalse);

      service.dispose();
    });

    test('Editing or deleting a preset does not mutate an active running session', () async {
      final service = FocusService(repository: repository, clock: clock);
      await service.init();

      final custom = await service.createPreset(
        FocusPreset(
          name: 'Test Preset',
          focusDuration: const Duration(minutes: 20),
          shortBreakDuration: const Duration(minutes: 5),
          longBreakDuration: const Duration(minutes: 15),
        ),
      );

      await service.selectPreset(custom);
      await service.start();

      expect(service.status, equals(FocusStatus.running));
      expect(service.targetDuration, equals(const Duration(minutes: 20)));

      // Selecting preset during active session throws StateError
      expect(
        () => service.selectPreset(service.presets.first),
        throwsA(isA<StateError>()),
      );

      // Editing preset in background
      await service.updatePreset(
        custom.copyWith(
          focusDuration: const Duration(minutes: 50),
        ),
      );

      // Running session retains its snapshotted 20 min duration
      expect(service.targetDuration, equals(const Duration(minutes: 20)));
      expect(service.remainingDuration, equals(const Duration(minutes: 20)));

      await service.stop();
      service.dispose();
    });

    test('Pomodoro cycles advance through short breaks and trigger long break on target cycle', () async {
      final service = FocusService(
        repository: repository,
        notificationService: notificationService,
        clock: clock,
      );
      await service.init();

      // Create preset: 2 cycles before long break, manual transitions
      final preset = await service.createPreset(
        FocusPreset(
          name: 'Two Cycle Pomodoro',
          focusDuration: const Duration(minutes: 25),
          shortBreakDuration: const Duration(minutes: 5),
          longBreakDuration: const Duration(minutes: 15),
          cyclesBeforeLongBreak: 2,
          autoStartBreaks: false,
          autoStartFocus: false,
        ),
      );

      await service.selectPreset(preset);

      // --- Cycle 1: Focus ---
      expect(service.currentCycle, equals(1));
      expect(service.totalCycles, equals(2));
      expect(service.sessionType, equals(FocusSessionType.focus));

      await service.start();
      simulatedTime = simulatedTime.add(const Duration(minutes: 25, seconds: 1));
      service.tick();
      await service.pendingDbOp;

      // Focus 1 completed -> Next is short break
      expect(service.status, equals(FocusStatus.completed));
      expect(service.remainingDuration, equals(Duration.zero));
      expect(service.currentCycle, equals(1));
      expect(service.isLongBreak, isFalse);

      // Start short break 1
      await service.startNextPhase();
      expect(service.status, equals(FocusStatus.running));
      expect(service.sessionType, equals(FocusSessionType.breakSession));
      expect(service.targetDuration, equals(const Duration(minutes: 5)));
      expect(service.isLongBreak, isFalse);

      simulatedTime = simulatedTime.add(const Duration(minutes: 5, seconds: 1));
      service.tick();
      await service.pendingDbOp;

      // Short break 1 completed -> Ready for Focus 2
      expect(service.status, equals(FocusStatus.completed));

      // --- Cycle 2: Focus ---
      await service.startNextPhase();
      expect(service.currentCycle, equals(2));
      expect(service.sessionType, equals(FocusSessionType.focus));
      expect(service.targetDuration, equals(const Duration(minutes: 25)));

      simulatedTime = simulatedTime.add(const Duration(minutes: 25, seconds: 1));
      service.tick();
      await service.pendingDbOp;

      // Focus 2 completed -> Reached cyclesBeforeLongBreak (2) -> Long break is next!
      expect(service.status, equals(FocusStatus.completed));
      expect(service.currentCycle, equals(2));
      expect(service.isLongBreak, isTrue);

      // Start long break
      await service.startNextPhase();
      expect(service.sessionType, equals(FocusSessionType.breakSession));
      expect(service.targetDuration, equals(const Duration(minutes: 15)));
      expect(service.isLongBreak, isTrue);

      simulatedTime = simulatedTime.add(const Duration(minutes: 15, seconds: 1));
      service.tick();
      await service.pendingDbOp;

      // Long break completed -> Resets cycle counter to 1
      expect(service.status, equals(FocusStatus.completed));
      expect(service.currentCycle, equals(1));
      expect(service.isLongBreak, isFalse);

      service.dispose();
    });

    test('Automatic transitions start next phase immediately when configured', () async {
      final service = FocusService(
        repository: repository,
        notificationService: notificationService,
        clock: clock,
      );
      await service.init();

      final autoPreset = await service.createPreset(
        FocusPreset(
          name: 'Auto Flow',
          focusDuration: const Duration(minutes: 20),
          shortBreakDuration: const Duration(minutes: 5),
          longBreakDuration: const Duration(minutes: 15),
          cyclesBeforeLongBreak: 3,
          autoStartBreaks: true,
          autoStartFocus: true,
        ),
      );

      await service.selectPreset(autoPreset);
      await service.start();
      expect(service.sessionType, equals(FocusSessionType.focus));
      expect(service.status, equals(FocusStatus.running));

      // Finish focus naturally
      simulatedTime = simulatedTime.add(const Duration(minutes: 20, seconds: 1));
      service.tick();
      await service.pendingDbOp;

      // Automatically transitions to running break
      expect(service.status, equals(FocusStatus.running));
      expect(service.sessionType, equals(FocusSessionType.breakSession));
      expect(service.targetDuration, equals(const Duration(minutes: 5)));

      // Finish break naturally
      simulatedTime = simulatedTime.add(const Duration(minutes: 5, seconds: 1));
      service.tick();
      await service.pendingDbOp;

      // Automatically transitions to running focus cycle 2
      expect(service.status, equals(FocusStatus.running));
      expect(service.sessionType, equals(FocusSessionType.focus));
      expect(service.currentCycle, equals(2));
      expect(service.targetDuration, equals(const Duration(minutes: 20)));

      await service.stop();
      service.dispose();
    });

    test('Skipping break advances to next focus cycle and honors allowSkipBreak flag', () async {
      final service = FocusService(repository: repository, clock: clock);
      await service.init();

      // 1. Preset with allowSkipBreak: true
      final allowSkipPreset = await service.createPreset(
        FocusPreset(
          name: 'Flexible Breaks',
          focusDuration: const Duration(minutes: 25),
          shortBreakDuration: const Duration(minutes: 5),
          longBreakDuration: const Duration(minutes: 15),
          cyclesBeforeLongBreak: 4,
          allowSkipBreak: true,
        ),
      );

      await service.selectPreset(allowSkipPreset);
      await service.setSessionType(FocusSessionType.breakSession);
      expect(service.canSkipBreak, isTrue);

      await service.start();
      expect(service.sessionType, equals(FocusSessionType.breakSession));

      // Skip break
      await service.skipBreak();
      expect(service.status, equals(FocusStatus.idle));
      expect(service.sessionType, equals(FocusSessionType.focus));
      expect(service.currentCycle, equals(2)); // Advanced to cycle 2

      // 2. Preset with allowSkipBreak: false
      final strictPreset = await service.createPreset(
        FocusPreset(
          name: 'Strict Breaks',
          focusDuration: const Duration(minutes: 25),
          shortBreakDuration: const Duration(minutes: 5),
          longBreakDuration: const Duration(minutes: 15),
          allowSkipBreak: false,
        ),
      );

      await service.selectPreset(strictPreset);
      await service.setSessionType(FocusSessionType.breakSession);
      expect(service.canSkipBreak, isFalse);

      expect(
        () => service.skipBreak(),
        throwsA(isA<StateError>()),
      );

      service.dispose();
    });

    test('Pause, resume, and stop during break accurately accounting for break duration', () async {
      final service = FocusService(repository: repository, clock: clock);
      await service.init();
      await service.setSessionType(FocusSessionType.breakSession);
      await service.start();

      expect(service.status, equals(FocusStatus.running));

      // Advance 2 minutes into break
      simulatedTime = simulatedTime.add(const Duration(minutes: 2));
      await service.pause();
      expect(service.status, equals(FocusStatus.paused));
      expect(service.remainingDuration, equals(const Duration(minutes: 3)));

      // Advance 10 minutes while paused
      simulatedTime = simulatedTime.add(const Duration(minutes: 10));

      await service.resume();
      expect(service.status, equals(FocusStatus.running));
      expect(service.remainingDuration, equals(const Duration(minutes: 3)));

      // Run for 1 more minute and stop early
      simulatedTime = simulatedTime.add(const Duration(minutes: 1));
      await service.stop();

      expect(service.status, equals(FocusStatus.idle));
      expect(service.recentSessions.length, equals(1));

      final breakRecord = service.recentSessions.first;
      expect(breakRecord.type, equals(FocusSessionType.breakSession));
      // Planned: 5 min, Actual: 3 min (excluding the 10 min pause)
      expect(breakRecord.actualDuration, equals(const Duration(minutes: 3)));
      expect(breakRecord.completedNaturally, isFalse);

      service.dispose();
    });

    test('Active Pomodoro state survives app restart and is recovered accurately', () async {
      final service1 = FocusService(repository: repository, clock: clock);
      await service1.init();

      final custom = await service1.createPreset(
        FocusPreset(
          name: 'Resilient Flow',
          focusDuration: const Duration(minutes: 35),
          shortBreakDuration: const Duration(minutes: 6),
          longBreakDuration: const Duration(minutes: 18),
          cyclesBeforeLongBreak: 3,
        ),
      );

      await service1.selectPreset(custom);
      await service1.start();

      // Advance 10 minutes
      simulatedTime = simulatedTime.add(const Duration(minutes: 10));
      await service1.pause();
      await service1.pendingDbOp;

      // Close service without calling stop
      service1.dispose();

      // Simulate app restart by initializing fresh FocusService
      final service2 = FocusService(repository: repository, clock: clock);
      await service2.init();

      expect(service2.status, equals(FocusStatus.paused));
      expect(service2.targetDuration, equals(const Duration(minutes: 35)));
      expect(service2.remainingDuration, equals(const Duration(minutes: 25)));
      expect(service2.currentCycle, equals(1));
      expect(service2.totalCycles, equals(3));
      expect(service2.isLongBreak, isFalse);

      // Resume and complete
      await service2.resume();
      simulatedTime = simulatedTime.add(const Duration(minutes: 25, seconds: 1));
      service2.tick();
      await service2.pendingDbOp;

      expect(service2.status, equals(FocusStatus.completed));
      expect(service2.recentSessions.length, equals(1));
      expect(service2.recentSessions.first.completedNaturally, isTrue);
      expect(service2.recentSessions.first.presetName, equals('Resilient Flow'));

      service2.dispose();
    });

    test('Sound and notifications respect preset soundEnabled and user settings', () async {
      final settingsService = SettingsService(repository: repository);
      await settingsService.init();
      await settingsService.setNotifications(true);

      final notifService = MockNotificationService(settingsService: settingsService);

      final service = FocusService(
        repository: repository,
        notificationService: notifService,
        clock: clock,
      );
      await service.init();

      // 1. Preset with soundEnabled: false
      final silentPreset = await service.createPreset(
        FocusPreset(
          name: 'Silent Work',
          focusDuration: const Duration(minutes: 25),
          shortBreakDuration: const Duration(minutes: 5),
          longBreakDuration: const Duration(minutes: 15),
          soundEnabled: false,
        ),
      );

      await service.selectPreset(silentPreset);
      await service.start();

      simulatedTime = simulatedTime.add(const Duration(minutes: 25, seconds: 1));
      service.tick();
      await service.pendingDbOp;

      expect(service.status, equals(FocusStatus.completed));
      // Notification sound was suppressed
      expect(notifService.notifyCount, equals(0));

      // 2. Preset with soundEnabled: true
      final audiblePreset = await service.createPreset(
        FocusPreset(
          name: 'Audible Work',
          focusDuration: const Duration(minutes: 25),
          shortBreakDuration: const Duration(minutes: 5),
          longBreakDuration: const Duration(minutes: 15),
          soundEnabled: true,
        ),
      );

      await service.selectPreset(audiblePreset);
      await service.start();

      simulatedTime = simulatedTime.add(const Duration(minutes: 25, seconds: 1));
      service.tick();
      await service.pendingDbOp;

      expect(notifService.notifyCount, equals(1));
      expect(notifService.lastSoundEnabled, isTrue);

      // 3. User global notification disabled
      await settingsService.setNotifications(false);
      await service.start();

      simulatedTime = simulatedTime.add(const Duration(minutes: 25, seconds: 1));
      service.tick();
      await service.pendingDbOp;

      // notifyCount did not increase because global notifications is false
      expect(notifService.notifyCount, equals(1));

      service.dispose();
    });
  });
}
