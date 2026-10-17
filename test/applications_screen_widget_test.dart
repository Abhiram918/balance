import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:balance/app/app.dart';
import 'package:balance/app/theme/app_colors.dart';
import 'package:balance/core/models/app_limit.dart';
import 'package:balance/core/models/app_session.dart';
import 'package:balance/core/services/application_analytics_service.dart';
import 'package:balance/core/services/focus_service.dart';
import 'package:balance/core/services/limits_service.dart';
import 'package:balance/core/services/settings_service.dart';
import 'package:balance/core/services/usage_repository.dart';
import 'package:balance/core/services/windows_usage_tracker.dart';
import 'package:balance/features/applications/applications_screen.dart';

class FakeApplicationsRepository extends UsageRepository {
  final List<AppSession> sessions = [];
  final List<AppLimit> limits = [];
  int _nextLimitId = 1;

  FakeApplicationsRepository() : super(dbName: 'fake_applications_test.db');

  @override
  Future<AppSession> insertSession(AppSession session) async {
    sessions.add(session);
    return session;
  }

  @override
  Future<List<AppSession>> getSessionsForRange(DateTime start, DateTime end) async {
    return sessions.where((s) {
      return s.startTime.isBefore(end) && s.endTime.isAfter(start);
    }).toList();
  }

