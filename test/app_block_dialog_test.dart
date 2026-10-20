import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balance/app/app.dart';
import 'package:balance/app/theme/app_colors.dart';
import 'package:balance/core/models/app_block_event.dart';
import 'package:balance/core/models/app_limit.dart';
import 'package:balance/core/models/app_session.dart';
import 'package:balance/core/models/focus_session.dart';
import 'package:balance/core/services/app_enforcement_service.dart';
import 'package:balance/core/services/limits_service.dart';
import 'package:balance/core/services/usage_repository.dart';
import 'package:balance/core/services/windows_process_manager.dart';
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
  final List<AppLimit> limits = [];
  final List<AppSession> sessions = [];
  final Map<int, Set<String>> sentNotifications = {};

  FakeUsageRepository() : super(dbName: 'fake_block_dialog_test.db');

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
  Future<void> deleteLimit(int id) async {
    limits.removeWhere((l) => l.id == id);
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
    sessions.add(session);
    return session;
  }

  @override
  Future<List<AppSession>> getSessionsForDay(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return sessions.where((s) => s.startTime.isBefore(end) && s.endTime.isAfter(start)).toList();
  }

  @override
  Future<List<AppSession>> getSessionsForRange(DateTime start, DateTime end) async {
    return sessions.where((s) => s.startTime.isBefore(end) && s.endTime.isAfter(start)).toList();
  }

  @override
  Future<List<FocusSessionRecord>> getFocusSessionsForRange(DateTime start, DateTime end) async => [];

  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Daily Limit Reached Block Dialog Tests', () {
    late FakeUsageRepository repository;
    late FakeProcessManager processManager;
    late AppEnforcementService enforcementService;
    late LimitsService limitsService;
    late DateTime testTime;

    DateTime getClock() => testTime;

    setUp(() {
      testTime = DateTime(2026, 10, 14, 14, 0); // Wednesday, Oct 14, 2026, 2:00 PM
      repository = FakeUsageRepository();
      processManager = FakeProcessManager(currentPid: 9999);
      enforcementService = AppEnforcementService(
        processManager: processManager,
        gracePeriod: Duration.zero,
        clock: getClock,
      );

      limitsService = LimitsService(
        repository: repository,
        enforcementService: enforcementService,
        clock: getClock,
      );
    });

    Widget buildTestApp({Widget? child}) {
      return LimitsProvider(
        limitsService: limitsService,
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: [AppThemeColors.dark],
          ),
          home: AppBlockDialogManager(
            limitsService: limitsService,
            child: child ?? const Scaffold(body: Center(child: Text('Main Content'))),
          ),
        ),
      );
    }

    testWidgets('1. A limit-reaching event requests and displays the correct dialog', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Create an enforced limit of 1 hour for Telegram
      await limitsService.createLimit(
        appName: 'Telegram',
        duration: const Duration(hours: 1),
        isEnforced: true,
      );

      // Record 1 hour and 5 minutes of usage for Telegram
      await repository.insertSession(AppSession(
        appName: 'Telegram',
        exePath: r'C:\telegram.exe',
        startTime: DateTime(2026, 10, 14, 10, 0),
        endTime: DateTime(2026, 10, 14, 11, 5),
      ));

      // Running process for Telegram exists
      processManager.processes.add(MockProcess(
        pid: 101,
        appName: 'Telegram',
        exeName: 'telegram.exe',
        exePath: r'C:\telegram.exe',
      ));

      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      // Evaluate usage: reaches limit and triggers enforcement
      await limitsService.evaluateUsage();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify the dialog is displayed on screen
      expect(find.byType(AppBlockDialog), findsOneWidget);
      expect(find.text('Daily limit reached'), findsOneWidget);
      expect(
        find.text("You've reached your daily limit for Telegram. You can't access this app again until your daily limit resets."),
        findsOneWidget,
      );

      // Verify the process was closed
      expect(processManager.gracefulCloseAttempts, contains(101));
      expect(enforcementService.isAppRestricted('Telegram'), isTrue);
    });

    testWidgets('2. The correct application name and usage information are displayed', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      // Dispatch a block event directly
      final midnight = DateTime(2026, 10, 15, 0, 0);
      enforcementService.dispatchBlockEvent(AppBlockEvent(
        appName: 'VS Code',
        exePath: r'C:\vscode.exe',
        limitDuration: const Duration(hours: 2),
        usedDuration: const Duration(hours: 2, minutes: 15),
        resetTime: midnight,
        timestamp: testTime,
      ));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Verify exact fields
      expect(find.byType(AppBlockDialog), findsOneWidget);
      expect(find.text('Daily limit reached'), findsOneWidget);
      expect(
        find.text("You've reached your daily limit for VS Code. You can't access this app again until your daily limit resets."),
        findsOneWidget,
      );
      expect(find.text('2h'), findsOneWidget); // Daily limit
      expect(find.text('2h 15m'), findsOneWidget); // Used today
      expect(find.text('Resets at midnight (12:00 AM)'), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);
    });

    testWidgets('3. Repeated polling events do not create duplicate simultaneous dialogs', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      final midnight = DateTime(2026, 10, 15, 0, 0);
      final event = AppBlockEvent(
        appName: 'Telegram',
        exePath: r'C:\telegram.exe',
        limitDuration: const Duration(hours: 1),
        usedDuration: const Duration(hours: 1, minutes: 2),
        resetTime: midnight,
        timestamp: testTime,
      );

      // Fire 5 identical events in rapid succession (simulating 2-second tracker polling ticks)
      for (int i = 0; i < 5; i++) {
        enforcementService.dispatchBlockEvent(event);
        await tester.pump(const Duration(milliseconds: 20));
      }

      // Exactly ONE dialog must be present in the widget tree
      expect(find.byType(AppBlockDialog), findsOneWidget);
      expect(find.text('Daily limit reached'), findsOneWidget);
    });

    testWidgets('4. Dismissing the popup does not disable enforcement', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final limit = await limitsService.createLimit(
        appName: 'Telegram',
        duration: const Duration(hours: 1),
        isEnforced: true,
      );

      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      // Enforce limit
      await enforcementService.enforceLimit(limit);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(AppBlockDialog), findsOneWidget);
      expect(enforcementService.isAppRestricted('Telegram'), isTrue);

      // User dismisses dialog by tapping "Got it"
      final gotItButton = find.byKey(const Key('block_dialog_got_it_button'));
      expect(gotItButton, findsOneWidget);
      await tester.tap(gotItButton);
      await tester.pumpAndSettle();

      // Dialog is gone
      expect(find.byType(AppBlockDialog), findsNothing);

      // CRITICAL: Enforcement MUST remain active
      expect(enforcementService.isAppRestricted('Telegram'), isTrue);
    });

    testWidgets('5. A subsequent blocked launch attempt can show the dialog again', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final limit = await limitsService.createLimit(
        appName: 'Telegram',
        duration: const Duration(hours: 1),
        isEnforced: true,
      );

      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      // 1. Initial block
      await enforcementService.enforceLimit(limit);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(AppBlockDialog), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.byKey(const Key('block_dialog_got_it_button')));
      await tester.pumpAndSettle();
      expect(find.byType(AppBlockDialog), findsNothing);

      // Advance time by 10 seconds (beyond 2-second cooldown)
      testTime = testTime.add(const Duration(seconds: 10));

      // Add a newly launched process for Telegram
      processManager.processes.add(MockProcess(
        pid: 202,
        appName: 'Telegram',
        exeName: 'telegram.exe',
        exePath: r'C:\telegram.exe',
      ));

      // User attempts to reopen the app -> tracker detects foreground app
      await enforcementService.onForegroundAppDetected(
        appName: 'Telegram',
        exePath: r'C:\telegram.exe',
        limits: limitsService.limits,
        todayUsage: const Duration(hours: 1, minutes: 5),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The new process must be closed
      expect(processManager.gracefulCloseAttempts, contains(202));

      // The dialog MUST appear again to explain why access was blocked!
      expect(find.byType(AppBlockDialog), findsOneWidget);
      expect(find.text('Daily limit reached'), findsOneWidget);
    });

    testWidgets('6. Applications without enforced limits are not blocked or shown a popup', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Limit with isEnforced = false
      await limitsService.createLimit(
        appName: 'Spotify',
        duration: const Duration(hours: 1),
        isEnforced: false,
      );

      processManager.processes.add(MockProcess(
        pid: 301,
        appName: 'Spotify',
        exeName: 'spotify.exe',
        exePath: r'C:\spotify.exe',
      ));

      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      // Foreground detection for Spotify
      await enforcementService.onForegroundAppDetected(
        appName: 'Spotify',
        exePath: r'C:\spotify.exe',
        limits: limitsService.limits,
        todayUsage: const Duration(hours: 2), // Exceeded, but NOT enforced
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // No close attempt and NO dialog
      expect(processManager.gracefulCloseAttempts, isEmpty);
      expect(enforcementService.isAppRestricted('Spotify'), isFalse);
      expect(find.byType(AppBlockDialog), findsNothing);
    });

    testWidgets('7. Disabling or deleting a limit stops enforcement appropriately', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final limit = await limitsService.createLimit(
        appName: 'Telegram',
        duration: const Duration(hours: 1),
        isEnforced: true,
      );

      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      // Enforce it initially
      await enforcementService.enforceLimit(limit);
      expect(enforcementService.isAppRestricted('Telegram'), isTrue);

      // Disable the limit
      await limitsService.toggleLimit(limit.id!, false);

      // Restriction should be cleared immediately
      expect(enforcementService.isAppRestricted('Telegram'), isFalse);

      // Delete the limit
      await limitsService.deleteLimit(limit.id!);
      expect(enforcementService.isAppRestricted('Telegram'), isFalse);
    });

    testWidgets('8. A daily reset allows the application to launch again', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final limit = await limitsService.createLimit(
        appName: 'Telegram',
        duration: const Duration(hours: 1),
        isEnforced: true,
      );

      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      // Enforce on Day 1 (Oct 14)
      await enforcementService.enforceLimit(limit);
      expect(enforcementService.isAppRestricted('Telegram'), isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Dismiss Day 1 dialog
      await tester.tap(find.byKey(const Key('block_dialog_got_it_button')));
      await tester.pumpAndSettle();
      expect(find.byType(AppBlockDialog), findsNothing);

      // Advance clock to Day 2 (Oct 15, 08:00 AM)
      testTime = DateTime(2026, 10, 15, 8, 0);

      // Querying restriction triggers daily reset check
      expect(enforcementService.isAppRestricted('Telegram'), isFalse);

      // Process launched on Day 2 with 0 usage today should not be closed
      processManager.processes.add(MockProcess(
        pid: 401,
        appName: 'Telegram',
        exeName: 'telegram.exe',
        exePath: r'C:\telegram.exe',
      ));

      await enforcementService.onForegroundAppDetected(
        appName: 'Telegram',
        exePath: r'C:\telegram.exe',
        limits: limitsService.limits,
        todayUsage: Duration.zero,
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Process 401 remains alive and NO dialog appears
      expect(processManager.gracefulCloseAttempts, isNot(contains(401)));
      expect(find.byType(AppBlockDialog), findsNothing);
    });

    testWidgets("9. An unrelated application's launch does not trigger the dialog", (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      // Telegram is enforced and restricted
      final limit = await limitsService.createLimit(
        appName: 'Telegram',
        duration: const Duration(hours: 1),
        isEnforced: true,
      );
      await enforcementService.enforceLimit(limit);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Dismiss the initial Telegram dialog
      await tester.tap(find.byKey(const Key('block_dialog_got_it_button')));
      await tester.pumpAndSettle();
      expect(find.byType(AppBlockDialog), findsNothing);

      // User launches unrelated application: Calculator
      processManager.processes.add(MockProcess(
        pid: 501,
        appName: 'Calculator',
        exeName: 'calculator.exe',
        exePath: r'C:\calculator.exe',
      ));

      await enforcementService.onForegroundAppDetected(
        appName: 'Calculator',
        exePath: r'C:\calculator.exe',
        limits: limitsService.limits,
        todayUsage: const Duration(minutes: 5),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Calculator is untouched and no dialog is shown
      expect(processManager.gracefulCloseAttempts, isNot(contains(501)));
      expect(find.byType(AppBlockDialog), findsNothing);
    });

    testWidgets('10. Widget disposal and event-listener cleanup do not cause errors', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      // Unmount the manager
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Unmounted')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // Emitting block events after disposal should not throw or cause unhandled async exceptions
      expect(
        () => enforcementService.dispatchBlockEvent(AppBlockEvent(
          appName: 'Telegram',
          limitDuration: const Duration(hours: 1),
          usedDuration: const Duration(hours: 1),
          resetTime: DateTime(2026, 10, 15),
          timestamp: testTime,
        )),
        returnsNormally,
      );

      // EnforcementService disposal cleans up the StreamController
      expect(() => enforcementService.dispose(), returnsNormally);
      expect(() => limitsService.dispose(), returnsNormally);
    });
  });
}
