import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balance/app/app.dart';
import 'package:balance/app/theme/app_colors.dart';
import 'package:balance/core/models/analytics_data.dart';
import 'package:balance/core/models/app_limit.dart';
import 'package:balance/core/models/app_session.dart';
import 'package:balance/core/models/focus_session.dart';
import 'package:balance/core/services/usage_analytics_service.dart';
import 'package:balance/core/services/usage_repository.dart';
import 'package:balance/core/services/windows_usage_tracker.dart';
import 'package:balance/features/insights/insights_screen.dart';

/// In-memory repository following the project's existing testing architecture
/// (see test/limits_dialog_widget_test.dart) to execute reliably within Flutter's
/// widget test FakeAsync event loop.
class FakeUsageRepository extends UsageRepository {
  final List<AppSession> sessions = [];
  final List<FocusSessionRecord> focusSessions = [];
  final List<AppLimit> limits = [];
  final Map<String, String> settings = {};

  FakeUsageRepository() : super(dbName: 'fake_insights_test.db');

  @override
  Future<String?> getSetting(String key) async => settings[key];

  @override
  Future<void> setSetting(String key, String value) async {
    settings[key] = value;
  }

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
  Future<List<FocusSessionRecord>> getFocusSessionsForRange(DateTime start, DateTime end) async {
    return focusSessions.where((s) {
      return s.startTime.isBefore(end) && s.endTime.isAfter(start);
    }).toList();
  }

  @override
  Future<FocusSessionRecord> insertFocusSession(FocusSessionRecord record) async {
    focusSessions.add(record);
    return record;
  }

  @override
  Future<List<AppLimit>> getAllLimits() async {
    return List.unmodifiable(limits);
  }

  @override
  Future<void> close() async {}
}

class SpyUsageAnalyticsService extends UsageAnalyticsService {
  int callCount = 0;
  final UsageAnalyticsService _inner;

  SpyUsageAnalyticsService(this._inner)
      : super(repository: _inner.repository, tracker: _inner.tracker);

  @override
  Future<PeriodAnalytics> getAnalytics({
    required AnalyticsPeriod period,
    DateTime? referenceDate,
  }) async {
    callCount++;
    return _inner.getAnalytics(period: period, referenceDate: referenceDate);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InsightsScreen Widget Tests', () {
    late FakeUsageRepository repository;
    late WindowsUsageTracker tracker;
    late UsageAnalyticsService analyticsService;

    final refDate = DateTime(2026, 10, 14, 15, 0);

    setUp(() {
      repository = FakeUsageRepository();

      tracker = WindowsUsageTracker(
        repository: repository,
        foregroundWindowProvider: () => null,
        idleTimeProvider: () => Duration.zero,
      );

      analyticsService = UsageAnalyticsService(
        repository: repository,
        tracker: tracker,
      );
    });

    tearDown(() async {
      await repository.close();
    });

    final testTheme = ThemeData.dark().copyWith(
      extensions: [AppThemeColors.dark],
    );

    Widget buildTestApp({UsageAnalyticsService? service, DateTime? referenceDate}) {
      return TrackerProvider(
        tracker: tracker,
        child: MaterialApp(
          theme: testTheme,
          home: Scaffold(
            body: InsightsScreen(
              analyticsService: service ?? analyticsService,
              referenceDate: referenceDate ?? refDate,
            ),
          ),
        ),
      );
    }

    testWidgets('Initial loading eventually displays the dashboard with real data', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Insert real recorded sessions for Telegram and VS Code on refDate (Oct 14)
      await repository.insertSession(AppSession(
        appName: 'VS Code',
        exePath: r'C:\vscode.exe',
        startTime: DateTime(2026, 10, 14, 9, 0),
        endTime: DateTime(2026, 10, 14, 11, 0), // 2h today
      ));
      await repository.insertSession(AppSession(
        appName: 'Telegram',
        exePath: r'C:\telegram.exe',
        startTime: DateTime(2026, 10, 14, 11, 30),
        endTime: DateTime(2026, 10, 14, 12, 0), // 30m today
      ));

      // Insert a completed focus session
      await repository.insertFocusSession(FocusSessionRecord(
        type: FocusSessionType.focus,
        plannedDuration: const Duration(minutes: 25),
        actualDuration: const Duration(minutes: 25),
        startTime: DateTime(2026, 10, 14, 13, 0),
        endTime: DateTime(2026, 10, 14, 13, 25),
        completedNaturally: true,
      ));

      await tester.pumpWidget(buildTestApp());
      // Initial state is loading
      expect(find.text('Analyzing recorded usage...'), findsOneWidget);

      // Settle loading future and chart animations
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 200));

      // Verify Header
      expect(find.text('Insights'), findsOneWidget);

      // Verify hardcoded placeholders are completely gone
      expect(find.text('5h 12m'), findsNothing);
      expect(find.text('Productivity'), findsNothing);
      expect(find.text('84%'), findsNothing);

      // Total usage is 2h 30m. Daily average over 7 days = 150m / 7 = 21m.
      expect(find.text('21m'), findsWidgets);
      expect(find.text('7-Day Daily Average'), findsOneWidget);

      // Most used app should be VS Code (2h)
      expect(find.text('VS Code'), findsWidgets);
      expect(find.text('Most Used Application'), findsOneWidget);

      // Focus sessions metric
      expect(find.text('Focus Sessions'), findsOneWidget);
      expect(find.text('25m'), findsWidgets);