  @override
  Future<List<AppSession>> getSessionsForDay(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day + 1);
    return getSessionsForRange(startOfDay, endOfDay);
  }

  @override
  Future<List<AppLimit>> getAllLimits() async {
    return List.unmodifiable(limits);
  }

  @override
  Future<AppLimit?> getLimitByAppName(String appName) async {
    final lower = appName.toLowerCase().trim();
    for (final l in limits) {
      if (l.appName.toLowerCase().trim() == lower) {
        return l;
      }
    }
    return null;
  }

  @override
  Future<AppLimit> insertLimit(AppLimit limit) async {
    final created = limit.copyWith(id: _nextLimitId++);
    limits.add(created);
    return created;
  }

  @override
  Future<void> updateLimit(AppLimit limit) async {
    final idx = limits.indexWhere((l) => l.id == limit.id);
    if (idx != -1) {
      limits[idx] = limit;
    }
  }

  @override
  Future<void> deleteLimit(int id) async {
    limits.removeWhere((l) => l.id == id);
  }

  @override
  Future<List<String>> getDistinctTrackedApps() async {
    return sessions.map((s) => s.appName).toSet().toList();
  }

  @override
  Future<List<Map<String, String>>> getDistinctTrackedAppsWithPaths() async {
    return sessions.map((s) => {'appName': s.appName, 'exePath': s.exePath}).toSet().toList();
  }

  @override
  Future<bool> hasLimitNotificationBeenSent(int limitId, String notificationType, String dateKey) async => false;

  @override
  Future<void> recordLimitNotificationSent(int limitId, String notificationType, String dateKey, DateTime timestamp) async {}

  @override
  Future<String?> getSetting(String key) async => null;

  @override
  Future<void> setSetting(String key, String value) async {}

  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApplicationsScreen & DetailScreen Widget Tests', () {
    late FakeApplicationsRepository repository;
    late WindowsUsageTracker tracker;
    late SettingsService settingsService;
    late FocusService focusService;
    late LimitsService limitsService;
    late ApplicationAnalyticsService analyticsService;

    // Fixed test date: Wednesday, October 14, 2026, 15:30
    final fixedNow = DateTime(2026, 10, 14, 15, 30);

    setUp(() async {
      repository = FakeApplicationsRepository();

      // Seed sessions for today (Oct 14) and previous days
      // VS Code today: 10:00 - 11:30 (90 mins)
      repository.sessions.add(AppSession(
        appName: 'VS Code',
        exePath: r'C:\vscode.exe',
        startTime: DateTime(2026, 10, 14, 10, 0),
        endTime: DateTime(2026, 10, 14, 11, 30),
      ));

      // Chrome today: 13:00 - 14:00 (60 mins)
      repository.sessions.add(AppSession(
        appName: 'Chrome',
        exePath: r'C:\chrome.exe',
        startTime: DateTime(2026, 10, 14, 13, 0),
        endTime: DateTime(2026, 10, 14, 14, 0),
      ));

      // Spotify yesterday (Oct 13): 14:00 - 15:00 (60 mins)
      repository.sessions.add(AppSession(
        appName: 'Spotify',
        exePath: r'C:\spotify.exe',
        startTime: DateTime(2026, 10, 13, 14, 0),
        endTime: DateTime(2026, 10, 13, 15, 0),
      ));

      // Configure a limit for Chrome: 45 minutes (so 60m used = limit reached)
      repository.limits.add(AppLimit(
        id: 1,
        appName: 'Chrome',
        exePath: r'C:\chrome.exe',
        limitDuration: const Duration(minutes: 45),
        isEnabled: true,
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1),
      ));

      // Configure a limit for VS Code: 3 hours (so 90m used = 50% progress, not reached)
      repository.limits.add(AppLimit(
        id: 2,
        appName: 'VS Code',
        exePath: r'C:\vscode.exe',
        limitDuration: const Duration(hours: 3),
        isEnabled: true,
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1),
      ));

      tracker = WindowsUsageTracker(
        repository: repository,
        idleTimeProvider: () => Duration.zero,
        foregroundWindowProvider: () => null,
      );

      settingsService = SettingsService(repository: repository);
      focusService = FocusService(repository: repository);

      limitsService = LimitsService(
        repository: repository,
        tracker: tracker,
        clock: () => fixedNow,
      );
      await limitsService.init();

      analyticsService = ApplicationAnalyticsService(
        repository: repository,
        tracker: tracker,
        limitsService: limitsService,
      );
    });

    tearDown(() {
      tracker.dispose();
      focusService.dispose();
      limitsService.dispose();
      settingsService.dispose();
    });

    final testTheme = ThemeData.dark().copyWith(
      extensions: [AppThemeColors.dark],
    );

    Widget buildTestApp({Widget? child}) {
      return SettingsProvider(
        settingsService: settingsService,
        child: TrackerProvider(
          tracker: tracker,
          child: FocusProvider(
            focusService: focusService,
            child: LimitsProvider(
              limitsService: limitsService,
              child: MaterialApp(
                theme: testTheme,
                home: child ??
                    ApplicationsScreen(
                      analyticsService: analyticsService,
                      referenceDate: fixedNow,
                    ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('1. Main Applications page renders header, summaries, chart, and application rows', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // 1. Header
      expect(find.text('Applications'), findsOneWidget);
      expect(find.textContaining('Monitor application usage'), findsOneWidget);

      // 2. Date presets
      expect(find.text('Today'), findsWidgets);
      expect(find.text('Past 7 Days'), findsOneWidget);
      expect(find.text('Past 30 Days'), findsOneWidget);

      // 3. Summaries
      expect(find.text('Active Daily Limits'), findsOneWidget);
      expect(find.text('Daily Limits Reached'), findsOneWidget);
      // Both Chrome and VS Code have limits -> 2 active limits
      expect(find.text('2'), findsWidgets);
      // Chrome (60m) reached 45m limit -> 1 limit reached
      expect(find.text('1'), findsWidgets);

      // 4. Usage bar chart
      expect(find.textContaining('Aggregate Application Usage'), findsOneWidget);

      // 5. Application rows for Today (VS Code and Chrome)
      expect(find.text('VS Code'), findsOneWidget);
      expect(find.text('Chrome'), findsOneWidget);
      // Spotify was used yesterday, so not in Today view
      expect(find.text('Spotify'), findsNothing);
    });

    testWidgets('2. Date preset switching to Past 7 Days includes multi-day usage and Spotify', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Click "Past 7 Days"
      final past7Btn = find.text('Past 7 Days');
      expect(past7Btn, findsOneWidget);
      await tester.tap(past7Btn);
      await tester.pumpAndSettle();

      // Now Spotify (yesterday) should be visible!
      expect(find.text('Spotify'), findsOneWidget);
      expect(find.text('VS Code'), findsOneWidget);
      expect(find.text('Chrome'), findsOneWidget);
    });

    testWidgets('3. Search by name filters the application list in real time', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Type "chr" in search
      final searchField = find.widgetWithText(TextField, 'Search applications by name...');
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'chr');
      await tester.pumpAndSettle();

      // Chrome matches, VS Code does not
      expect(find.text('Chrome'), findsOneWidget);
      expect(find.text('VS Code'), findsNothing);

      // Type nonexistent query
      await tester.enterText(searchField, 'xyz_not_exist');
      await tester.pumpAndSettle();

      expect(find.text('No applications match "xyz_not_exist".'), findsOneWidget);

      // Clear search
      final clearBtn = find.byIcon(LucideIcons.x);
      expect(clearBtn, findsOneWidget);
      await tester.tap(clearBtn);
      await tester.pumpAndSettle();

      expect(find.text('VS Code'), findsOneWidget);
      expect(find.text('Chrome'), findsOneWidget);
    });

    testWidgets('4. Filter buttons (Limited, Limit Reached) filter the application list', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Filter: "Limit Reached"
      final limitReachedPill = find.byKey(const ValueKey('filter_pill_limitReached'));
      expect(limitReachedPill, findsOneWidget);
      await tester.tap(limitReachedPill);
      await tester.pumpAndSettle();

      // Chrome reached its limit (60m used >= 45m limit)
      expect(find.text('Chrome'), findsOneWidget);
      // VS Code has NOT reached its limit (90m used < 3h limit)
      expect(find.text('VS Code'), findsNothing);

      // Filter back to "All"
      final allPill = find.byKey(const ValueKey('filter_pill_all'));
      await tester.tap(allPill);
      await tester.pumpAndSettle();

      expect(find.text('VS Code'), findsOneWidget);
      expect(find.text('Chrome'), findsOneWidget);
    });

    testWidgets('5. Selecting an application drills down into ApplicationDetailScreen', (tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Tap on Chrome row
      final chromeRow = find.text('Chrome');
      expect(chromeRow, findsOneWidget);
      await tester.ensureVisible(chromeRow);
      await tester.tap(chromeRow);
      await tester.pumpAndSettle();

      // Detail Screen should be displayed
      expect(find.text('Back to Applications'), findsOneWidget);
      expect(find.text('Chrome Usage (Today, Oct 14, 2026)'), findsOneWidget);
      expect(find.text('Total Usage (Today, Oct 14, 2026)'), findsOneWidget);
      expect(find.text('Daily Limit Configuration'), findsOneWidget);
      expect(find.text('Activity & Session History'), findsOneWidget);

      // Back button returns to main Applications list
      final backBtn = find.text('Back to Applications');
      await tester.tap(backBtn);
      await tester.pumpAndSettle();

      expect(find.text('Applications'), findsOneWidget);
      expect(find.text('VS Code'), findsOneWidget);
      expect(find.text('Chrome'), findsOneWidget);
    });

    testWidgets('6. Window resizing test: desktop width and compact width render without overflow', (tester) async {
      // Wide desktop
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Compact width
      tester.view.physicalSize = const Size(800, 700);
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
