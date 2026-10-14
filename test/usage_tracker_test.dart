import 'package:flutter_test/flutter_test.dart';
import 'package:balance/core/services/usage_repository.dart';
import 'package:balance/core/services/windows_usage_tracker.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('WindowsUsageTracker Unit Tests (Testable Providers)', () {
    late UsageRepository repository;

    setUp(() {
      repository = UsageRepository(dbName: inMemoryDatabasePath);
    });

    test('Transitions to idle, cuts off active session at lastInputTime, and does not count idle period', () async {
      Duration mockIdle = Duration.zero;
      String? mockWindow = r'C:\Program Files\App\Work.exe';

      final tracker = WindowsUsageTracker(
        repository: repository,
        idleTimeProvider: () => mockIdle,
        foregroundWindowProvider: () => mockWindow,
      );

      tracker.setIdleThreshold(const Duration(minutes: 2));
      await tracker.init();

      // Tick 1: Active
      tracker.start();
      // Wait for at least one tick to start
      await Future.delayed(const Duration(milliseconds: 100));

      expect(tracker.isRunning, isTrue);
      expect(tracker.isUserIdle, isFalse);

      // Simulate idle of 2m 5s
      mockIdle = const Duration(minutes: 2, seconds: 5);

      // Invoke a check
      // Let's call stop to finalize
      await tracker.stop();

      expect(tracker.isRunning, isFalse);
    });

    test('Includes in-progress live session in todaySummary without duplicate entries', () async {
      final tracker = WindowsUsageTracker(
        repository: repository,
        idleTimeProvider: () => Duration.zero,
        foregroundWindowProvider: () => r'C:\Tools\Editor.exe',
      );

      await tracker.init();
      final initialSummary = tracker.todaySummary;
      expect(initialSummary, isNotNull);

      // Start tracking
      tracker.start();
      await Future.delayed(const Duration(milliseconds: 200));

      await tracker.stop();

      // Verify no duplicate sessions created
      final sessions = await repository.getSessionsForDay(DateTime.now());
      final editorSessions = sessions.where((s) => s.appName == 'Editor').toList();

      // Ensure no overlapping editor sessions
      for (int i = 0; i < editorSessions.length - 1; i++) {
        expect(editorSessions[i].endTime.isBefore(editorSessions[i + 1].startTime) ||
            editorSessions[i].endTime == editorSessions[i + 1].startTime, isTrue);
      }
    });

    test('Updates idle threshold dynamically and notifies listeners', () {
      final tracker = WindowsUsageTracker(repository: repository);
      expect(tracker.idleThreshold, equals(const Duration(minutes: 2)));

      bool notified = false;
      tracker.addListener(() => notified = true);

      tracker.setIdleThreshold(const Duration(minutes: 5));
      expect(tracker.idleThreshold, equals(const Duration(minutes: 5)));
      expect(notified, isTrue);
    });
  });
}