      // Application Breakdown section
      expect(find.text('Application Breakdown'), findsOneWidget);
      expect(find.text('Telegram'), findsWidgets);
      expect(find.text('2h'), findsWidgets);
      expect(find.text('30m'), findsWidgets);
    });

    testWidgets('Empty state appears when no usage records exist', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Insights'), findsOneWidget);
      expect(find.text('0m'), findsWidgets);
      expect(find.text('None'), findsWidgets);
      expect(find.text('No application usage recorded for this period.'), findsOneWidget);
    });

    testWidgets('Changing the selected reporting period still refreshes the analytics', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 200));

      // Check default Last 7 Days
      expect(find.text('Last 7 Days'), findsOneWidget);
      expect(find.text('Your weekly digital habits and trends over the last 7 calendar days.'), findsOneWidget);

      // Tap Today
      final todayPill = find.text('Today');
      expect(todayPill, findsOneWidget);
      await tester.tap(todayPill);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Your digital usage and active breakdown for today.'), findsOneWidget);
      expect(find.text("Today's Usage"), findsOneWidget);

      // Tap Last 30 Days
      final thirtyDaysPill = find.text('Last 30 Days');
      expect(thirtyDaysPill, findsOneWidget);
      await tester.tap(thirtyDaysPill);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Your 30-day digital trends and long-term usage patterns.'), findsOneWidget);
      expect(find.text('Daily Screen Time (Last 30 Days)'), findsOneWidget);
    });

    testWidgets('Rebuilding the widget does not trigger unnecessary duplicate analytics requests', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final spyService = SpyUsageAnalyticsService(analyticsService);

      await tester.pumpWidget(buildTestApp(service: spyService));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 200));

      expect(spyService.callCount, 1);

      // Trigger a rebuild of the widget tree (e.g. parent theme change or re-render)
      await tester.pumpWidget(buildTestApp(service: spyService));
      await tester.pump(const Duration(milliseconds: 50));

      // Should still be 1 request because _isInitialized guards against duplicate loads on rebuild
      expect(spyService.callCount, 1);
    });

    testWidgets('Regression: Background refresh does NOT hide the dashboard with loading spinner', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await repository.insertSession(AppSession(
        appName: 'VS Code',
        exePath: r'C:\vscode.exe',
        startTime: DateTime(2026, 10, 14, 9, 0),
        endTime: DateTime(2026, 10, 14, 10, 0),
      ));

      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 200));

      // Dashboard is now fully rendered
      expect(find.text('7-Day Daily Average'), findsOneWidget);
      expect(find.text('VS Code'), findsWidgets);
      expect(find.text('Analyzing recorded usage...'), findsNothing);

      // Simulate live tracker notification (the event that previously caused flickering)
      tracker.notifyListeners();
      await tester.pump(); // Pump frame immediately after notification

      // The dashboard MUST remain visible and MUST NOT flicker back to loading state
      expect(find.text('7-Day Daily Average'), findsOneWidget);
      expect(find.text('VS Code'), findsWidgets);
      expect(find.text('Analyzing recorded usage...'), findsNothing);

      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('7-Day Daily Average'), findsOneWidget);
      expect(find.text('Analyzing recorded usage...'), findsNothing);
    });

    testWidgets('Regression: Repeated tracker notifications do not cause continuous loading flicker', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 200));

      // Fire 10 consecutive tracker ticks (simulating 20 seconds of live tracking)
      for (int i = 0; i < 10; i++) {
        tracker.notifyListeners();
        await tester.pump(const Duration(milliseconds: 50));
        // Verify loading state is NEVER shown while dashboard is already loaded
        expect(find.text('Analyzing recorded usage...'), findsNothing);
      }

      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Insights'), findsOneWidget);
    });

    testWidgets('Regression: Disposing screen cleans up tracker listeners without errors', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 200));

      // Navigate away / replace with empty container (triggers dispose)
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Other Screen')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Tracker notification after dispose should not throw or cause errors
      expect(() => tracker.notifyListeners(), returnsNormally);
    });

    testWidgets('First-time user with no saved preference preserves default of Last 7 Days', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Ensure no saved setting exists
      expect(repository.settings[UsageAnalyticsService.insightsPeriodSettingKey], isNull);

      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 200));

      // Default is Last 7 Days
      expect(find.text('Your weekly digital habits and trends over the last 7 calendar days.'), findsOneWidget);
      expect(find.text('Last 7 Days'), findsOneWidget);
    });

    testWidgets('Selecting Today saves preference to repository and restores on screen restart', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 200));

      // Initially Last 7 Days
      expect(find.text('Your weekly digital habits and trends over the last 7 calendar days.'), findsOneWidget);

      // Select Today
      final todayPill = find.text('Today');
      await tester.tap(todayPill);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 200));

      // Preference is saved in repository
      expect(repository.settings[UsageAnalyticsService.insightsPeriodSettingKey], equals('today'));
      expect(find.text('Your digital usage and active breakdown for today.'), findsOneWidget);

      // Simulate app restart / screen recreation with a fresh widget tree
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Temporary Blank'))),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // Reopen InsightsScreen
      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 200));

      // Insights automatically restores Today instead of resetting to Last 7 Days!
      expect(find.text('Your digital usage and active breakdown for today.'), findsOneWidget);
      expect(find.text("Today's Usage"), findsOneWidget);
      expect(find.text('Your weekly digital habits and trends over the last 7 calendar days.'), findsNothing);
    });

    testWidgets('Corrupted or invalid saved preference safely falls back to Last 7 Days default', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Seed invalid/corrupted preference in repository
      repository.settings[UsageAnalyticsService.insightsPeriodSettingKey] = 'invalid_corrupted_value';

      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 200));

      // Safely defaults to Last 7 Days without throwing
      expect(find.text('Your weekly digital habits and trends over the last 7 calendar days.'), findsOneWidget);
      expect(find.text('Last 7 Days'), findsOneWidget);
    });
  });
}
