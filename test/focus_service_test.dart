import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:balance/core/models/focus_session.dart';
import 'package:balance/core/services/focus_notification_service.dart';
import 'package:balance/core/services/focus_service.dart';
import 'package:balance/core/services/settings_service.dart';
import 'package:balance/core/services/usage_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeNotificationService extends FocusNotificationService {
  int notifyCount = 0;
  FocusSessionType? lastType;
  bool? lastCompletedNaturally;

  FakeNotificationService({super.settingsService});

  @override
  Future<bool> notifySessionCompleted({
    required FocusSessionType type,
    required bool completedNaturally,
  }) async {
    if (settingsService != null && !settingsService!.notifications) {
      return false;
    }
    notifyCount++;
    lastType = type;
    lastCompletedNaturally = completedNaturally;
    return true;
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('FocusService Unit and Integration Tests', () {
    late Directory tempDir;
    late String dbPath;
    late UsageRepository repository;
    late DateTime simulatedTime;

    DateTime clock() => simulatedTime;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('focus_test_');
      dbPath = '${tempDir.path}${Platform.pathSeparator}test_focus.db';
      repository = UsageRepository(dbName: dbPath);
      simulatedTime = DateTime(2026, 10, 11, 10, 0, 0);
    });

    tearDown(() async {
      await repository.close();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('Starting a focus session initializes running state and persists active state in SQLite', () async {
      final service = FocusService(repository: repository, clock: clock);
      await service.init();

      expect(service.status, equals(FocusStatus.idle));
      expect(service.targetDuration, equals(const Duration(minutes: 25)));

      await service.start();

      expect(service.status, equals(FocusStatus.running));
      expect(service.startTime, equals(simulatedTime));
      expect(service.expectedEndTime, equals(simulatedTime.add(const Duration(minutes: 25))));
      expect(service.remainingDuration, equals(const Duration(minutes: 25)));

      // Verify SQLite ActiveFocus record
      final active = await repository.getActiveFocusState();
      expect(active, isNotNull);
      expect(active!.status, equals(FocusStatus.running));
      expect(active.type, equals(FocusSessionType.focus));
      expect(active.targetDuration, equals(const Duration(minutes: 25)));
      expect(active.startTime, equals(simulatedTime));

      service.dispose();
    });

    test('Pausing and resuming updates remaining time and expected end time without drifting', () async {
      final service = FocusService(repository: repository, clock: clock);
      await service.init();
      await service.start();

      // Advance clock by 5 minutes
      simulatedTime = simulatedTime.add(const Duration(minutes: 5));
      await service.pause();

      expect(service.status, equals(FocusStatus.paused));
      expect(service.remainingDuration, equals(const Duration(minutes: 20)));

      // Verify SQLite state is paused
      var active = await repository.getActiveFocusState();
      expect(active?.status, equals(FocusStatus.paused));
      expect(active?.remainingDuration, equals(const Duration(minutes: 20)));

      // Advance clock by 15 minutes while paused
      simulatedTime = simulatedTime.add(const Duration(minutes: 15));

      // Resume session
      await service.resume();
      expect(service.status, equals(FocusStatus.running));
      // Expected end time must now be current time (10:20) + remaining 20 minutes = 10:40
      expect(service.expectedEndTime, equals(simulatedTime.add(const Duration(minutes: 20))));

      active = await repository.getActiveFocusState();
      expect(active?.status, equals(FocusStatus.running));

      service.dispose();
    });

    test('Stopping early records partial session in history and resets active focus', () async {
      final service = FocusService(repository: repository, clock: clock);
      await service.init();
      await service.start();

      // Advance clock by 8 minutes
      simulatedTime = simulatedTime.add(const Duration(minutes: 8));

      await service.stop();

      expect(service.status, equals(FocusStatus.idle));
      expect(service.recentSessions.length, equals(1));

      final record = service.recentSessions.first;
      expect(record.type, equals(FocusSessionType.focus));
      expect(record.plannedDuration, equals(const Duration(minutes: 25)));
      expect(record.actualDuration, equals(const Duration(minutes: 8)));
      expect(record.completedNaturally, isFalse);

      // Verify ActiveFocus is cleared in SQLite
      final active = await repository.getActiveFocusState();
      expect(active, isNull);

      service.dispose();
    });

    test('Switching session types between Focus and Break updates duration presets', () async {
      final service = FocusService(repository: repository, clock: clock);
      await service.init();

      expect(service.sessionType, equals(FocusSessionType.focus));
      expect(service.targetDuration, equals(const Duration(minutes: 25)));

      await service.setSessionType(FocusSessionType.breakSession);
      expect(service.sessionType, equals(FocusSessionType.breakSession));
      expect(service.targetDuration, equals(const Duration(minutes: 5)));

      service.setTargetDuration(const Duration(minutes: 10));
      expect(service.targetDuration, equals(const Duration(minutes: 10)));

      // Switching to focus resets to 25 min because 10 min is not a focus preset
      await service.setSessionType(FocusSessionType.focus);
      expect(service.sessionType, equals(FocusSessionType.focus));
      expect(service.targetDuration, equals(const Duration(minutes: 25)));

      service.dispose();
    });

    test('Completing a session naturally records full duration and sets status to completed', () async {
      final service = FocusService(repository: repository, clock: clock);
      await service.init();
      await service.start();

      // Fast forward past the end time
      simulatedTime = simulatedTime.add(const Duration(minutes: 25, seconds: 1));

      // Re-evaluate
      await service.init(); // Simulating refresh or tick

      expect(service.status, equals(FocusStatus.completed));
      expect(service.remainingDuration, equals(Duration.zero));
      expect(service.recentSessions.length, equals(1));

      final record = service.recentSessions.first;
      expect(record.completedNaturally, isTrue);
      expect(record.actualDuration, equals(const Duration(minutes: 25)));

      final active = await repository.getActiveFocusState();
      expect(active, isNull);

      service.dispose();
    });

    test('Persisting and restoring a running session across app restart', () async {
      final serviceA = FocusService(repository: repository, clock: clock);
      await serviceA.init();
      await serviceA.start();

      // Advance clock by 10 minutes
      simulatedTime = simulatedTime.add(const Duration(minutes: 10));

      // Simulate app closing without stop
      serviceA.dispose();

      // Create new service instance representing app relaunch at 10:10
      final serviceB = FocusService(repository: repository, clock: clock);
      await serviceB.init();

      expect(serviceB.status, equals(FocusStatus.running));
      expect(serviceB.remainingDuration, equals(const Duration(minutes: 15)));
      expect(serviceB.expectedEndTime, equals(DateTime(2026, 10, 11, 10, 25, 0)));

      serviceB.dispose();
    });

    test('Persisting and restoring a paused session across app restart', () async {
      final serviceA = FocusService(repository: repository, clock: clock);
      await serviceA.init();
      await serviceA.start();

      // Advance by 7 minutes, then pause
      simulatedTime = simulatedTime.add(const Duration(minutes: 7));
      await serviceA.pause();
      expect(serviceA.remainingDuration, equals(const Duration(minutes: 18)));

      serviceA.dispose();

      // Advance clock while app is closed
      simulatedTime = simulatedTime.add(const Duration(hours: 1));

      // Reopen app
      final serviceB = FocusService(repository: repository, clock: clock);
      await serviceB.init();

      expect(serviceB.status, equals(FocusStatus.paused));
      expect(serviceB.remainingDuration, equals(const Duration(minutes: 18)));

      serviceB.dispose();
    });

    test('Session expiring while app is closed transitions to completed and writes to history', () async {
      final serviceA = FocusService(repository: repository, clock: clock);
      await serviceA.init();
      await serviceA.start();

      // App is closed. Time passes beyond expected end time (35 minutes later).
      serviceA.dispose();
      simulatedTime = simulatedTime.add(const Duration(minutes: 35));

      // Reopen app
      final serviceB = FocusService(repository: repository, clock: clock);
      await serviceB.init();

      expect(serviceB.status, equals(FocusStatus.completed));
      expect(serviceB.remainingDuration, equals(Duration.zero));
      expect(serviceB.recentSessions.length, equals(1));
      expect(serviceB.recentSessions.first.completedNaturally, isTrue);

      // Ensure active state is cleared
      final active = await repository.getActiveFocusState();
      expect(active, isNull);

      serviceB.dispose();
    });

    test('Preventing duplicate completion and history entries', () async {
      final service = FocusService(repository: repository, clock: clock);
      await service.init();
      await service.start();

      // Session expires while closed
      service.dispose();
      simulatedTime = simulatedTime.add(const Duration(minutes: 30));

      final service2 = FocusService(repository: repository, clock: clock);
      await service2.init();
      expect(service2.recentSessions.length, equals(1));

      // Calling init again must not create duplicate entry
      await service2.init();
      expect(service2.recentSessions.length, equals(1));

      final dbSessions = await repository.getRecentFocusSessions();
      expect(dbSessions.length, equals(1));

      service2.dispose();
    });

    test('triggerTestNotification invokes notification pipeline without mutating timer or adding history', () async {
      final fakeNotifier = FakeNotificationService();
      final service = FocusService(
        repository: repository,
        notificationService: fakeNotifier,
        clock: clock,
      );
      await service.init();
      await service.start();

      expect(service.status, equals(FocusStatus.running));
      final initialRemaining = service.remainingDuration;
      final initialStartTime = service.startTime;
      final initialExpectedEnd = service.expectedEndTime;
      final initialHistoryCount = service.recentSessions.length;

      // Trigger test notification for Break
      final result = await service.triggerTestNotification(type: FocusSessionType.breakSession);
      expect(result, isTrue);
      expect(fakeNotifier.notifyCount, equals(1));
      expect(fakeNotifier.lastType, equals(FocusSessionType.breakSession));
      expect(fakeNotifier.lastCompletedNaturally, isTrue);

      // Verify active timer state is 100% UNCHANGED
      expect(service.status, equals(FocusStatus.running));
      expect(service.remainingDuration, equals(initialRemaining));
      expect(service.startTime, equals(initialStartTime));
      expect(service.expectedEndTime, equals(initialExpectedEnd));

      // Verify NO fake or new entries added to history
      expect(service.recentSessions.length, equals(initialHistoryCount));
      final dbSessions = await repository.getRecentFocusSessions();
      expect(dbSessions.length, equals(initialHistoryCount));

      // Also verify ActiveFocus in SQLite is untouched
      final active = await repository.getActiveFocusState();
      expect(active?.status, equals(FocusStatus.running));

      service.dispose();
    });

    test('triggerTestNotification respects user notification setting when disabled', () async {
      final settingsService = SettingsService(repository: repository);
      await settingsService.init();
      await settingsService.setNotifications(false); // Turned OFF

      final fakeNotifier = FakeNotificationService(settingsService: settingsService);
      final service = FocusService(
        repository: repository,
        notificationService: fakeNotifier,
        clock: clock,
      );
      await service.init();

      final result = await service.triggerTestNotification();
      expect(result, isFalse);
      expect(fakeNotifier.notifyCount, equals(0));

      service.dispose();
    });
  });
}
